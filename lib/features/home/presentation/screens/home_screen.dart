import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tulink_flutter/features/analytics/presentation/screens/journey_history_screen.dart';
import 'package:tulink_flutter/features/auth/presentation/providers/auth_provider.dart';
import 'package:tulink_flutter/features/journeys/presentation/pages/create_journey_screen.dart';
import 'package:tulink_flutter/features/analytics/presentation/providers/analytics_provider.dart';
import 'package:tulink_flutter/features/journeys/presentation/providers/journey_provider.dart';
import 'package:tulink_flutter/features/profile/presentation/screens/profile_screen.dart';
import '../../../../core/theme/tulink_colors.dart';
import '../widgets/journey_card.dart';
import '../widgets/journeys_card.dart';

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
      _refreshData();
    });
  }

  Future<void> _refreshData() async {
    await Future.wait([
      context.read<AnalyticsProvider>().loadRecentJourneys(),
      context.read<JourneyProvider>().fetchActiveJourneys(),
      context.read<AnalyticsProvider>().loadJourneyHistory(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;
    final user = context.watch<AuthProvider>().user;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refreshData,
          color: colors.electricRed,
          backgroundColor: colors.cardDark,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            physics: const AlwaysScrollableScrollPhysics(),
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
                  GestureDetector(
                    onTap: _navigateToProfile,
                    child: SizedBox(
                      width: 54,
                      height: 54,
                      child: Stack(
                        children: [
                          // Main Avatar Container
                          Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: colors.electricRed,
                                width: 3,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: colors.electricRed.withValues(alpha: 0.3),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Container(
                              margin: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [
                                    colors.brushedSteel,
                                    colors.brushedSteel.withValues(alpha: 0.8),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  _getInitials(user?.name ?? 'User'),
                                  style: TextStyle(
                                    color: colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          
                          // Online Status Indicator
                          Positioned(
                            bottom: 3,
                            right: 3,
                            child: Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.green,
                                border: Border.all(
                                  color: colors.carbonBlack,
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.green.withValues(alpha: 0.4),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
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
                  return JourneysCard(
                    title: 'Active Journeys',
                    journeys: journeyProvider.activeJourneys,
                    showParticipants: true,
                    isLoading: journeyProvider.isLoading && journeyProvider.activeJourneys.isEmpty,
                    onJourneyTap: (journey) => _navigateToJourneyPreview(journey.id),
                  );
                },
              ),
              
              const SizedBox(height: 32),
              
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

                  return JourneysCard(
                    title: 'Recent Journeys',
                    journeys: analyticsProvider.recentJourneys,
                    showParticipants: false,
                    isLoading: analyticsProvider.isLoading && analyticsProvider.recentJourneys.isEmpty,
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

  void _navigateToJourneyDetails(dynamic journey) {
    Navigator.of(context).pushNamed('/journey-details', arguments: journey);
  }

  void _navigateToJourneyPreview(String journeyId) {
    Navigator.of(context).pushNamed('/journey-preview', arguments: journeyId);
  }

  void _navigateToProfile() {
    Navigator.of(context).pushNamed(ProfileScreen.routeName);
  }

  String _getInitials(String name) {
    final nameParts = name.split(' ');
    if (nameParts.length >= 2) {
      return '${nameParts[0][0]}${nameParts[1][0]}'.toUpperCase();
    } else if (nameParts.isNotEmpty) {
      return nameParts[0][0].toUpperCase();
    }
    return 'U';
  }
}