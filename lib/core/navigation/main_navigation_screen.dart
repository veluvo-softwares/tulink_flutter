import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tulink_flutter/core/navigation/widgets/app_navbar.dart';
import 'package:tulink_flutter/features/home/presentation/screens/home_screen.dart';
import 'package:tulink_flutter/features/invites/presentation/providers/invite_provider.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  static const String routeName = '/main';

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // A single HomeScreen owns Mapbox for every tab. Journeys and Invites
      // are map overlays instead of separate pages, so switching tabs keeps
      // camera position, the journey draft, and map rendering alive.
      body: HomeScreen(
        selectedTab: _currentIndex,
        onTabSelected: (index) => setState(() => _currentIndex = index),
      ),
      bottomNavigationBar: AppNavbar(
        currentIndex: _currentIndex,
        invitationCount: context.watch<InviteProvider>().pendingInvitationCount,
        onTap: (index) => setState(() => _currentIndex = index),
      ),
    );
  }
}
