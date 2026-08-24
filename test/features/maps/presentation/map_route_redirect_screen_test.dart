import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/features/maps/presentation/map_route_redirect_screen.dart';

/// The legacy `/mapview` entry point must preserve *which* journey a stale link
/// referred to. Dropping the id would silently downgrade a notification tap
/// into "here is a map", which is the bug this parsing exists to prevent.
void main() {
  group('journey identity is recovered from legacy arguments', () {
    test('a bare id string is the shape the old call sites used', () {
      expect(MapRouteRedirectScreen.journeyIdFrom('journey-42'), 'journey-42');
    });

    test('surrounding whitespace is tolerated', () {
      expect(
        MapRouteRedirectScreen.journeyIdFrom('  journey-42 '),
        'journey-42',
      );
    });

    test('a notification payload map is read by journeyId', () {
      expect(
        MapRouteRedirectScreen.journeyIdFrom({'journeyId': 'journey-42'}),
        'journey-42',
      );
    });

    test('a payload using id is also accepted', () {
      expect(
        MapRouteRedirectScreen.journeyIdFrom({'id': 'journey-42'}),
        'journey-42',
      );
    });

    test('journeyId wins when a payload carries both', () {
      expect(
        MapRouteRedirectScreen.journeyIdFrom({
          'journeyId': 'journey-42',
          'id': 'something-else',
        }),
        'journey-42',
      );
    });
  });

  group('malformed arguments degrade to just showing the map', () {
    test('no argument', () {
      expect(MapRouteRedirectScreen.journeyIdFrom(null), isNull);
    });

    test('an empty or blank id', () {
      expect(MapRouteRedirectScreen.journeyIdFrom(''), isNull);
      expect(MapRouteRedirectScreen.journeyIdFrom('   '), isNull);
    });

    test('stringified null/undefined from a stale payload', () {
      // Push payloads are JSON-stringified; a missing field arrives as the
      // literal text, and requesting a journey called "null" would 404.
      expect(MapRouteRedirectScreen.journeyIdFrom('null'), isNull);
      expect(MapRouteRedirectScreen.journeyIdFrom('undefined'), isNull);
      expect(
        MapRouteRedirectScreen.journeyIdFrom({'journeyId': 'null'}),
        isNull,
      );
    });

    test('a wrongly typed argument', () {
      expect(MapRouteRedirectScreen.journeyIdFrom(42), isNull);
      expect(MapRouteRedirectScreen.journeyIdFrom({'journeyId': 42}), isNull);
      expect(MapRouteRedirectScreen.journeyIdFrom(['journey-42']), isNull);
    });

    test('a map with no recognised key', () {
      expect(MapRouteRedirectScreen.journeyIdFrom({'type': 'JOURNEY'}), isNull);
    });
  });
}
