import 'package:equatable/equatable.dart';

/// Represents a single navigation instruction step
class NavigationStep extends Equatable {
  const NavigationStep({
    required this.distance,
    required this.duration,
    required this.geometry,
    required this.instruction,
    required this.maneuver,
    this.name,
    this.mode,
    this.drivingSide,
    this.intersections,
  });

  /// Distance for this step in meters
  final double distance;

  /// Duration for this step in seconds
  final double duration;

  /// Geometry for this step (encoded polyline)
  final String geometry;

  /// Human-readable instruction for this step
  final String instruction;

  /// Maneuver information for this step
  final StepManeuver maneuver;

  /// Name of the way/street for this step
  final String? name;

  /// Mode of transport for this step
  final String? mode;

  /// Which side of the road to drive on
  final String? drivingSide;

  /// List of intersections along this step
  final List<StepIntersection>? intersections;

  /// Get formatted distance for this step
  String get formattedDistance {
    if (distance < 1000) {
      return '${distance.round()} m';
    }
    final km = distance / 1000;
    return '${km.toStringAsFixed(1)} km';
  }

  /// Get formatted duration for this step
  String get formattedDuration {
    final minutes = (duration / 60).round();
    if (minutes < 1) return '< 1min';
    return '${minutes}min';
  }

  /// Get the primary direction for this step
  String get primaryDirection {
    return maneuver.type;
  }

  /// Get the street name or fallback instruction
  String get streetName {
    return name ?? instruction;
  }

  @override
  List<Object?> get props => [
        distance,
        duration,
        geometry,
        instruction,
        maneuver,
        name,
        mode,
        drivingSide,
        intersections,
      ];
}

/// Represents maneuver information for a navigation step
class StepManeuver extends Equatable {
  const StepManeuver({
    required this.type,
    required this.instruction,
    required this.bearingBefore,
    required this.bearingAfter,
    required this.location,
    this.modifier,
  });

  /// Type of maneuver (turn, depart, arrive, etc.)
  final String type;

  /// Instruction for the maneuver
  final String instruction;

  /// Bearing before the maneuver in degrees
  final double bearingBefore;

  /// Bearing after the maneuver in degrees
  final double bearingAfter;

  /// Location of the maneuver [longitude, latitude]
  final List<double> location;

  /// Modifier for the maneuver (left, right, straight, etc.)
  final String? modifier;

  /// Get the icon name for this maneuver type
  String get iconName {
    switch (type.toLowerCase()) {
      case 'depart':
        return 'navigation';
      case 'turn':
        if (modifier?.contains('left') == true) {
          return 'turn_left';
        } else if (modifier?.contains('right') == true) {
          return 'turn_right';
        }
        return 'straight';
      case 'merge':
        return 'merge';
      case 'on ramp':
      case 'ramp':
        return 'ramp';
      case 'off ramp':
        return 'exit_ramp';
      case 'fork':
        return 'fork';
      case 'roundabout':
      case 'rotary':
        return 'roundabout';
      case 'arrive':
        return 'flag';
      default:
        return 'straight';
    }
  }

  @override
  List<Object?> get props => [
        type,
        instruction,
        bearingBefore,
        bearingAfter,
        location,
        modifier,
      ];
}

/// Represents an intersection along a navigation step
class StepIntersection extends Equatable {
  const StepIntersection({
    required this.location,
    required this.bearings,
    required this.entry,
    this.in_,
    this.out,
  });

  /// Location of the intersection [longitude, latitude]
  final List<double> location;

  /// List of bearings for roads at this intersection
  final List<int> bearings;

  /// List indicating which roads can be entered
  final List<bool> entry;

  /// Index of the bearing the route enters the intersection on
  final int? in_;

  /// Index of the bearing the route exits the intersection on
  final int? out;

  @override
  List<Object?> get props => [location, bearings, entry, in_, out];
}

/// Common maneuver types
class ManeuverType {
  static const String depart = 'depart';
  static const String turn = 'turn';
  static const String merge = 'merge';
  static const String onRamp = 'on ramp';
  static const String offRamp = 'off ramp';
  static const String fork = 'fork';
  static const String endOfRoad = 'end of road';
  static const String continueRoute = 'continue';
  static const String roundabout = 'roundabout';
  static const String rotary = 'rotary';
  static const String roundaboutTurn = 'roundabout turn';
  static const String arrive = 'arrive';
}

/// Common maneuver modifiers
class ManeuverModifier {
  static const String uturn = 'uturn';
  static const String sharpRight = 'sharp right';
  static const String right = 'right';
  static const String slightRight = 'slight right';
  static const String straight = 'straight';
  static const String slightLeft = 'slight left';
  static const String left = 'left';
  static const String sharpLeft = 'sharp left';
}