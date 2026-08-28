import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:live_activities/live_activities.dart';
import 'package:tulink_flutter/features/convoy/domain/entities/convoy_snapshot.dart';
import 'package:tulink_flutter/features/convoy/presentation/services/journey_status_formatter.dart';
import 'package:tulink_flutter/features/convoy/presentation/utils/convoy_member_presentation.dart';
import 'package:tulink_flutter/features/maps/domain/entities/route_progress.dart';

/// Glanceable journey-status surface while a journey is running — the
/// "Uber trip" view when the app is backgrounded (the location foreground
/// service keeps the isolate alive, so updates continue off-screen).
///
/// Android: a silent, ongoing notification showing this driver's
/// ETA/distance plus one distance-to-destination line per convoy member.
///
/// iOS: a Live Activity (lock screen + Dynamic Island) rendered by the
/// TulinkJourneyWidget extension; data crosses via the app-group
/// UserDefaults contract of the live_activities plugin.
class JourneyStatusNotifier {
  /// Creates the platform journey-status surface coordinator.
  JourneyStatusNotifier({
    FlutterLocalNotificationsPlugin? plugin,
    LiveActivities? liveActivities,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
       _liveActivities = liveActivities ?? LiveActivities();

  static const int _notificationId = 8801;
  static const String _channelId = 'journey_status';
  static const String _appGroupId = 'group.xyz.tulink.app';

  /// Qualified Android resource used as the notification's default icon.
  ///
  /// Keep this aligned with `android:icon` in AndroidManifest.xml. A missing
  /// resource makes flutter_local_notifications throw during initialization;
  /// this previously terminated the journey-start flow on Android.
  @visibleForTesting
  static const String androidNotificationIcon = '@mipmap/launcher_icon';

  /// Member rows rendered on the iOS lock-screen activity (height budget).
  static const int _maxLiveActivityMembers = 3;

  /// Floor between posts so a busy convoy doesn't spam the surface;
  /// member count or arrival changes bypass it.
  static const Duration _minUpdateInterval = Duration(seconds: 15);

  final FlutterLocalNotificationsPlugin _plugin;
  final LiveActivities _liveActivities;
  bool _androidInitialized = false;
  bool _iosInitialized = false;
  String? _activityId;
  DateTime? _lastPostedAt;
  int _lastMemberCount = -1;
  int _lastArrivedCount = -1;

  /// Post or refresh the status surface. Safe to call on every convoy
  /// snapshot / navigation frame — throttling happens here.
  Future<void> update({
    required String journeyName,
    required String selfUserId,
    required Map<String, ConvoyMemberPresentation> presentation,
    ConvoySnapshot? snapshot,
    RouteProgress? progress,
    int rosterMemberCount = 0,
  }) async {
    final platform = defaultTargetPlatform;
    if (platform != TargetPlatform.android && platform != TargetPlatform.iOS) {
      return;
    }

    final memberCount = math.max(
      snapshot?.members.length ?? 0,
      rosterMemberCount,
    );
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

    final displayNames = {
      for (final entry in presentation.entries)
        entry.key: entry.value.displayName,
    };
    final title = buildStatusTitle(
      journeyName: journeyName,
      etaSeconds: progress?.durationRemainingSeconds,
      distanceRemainingMeters: progress?.distanceRemainingMetres,
    );
    final entries = snapshot == null
        ? const <MemberStatusEntry>[]
        : buildMemberEntries(
            members: snapshot.members,
            destination: snapshot.destination,
            displayNames: displayNames,
            selfUserId: selfUserId,
          );

    try {
      if (platform == TargetPlatform.android) {
        await _updateAndroid(title, entries, memberCount);
      } else {
        await _updateIos(title, entries, presentation, progress, memberCount);
      }
    } catch (error, stackTrace) {
      // Journey status is an optional secondary surface. A missing native
      // notification resource, denied notification capability, or Live
      // Activity failure must never escape into the active journey lifecycle.
      debugPrint('Could not update journey status surface: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _updateAndroid(
    String title,
    List<MemberStatusEntry> entries,
    int memberCount,
  ) async {
    if (!_androidInitialized) {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings(androidNotificationIcon),
      );
      await _plugin.initialize(settings: settings);
      _androidInitialized = true;
    }

    final lines = entries.map(memberLine).toList();
    final body = lines.isEmpty
        ? memberCount > 1
              ? '$memberCount people in convoy — waiting for shared locations'
              : 'Convoy running — you are the only member on the map'
        : lines.join('\n');

    await _plugin.show(
      id: _notificationId,
      title: title,
      body: lines.isEmpty ? body : lines.first,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Journey status',
          channelDescription: 'Live convoy progress while a journey is running',
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          onlyAlertOnce: true,
          showWhen: false,
          styleInformation: BigTextStyleInformation(body, contentTitle: title),
        ),
      ),
    );
  }

  Future<void> _updateIos(
    String title,
    List<MemberStatusEntry> entries,
    Map<String, ConvoyMemberPresentation> presentation,
    RouteProgress? progress,
    int memberCount,
  ) async {
    if (!_iosInitialized) {
      await _liveActivities.init(appGroupId: _appGroupId);
      _iosInitialized = true;
    }
    if (!await _liveActivities.areActivitiesEnabled()) return;

    final data = buildLiveActivityData(
      title: title,
      entries: entries,
      presentation: presentation,
      progress: progress,
      totalMemberCount: memberCount,
    );

    final existing = _activityId;
    if (existing == null) {
      _activityId = await _liveActivities.createActivity(
        'journey-status',
        data,
        removeWhenAppIsKilled: true,
      );
    } else {
      await _liveActivities.updateActivity(existing, data);
    }
  }

  /// The app-group payload the TulinkJourneyWidget extension renders.
  ///
  /// Every member slot is written, including the empty ones. The widget reads
  /// these keys from app-group UserDefaults, which outlive any single
  /// activity: a slot left unwritten keeps whatever the previous journey put
  /// there, which is how a solo journey came to show a member — and their
  /// distance — inherited from an earlier convoy. An empty value decodes to no
  /// row on the Swift side, so blanking is enough to clear one.
  @visibleForTesting
  Map<String, dynamic> buildLiveActivityData({
    required String title,
    required List<MemberStatusEntry> entries,
    required Map<String, ConvoyMemberPresentation> presentation,
    RouteProgress? progress,
    int? totalMemberCount,
  }) {
    final visible = entries.take(_maxLiveActivityMembers).toList();
    return <String, dynamic>{
      'title': title,
      'subtitle': progress != null
          ? formatEta(progress.durationRemainingSeconds)
          : (totalMemberCount ?? entries.length + 1) <= 1
          ? 'Solo journey'
          : '${totalMemberCount ?? entries.length + 1} in convoy',
      'extraMembers': entries.length - visible.length,
      for (var i = 0; i < _maxLiveActivityMembers; i++)
        'member$i': i < visible.length
            ? _encodeMemberRow(visible[i], presentation)
            : '',
    };
  }

  /// "INITIALS|Name — 2.1 km|#RRGGBB|arrivedFlag" — the pipe-separated row
  /// contract of MemberRow.decode in the TulinkJourneyWidget extension.
  String _encodeMemberRow(
    MemberStatusEntry entry,
    Map<String, ConvoyMemberPresentation> presentation,
  ) {
    final identity = presentation[entry.userId];
    final initials =
        identity?.initials ?? ConvoyMemberPresentation.initialsFor(entry.name);
    final argb = (identity?.color ?? ConvoyMemberPresentation.palette.first)
        .toARGB32();
    final hex =
        '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
    final line = memberLine(entry).replaceAll('|', '/');
    final safeInitials = initials.replaceAll('|', '/');
    return '$safeInitials|$line|$hex|${entry.arrived ? 1 : 0}';
  }

  /// Remove the surface (journey ended / coordination stopped).
  Future<void> clear() async {
    _lastPostedAt = null;
    _lastMemberCount = -1;
    _lastArrivedCount = -1;
    if (defaultTargetPlatform == TargetPlatform.android &&
        _androidInitialized) {
      await _plugin.cancel(id: _notificationId);
    }
    if (defaultTargetPlatform == TargetPlatform.iOS && _iosInitialized) {
      _activityId = null;
      await _liveActivities.endAllActivities();
    }
  }
}
