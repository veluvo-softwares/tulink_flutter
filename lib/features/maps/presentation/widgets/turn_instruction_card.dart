import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/tulink_colors.dart';
import '../../domain/entities/route_progress.dart';

/// Top-of-screen turn-by-turn instruction card.
///
/// Shows the user's next maneuver with a large directional arrow icon,
/// the distance until the maneuver, and the instruction text. Visible
/// only during active navigation (when [progress] is non-null).
///
/// Matches the design language of [JourneyProgressCard] — dark card on
/// Carbon Black, Electric Red accent for the arrow, Rajdhani for the
/// distance display, Inter for the instruction text.
class TurnInstructionCard extends StatelessWidget {
  const TurnInstructionCard({
    super.key,
    required this.progress,
    this.onToggleVoice,
    this.isVoiceEnabled = true,
  });

  final RouteProgress? progress;
  final VoidCallback? onToggleVoice;
  final bool isVoiceEnabled;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    if (p == null) return const SizedBox.shrink();

    final colors = Theme.of(context).extension<TulinkColors>()!;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      decoration: BoxDecoration(
        color: colors.carbonBlack,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.brushedSteel.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            _buildManeuverIcon(p, colors),
            const SizedBox(width: 16),
            Expanded(child: _buildInstructionBody(p, colors)),
            if (onToggleVoice != null) ...[
              const SizedBox(width: 12),
              _buildVoiceToggle(colors),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildManeuverIcon(RouteProgress p, TulinkColors colors) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: colors.electricRed.withOpacity(0.15),
        shape: BoxShape.circle,
      ),
      child: Icon(
        _iconForManeuver(p.currentManeuver.maneuverType),
        color: colors.electricRed,
        size: 32,
      ),
    );
  }

  Widget _buildInstructionBody(RouteProgress p, TulinkColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _formatDistance(p.distanceToNextManeuverMetres),
          style: GoogleFonts.rajdhani(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: colors.electricRed,
            height: 1.0,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          p.currentManeuver.instruction,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: colors.white,
            height: 1.3,
          ),
        ),
      ],
    );
  }

  Widget _buildVoiceToggle(TulinkColors colors) {
    return GestureDetector(
      onTap: onToggleVoice,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: colors.brushedSteel.withOpacity(0.3),
          shape: BoxShape.circle,
        ),
        child: Icon(
          isVoiceEnabled ? Icons.volume_up : Icons.volume_off,
          color: isVoiceEnabled ? colors.white : colors.silver,
          size: 20,
        ),
      ),
    );
  }

  /// Map Mapbox maneuver type tokens to Material icons.
  /// Coverage tuned for real Kenyan-road responses from the backend:
  /// `depart`, `turn`, `roundabout`, `rotary`, `fork`, `end of road`,
  /// `merge`, `arrive`, plus directional turn variants.
  IconData _iconForManeuver(String maneuverType) {
    switch (maneuverType) {
      case 'turn-right':
      case 'turn-slight-right':
        return Icons.turn_right;
      case 'turn-sharp-right':
        return Icons.turn_sharp_right;
      case 'turn-left':
      case 'turn-slight-left':
        return Icons.turn_left;
      case 'turn-sharp-left':
        return Icons.turn_sharp_left;
      case 'uturn':
        return Icons.u_turn_right;
      case 'straight':
      case 'depart':
      case 'continue':
        return Icons.straight;
      case 'merge':
        return Icons.merge;
      case 'fork':
        return Icons.call_split;
      case 'end of road':
        return Icons.turn_right;
      case 'roundabout':
      case 'rotary':
        return Icons.roundabout_right;
      case 'arrive':
        return Icons.flag;
      default:
        return Icons.straight;
    }
  }

  String _formatDistance(double metres) {
    if (metres >= 1000) {
      return '${(metres / 1000).toStringAsFixed(1)} km';
    }
    final rounded = (metres / 10).round() * 10;
    return '$rounded m';
  }
}
