import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/navigation/navigation_helper.dart';
import '../../journeys/domain/entities/journey.dart';
import '../../journeys/presentation/providers/journey_provider.dart';

/// Compatibility entry point for the retired `/mapview` route.
///
/// The map is no longer a destination you navigate to — there is one persistent
/// map hosted by the Home shell, and a journey becomes live *on it*. This route
/// survives only so that an external entry point still naming `/mapview` — a
/// notification payload, a deep link, a stale build — lands correctly instead
/// of on the undefined-route screen.
///
/// It deliberately contains no map. What it does do is **preserve journey
/// identity**: a legacy link that named a journey must still open that journey,
/// not dump the user on a generic map.
class MapRouteRedirectScreen extends StatefulWidget {
  const MapRouteRedirectScreen({super.key, this.arguments});

  static const String routeName = '/mapview';

  /// The legacy route argument, in whatever shape the old call sites passed.
  final Object? arguments;

  /// Extract a journey id from the argument shapes this repository actually
  /// used for `/mapview`: a bare id string, or a map carrying `journeyId`/`id`.
  ///
  /// Returns null for anything else — including empty strings and the
  /// placeholder values that stale payloads carry — so a malformed argument
  /// degrades to "just show the map" rather than requesting a bogus journey.
  static String? journeyIdFrom(Object? arguments) {
    String? normalise(Object? value) {
      if (value is! String) return null;
      final trimmed = value.trim();
      if (trimmed.isEmpty) return null;
      if (trimmed == 'null' || trimmed == 'undefined') return null;
      return trimmed;
    }

    if (arguments is String) return normalise(arguments);
    if (arguments is Map) {
      return normalise(arguments['journeyId']) ?? normalise(arguments['id']);
    }
    return null;
  }

  @override
  State<MapRouteRedirectScreen> createState() => _MapRouteRedirectScreenState();
}

class _MapRouteRedirectScreenState extends State<MapRouteRedirectScreen> {
  /// Guards against re-entering the redirect if this route is somehow rebuilt
  /// before it is popped — a redirect that can fire twice can loop.
  bool _redirected = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _redirect());
  }

  void _redirect() {
    if (!mounted || _redirected) return;
    _redirected = true;

    final journeyId = MapRouteRedirectScreen.journeyIdFrom(
      widget.arguments ?? ModalRoute.of(context)?.settings.arguments,
    );

    // Making the journey current is the whole handoff: the shell adopts
    // whatever journey is current and stages it over the persistent map, so
    // this route never needs to know about rooms, routes or coordination.
    if (journeyId != null) {
      final journeys = context.read<JourneyProvider>();
      final known = _findKnownJourney(journeys, journeyId);
      if (known != null) {
        journeys.setCurrentJourney(known);
      } else {
        // Not in memory (cold start from a notification). Fetch it; the shell
        // adopts it when it arrives, and a stale id simply fails to resolve.
        unawaited(journeys.fetchJourneyById(journeyId));
      }
    }

    NavigationHelper.toHomeAndClearStack(context);
  }

  Journey? _findKnownJourney(JourneyProvider journeys, String journeyId) {
    if (journeys.currentJourney?.id == journeyId)
      return journeys.currentJourney;
    for (final journey in journeys.activeJourneys) {
      if (journey.id == journeyId) return journey;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
