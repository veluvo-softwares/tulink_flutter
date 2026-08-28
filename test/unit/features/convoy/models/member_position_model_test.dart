import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/features/convoy/data/models/member_position_model.dart';

void main() {
  group('MemberPositionModel', () {
    test('should parse from JSON correctly', () {
      // Arrange
      final json = {
        'userId': 'user123',
        'latitude': -1.2921,
        'longitude': 36.8219,
        'timestamp': 1735171200000,
        'accuracy': 10.5,
        'heading': 90.0,
        'speed': 15.5,
        'altitude': 1795.0,
        'batteryLevel': 75,
        'isMoving': true,
        'statusChange': 'MOVING',
        'sequenceNumber': 42,
        'priority': 'HIGH',
      };

      // Act
      final model = MemberPositionModel.fromJson(json);

      // Assert
      expect(model.userId, 'user123');
      expect(model.latitude, -1.2921);
      expect(model.longitude, 36.8219);
      expect(model.timestamp, 1735171200000);
      expect(model.accuracy, 10.5);
      expect(model.heading, 90.0);
      expect(model.speed, 15.5);
      expect(model.altitude, 1795.0);
      expect(model.batteryLevel, 75);
      expect(model.isMoving, true);
      expect(model.statusChange, 'MOVING');
      expect(model.sequenceNumber, 42);
      expect(model.priority, 'HIGH');
    });

    test('should parse from RTDB format correctly', () {
      // Arrange
      final rtdbData = {
        'userId': 'user123',
        'lat': -1.2921,
        'lng': 36.8219,
        'timestamp': 1735171200000,
        'accuracy': 10.5,
        'heading': 450.0, // Test heading normalization
        'speed': 15.5,
        'altitude': 1795.0,
        'sequenceNumber': 42,
        'priority': 'HIGH',
        'metadata': {
          'batteryLevel': 75,
          'isMoving': true,
          'statusChange': 'MOVING',
        },
      };

      // Act
      final model = MemberPositionModel.fromRtdb(rtdbData);

      // Assert
      expect(model.userId, 'user123');
      expect(model.latitude, -1.2921);
      expect(model.longitude, 36.8219);
      expect(model.normalizedHeading, 90.0); // 450 normalized to 90
      expect(model.batteryLevel, 75);
      expect(model.isMoving, true);
    });

    test('should handle missing optional fields gracefully', () {
      // Arrange
      final json = {
        'userId': 'user123',
        'latitude': -1.2921,
        'longitude': 36.8219,
        'timestamp': 1735171200000,
      };

      // Act
      final model = MemberPositionModel.fromJson(json);

      // Assert
      expect(model.userId, 'user123');
      expect(model.accuracy, null);
      expect(model.heading, null);
      expect(model.batteryLevel, null);
      expect(model.isMoving, false); // Default value
    });

    test('should read movement state from WebSocket metadata', () {
      final model = MemberPositionModel.fromJson({
        'userId': 'user123',
        'latitude': -1.2921,
        'longitude': 36.8219,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'speed': 12.0,
        'metadata': {'isMoving': true, 'batteryLevel': 82},
      });

      expect(model.isMoving, true);
      expect(model.batteryLevel, 82);
      expect(model.memberStatus, 'MOVING');
    });

    test('should convert to entity correctly', () {
      // Arrange
      const model = MemberPositionModel(
        userId: 'user123',
        latitude: -1.2921,
        longitude: 36.8219,
        timestamp: 1735171200000,
        heading: 90.0,
        speed: 15.5,
        isMoving: true,
        statusChange: 'MOVING',
      );

      // Act
      final entity = model.toEntity();

      // Assert
      expect(entity.userId, 'user123');
      expect(entity.latitude, -1.2921);
      expect(entity.longitude, 36.8219);
      expect(entity.speedKmh, closeTo(55.8, 0.001)); // 15.5 m/s to km/h
    });

    test('should handle RTDB snapshot parsing', () {
      // Arrange
      final snapshot = {
        'user1': {
          'userId': 'user1',
          'lat': -1.2921,
          'lng': 36.8219,
          'timestamp': 1735171200000,
          'metadata': {'isMoving': true},
        },
        'user2': {
          'userId': 'user2',
          'lat': -1.2845,
          'lng': 36.8310,
          'timestamp': 1735171200000,
          'metadata': {'isMoving': false},
        },
      };

      // Act
      final positions = MemberPositionModel.fromRtdbSnapshot(snapshot);

      // Assert
      expect(positions.length, 2);
      expect(positions[0].userId, 'user1');
      expect(positions[1].userId, 'user2');
    });
  });
}
