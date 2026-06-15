import 'dart:async';
import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

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

  /// Foreground messages and notification taps, surfaced so the app can react
  /// (e.g. refresh the invite list, show a banner).
  Stream<RemoteMessage> get messages => _messageController.stream;

  /// Initialise FCM. Call once the user is authenticated — registering the
  /// token hits an authenticated backend endpoint. Safe to call repeatedly.
  Future<void> init() async {
    if (_initialized) return;
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
        print('📩 FCM foreground: ${message.notification?.title} ${message.data}');
        if (!_messageController.isClosed) _messageController.add(message);
      });

      // User tapped a notification that opened the app from the background.
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        print('📲 FCM opened app: ${message.data}');
        if (!_messageController.isClosed) _messageController.add(message);
      });
    } catch (e) {
      print('❌ Failed to initialise push notifications: $e');
    }
  }

  Future<void> _registerCurrentToken() async {
    try {
      final token = await _messaging.getToken();
      if (token != null) {
        await _registerToken(token);
      }
    } catch (e) {
      print('❌ Failed to get FCM token: $e');
    }
  }

  Future<void> _registerToken(String token) async {
    try {
      await _dio.post(
        '/notifications/fcm-token',
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

  Future<void> dispose() async {
    await _tokenRefreshSub?.cancel();
    if (!_messageController.isClosed) await _messageController.close();
  }
}
