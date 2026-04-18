import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/tulink_colors.dart';
import '../../../../features/journeys/domain/entities/journey.dart';
import '../../../journeys/presentation/pages/create_journey_screen.dart';
import '../../../../features/journeys/presentation/providers/journey_provider.dart';

class MapJourneyOverlay extends StatelessWidget {
  const MapJourneyOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;
    final journeyProvider = context.watch<JourneyProvider>();
    final activeJourney = journeyProvider.currentJourney;
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.cardDark,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: colors.brushedSteel,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            if (activeJourney == null)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pushNamed(CreateJourneyScreen.routeName),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.electricRed,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text("CREATE NEW JOURNEY"),
                ),
              )
            else ...[
              // Journey Stats
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStat(context, "DISTANCE", "0.0", "KM"),
                  _buildStat(context, "TIME", "00:00", "MIN"),
                  _buildStat(context, "PACE", "0:00", "/KM"),
                ],
              ),
              
              const SizedBox(height: 24),
              
              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: activeJourney.status == JourneyStatus.PENDING 
                        ? () => journeyProvider.startJourney(activeJourney.id)
                        : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.electricRed,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: Text(activeJourney.status == JourneyStatus.PENDING ? "START JOURNEY" : "ACTIVE"),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: colors.brushedSteel,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: IconButton(
                      onPressed: () {},
                      icon: Icon(Icons.stop_rounded, color: colors.electricRed, size: 28),
                      padding: const EdgeInsets.all(12),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStat(BuildContext context, String label, String value, String unit) {
    final colors = Theme.of(context).tulinkColors;
    
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: colors.silver,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: value,
                style: TextStyle(
                  color: colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const WidgetSpan(child: SizedBox(width: 4)),
              TextSpan(
                text: unit,
                style: TextStyle(
                  color: colors.silver,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
