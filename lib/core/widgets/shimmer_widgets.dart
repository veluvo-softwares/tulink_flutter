import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../theme/tulink_colors.dart';

/// A collection of reusable shimmer components for loading states
/// Usage: Shimmer.Card(), Shimmer.JourneyCard(), etc.
class ShimmerWidgets {
  ShimmerWidgets._();

  /// Basic card shimmer for general card loading states
  static Widget card(BuildContext context, {double? height, double? width}) {
    final colors = Theme.of(context).tulinkColors;
    
    return Shimmer.fromColors(
      baseColor: colors.cardDark,
      highlightColor: colors.brushedSteel.withValues(alpha: 0.3),
      child: Container(
        height: height ?? 150,
        width: width ?? double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: colors.cardDark,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: colors.brushedSteel.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
      ),
    );
  }

  /// Journey card specific shimmer that matches JourneysCard layout
  static Widget journeyCard(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colors.brushedSteel.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Shimmer.fromColors(
        baseColor: colors.brushedSteel.withValues(alpha: 0.2),
        highlightColor: colors.brushedSteel.withValues(alpha: 0.4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header shimmer
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  height: 18,
                  width: 120,
                  decoration: BoxDecoration(
                    color: colors.brushedSteel,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Container(
                  height: 14,
                  width: 50,
                  decoration: BoxDecoration(
                    color: colors.brushedSteel,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Journey items shimmer
            ...List.generate(3, (index) => Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      // Icon shimmer
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: colors.brushedSteel,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      
                      const SizedBox(width: 12),
                      
                      // Content shimmer
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              height: 16,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: colors.brushedSteel,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              height: 12,
                              width: 150,
                              decoration: BoxDecoration(
                                color: colors.brushedSteel,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(width: 12),
                      
                      // Status shimmer
                      Container(
                        width: 60,
                        height: 20,
                        decoration: BoxDecoration(
                          color: colors.brushedSteel,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ],
                  ),
                ),
                if (index < 2)
                  Container(
                    height: 1,
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    color: colors.brushedSteel.withValues(alpha: 0.3),
                  ),
              ],
            )),
          ],
        ),
      ),
    );
  }

  /// List item shimmer for individual journey items
  static Widget listItem(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;
    
    return Shimmer.fromColors(
      baseColor: colors.brushedSteel.withValues(alpha: 0.2),
      highlightColor: colors.brushedSteel.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: Row(
          children: [
            // Icon shimmer
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colors.brushedSteel,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            
            const SizedBox(width: 12),
            
            // Content shimmer
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 16,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: colors.brushedSteel,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    height: 12,
                    width: 120,
                    decoration: BoxDecoration(
                      color: colors.brushedSteel,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(width: 12),
            
            // Status shimmer
            Container(
              width: 60,
              height: 20,
              decoration: BoxDecoration(
                color: colors.brushedSteel,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Text line shimmer for individual text elements
  static Widget textLine(BuildContext context, {double? width, double height = 16}) {
    final colors = Theme.of(context).tulinkColors;
    
    return Shimmer.fromColors(
      baseColor: colors.brushedSteel.withValues(alpha: 0.2),
      highlightColor: colors.brushedSteel.withValues(alpha: 0.4),
      child: Container(
        height: height,
        width: width ?? 100,
        decoration: BoxDecoration(
          color: colors.brushedSteel,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }

  /// Circle shimmer for avatars and circular elements
  static Widget circle(BuildContext context, {double radius = 24}) {
    final colors = Theme.of(context).tulinkColors;
    
    return Shimmer.fromColors(
      baseColor: colors.brushedSteel.withValues(alpha: 0.2),
      highlightColor: colors.brushedSteel.withValues(alpha: 0.4),
      child: Container(
        width: radius * 2,
        height: radius * 2,
        decoration: BoxDecoration(
          color: colors.brushedSteel,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// Convenient access to shimmer widgets using dot notation
/// Usage: ShimmerEffect.card(context), ShimmerEffect.journeyCard(context)
class ShimmerEffect {
  static Widget card(BuildContext context, {double? height, double? width}) =>
      ShimmerWidgets.card(context, height: height, width: width);
  
  static Widget journeyCard(BuildContext context) =>
      ShimmerWidgets.journeyCard(context);
  
  static Widget listItem(BuildContext context) =>
      ShimmerWidgets.listItem(context);
  
  static Widget textLine(BuildContext context, {double? width, double height = 16}) =>
      ShimmerWidgets.textLine(context, width: width, height: height);
  
  static Widget circle(BuildContext context, {double radius = 24}) =>
      ShimmerWidgets.circle(context, radius: radius);
}