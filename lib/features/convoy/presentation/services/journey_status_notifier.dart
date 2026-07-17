import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../../maps/domain/entities/route_progress.dart';
import '../../domain/entities/convoy_snapshot.dart';
import 'journey_status_formatter.dart';

/// Android journey-status surface: a silent, ongoing notification showing
/// this driver's ETA/distance plus one distance-to-destination line per
/// convoy member — the glanceable "Uber trip" view while the app is
/// backgrounded (the location foreground service keeps the isolate alive,
/// so updates continue off-screen).
///
/// iOS has no equivalent ongoing-notification concept; the planned Live
/// Activity (see docs/backgrounding-and-widget-proposal.md) covers it and
/// this class is a no-op there.
class JourneyStatusNotifier {
  JourneyStatusNotifier({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const int _notificationId = 8801;
  static const String _channelId = 'journey_status';

  /// Floor between posts so a busy convoy doesn't spam the notification
  /// shade; member count or arrival changes bypass it.
  static const Duration _minUpdateInterval = Duration(seconds: 15);

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;
  DateTime? _lastPostedAt;
  int _lastMemberCount = -1;
  int _lastArrivedCount = -1;

  Future<void> _ensureInitialized() async {
    if (_initialized || !Platform.isAndroid) return;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(settings: settings);
    _initialized = true;
  }

  /// Post or refresh the status notification. Safe to call on every convoy
  /// snapshot / navigation frame — throttling happens here.
  Future<void> update({
    required String journeyName,
    required String selfUserId,
    required Map<String, String> displayNames,
    ConvoySnapshot? snapshot,
    RouteProgress? progress,
  }) async {
    if (!Platform.isAndroid) return;

    final memberCount = snapshot?.members.length ?? 0;
    final arrivedCount =
        snapshot?.members.values.where((m) => m.hasArrived).length ?? 0;
    final significantChange =
        memberCount != _lastMemberCount || arrivedCount != _lastArrivedCount;
    final now = DateTime.now();
    if (!significantChange &&
        _lastPostedAt != null &&
        now.difference(_lastPostedAt!) < _minUpdateInterval) {
      return;
    }
    _lastPostedAt = now;
    _lastMemberCount = memberCount;
    _lastArrivedCount = arrivedCount;

    await _ensureInitialized();

    final title = buildStatusTitle(
      journeyName: journeyName,
      etaSeconds: progress?.durationRemainingSeconds,
      distanceRemainingMeters: progress?.distanceRemainingMetres,
    );
    final lines = snapshot == null
        ? const <String>[]
        : buildMemberLines(
            members: snapshot.members,
            destination: snapshot.destination,
            displayNames: displayNames,
            selfUserId: selfUserId,
          );
    final body = lines.isEmpty
        ? 'Convoy running — you are the only member on the map'
        : lines.join('\n');

    await _plugin.show(
      id: _notificationId,
      title: title,
      body: lines.isEmpty ? body : lines.first,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Journey status',
          channelDescription:
              'Live convoy progress while a journey is running',
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          onlyAlertOnce: true,
          showWhen: false,
          styleInformation: BigTextStyleInformation(
            body,
            contentTitle: title,
          ),
        ),
      ),
    );
  }

  /// Remove the notification (journey ended / coordination stopped).
  Future<void> clear() async {
    if (!Platform.isAndroid || !_initialized) return;
    _lastPostedAt = null;
    _lastMemberCount = -1;
    _lastArrivedCount = -1;
    await _plugin.cancel(id: _notificationId);
  }
}
