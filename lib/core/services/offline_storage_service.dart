import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';

import '../constants/storage_keys.dart';

/// Owns the encrypted, versioned boxes used by offline navigation.
/// Values are JSON-compatible maps so schema migrations remain explicit.
class OfflineStorageService {
  OfflineStorageService({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secureStorage;
  late Box<dynamic> _routes;
  late Box<dynamic> _sessions;
  late Box<dynamic> _outbox;
  late Box<dynamic> _tileMetadata;

  Box<dynamic> get routes => _routes;
  Box<dynamic> get sessions => _sessions;
  Box<dynamic> get outbox => _outbox;
  Box<dynamic> get tileMetadata => _tileMetadata;

  Future<void> init() async {
    final cipher = HiveAesCipher(await _loadOrCreateCipherKey());
    _routes = await Hive.openBox<dynamic>(
      StorageKeys.offlineRoutesBox,
      encryptionCipher: cipher,
    );
    _sessions = await Hive.openBox<dynamic>(
      StorageKeys.offlineSessionsBox,
      encryptionCipher: cipher,
    );
    _outbox = await Hive.openBox<dynamic>(
      StorageKeys.locationOutboxBox,
      encryptionCipher: cipher,
    );
    _tileMetadata = await Hive.openBox<dynamic>(
      StorageKeys.offlineTileMetadataBox,
      encryptionCipher: cipher,
    );
  }

  String routeKey(String userId, String journeyId) =>
      '${StorageKeys.offlineRoutePrefix}$userId:$journeyId';
  String sessionKey(String userId, String journeyId) =>
      '${StorageKeys.offlineSessionPrefix}$userId:$journeyId';

  Future<void> mergeSession(
    String userId,
    String journeyId,
    Map<String, dynamic> values,
  ) async {
    final key = sessionKey(userId, journeyId);
    final existing = readMap(_sessions.get(key)) ?? <String, dynamic>{};
    await _sessions.put(key, <String, dynamic>{
      ...existing,
      ...values,
      'schemaVersion': 1,
      'userId': userId,
      'journeyId': journeyId,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Map<String, dynamic>? loadSession(String userId, String journeyId) =>
      readMap(_sessions.get(sessionKey(userId, journeyId)));

  List<Map<String, dynamic>> loadUserSessions(String userId) => _sessions.values
      .map(readMap)
      .whereType<Map<String, dynamic>>()
      .where((value) => value['userId'] == userId)
      .toList(growable: false);

  Future<void> deleteSession(String userId, String journeyId) =>
      _sessions.delete(sessionKey(userId, journeyId));

  static Map<String, dynamic>? readMap(dynamic value) {
    if (value is! Map) return null;
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  Future<List<int>> _loadOrCreateCipherKey() async {
    final encoded = await _secureStorage.read(
      key: StorageKeys.offlineStorageCipherKey,
    );
    if (encoded != null) {
      final decoded = base64Url.decode(encoded);
      if (decoded.length == 32) return decoded;
    }

    final random = Random.secure();
    final key = List<int>.generate(32, (_) => random.nextInt(256));
    await _secureStorage.write(
      key: StorageKeys.offlineStorageCipherKey,
      value: base64UrlEncode(key),
    );
    return key;
  }

  Future<void> purgeUser(String userId) async {
    for (final box in [_routes, _sessions, _outbox, _tileMetadata]) {
      final keys = box.keys
          .where((key) => key.toString().contains('$userId:'))
          .toList(growable: false);
      await box.deleteAll(keys);
    }
  }

  Future<void> close() async {
    await Future.wait([
      _routes.close(),
      _sessions.close(),
      _outbox.close(),
      _tileMetadata.close(),
    ]);
  }
}
