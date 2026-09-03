import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tulink_flutter/core/navigation/navigation_helper.dart';
import 'package:tulink_flutter/core/layout/tulink_breakpoints.dart';
import 'package:tulink_flutter/core/theme/tulink_colors.dart';
import 'package:tulink_flutter/core/utils/journey_stats_calculator.dart';
import 'package:tulink_flutter/features/analytics/presentation/providers/analytics_provider.dart';
import 'package:tulink_flutter/features/auth/presentation/providers/auth_provider.dart';
import 'package:tulink_flutter/features/convoy/presentation/providers/convoy_provider.dart';
import 'package:tulink_flutter/features/maps/presentation/providers/navigation_provider.dart';
import 'package:tulink_flutter/features/profile/presentation/widgets/profile_avatar.dart';
import 'package:tulink_flutter/features/profile/presentation/widgets/profile_stats_grid.dart';
import 'package:tulink_flutter/features/profile/presentation/widgets/settings_menu_item.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  static const String routeName = '/profile';

  /// Pop result asking the shell to select the Journeys overlay. Journey
  /// history is part of the map-focused experience, so the profile hands the
  /// user back to it instead of pushing a separate full-page history screen.
  static const String showJourneysResult = 'show-journeys';

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
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
    final user = context.watch<AuthProvider>().user;
    final journeys = context.watch<AnalyticsProvider>().journeyHistory;
    final userId = user?.id ?? '';
    final journeyCount = JourneyStatsCalculator.calculateParticipationCount(
      journeys,
      userId,
    );
    final totalDistance = JourneyStatsCalculator.calculateTotalDistance(
      journeys,
    );
    final leadershipCount = JourneyStatsCalculator.calculateLeadershipCount(
      journeys,
      userId,
    );

    final overview = Column(
      children: [
        _ProfileHero(
          name: user?.name ?? 'Traveller',
          email: user?.email ?? 'driver@tulink.app',
          imageUrl: user?.profilePicture,
          isVerified: user?.isEmailVerified ?? false,
        ),
        const SizedBox(height: 18),
        ProfileStatsGrid(
          journeyCount: journeyCount,
          totalDistance: totalDistance,
          leaderboardPosition: leadershipCount,
        ),
      ],
    );

    final accountDetails = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: 'Your travel',
          actionLabel: 'View journeys',
          onAction: () =>
              Navigator.of(context).pop(ProfileScreen.showJourneysResult),
        ),
        const SizedBox(height: 10),
        _TravelSummaryCard(
          journeyCount: journeyCount,
          onTap: () =>
              Navigator.of(context).pop(ProfileScreen.showJourneysResult),
        ),
        const SizedBox(height: 28),
        const _SectionHeader(title: 'Preferences'),
        const SizedBox(height: 10),
        _SettingsGroup(
          children: [
            Consumer<NavigationProvider>(
              builder: (context, navigation, _) => SettingsMenuItem(
                icon: Icons.record_voice_over_outlined,
                title: 'Voice navigation',
                subtitle: 'Hear turns and convoy updates',
                showArrow: false,
                onTap: () =>
                    navigation.setVoiceEnabled(!navigation.isVoiceEnabled),
                trailing: Switch.adaptive(
                  value: navigation.isVoiceEnabled,
                  onChanged: navigation.setVoiceEnabled,
                  activeTrackColor: colors.routeTeal,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        const _SectionHeader(title: 'Account'),
        const SizedBox(height: 10),
        _SettingsGroup(
          children: [
            SettingsMenuItem(
              icon: Icons.logout_rounded,
              title: 'Sign out',
              titleColor: Theme.of(context).colorScheme.error,
              iconColor: Theme.of(context).colorScheme.error,
              showArrow: false,
              onTap: _showSignOutDialog,
            ),
          ],
        ),
      ],
    );

    return Scaffold(
      backgroundColor: colors.warmSand,
      appBar: AppBar(
        leading: IconButton.filledTonal(
          tooltip: 'Back to map',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Profile'),
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, _) => SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              TulinkBreakpoints.isWideLandscape(context) ? 32 : 20,
              12,
              TulinkBreakpoints.isWideLandscape(context) ? 32 : 20,
              36,
            ),
            child: TulinkBreakpoints.isWideLandscape(context)
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 4, child: overview),
                      const SizedBox(width: 28),
                      Expanded(flex: 6, child: accountDetails),
                    ],
                  )
                : Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          overview,
                          const SizedBox(height: 28),
                          accountDetails,
                        ],
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Future<void> _showSignOutDialog() async {
    final shouldSignOut = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.logout_rounded),
        title: const Text('Sign out?'),
        content: const Text(
          'You will need to sign in again before starting or joining '
          'a journey.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (shouldSignOut != true || !mounted) return;
    await context.read<ConvoyProvider>().stopUserChannel();
    if (!mounted) return;
    final signedOut = await context.read<AuthProvider>().signOut();
    if (!mounted || !signedOut) return;

    // Profile is pushed above HomePage. AuthProvider has already rebuilt that
    // root to AuthScreen; remove the stale authenticated routes so the user
    // sees it immediately instead of having to press Back manually.
    await NavigationHelper.toHomeAndClearStack(context);
  }
}

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({
    required this.name,
    required this.email,
    required this.imageUrl,
    required this.isVerified,
  });

  final String name;
  final String email;
  final String? imageUrl;
  final bool isVerified;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        children: [
          ProfileAvatar(
            initials: _initials(name),
            imageUrl: imageUrl,
            isOnline: true,
            size: 92,
          ),
          const SizedBox(height: 16),
          Text(
            name,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 4),
          Text(
            email,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: colors.routeTeal.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isVerified ? Icons.verified_rounded : Icons.person_rounded,
                  size: 16,
                  color: colors.deepTeal,
                ),
                const SizedBox(width: 6),
                Text(
                  isVerified ? 'Verified traveller' : 'Tulink traveller',
                  style: TextStyle(
                    color: colors.deepTeal,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TravelSummaryCard extends StatelessWidget {
  const _TravelSummaryCard({required this.journeyCount, required this.onTap});

  final int journeyCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;
    return Material(
      color: colors.deepTeal,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(Icons.route_rounded, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      journeyCount == 0
                          ? 'Your journeys start here'
                          : '$journeyCount journeys together',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      journeyCount == 0
                          ? 'Choose a destination from the map'
                          : 'Revisit a route or travel together again',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .75),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_rounded, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        children: [
          for (var index = 0; index < children.length; index++) ...[
            children[index],
            if (index < children.length - 1)
              Divider(height: 1, indent: 68, color: colors.divider),
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({this.title, this.actionLabel, this.onAction});

  final String? title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title ?? '',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        if (actionLabel != null)
          TextButton(onPressed: onAction, child: Text(actionLabel!)),
      ],
    );
  }
}

String _initials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    return parts.first
        .substring(0, parts.first.length.clamp(1, 2))
        .toUpperCase();
  }
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}
