import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';

import '../constants/storage_keys.dart';

/// Owns the encrypted, versioned boxes used by offline navigation.
/// Values are JSON-compatible maps so schema migrations remain explicit.
class OfflineStorageService {
  OfflineStorageService({FlutterSecureStorage? secureStorage})
    : _secureStorage =
          secureStorage ??
          const FlutterSecureStorage(
            // Matches TokenManager. This holds the Hive encryption key, which
            // is read while a journey drains its outbox in the background —
            // so it has to survive a locked screen too.
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock,
            ),
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          );

  final FlutterSecureStorage _secureStorage;
  late Box<dynamic> _routes;
  late Box<dynamic> _sessions;
  late Box<dynamic> _outbox;
  late Box<dynamic> _tileMetadata;
  late Box<dynamic> _journeyHistory;

  Box<dynamic> get routes => _routes;
  Box<dynamic> get sessions => _sessions;
  Box<dynamic> get outbox => _outbox;
  Box<dynamic> get tileMetadata => _tileMetadata;
  Box<dynamic> get journeyHistory => _journeyHistory;

  /// How many finished journeys to keep per user.
  ///
  /// Bounded by count rather than age on purpose: a daily driver accumulates
  /// ninety journeys in ninety days while an occasional one has five in a
  /// year, so a time window bounds storage for neither. At roughly 2KB of
  /// metadata each this ceiling is about 200KB, and it is far past what the
  /// home list and "see all" ever scroll to.
  static const int journeyHistoryRetentionCount = 100;

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
    _journeyHistory = await Hive.openBox<dynamic>(
      StorageKeys.journeyHistoryBox,
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

  /// Drop a journey's stored route.
  ///
  /// Polylines are by far the largest per-journey artefact — hundreds to
  /// thousands of coordinate pairs each — and exist solely so navigation can
  /// resume. Once a journey has ended it will never be navigated again, so the
  /// route is dead weight from that moment on.
  Future<void> deleteRoute(String userId, String journeyId) =>
      _routes.delete(routeKey(userId, journeyId));

  String journeyHistoryKey(String userId) =>
      '${StorageKeys.journeyHistoryPrefix}$userId';

  /// Replace a user's cached finished-journey list, trimmed to
  /// [journeyHistoryRetentionCount].
  ///
  /// Trimming happens here rather than on a timer or at startup: this is the
  /// only moment the list can exceed its bound, so enforcing it here needs no
  /// scheduling and costs nothing at launch. [journeys] is expected
  /// newest-first, matching the order the history endpoint returns.
  Future<void> saveJourneyHistory(
    String userId,
    List<Map<String, dynamic>> journeys,
  ) async {
    final retained = journeys.length > journeyHistoryRetentionCount
        ? journeys.sublist(0, journeyHistoryRetentionCount)
        : journeys;
    await _journeyHistory.put(journeyHistoryKey(userId), <String, dynamic>{
      'schemaVersion': 1,
      'userId': userId,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      'journeys': retained,
    });
  }

  /// A user's cached finished journeys, newest-first. Empty when nothing has
  /// been cached yet or the entry predates this schema.
  List<Map<String, dynamic>> loadJourneyHistory(String userId) {
    final value = readMap(_journeyHistory.get(journeyHistoryKey(userId)));
    if (value == null || value['schemaVersion'] != 1) return const [];
    if (value['userId'] != userId) return const [];
    final journeys = value['journeys'];
    if (journeys is! List) return const [];
    return journeys
        .map(readMap)
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
  }

  Future<void> deleteJourneyHistory(String userId) =>
      _journeyHistory.delete(journeyHistoryKey(userId));

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
    // History is keyed per user rather than per journey, so it has no
    // '<userId>:' segment for the loop above to match. Deleted explicitly so
    // signing out cannot leave one person's journeys readable to the next.
    await deleteJourneyHistory(userId);
  }

  Future<void> close() async {
    await Future.wait([
      _routes.close(),
      _sessions.close(),
      _outbox.close(),
      _tileMetadata.close(),
      _journeyHistory.close(),
    ]);
  }
}
