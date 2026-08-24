import '../../../convoy/domain/entities/convoy_snapshot.dart';
import '../../../journeys/domain/entities/journey.dart';

/// What the single Home map is currently being used for.
///
/// The map is one persistent surface: starting, joining, resuming, driving and
/// completing a journey all happen on it. This enum names the phases of that
/// lifecycle so overlays and controls can be driven from one derived value
/// rather than a drift-prone collection of independent booleans.
///
/// It is **derived**, never stored: [resolveMapExperienceState] computes it
/// from the authoritative journey, convoy and draft state, so there is no
/// second journey lifecycle that can disagree with the providers.
enum MapExperienceState {
  /// No draft and no journey — the user is just looking at the map.
  exploring,

  /// A destination (and optionally companions) has been chosen but the journey
  /// has not been created yet.
  drafting,

  /// Create/start is in flight.
  starting,

  /// An invited member has joined a journey the leader has not started yet.
  waitingForLeader,

  /// A journey is ACTIVE and the convoy connection is healthy.
  liveConvoy,

  /// A journey is ACTIVE but the convoy connection is not currently healthy.
  /// The map stays live; the overlay offers recovery.
  recovering,

  /// End-journey is in flight.
  ending,

  /// The journey finished and its summary is being shown over the map.
  completed,
}

/// Derive the map experience from authoritative state.
///
/// Ordering matters: transient in-flight operations ([isEnding], [isStarting])
/// and a pending completion summary outrank the steady-state values, so the map
/// never flickers back to an earlier phase while an operation is resolving.
MapExperienceState resolveMapExperienceState({
  required Journey? currentJourney,
  required Journey? completedJourney,
  required bool hasDraft,
  required bool isStarting,
  required bool isEnding,
  required bool isCurrentUserLeader,
  required ConvoyConnectionState connectionState,
}) {
  if (isEnding) return MapExperienceState.ending;

  // A completed journey awaiting its summary outranks the same journey (or an
  // empty selection), but never a newer selected journey. A late completion
  // callback from A must not cover an already-active B with A's summary.
  if (completedJourney != null &&
      (currentJourney == null || currentJourney.id == completedJourney.id)) {
    return MapExperienceState.completed;
  }

  if (isStarting) return MapExperienceState.starting;

  if (currentJourney != null) {
    switch (currentJourney.status) {
      case JourneyStatus.ACTIVE:
        return _isConnectionHealthy(connectionState)
            ? MapExperienceState.liveConvoy
            : MapExperienceState.recovering;
      case JourneyStatus.PENDING:
        // A member who accepted an invitation can only wait; the leader still
        // owns the draft and its Start control.
        return isCurrentUserLeader
            ? MapExperienceState.drafting
            : MapExperienceState.waitingForLeader;
      case JourneyStatus.PAUSED:
        return MapExperienceState.recovering;
      case JourneyStatus.COMPLETED:
      case JourneyStatus.CANCELLED:
        // Terminal but not held for a summary — fall through to the draft or
        // exploring state below rather than pinning the map to a dead journey.
        break;
    }
  }

  return hasDraft ? MapExperienceState.drafting : MapExperienceState.exploring;
}

/// Only a genuinely connected socket counts as healthy.
///
/// Deliberately identical to `ConvoyStatusBar._hasLiveSnapshot`'s rule: if the
/// two disagreed, the map could present a live experience while the status bar
/// called the same data stale.
bool _isConnectionHealthy(ConvoyConnectionState state) {
  switch (state) {
    case ConvoyConnectionState.connected:
      return true;
    case ConvoyConnectionState.connecting:
    case ConvoyConnectionState.disconnected:
    case ConvoyConnectionState.reconnecting:
    case ConvoyConnectionState.error:
      return false;
  }
}

/// Convenience predicates used by the Home overlays.
extension MapExperienceStateX on MapExperienceState {
  /// A journey is under way on the map (live or recovering).
  bool get isJourneyRunning =>
      this == MapExperienceState.liveConvoy ||
      this == MapExperienceState.recovering;

  /// The map is showing journey geometry that must not be cleared.
  bool get holdsJourneyGeometry =>
      isJourneyRunning ||
      this == MapExperienceState.starting ||
      this == MapExperienceState.ending ||
      this == MapExperienceState.waitingForLeader;

  /// Leaving the map would abandon something in progress.
  bool get isBusy =>
      this == MapExperienceState.starting || this == MapExperienceState.ending;

  /// The journey owns the whole screen, so the shell's tab bar must be hidden.
  ///
  /// Tabs navigate to overlays that are not rendered in these states, so
  /// leaving the bar visible would offer destinations that cannot be honoured.
  /// This lives here, next to the state it reads, so the navigation shell
  /// cannot drift from Home's view of the same moment.
  bool get hidesNavigationTabs =>
      isJourneyRunning ||
      this == MapExperienceState.waitingForLeader ||
      this == MapExperienceState.starting ||
      this == MapExperienceState.ending ||
      this == MapExperienceState.completed;
}
