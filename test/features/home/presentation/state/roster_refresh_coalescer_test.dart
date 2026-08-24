import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/features/home/presentation/state/roster_refresh_coalescer.dart';

/// A burst of `participant-accepted` events must always end in a refresh.
///
/// Home used to advance the observed tick and then drop the request whenever a
/// refresh was already running, so the *last* acceptance in a burst was
/// routinely lost and the leader's roster silently stayed stale until some
/// unrelated event repaired it.
void main() {
  test('an acceptance during an in-flight refresh still gets served', () async {
    final gates = <Completer<String?>>[];
    var calls = 0;
    final coalescer = RosterRefreshCoalescer(
      refresh: (journeyId) {
        calls++;
        final gate = Completer<String?>();
        gates.add(gate);
        return gate.future;
      },
    );

    final first = coalescer.record(
      tick: 1,
      journeyId: 'A',
      isStillStaged: () => true,
    );
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);

    // A second acceptance arrives while the first refresh is still running.
    unawaited(
      coalescer.record(tick: 2, journeyId: 'A', isStillStaged: () => true),
    );
    gates[0].complete('A');
    await Future<void>.delayed(Duration.zero);

    expect(
      calls,
      2,
      reason: 'the trailing edge of the burst must trigger another refresh',
    );

    gates[1].complete('A');
    await first;
    expect(coalescer.servedTick, 2);
  });

  test(
    'two acceptances during one refresh collapse into one more pass',
    () async {
      final gates = <Completer<String?>>[];
      var calls = 0;
      final coalescer = RosterRefreshCoalescer(
        refresh: (_) {
          calls++;
          final gate = Completer<String?>();
          gates.add(gate);
          return gate.future;
        },
      );

      final run = coalescer.record(
        tick: 1,
        journeyId: 'A',
        isStillStaged: () => true,
      );
      await Future<void>.delayed(Duration.zero);

      unawaited(
        coalescer.record(tick: 2, journeyId: 'A', isStillStaged: () => true),
      );
      unawaited(
        coalescer.record(tick: 3, journeyId: 'A', isStillStaged: () => true),
      );

      gates[0].complete('A');
      await Future<void>.delayed(Duration.zero);
      gates[1].complete('A');
      await run;

      expect(calls, 2, reason: 'coalesced, not one refresh per acceptance');
      expect(coalescer.servedTick, 3);
    },
  );

  test('a failed refresh does not mark the tick as served', () async {
    var calls = 0;
    final coalescer = RosterRefreshCoalescer(
      refresh: (_) async {
        calls++;
        return calls == 1 ? null : 'A'; // first refresh fails
      },
    );

    await coalescer.record(tick: 1, journeyId: 'A', isStillStaged: () => true);
    expect(coalescer.servedTick, 0, reason: 'nothing was actually refreshed');

    // A later acceptance must still be able to repair the roster.
    await coalescer.record(tick: 2, journeyId: 'A', isStillStaged: () => true);
    expect(coalescer.servedTick, 2);
    expect(calls, 2);
  });

  test('a response for another journey is never accepted', () async {
    final coalescer = RosterRefreshCoalescer(
      refresh: (_) async => 'B', // the server answered about B
    );

    await coalescer.record(tick: 1, journeyId: 'A', isStillStaged: () => true);

    expect(
      coalescer.servedTick,
      0,
      reason: "another journey's roster must not be installed as A's",
    );
  });

  test('leaving the staging state mid-refresh abandons the rest', () async {
    var staged = true;
    var calls = 0;
    final gate = Completer<String?>();
    final coalescer = RosterRefreshCoalescer(
      refresh: (_) {
        calls++;
        return calls == 1 ? gate.future : Future.value('A');
      },
    );

    final run = coalescer.record(
      tick: 1,
      journeyId: 'A',
      isStillStaged: () => staged,
    );
    await Future<void>.delayed(Duration.zero);

    unawaited(
      coalescer.record(tick: 2, journeyId: 'A', isStillStaged: () => staged),
    );
    staged = false; // the user left staging
    gate.complete('A');
    await run;

    expect(
      calls,
      1,
      reason: 'no further refresh may run once the journey is not staged',
    );
    expect(coalescer.isRefreshing, isFalse);
  });

  test('a stale tick is ignored', () async {
    var calls = 0;
    final coalescer = RosterRefreshCoalescer(
      refresh: (_) async {
        calls++;
        return 'A';
      },
    );

    await coalescer.record(tick: 5, journeyId: 'A', isStillStaged: () => true);
    await coalescer.record(tick: 3, journeyId: 'A', isStillStaged: () => true);

    expect(calls, 1);
    expect(coalescer.observedTick, 5);
  });
}
