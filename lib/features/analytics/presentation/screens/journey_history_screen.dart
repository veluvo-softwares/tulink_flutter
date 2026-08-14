import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/tulink_colors.dart';
import '../../../../core/widgets/status_indicator.dart';
import '../../../journeys/domain/entities/journey.dart';
import '../../../journeys/presentation/utils/journey_navigation.dart';
import '../../../journeys/presentation/widgets/journey_info_card.dart';
import '../providers/analytics_provider.dart';

class JourneyHistoryScreen extends StatefulWidget {
  const JourneyHistoryScreen({super.key});

  static const String routeName = '/journey-history';

  @override
  State<JourneyHistoryScreen> createState() => _JourneyHistoryScreenState();
}

class _JourneyHistoryScreenState extends State<JourneyHistoryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AnalyticsProvider>().loadJourneyHistory();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;

    return Scaffold(
      backgroundColor: colors.warmSand,
      appBar: AppBar(title: const Text('Journey history')),
      body: Consumer<AnalyticsProvider>(
        builder: (context, analyticsProvider, child) {
          if (analyticsProvider.isLoading &&
              analyticsProvider.journeyHistory.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (analyticsProvider.error != null &&
              analyticsProvider.journeyHistory.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    color: colors.sunsetOrange,
                    size: 56,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Failed to load journey history',
                    style: TextStyle(
                      color: colors.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    analyticsProvider.error!,
                    style: TextStyle(color: colors.muted, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => analyticsProvider.loadJourneyHistory(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          if (analyticsProvider.journeyHistory.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.route_outlined, color: colors.routeTeal, size: 56),
                  const SizedBox(height: 16),
                  Text(
                    'No journeys yet',
                    style: TextStyle(
                      color: colors.ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Create your first journey to get started',
                    style: TextStyle(color: colors.muted, fontSize: 14),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => analyticsProvider.loadJourneyHistory(),
            color: colors.routeTeal,
            backgroundColor: colors.surface,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: analyticsProvider.journeyHistory.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final journey = analyticsProvider.journeyHistory[index];
                return _JourneyHistoryItem(
                  journey: journey,
                  onTap: () => _navigateToJourneyDetails(journey),
                );
              },
            ),
          );
        },
      ),
    );
  }

  void _navigateToJourneyDetails(Journey journey) {
    JourneyNavigation.open(context, journey);
  }
}

class _JourneyHistoryItem extends StatelessWidget {
  final Journey journey;
  final VoidCallback onTap;

  const _JourneyHistoryItem({required this.journey, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;

    return Semantics(
      button: true,
      label: '${journey.name}, ${journey.destinationAddress}',
      child: JourneyInfoCard(
        margin: EdgeInsets.zero,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Journey name and status
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        journey.name,
                        style: TextStyle(
                          color: colors.ink,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    StatusIndicator(status: journey.status),
                  ],
                ),

                const SizedBox(height: 12),

                // Destination
                Row(
                  children: [
                    Icon(
                      Icons.location_on,
                      color: colors.sunsetOrange,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        journey.destinationAddress,
                        style: TextStyle(color: colors.muted, fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // Info row
                Row(
                  children: [
                    // Lag threshold
                    Icon(Icons.speed, color: colors.muted, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      '${journey.lagThresholdMeters}m',
                      style: TextStyle(color: colors.muted, fontSize: 12),
                    ),

                    const SizedBox(width: 16),

                    // Participants count
                    Icon(Icons.group, color: colors.muted, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      '${journey.participants?.length ?? 0} participants',
                      style: TextStyle(color: colors.muted, fontSize: 12),
                    ),

                    const Spacer(),

                    // Created date
                    Text(
                      _formatDate(journey.createdAt),
                      style: TextStyle(color: colors.muted, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Unknown';

    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 30) {
      return '${date.month}/${date.year}';
    } else if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inMinutes}m ago';
    }
  }
}
