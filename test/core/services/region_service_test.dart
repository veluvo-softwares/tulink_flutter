import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/core/services/region_service.dart';

void main() {
  group('RegionService.normalizeRegionCode', () {
    test('uppercases a valid lowercase code', () {
      expect(RegionService.normalizeRegionCode('ke'), 'KE');
    });

    test('passes through a valid uppercase code', () {
      expect(RegionService.normalizeRegionCode('UG'), 'UG');
    });

    test('trims surrounding whitespace', () {
      expect(RegionService.normalizeRegionCode('  ke '), 'KE');
    });

    test('rejects null', () {
      expect(RegionService.normalizeRegionCode(null), isNull);
    });

    test('rejects the empty string', () {
      expect(RegionService.normalizeRegionCode(''), isNull);
    });

    test('rejects a 1-letter code', () {
      expect(RegionService.normalizeRegionCode('K'), isNull);
    });

    test('rejects a 3-letter code', () {
      expect(RegionService.normalizeRegionCode('KEN'), isNull);
    });

    test('rejects codes containing digits', () {
      expect(RegionService.normalizeRegionCode('K1'), isNull);
    });
  });

  group('RegionService.reset', () {
    test('is callable and clears cached state without error', () {
      // Seam used by tests to drop any in-memory cache between cases.
      RegionService.reset();
      expect(RegionService.normalizeRegionCode('ke'), 'KE');
    });
  });
}
