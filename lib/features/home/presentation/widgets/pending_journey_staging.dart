import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/errors/failure.dart';
import '../../../journeys/domain/entities/journey.dart';
import '../../../journeys/presentation/widgets/pending_journey_overlay.dart';

/// Joins a staged journey's live-update room, listener-only.
///
/// Returns true once the server has confirmed room membership. Never requests
/// GPS: a member who has denied location must still receive `journey-started`.
typedef JoinPendingRoom = Future<bool> Function(String journeyId);

/// Staging chrome plus the room-membership state machine behind it.
///
/// This widget exists so the recovery path is *production* wiring rather than
/// something each host re-derives. [PendingJourneyOverlay] already supported
/// `hasRoomFailure` / `onReconnectRoom` / `isReconnectingRoom`, but no host
/// passed them, so the explicit listener-only reconnect was unreachable in the
/// shipped app while every widget test of the overlay still passed.
///
/// The states it publishes are held to one rule: **`isReconnectingRoom` is true
/// only while a join is actually running or a bounded retry is actually
/// scheduled.** Anything else is the app claiming to reconnect while nothing
/// is.
class PendingJourneyStaging extends StatefulWidget {
  const PendingJourneyStaging({
    super.key,
    required this.journey,
    required this.isLeader,
    required this.joinRoom,
    required this.onDismiss,
    this.leaderName,
    this.onStart,
    this.onCancelJourney,
    this.onLeaveJourney,
    this.onShareCode,
    this.onInvitePeople,
    this.isBusy = false,
    this.locationFailure,
    this.onRetryLocation,
    this.hasStartFailure = false,
    this.onRetryStart,
    this.maxAutomaticRetries = 2,
    this.retryBackoff = defaultRetryBackoff,
  });

  /// Bounded automatic backoff before the user is handed an explicit control.
  static Duration defaultRetryBackoff(int attempt) =>
      Duration(milliseconds: 600 * (1 << attempt));

  final Journey journey;
  final bool isLeader;

  /// Listener-only room join. Called on mount, on journey change, on each
  /// bounded automatic retry, and on the user's explicit Reconnect.
  final JoinPendingRoom joinRoom;

  final VoidCallback onDismiss;
  final String? leaderName;
  final VoidCallback? onStart;
  final VoidCallback? onCancelJourney;
  final VoidCallback? onLeaveJourney;
  final VoidCallback? onShareCode;
  final VoidCallback? onInvitePeople;
  final bool isBusy;

  /// Location publishing problem — surfaced separately from the connection
  /// problem below, because they fail for different reasons and have different
  /// remedies.
  final Failure? locationFailure;
  final VoidCallback? onRetryLocation;

  /// True when the leader's start was received but this device could not load
  /// the journey after its bounded retries.
  ///
  /// Surfaced through the same recovery control rather than a toast that says
  /// "Retrying…" while nothing is scheduled.
  final bool hasStartFailure;

  /// Re-attempt the pending `journey-started` transition. Invoked by Reconnect
  /// alongside the room rejoin, because a device that missed the start is
  /// usually a device that lost the room.
  final VoidCallback? onRetryStart;

  final int maxAutomaticRetries;
  final Duration Function(int attempt) retryBackoff;

  @override
  State<PendingJourneyStaging> createState() => PendingJourneyStagingState();
}

class PendingJourneyStagingState extends State<PendingJourneyStaging> {
  /// Monotonic token for join attempts. A continuation whose token is no longer
  /// current abandons itself instead of writing state for a journey — or an
  /// attempt — that has been superseded.
  int _attemptSeq = 0;

  /// The journey the newest attempt belongs to.
  String? _attemptJourneyId;

  /// True while a join is running **or** a bounded retry is scheduled.
  bool _isRecovering = false;

