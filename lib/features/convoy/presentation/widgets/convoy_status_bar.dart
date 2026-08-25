import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/entities/convoy_snapshot.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/theme/tulink_colors.dart';

/// Top status bar widget showing convoy progress and member count
/// Displays journey status, member count, and connection state
class ConvoyStatusBar extends StatefulWidget {
  const ConvoyStatusBar({
    super.key,
    required this.snapshot,
    required this.connectionState,
    this.rosterMemberCount,
    this.onTap,
    this.onBack,
    this.locationFailure,
    this.onRetryLocation,
    this.journeyId,
    this.connectionAttemptId = 0,
    this.onReconnect,
    this.isReconnecting = false,
  });

  /// How long the bar is allowed to claim it is still connecting before it
  /// admits failure. Without this bound, any condition that prevented a
  /// snapshot rendered as an indefinite, unactionable "CONNECTING...".
  static const Duration connectingGracePeriod = Duration(seconds: 12);

  final ConvoySnapshot? snapshot;

  /// Accepted journey participants, including the current user. Unlike a
  /// location snapshot this remains authoritative before everyone has shared
  /// their first position.
  final int? rosterMemberCount;
  final ConvoyConnectionState connectionState;
  final VoidCallback? onTap;
  final VoidCallback? onBack;

  /// Location trouble, reported independently of convoy connectivity: the
  /// client can be fully joined to the room while having no GPS fix.
  final Failure? locationFailure;
  final VoidCallback? onRetryLocation;

  /// Journey currently being coordinated. A change resets the watchdog, so a
  /// new journey never inherits the previous one's timed-out state.
  final String? journeyId;

  /// Monotonic id of the current connection attempt.
  ///
  /// Incremented by the owner on every reconnect. `journeyId` alone is not
  /// enough: retrying the *same* journey is a new attempt and must start a
  /// fresh bounded window rather than inherit the previous timeout.
  final int connectionAttemptId;

  /// Retry the convoy connection. Distinct from [onRetryLocation]: the socket
  /// and the GPS fix fail independently and are recovered independently.
  final VoidCallback? onReconnect;

  /// True while a reconnect attempt is in flight, so the action can show
  /// progress and refuse concurrent taps.
  final bool isReconnecting;

  @override
  State<ConvoyStatusBar> createState() => _ConvoyStatusBarState();
}

