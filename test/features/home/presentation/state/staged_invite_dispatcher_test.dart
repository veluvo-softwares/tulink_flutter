import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/features/home/presentation/state/staged_invite_dispatcher.dart';

/// The invite flow must be claimed before the picker opens.
///
/// The shipped guard was checked before `showModalBottomSheet` and claimed only
/// after it returned, so two taps inside that window both passed the check,
/// both opened a picker, and both continuations sent invitations.
void main() {
  late StagedInviteDispatcher dispatcher;

  setUp(() => dispatcher = StagedInviteDispatcher());

  test('a duplicate tap cannot open a second picker', () async {
    final gate = Completer<List<String>?>();
    var pickersOpened = 0;
    final sent = <String>[];

    Future<InviteDispatchResult> tap() => dispatcher.dispatch<String>(
      journeyId: 'j1',
      isStillCurrent: () => true,
      nameOf: (t) => t,
      pickTargets: () {
        pickersOpened++;
        return gate.future;
      },
      sendInvite: (t) async {
        sent.add(t);
        return true;
      },
    );

    final first = tap();
    final second = await tap(); // the duplicate tap, while the picker is open

    expect(
      pickersOpened,
      1,
      reason: 'the claim must be taken before the first await',
    );
    expect(second.sent, 0);
    expect(second.hasAnything, isFalse);

    gate.complete(['u1', 'u2']);
    final result = await first;

    expect(sent, ['u1', 'u2']);
    expect(result.sent, 2);
  });

  test('the claim is released so a later invite still works', () async {
    Future<InviteDispatchResult> run(List<String> targets) =>
        dispatcher.dispatch<String>(
          journeyId: 'j1',
          isStillCurrent: () => true,
          nameOf: (t) => t,
          pickTargets: () async => targets,
          sendInvite: (_) async => true,
        );

    expect((await run(['u1'])).sent, 1);
    expect(dispatcher.isBusy, isFalse);
    expect((await run(['u2'])).sent, 1);
  });

  test('a cancelled picker sends nothing and releases the claim', () async {
    final result = await dispatcher.dispatch<String>(
      journeyId: 'j1',
      isStillCurrent: () => true,
      nameOf: (t) => t,
      pickTargets: () async => null,
      sendInvite: (_) async => true,
    );

    expect(result.sent, 0);
    expect(result.abandoned, isFalse);
    expect(dispatcher.isBusy, isFalse);
  });

  test('a journey switch while the picker is open sends nothing', () async {
    var current = true;
    final sent = <String>[];

    final result = await dispatcher.dispatch<String>(
      journeyId: 'j1',
      isStillCurrent: () => current,
      nameOf: (t) => t,
      pickTargets: () async {
        current = false; // the user moved to another journey
        return ['u1'];
      },
      sendInvite: (t) async {
        sent.add(t);
        return true;
      },
    );

    expect(sent, isEmpty);
    expect(result.abandoned, isTrue);
  });

  test('a switch part-way stops sending but keeps what already went', () async {
    var current = true;
    final sent = <String>[];

    final result = await dispatcher.dispatch<String>(
      journeyId: 'j1',
      isStillCurrent: () => current,
      nameOf: (t) => t,
      pickTargets: () async => ['u1', 'u2', 'u3'],
      sendInvite: (t) async {
        sent.add(t);
        if (sent.length == 1) current = false;
        return true;
      },
    );

    expect(sent, ['u1']);
    expect(result.sent, 1, reason: 'partial success is never discarded');
    expect(result.abandoned, isTrue);
  });

  test('partial failure is reported per user', () async {
    final result = await dispatcher.dispatch<String>(
      journeyId: 'j1',
      isStillCurrent: () => true,
      nameOf: (t) => t,
      pickTargets: () async => ['ok', 'bad', 'ok2'],
      sendInvite: (t) async => t != 'bad',
    );

    expect(result.sent, 2);
    expect(result.failed, ['bad']);
    expect(result.abandoned, isFalse);
  });
}
