import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/features/maps/data/models/route_result_model.dart';

void main() {
  test('parses valid route alternatives and drops malformed geometry', () {
    final route = RouteResultModel.fromJson({
      'coordinates': [
        [36.8, -1.2],
        [36.9, -1.3],
      ],
      'distanceMetres': 1000,
      'durationSeconds': 600,
      'steps': <Object?>[],
      'alternates': [
        {
          'coordinates': [
            [36.8, -1.2],
            [37.0, -1.4],
          ],
          'distanceMetres': 1200,
          'durationSeconds': 720,
          'steps': <Object?>[],
        },
        {
          'coordinates': [
            [999, -1.2],
          ],
          'distanceMetres': 10,
          'durationSeconds': 10,
          'steps': <Object?>[],
        },
      ],
    });

    expect(route.alternates, hasLength(1));
    expect(route.alternates.single.distanceMetres, 1200);
    expect(route.toJson()['alternates'], isA<List<Object?>>());
  });

  test('older route responses remain valid without alternatives', () {
    final route = RouteResultModel.fromJson({
      'coordinates': [
        [36.8, -1.2],
        [36.9, -1.3],
      ],
      'distanceMetres': 1000,
      'durationSeconds': 600,
      'steps': <Object?>[],
    });

    expect(route.alternates, isEmpty);
    expect(route.toJson().containsKey('alternates'), isFalse);
  });
}