class _ConvoyStatusBarState extends State<ConvoyStatusBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  /// Fires once the grace period lapses with no snapshot, flipping the bar from
  /// "connecting" to an actionable failure state.
  ///
  /// The watchdog keys off snapshot *absence*, not arrival: it is armed
  /// whenever there is no snapshot and no terminal error, cancelled when a
  /// snapshot lands, and re-armed if a snapshot is subsequently lost. An
  /// earlier version re-armed only on arrival, so losing a snapshot left the
  /// bar showing `CONNECTING...` forever — the original defect in a new shape.
  Timer? _connectingTimer;
  bool _connectingTimedOut = false;

  /// True only when a snapshot exists **and** the socket is actually connected.
  ///
  /// `connecting` deliberately does NOT qualify: a snapshot retained while the
  /// socket is still coming up describes the convoy as it was, not as it is, so
  /// presenting it as healthy status would again show confident data over an
  /// unconfirmed connection.
  bool get _hasLiveSnapshot =>
      widget.snapshot != null &&
      widget.connectionState == ConvoyConnectionState.connected;

  @override
  void initState() {
    super.initState();

    _syncWatchdog(attemptChanged: true);

    // Setup pulsing animation for status indicator
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _pulseController.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant ConvoyStatusBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different journey OR a new attempt on the same journey is a fresh
    // connection attempt: forget any previous timeout. Direct field mutation is
    // safe here — a build always follows.
    _syncWatchdog(
      attemptChanged:
          widget.journeyId != oldWidget.journeyId ||
          widget.connectionAttemptId != oldWidget.connectionAttemptId,
    );
  }

  void _cancelWatchdog() {
    _connectingTimer?.cancel();
    _connectingTimer = null;
  }

  void _armWatchdog() {
    if (_connectingTimer != null) return; // already counting down
    _connectingTimer = Timer(ConvoyStatusBar.connectingGracePeriod, () {
      _connectingTimer = null;
      if (!mounted || _hasLiveSnapshot) return;
      setState(() => _connectingTimedOut = true);
    });
  }

  /// Reconcile the watchdog with the current state.
  void _syncWatchdog({required bool attemptChanged}) {
    if (attemptChanged) {
      _cancelWatchdog();
      _connectingTimedOut = false;
    }

    if (_hasLiveSnapshot) {
      // Genuinely connected. Stop waiting and clear any previous timeout so
      // that losing this snapshot later starts a fresh grace period rather
      // than jumping straight back to a stale failure.
      _cancelWatchdog();
      _connectingTimedOut = false;
      return;
    }

    if (widget.connectionState == ConvoyConnectionState.error) {
      // Already actionable; counting down to a weaker message helps nobody.
      _cancelWatchdog();
      return;
    }

    // Waiting: connecting, reconnecting, disconnected, or holding a stale
    // snapshot behind a dead socket. All are bounded.
    if (!_connectingTimedOut) _armWatchdog();
  }

  @override
  void dispose() {
    _cancelWatchdog();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<TulinkColors>()!;

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        margin: const EdgeInsets.only(top: 50, left: 16, right: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: colors.surface.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.divider),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            if (widget.onBack != null) ...[
              // A real button rather than a bare GestureDetector: it was
              // unlabelled and therefore invisible to screen readers and to
              // automated testing, and its 34pt box is below the 44pt minimum
              // touch target. The InkWell keeps the visual circle while giving
              // it a proper hit area and semantics.
              Semantics(
                label: 'Hide convoy controls',
                button: true,
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: IconButton(
                    onPressed: widget.onBack,
                    padding: EdgeInsets.zero,
                    tooltip: 'Hide convoy controls',
                    icon: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: colors.warmSand,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.arrow_back,
                        color: colors.ink,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],
            _buildStatusIndicator(colors),
            const SizedBox(width: 10),
            Expanded(child: _buildStatusInfo(colors)),
            _buildConnectionIndicator(colors),
          ],
        ),
      ),
    );
  }

  /// Build the pulsing status dot
  Widget _buildStatusIndicator(TulinkColors colors) {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: _getStatusColor(colors).withOpacity(_pulseAnimation.value),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: _getStatusColor(colors).withOpacity(0.3),
                blurRadius: 4,
                spreadRadius: 1,
              ),
            ],
          ),
        );
      },
    );
  }

  /// Build status text and member count
  Widget _buildStatusInfo(TulinkColors colors) {
    final snapshot = widget.snapshot;
    final String statusText;
    String memberText = '';

    // Connectivity is authoritative. A snapshot only proves what the convoy
    // looked like when it last arrived — presenting it as live while the
    // connection is down showed users a confident "SOLO JOURNEY" over dead
    // data and hid the Reconnect action behind a `snapshot == null` guard.
    if (_hasLiveSnapshot && snapshot != null) {
      statusText = _getStatusText(snapshot, _effectiveMemberCount(snapshot));
      memberText = _getMemberCountText(
        snapshot,
        _effectiveMemberCount(snapshot),
      );
    } else {
      switch (widget.connectionState) {
        case ConvoyConnectionState.error:
          statusText = 'CONNECTION ERROR';
        case ConvoyConnectionState.reconnecting:
          // A reconnect that never lands is just as unactionable as an
          // indefinite "CONNECTING..." — it must time out too.
          statusText = _connectingTimedOut
              ? 'NOT CONNECTED'
              : 'RECONNECTING...';
        case ConvoyConnectionState.connected:
        case ConvoyConnectionState.connecting:
        case ConvoyConnectionState.disconnected:
          // Deliberately not "CONNECTING..." once the grace period lapses:
          // claiming progress would be a lie the user cannot act on.
          statusText = _connectingTimedOut ? 'NOT CONNECTED' : 'CONNECTING...';
      }
      // Stale membership is still useful context, but only when marked as
      // such — never as evidence that the convoy is reachable.
      if (snapshot != null) {
        memberText =
            'Last known: ${_getMemberCountText(snapshot, _effectiveMemberCount(snapshot))}';
      }
    }

    final locationFailure = widget.locationFailure;
    // Recoverable whenever the connection is not currently healthy: a hard
    // error, a lapsed grace period, or a stale snapshot behind a dead socket.
    final canReconnect =
        !_hasLiveSnapshot &&
        widget.onReconnect != null &&
        (widget.connectionState == ConvoyConnectionState.error ||
            widget.connectionState == ConvoyConnectionState.reconnecting ||
            _connectingTimedOut ||
            snapshot != null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                statusText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: colors.ink,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            if (canReconnect) ...[
              const SizedBox(width: 8),
              _ReconnectAction(
                colors: colors,
                isReconnecting: widget.isReconnecting,
                onPressed: widget.onReconnect,
              ),
            ],
          ],
        ),
        if (memberText.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            memberText,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: colors.muted,
              letterSpacing: 0.3,
            ),
          ),
        ],
        // Location trouble is its own line so it never reads as a convoy
        // connectivity problem — the two fail independently.
        if (locationFailure != null) ...[
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.location_disabled,
                size: 13,
                color: colors.sunsetOrange,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  locationFailure.message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: colors.sunsetOrange,
                  ),
                ),
              ),
              if (widget.onRetryLocation != null) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: widget.onRetryLocation,
                  child: Semantics(
                    button: true,
                    label: 'Retry location',
                    child: Text(
                      'Retry',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: colors.deepTeal,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }

  /// Build connection state indicator
  Widget _buildConnectionIndicator(TulinkColors colors) {
    IconData icon;
    Color iconColor;

    switch (widget.connectionState) {
      case ConvoyConnectionState.connected:
        icon = Icons.signal_wifi_4_bar;
        iconColor = Colors.green;
        break;
      case ConvoyConnectionState.connecting:
      case ConvoyConnectionState.reconnecting:
        icon = Icons.signal_wifi_0_bar;
        iconColor = Colors.orange;
        break;
      case ConvoyConnectionState.error:
        icon = Icons.signal_wifi_off;
        iconColor = Colors.red;
        break;
      case ConvoyConnectionState.disconnected:
        icon = Icons.signal_wifi_0_bar;
        iconColor = colors.muted;
        break;
    }

    return Icon(icon, size: 18, color: iconColor);
  }

  /// Get status indicator color based on convoy state
  Color _getStatusColor(TulinkColors colors) {
    final snapshot = widget.snapshot;

    if (snapshot == null) return colors.muted;

    if (snapshot.laggingMembers.isNotEmpty) return Colors.orange;
    if (snapshot.allMembersArrived) return Colors.blue;
    if (snapshot.movingMemberCount > 0) return colors.routeTeal;

    return Colors.green;
  }

  /// Get status text based on convoy state
  int _effectiveMemberCount(ConvoySnapshot snapshot) {
    final roster = widget.rosterMemberCount ?? 0;
    return roster > snapshot.totalMembers ? roster : snapshot.totalMembers;
  }

  String _getStatusText(ConvoySnapshot snapshot, int totalMembers) {
    if (snapshot.allMembersArrived) return 'ALL ARRIVED';
    if (snapshot.laggingMembers.isNotEmpty) return 'MEMBERS LAGGING';
    if (snapshot.movingMemberCount > 0) return 'IN PROGRESS';

    // For solo journeys, show journey status instead of waiting
    if (totalMembers <= 1) return 'SOLO JOURNEY';

    if (!snapshot.hasActiveMembers) return 'WAITING';

    return 'CONVOY READY';
  }

  /// Get member count text
  String _getMemberCountText(ConvoySnapshot snapshot, int total) {
    final active = snapshot.activeMemberCount;
    final moving = snapshot.movingMemberCount;

    if (total == 0) return 'NO MEMBERS';
    if (total == 1) return 'SOLO MODE';

    String baseText = '$total MEMBERS';

    if (active < total) {
      baseText += ' • $active ACTIVE';
    }

    if (moving > 0) {
      baseText += ' • $moving MOVING';
    }

    return baseText;
  }
}

