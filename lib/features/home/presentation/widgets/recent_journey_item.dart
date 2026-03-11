import 'package:flutter/material.dart';
import '../../../../core/theme/tulink_colors.dart';

class RecentJourneyItem extends StatelessWidget {
  final String title; // Represents "From -> To"
  final String date;
  final String members; // e.g., "4 members"
  final String status; // e.g., "ACTIVE"
  final VoidCallback? onTap;

  const RecentJourneyItem({
    super.key,
    required this.title,
    required this.date,
    required this.members,
    this.status = "ACTIVE",
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            color: colors.cardDark,
            // No border needed as per the image, purely solid card
          ),
          child: IntrinsicHeight(
            child: Row(
              children: [
                // Left Vertical Stripe
                Container(
                  width: 10,
                  color: colors.electricRed,
                ),
                
                // Content Area
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16, 
                      vertical: 20
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Left Text Info
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "$date • $members",
                              style: TextStyle(
                                color: colors.silver,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        
                        // Right Status Badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16, 
                            vertical: 8
                          ),
                          decoration: BoxDecoration(
                            color: colors.electricRed,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            status.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}