  /// True once a join has failed. Stays set across an explicit retry so the
  /// failure card — and its progress state — remain visible while the retry
  /// runs, and clears only on a confirmed join.
  bool _hasRoomFailure = false;

  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    _startAttempt(widget.journey.id, resetFailure: true);
  }

  @override
  void didUpdateWidget(covariant PendingJourneyStaging oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different journey is being staged: the previous attempt no longer owns
    // this widget, so it is invalidated rather than left to finish and report
    // its result against the new journey.
    if (oldWidget.journey.id != widget.journey.id) {
      _startAttempt(widget.journey.id, resetFailure: true);
    }
  }

  @override
  void dispose() {
    // Invalidate any continuation still in flight before the state goes away.
    _attemptSeq++;
    _retryTimer?.cancel();
    super.dispose();
  }

  void _startAttempt(String journeyId, {required bool resetFailure}) {
    _retryTimer?.cancel();
    final token = ++_attemptSeq;
    _attemptJourneyId = journeyId;
    _apply(recovering: true, failed: resetFailure ? false : _hasRoomFailure);
    unawaited(_join(journeyId, token, 0));
  }

  Future<void> _join(String journeyId, int token, int attempt) async {
    bool isCurrent() =>
        mounted && _attemptSeq == token && _attemptJourneyId == journeyId;

    bool joined;
    try {
      joined = await widget.joinRoom(journeyId);
    } catch (_) {
      joined = false;
    }

    // Superseded by a newer journey, an explicit retry, or disposal. This
    // deliberately does **not** clear the recovering flag: whichever attempt
    // superseded us owns it now, and clearing it from here is exactly how the
    // UI got stuck showing "Reconnecting…" with nothing running.
    if (!isCurrent()) return;

    if (joined) {
      _apply(recovering: false, failed: false);
      return;
    }

    if (attempt < widget.maxAutomaticRetries) {
      // A retry really is scheduled, so the recovering state stays truthfully
      // true across the backoff.
      _retryTimer = Timer(widget.retryBackoff(attempt), () {
        if (!isCurrent()) return;
        unawaited(_join(journeyId, token, attempt + 1));
      });
      return;
    }

    // Retries exhausted. Hand the user an explicit control and stop claiming
    // anything is in progress.
    _apply(recovering: false, failed: true);
  }

  void _apply({required bool recovering, required bool failed}) {
    if (_isRecovering == recovering && _hasRoomFailure == failed) return;
    if (!mounted) {
      _isRecovering = recovering;
      _hasRoomFailure = failed;
      return;
    }
    setState(() {
      _isRecovering = recovering;
      _hasRoomFailure = failed;
    });
  }

  /// The user's explicit recovery action.
  ///
  /// Listener-only: it rejoins the room and re-attempts a missed start. It
  /// never asks for location and never begins publishing — the journey has not
  /// started yet, and a member with location denied must still be able to
  /// recover their connection.
  void _reconnect() {
    if (_isRecovering) return;
    widget.onRetryStart?.call();
    _startAttempt(widget.journey.id, resetFailure: false);
  }

  @override
  Widget build(BuildContext context) {
    final showFailure = _hasRoomFailure || widget.hasStartFailure;
    return PendingJourneyOverlay(
      journey: widget.journey,
      isLeader: widget.isLeader,
      leaderName: widget.leaderName,
      isBusy: widget.isBusy,
      locationFailure: widget.locationFailure,
      onRetryLocation: widget.onRetryLocation,
      onDismiss: widget.onDismiss,
      onStart: widget.onStart,
      onCancelJourney: widget.onCancelJourney,
      onLeaveJourney: widget.onLeaveJourney,
      onShareCode: widget.onShareCode,
      onInvitePeople: widget.onInvitePeople,
      hasRoomFailure: showFailure,
      isReconnectingRoom: _isRecovering,
      onReconnectRoom: _reconnect,
      roomFailureMessage: widget.hasStartFailure && !_hasRoomFailure
          ? 'The journey has started but could not be loaded on this device. '
                'Reconnect to try again.'
          : null,
    );
  }
}
