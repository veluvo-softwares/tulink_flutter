import 'dart:async';
import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../network/api_routes.dart';
import '../utils/logger.dart';

/// Handles Firebase Cloud Messaging: notification permission, registering the
/// device token with the backend, and surfacing incoming messages to the app
/// (so it can refresh data and show in-app banners without a manual reload).
class PushNotificationService {
  PushNotificationService(this._dio);

  final Dio _dio;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  bool _initialized = false;
  StreamSubscription<String>? _tokenRefreshSub;

  final StreamController<RemoteMessage> _messageController =
      StreamController<RemoteMessage>.broadcast();
  final StreamController<RemoteMessage> _notificationTapController =
      StreamController<RemoteMessage>.broadcast();
  RemoteMessage? _initialNotificationTap;

  /// Foreground messages, surfaced so the app can refresh data and show a
  /// banner without treating receipt as a user navigation intent.
  Stream<RemoteMessage> get messages => _messageController.stream;

  /// Messages whose system notification was explicitly tapped by the user.
  Stream<RemoteMessage> get notificationTaps =>
      _notificationTapController.stream;

  /// Consume the notification that launched a previously terminated app.
  RemoteMessage? takeInitialNotificationTap() {
    final message = _initialNotificationTap;
    _initialNotificationTap = null;
    return message;
  }

  /// Initialise FCM. Call once the user is authenticated — registering the
  /// token hits an authenticated backend endpoint. Safe to call repeatedly.
  Future<void> init() async {
    if (_initialized) {
      // Listeners are already wired, but a sign-out in this same app session
      // may have unlinked the token (removeCurrentToken); re-register so the
      // new session's device row exists on the backend. The backend upserts
      // on (userId, token), so repeating this is harmless.
      await _registerCurrentToken();
      return;
    }
    _initialized = true;

    try {
      await _messaging.requestPermission(alert: true, badge: true, sound: true);

      // Show heads-up notifications while the app is foregrounded (iOS).
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      await _registerCurrentToken();

      _tokenRefreshSub = _messaging.onTokenRefresh.listen(
        _registerToken,
        onError: (Object e) => print('❌ FCM token refresh error: $e'),
      );

      // App in foreground: deliver to listeners (no OS notification shown).
      FirebaseMessaging.onMessage.listen((message) {
        print(
          '📩 FCM foreground: ${message.notification?.title} ${message.data}',
        );
        if (!_messageController.isClosed) _messageController.add(message);
      });

      // User tapped a notification that opened the app from the background.
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        print('📲 FCM opened app: ${message.data}');
        if (!_notificationTapController.isClosed) {
          _notificationTapController.add(message);
        }
      });

      // A notification may have launched a fully terminated app. Keep it
      // buffered until authenticated home navigation is mounted and ready.
      _initialNotificationTap = await _messaging.getInitialMessage();
    } catch (e) {
      print('❌ Failed to initialise push notifications: $e');
    }
  }

  Future<void> _registerCurrentToken() async {
    try {
      if (Platform.isIOS && await _messaging.getAPNSToken() == null) {
        // On iOS, getToken() requires the native APNs device token to be set
        // first. That arrives asynchronously (a round-trip to APNs) after
        // requestPermission() resolves, so calling getToken() immediately
        // after almost always throws. There's no completion callback for
        // this, so poll briefly rather than failing the first attempt.
        if (!await _waitForApnsToken()) {
          print(
            '❌ APNs token not available after waiting — skipping FCM registration',
          );
          return;
        }
      }

      final token = await _messaging.getToken();
      if (token != null) {
        await _registerToken(token);
      }
    } catch (e) {
      print('❌ Failed to get FCM token: $e');
    }
  }

  Future<bool> _waitForApnsToken() async {
    for (var attempt = 0; attempt < 10; attempt++) {
      await Future.delayed(const Duration(seconds: 1));
      if (await _messaging.getAPNSToken() != null) return true;
    }
    return false;
  }

  Future<void> _registerToken(String token) async {
    try {
      await _dio.post(
        ApiRoutes.fcmToken,
        data: {
          'fcmToken': token,
          'platform': Platform.isIOS ? 'ios' : 'android',
        },
      );
      print('✅ FCM token registered with backend');
    } catch (e) {
      print('❌ Failed to register FCM token with backend: $e');
    }
  }

  /// Bounds how long sign-out waits on the token unlink. Dio's own timeouts
  /// (30s) plus the retry interceptor could otherwise hold the sign-out
  /// spinner for minutes on a dead network; past this bound sign-out proceeds
  /// and the request is abandoned to finish (or fail) in the background.
  static const Duration _unlinkTimeout = Duration(seconds: 5);

  /// Unlink this device's token from the backend on logout. MUST be called
  /// while the user is still authenticated — the endpoint is auth-guarded — so
  /// invoke it BEFORE clearing the session. Best-effort: never throws and is
  /// bounded by [_unlinkTimeout], so it can't block sign-out. Removing only
  /// this device's token (not all of the user's tokens) keeps their other
  /// devices' notifications intact, and stops the next user on this device
  /// from receiving the previous user's pushes.
  Future<void> removeCurrentToken() async {
    try {
      final token = await _messaging.getToken();
      if (token == null) return;
      await _dio
          .delete<void>(ApiRoutes.fcmToken, data: {'fcmToken': token})
          .timeout(_unlinkTimeout);
      AppLogger.info('FCM token unregistered from backend');
    } catch (e) {
      AppLogger.warning(
        'Failed to unregister FCM token (continuing sign-out)',
        e,
      );
    }
  }

  Future<void> dispose() async {
    await _tokenRefreshSub?.cancel();
    if (!_messageController.isClosed) await _messageController.close();
    if (!_notificationTapController.isClosed) {
      await _notificationTapController.close();
    }
  }
}
