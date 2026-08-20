import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tulink_flutter/core/navigation/navigation_helper.dart';
import 'package:tulink_flutter/features/analytics/presentation/screens/journey_details_screen.dart';
import 'package:tulink_flutter/features/journeys/domain/entities/journey.dart';
import 'package:tulink_flutter/features/journeys/presentation/providers/journey_provider.dart';

/// Centralizes the rule for where a journey tap should land.
///
/// - COMPLETED / CANCELLED → [JourneyDetailsScreen] (analytics summary)
/// - Everything else (PENDING / ACTIVE / PAUSED) → the persistent Home map
///
/// A live or upcoming journey is no longer a *page*. Selecting it makes it the
/// current journey and returns to the shell, which stages it over the one map.
/// This keeps `JourneyProvider.currentJourney` the single source of truth: no
/// caller has to know how staging works, and none of them can drift from it.
class JourneyNavigation {
  JourneyNavigation._();

  static Future<void> open(BuildContext context, Journey journey) {
    final isHistorical =
        journey.status == JourneyStatus.COMPLETED ||
        journey.status == JourneyStatus.CANCELLED;

    if (isHistorical) {
      return Navigator.of(
        context,
      ).pushNamed(JourneyDetailsScreen.routeName, arguments: journey);
    }

    context.read<JourneyProvider>().setCurrentJourney(journey);
    return NavigationHelper.toHomeAndClearStack(context);
  }
}
