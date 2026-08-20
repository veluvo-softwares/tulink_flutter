import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tulink_flutter/core/navigation/widgets/app_navbar.dart';
import 'package:tulink_flutter/features/home/presentation/screens/home_screen.dart';
import 'package:tulink_flutter/features/home/presentation/state/map_experience_state.dart';
import 'package:tulink_flutter/features/invites/presentation/providers/invite_provider.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  static const String routeName = '/main';

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  /// The authoritative map experience, written by [HomeScreen].
  ///
  /// The shell deliberately does **not** derive this itself. Starting, ending
  /// and the completion summary are Home-local transient state, so a second
  /// derivation here would be blind to exactly the transitions that matter and
  /// would disagree with Home about whether tabs may be shown.
  final ValueNotifier<MapExperienceState> _experience =
      ValueNotifier<MapExperienceState>(MapExperienceState.exploring);

  @override
  void dispose() {
    _experience.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MapExperienceState>(
      valueListenable: _experience,
      builder: (context, experience, _) {
        return Scaffold(
          // A single HomeScreen owns Mapbox for every tab. Journeys and Invites
          // are map overlays instead of separate pages, so switching tabs keeps
          // camera position, the journey draft, and map rendering alive.
          //
          // `resizeToAvoidBottomInset: false` keeps the map from being resized
          // by a keyboard during a critical transition.
          resizeToAvoidBottomInset: false,
          body: HomeScreen(
            selectedTab: _currentIndex,
            onTabSelected: (index) => setState(() => _currentIndex = index),
            experience: _experience,
          ),
          bottomNavigationBar: experience.hidesNavigationTabs
              ? null
              : AppNavbar(
                  currentIndex: _currentIndex,
                  invitationCount: context
                      .watch<InviteProvider>()
                      .pendingInvitationCount,
                  onTap: (index) => setState(() => _currentIndex = index),
                ),
        );
      },
    );
  }
}
