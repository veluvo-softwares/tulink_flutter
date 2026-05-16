import 'package:flutter/material.dart';
import 'package:tulink_flutter/features/analytics/presentation/screens/journey_details_screen.dart';
import 'package:tulink_flutter/features/journeys/domain/entities/journey.dart';
import 'package:tulink_flutter/features/journeys/presentation/pages/journey_preview_screen.dart';

/// Centralizes the rule for where a journey tap should land.
///
/// - COMPLETED / CANCELLED → [JourneyDetailsScreen] (analytics summary)
/// - Everything else (PENDING / ACTIVE / PAUSED) → [JourneyPreviewScreen]
///   (manage participants, start/resume)
class JourneyNavigation {
  JourneyNavigation._();

  static Future<void> open(BuildContext context, Journey journey) {
    final isHistorical = journey.status == JourneyStatus.COMPLETED ||
        journey.status == JourneyStatus.CANCELLED;

    if (isHistorical) {
      return Navigator.of(context).pushNamed(
        JourneyDetailsScreen.routeName,
        arguments: journey,
      );
    }

    return Navigator.of(context).pushNamed(
      JourneyPreviewScreen.routeName,
      arguments: journey.id,
    );
  }
}
