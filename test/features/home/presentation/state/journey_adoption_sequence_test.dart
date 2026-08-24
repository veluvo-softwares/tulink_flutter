import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/features/home/presentation/state/journey_adoption_sequence.dart';

void main() {
  test(
    'a live handoff does not wait for pending destination staging',
    () async {
      var enteredLive = false;
      var stagedPending = false;

      await sequenceJourneyAdoption(
        isLive: true,
        enterLive: () => enteredLive = true,
        stagePending: () async => stagedPending = true,
      );

      expect(enteredLive, isTrue);
      expect(stagedPending, isFalse);
    },
  );

  test(
    'a pending handoff stages the destination before it completes',
    () async {
      final gate = Completer<void>();
      var enteredLive = false;
      var stagedPending = false;

      final adoption = sequenceJourneyAdoption(
        isLive: false,
        enterLive: () => enteredLive = true,
        stagePending: () async {
          stagedPending = true;
          await gate.future;
        },
      );

      await Future<void>.delayed(Duration.zero);
      expect(stagedPending, isTrue);
      expect(enteredLive, isFalse);

      gate.complete();
      await adoption;
    },
  );
}
