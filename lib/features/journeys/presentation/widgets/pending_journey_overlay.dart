import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/theme/tulink_colors.dart';
import '../../domain/entities/journey.dart';

/// Staging chrome for a journey that exists but has not started, rendered over
/// the persistent Home map.
///
/// This replaces navigating to `JourneyPreviewScreen`. Both roles are served by
/// one overlay because they are the same moment in the journey seen from two
/// sides:
///
/// * the **leader** can start, share the invite code, or cancel;
/// * an invited **member** sees who they are waiting for and can leave.
///
/// Crucially the member's view is a real experience, not a placeholder — the
/// destination stays drawn on the map behind it, room membership is already
/// live, and `journey-started` promotes this to the live convoy on the very
/// same map without any navigation.
class PendingJourneyOverlay extends StatelessWidget {
  const PendingJourneyOverlay({
    super.key,
    required this.journey,
    required this.isLeader,
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
    this.hasRoomFailure = false,
    this.onReconnectRoom,
    this.isReconnectingRoom = false,
    this.roomFailureMessage,
  });

  /// Minimum tap target for the recovery control, per the platform guidance
  /// both stores enforce. The Reconnect action is the only way out of a failed
  /// room join, so it must not be a cramped text button.
  static const double kRecoveryControlMinSize = 44;

  /// Stable handle for the listener-only reconnect control.
  ///
  /// The control changes its child between a label and a spinner, so anything
  /// that needs to address it — a test, an accessibility sweep — must not rely
  /// on the visible text.
  static const Key reconnectRoomKey = Key('pending-journey-reconnect-room');

  final Journey journey;
  final bool isLeader;

  /// Collapse the overlay and go back to browsing. Does not touch the journey.
  final VoidCallback onDismiss;

  /// Display name of the leader, when known, for the member's waiting copy.
  final String? leaderName;

  final VoidCallback? onStart;
  final VoidCallback? onCancelJourney;
  final VoidCallback? onLeaveJourney;
  final VoidCallback? onShareCode;
  final VoidCallback? onInvitePeople;

  /// True while a start/cancel/leave call is in flight.
  final bool isBusy;

  /// Location publishing problem, surfaced without blocking membership.
  /// Typed rather than a string so the presentation stays consistent with the
  /// live layer's own recovery UI.
  final Failure? locationFailure;
  final VoidCallback? onRetryLocation;

  /// True when this device is not in the journey's live-update room.
  ///
  /// Deliberately distinct from [locationFailure]: not receiving the leader's
  /// start is a different problem from not being able to publish your own
  /// position, and they have different remedies.
  final bool hasRoomFailure;

  /// Rejoin the live-update room. Listener-only — never requests GPS.
  final VoidCallback? onReconnectRoom;

  /// True while a room rejoin is in flight *or* an automatic retry is
  /// scheduled. It must never be true when nothing is actually retrying —
  /// showing "Reconnecting…" over a dead state is what made the previous
  /// exhausted-retry copy dishonest.
  final bool isReconnectingRoom;

  /// Overrides the default connection-failure copy.
  ///
  /// Supplied when the failure is more specific than "not in the room" — e.g.
  /// the leader has started but this device could not load the journey.
  final String? roomFailureMessage;

