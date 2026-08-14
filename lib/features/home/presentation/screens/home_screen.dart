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
import 'package:tulink_flutter/features/journeys/presentation/pages/journey_preview_screen.dart';
import 'package:tulink_flutter/features/journeys/presentation/providers/journey_provider.dart';
import 'package:tulink_flutter/features/journeys/presentation/utils/journey_navigation.dart';
import 'package:tulink_flutter/features/maps/domain/entities/place_search_result.dart';
import 'package:tulink_flutter/features/maps/presentation/providers/map_provider.dart';
import 'package:tulink_flutter/features/profile/presentation/screens/profile_screen.dart';

/// Tulink's map-first home. Creating a journey is intentionally reduced to
/// destination -> people -> start, while the existing providers continue to
/// own networking, location, invitations and convoy coordination.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.selectedTab = 0, this.onTabSelected});

  static const routeName = '/dashboard';

  /// 0 = Map, 1 = Journeys, 2 = Invites. The map itself remains mounted while
  /// these overlays change, keeping camera and journey-draft state intact.
  final int selectedTab;
  final ValueChanged<int>? onTabSelected;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  MapboxMap? _map;
  CircleAnnotationManager? _destinationAnnotations;
  StreamSubscription<RemoteMessage>? _pushSub;
  StreamSubscription<RemoteMessage>? _pushTapSub;
  Timer? _invitePollingTimer;
  PlaceSearchResult? _destination;
  List<_SelectedCompanion> _companions = const [];
  bool _isStarting = false;
  bool _isRoutingToMap = false;
  int _lastJourneyInviteTick = 0;
  String? _previewedJourneyId;

  static const _previewSourceId = 'home-preview-route-source';
  static const _previewShadowId = 'home-preview-route-shadow';
  static const _previewLineId = 'home-preview-route-line';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    _pushSub?.cancel();
    _pushTapSub?.cancel();
    _invitePollingTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<InviteProvider>().refreshInvitationsSilently(force: true);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final convoy = context.watch<ConvoyProvider>();

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

    final startedJourneyId = convoy.pendingJourneyStartedId;
    if (startedJourneyId != null && !_isRoutingToMap) {
      _isRoutingToMap = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        convoy.consumeJourneyStartedEvent();
        await context.read<JourneyProvider>().fetchJourneyById(
          startedJourneyId,
        );
        if (!mounted || !await ensureLocationReady(context)) {
          _isRoutingToMap = false;
          return;
        }
        if (!mounted) return;
        unawaited(
          context.read<ConvoyProvider>().startCoordination(startedJourneyId),
        );
        await Navigator.of(context).pushNamed('/mapview');
        _isRoutingToMap = false;
      });
    }
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
        Navigator.of(
          context,
        ).pushNamed(JourneyPreviewScreen.routeName, arguments: journeyId);
      }
    }
  }

  Future<void> _onMapCreated(MapboxMap map) async {
    _map = map;
    await map.scaleBar.updateSettings(ScaleBarSettings(enabled: false));
    _destinationAnnotations = await map.annotations
        .createCircleAnnotationManager();
    try {
      await map.location.updateSettings(
        LocationComponentSettings(enabled: true, pulsingEnabled: true),
      );
    } catch (_) {
      // Location access is already explained and requested by the home flow.
    }
    await _recenter();
    final draftDestination = _destination;
    if (draftDestination != null) {
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

  Future<void> _showDestinationOnMap(PlaceSearchResult place) async {
    final manager = _destinationAnnotations;
    final map = _map;
    if (manager == null || map == null) return;
    await manager.deleteAll();
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
      // A denied or cold GPS fix should not prevent a route preview. Nairobi
      // is already Tulink's initial map centre and is replaced by live origin
      // whenever location is available.
      originLat: origin?.latitude ?? -1.2921,
      originLng: origin?.longitude ?? 36.8219,
      destLat: place.lat,
      destLng: place.lng,
    );
    if (!mounted) return;
    if (route != null && route.coordinates.length > 1) {
      await _drawPreviewRoute(route.coordinates);
      await _fitPreviewCamera(route.coordinates);
      return;
    }

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
      displayName: _destinationTitle(journey.destinationAddress),
      address: journey.destinationAddress,
      lat: journey.destination.latitude,
      lng: journey.destination.longitude,
      types: const ['journey'],
    );
    await _showDestinationOnMap(place);
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

    final title = _destinationTitle(journey.destinationAddress);
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
    if (!await ensureLocationReady(context) || !mounted) return;

    setState(() => _isStarting = true);
    final journeys = context.read<JourneyProvider>();
    final created = await journeys.createJourney(
      name: 'Trip to ${_destinationTitle(destination.displayName)}',
      latitude: destination.lat,
      longitude: destination.lng,
      destinationAddress: destination.address,
      lagThresholdMeters: 500,
    );
    if (!mounted) return;
    if (!created || journeys.currentJourney == null) {
      setState(() => _isStarting = false);
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
      setState(() => _isStarting = false);
      context.showErrorToast(journeys.error ?? 'Could not start this journey');
      return;
    }

    unawaited(context.read<ConvoyProvider>().startCoordination(journeyId));
    if (failedInvites > 0) {
      context.showInfoToast(
        '$failedInvites invitation${failedInvites == 1 ? '' : 's'} '
        'could not be sent',
      );
    }
    setState(() => _isStarting = false);
    await Navigator.of(context).pushNamed('/mapview', arguments: journeyId);
  }

  Future<void> _continueJourney(Journey journey) async {
    if (journey.status == JourneyStatus.PENDING) {
      await Navigator.of(
        context,
      ).pushNamed(JourneyPreviewScreen.routeName, arguments: journey.id);
      return;
    }
    if (!await ensureLocationReady(context) || !mounted) return;
    context.read<JourneyProvider>().setCurrentJourney(journey);
    unawaited(context.read<ConvoyProvider>().startCoordination(journey.id));
    await Navigator.of(context).pushNamed('/mapview', arguments: journey.id);
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
      if (!await ensureLocationReady(context) || !mounted) return;
      await context.read<ConvoyProvider>().startCoordination(joinedJourney.id);
      if (mounted) {
        await Navigator.of(
          context,
        ).pushNamed('/mapview', arguments: joinedJourney.id);
      }
      return;
    }

    final listening = await context.read<ConvoyProvider>().joinJourneyRoom(
      joinedJourney.id,
    );
    if (!mounted) return;
    if (!listening) {
      context.showWarningToast('Joined. Live updates are reconnecting.');
    }
    await Navigator.of(
      context,
    ).pushNamed(JourneyPreviewScreen.routeName, arguments: joinedJourney.id);
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
    await context.read<JourneyProvider>().fetchJourneyById(
      invitation.journeyId,
    );
    if (!mounted) return;
    final journey = context.read<JourneyProvider>().currentJourney;
    if (journey?.status == JourneyStatus.ACTIVE) {
      if (!await ensureLocationReady(context) || !mounted) return;
      await context.read<ConvoyProvider>().startCoordination(
        invitation.journeyId,
      );
      if (mounted) await Navigator.of(context).pushNamed('/mapview');
      return;
    }

    final listening = await context.read<ConvoyProvider>().joinJourneyRoom(
      invitation.journeyId,
    );
    if (!mounted) return;
    if (!listening) {
      context.showWarningToast(
        'Journey joined. Live updates are reconnecting.',
      );
    }
    await Navigator.of(context).pushNamed(
      JourneyPreviewScreen.routeName,
      arguments: invitation.journeyId,
    );
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

  void _clearDraft() {
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
    final firstHistoryJourney = analytics.journeyHistory.firstOrNull;

    if (widget.selectedTab == 1 &&
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
                onClose: _clearDraft,
                onChooseCompanions: _chooseCompanions,
                onStart: _startJourney,
              ),
    };

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: MapWidget(
              key: const ValueKey('tulink_home_map'),
              onMapCreated: _onMapCreated,
              styleUri: MapboxStyles.MAPBOX_STREETS,
              cameraOptions: CameraOptions(
                center: Point(coordinates: Position(36.8219, -1.2921)),
                zoom: 10.5,
              ),
            ),
          ),
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
                onProfileTap: () =>
                    Navigator.of(context).pushNamed(ProfileScreen.routeName),
              ),
            ),
          ),
          Align(alignment: Alignment.bottomCenter, child: bottomOverlay),
        ],
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
  const _CompanionPickerSheet({required this.initial});

  final List<_SelectedCompanion> initial;

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
    required this.onClose,
    required this.onChooseCompanions,
    required this.onStart,
  });

  final String destinationTitle;
  final List<_SelectedCompanion> companions;
  final bool isStarting;
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
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: isStarting ? null : onStart,
              icon: isStarting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.arrow_forward_rounded),
              iconAlignment: IconAlignment.end,
              label: Text(isStarting ? 'Starting…' : 'Start journey'),
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
      label: '${journey.name}, ${journey.destinationAddress}',
      child: InkWell(
        onTap: onPreview,
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
                            journey.destinationAddress,
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
              if (isPrimary)
                FilledButton(
                  onPressed: onRepeat,
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.deepTeal,
                    foregroundColor: Colors.white,
                    minimumSize: const ui.Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 15),
                  ),
                  child: const Text('Go again'),
                )
              else
                IconButton(
                  tooltip: 'Open journey details',
                  onPressed: onOpen,
                  icon: const Icon(Icons.chevron_right_rounded),
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
                  journey.destinationAddress,
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
