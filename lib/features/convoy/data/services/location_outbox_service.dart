import 'dart:math';

import '../../../../core/services/offline_storage_service.dart';
import '../models/location_update_dto.dart';

class LocationOutboxService {
  LocationOutboxService(this._storage);

  static const int maxPoints = 20000;
  final OfflineStorageService _storage;
  final Random _random = Random.secure();

  Future<LocationUpdateDto> enqueue(
    String userId,
    LocationUpdateDto point,
  ) async {
    final pointId = point.clientPointId ?? _newPointId(point.timestamp);
    final stored = LocationUpdateDto(
      journeyId: point.journeyId,
      location: point.location,
      timestamp: point.timestamp,
      clientPointId: pointId,
      accuracy: point.accuracy,
      altitude: point.altitude,
      heading: point.heading,
      speed: point.speed,
      metadata: point.metadata,
    );
    await _enforceLimit(userId);
    await _storage.outbox.put(_key(userId, point.journeyId, pointId), {
      ...stored.toJson(),
      'userId': userId,
      'queuedAt': DateTime.now().toUtc().toIso8601String(),
      'retryCount': 0,
    });
    return stored;
  }

  List<LocationUpdateDto> pending(
    String userId,
    String journeyId, {
    int limit = 200,
  }) {
    final points =
        _storage.outbox.values
            .map(OfflineStorageService.readMap)
            .whereType<Map<String, dynamic>>()
            .where(
              (value) =>
                  value['userId'] == userId &&
                  value['journeyId'] == journeyId &&
                  value['state'] != 'rejected',
            )
            .map(LocationUpdateDto.fromJson)
            .toList()
          ..sort((left, right) => left.timestamp.compareTo(right.timestamp));
    return points.take(limit).toList(growable: false);
  }

  List<String> journeyIds(String userId) => _storage.outbox.values
      .map(OfflineStorageService.readMap)
      .whereType<Map<String, dynamic>>()
      .where((value) => value['userId'] == userId)
      .where((value) => value['state'] != 'rejected')
      .map((value) => value['journeyId']?.toString())
      .whereType<String>()
      .toSet()
      .toList(growable: false);

  Future<void> acknowledge(
    String userId,
    String journeyId,
    Iterable<String> pointIds,
  ) async {
    await _storage.outbox.deleteAll(
      pointIds.map((pointId) => _key(userId, journeyId, pointId)),
    );
  }

  Future<void> markAttempt(
    String userId,
    String journeyId,
    Iterable<String> pointIds,
  ) async {
    for (final pointId in pointIds) {
      final key = _key(userId, journeyId, pointId);
      final value = OfflineStorageService.readMap(_storage.outbox.get(key));
      if (value == null) continue;
      await _storage.outbox.put(key, {
        ...value,
        'retryCount': ((value['retryCount'] as num?)?.toInt() ?? 0) + 1,
        'lastAttemptAt': DateTime.now().toUtc().toIso8601String(),
      });
    }
  }

  /// Preserve permanently rejected samples for diagnostics without allowing
  /// one invalid timestamp to block every newer point in the journey queue.
  Future<void> quarantineRejected(
    String userId,
    String journeyId,
    Iterable<Map<String, dynamic>> rejected,
  ) async {
    for (final rejection in rejected) {
      final pointId = rejection['clientPointId']?.toString();
      if (pointId == null) continue;
      final key = _key(userId, journeyId, pointId);
      final value = OfflineStorageService.readMap(_storage.outbox.get(key));
      if (value == null) continue;
      await _storage.outbox.put(key, {
        ...value,
        'state': 'rejected',
        'rejectionReason': rejection['reason']?.toString() ?? 'UNKNOWN',
        'rejectedAt': DateTime.now().toUtc().toIso8601String(),
      });
    }
  }

  Map<String, dynamic> toBackfillPoint(LocationUpdateDto point) => {
    'clientPointId': point.clientPointId,
    'recordedAt': point.timestamp,
    'location': point.location.toJson(),
    'accuracy': point.accuracy ?? 0,
    if (point.altitude != null) 'altitude': point.altitude,
    if (point.heading != null) 'heading': point.heading,
    if (point.speed != null) 'speed': point.speed,
    if (point.metadata != null) 'metadata': point.metadata,
  };

  /// A retry of the same leading page must carry the same batch identifier.
  /// Point IDs remain the real idempotency boundary; this stable ID also makes
  /// server/client diagnostics correlate a lost acknowledgement correctly.
  String batchIdFor(List<LocationUpdateDto> points) {
    if (points.isEmpty) throw ArgumentError('Cannot identify an empty batch');
    return 'batch-${points.first.clientPointId}-${points.last.clientPointId}-${points.length}';
  }

  String _key(String userId, String journeyId, String pointId) =>
      'outbox_$userId:$journeyId:$pointId';

  String _newPointId(int timestamp) {
    final entropy = List<int>.generate(
      12,
      (_) => _random.nextInt(256),
    ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    return '$timestamp-$entropy';
  }

  Future<void> _enforceLimit(String userId) async {
    final entries = _storage.outbox.toMap().entries.where((entry) {
      final value = OfflineStorageService.readMap(entry.value);
      return value?['userId'] == userId;
    }).toList();
    if (entries.length < maxPoints) return;
    entries..sort((left, right) {
      final leftMap = OfflineStorageService.readMap(left.value);
      final rightMap = OfflineStorageService.readMap(right.value);
      return (leftMap?['timestamp'] as num? ?? 0).compareTo(
        rightMap?['timestamp'] as num? ?? 0,
      );
    });
    // Compact a bounded oldest window by sampling alternate points. This
    // preserves the broad trail shape and newer navigation-detail samples.
    final oldestWindow = entries.take(maxPoints ~/ 5).toList(growable: false);
    final keysToRemove = <dynamic>[];
    for (var index = 1; index < oldestWindow.length; index += 2) {
      keysToRemove.add(oldestWindow[index].key);
    }
    await _storage.outbox.deleteAll(keysToRemove);
    print(
      '⚠️ Offline trail reached its cap; sampled ${keysToRemove.length} oldest points',
    );
  }
}
