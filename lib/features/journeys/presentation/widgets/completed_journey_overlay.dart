import 'package:flutter/material.dart';

import '../../../../core/theme/tulink_colors.dart';
import '../../domain/entities/journey.dart';

/// Completion summary shown over the map the journey was driven on.
///
/// This replaces pushing a details screen when a journey ends. The shell
/// clears live route artifacts as soon as completion is confirmed, so the
/// summary remains over the same map without leaking finished geometry back
/// into the exploring state.
class CompletedJourneyOverlay extends StatelessWidget {
  const CompletedJourneyOverlay({
    super.key,
    required this.journey,
    required this.onDismiss,
    this.onViewDetails,
    this.isDismissing = false,
  });

  final Journey journey;

  /// Dismiss the summary and return the map to exploring.
  final VoidCallback onDismiss;

  /// Open the full record. Optional — the summary stands on its own.
  final VoidCallback? onViewDetails;

  /// True while the finished journey is being cleared off the shared map.
  ///
  /// The summary deliberately stays up for the whole cleanup: returning to
  /// "exploring" before the route, destination, peers and puck are actually
  /// gone showed a map that still had the finished journey drawn on it, and
  /// let the next journey start drawing into a surface being erased.
  final bool isDismissing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;
    final subtitle = journey.destinationSubtitle;

    return Stack(
      children: [
        // Scrim: dismissible, so the summary never traps the user on a map
        // they can no longer interact with.
        Positioned.fill(
          child: GestureDetector(
            onTap: isDismissing ? null : onDismiss,
            child: ColoredBox(color: Colors.black.withValues(alpha: 0.45)),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: colors.sunsetOrange.withValues(alpha: 0.14),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.flag_rounded,
                            color: colors.sunsetOrange,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Journey complete',
                                style: TextStyle(
                                  color: colors.ink,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                journey.destinationLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colors.muted,
                                  fontSize: 14,
                                ),
                              ),
                              if (subtitle != null)
                                Text(
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: colors.muted,
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        if (onViewDetails != null) ...[
                          Expanded(
                            child: OutlinedButton(
                              onPressed: onViewDetails,
                              child: const Text('View details'),
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: FilledButton(
                            onPressed: isDismissing ? null : onDismiss,
                            child: isDismissing
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Done'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
