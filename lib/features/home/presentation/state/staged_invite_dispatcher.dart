import 'dart:async';

/// Outcome of one invite dispatch, so partial success is never discarded.
class InviteDispatchResult {
  const InviteDispatchResult({
    required this.sent,
    required this.failed,
    required this.abandoned,
  });

  /// Nothing was attempted — a duplicate tap, an empty selection, or a
  /// cancelled picker.
  static const InviteDispatchResult none = InviteDispatchResult(
    sent: 0,
    failed: <String>[],
    abandoned: false,
  );

  final int sent;

  /// Display names whose invitation could not be sent.
  final List<String> failed;

  /// True when the journey or session changed part-way, so the remaining
  /// targets were deliberately not invited.
  final bool abandoned;

  bool get hasAnything => sent > 0 || failed.isNotEmpty;
}

/// Sends invitations for an existing pending journey.
///
/// Exists to make the claim *atomic with respect to the picker*. The busy flag
/// used to be checked before the picker opened and claimed only after it
/// returned, so two taps landing inside that window both passed the check, both
/// opened a picker, and both continuations sent invitations — inviting everyone
/// twice.
class StagedInviteDispatcher {
  /// The journey an invite flow is currently claimed for, if any.
  String? _claimedJourneyId;

  String? get claimedJourneyId => _claimedJourneyId;
  bool get isBusy => _claimedJourneyId != null;

  /// Run one invite flow for [journeyId].
  ///
  /// [pickTargets] opens the picker. [sendInvite] sends one invitation and
  /// reports success. [isStillCurrent] is re-checked before the picker result
  /// is used, before every send, and before the roster refresh — the picker can
  /// stay open indefinitely, and invitations must not be sent for a journey or
  /// a session the user has since left.
  Future<InviteDispatchResult> dispatch<T>({
    required String journeyId,
    required Future<List<T>?> Function() pickTargets,
    required Future<bool> Function(T target) sendInvite,
    required String Function(T target) nameOf,
    required bool Function() isStillCurrent,
  }) async {
    // Claimed synchronously, before the first await. This single line is the
    // fix: everything else here is validation.
    if (_claimedJourneyId != null) return InviteDispatchResult.none;
    _claimedJourneyId = journeyId;

    try {
      final targets = await pickTargets();
      if (targets == null || targets.isEmpty) return InviteDispatchResult.none;
      if (!isStillCurrent()) {
        return const InviteDispatchResult(
          sent: 0,
          failed: <String>[],
          abandoned: true,
        );
      }

      var sent = 0;
      final failed = <String>[];
      var abandoned = false;

      for (final target in targets) {
        if (!isStillCurrent()) {
          abandoned = true;
          break;
        }
        if (await sendInvite(target)) {
          sent++;
        } else {
          failed.add(nameOf(target));
        }
      }

      return InviteDispatchResult(
        sent: sent,
        failed: failed,
        abandoned: abandoned,
      );
    } finally {
      if (_claimedJourneyId == journeyId) _claimedJourneyId = null;
    }
  }
}
