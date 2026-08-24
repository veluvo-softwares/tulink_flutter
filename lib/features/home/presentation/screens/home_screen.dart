import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:tulink_flutter/core/services/car_toast_service.dart';
import 'package:tulink_flutter/core/services/push_notification_service.dart';
import 'package:tulink_flutter/core/theme/tulink_colors.dart';
import 'package:tulink_flutter/core/widgets/location_access_sheet.dart';
import 'package:tulink_flutter/features/analytics/presentation/providers/analytics_provider.dart';
import 'package:tulink_flutter/features/auth/presentation/providers/auth_provider.dart';
import 'package:tulink_flutter/features/convoy/presentation/providers/convoy_provider.dart';
import 'package:tulink_flutter/features/invites/domain/entities/user_search_result.dart';
import 'package:tulink_flutter/features/invites/domain/entities/journey_invitation.dart';
import 'package:tulink_flutter/features/invites/presentation/providers/invite_provider.dart';
import 'package:tulink_flutter/features/journeys/domain/entities/journey.dart';
import 'package:tulink_flutter/features/journeys/presentation/providers/journey_provider.dart';
import 'package:tulink_flutter/features/journeys/presentation/utils/journey_lifecycle.dart';
import 'package:tulink_flutter/features/journeys/presentation/widgets/completed_journey_overlay.dart';
import 'package:tulink_flutter/features/home/presentation/widgets/live_journey_back_boundary.dart';
import 'package:tulink_flutter/features/home/presentation/widgets/pending_journey_staging.dart';
import 'package:tulink_flutter/features/journeys/presentation/utils/journey_navigation.dart';
import 'package:tulink_flutter/features/maps/domain/entities/place_search_result.dart';
import 'package:tulink_flutter/features/home/presentation/state/map_experience_state.dart';
import 'package:tulink_flutter/features/home/presentation/state/live_artifact_coordinator.dart';
import 'package:tulink_flutter/features/home/presentation/state/roster_refresh_coalescer.dart';
import 'package:tulink_flutter/features/home/presentation/state/staged_invite_dispatcher.dart';
import 'package:tulink_flutter/features/maps/presentation/controllers/live_artifact_cleaner.dart';
import 'package:tulink_flutter/features/maps/presentation/controllers/live_map_artifacts.dart';
import 'package:tulink_flutter/features/maps/presentation/controllers/persistent_map_controller.dart';
import 'package:tulink_flutter/features/maps/presentation/live_journey_experience.dart';
import 'package:tulink_flutter/features/maps/presentation/providers/map_provider.dart';
import 'package:tulink_flutter/features/maps/presentation/widgets/persistent_tulink_map.dart';
import 'package:tulink_flutter/features/profile/presentation/screens/profile_screen.dart';

