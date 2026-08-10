import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/features/maps/domain/entities/last_known_progress.dart';

Map<String, dynamic> _persisted({
  double distance = 4200,
  double duration = 540,
  int segment = 3,
  String? recordedAt,
}) => {
  'currentSegmentIndex': segment,
  'distanceRemainingMetres': distance,
  'durationRemainingSeconds': duration,
  'snappedLatitude': -1.2921,
  'snappedLongitude': 36.8219,
  'positionRecordedAt':
      recordedAt ?? DateTime.now().toUtc().toIso8601String(),
};

void main() {
  group('restoring what was persisted', () {
    test('reads every field the beacon writes, not just the cursor', () {
      final restored = LastKnownProgress.fromStorage(_persisted());

      expect(restored, isNotNull);
      expect(restored!.distanceRemainingMetres, 4200);
      expect(restored.durationRemainingSeconds, 540);
      expect(restored.currentSegmentIndex, 3);
      expect(restored.snappedLatitude, closeTo(-1.2921, 0.0001));
      expect(restored.snappedLongitude, closeTo(36.8219, 0.0001));
    });

    test('returns null when there is nothing stored', () {
      expect(LastKnownProgress.fromStorage(null), isNull);
      expect(LastKnownProgress.fromStorage(<String, dynamic>{}), isNull);
    });

    test('rejects an entry missing distance or duration', () {
      final noDistance = _persisted()..remove('distanceRemainingMetres');
      final noDuration = _persisted()..remove('durationRemainingSeconds');

      expect(LastKnownProgress.fromStorage(noDistance), isNull);
      expect(LastKnownProgress.fromStorage(noDuration), isNull);
    });

    test('rejects an entry with no timestamp', () {
      // Without knowing the age we cannot label staleness, and an unlabelled
      // stale figure is worse than showing nothing.
      final undated = _persisted()..remove('positionRecordedAt');

      expect(LastKnownProgress.fromStorage(undated), isNull);
    });
  });

  group('staleness', () {
    final now = DateTime.utc(2026, 8, 10, 12, 0, 0);

    LastKnownProgress at(Duration ago) => LastKnownProgress.fromStorage(
      _persisted(recordedAt: now.subtract(ago).toIso8601String()),
    )!;

    test('a few seconds old counts as live — the beacon writes that often', () {
      expect(at(const Duration(seconds: 5)).isStaleAt(now), isFalse);
      expect(at(const Duration(seconds: 59)).isStaleAt(now), isFalse);
    });

    test('a minute or older is stale', () {
      expect(at(const Duration(seconds: 60)).isStaleAt(now), isTrue);
      expect(at(const Duration(hours: 6)).isStaleAt(now), isTrue);
    });

    test('age is reported for labelling', () {
      expect(at(const Duration(minutes: 2)).ageAt(now).inMinutes, 2);
      expect(at(const Duration(hours: 6)).ageAt(now).inHours, 6);
    });
  });
}
