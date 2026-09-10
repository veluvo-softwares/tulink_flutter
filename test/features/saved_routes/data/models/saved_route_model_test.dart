import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/features/saved_routes/data/models/saved_route_model.dart';
import 'package:tulink_flutter/features/saved_routes/domain/entities/saved_route.dart';

void main() {
  test('parses backend geometry, waypoints, permissions, and steps', () {
    final route = SavedRouteModel.fromJson({
      'id': 'route-1',
      'organizationId': 'org-1',
      'name': 'Airstrip transfer',
      'source': 'RECORDED',
      'geometry': [
        [36.8, -1.2],
        [36.9, -1.3],
      ],
      'waypoints': [
        {'latitude': -1.2, 'longitude': 36.8, 'name': 'Gate'},
        {'latitude': -1.3, 'longitude': 36.9, 'name': 'Airstrip'},
      ],
      'distanceMetres': 15000,
      'durationSeconds': 1200,
      'steps': [
        {
          'instruction': 'Continue straight',
          'distanceMetres': 500,
          'maneuver': 'continue',
        },
      ],
      'version': 2,
      'canEdit': true,
      'editorUserIds': ['editor-1'],
      'createdAt': '2026-09-10T08:00:00.000Z',
      'updatedAt': '2026-09-10T09:00:00.000Z',
    });

    expect(route.source, SavedRouteSource.recorded);
    expect(route.geometry.last, [36.9, -1.3]);
    expect(route.destination.name, 'Airstrip');
    expect(route.steps.single.maneuver, 'continue');
    expect(route.canEdit, isTrue);
    expect(route.editorUserIds, ['editor-1']);
    expect(route.version, 2);
  });
}
