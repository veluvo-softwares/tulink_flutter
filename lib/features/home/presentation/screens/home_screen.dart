import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tulink_flutter/features/analytics/presentation/screens/journey_history_screen.dart';
import 'package:tulink_flutter/features/auth/presentation/providers/auth_provider.dart';
import 'package:tulink_flutter/features/journeys/domain/usecases/journey_usecases.dart';
import 'package:tulink_flutter/features/journeys/presentation/pages/create_journey_screen.dart';
import 'package:tulink_flutter/features/maps/presentation/tulink_map_screen.dart';
import 'package:tulink_flutter/features/analytics/presentation/providers/analytics_provider.dart';
import 'package:tulink_flutter/features/journeys/presentation/providers/journey_provider.dart';
import '../../../../core/theme/tulink_colors.dart';
import '../../../../core/widgets/status_indicator.dart';
import '../widgets/dashboard_card.dart';
import '../widgets/journey_card.dart';
import '../widgets/recent_journey_item.dart';
import '../widgets/recent_journeys_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  static const String routeName = '/dashboard';

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AnalyticsProvider>().loadRecentJourneys();
      context.read<JourneyProvider>().fetchActiveJourneys();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;
    final user = context.watch<AuthProvider>().user;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "WELCOME BACK,",
                        style: TextStyle(
                          color: colors.silver,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        (user?.name ?? 'Champion').toUpperCase(),
                        style: TextStyle(
                          color: colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: colors.electricRed, width: 2),
                      shape: BoxShape.circle,
                    ),
                    child: CircleAvatar(
                      radius: 24,
                      backgroundColor: colors.brushedSteel,
                      child: Icon(Icons.person_rounded, color: colors.white),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 32),
              
              // New Journey Call To Action Card
              JourneyCard(
                title: "Start a journey",
                description: "Create a convoy and lead the pack",
                colors: [colors.electricRed, colors.electricRed.withValues(alpha: 0.8)],
                iconText: '🏁',
                onTap: () {
                  Navigator.of(context).pushNamed(CreateJourneyScreen.routeName);
                },
              ),

               const SizedBox(height: 16),
              
                 JourneyCard(
                title: "Join a journey",
                description: "Enter a code and join the formation",
                borderColor: colors.electricRed,
                onTap: () {},
              ),
              
            
              const SizedBox(height: 32),
              
              // Active Journeys Section
              Consumer<JourneyProvider>(
                builder: (context, journeyProvider, child) {
                  if (journeyProvider.activeJourneys.isNotEmpty) {
                    return Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "Active journeys",
                              style: TextStyle(
                                color: colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 16),
                        
                        // Active Journey Items
                        ...journeyProvider.activeJourneys.take(3).map((journey) => 
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: RecentJourneyItem(
                              title: journey.name,
                              date: _formatDate(journey.createdAt),
                              members: "${journey.participants?.length ?? 0} members",
                              status: "ACTIVE",
                              onTap: () => _navigateToJourneyPreview(journey.id),
                            ),
                          ),
                        ),
                        
                        const SizedBox(height: 24),
                      ],
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
              
              // Recent Journeys Section
              Consumer<AnalyticsProvider>(
                builder: (context, analyticsProvider, child) {
                  if (analyticsProvider.isLoading && analyticsProvider.recentJourneys.isEmpty) {
                    return Container(
                      height: 150,
                      alignment: Alignment.center,
                      child: const CircularProgressIndicator(),
                    );
                  }

                  if (analyticsProvider.error != null && analyticsProvider.recentJourneys.isEmpty) {
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colors.cardDark,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colors.brushedSteel.withOpacity(0.3)),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: colors.electricRed,
                            size: 32,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "Failed to load recent journeys",
                            style: TextStyle(
                              color: colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          GestureDetector(
                            onTap: () => analyticsProvider.refreshRecentJourneys(),
                            child: Text(
                              "Tap to retry",
                              style: TextStyle(
                                color: colors.electricRed,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return RecentJourneysCard(
                    journeys: analyticsProvider.recentJourneys,
                    onSeeAll: () => _navigateToJourneyHistory(),
                    onJourneyTap: (journey) => _navigateToJourneyDetails(journey),
                  );
                },
              ),
              
              const SizedBox(height: 120), // Space for Navbar and FAB
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).pushNamed(JourneyHistoryScreen.routeName),
        label: const Text("Journey History"),
        icon: const Icon(Icons.play_arrow_rounded),
      ),
    );
  }

  void _navigateToJourneyHistory() {
    Navigator.of(context).pushNamed('/journey-history');
  }

  void _navigateToJourneyDetails(journey) {
    Navigator.of(context).pushNamed('/journey-details', arguments: journey);
  }

  void _navigateToJourneyPreview(String journeyId) {
    Navigator.of(context).pushNamed('/journey-preview', arguments: journeyId);
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Unknown';
    
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else {
      return 'Recently';
    }
  }

  String _getStatusText(status) {
    switch (status.toString()) {
      case 'JourneyStatus.PENDING':
        return 'PENDING';
      case 'JourneyStatus.ACTIVE':
        return 'ACTIVE';
      case 'JourneyStatus.PAUSED':
        return 'PAUSED';
      case 'JourneyStatus.COMPLETED':
        return 'COMPLETED';
      case 'JourneyStatus.CANCELLED':
        return 'CANCELLED';
      default:
        return status.toString().split('.').last;
    }
  }
}