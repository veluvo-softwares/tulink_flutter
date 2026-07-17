import 'dart:math' as math;

import '../../domain/entities/convoy_snapshot.dart';
import '../../domain/entities/member_position.dart';

/// Pure formatting helpers for the background journey-status notification.
/// Kept free of platform imports so the copy is unit-testable.

/// "12 min" / "1 h 05 min"; sub-minute clamps to "1 min".
String formatEta(double seconds) {
  final minutes = (seconds / 60).round();
  if (minutes < 1) return '1 min';
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return '$hours h ${rest.toString().padLeft(2, '0')} min';
}

/// "850 m" below one kilometre, "3.4 km" above.
String formatDistance(double meters) {
  if (meters < 1000) return '${meters.round()} m';
  return '${(meters / 1000).toStringAsFixed(1)} km';
}

/// Great-circle distance in metres (haversine).
double distanceMeters(
  double lat1,
  double lng1,
  double lat2,
  double lng2,
) {
  const earthRadiusM = 6371000.0;
  final dLat = (lat2 - lat1) * math.pi / 180.0;
  final dLng = (lng2 - lng1) * math.pi / 180.0;
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * math.pi / 180.0) *
          math.cos(lat2 * math.pi / 180.0) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadiusM * c;
}

/// One "Name — 2.1 km" line per convoy member, ordered nearest-first with
/// arrived members last. The current user is skipped — their own progress is
/// the notification title line.
List<String> buildMemberLines({
  required Map<String, MemberPosition> members,
  required ConvoyDestination destination,
  required Map<String, String> displayNames,
  required String selfUserId,
}) {
  final entries =
      members.entries.where((entry) => entry.key != selfUserId).map((entry) {
        final position = entry.value;
        final name = displayNames[entry.key] ?? entry.key;
        final meters = distanceMeters(
          position.latitude,
          position.longitude,
          destination.latitude,
          destination.longitude,
        );
        return (
          name: name,
          meters: meters,
          arrived: position.hasArrived,
        );
      }).toList()..sort((a, b) {
        if (a.arrived != b.arrived) return a.arrived ? 1 : -1;
        return a.meters.compareTo(b.meters);
      });

  return [
    for (final entry in entries)
      entry.arrived
          ? '${entry.name} — arrived'
          : '${entry.name} — ${formatDistance(entry.meters)}',
  ];
}

/// Title line for the status notification.
String buildStatusTitle({
  required String journeyName,
  required double? etaSeconds,
  required double? distanceRemainingMeters,
}) {
  if (etaSeconds == null || distanceRemainingMeters == null) {
    return journeyName;
  }
  return '$journeyName — ${formatEta(etaSeconds)} · '
      '${formatDistance(distanceRemainingMeters)}';
}
