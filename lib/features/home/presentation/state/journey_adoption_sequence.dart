import 'dart:async';

/// Orders the visible handoff when Home adopts a journey.
///
/// A live journey owns and restores its own map geometry, so it must enter the
/// live experience immediately. Waiting for draft-style destination staging
/// first can strand an accepted member on the browse map when native map work
/// is delayed. Pending journeys still stage their destination before exposing
/// their waiting controls.
Future<void> sequenceJourneyAdoption({
  required bool isLive,
  required FutureOr<void> Function() enterLive,
  required Future<void> Function() stagePending,
}) async {
  if (isLive) {
    await enterLive();
    return;
  }

  await stagePending();
}