/// Tulink's map-first home. Creating a journey is intentionally reduced to
/// destination -> people -> start, while the existing providers continue to
/// own networking, location, invitations and convoy coordination.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.selectedTab = 0,
    this.onTabSelected,
    this.experience,
  });

  static const routeName = '/dashboard';

  /// 0 = Map, 1 = Journeys, 2 = Invites. The map itself remains mounted while
  /// these overlays change, keeping camera and journey-draft state intact.
  final int selectedTab;
  final ValueChanged<int>? onTabSelected;

  /// The single authoritative map experience, published for the navigation
  /// shell to read.
  ///
  /// Home is the only place that can derive this, because starting, ending and
  /// the completion summary are Home-local transient state. The shell must not
  /// recompute it from providers alone — it would be missing exactly those
  /// inputs and would disagree with Home during the transitions that matter.
  final ValueNotifier<MapExperienceState>? experience;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  /// Owns the application's only map surface. Every layer — draft preview,
  /// live convoy, completed summary — draws through this rather than mounting
  /// a map of its own.
  final PersistentMapController _mapController = PersistentMapController();

  CircleAnnotationManager? _destinationAnnotations;

  /// Journey whose completion summary is showing over the map. Held here (not
  /// in a provider) because it is presentation state for this shell only, and
  /// clearing it is how the user dismisses the summary.
  Journey? _completedJourney;

  /// True while the live layer holds the map's geometry, so the shell stops
  /// drawing its draft preview and leaves the camera alone.
  bool _liveLayerOwnsMap = false;
  StreamSubscription<RemoteMessage>? _pushSub;
  StreamSubscription<RemoteMessage>? _pushTapSub;
  Timer? _invitePollingTimer;
  PlaceSearchResult? _destination;
  List<_SelectedCompanion> _companions = const [];
  bool _isStarting = false;
  bool _isEnteringLiveJourney = false;

  /// Journey the shell has already promoted to live, so a duplicate
  /// `journey-started` event is idempotent.
  String? _liveJourneyId;

  /// Bounded retries for a transient failure refreshing a started journey.
  static const int _journeyStartedMaxRetries = 3;
  int _lastJourneyInviteTick = 0;

  /// Last observed ConvoyProvider.participantAcceptedTick, so a burst of
  /// acceptances collapses into a single roster refresh.
  int _lastParticipantAcceptedTick = 0;

  /// True while the shared surface is being cleared of a finished journey's
  /// drawings. Mirrors [LiveArtifactCoordinator.isCleaning] for the build.
  bool _isCleaningArtifacts = false;
  bool _wasBackgrounded = false;

  /// True when the user pressed Back during a live journey. The journey keeps
  /// running; only its chrome is collapsed to a restore pill.
  bool _isLiveChromeCollapsed = false;

  /// True while a staging action (start / cancel / leave) is in flight.
  bool _isStagingBusy = false;

  /// True while the live layer is tearing a journey down.
  bool _isEndingJourney = false;

  /// Place id of a *journey's* destination currently drawn on the map, as
  /// opposed to a user-composed draft. Kept so draft teardown does not erase a
  /// real journey's destination.
  String? _journeyDestinationPlaceId;

  /// Monotonic token for destination draws, so a superseded draw cannot paint
  /// or move the camera after a newer destination has been chosen.
  int _destinationDrawSeq = 0;

  /// The user/session the map's geometry belongs to. A change (logout, account
  /// switch) invalidates every route held or in flight — a route is scoped to
  /// the session that requested it.
  String? _routeSessionUserId;
  bool _sawUserSession = false;

  /// Journey already staged onto the map, so adoption runs once per journey.
  String? _stagedJourneyId;

  /// The journey whose `journey-started` transition exhausted its retries.
  ///
  /// Held so the staging chrome can offer a real Reconnect instead of a toast
  /// that claims "Retrying…" while nothing is scheduled. The event itself
  /// stays unconsumed, so the retry has something to act on.
  String? _journeyStartFailedId;

  /// Selection generation the in-flight `journey-started` transition was
  /// issued under. Re-read immediately before the event is consumed, so
  /// switching to another journey mid-transition abandons it.
  int? _journeyStartSelectionGeneration;

  /// Live drawings currently on the shared surface, and the id of the journey
  /// they belong to. Held here because they outlive [LiveJourneyExperience]:
  /// the surface is the shell's, so removing them is the shell's job.
  LiveMapArtifacts? _liveArtifacts;
  String? _liveArtifactJourneyId;

  late final LiveArtifactCleaner _artifactCleaner = LiveArtifactCleaner(
    artifacts: () => _liveArtifacts,
    currentGeneration: () => _mapController.generation,
    currentJourneyId: () => _liveArtifactJourneyId,
  );

  /// Owns the completion → cleaning → exploring transition, so Done is atomic
  /// and journey B cannot draw into the middle of journey A's removals.
  late final LiveArtifactCoordinator _artifactCoordinator =
      LiveArtifactCoordinator(cleaner: _artifactCleaner);

  /// Trailing-edge coalescing for `participant-accepted` bursts.
  late final RosterRefreshCoalescer _rosterRefresh = RosterRefreshCoalescer(
    refresh: (journeyId) async {
      final refreshed = await context.read<JourneyProvider>().fetchJourneyById(
        journeyId,
      );
      if (!mounted) return null;
      if (refreshed != null && refreshed.id == journeyId) setState(() {});
      return refreshed?.id;
    },
  );

  /// Journey-scoped claim on the invite flow, taken before the picker opens.
  final StagedInviteDispatcher _inviteDispatcher = StagedInviteDispatcher();
  String? _previewedJourneyId;

  /// The live Mapbox handle, or null while no surface is attached.
  MapboxMap? get _map => _mapController.map;

  static const _previewSourceId = 'home-preview-route-source';
  static const _previewShadowId = 'home-preview-route-shadow';
  static const _previewLineId = 'home-preview-route-line';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _mapController.addListener(_onMapSurfaceChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialiseHome());
  }

  Future<void> _initialiseHome() async {
    await maybeShowLocationPriming(context);
    if (!mounted) return;

    final push = context.read<PushNotificationService>();
    await push.init();
    if (!mounted) return;
    _pushSub = push.messages.listen(_onPushMessage);
    _pushTapSub = push.notificationTaps.listen(_onNotificationTap);
    final initialTap = push.takeInitialNotificationTap();
    if (initialTap != null) _onNotificationTap(initialTap);

    unawaited(context.read<ConvoyProvider>().startUserChannel());
    await _refreshData();
    _invitePollingTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) {
        context.read<InviteProvider>().refreshInvitationsSilently();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _mapController.removeListener(_onMapSurfaceChanged);
    _mapController.dispose();
    _pushSub?.cancel();
    _pushTapSub?.cancel();
    _invitePollingTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _wasBackgrounded = true;
      return;
    }
    if (state != AppLifecycleState.resumed || !mounted) return;

    context.read<InviteProvider>().refreshInvitationsSilently(force: true);

    if (!_wasBackgrounded) return;
    _wasBackgrounded = false;
    // Some devices resume with a black native surface while Flutter keeps
    // rendering. The shell owns the surface, so it is the one that rebuilds it;
    // every layer restores its own geometry off the resulting generation bump.
    _destinationAnnotations = null;
    // `recreate()` bumps the generation, which is what re-arms the surface's
    // one-restoration-per-generation claim.
    _mapController.recreate();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final convoy = context.watch<ConvoyProvider>();

    // Session identity is checked before anything else reads route state, so a
    // logout or account switch cannot leave the previous user's route drawn or
    // let their in-flight response land on the new session's map.
    final userId = context.watch<AuthProvider>().user?.id;
    if (!_sawUserSession || userId != _routeSessionUserId) {
      _sawUserSession = true;
      _routeSessionUserId = userId;
      // Deferred: dropping a route notifies listeners, which is not allowed
      // while this frame is still building.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.read<MapProvider>().onUserChanged(userId);
      });
    }

    if (convoy.journeyInviteTick != _lastJourneyInviteTick) {
      _lastJourneyInviteTick = convoy.journeyInviteTick;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.read<InviteProvider>().refreshInvitationsSilently(
            force: true,
          );
        }
      });
    }

    // A journey can be made current from outside this shell (JourneyNavigation
    // from history, the create screen, a deep link). Adopt it onto the map
    // instead of requiring every caller to know how staging works.
    final current = context.watch<JourneyProvider>().currentJourney;
    if (current == null) {
      _stagedJourneyId = null;
    } else if (current.id != _stagedJourneyId &&
        (current.status == JourneyStatus.PENDING ||
            current.status == JourneyStatus.ACTIVE ||
            current.status == JourneyStatus.PAUSED)) {
      final journey = current;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_adoptCurrentJourney(journey));
      });
    }

    // A participant accepting must refresh the staged journey's roster here —
    // this shell is the authoritative staging surface now, and the behaviour
    // previously lived only on the retired preview screen.
    if (convoy.participantAcceptedTick != _lastParticipantAcceptedTick) {
      _lastParticipantAcceptedTick = convoy.participantAcceptedTick;
      final stagedId = _stagedJourneyId;
      // The event is journey-scoped (the data source parses `journeyId` from
      // the payload). An acceptance for a journey we are not staging must not
      // trigger a refresh of the one we are.
      final acceptedFor = convoy.lastParticipantAcceptedJourneyId;
      if (stagedId != null &&
          (acceptedFor == null || acceptedFor == stagedId)) {
        final tick = convoy.participantAcceptedTick;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          unawaited(
            _rosterRefresh.record(
              tick: tick,
              journeyId: stagedId,
              isStillStaged: () => mounted && _stagedJourneyId == stagedId,
            ),
          );
        });
      }
    }

    final startedJourneyId = convoy.pendingJourneyStartedId;
    if (startedJourneyId != null &&
        !_isEnteringLiveJourney &&
        // A transition that already exhausted its retries is not retried
        // automatically. It waits for the explicit Reconnect, which is the
        // only honest way to present it — an unbounded automatic re-entry
        // driven by provider notifications is neither visible nor bounded.
        _journeyStartFailedId != startedJourneyId) {
      _isEnteringLiveJourney = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_handleJourneyStarted(startedJourneyId));
      });
    }
  }

  /// Promote a member to the live convoy after a `journey-started` event.
  ///
  /// The event is delivered exactly once, so it is **not** consumed until the
  /// transition is known to be safe. Consuming first — as this used to — meant
  /// a single transient GET failure lost the event permanently and left the
  /// member waiting forever with no way to recover.
  Future<void> _handleJourneyStarted(
    String journeyId, {
    int attempt = 0,
  }) async {
    if (!mounted) {
      _isEnteringLiveJourney = false;
      return;
    }

    // Already live on this journey: a duplicate event is a no-op.
    if (_liveJourneyId == journeyId) {
      context.read<ConvoyProvider>().consumeJourneyStartedEvent();
      _isEnteringLiveJourney = false;
      return;
    }

    final journeys = context.read<JourneyProvider>();
    // Capture the selection this transition belongs to *before* the await.
    // Every other identity check below is meaningless if the user moved to a
    // different journey while the fetch was in flight.
    final selectionAtIssue = journeys.selectionGeneration;
    _journeyStartSelectionGeneration = selectionAtIssue;

    final journey = await journeys.fetchJourneyById(journeyId);
    if (!mounted) {
      _isEnteringLiveJourney = false;
      return;
    }

    // Revalidate the whole identity immediately before consuming the event:
    // the returned entity, its status, the journey still selected, the room
    // this device actually owns, and the transition generation. Validating the
    // entity alone let a switch to B activate on A's late response.
    final convoy = context.read<ConvoyProvider>();
    final isUsable =
        journey != null &&
        journey.id == journeyId &&
        journey.status == JourneyStatus.ACTIVE;
    final stillOurs =
        journeys.selectionGeneration == selectionAtIssue &&
        _journeyStartSelectionGeneration == selectionAtIssue &&
        (journeys.currentJourney?.id == journeyId) &&
        (convoy.currentJourneyId == null ||
            convoy.currentJourneyId == journeyId) &&
        convoy.pendingJourneyStartedId == journeyId;

    if (!stillOurs) {
      // Superseded. The event is left unconsumed for whoever owns it now, and
      // nothing about this transition is applied.
      _isEnteringLiveJourney = false;
      return;
    }

    if (!isUsable) {
      // Retain the event and retry with a bounded backoff. The event stays
      // unconsumed so the explicit Reconnect can still pick it up.
      if (attempt < _journeyStartedMaxRetries) {
        final delay = Duration(milliseconds: 400 * (1 << attempt));
        await Future<void>.delayed(delay);
        if (!mounted || journeys.selectionGeneration != selectionAtIssue) {
          _isEnteringLiveJourney = false;
          return;
        }
        return _handleJourneyStarted(journeyId, attempt: attempt + 1);
      }
      // Retries exhausted. Publish a truthful, actionable state — the staging
      // chrome renders it with a real Reconnect control — instead of a toast
      // promising a retry that is not scheduled.
      setState(() => _journeyStartFailedId = journeyId);
      context.showWarningToast(
        'The journey started but could not be loaded. '
        'Tap Reconnect to try again.',
      );
      _isEnteringLiveJourney = false;
      return;
    }

    // Safe to consume: right journey, really active, still ours.
    _journeyStartFailedId = null;
    convoy.consumeJourneyStartedEvent();
    _liveJourneyId = journeyId;

    // Deliberately NOT gated on location. The leader has started; this member
    // must reach the live convoy and keep receiving journey events regardless
    // of their own permission state. ConvoyProvider joins the room first and
    // reports a location failure separately, which the live layer surfaces
    // with a retry — see Phase 1's resilience invariant.
    unawaited(context.read<ConvoyProvider>().startCoordination(journeyId));
    _enterLiveJourney();
    _isEnteringLiveJourney = false;
  }

  /// Bring the live convoy into view on the map the user is already looking at.
  ///
  /// Replaces the old `pushNamed('/mapview')` handoff. There is no second map
  /// to push to any more, so "entering" a journey is a state change plus a tab
  /// switch — the camera, route and destination stay exactly as they were.
  void _enterLiveJourney() {
    if (!mounted) return;
    // The live layer is about to draw onto the shared surface; remember whose
    // drawings they are so a later cleanup can be matched to them.
    final journeyId = context.read<JourneyProvider>().currentJourney?.id;
    if (journeyId != null) {
      _liveArtifactJourneyId = journeyId;
      _artifactCoordinator.adopt(journeyId);
    }
    setState(() => _completedJourney = null);
    if (widget.selectedTab != 0) widget.onTabSelected?.call(0);
  }

  /// Remove the live convoy's drawings from the shared map.
  ///
  /// Called on explicit dismissal — never on a mere state transition, which is
  /// what keeps the driven route visible behind the completion summary.
  Future<bool> _clearLiveArtifacts() async {
    final cleaned = await _artifactCoordinator.clear(
      onStateChanged: () {
        if (!mounted) return;
        setState(() => _isCleaningArtifacts = _artifactCoordinator.isCleaning);
      },
    );
    if (cleaned) _liveArtifactJourneyId = _artifactCoordinator.journeyId;
    return cleaned;
  }

  /// The live layer finished — the journey is genuinely over (ended or left).
  ///
  /// Only reached after [JourneyProvider] has stopped the journey, so clearing
  /// the draft here is safe. Back does **not** route here; see
  /// [_collapseLiveChrome].
  void _onLiveJourneyExit() {
    if (!mounted) return;
    final journeyId = context.read<JourneyProvider>().currentJourney?.id;
    setState(() {
      _completedJourney = null;
      _isLiveChromeCollapsed = false;
      // The teardown is over. Leaving this set would pin the experience on
      // `ending`, which outranks every other state.
      _isEndingJourney = false;
    });
    if (journeyId != null) _clearDraftIfJourneyFinished(journeyId);
    unawaited(
      _clearLiveArtifacts().then((_) {
        if (mounted) _clearDraft();
      }),
    );
  }

  /// A journey ended but its summary could not be loaded.
  ///
  /// Release it from selection anyway: leaving a finished journey as current
  /// keeps the live layer mounted, which strands the user on the teardown
  /// overlay with no way out.
  void _releaseEndedJourney(String journeyId) {
    if (!mounted) return;
    context.read<JourneyProvider>().releaseFinishedJourney(journeyId);
    if (_stagedJourneyId == journeyId) _stagedJourneyId = null;
    unawaited(_clearLiveArtifacts());
  }

  /// Back from the live convoy.
  ///
  /// Back must never silently abandon a running journey, and it must not be a
  /// no-op either: it collapses the live chrome so the user can see and pan the
  /// map, leaving the journey running and reachable. Ending or leaving stays an
  /// explicit, confirmed action on the progress card.
  void _collapseLiveChrome() {
    if (!mounted || _isLiveChromeCollapsed) return;
    setState(() => _isLiveChromeCollapsed = true);
  }

  void _restoreLiveChrome() {
    if (!mounted || !_isLiveChromeCollapsed) return;
    setState(() => _isLiveChromeCollapsed = false);
  }

  /// The journey completed and has a summary to show over the same map.
  void _onLiveJourneyCompleted(Journey journey) {
    if (!mounted) return;
    setState(() {
      _completedJourney = journey;
      // Teardown finished — clear it so the summary can outrank `ending`.
      _isEndingJourney = false;
      _isLiveChromeCollapsed = false;
    });
    // Stop treating it as the current journey, or the map re-derives a live
    // convoy for a trip that has already finished the moment the summary is
    // dismissed. The summary itself is driven by [_completedJourney].
    context.read<JourneyProvider>().releaseFinishedJourney(journey.id);
    _stagedJourneyId = null;
    unawaited(context.read<AnalyticsProvider>().loadJourneyHistory());
  }

  /// Dismiss the completion summary and return the map to exploring.
  ///
  /// The transition is atomic from the user's point of view: the summary stays
  /// up in an explicit cleaning state until the surface is genuinely clear.
  /// Dismissing first and cleaning in the background let journey B start
  /// drawing while A's removals were still running on the same surface, and
  /// showed an "exploring" map that still had A's route on it.
  Future<void> _dismissCompletedJourney() async {
    if (!mounted || _isCleaningArtifacts) return;

    // Awaited, not fired and forgotten. The summary stays up in an explicit
    // cleaning state for the whole removal, so exploring is only ever reported
    // for a surface that really is clear.
    final cleaned = await _clearLiveArtifacts();
    if (!mounted) return;

    if (!cleaned) {
      // Do not pretend the map is clean. The summary stays, so Done can be
      // pressed again against a surface that is still dirty.
      context.showErrorToast(
        'Could not clear the finished journey from the map. Try again.',
      );
      return;
    }

    setState(() => _completedJourney = null);
    _clearDraft();
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedTab == widget.selectedTab) return;

    if (widget.selectedTab == 0) {
      if (_destination == null) {
        _previewedJourneyId = null;
        unawaited(_clearPreviewRoute());
        unawaited(_clearDestinationAnnotations());
        unawaited(_recenter());
      } else {
        unawaited(_showDestinationOnMap(_destination!));
      }
    } else if (widget.selectedTab == 2) {
      _previewedJourneyId = null;
      unawaited(_clearPreviewRoute());
      unawaited(_clearDestinationAnnotations());
    }
  }

  Future<void> _refreshData() async {
    await Future.wait([
      context.read<AnalyticsProvider>().loadJourneyHistory(),
      context.read<JourneyProvider>().fetchActiveJourneys(),
      context.read<InviteProvider>().fetchInvitations(),
    ]);
  }

  void _onPushMessage(RemoteMessage message) {
    if (!mounted) return;
    context.read<InviteProvider>().refreshInvitationsSilently(force: true);
    final text = message.notification?.title ?? message.notification?.body;
    if (text != null) context.showSuccessToast(text);
  }

  void _onNotificationTap(RemoteMessage message) {
    if (!mounted) return;
    if (message.data['type']?.toString() == 'JOURNEY_INVITE') {
      final selectTab = widget.onTabSelected;
      if (selectTab != null) {
        selectTab(2);
      } else {
        Navigator.of(context).pushNamed('/invitations');
      }
      return;
    }
    final type = message.data['type']?.toString();
    if (type == 'JOURNEY_REMINDER' ||
        type == 'JOURNEY_STARTING_NOW' ||
        type == 'JOURNEY_MISSED_START') {
      final journeyId = message.data['journeyId']?.toString();
      if (journeyId != null && journeyId.isNotEmpty) {
        unawaited(openJourneyOnMap(journeyId));
      }
    }
  }

  /// Bring [journeyId] onto the persistent map in whatever state it is in.
  ///
  /// This is the single entry point for "show me this journey" from outside the
  /// shell — notifications, reminders, and the legacy `/mapview` deep link all
  /// land here rather than pushing a journey page. An unknown or stale id fails
  /// visibly instead of leaving the user on a blank screen.
  Future<void> openJourneyOnMap(String journeyId) async {
    final journeys = context.read<JourneyProvider>();
    // Use the returned entity: on failure the provider keeps the previous
    // selection, so reading currentJourney here could open a different journey.
    final journey = await journeys.fetchJourneyById(journeyId);
    if (!mounted) return;

    if (journey == null || journey.id != journeyId) {
      context.showErrorToast(
        journeys.error ?? 'That journey is no longer available',
      );
      if (widget.selectedTab != 0) widget.onTabSelected?.call(0);
      return;
    }

    switch (journey.status) {
      case JourneyStatus.ACTIVE:
      case JourneyStatus.PAUSED:
        // Join/observe — not gated on location. A paused convoy is still one
        // the user belongs to, so it opens on the live map too.
        unawaited(context.read<ConvoyProvider>().startCoordination(journey.id));
        _enterLiveJourney();
        await _showJourneyDestinationOnMap(journey);
      case JourneyStatus.PENDING:
        await _enterPendingJourney(journey);
      case JourneyStatus.COMPLETED:
        if (widget.selectedTab != 0) widget.onTabSelected?.call(0);
        setState(() => _completedJourney = journey);
      case JourneyStatus.CANCELLED:
        if (widget.selectedTab != 0) widget.onTabSelected?.call(0);
        context.showInfoToast('That journey was cancelled');
    }
  }

  /// Restore the shell's own layers whenever a new surface attaches.
  void _onMapSurfaceChanged() {
    if (!mounted) return;
    // Publish the surface generation before anything reads it. Route work is
    // stamped with the generation it was issued under, so a rebuild has to
    // invalidate the outstanding requests before the new surface is drawn on —
    // otherwise a response resolved against the old style repaints the new one.
    context.read<MapProvider>().onSurfaceGenerationChanged(
      _mapController.generation,
    );
    // The surface itself owns "restore exactly once per generation", so a
    // second notification for the same surface cannot trigger a second full
    // redraw of every layer.
    if (!_mapController.claimRestoration()) return;
    final map = _mapController.map!;
    _destinationAnnotations = null;
    unawaited(
      _restoreShellLayers(map, _mapController.generation).catchError((
        Object _,
      ) {
        // A surface can be torn down mid-restore; the next attach redraws.
      }),
    );
  }

  Future<void> _restoreShellLayers(MapboxMap map, int generation) async {
    await map.scaleBar.updateSettings(ScaleBarSettings(enabled: false));
    final annotations = await map.annotations.createCircleAnnotationManager();
    if (!mounted || generation != _mapController.generation) return;
    _destinationAnnotations = annotations;
    // Rebind the artifact port to the new surface; the old one referenced a
    // style that no longer exists.
    _liveArtifacts = MapboxLiveMapArtifacts(map, annotations: null);
    try {
      await map.location.updateSettings(
        LocationComponentSettings(enabled: true, pulsingEnabled: true),
      );
    } catch (_) {
      // Location access is already explained and requested by the home flow.
    }
    if (!mounted || generation != _mapController.generation) return;

    // While a journey is running the live layer owns the camera and the route.
    // Recentring or drawing a draft preview here would fight it.
    if (_liveLayerOwnsMap) return;

    await _recenter();
    final draftDestination = _destination;
    if (draftDestination != null && mounted) {
      await _showDestinationOnMap(draftDestination);
    }
  }

  Future<void> _recenter() async {
    final map = _map;
    if (map == null) return;
    geo.Position? position;
    try {
      position = await geo.Geolocator.getLastKnownPosition();
      position ??= await geo.Geolocator.getCurrentPosition(
        locationSettings: const geo.LocationSettings(
          accuracy: geo.LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 5));
    } catch (_) {
      return;
    }
    await map.flyTo(
      CameraOptions(
        center: Point(
          coordinates: Position(position.longitude, position.latitude),
        ),
        zoom: 11.5,
      ),
      MapAnimationOptions(duration: 700),
    );
  }

  /// Draw [place] as the map's destination and preview a route to it.
  ///
  /// [asDraft] distinguishes a destination the user is composing from one that
  /// belongs to a real journey. A journey's destination must not be cleared by
  /// draft teardown, and the route it fetches is what the live layer later
  /// reuses as its cached route — which is what makes the geometry survive
  /// pending → starting → live without a refetch or a visible reset.
  Future<void> _showDestinationOnMap(
    PlaceSearchResult place, {
    bool asDraft = true,
  }) async {
    final manager = _destinationAnnotations;
    final map = _map;
    if (manager == null || map == null) return;
    if (!asDraft) _journeyDestinationPlaceId = place.placeId;

    // Capture what this draw is for. A slow route for place A must not draw
    // itself, or move the camera, after the user has chosen place B — or onto
    // a map surface that has since been rebuilt.
    final drawToken = ++_destinationDrawSeq;
    final generation = _mapController.generation;
    bool isCurrentDraw() =>
        mounted &&
        _destinationDrawSeq == drawToken &&
        _mapController.generation == generation;
    await manager.deleteAll();
    if (!isCurrentDraw()) return;
    await manager.create(
      CircleAnnotationOptions(
        geometry: Point(coordinates: Position(place.lng, place.lat)),
        circleColor: const Color(0xFFF35D32).toARGB32(),
        circleRadius: 10,
        circleStrokeColor: Colors.white.toARGB32(),
        circleStrokeWidth: 4,
      ),
    );

    final origin = await _resolveOrigin();
    final userId = context.read<AuthProvider>().user?.id ?? 'map-preview';
    final route = await context.read<MapProvider>().fetchRoute(
      userId: userId,
      journeyId: 'draft-${place.placeId}',
      surfaceGeneration: generation,
      // A denied or cold GPS fix should not prevent a route preview. Nairobi
      // is already Tulink's initial map centre and is replaced by live origin
      // whenever location is available.
      originLat: origin?.latitude ?? -1.2921,
      originLng: origin?.longitude ?? 36.8219,
      destLat: place.lat,
      destLng: place.lng,
    );
    if (!isCurrentDraw()) return;
    if (route != null && route.coordinates.length > 1) {
      await _drawPreviewRoute(route.coordinates);
      if (!isCurrentDraw()) return;
      await _fitPreviewCamera(route.coordinates);
      return;
    }

    if (!isCurrentDraw()) return;
    await map.flyTo(
      CameraOptions(
        center: Point(coordinates: Position(place.lng, place.lat)),
        zoom: 12.5,
      ),
      MapAnimationOptions(duration: 800),
    );
  }

  Future<geo.Position?> _resolveOrigin() async {
    try {
      final lastKnown = await geo.Geolocator.getLastKnownPosition();
      if (lastKnown != null) return lastKnown;
      return await geo.Geolocator.getCurrentPosition(
        locationSettings: const geo.LocationSettings(
          accuracy: geo.LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 5));
    } catch (_) {
      return null;
    }
  }

  Future<void> _drawPreviewRoute(List<List<double>> coordinates) async {
    final map = _map;
    if (map == null || coordinates.length < 2) return;
    await _clearPreviewRoute();
    try {
      final geoJson = jsonEncode({
        'type': 'Feature',
        'properties': <String, dynamic>{},
        'geometry': {'type': 'LineString', 'coordinates': coordinates},
      });
      await map.style.addSource(
        GeoJsonSource(id: _previewSourceId, data: geoJson),
      );
      await map.style.addLayer(
        LineLayer(
          id: _previewShadowId,
          sourceId: _previewSourceId,
          lineCap: LineCap.ROUND,
          lineJoin: LineJoin.ROUND,
          lineWidth: 8,
          lineColor: const Color(0xFFFFFFFF).toARGB32(),
          lineOpacity: .9,
        ),
      );
      await map.style.addLayer(
        LineLayer(
          id: _previewLineId,
          sourceId: _previewSourceId,
          lineCap: LineCap.ROUND,
          lineJoin: LineJoin.ROUND,
          lineWidth: 5,
          lineColor: const Color(0xFF12848D).toARGB32(),
          lineOpacity: 1,
        ),
      );
    } catch (error) {
      debugPrint('Could not draw home route preview: $error');
    }
  }

  Future<void> _clearPreviewRoute() async {
    final map = _map;
    if (map == null) return;
    try {
      await map.style.removeStyleLayer(_previewLineId);
    } catch (_) {}
    try {
      await map.style.removeStyleLayer(_previewShadowId);
    } catch (_) {}
    try {
      await map.style.removeStyleSource(_previewSourceId);
    } catch (_) {}
  }

  Future<void> _clearDestinationAnnotations() async {
    try {
      await _destinationAnnotations?.deleteAll();
    } catch (_) {}
  }

  Future<void> _fitPreviewCamera(List<List<double>> coordinates) async {
    final map = _map;
    if (map == null || coordinates.isEmpty) return;
    var minLng = coordinates.first[0];
    var maxLng = coordinates.first[0];
    var minLat = coordinates.first[1];
    var maxLat = coordinates.first[1];
    for (final coordinate in coordinates.skip(1)) {
      minLng = coordinate[0] < minLng ? coordinate[0] : minLng;
      maxLng = coordinate[0] > maxLng ? coordinate[0] : maxLng;
      minLat = coordinate[1] < minLat ? coordinate[1] : minLat;
      maxLat = coordinate[1] > maxLat ? coordinate[1] : maxLat;
    }
    try {
      final camera = await map.cameraForCoordinateBounds(
        CoordinateBounds(
          southwest: Point(coordinates: Position(minLng, minLat)),
          northeast: Point(coordinates: Position(maxLng, maxLat)),
          infiniteBounds: false,
        ),
        // Keep the destination below the search bar and the origin above the
        // journey sheet instead of technically fitting them behind overlays.
        MbxEdgeInsets(top: 180, left: 44, bottom: 300, right: 44),
        null,
        null,
        null,
        null,
      );
      await map.flyTo(camera, MapAnimationOptions(duration: 800));
    } catch (error) {
      debugPrint('Could not fit home route preview: $error');
    }
  }

  Future<void> _previewJourney(Journey journey) async {
    _previewedJourneyId = journey.id;
    final place = PlaceSearchResult(
      placeId: 'preview-${journey.id}',
      displayName: journey.destinationLabel,
      address: journey.destinationAddress,
      lat: journey.destination.latitude,
      lng: journey.destination.longitude,
      types: const ['journey'],
    );
    await _showDestinationOnMap(place);
  }

  /// Open the profile, honouring a request to land on the Journeys overlay.
  ///
  /// Journey history lives in the map-focused Journeys tab, so the profile's
  /// travel links pop back here and select that tab rather than pushing a
  /// competing full-page history screen.
  Future<void> _openProfile() async {
    final result = await Navigator.of(
      context,
    ).pushNamed<Object?>(ProfileScreen.routeName);
    if (!mounted) return;
    if (result == ProfileScreen.showJourneysResult) {
      widget.onTabSelected?.call(1);
    }
  }

  Future<void> _chooseDestination() async {
    final place = await showModalBottomSheet<PlaceSearchResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _DestinationSearchSheet(),
    );
    if (place == null || !mounted) return;
    widget.onTabSelected?.call(0);
    setState(() {
      _destination = place;
      _companions = const [];
    });
    await _showDestinationOnMap(place);
  }

  Future<void> _repeatJourney(Journey journey) async {
    final userId = context.read<AuthProvider>().user?.id;
    final people = (journey.participants ?? const <Participant>[])
        .where((person) => person.userId != userId)
        .where((person) => person.status.toUpperCase() != 'LEFT')
        .map(_SelectedCompanion.fromParticipant)
        .fold(<String, _SelectedCompanion>{}, (byId, person) {
          byId[person.id] = person;
          return byId;
        })
        .values
        .toList();

    final title = journey.destinationLabel;
    final place = PlaceSearchResult(
      placeId: 'journey-${journey.id}',
      displayName: title,
      address: journey.destinationAddress,
      lat: journey.destination.latitude,
      lng: journey.destination.longitude,
      types: const ['journey'],
    );
    widget.onTabSelected?.call(0);
    setState(() {
      _destination = place;
      _companions = people;
    });
    await _showDestinationOnMap(place);
  }

  /// Invite people to an existing pending journey.
  ///
  /// Distinct from [_chooseCompanions], which only composes a *draft*: that
  /// list is consumed by journey creation, so reusing it here silently did
  /// nothing — the journey already existed and nothing ever sent the invites.
  Future<void> _invitePeopleToStagedJourney(Journey journey) async {
    if (_isStagingBusy) return;

    final journeys = context.read<JourneyProvider>();
    final selectionAtIssue = journeys.selectionGeneration;
    final userAtIssue = context.read<AuthProvider>().user?.id;

    // Exclude the leader and anyone already on the journey, so the picker
    // cannot produce a duplicate invitation.
    final existing = <String>{
      journey.leaderId,
      ...(journey.participants ?? const <Participant>[])
          .where((p) => p.status.toUpperCase() != 'LEFT')
          .map((p) => p.userId),
    };

    final invites = context.read<InviteProvider>();

    // The dispatcher claims the flow for this journey *before* the picker
    // opens, which is the whole fix: the previous guard was checked before the
    // picker and claimed only after it returned, so a second tap inside that
    // window opened a second picker and both continuations sent.
    final result = await _inviteDispatcher.dispatch<_SelectedCompanion>(
      journeyId: journey.id,
      isStillCurrent: () =>
          _inviteContextIsCurrent(journey, selectionAtIssue, userAtIssue),
      nameOf: (person) => person.name,
      pickTargets: () async {
        final selected = await showModalBottomSheet<List<_SelectedCompanion>>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => _CompanionPickerSheet(
            initial: const [],
            excludedUserIds: existing,
          ),
        );
        if (selected == null || !mounted) return null;
        // Dedupe defensively; the picker is keyed by id but callers can change.
        return <String, _SelectedCompanion>{
          for (final person in selected)
            if (!existing.contains(person.id)) person.id: person,
        }.values.toList();
      },
      sendInvite: (person) async {
        if (mounted && !_isStagingBusy) {
          setState(() => _isStagingBusy = true);
        }
        return invites.sendInvite(
          journeyId: journey.id,
          invitedUserId: person.id,
        );
      },
    );

    if (mounted && _isStagingBusy) setState(() => _isStagingBusy = false);
    if (!mounted) return;

    // Partial success is reported whatever happened to the rest.
    if (result.sent > 0) {
      context.showSuccessToast(
        '${result.sent} invitation${result.sent == 1 ? '' : 's'} sent',
      );
    }
    if (result.failed.isNotEmpty) {
      context.showErrorToast('Could not invite ${result.failed.join(', ')}');
    }
    if (!result.hasAnything) return;

    if (!_inviteContextIsCurrent(journey, selectionAtIssue, userAtIssue)) {
      return;
    }

    // Refresh this exact journey's roster, rejecting a stale response.
    final refreshed = await journeys.fetchJourneyById(journey.id);
    if (!mounted || refreshed == null || refreshed.id != journey.id) return;
    if (!_inviteContextIsCurrent(journey, selectionAtIssue, userAtIssue)) {
      return;
    }
    setState(() {});
  }

  /// True while the invite flow still belongs to the journey and session it was
  /// started for.
  bool _inviteContextIsCurrent(
    Journey journey,
    int selectionAtIssue,
    String? userAtIssue,
  ) {
    if (!mounted) return false;
    final journeys = context.read<JourneyProvider>();
    return journeys.selectionGeneration == selectionAtIssue &&
        journeys.currentJourney?.id == journey.id &&
        context.read<AuthProvider>().user?.id == userAtIssue;
  }

  Future<void> _chooseCompanions() async {
    final selected = await showModalBottomSheet<List<_SelectedCompanion>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CompanionPickerSheet(initial: _companions),
    );
    if (selected != null && mounted) {
      setState(() => _companions = selected);
    }
  }

  Future<void> _startJourney() async {
    final destination = _destination;
    if (destination == null || _isStarting) return;

    // Claim the in-flight slot synchronously. The guard used to be set only
    // after `ensureLocationReady` awaited, so a second tap landing inside that
    // gap passed the check too and created a duplicate journey.
    setState(() => _isStarting = true);
    try {
      await _startJourneyInternal(destination);
    } finally {
      if (mounted) setState(() => _isStarting = false);
    }
  }

  Future<void> _startJourneyInternal(PlaceSearchResult destination) async {
    // Leader activation gate — deliberately retained. Creating and starting a
    // journey flips the convoy ACTIVE for everyone invited, and they navigate
    // off this leader's positions. A leader who cannot publish must not
    // activate one. Joining or observing an existing journey has no such gate.
    if (!await ensureLocationReady(context) || !mounted) return;

    final journeys = context.read<JourneyProvider>();
    final created = await journeys.createJourney(
      name: 'Trip to ${_destinationTitle(destination.displayName)}',
      latitude: destination.lat,
      longitude: destination.lng,
      // The place name is what the user recognises; the formatted address is
      // frequently only city-level and is kept as secondary information.
      destinationName: destination.displayName,
      destinationAddress: destination.address,
      lagThresholdMeters: 500,
    );
    if (!mounted) return;
    if (!created || journeys.currentJourney == null) {
      context.showErrorToast(journeys.error ?? 'Could not create this journey');
      return;
    }

    final journeyId = journeys.currentJourney!.id;
    final invites = context.read<InviteProvider>();
    invites.resetInviteSession();
    var failedInvites = 0;
    for (final person in _companions) {
      final sent = await invites.sendInvite(
        journeyId: journeyId,
        invitedUserId: person.id,
      );
      if (!sent) failedInvites++;
    }

    final started = await journeys.startJourney(journeyId);
    if (!mounted) return;
    if (!started) {
      context.showErrorToast(journeys.error ?? 'Could not start this journey');
      return;
    }

    // Coordination failures surface on ConvoyProvider's own state, which the
    // map screen's status bar renders — so this unawaited call is observable.
    unawaited(context.read<ConvoyProvider>().startCoordination(journeyId));
    if (failedInvites > 0) {
      context.showInfoToast(
        '$failedInvites invitation${failedInvites == 1 ? '' : 's'} '
        'could not be sent',
      );
    }
    // The previewed route is already drawn on this map; the live layer adopts
    // it rather than pushing a second map that refetches the same geometry.
    // The draft is retired when the journey finishes, in [_onLiveJourneyExit].
    _enterLiveJourney();
  }

  /// Clear the composed draft once [journeyId] is no longer live.
  ///
  /// A journey that ended is removed from [JourneyProvider.activeJourneys] and
  /// clears `currentJourney`, so its absence from both is the signal that the
  /// draft should be retired.
  void _clearDraftIfJourneyFinished(String journeyId) {
    final journeys = context.read<JourneyProvider>();
    final finished = isJourneyFinished(
      journeyId: journeyId,
      currentJourney: journeys.currentJourney,
      activeJourneys: journeys.activeJourneys,
    );
    if (finished) _clearDraft();
  }

  Future<void> _continueJourney(Journey journey) async {
    if (journey.status == JourneyStatus.PENDING) {
      // Staging happens over the map, not on a separate page.
      await _enterPendingJourney(journey);
      return;
    }
    // Resuming an already-active journey is a *join/observe* action, not a
    // journey activation. It must not be gated on location: the user has to be
    // able to see the convoy and reconnect even with permission denied.
    // ConvoyProvider records the location failure independently.
    context.read<JourneyProvider>().setCurrentJourney(journey);
    unawaited(context.read<ConvoyProvider>().startCoordination(journey.id));
    _enterLiveJourney();
  }

  /// Show a not-yet-started journey as staging chrome over the persistent map.
  Future<void> _enterPendingJourney(Journey journey) async {
    context.read<JourneyProvider>().setCurrentJourney(journey);
    await _adoptCurrentJourney(journey);
  }

  /// Bring [journey] onto the map: select the Map tab, join its room, and draw
  /// its destination.
  ///
  /// This is the one place journey staging is set up. Callers only have to make
  /// the journey current — including callers outside this shell, which reach it
  /// through the reactive check in [didChangeDependencies]. That keeps
  /// `JourneyProvider.currentJourney` the single source of truth instead of
  ///each caller re-implementing setup.
  Future<void> _adoptCurrentJourney(Journey journey) async {
    if (_stagedJourneyId == journey.id) return;

    // A finished journey's drawings are still being removed from this surface.
    // Drawing B now would race those removals and lose. Wait for the cleanup
    // to settle, then re-check that B is still what we are adopting.
    if (_artifactCoordinator.isCleaning || _artifactCleaner.inFlight != null) {
      await _artifactCoordinator.settle();
      if (!mounted || _stagedJourneyId == journey.id) return;
    }
    // Geometry staging is tracked separately from room membership. They used to
    // share this one flag, so a failed room join permanently blocked any retry:
    // the journey was "staged", so adoption never ran again.
    _stagedJourneyId = journey.id;

    if (widget.selectedTab != 0) widget.onTabSelected?.call(0);
    setState(() {
      _completedJourney = null;
      _isLiveChromeCollapsed = false;
    });

    // Draw the destination regardless of membership — the waiting overlay is
    // still useful and honest when the room is unreachable.
    await _showJourneyDestinationOnMap(journey);
    if (!mounted) return;

    // Join listener-only so membership exists even when the staging chrome is
    // dismissed. [PendingJourneyStaging] joins too — the call is idempotent —
    // and it is the one that owns the *visible* retry/failure state.
    unawaited(_joinPendingRoomFor(journey.id));
  }

  /// Join the convoy room for a staged (not yet live) journey, listener-only.
  ///
  /// Deliberately does **not** request GPS or begin publishing: nothing is
  /// moving yet, and a member who has denied location must still receive
  /// `journey-started`.
  ///
  /// Bounded retry, the visible "reconnecting" state, and the explicit
  /// Reconnect control all live in [PendingJourneyStaging], so there is exactly
  /// one state machine and the three can never disagree.
  Future<bool> _joinPendingRoomFor(String journeyId) {
    return context.read<ConvoyProvider>().joinJourneyRoom(journeyId);
  }

  /// Re-attempt a `journey-started` transition that exhausted its retries.
  ///
  /// Clearing the failed marker is what re-arms the reactive dispatch in
  /// [didChangeDependencies]; the event itself was never consumed.
  void _retryJourneyStarted() {
    if (!mounted || _journeyStartFailedId == null) return;
    setState(() => _journeyStartFailedId = null);
  }

  /// Re-read the staged journey so an acceptance shows up in the roster.
  ///
  /// Scoped to [journeyId] and validated against the response, so a refresh
  /// triggered while switching journeys cannot install the wrong roster.

  /// Draw a journey's destination on the shared map without creating a draft.
  Future<void> _showJourneyDestinationOnMap(Journey journey) async {
    await _showDestinationOnMap(
      PlaceSearchResult(
        placeId: 'journey-${journey.id}',
        displayName: journey.destinationLabel,
        address: journey.destinationAddress,
        lat: journey.destination.latitude,
        lng: journey.destination.longitude,
        types: const ['journey'],
      ),
      asDraft: false,
    );
  }

  Future<void> _joinJourneyByCode() async {
    final joinedJourney = await showModalBottomSheet<Journey>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const JoinJourneyCodeSheet(),
    );
    if (!mounted || joinedJourney == null) return;

    if (joinedJourney.status == JourneyStatus.ACTIVE) {
      // Joining an already-active convoy — not gated on location.
      context.read<JourneyProvider>().setCurrentJourney(joinedJourney);
      unawaited(
        context.read<ConvoyProvider>().startCoordination(joinedJourney.id),
      );
      _enterLiveJourney();
      await _showJourneyDestinationOnMap(joinedJourney);
      return;
    }

    await _enterPendingJourney(joinedJourney);
  }

  Future<void> _acceptInvitation(JourneyInvitation invitation) async {
    final accepted = await context.read<InviteProvider>().acceptInvitation(
      invitation.journeyId,
    );
    if (!mounted) return;

    if (!accepted) {
      context.showErrorToast(
        context.read<InviteProvider>().acceptError ??
            'Failed to accept invitation',
      );
      return;
    }

    context.showSuccessToast('You joined "${invitation.journeyName}"!');
    // Identity comes from the returned entity, never from currentJourney: a
    // failed fetch leaves a previously selected journey in place, and staging
    // *that* while coordinating this invitation is how the wrong journey ends
    // up on the map.
    final journey = await context.read<JourneyProvider>().fetchJourneyById(
      invitation.journeyId,
    );
    if (!mounted) return;
    if (journey == null || journey.id != invitation.journeyId) {
      context.showErrorToast('Joined, but the journey could not be loaded');
      return;
    }

    if (journey.status == JourneyStatus.ACTIVE) {
      // Accepting an invite to a convoy that is already moving. Joining is not
      // an activation, so location is not a precondition — the member must be
      // able to observe and reconnect even with permission denied.
      unawaited(
        context.read<ConvoyProvider>().startCoordination(invitation.journeyId),
      );
      _enterLiveJourney();
      await _showJourneyDestinationOnMap(journey);
      return;
    }

    // Still pending: stage over the map and wait for the leader there.
    await _enterPendingJourney(journey);
  }

  Future<void> _declineInvitation(JourneyInvitation invitation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Decline invitation?'),
        content: Text(
          'You will decline the invitation to "${invitation.journeyName}".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep invitation'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Decline'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final declined = await context.read<InviteProvider>().declineInvitation(
      invitation.journeyId,
    );
    if (!mounted) return;
    if (declined) {
      context.showSuccessToast('Invitation declined');
    } else {
      context.showErrorToast(
        context.read<InviteProvider>().declineError ??
            'Failed to decline invitation',
      );
    }
  }

  /// Name to show a waiting member, best-effort from participant data.
  String? _leaderNameFor(Journey journey) {
    for (final person in journey.participants ?? const <Participant>[]) {
      if (person.userId == journey.leaderId) return person.displayName;
    }
    return null;
  }

  /// Collapse staging chrome without touching the journey.
  ///
  /// The user stays in the convoy — they are just looking at the map. The
  /// journey remains current, so the overlay returns when they act on it again.
  void _browseFromStaging() {
    if (!mounted) return;
    setState(() => _isStagingBusy = false);
    context.read<JourneyProvider>().clearCurrentJourneySelection();
  }

  Future<void> _startStagedJourney(Journey journey) async {
    if (_isStagingBusy) return;
    // Leader activation *is* gated on location: the backend flips the convoy
    // ACTIVE and every member starts navigating off this action, so a leader
    // who cannot publish position must not activate one. Joining/observing an
    // existing journey deliberately has no such gate.
    //
    // The busy slot is claimed synchronously *before* the location await:
    // setting it afterwards let a second tap land inside that gap and start the
    // journey twice, the same race already fixed on the new-draft start path.
    setState(() => _isStagingBusy = true);
    try {
      if (!await ensureLocationReady(context) || !mounted) return;
      final journeys = context.read<JourneyProvider>();
      final started = await journeys.startJourney(journey.id);
      if (!mounted) return;
      if (!started) {
        context.showErrorToast(
          journeys.error ?? 'Could not start this journey',
        );
        return;
      }
      unawaited(context.read<ConvoyProvider>().startCoordination(journey.id));
      _enterLiveJourney();
    } finally {
      if (mounted) setState(() => _isStagingBusy = false);
    }
  }

  Future<void> _cancelStagedJourney(Journey journey) async {
    if (_isStagingBusy) return;
    final confirmed = await _confirmStagingExit(
      title: 'Cancel journey?',
      message: 'This cancels "${journey.name}" for everyone invited.',
      confirmLabel: 'Cancel journey',
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isStagingBusy = true);
    try {
      final journeys = context.read<JourneyProvider>();
      final cancelled = await journeys.cancelJourney(journey.id);
      if (!mounted) return;
      if (!cancelled) {
        context.showErrorToast(journeys.error ?? 'Could not cancel');
        return;
      }
      await context.read<ConvoyProvider>().stopCoordination();
      if (mounted) _clearDraft();
    } finally {
      if (mounted) setState(() => _isStagingBusy = false);
    }
  }

  Future<void> _leaveStagedJourney(Journey journey) async {
    if (_isStagingBusy) return;
    final confirmed = await _confirmStagingExit(
      title: 'Leave journey?',
      message: 'You will stop receiving updates for "${journey.name}".',
      confirmLabel: 'Leave',
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isStagingBusy = true);
    try {
      final journeys = context.read<JourneyProvider>();
      final left = await journeys.leaveJourney(journey.id);
      if (!mounted) return;
      if (!left) {
        context.showErrorToast(journeys.error ?? 'Could not leave');
        return;
      }
      await context.read<ConvoyProvider>().stopCoordination();
      if (mounted) _clearDraft();
    } finally {
      if (mounted) setState(() => _isStagingBusy = false);
    }
  }

  Future<bool?> _confirmStagingExit({
    required String title,
    required String message,
    required String confirmLabel,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _shareInviteCode(Journey journey) async {
    final code = journey.inviteCode;
    if (code == null || code.isEmpty) {
      context.showInfoToast('No invite code for this journey yet');
      return;
    }
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) context.showSuccessToast('Invite code $code copied');
  }

  /// The live layer is tearing a journey down. Feeds the authoritative
  /// `ending` state, which is what keeps chrome and navbar consistent during
  /// the transition.
  void _setEndingJourney(bool isEnding) {
    if (!mounted || _isEndingJourney == isEnding) return;
    setState(() => _isEndingJourney = isEnding);
  }

  void _clearDraft() {
    // Abandon any in-flight route/draw work for the destination being dropped.
    _destinationDrawSeq++;
    context.read<MapProvider>().invalidateRouteRequests();
    unawaited(_clearDestinationAnnotations());
    unawaited(_clearPreviewRoute());
    setState(() {
      _destination = null;
      _companions = const [];
    });
    unawaited(_recenter());
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final analytics = context.watch<AnalyticsProvider>();
    final recentJourney = analytics.recentJourneys.firstOrNull;
    final activeJourney = context.watch<JourneyProvider>().currentJourney;
    final isRouteLoading = context.watch<MapProvider>().isFetchingRoute;
    final firstHistoryJourney = analytics.journeyHistory.firstOrNull;
    final convoy = context.watch<ConvoyProvider>();

    // One derived value decides what the map is doing, so the map layer and
    // the overlays can never disagree about the same journey.
    final isCurrentUserLeader =
        activeJourney != null && activeJourney.leaderId == user?.id;
    final experience = resolveMapExperienceState(
      currentJourney: activeJourney,
      completedJourney: _completedJourney,
      hasDraft: _destination != null,
      isStarting: _isStarting,
      isEnding: _isEndingJourney,
      isCurrentUserLeader: isCurrentUserLeader,
      connectionState: convoy.connectionState,
    );

    // Publish after the frame: listeners (the navigation shell) rebuild on
    // this, and notifying mid-build would set state during build.
    final experienceSink = widget.experience;
    if (experienceSink != null && experienceSink.value != experience) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) experienceSink.value = experience;
      });
    }

    // The live layer takes over the map's geometry and camera; the shell must
    // stop drawing its draft preview underneath it.
    final liveOwnsMap = experience.holdsJourneyGeometry;
    if (liveOwnsMap != _liveLayerOwnsMap) {
      _liveLayerOwnsMap = liveOwnsMap;
      if (liveOwnsMap) {
        // Hand the geometry over cleanly — two route polylines on one map is
        // exactly the divergence the single-map work exists to remove.
        unawaited(_clearPreviewRoute());
        unawaited(_clearDestinationAnnotations());
      }
    }

    if (widget.selectedTab == 1 &&
        !liveOwnsMap &&
        firstHistoryJourney != null &&
        _previewedJourneyId != firstHistoryJourney.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.selectedTab == 1) {
          unawaited(_previewJourney(firstHistoryJourney));
        }
      });
    }

    final Widget bottomOverlay = switch (widget.selectedTab) {
      1 => _JourneyHistoryMapSheet(
        journeys: analytics.journeyHistory,
        isLoading: analytics.isLoading,
        error: analytics.error,
        selectedJourneyId: _previewedJourneyId,
        currentUserId: user?.id,
        onRefresh: () => analytics.loadJourneyHistory(),
        onPreview: _previewJourney,
        onOpen: (journey) => JourneyNavigation.open(context, journey),
        onRepeat: _repeatJourney,
      ),
      2 => _InvitationsMapSheet(
        onRefresh: () => context.read<InviteProvider>().fetchInvitations(),
        onAccept: _acceptInvitation,
        onDecline: _declineInvitation,
      ),
      _ =>
        _destination == null
            ? activeJourney == null && recentJourney == null
                  ? const SizedBox.shrink()
                  : _HomeJourneySheet(
                      activeJourney: activeJourney,
                      recentJourney: recentJourney,
                      currentUserId: user?.id,
                      onContinue: _continueJourney,
                      onRepeat: _repeatJourney,
                    )
            : _ReadyJourneySheet(
                destinationTitle: _destinationTitle(_destination!.displayName),
                companions: _companions,
                isStarting: _isStarting,
                isRouteLoading: isRouteLoading,
                onClose: _clearDraft,
                onChooseCompanions: _chooseCompanions,
                onStart: _startJourney,
              ),
    };

    // Intercept the platform back gesture at the Home/live boundary for the
    // whole life of the journey. The intercept used to be released once the
    // chrome was collapsed, so a second Back popped the shell and stranded a
    // running convoy behind a screen the user could no longer reach.
    final hasActiveJourney =
        experience.isJourneyRunning || experience == MapExperienceState.ending;

    return LiveJourneyBackBoundary(
      hasActiveJourney: hasActiveJourney,
      isChromeCollapsed: _isLiveChromeCollapsed,
      onCollapseChrome: _collapseLiveChrome,
      onRestoreChrome: _restoreLiveChrome,
      child: Scaffold(
        body: Stack(
          children: [
            // The application's single map. It is never rebuilt across a journey
            // transition, which is what keeps the camera and the drawn route
            // continuous from destination preview through to arrival.
            Positioned.fill(
              child: PersistentTulinkMap(controller: _mapController),
            ),

            // Browse chrome is replaced by journey chrome whenever the journey
            // owns the screen. This is deliberately the *same* predicate the
            // navigation shell uses for the tab bar: when they disagreed, a
            // finished journey left a stale draft sheet — with a live "Start
            // journey" button — sitting under the completion summary.
            if (!experience.hidesNavigationTabs) ...[
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: _MapSearchBar(
                    destination: _destination,
                    userName: user?.name ?? 'Traveller',
                    imageUrl: user?.profilePicture,
                    onLogoTap: _clearDraft,
                    onSearchTap: _chooseDestination,
                    onJoinTap: _joinJourneyByCode,
                    onProfileTap: _openProfile,
                  ),
                ),
              ),
              Align(alignment: Alignment.bottomCenter, child: bottomOverlay),
            ],

            // An invited member waiting for the leader. A real experience over
            // the same map — the destination is already drawn behind it and
            // `journey-started` promotes this in place, with no navigation.
            if (experience == MapExperienceState.waitingForLeader &&
                activeJourney != null)
              Positioned.fill(
                child: PendingJourneyStaging(
                  // Keyed by journey so switching staged journeys rebuilds the
                  // room state machine instead of carrying A's state into B.
                  key: ValueKey('staging-${activeJourney.id}'),
                  journey: activeJourney,
                  isLeader: false,
                  leaderName: _leaderNameFor(activeJourney),
                  isBusy: _isStagingBusy,
                  locationFailure: convoy.locationFailure,
                  onRetryLocation: () =>
                      context.read<ConvoyProvider>().retryLocationPublishing(),
                  onDismiss: _browseFromStaging,
                  onLeaveJourney: () => _leaveStagedJourney(activeJourney),
                  joinRoom: _joinPendingRoomFor,
                  hasStartFailure:
                      _journeyStartFailedId != null &&
                      _journeyStartFailedId == activeJourney.id,
                  onRetryStart: _retryJourneyStarted,
                ),
              ),

            // The leader's own staging chrome for a journey that exists but has
            // not started (resumed from history, or created elsewhere).
            if (experience == MapExperienceState.drafting &&
                activeJourney != null &&
                activeJourney.status == JourneyStatus.PENDING &&
                isCurrentUserLeader)
              Positioned.fill(
                child: PendingJourneyStaging(
                  key: ValueKey('staging-${activeJourney.id}'),
                  journey: activeJourney,
                  isLeader: true,
                  isBusy: _isStagingBusy,
                  locationFailure: convoy.locationFailure,
                  onRetryLocation: () =>
                      context.read<ConvoyProvider>().retryLocationPublishing(),
                  onDismiss: _browseFromStaging,
                  onStart: () => _startStagedJourney(activeJourney),
                  onCancelJourney: () => _cancelStagedJourney(activeJourney),
                  onShareCode: () => _shareInviteCode(activeJourney),
                  onInvitePeople: () =>
                      _invitePeopleToStagedJourney(activeJourney),
                  joinRoom: _joinPendingRoomFor,
                  hasStartFailure:
                      _journeyStartFailedId != null &&
                      _journeyStartFailedId == activeJourney.id,
                  onRetryStart: _retryJourneyStarted,
                ),
              ),

            // Kept mounted through `ending` as well as while running. Teardown
            // is asynchronous and finishes *inside* this layer; unmounting it the
            // moment it reported `ending` killed the very callback that clears
            // the flag and produces the summary, leaving a chrome-less map.
            if ((experience.isJourneyRunning ||
                    experience == MapExperienceState.ending) &&
                !_isLiveChromeCollapsed)
              Positioned.fill(
                child: LiveJourneyExperience(
                  controller: _mapController,
                  onExit: _onLiveJourneyExit,
                  onCompleted: _onLiveJourneyCompleted,
                  onBack: _collapseLiveChrome,
                  onEndingChanged: _setEndingJourney,
                ),
              ),

            // Back collapsed the live chrome. The journey is still running — this
            // pill is the observable proof of that, and the way back in.
            if (experience.isJourneyRunning && _isLiveChromeCollapsed)
              SafeArea(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: _ResumeLiveChromePill(
                    journey: activeJourney,
                    onTap: _restoreLiveChrome,
                  ),
                ),
              ),

            if (experience == MapExperienceState.completed &&
                _completedJourney != null)
              Positioned.fill(
                child: CompletedJourneyOverlay(
                  journey: _completedJourney!,
                  isDismissing: _isCleaningArtifacts,
                  onDismiss: _dismissCompletedJourney,
                  onViewDetails: () =>
                      JourneyNavigation.open(context, _completedJourney!),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Shown when Back collapsed the live convoy chrome.
///
/// Its presence is what makes Back a real, observable state change rather than
/// a no-op: the journey is still running, the map is now free to pan, and this
/// is the way back to the convoy.
class _ResumeLiveChromePill extends StatelessWidget {
  const _ResumeLiveChromePill({required this.journey, required this.onTap});

  final Journey? journey;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Material(
        color: colors.electricRed,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.navigation, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(
                  journey == null
                      ? 'Journey in progress'
                      : 'Back to ${journey!.destinationLabel}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MapSearchBar extends StatelessWidget {
  const _MapSearchBar({
    required this.destination,
    required this.userName,
    required this.imageUrl,
    required this.onLogoTap,
    required this.onSearchTap,
    required this.onJoinTap,
    required this.onProfileTap,
  });

  final PlaceSearchResult? destination;
  final String userName;
  final String? imageUrl;
  final VoidCallback onLogoTap;
  final VoidCallback onSearchTap;
  final VoidCallback onJoinTap;
  final VoidCallback onProfileTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;
    return Material(
      color: colors.surface,
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: .16),
      borderRadius: BorderRadius.circular(28),
      child: SizedBox(
        height: 58,
        child: Row(
          children: [
            Semantics(
              button: true,
              label: 'Clear journey and return home',
              child: InkWell(
                onTap: onLogoTap,
                customBorder: const CircleBorder(),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 7, 8, 7),
                  child: SvgPicture.asset(
                    'assets/brand/logo-mark-primary.svg',
                    width: 42,
                    height: 42,
                  ),
                ),
              ),
            ),
            Expanded(
              child: InkWell(
                onTap: onSearchTap,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    destination?.displayName ?? 'Where are you going?',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: destination == null ? colors.muted : colors.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Join with a code',
              onPressed: onJoinTap,
              color: colors.deepTeal,
              icon: const Icon(Icons.dialpad_rounded, size: 21),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _ProfileButton(
                name: userName,
                imageUrl: imageUrl,
                onTap: onProfileTap,
                size: 46,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet for joining an existing journey using its shared code.
class JoinJourneyCodeSheet extends StatefulWidget {
  const JoinJourneyCodeSheet({super.key});

  @override
  State<JoinJourneyCodeSheet> createState() => _JoinJourneyCodeSheetState();
}

class _JoinJourneyCodeSheetState extends State<JoinJourneyCodeSheet> {
  final _controller = TextEditingController();
  bool _submitting = false;
  String? _validationError;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final code = _controller.text.trim().toUpperCase();
    if (!RegExp(r'^[2-9A-HJ-NP-Z]{10}$').hasMatch(code)) {
      setState(() {
        _validationError = 'Enter a valid 10-character code';
      });
      return;
    }

    setState(() {
      _submitting = true;
      _validationError = null;
    });
    final provider = context.read<JourneyProvider>();
    final journey = await provider.joinJourneyByCode(code);
    if (!mounted) return;
    if (journey == null) {
      setState(() {
        _submitting = false;
        _validationError = provider.error ?? 'Unable to join this journey';
      });
      return;
    }
    Navigator.of(context).pop(journey);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        8,
        24,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Join a journey',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Enter the 10-character code shared by the journey leader.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            textAlign: TextAlign.center,
            inputFormatters: [
              FilteringTextInputFormatter.allow(
                RegExp('[2-9A-HJ-NP-Za-hj-np-z]'),
              ),
              LengthLimitingTextInputFormatter(10),
            ],
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w800,
              letterSpacing: 3.2,
            ),
            decoration: InputDecoration(
              hintText: 'JOURNEY CODE',
              errorText: _validationError,
            ),
            onChanged: (_) {
              if (_validationError != null) {
                setState(() => _validationError = null);
              }
            },
            onSubmitted: _submitting ? null : (_) => _submit(),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Join journey'),
          ),
        ],
      ),
    );
  }
}

class _DestinationSearchSheet extends StatefulWidget {
  const _DestinationSearchSheet();

  @override
  State<_DestinationSearchSheet> createState() =>
      _DestinationSearchSheetState();
}

class _DestinationSearchSheetState extends State<_DestinationSearchSheet> {
  final _controller = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _search(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      context.read<MapProvider>().clearSearchResults();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) context.read<MapProvider>().searchPlaces(value.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;
    final maps = context.watch<MapProvider>();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Where are you going?',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Your destination becomes the journey name.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _controller,
              autofocus: true,
              onChanged: _search,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                hintText: 'Search for a place',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 12),
            if (maps.isSearching)
              const LinearProgressIndicator(minHeight: 2)
            else if (maps.searchError != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(maps.searchError!),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: maps.searchResults.length,
                  separatorBuilder: (_, __) => Divider(color: colors.divider),
                  itemBuilder: (context, index) {
                    final place = maps.searchResults[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      leading: CircleAvatar(
                        backgroundColor: colors.routeTeal.withValues(
                          alpha: .12,
                        ),
                        foregroundColor: colors.deepTeal,
                        child: const Icon(Icons.place_outlined),
                      ),
                      title: Text(
                        place.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        place.address,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => Navigator.of(context).pop(place),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CompanionPickerSheet extends StatefulWidget {
  const _CompanionPickerSheet({
    required this.initial,
    this.excludedUserIds = const <String>{},
  });

  final List<_SelectedCompanion> initial;

  /// Users who cannot be picked — the leader and anyone already on the journey.
  /// Filtering here rather than after selection means a duplicate invitation is
  /// simply not offerable.
  final Set<String> excludedUserIds;

  @override
  State<_CompanionPickerSheet> createState() => _CompanionPickerSheetState();
}

class _CompanionPickerSheetState extends State<_CompanionPickerSheet> {
  final _controller = TextEditingController();
  final Map<String, _SelectedCompanion> _selected = {};
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    for (final person in widget.initial) {
      _selected[person.id] = person;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<InviteProvider>().clearSearch();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _search(String value) {
    setState(() {});
    _debounce?.cancel();
    if (value.trim().length < 2) {
      context.read<InviteProvider>().clearSearch();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) context.read<InviteProvider>().searchUsers(value.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final invites = context.watch<InviteProvider>();
    final colors = Theme.of(context).tulinkColors;
    final currentUserId = context.read<AuthProvider>().user?.id;
    final results = invites.searchResults
        .where((user) => user.uid != currentUserId)
        // Already on the journey (or the leader): not offerable, so a
        // duplicate invitation cannot be composed in the first place.
        .where((user) => !widget.excludedUserIds.contains(user.uid))
        .toList();
    final showingSearch = _controller.text.trim().length >= 2;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .76,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Who’s coming?',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                TextButton(
                  onPressed: () =>
                      Navigator.of(context).pop(_selected.values.toList()),
                  child: Text('Done · ${_selected.length}'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Search people already using Tulink.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _controller,
              autofocus: widget.initial.isEmpty,
              onChanged: _search,
              decoration: const InputDecoration(
                hintText: 'Search by name or username',
                prefixIcon: Icon(Icons.person_search_outlined),
              ),
            ),
            const SizedBox(height: 12),
            if (invites.isSearching)
              const LinearProgressIndicator(minHeight: 2)
            else
              Expanded(
                child: ListView.separated(
                  itemCount: showingSearch ? results.length : _selected.length,
                  separatorBuilder: (_, __) => Divider(color: colors.divider),
                  itemBuilder: (context, index) {
                    if (!showingSearch) {
                      final person = _selected.values.elementAt(index);
                      return _PersonTile(
                        name: person.name,
                        selected: true,
                        onTap: () =>
                            setState(() => _selected.remove(person.id)),
                      );
                    }
                    final user = results[index];
                    final selected = _selected.containsKey(user.uid);
                    return _PersonTile(
                      name: user.displayName,
                      subtitle: user.email,
                      selected: selected,
                      onTap: () => setState(() {
                        if (selected) {
                          _selected.remove(user.uid);
                        } else {
                          _selected[user.uid] =
                              _SelectedCompanion.fromSearchResult(user);
                        }
                      }),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HomeJourneySheet extends StatelessWidget {
  const _HomeJourneySheet({
    required this.activeJourney,
    required this.recentJourney,
    required this.currentUserId,
    required this.onContinue,
    required this.onRepeat,
  });

  final Journey? activeJourney;
  final Journey? recentJourney;
  final String? currentUserId;
  final ValueChanged<Journey> onContinue;
  final ValueChanged<Journey> onRepeat;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(20, 10, 20, 12),
      decoration: BoxDecoration(
        color: colors.warmSand,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 24,
            offset: Offset(0, -8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: colors.divider,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          if (activeJourney != null &&
              (activeJourney!.status == JourneyStatus.PENDING ||
                  activeJourney!.status == JourneyStatus.ACTIVE)) ...[
            const SizedBox(height: 10),
            Material(
              color: colors.deepTeal,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                onTap: () => onContinue(activeJourney!),
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.route_rounded, color: Colors.white),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              activeJourney!.status == JourneyStatus.ACTIVE
                                  ? 'Journey in progress'
                                  : 'Journey ready',
                              style: const TextStyle(color: Color(0xFFDCEDEF)),
                            ),
                            Text(
                              activeJourney!.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ] else if (recentJourney != null) ...[
            const SizedBox(height: 4),
            Text(
              'LAST JOURNEY',
              style: TextStyle(
                color: colors.deepTeal,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
            _RecentJourneyRow(
              journey: recentJourney!,
              currentUserId: currentUserId,
              onTap: () => onRepeat(recentJourney!),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReadyJourneySheet extends StatelessWidget {
  const _ReadyJourneySheet({
    required this.destinationTitle,
    required this.companions,
    required this.isStarting,
    required this.isRouteLoading,
    required this.onClose,
    required this.onChooseCompanions,
    required this.onStart,
  });

  final String destinationTitle;
  final List<_SelectedCompanion> companions;
  final bool isStarting;
  final bool isRouteLoading;
  final VoidCallback onClose;
  final VoidCallback onChooseCompanions;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
      decoration: BoxDecoration(
        color: colors.warmSand,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 24,
            offset: Offset(0, -8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: colors.divider,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  'Trip to $destinationTitle',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              IconButton(
                tooltip: 'Cancel journey setup',
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Text(
                'Going with',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: companions.isEmpty
                    ? Text(
                        'Add your people',
                        style: Theme.of(context).textTheme.bodyMedium,
                      )
                    : Row(
                        children: [
                          _AvatarStack(
                            names: companions.map((p) => p.name).toList(),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              _companionSummary(companions),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
              ),
              IconButton.filledTonal(
                tooltip: 'Choose people',
                onPressed: onChooseCompanions,
                icon: const Icon(Icons.person_add_alt_1_rounded),
              ),
            ],
          ),
          const SizedBox(height: 22),
          if (isRouteLoading) ...[
            Row(
              children: [
                SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.routeTeal,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Finding the best route…',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
            const SizedBox(height: 14),
          ],
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: isStarting || isRouteLoading ? null : onStart,
              icon: isStarting || isRouteLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.arrow_forward_rounded),
              iconAlignment: IconAlignment.end,
              label: Text(
                isStarting
                    ? 'Starting…'
                    : isRouteLoading
                    ? 'Finding route…'
                    : 'Start journey',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _JourneyHistoryMapSheet extends StatelessWidget {
  const _JourneyHistoryMapSheet({
    required this.journeys,
    required this.isLoading,
    required this.error,
    required this.selectedJourneyId,
    required this.currentUserId,
    required this.onRefresh,
    required this.onPreview,
    required this.onOpen,
    required this.onRepeat,
  });

  final List<Journey> journeys;
  final bool isLoading;
  final String? error;
  final String? selectedJourneyId;
  final String? currentUserId;
  final Future<void> Function() onRefresh;
  final ValueChanged<Journey> onPreview;
  final ValueChanged<Journey> onOpen;
  final ValueChanged<Journey> onRepeat;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;
    return DraggableScrollableSheet(
      initialChildSize: .43,
      minChildSize: .115,
      maxChildSize: .78,
      snap: true,
      snapSizes: const [.115, .43, .78],
      builder: (context, scrollController) {
        return DecoratedBox(
          decoration: _mapSheetDecoration(colors),
          child: RefreshIndicator(
            onRefresh: onRefresh,
            color: colors.routeTeal,
            child: CustomScrollView(
              controller: scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: _MapSheetHeader(title: 'Journeys')),
                if (isLoading && journeys.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: CircularProgressIndicator(color: colors.routeTeal),
                    ),
                  )
                else if (error != null && journeys.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _OverlayMessage(
                      icon: Icons.cloud_off_rounded,
                      title: 'Journeys are unavailable',
                      message: error!,
                      actionLabel: 'Try again',
                      onAction: onRefresh,
                    ),
                  )
                else if (journeys.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: _OverlayMessage(
                      icon: Icons.route_rounded,
                      title: 'No journeys yet',
                      message: 'Choose a destination on the map to get moving.',
                    ),
                  )
                else ...[
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
                    sliver: SliverList.separated(
                      itemCount: journeys.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: colors.divider.withValues(alpha: .8),
                      ),
                      itemBuilder: (context, index) {
                        final journey = journeys[index];
                        return _JourneyOverlayRow(
                          journey: journey,
                          isSelected: selectedJourneyId == journey.id,
                          isPrimary: index == 0,
                          currentUserId: currentUserId,
                          onPreview: () => onPreview(journey),
                          onOpen: () => onOpen(journey),
                          onRepeat: () => onRepeat(journey),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _JourneyOverlayRow extends StatelessWidget {
  const _JourneyOverlayRow({
    required this.journey,
    required this.isSelected,
    required this.isPrimary,
    required this.currentUserId,
    required this.onPreview,
    required this.onOpen,
    required this.onRepeat,
  });

  final Journey journey;
  final bool isSelected;
  final bool isPrimary;
  final String? currentUserId;
  final VoidCallback onPreview;
  final VoidCallback onOpen;
  final VoidCallback onRepeat;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;
    final people = (journey.participants ?? const <Participant>[])
        .where((person) => person.userId != currentUserId)
        .where((person) => person.status.toUpperCase() != 'LEFT')
        .length;
    return Semantics(
      button: true,
      label: '${journey.name}, ${journey.destinationLabel}',
      hint: 'Tap to preview on the map, long press for journey details',
      onLongPress: onOpen,
      child: InkWell(
        onTap: onPreview,
        // Tapping the row belongs to the map preview (the map-first direction);
        // full details remain reachable without competing for that gesture.
        onLongPress: onOpen,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? colors.routeTeal.withValues(alpha: .07)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colors.routeTeal.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(Icons.route_rounded, color: colors.routeTeal),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      journey.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_rounded,
                          size: 15,
                          color: colors.sunsetOrange,
                        ),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            journey.destinationLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '$people ${people == 1 ? 'companion' : 'companions'}  •  ${_timeAgo(journey.createdAt)}',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // "Go again" is the headline affordance of the redesign, so every
              // completed row offers it — not just the most recent one. Details
              // stay reachable from the row body via [onOpen].
              FilledButton(
                onPressed: onRepeat,
                style: FilledButton.styleFrom(
                  backgroundColor: isPrimary
                      ? colors.deepTeal
                      : colors.warmSand,
                  foregroundColor: isPrimary ? Colors.white : colors.deepTeal,
                  minimumSize: const ui.Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                ),
                child: const Text('Go again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InvitationsMapSheet extends StatelessWidget {
  const _InvitationsMapSheet({
    required this.onRefresh,
    required this.onAccept,
    required this.onDecline,
  });

  final Future<void> Function() onRefresh;
  final ValueChanged<JourneyInvitation> onAccept;
  final ValueChanged<JourneyInvitation> onDecline;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;
    final provider = context.watch<InviteProvider>();
    final invitations = provider.invitations;
    return DraggableScrollableSheet(
      initialChildSize: invitations.isEmpty ? .36 : .48,
      minChildSize: .115,
      maxChildSize: .78,
      snap: true,
      snapSizes: [.115, invitations.isEmpty ? .36 : .48, .78],
      builder: (context, scrollController) {
        return DecoratedBox(
          decoration: _mapSheetDecoration(colors),
          child: RefreshIndicator(
            onRefresh: onRefresh,
            color: colors.routeTeal,
            child: CustomScrollView(
              controller: scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: _MapSheetHeader(
                    title: 'Invites',
                    count: invitations.length,
                  ),
                ),
                if (provider.isLoadingInvitations && invitations.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: CircularProgressIndicator(color: colors.routeTeal),
                    ),
                  )
                else if (provider.invitationsError != null &&
                    invitations.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _OverlayMessage(
                      icon: Icons.cloud_off_rounded,
                      title: 'Invites are unavailable',
                      message: provider.invitationsError!,
                      actionLabel: 'Try again',
                      onAction: onRefresh,
                    ),
                  )
                else if (invitations.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: _OverlayMessage(
                      icon: Icons.mail_outline_rounded,
                      title: 'No invitations',
                      message: 'New journey invitations will appear here.',
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
                    sliver: SliverList.separated(
                      itemCount: invitations.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: colors.divider.withValues(alpha: .8),
                      ),
                      itemBuilder: (context, index) {
                        final invitation = invitations[index];
                        return _InvitationOverlayRow(
                          invitation: invitation,
                          isPrimary: index == 0,
                          isBusy: provider.isAccepting || provider.isDeclining,
                          onAccept: () => onAccept(invitation),
                          onDecline: () => onDecline(invitation),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _InvitationOverlayRow extends StatelessWidget {
  const _InvitationOverlayRow({
    required this.invitation,
    required this.isPrimary,
    required this.isBusy,
    required this.onAccept,
    required this.onDecline,
  });

  final JourneyInvitation invitation;
  final bool isPrimary;
  final bool isBusy;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: isPrimary
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _InitialAvatar(
                      label: _initials(invitation.invitedBy.displayName),
                      size: 52,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            invitation.journeyName,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            invitation.destination,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Invited by ${invitation.invitedBy.displayName}  •  ${_timeAgo(invitation.invitedAt)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(
                              context,
                            ).textTheme.bodyMedium?.copyWith(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: isBusy ? null : onAccept,
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.deepTeal,
                      foregroundColor: Colors.white,
                      minimumSize: const ui.Size.fromHeight(52),
                    ),
                    child: Text(isBusy ? 'Working…' : 'Accept'),
                  ),
                ),
                Center(
                  child: TextButton(
                    onPressed: isBusy ? null : onDecline,
                    child: const Text('Decline'),
                  ),
                ),
              ],
            )
          : Row(
              children: [
                _InitialAvatar(
                  label: _initials(invitation.invitedBy.displayName),
                  size: 42,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        invitation.journeyName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '${invitation.destination}  •  ${_timeAgo(invitation.invitedAt)}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Accept invitation',
                  onPressed: isBusy ? null : onAccept,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
    );
  }
}

class _MapSheetHeader extends StatelessWidget {
  const _MapSheetHeader({required this.title, this.count});

  final String title;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 16),
      child: Column(
        children: [
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: colors.divider,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.displaySmall?.copyWith(fontSize: 26),
                ),
              ),
              if (count != null && count! > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: colors.routeTeal.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      color: colors.deepTeal,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OverlayMessage extends StatelessWidget {
  const _OverlayMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final Future<void> Function()? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 10, 28, 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 46, color: colors.routeTeal),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

class _InitialAvatar extends StatelessWidget {
  const _InitialAvatar({required this.label, required this.size});

  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: colors.deepTeal, shape: BoxShape.circle),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * .3,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

BoxDecoration _mapSheetDecoration(TulinkColors colors) => BoxDecoration(
  color: colors.warmSand,
  borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
  boxShadow: const [
    BoxShadow(color: Color(0x18000000), blurRadius: 28, offset: Offset(0, -8)),
  ],
);

class _RecentJourneyRow extends StatelessWidget {
  const _RecentJourneyRow({
    required this.journey,
    required this.currentUserId,
    required this.onTap,
  });

  final Journey journey;
  final String? currentUserId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final people = (journey.participants ?? const <Participant>[])
        .where(
          (p) => p.userId != currentUserId && p.status.toUpperCase() != 'LEFT',
        )
        .map((p) => p.displayName ?? 'Traveller')
        .take(4)
        .toList();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  journey.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  journey.destinationLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          if (people.isNotEmpty) ...[
            _AvatarStack(names: people, size: 36),
            const SizedBox(width: 10),
          ],
          FilledButton(
            onPressed: onTap,
            style: FilledButton.styleFrom(
              minimumSize: const ui.Size(58, 44),
              padding: const EdgeInsets.symmetric(horizontal: 18),
            ),
            child: const Text('Go again'),
          ),
        ],
      ),
    );
  }
}

class _AvatarStack extends StatelessWidget {
  const _AvatarStack({required this.names, this.size = 40});

  final List<String> names;
  final double size;

  @override
  Widget build(BuildContext context) {
    final visible = names.take(4).toList();
    final width = visible.isEmpty
        ? 0.0
        : size + (visible.length - 1) * size * .62;
    return SizedBox(
      width: width,
      height: size,
      child: Stack(
        children: [
          for (var index = 0; index < visible.length; index++)
            Positioned(
              left: index * size * .62,
              child: _InitialsAvatar(name: visible[index], size: size),
            ),
        ],
      ),
    );
  }
}

class _PersonTile extends StatelessWidget {
  const _PersonTile({
    required this.name,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  final String name;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: _InitialsAvatar(name: name, size: 44),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: Icon(
        selected
            ? Icons.check_circle_rounded
            : Icons.add_circle_outline_rounded,
        color: selected ? colors.routeTeal : colors.muted,
      ),
      onTap: onTap,
    );
  }
}

class _InitialsAvatar extends StatelessWidget {
  const _InitialsAvatar({required this.name, required this.size});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.routeTeal,
        shape: BoxShape.circle,
        border: Border.all(color: colors.warmSand, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        _initials(name),
        style: TextStyle(
          color: Colors.white,
          fontSize: size * .31,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ProfileButton extends StatelessWidget {
  const _ProfileButton({
    required this.name,
    required this.imageUrl,
    required this.onTap,
    this.size = 48,
  });

  final String name;
  final String? imageUrl;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl != null && imageUrl!.trim().isNotEmpty;
    return Semantics(
      button: true,
      label: 'Open profile',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          padding: const EdgeInsets.all(3),
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
          child: hasImage
              ? CircleAvatar(backgroundImage: NetworkImage(imageUrl!))
              : _InitialsAvatar(name: name, size: size - 6),
        ),
      ),
    );
  }
}

class _SelectedCompanion {
  const _SelectedCompanion({required this.id, required this.name});

  factory _SelectedCompanion.fromParticipant(Participant participant) {
    return _SelectedCompanion(
      id: participant.userId,
      name: participant.displayName ?? 'Traveller',
    );
  }

  factory _SelectedCompanion.fromSearchResult(UserSearchResult user) {
    return _SelectedCompanion(id: user.uid, name: user.displayName);
  }

  final String id;
  final String name;
}

String _destinationTitle(String value) {
  final first = value.split(',').first.trim();
  return first.isEmpty ? 'your destination' : first;
}

String _companionSummary(List<_SelectedCompanion> companions) {
  final firstNames = companions
      .map((person) => person.name.trim().split(RegExp(r'\s+')).first)
      .toList();
  if (firstNames.isEmpty) return 'Add your people';
  if (firstNames.length == 1) return firstNames.first;
  if (firstNames.length == 2) {
    return '${firstNames[0]} and ${firstNames[1]}';
  }
  return '${firstNames[0]}, ${firstNames[1]} +${firstNames.length - 2}';
}

String _timeAgo(DateTime? dateTime) {
  if (dateTime == null) return 'Recently';
  final difference = DateTime.now().difference(dateTime);
  if (difference.inDays > 0) return '${difference.inDays}d ago';
  if (difference.inHours > 0) return '${difference.inHours}h ago';
  if (difference.inMinutes > 0) return '${difference.inMinutes}m ago';
  return 'Just now';
}

String _initials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}