/// Explicit, accessible convoy reconnect control.
///
/// Separate from "Retry location": the socket and the GPS fix fail for
/// different reasons and are recovered independently. Previously the only way
/// to act on a dead convoy connection was to guess that tapping the whole
/// status bar opened a sheet.
class _ReconnectAction extends StatelessWidget {
  const _ReconnectAction({
    required this.colors,
    required this.isReconnecting,
    required this.onPressed,
  });

  final TulinkColors colors;
  final bool isReconnecting;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    // TextButton already exposes button semantics, enabled state, a tap action
    // and a focusable node, with the visible label as its accessible name —
    // wrapping it in another Semantics only competes with that.
    return Tooltip(
      message: isReconnecting
          ? 'Reconnecting to convoy'
          : 'Reconnect to convoy',
      child: SizedBox(
        height: 44, // minimum comfortable touch target
        child: TextButton.icon(
          // Disabled while in flight, so a second tap cannot start a
          // concurrent reconnect.
          onPressed: isReconnecting ? null : onPressed,
          style: TextButton.styleFrom(
            foregroundColor: colors.deepTeal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            minimumSize: const Size(0, 44),
            tapTargetSize: MaterialTapTargetSize.padded,
          ),
          icon: isReconnecting
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(colors.deepTeal),
                  ),
                )
              : const Icon(Icons.refresh_rounded, size: 16),
          label: Text(
            isReconnecting ? 'Reconnecting' : 'Reconnect',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}
