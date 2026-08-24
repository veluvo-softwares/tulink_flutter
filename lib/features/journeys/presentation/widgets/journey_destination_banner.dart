import 'package:flutter/material.dart';

import '../../../../core/theme/tulink_colors.dart';
import '../../domain/entities/journey.dart';

/// Map-free destination header for journey detail surfaces.
///
/// Replaces the former `JourneyPreviewMap`, which instantiated a second Mapbox
/// widget purely to render a thumbnail. The product direction is that all
/// map-focused functionality uses the single persistent Home map, so these
/// secondary surfaces show the destination without standing up another map.
class JourneyDestinationBanner extends StatelessWidget {
  const JourneyDestinationBanner({super.key, required this.journey});

  final Journey journey;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;
    final subtitle = journey.destinationSubtitle;

    return Semantics(
      label: 'Destination: ${journey.destinationLabel}',
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: colors.warmSand,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: colors.sunsetOrange.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.location_on_rounded,
                color: colors.sunsetOrange,
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'DESTINATION',
                    style: TextStyle(
                      color: colors.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    journey.destinationLabel,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.ink,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colors.muted, fontSize: 13),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
