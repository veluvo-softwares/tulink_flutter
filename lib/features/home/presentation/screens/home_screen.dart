import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:tulink_flutter/features/analytics/presentation/providers/analytics_provider.dart';
import 'package:tulink_flutter/features/auth/presentation/providers/auth_provider.dart';
import 'package:tulink_flutter/features/convoy/presentation/providers/convoy_provider.dart';
import 'package:tulink_flutter/features/invites/presentation/pages/invitations_screen.dart';
import 'package:tulink_flutter/features/invites/presentation/providers/invite_provider.dart';
import 'package:tulink_flutter/features/journeys/domain/entities/journey.dart';
import 'package:tulink_flutter/features/journeys/presentation/pages/create_journey_screen.dart';
import 'package:tulink_flutter/features/journeys/presentation/pages/journey_preview_screen.dart';
import 'package:tulink_flutter/features/journeys/presentation/providers/journey_provider.dart';
import 'package:tulink_flutter/features/journeys/presentation/utils/journey_navigation.dart';
import 'package:tulink_flutter/features/profile/presentation/screens/profile_screen.dart';
import 'package:tulink_flutter/core/services/car_toast_service.dart';
import 'package:tulink_flutter/core/services/push_notification_service.dart';
import 'package:tulink_flutter/core/widgets/location_access_sheet.dart';
import 'package:tulink_flutter/core/theme/tulink_colors.dart';
import '../widgets/journey_card.dart';
import '../widgets/journeys_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  static const String routeName = '/dashboard';

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  Timer? _invitePollingTimer;
  StreamSubscription<RemoteMessage>? _pushSub;
  StreamSubscription<RemoteMessage>? _pushTapSub;
  bool _isOpeningInvitations = false;
  int _lastJourneyInviteTick = 0;

  /// Guards the resume-on-launch prompt so it fires at most once per app
  /// session — not on every home rebuild, tab switch, or background/resume.
  bool _resumePrompted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Prime + request location first (right after login lands on home), with
      // an explainer sheet to lift grant rates, so it's already granted by the
      // time a journey starts. Awaited and sequenced BEFORE the push prompt
      // below so two system permission dialogs never stack. The convoy flow
      // still hard-gates location before starting.
      if (mounted) {
        await maybeShowLocationPriming(context);
      }

      // Initialise push notifications (FCM) now that we're authenticated, and
      // refresh the invite list when a push arrives so invites show up live.
      if (mounted) {
        final push = context.read<PushNotificationService>();
        await push.init();
        if (!mounted) return;
        _pushSub = push.messages.listen(_onPushMessage);
        _pushTapSub = push.notificationTaps.listen(_onNotificationTap);
        final initialTap = push.takeInitialNotificationTap();
        if (initialTap != null) _onNotificationTap(initialTap);

        // Open the WebSocket user channel for instant invite delivery while the
        // app is open. FCM covers the backgrounded/closed case.
        unawaited(context.read<ConvoyProvider>().startUserChannel());
      }

      await _refreshData();
      // After refresh, if the server has no active journeys but _currentJourney
      // is still set (e.g. from a previous session), clear it.
      if (mounted) {
        final journeyProvider = context.read<JourneyProvider>();
        if (journeyProvider.currentJourney != null &&
            journeyProvider.currentJourney!.status == JourneyStatus.ACTIVE &&
            journeyProvider.activeJourneys.isEmpty) {
          journeyProvider.clearCurrentJourney();
        }
      }

      // Resume an in-progress journey after a relaunch / force-close: if the
      // server still lists an ACTIVE journey for this user, surface it on home
      // and offer a one-tap return to the live map.
      if (mounted) _maybeResumeActiveJourney();

      _startInvitePolling();
    });
  }

  @override
  void dispose() {
    _invitePollingTimer?.cancel();
    _pushSub?.cancel();
    _pushTapSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// A push arrived while the app is foregrounded on home — refresh the invite
  /// list and surface a brief in-app banner so the user sees it immediately.
  void _onPushMessage(RemoteMessage message) {
    if (!mounted) return;
    context.read<InviteProvider>().refreshInvitationsSilently(force: true);

    final notification = message.notification;
    final text = notification?.title ?? notification?.body;
    if (text != null) {
      CarToastService.showSuccess(text, context: context);
    }
  }

  void _onNotificationTap(RemoteMessage message) {
    if (!mounted || message.data['type'] != 'JOURNEY_INVITE') return;
    context.read<InviteProvider>().refreshInvitationsSilently(force: true);
    if (_isOpeningInvitations) return;
    _isOpeningInvitations = true;
    Navigator.of(context)
        .pushNamed(InvitationsScreen.routeName)
        .whenComplete(() => _isOpeningInvitations = false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<InviteProvider>().refreshInvitationsSilently(force: true);
      // The invite-delivery socket is evicted by the server heartbeat monitor
      // while the app is suspended; reconnect it so live invites resume.
      unawaited(context.read<ConvoyProvider>().onAppResumed());
    }
  }

  void _startInvitePolling() {
    _invitePollingTimer?.cancel();
    _invitePollingTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) {
        context.read<InviteProvider>().refreshInvitationsSilently();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final convoyProvider = context.watch<ConvoyProvider>();

    // A journey-invite arrived over the WebSocket user channel — refresh the
    // invite list and surface a banner without a reload.
    if (convoyProvider.journeyInviteTick != _lastJourneyInviteTick) {
      _lastJourneyInviteTick = convoyProvider.journeyInviteTick;
      final invite = convoyProvider.lastJourneyInvite;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<InviteProvider>().refreshInvitationsSilently(force: true);
        final journeyName = invite?['journeyName'] as String?;
        CarToastService.showSuccess(
          journeyName != null
              ? 'New invite: $journeyName'
              : 'You have a new journey invite',
          context: context,
        );
      });
    }

    if (convoyProvider.pendingJourneyStartedId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final journeyId = convoyProvider.pendingJourneyStartedId;
        if (journeyId == null) return;
        convoyProvider.consumeJourneyStartedEvent();
        context.read<JourneyProvider>().fetchJourneyById(journeyId).then((
          _,
        ) async {
          if (!mounted) return;
          // Gate location before starting coordination — matches
          // journey_preview_screen's handler for the same event. Both screens
          // can be mounted at once (this one underneath, in the Navigator
          // stack) and react to the same journey-started broadcast; routing
          // both through the shared guarded permission request (see
          // LocationPermissionService.requestPermissionGuarded) keeps a
          // concurrent gate from stacking a second native dialog.
          if (!await ensureLocationReady(context)) return;
          if (!mounted) return;
          context.read<ConvoyProvider>().startCoordination(journeyId);
          Navigator.of(context).pushNamed('/mapview');
        });
      });
    }
  }

  Future<void> _refreshData() async {
    await Future.wait([
      context.read<AnalyticsProvider>().loadRecentJourneys(),
      context.read<JourneyProvider>().fetchActiveJourneys(),
      context.read<AnalyticsProvider>().loadJourneyHistory(),
      context.read<InviteProvider>().fetchInvitations(),
    ]);

    // Pre-join WebSocket room for any active journey we're a member of so
    // we receive the journey-started event while waiting on the home screen.
    if (!mounted) return;
    _preJoinActiveJourneyRoom();
  }

  void _preJoinActiveJourneyRoom() {
    final journeyProvider = context.read<JourneyProvider>();
    final convoyProvider = context.read<ConvoyProvider>();
    final authProvider = context.read<AuthProvider>();
    final userId = authProvider.user?.id;
    if (userId == null) return;

    for (final journey in journeyProvider.activeJourneys) {
      convoyProvider.joinJourneyRoom(journey.id);
      break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;
    final user = context.watch<AuthProvider>().user;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refreshData,
          color: colors.electricRed,
          backgroundColor: colors.cardDark,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'WELCOME BACK,',
                          style: TextStyle(
                            color: colors.silver,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          (user?.name ?? 'Champion').toUpperCase(),
                          style: TextStyle(
                            color: colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        // Invitations bell
                        Consumer<InviteProvider>(
                          builder: (context, inviteProvider, _) {
                            final count = inviteProvider.pendingInvitationCount;
                            return Semantics(
                              button: true,
                              label: count == 0
                                  ? 'Journey invitations, none pending'
                                  : 'Journey invitations, $count pending',
                              child: GestureDetector(
                                onTap: () => Navigator.of(
                                  context,
                                ).pushNamed(InvitationsScreen.routeName),
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: colors.cardDark,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: colors.brushedSteel
                                              .withOpacity(0.4),
                                        ),
                                      ),
                                      child: Icon(
                                        Icons.mail_outline,
                                        color: colors.silver,
                                        size: 20,
                                      ),
                                    ),
                                    if (count > 0)
                                      Positioned(
                                        top: -4,
                                        right: -4,
                                        child: Container(
                                          width: 18,
                                          height: 18,
                                          decoration: BoxDecoration(
                                            color: colors.electricRed,
                                            shape: BoxShape.circle,
                                          ),
                                          child: Center(
                                            child: Text(
                                              count > 9 ? '9+' : '$count',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 10),
                        // Profile avatar
                        GestureDetector(
                          onTap: _navigateToProfile,
                          child: SizedBox(
                            width: 54,
                            height: 54,
                            child: Stack(
                              children: [
                                // Main Avatar Container
                                Container(
                                  width: 54,
                                  height: 54,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: colors.electricRed,
                                      width: 3,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: colors.electricRed.withValues(
                                          alpha: 0.3,
                                        ),
                                        blurRadius: 10,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: Container(
                                    margin: const EdgeInsets.all(3),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: LinearGradient(
                                        colors: [
                                          colors.brushedSteel,
                                          colors.brushedSteel.withValues(
                                            alpha: 0.8,
                                          ),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                    ),
                                    child: Center(
                                      child: Text(
                                        _getInitials(user?.name ?? 'User'),
                                        style: TextStyle(
                                          color: colors.white,
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 1,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),

                                // Online Status Indicator
                                Positioned(
                                  bottom: 3,
                                  right: 3,
                                  child: Container(
                                    width: 14,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.green,
                                      border: Border.all(
                                        color: colors.carbonBlack,
                                        width: 2,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.green.withValues(
                                            alpha: 0.4,
                                          ),
                                          blurRadius: 6,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ], // inner Row children (bell + avatar)
                    ), // inner Row
                  ],
                ),

                const SizedBox(height: 32),

                // Journey Action Cards - Show active journey card OR create/join cards
                Consumer<JourneyProvider>(
                  builder: (context, journeyProvider, child) {
                    final hasOpenJourney =
                        journeyProvider.currentJourney != null &&
                        (journeyProvider.currentJourney!.status ==
                                JourneyStatus.PENDING ||
                            journeyProvider.currentJourney!.status ==
                                JourneyStatus.ACTIVE);

                    if (hasOpenJourney) {
                      return _buildActiveJourneyCard(
                        colors,
                        journeyProvider.currentJourney,
                      );
                    } else {
                      return Column(
                        children: [
                          JourneyCard(
                            title: 'Start a journey',
                            description: 'Create a convoy and lead the pack',
                            colors: [
                              colors.electricRed,
                              colors.electricRed.withValues(alpha: 0.8),
                            ],
                            iconText: '🏁',
                            onTap: () {
                              Navigator.of(
                                context,
                              ).pushNamed(CreateJourneyScreen.routeName);
                            },
                          ),
                          const SizedBox(height: 16),
                          JourneyCard(
                            title: 'Join a journey',
                            description: 'Enter a code and join the formation',
                            borderColor: colors.electricRed,
                            onTap: _showJoinJourneyCodeSheet,
                          ),
                        ],
                      );
                    }
                  },
                ),

                const SizedBox(height: 32),

                // Active Journeys Section
                Consumer<JourneyProvider>(
                  builder: (context, journeyProvider, child) {
                    return JourneysCard(
                      title: 'Active Journeys',
                      journeys: journeyProvider.activeJourneys,
                      showParticipants: true,
                      isLoading:
                          journeyProvider.isLoading &&
                          journeyProvider.activeJourneys.isEmpty,
                      onJourneyTap: _continueActiveJourney,
                    );
                  },
                ),

                const SizedBox(height: 32),

                // Recent Journeys Section
                Consumer<AnalyticsProvider>(
                  builder: (context, analyticsProvider, child) {
                    if (analyticsProvider.isLoading &&
                        analyticsProvider.recentJourneys.isEmpty) {
                      return Container(
                        height: 150,
                        alignment: Alignment.center,
                        child: const CircularProgressIndicator(),
                      );
                    }

                    if (analyticsProvider.error != null &&
                        analyticsProvider.recentJourneys.isEmpty) {
                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: colors.cardDark,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: colors.brushedSteel.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: colors.electricRed,
                              size: 32,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Failed to load recent journeys',
                              style: TextStyle(
                                color: colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            GestureDetector(
                              onTap: () =>
                                  analyticsProvider.refreshRecentJourneys(),
                              child: Text(
                                'Tap to retry',
                                style: TextStyle(
                                  color: colors.electricRed,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return JourneysCard(
                      title: 'Recent Journeys',
                      journeys: analyticsProvider.recentJourneys,
                      showParticipants: false,
                      isLoading:
                          analyticsProvider.isLoading &&
                          analyticsProvider.recentJourneys.isEmpty,
                      onSeeAll: _navigateToJourneyHistory,
                      onJourneyTap: _navigateToJourneyDetails,
                    );
                  },
                ),

                const SizedBox(height: 120), // Space for Navbar and FAB
              ],
            ),
          ),
        ),
      ),
      // floatingActionButton: FloatingActionButton.extended(
      //   onPressed: () => Navigator.of(context).pushNamed(JourneyHistoryScreen.routeName),
      //   label: const Text("Journey History"),
      //   icon: const Icon(Icons.play_arrow_rounded),
      // ),
    );
  }

  void _navigateToJourneyHistory() {
    Navigator.of(context).pushNamed('/journey-history');
  }

  Future<void> _showJoinJourneyCodeSheet() async {
    final colors = Theme.of(context).tulinkColors;
    final controller = TextEditingController();
    var submitting = false;
    String? validationError;

    final joinedJourney = await showModalBottomSheet<Journey>(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          Future<void> submit() async {
            if (submitting) return;
            final code = controller.text.trim().toUpperCase();
            if (!RegExp(r'^[2-9A-HJ-NP-Z]{10}$').hasMatch(code)) {
              setSheetState(
                () => validationError = 'Enter a valid 10-character code',
              );
              return;
            }

            setSheetState(() {
              submitting = true;
              validationError = null;
            });
            final provider = context.read<JourneyProvider>();
            final journey = await provider.joinJourneyByCode(code);
            if (!sheetContext.mounted) return;
            if (journey == null) {
              setSheetState(() {
                submitting = false;
                validationError =
                    provider.error ?? 'Unable to join this journey';
              });
              return;
            }
            Navigator.of(sheetContext).pop(journey);
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              16,
              24,
              MediaQuery.viewInsetsOf(sheetContext).bottom + 24,
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colors.silver.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'JOIN A JOURNEY',
                    style: TextStyle(
                      color: colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter the 10-character code shared by the convoy leader.',
                    style: TextStyle(color: colors.silver, fontSize: 14),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    textCapitalization: TextCapitalization.characters,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 4,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp('[2-9A-HJ-NP-Za-hj-np-z]'),
                      ),
                      LengthLimitingTextInputFormatter(10),
                    ],
                    decoration: InputDecoration(
                      hintText: 'ENTER CODE',
                      errorText: validationError,
                      filled: true,
                      fillColor: colors.carbonBlack,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onChanged: (_) {
                      if (validationError != null) {
                        setSheetState(() => validationError = null);
                      }
                    },
                    onSubmitted: submitting ? null : (_) => submit(),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: submitting ? null : submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.electricRed,
                      minimumSize: const Size.fromHeight(54),
                    ),
                    child: submitting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('JOIN CONVOY'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    controller.dispose();
    if (!mounted || joinedJourney == null) return;

    if (joinedJourney.status == JourneyStatus.ACTIVE) {
      if (!await ensureLocationReady(context)) {
        if (mounted) {
          context.showWarningToast(
            'Journey joined. Enable location to enter the live convoy.',
          );
        }
        return;
      }
      if (!mounted) return;
      await context.read<ConvoyProvider>().startCoordination(joinedJourney.id);
      if (mounted) Navigator.of(context).pushNamed('/mapview');
      return;
    }

    final listening = await context.read<ConvoyProvider>().joinJourneyRoom(
      joinedJourney.id,
    );
    if (!mounted) return;
    if (!listening) {
      context.showWarningToast('Joined. Live updates are reconnecting.');
    }
    Navigator.of(
      context,
    ).pushNamed(JourneyPreviewScreen.routeName, arguments: joinedJourney.id);
  }

  void _navigateToJourneyDetails(dynamic journey) {
    if (journey is Journey) {
      JourneyNavigation.open(context, journey);
    }
  }

  void _navigateToJourneyPreview(String journeyId) {
    Navigator.of(context).pushNamed('/journey-preview', arguments: journeyId);
  }

  /// Continue an open journey. Pending journeys return to preview; active
  /// journeys return to the live map.
  void _continueActiveJourney(dynamic journey) {
    final journeyProvider = context.read<JourneyProvider>();

    // Set this journey as the current journey
    if (journey is Journey) {
      journeyProvider.setCurrentJourney(journey);
      if (journey.status == JourneyStatus.PENDING) {
        _navigateToJourneyPreview(journey.id);
        return;
      }
    }

    // Navigate directly to map screen for active journey
    Navigator.of(context).pushNamed('/mapview');
  }

  /// On launch, if the server still reports an ACTIVE journey for this user
  /// (the journey kept running while the app was backgrounded/force-closed),
  /// promote it to the current journey so the home banner shows, and offer a
  /// one-tap return to the live map. The map screen re-starts convoy
  /// coordination on mount, so resuming is just navigation.
  void _maybeResumeActiveJourney() {
    if (_resumePrompted) return;

    final journeyProvider = context.read<JourneyProvider>();

    // Prefer an already-current active journey; otherwise the first ACTIVE
    // journey the server returned for this user.
    Journey? resume;
    final current = journeyProvider.currentJourney;
    if (current != null && current.status == JourneyStatus.ACTIVE) {
      resume = current;
    } else {
      for (final j in journeyProvider.activeJourneys) {
        if (j.status == JourneyStatus.ACTIVE) {
          resume = j;
          break;
        }
      }
    }
    if (resume == null) return;

    _resumePrompted = true;

    // Surface it on home (active-journey card) even if the user dismisses the
    // prompt — a cold launch leaves currentJourney null otherwise.
    journeyProvider.setCurrentJourney(resume);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showResumeJourneySheet(resume!);
    });
  }

  Future<void> _showResumeJourneySheet(Journey journey) async {
    final colors = Theme.of(context).tulinkColors;

    final shouldResume = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: colors.cardDark,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: colors.silver.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: colors.electricRed.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.navigation_rounded,
                  color: colors.electricRed,
                  size: 32,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Journey in progress',
                style: TextStyle(
                  color: colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'You have a live journey to '
                '${journey.destinationAddress.isNotEmpty ? journey.destinationAddress : 'your destination'}. '
                'Jump back in to keep your convoy in sync.',
                style: TextStyle(
                  color: colors.silver,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.electricRed,
                    foregroundColor: colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => Navigator.of(sheetContext).pop(true),
                  child: const Text(
                    'Resume journey',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 48,
                child: TextButton(
                  onPressed: () => Navigator.of(sheetContext).pop(false),
                  child: Text(
                    'Not now',
                    style: TextStyle(
                      color: colors.silver,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (shouldResume == true && mounted) {
      _continueActiveJourney(journey);
    }
  }

  void _navigateToProfile() {
    Navigator.of(context).pushNamed(ProfileScreen.routeName);
  }

  /// Build the active journey in progress card
  Widget _buildActiveJourneyCard(TulinkColors colors, Journey? journey) {
    final isPending = journey?.status == JourneyStatus.PENDING;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colors.electricRed,
            colors.electricRed.withValues(alpha: 0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.electricRed, width: 2),
        boxShadow: [
          BoxShadow(
            color: colors.electricRed.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Racing flag icon
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Text('🏁', style: TextStyle(fontSize: 28)),
            ),
          ),
          const SizedBox(width: 16),
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isPending
                      ? 'JOURNEY READY TO MANAGE'
                      : 'ACTIVE JOURNEY IN PROGRESS',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isPending
                      ? 'Your convoy is waiting for participants or departure'
                      : 'You are currently in an active convoy journey',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 12),
                // Continue journey button
                GestureDetector(
                  onTap: () => _continueActiveJourney(journey),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isPending ? 'MANAGE JOURNEY →' : 'CONTINUE JOURNEY →',
                      style: TextStyle(
                        color: colors.electricRed,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getInitials(String name) {
    final nameParts = name.split(' ');
    if (nameParts.length >= 2) {
      return '${nameParts[0][0]}${nameParts[1][0]}'.toUpperCase();
    } else if (nameParts.isNotEmpty) {
      return nameParts[0][0].toUpperCase();
    }
    return 'U';
  }
}
