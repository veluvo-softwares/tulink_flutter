import 'package:flutter/material.dart';
import 'package:tulink_flutter/features/maps/presentation/tulink_map_screen.dart';
import '../../../../core/theme/tulink_colors.dart';
import '../widgets/dashboard_card.dart';
import '../widgets/journey_card.dart';
import '../widgets/recent_journey_item.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const String routeName = '/dashboard';

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;
    
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
                        "CHAMPION!",
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
                onTap: () {},
              ),

               const SizedBox(height: 16),
              
                 JourneyCard(
                title: "Join a journey",
                description: "Enter a code and join the formation",
                borderColor: colors.electricRed,
                onTap: () {},
              ),
              
            
              const SizedBox(height: 32),
              
              // Recent Activity Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Recent journeys",
                    style: TextStyle(
                      color: colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                    ),
                  ),
                  Text(
                    "See all",
                    style: TextStyle(
                      color: colors.electricRed,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 16),
              
              // Optimized Recent Journey Item
              RecentJourneyItem(
                title: "Miami -> Orlando",
                date: "Jan 15",
                members: "4 members",
                status: "ACTIVE",
                onTap: () {},
              ),
              
              const SizedBox(height: 120), // Space for Navbar and FAB
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).pushNamed(TulinkMapScreen.routeName),
        label: const Text("START JOURNEY"),
        icon: const Icon(Icons.play_arrow_rounded),
      ),
    );
  }
}