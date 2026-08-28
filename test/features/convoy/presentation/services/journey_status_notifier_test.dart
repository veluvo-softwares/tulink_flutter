import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:tulink_flutter/features/convoy/presentation/services/journey_status_formatter.dart';
import 'package:tulink_flutter/features/convoy/presentation/services/journey_status_notifier.dart';

import 'journey_status_notifier_test.mocks.dart';

@GenerateNiceMocks([MockSpec<FlutterLocalNotificationsPlugin>()])
MemberStatusEntry _member(String name, double meters) => (
  userId: 'user-${name.toLowerCase()}',
  name: name,
  meters: meters,
  arrived: false,
);

void main() {
  late JourneyStatusNotifier notifier;

  setUp(() => notifier = JourneyStatusNotifier());

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  Map<String, dynamic> build(
    List<MemberStatusEntry> entries, {
    int? totalMemberCount,
  }) => notifier.buildLiveActivityData(
    title: 'home card test',
    entries: entries,
    presentation: const {},
    totalMemberCount: totalMemberCount,
  );

  group('member slots are always fully written', () {
    test('a solo journey blanks every slot', () {
      // The widget reads member keys from app-group UserDefaults, which
      // outlive the activity. Omitting a key leaves the previous journey's
      // member on screen — a solo journey showed a member from an earlier
      // convoy, complete with a distance from that other trip.
      final data = build(const []);

      expect(data['member0'], '');
      expect(data['member1'], '');
      expect(data['member2'], '');
    });

    test('slots beyond the current members are blanked', () {
      final data = build([_member('Ada', 1200)]);

      expect(data['member0'], isNot(''));
      expect(data['member0'], contains('Ada'));
      expect(data['member1'], '');
      expect(data['member2'], '');
    });

    test('a full convoy fills every slot', () {
      final data = build([
        _member('Ada', 1200),
        _member('Brian', 2400),
        _member('Cleo', 3600),
      ]);

      expect(data['member0'], contains('Ada'));
      expect(data['member1'], contains('Brian'));
      expect(data['member2'], contains('Cleo'));
    });

    test('members past the visible budget are counted, not dropped', () {
      final data = build([
        _member('Ada', 1200),
        _member('Brian', 2400),
        _member('Cleo', 3600),
        _member('Dan', 4800),
        _member('Eve', 6000),
      ]);

      expect(data['extraMembers'], 2);
      expect(data['member2'], contains('Cleo'));
    });
  });

  group('subtitle', () {
    test('a solo journey does not claim to be a convoy', () {
      expect(build(const [])['subtitle'], 'Solo journey');
    });

    test('a convoy counts the members plus this driver', () {
      expect(build([_member('Ada', 1200)])['subtitle'], '2 in convoy');
      expect(
        build([_member('Ada', 1200), _member('Brian', 2400)])['subtitle'],
        '3 in convoy',
      );
    });

    test('an accepted roster is not labelled solo before GPS arrives', () {
      expect(build(const [], totalMemberCount: 2)['subtitle'], '2 in convoy');
    });
  });

  test('the row format matches the widget decode contract', () {
    // MemberRow.decode splits on "|" and rejects anything under four parts,
    // which is what makes a blank slot render as no row at all.
    final row = build([_member('Ada', 1200)])['member0'] as String;

    expect(row.split('|').length, greaterThanOrEqualTo(4));
    expect(''.split('|').length, lessThan(4));
  });

  group('Android notification safety', () {
    test('uses the launcher resource shipped by the Android app', () {
      expect(
        JourneyStatusNotifier.androidNotificationIcon,
        '@mipmap/launcher_icon',
      );
    });

    test('launcher resource exists in every Android density', () {
      final resourceFiles = Directory('android/app/src/main/res')
          .listSync()
          .whereType<Directory>()
          .where((directory) => directory.path.contains('mipmap-'))
          .map((directory) => File('${directory.path}/launcher_icon.png'));

      expect(resourceFiles, isNotEmpty);
      expect(resourceFiles.every((file) => file.existsSync()), isTrue);
    });

    test('a native notification failure never escapes the journey', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final plugin = MockFlutterLocalNotificationsPlugin();
      when(
        plugin.initialize(settings: anyNamed('settings')),
      ).thenThrow(PlatformException(code: 'invalid_icon'));
      notifier = JourneyStatusNotifier(plugin: plugin);

      await expectLater(
        notifier.update(
          journeyName: 'Trip to Enashipai',
          selfUserId: 'driver',
          presentation: const {},
        ),
        completes,
      );

      final settings =
          verify(
                plugin.initialize(settings: captureAnyNamed('settings')),
              ).captured.single
              as InitializationSettings;
      expect(
        settings.android?.defaultIcon,
        JourneyStatusNotifier.androidNotificationIcon,
      );
    });
  });
}
