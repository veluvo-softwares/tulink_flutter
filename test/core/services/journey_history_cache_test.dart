import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:tulink_flutter/core/services/offline_storage_service.dart';

/// Storage double holding the Hive cipher key in memory.
class _FakeSecureStorage implements FlutterSecureStorage {
  final Map<String, String> values = {};

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value != null) values[key] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> _journey(String id) => {
  'id': id,
  'name': 'Journey $id',
  'status': 'COMPLETED',
};

void main() {
  late OfflineStorageService storage;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('history_cache_test');
    Hive.init(tempDir.path);
    storage = OfflineStorageService(secureStorage: _FakeSecureStorage());
    await storage.init();
  });

  tearDown(() async {
    await storage.close();
    await Hive.deleteFromDisk();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('round-trips a history list newest-first', () async {
    await storage.saveJourneyHistory('user-1', [
      _journey('a'),
      _journey('b'),
    ]);

    final loaded = storage.loadJourneyHistory('user-1');
    expect(loaded.map((j) => j['id']), ['a', 'b']);
  });

  test('trims to the retention count, keeping the newest', () async {
    final overflowing = List.generate(
      OfflineStorageService.journeyHistoryRetentionCount + 25,
      (i) => _journey('journey-$i'),
    );

    await storage.saveJourneyHistory('user-1', overflowing);
    final loaded = storage.loadJourneyHistory('user-1');

    expect(loaded, hasLength(
      OfflineStorageService.journeyHistoryRetentionCount,
    ));
    // Newest-first input means the head is what a driver actually scrolls to.
    expect(loaded.first['id'], 'journey-0');
    expect(loaded.last['id'],
        'journey-${OfflineStorageService.journeyHistoryRetentionCount - 1}');
  });

  test('a short list is stored whole', () async {
    await storage.saveJourneyHistory('user-1', [_journey('only')]);
    expect(storage.loadJourneyHistory('user-1'), hasLength(1));
  });

  test('history is per user and does not leak across accounts', () async {
    await storage.saveJourneyHistory('user-1', [_journey('mine')]);

    expect(storage.loadJourneyHistory('user-2'), isEmpty);
  });

  test('purgeUser removes history, not just journey-keyed data', () async {
    // History is keyed per user rather than per journey, so it has no
    // '<userId>:' segment — the purge loop over the other boxes cannot match
    // it. Signing out must not leave one person's journeys on the device.
    await storage.saveJourneyHistory('user-1', [_journey('a')]);
    expect(storage.loadJourneyHistory('user-1'), isNotEmpty);

    await storage.purgeUser('user-1');

    expect(storage.loadJourneyHistory('user-1'), isEmpty);
  });

  test('reading before anything is cached returns empty, not an error', () {
    expect(storage.loadJourneyHistory('nobody'), isEmpty);
  });

  group('route retention', () {
    test('deleting a route leaves other journeys untouched', () async {
      await storage.routes.put(storage.routeKey('user-1', 'journey-a'), {
        'schemaVersion': 1,
        'route': {'coordinates': []},
      });
      await storage.routes.put(storage.routeKey('user-1', 'journey-b'), {
        'schemaVersion': 1,
        'route': {'coordinates': []},
      });

      await storage.deleteRoute('user-1', 'journey-a');

      expect(storage.routes.get(storage.routeKey('user-1', 'journey-a')),
          isNull);
      expect(storage.routes.get(storage.routeKey('user-1', 'journey-b')),
          isNotNull);
    });

    test('deleting a route another user holds is not possible by id', () async {
      await storage.routes.put(storage.routeKey('user-2', 'journey-a'), {
        'schemaVersion': 1,
      });

      await storage.deleteRoute('user-1', 'journey-a');

      expect(storage.routes.get(storage.routeKey('user-2', 'journey-a')),
          isNotNull);
    });
  });
}
