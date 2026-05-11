import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/models/navigation_step.dart';
import '../../../../core/theme/tulink_colors.dart';

/// Banner widget displaying current navigation instruction
/// Shows turn-by-turn directions with maneuver icons and distance
class NavigationInstructionBanner extends StatelessWidget {
  const NavigationInstructionBanner({
    super.key,
    required this.currentStep,
    this.nextStep,
    this.distanceToNext,
    this.onTap,
  });

  final NavigationStep currentStep;
  final NavigationStep? nextStep;
  final double? distanceToNext;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<TulinkColors>()!;
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: colors.carbonBlack,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.electricRed.withOpacity(0.3)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Maneuver Icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colors.electricRed.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _getManeuverIcon(currentStep.maneuver.iconName),
                  color: colors.electricRed,
                  size: 24,
                ),
              ),
              
              const SizedBox(width: 16),
              
              // Instruction Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Distance to next instruction
                    if (distanceToNext != null) ...[
                      Text(
                        _formatDistance(distanceToNext!),
                        style: GoogleFonts.poppins(
                          color: colors.electricRed,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                    ],
                    
                    // Current instruction
                    Text(
                      currentStep.instruction,
                      style: GoogleFonts.poppins(
                        color: colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    
                    // Street name if available
                    if (
                        currentStep.streetName.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'on ${currentStep.streetName}',
                        style: GoogleFonts.poppins(
                          color: colors.silver,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              
              // Next step preview (optional)
              if (nextStep != null) ...[
                const SizedBox(width: 16),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: colors.silver.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    _getManeuverIcon(nextStep!.maneuver.iconName),
                    color: colors.silver,
                    size: 16,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Get appropriate icon for maneuver type
  IconData _getManeuverIcon(String iconName) {
    switch (iconName.toLowerCase()) {
      case 'navigation':
      case 'depart':
        return Icons.navigation;
      case 'turn_left':
        return Icons.turn_left;
      case 'turn_right':
        return Icons.turn_right;
      case 'straight':
        return Icons.straight;
      case 'merge':
        return Icons.merge;
      case 'ramp':
        return Icons.ramp_left;
      case 'exit_ramp':
        return Icons.ramp_right;
      case 'fork':
        return Icons.call_split;
      case 'roundabout':
        return Icons.roundabout_left;
      case 'flag':
      case 'arrive':
        return Icons.flag;
      default:
        return Icons.navigation;
    }
  }

  /// Format distance for display
  String _formatDistance(double distanceInMeters) {
    if (distanceInMeters < 1000) {
      return '${distanceInMeters.round()} m';
    } else {
      final km = distanceInMeters / 1000;
      if (km < 10) {
        return '${km.toStringAsFixed(1)} km';
      } else {
        return '${km.round()} km';
      }
    }
  }
}

/// Compact navigation instruction banner for minimal UI
class CompactNavigationBanner extends StatelessWidget {
  const CompactNavigationBanner({
    super.key,
    required this.instruction,
    required this.distance,
    required this.iconName,
    this.onTap,
  });

  final String instruction;
  final double distance;
  final String iconName;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<TulinkColors>()!;
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: colors.carbonBlack.withOpacity(0.95),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.electricRed.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(
              _getManeuverIcon(iconName),
              color: colors.electricRed,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                instruction,
                style: GoogleFonts.poppins(
                  color: colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              _formatDistance(distance),
              style: GoogleFonts.poppins(
                color: colors.electricRed,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Get appropriate icon for maneuver type
  IconData _getManeuverIcon(String iconName) {
    switch (iconName.toLowerCase()) {
      case 'navigation':
      case 'depart':
        return Icons.navigation;
      case 'turn_left':
        return Icons.turn_left;
      case 'turn_right':
        return Icons.turn_right;
      case 'straight':
        return Icons.straight;
      case 'merge':
        return Icons.merge;
      case 'ramp':
        return Icons.ramp_left;
      case 'exit_ramp':
        return Icons.ramp_right;
      case 'fork':
        return Icons.call_split;
      case 'roundabout':
        return Icons.roundabout_left;
      case 'flag':
      case 'arrive':
        return Icons.flag;
      default:
        return Icons.navigation;
    }
  }

  /// Format distance for display
  String _formatDistance(double distanceInMeters) {
    if (distanceInMeters < 1000) {
      return '${distanceInMeters.round()} m';
    } else {
      final km = distanceInMeters / 1000;
      return '${km.toStringAsFixed(1)} km';
    }
  }
}