import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tulink_flutter/features/analytics/presentation/screens/journey_history_screen.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/auth/presentation/screens/auth_screen.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/profile/presentation/screens/profile_screen.dart';
import '../theme/tulink_colors.dart';
import 'widgets/app_navbar.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  static const String routeName = '/main';

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const HomeScreen(),
    const JourneyHistoryScreen(),
    const ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, _) {
        final scaffold = Scaffold(
          body: _screens[_currentIndex],
          bottomNavigationBar: AppNavbar(
            currentIndex: _currentIndex,
            onTap: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
          ),
        );

        if (authProvider.isGuest) {
          final colors = Theme.of(context).extension<TulinkColors>()!;
          return Column(
            children: [
              Container(
                width: double.infinity,
                color: colors.brushedSteel,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.person_outline, color: colors.silver, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Guest Mode — Sign up to save your progress',
                        style: TextStyle(color: colors.silver, fontSize: 12),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context)
                          .pushReplacementNamed(AuthScreen.routeName),
                      style: TextButton.styleFrom(
                        foregroundColor: colors.electricRed,
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Sign Up',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(child: scaffold),
            ],
          );
        }

        return scaffold;
      },
    );
  }
}
