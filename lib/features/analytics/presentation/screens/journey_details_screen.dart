import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/tulink_colors.dart';
import '../../../../core/widgets/status_indicator.dart';
import '../../../journeys/domain/entities/journey.dart';
import '../../../journeys/presentation/widgets/journey_preview_map.dart';
import '../../../journeys/presentation/providers/journey_provider.dart';
import '../providers/analytics_provider.dart';

class JourneyDetailsScreen extends StatefulWidget {
  final Journey journey;
  final bool showDoneButton;

  const JourneyDetailsScreen({
    super.key,
    required this.journey,
    this.showDoneButton = false,
  });

  static const String routeName = '/journey-details';

  @override
  State<JourneyDetailsScreen> createState() => _JourneyDetailsScreenState();
}

class _JourneyDetailsScreenState extends State<JourneyDetailsScreen> {
  @override
  void initState() {
    super.initState();
    // Post-trip screen — load summary statistics for the completed journey
    if (widget.showDoneButton ||
        widget.journey.status == JourneyStatus.COMPLETED) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.read<AnalyticsProvider>().loadJourneySummary(
            widget.journey.id,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;
    final journey = widget.journey;
    final showDoneButton = widget.showDoneButton;
    final showJourneyStats = journey.status == JourneyStatus.COMPLETED;

    return Scaffold(
      backgroundColor: colors.carbonBlack,
      body: SingleChildScrollView(
        child: Column(
          children: [
            // App Bar
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(
                        Icons.arrow_back,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Journey Details',
                      style: TextStyle(
                        color: colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(width: 48), // Balance the back button
                  ],
                ),
              ),
            ),

            // Compact Map View
            Container(
              height: 180,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colors.brushedSteel.withValues(alpha: 0.3),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: JourneyPreviewMap(journey: journey),
              ),
            ),

            const SizedBox(height: 20),

            // Journey Title and Status
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      journey.name,
                      style: TextStyle(
                        color: colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  StatusIndicator(
                    status: journey.status,
                    fontSize: 12,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Subtitle
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    'CONVOY • ',
                    style: TextStyle(
                      color: colors.silver,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    journey.createdAt != null
                        ? 'CREATED ${_getTimeAgo(journey.createdAt)}'
                        : 'CREATED RECENTLY',
                    style: TextStyle(
                      color: colors.silver,
                      fontSize: 12,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Destination Card (without edit button)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.cardDark,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colors.brushedSteel.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.location_on, color: colors.electricRed, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'DESTINATION',
                          style: TextStyle(
                            color: colors.silver,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          journey.destinationAddress,
                          style: TextStyle(
                            color: colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Journey Info Cards Row
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _buildInfoCard(
                      colors,
                      'TYPE',
                      'Convoy',
                      Icons.route,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildInfoCard(
                      colors,
                      'LAG LIMIT',
                      '${journey.lagThresholdMeters}m',
                      Icons.speed,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildInfoCard(
                      colors,
                      'DRIVERS',
                      '${journey.participants?.length ?? 1}',
                      Icons.group,
                    ),
                  ),
                ],
              ),
            ),

            // Journey Stats Section — only shown on post-trip summary
            if (showJourneyStats) ...[
              const SizedBox(height: 16),
              Consumer<AnalyticsProvider>(
                builder: (context, analytics, _) {
                  if (analytics.isSummaryLoading) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }
                  final summary = analytics.currentSummary;
                  if (summary == null) {
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colors.cardDark,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              analytics.summaryError ??
                                  'Journey statistics are still being prepared.',
                              style: TextStyle(color: colors.silver),
                            ),
                          ),
                          TextButton(
                            onPressed: () =>
                                analytics.loadJourneySummary(journey.id),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    );
                  }

                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TRIP STATS',
                          style: TextStyle(
                            color: colors.silver,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildStatCard(
                                colors,
                                'LEADER DISTANCE',
                                summary.distanceDisplay,
                                Icons.straighten,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildStatCard(
                                colors,
                                'DURATION',
                                summary.durationDisplay,
                                Icons.timer,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _buildStatCard(
                                colors,
                                'LEADER AVG SPEED',
                                summary.avgSpeedDisplay,
                                Icons.speed,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildStatCard(
                                colors,
                                'LAG ALERTS',
                                summary.lagAlertCount.toString(),
                                Icons.warning_amber,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _buildStatCard(
                                colors,
                                'DRIVERS',
                                summary.participantCount.toString(),
                                Icons.group,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildStatCard(
                                colors,
                                'COMPLETED',
                                _formatDateTime(summary.endTime),
                                Icons.flag,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],

            const SizedBox(height: 20),

            // Done Button (for completed journeys)
            if (showDoneButton) ...[
              Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                child: ElevatedButton(
                  onPressed: () => _navigateToHomeAndRefresh(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.electricRed,
                    foregroundColor: colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Done',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 40), // Extra padding for bottom
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(
    TulinkColors colors,
    String title,
    String value,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.cardDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.brushedSteel.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: colors.electricRed, size: 20),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              color: colors.silver,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    TulinkColors colors,
    String label,
    String value,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.cardDark,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.brushedSteel.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colors.electricRed, size: 18),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: colors.silver,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  /// Navigate to home screen and refresh data
  Future<void> _navigateToHomeAndRefresh(BuildContext context) async {
    final analyticsProvider = context.read<AnalyticsProvider>();
    final journeyProvider = context.read<JourneyProvider>();

    // Show loading indicator while refreshing data
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // Refresh data: loadJourneyHistory and fetchActiveJourneys
      await Future.wait([
        analyticsProvider.loadJourneyHistory(),
        journeyProvider.fetchActiveJourneys(),
      ]);

      if (context.mounted) {
        // Dismiss loading dialog
        Navigator.of(context).pop();

        // Navigate to home screen (clear all routes)
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/home', (route) => false);
      }
    } catch (e) {
      if (context.mounted) {
        // Dismiss loading dialog
        Navigator.of(context).pop();

        // Show error but still navigate
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Data refresh failed: $e'),
            backgroundColor: Colors.red,
          ),
        );

        // Navigate to home anyway
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/home', (route) => false);
      }
    }
  }

  String _getTimeAgo(DateTime? date) {
    if (date == null) return 'UNKNOWN TIME';

    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 30) {
      final months = (difference.inDays / 30).floor();
      return '${months}MO AGO';
    } else if (difference.inDays > 0) {
      return '${difference.inDays}D AGO';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}H AGO';
    } else {
      return 'RECENTLY';
    }
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) return 'Pending';
    final local = value.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.day}/${local.month} $hour:$minute';
  }
}