  List<Participant> get _participants =>
      (journey.participants ?? const <Participant>[])
          .where((p) => p.status.toUpperCase() != 'LEFT')
          .toList();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;

    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.72,
            ),
            decoration: BoxDecoration(
              color: colors.cardDark,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: colors.brushedSteel.withValues(alpha: 0.3),
              ),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _grabber(colors),
                  const SizedBox(height: 12),
                  _header(colors),
                  const SizedBox(height: 14),
                  _destination(colors),
                  if (journey.isScheduled) ...[
                    const SizedBox(height: 10),
                    _scheduled(colors),
                  ],
                  const SizedBox(height: 16),
                  _participantsSection(colors),
                  if (hasRoomFailure) ...[
                    const SizedBox(height: 14),
                    _roomFailure(colors),
                  ],
                  if (locationFailure != null) ...[
                    const SizedBox(height: 14),
                    _locationFailure(colors),
                  ],
                  const SizedBox(height: 18),
                  _actions(context, colors),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _grabber(TulinkColors colors) => Center(
    child: GestureDetector(
      onTap: onDismiss,
      child: Container(
        width: 42,
        height: 4,
        decoration: BoxDecoration(
          color: colors.brushedSteel,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    ),
  );

  Widget _header(TulinkColors colors) {
    // The member's headline is the whole point of this state: it names who the
    // convoy is waiting on, so the wait never reads as the app being stuck.
    final title = isLeader
        ? journey.name
        : 'Waiting for ${leaderName ?? 'the leader'} to start';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                isLeader
                    ? 'Everyone is notified the moment you start.'
                    : "You're in the convoy. This screen becomes live "
                          'navigation automatically.',
                style: TextStyle(color: colors.silver, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        _statusChip(colors),
      ],
    );
  }

  Widget _statusChip(TulinkColors colors) {
    final label = isLeader ? 'READY' : 'WAITING';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: colors.electricRed.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.electricRed),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: colors.electricRed,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _destination(TulinkColors colors) {
    final subtitle = journey.destinationSubtitle;
    return Row(
      children: [
        Icon(Icons.location_on, color: colors.electricRed, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'DESTINATION',
                style: TextStyle(
                  color: colors.silver,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                journey.destinationLabel,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.silver, fontSize: 12),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _scheduled(TulinkColors colors) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: colors.electricRed.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: colors.electricRed.withValues(alpha: 0.3)),
    ),
    child: Row(
      children: [
        Icon(Icons.event, color: colors.electricRed, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Scheduled for '
            '${DateFormat('EEE, MMM d • HH:mm').format(journey.scheduledFor!.toLocal())}'
            '${journey.autoStart ? ' — starts automatically' : ''}',
            style: TextStyle(color: colors.white, fontSize: 12),
          ),
        ),
      ],
    ),
  );

  Widget _participantsSection(TulinkColors colors) {
    final people = _participants;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(
              'CONVOY',
              style: TextStyle(
                color: colors.silver,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${people.length}',
              style: TextStyle(
                color: colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            if (isLeader && onInvitePeople != null)
              TextButton.icon(
                onPressed: onInvitePeople,
                icon: const Icon(Icons.person_add_alt, size: 16),
                label: const Text('Invite'),
              ),
          ],
        ),
        const SizedBox(height: 6),
        if (people.isEmpty)
          Text(
            'No one else yet — share the code to bring people along.',
            style: TextStyle(color: colors.silver, fontSize: 12),
          )
        else
          ...people.map((person) => _participantRow(person, colors)),
      ],
    );
  }

  Widget _participantRow(Participant person, TulinkColors colors) {
    final isJourneyLeader = person.userId == journey.leaderId;
    final status = person.status.toUpperCase();
    // ACCEPTED/JOINED read as confirmed; anything else is still outstanding.
    final confirmed = status == 'ACCEPTED' || status == 'JOINED';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(
            confirmed ? Icons.check_circle : Icons.schedule,
            size: 16,
            color: confirmed ? colors.electricRed : colors.silver,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              person.displayName ?? 'Traveller',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.white, fontSize: 13),
            ),
          ),
          if (isJourneyLeader)
            Text(
              'LEADER',
              style: TextStyle(
                color: colors.silver,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            )
          else
            Text(
              confirmed ? 'IN' : status,
              style: TextStyle(color: colors.silver, fontSize: 10),
            ),
        ],
      ),
    );
  }

  Widget _roomFailure(TulinkColors colors) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: colors.electricRed.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: colors.electricRed.withValues(alpha: 0.5)),
    ),
    child: Row(
      children: [
        Icon(Icons.wifi_off, color: colors.electricRed, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            roomFailureMessage ??
                'Not receiving live updates — you may miss the start.',
            style: TextStyle(color: colors.white, fontSize: 12),
          ),
        ),
        if (onReconnectRoom != null) ...[
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: kRecoveryControlMinSize,
              minWidth: kRecoveryControlMinSize,
            ),
            child: Semantics(
              button: true,
              enabled: !isReconnectingRoom,
              label: 'Reconnect to live updates',
              child: TextButton(
                key: reconnectRoomKey,
                onPressed: isReconnectingRoom ? null : onReconnectRoom,
                style: TextButton.styleFrom(
                  minimumSize: const Size(
                    kRecoveryControlMinSize,
                    kRecoveryControlMinSize,
                  ),
                  tapTargetSize: MaterialTapTargetSize.padded,
                ),
                child: isReconnectingRoom
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Reconnect'),
              ),
            ),
          ),
        ],
      ],
    ),
  );

  Widget _locationFailure(TulinkColors colors) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Colors.orange.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
    ),
    child: Row(
      children: [
        const Icon(Icons.location_off, color: Colors.orange, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            locationFailure!.message,
            style: TextStyle(color: colors.white, fontSize: 12),
          ),
        ),
        if (onRetryLocation != null)
          TextButton(onPressed: onRetryLocation, child: const Text('Retry')),
      ],
    ),
  );

  Widget _actions(BuildContext context, TulinkColors colors) {
    if (isLeader) {
      return Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: isBusy ? null : onStart,
              child: isBusy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Start journey'),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (onShareCode != null)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isBusy ? null : onShareCode,
                    icon: const Icon(Icons.ios_share, size: 16),
                    label: const Text('Share code'),
                  ),
                ),
              if (onShareCode != null && onCancelJourney != null)
                const SizedBox(width: 8),
              if (onCancelJourney != null)
                Expanded(
                  child: OutlinedButton(
                    onPressed: isBusy ? null : onCancelJourney,
                    child: const Text('Cancel'),
                  ),
                ),
            ],
          ),
        ],
      );
    }

    return Column(
      children: [
        // A member has nothing to start. The honest affordance is leaving —
        // presented as secondary so it is not mistaken for the primary path.
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: isBusy ? null : onDismiss,
                child: const Text('Browse map'),
              ),
            ),
            if (onLeaveJourney != null) ...[
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: isBusy ? null : onLeaveJourney,
                  child: const Text('Leave'),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
