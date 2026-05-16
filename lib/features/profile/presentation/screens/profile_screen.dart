import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tulink_flutter/features/analytics/presentation/screens/journey_history_screen.dart';
import '../../../../core/theme/tulink_colors.dart';
import '../../../../core/utils/journey_stats_calculator.dart';
import '../../../../core/widgets/status_indicator.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../analytics/presentation/providers/analytics_provider.dart';
import '../../../journeys/domain/entities/journey.dart';
import '../../../journeys/presentation/utils/journey_navigation.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/profile_stats_grid.dart';
import '../widgets/settings_menu_item.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  static const String routeName = '/profile';

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Load profile stats
      context.read<AnalyticsProvider>().loadJourneyHistory();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;
    final authProvider = context.watch<AuthProvider>();
    final analyticsProvider = context.watch<AnalyticsProvider>();
    final user = authProvider.user;

    return Scaffold(
      backgroundColor: colors.carbonBlack,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            children: [
              // Profile Header
              Text(
                'PROFILE',
                style: TextStyle(
                  color: colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
              
              const SizedBox(height: 32),
              
              // Profile Avatar with Status
              ProfileAvatar(
                initials: _getInitials(user?.name ?? 'User'),
                isOnline: true, // You can determine this from your app state
              ),
              
              const SizedBox(height: 16),
              
              // User Name
              Text(
                user?.name ?? 'Racer',
                style: TextStyle(
                  color: colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              
              const SizedBox(height: 8),
              
              // User Email
              Text(
                user?.email ?? 'driver@tulink.app',
                style: TextStyle(
                  color: colors.silver,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Edit Profile Button
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: colors.cardDark,
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(
                    color: colors.brushedSteel.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.edit,
                      color: colors.electricRed,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Edit Profile',
                      style: TextStyle(
                        color: colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 32),
              
              // Profile Stats Grid
              ProfileStatsGrid(
                journeyCount: JourneyStatsCalculator.calculateParticipationCount(
                  analyticsProvider.journeyHistory,
                  user?.id ?? '',
                ),
                totalDistance: JourneyStatsCalculator.calculateTotalDistance(
                  analyticsProvider.journeyHistory,
                ),
                leaderboardPosition: JourneyStatsCalculator.calculateLeadershipCount(
                  analyticsProvider.journeyHistory,
                  user?.id ?? '',
                ),
              ),
              
              const SizedBox(height: 32),
              // Settings Section
              Container(
                width: double.infinity,
                alignment: Alignment.centerLeft,
                child: Text(
                  'SETTINGS',
                  style: TextStyle(
                    color: colors.silver,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
            
              // Settings Menu Items
              Container(
                decoration: BoxDecoration(
                  color: colors.cardDark,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colors.brushedSteel.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Column(
                  children: [
                    SettingsMenuItem(
                      icon: Icons.notifications_outlined,
                      title: 'Notifications',
                      onTap: () => _navigateToNotifications(),
                    ),
                    _buildDivider(colors),
                    SettingsMenuItem(
                      icon: Icons.privacy_tip_outlined,
                      title: 'Privacy',
                      onTap: () => _navigateToPrivacy(),
                    ),
                    _buildDivider(colors),
                    SettingsMenuItem(
                      icon: Icons.link,
                      title: 'Linked Accounts',
                      onTap: () => _navigateToLinkedAccounts(),
                    ),
                    _buildDivider(colors),
                    SettingsMenuItem(
                      icon: Icons.help_outline,
                      title: 'Help & Support',
                      onTap: () => _navigateToSupport(),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Sign Out Button
              Container(
                decoration: BoxDecoration(
                  color: colors.cardDark,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colors.electricRed.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: SettingsMenuItem(
                  icon: Icons.logout,
                  title: 'Sign Out',
                  titleColor: colors.electricRed,
                  iconColor: colors.electricRed,
                  showArrow: false,
                  onTap: () => _showSignOutDialog(),
                ),
              ),
              
              const SizedBox(height: 100), // Bottom padding for navigation
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildJourneysLoadingState(TulinkColors colors) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colors.brushedSteel.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white54,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Loading journeys...',
            style: TextStyle(
              color: colors.silver,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyJourneysState(TulinkColors colors) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colors.brushedSteel.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.route_outlined,
            color: colors.silver,
            size: 32,
          ),
          const SizedBox(height: 8),
          Text(
            'No journeys yet',
            style: TextStyle(
              color: colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Create your first journey to get started',
            style: TextStyle(
              color: colors.silver,
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildJourneyItem(Journey journey, TulinkColors colors) {
    return InkWell(
      onTap: () => _navigateToJourneyDetails(journey),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                      color: colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                StatusIndicator(status: journey.status, fontSize: 10),
              ],
            ),
            
            const SizedBox(height: 8),
            
            // Destination
            Row(
              children: [
                Icon(
                  Icons.location_on,
                  color: colors.electricRed,
                  size: 14,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    journey.destinationAddress,
                    style: TextStyle(
                      color: colors.silver,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 6),
            
            // Info row
            Row(
              children: [
                Icon(
                  Icons.group,
                  color: colors.silver,
                  size: 12,
                ),
                const SizedBox(width: 4),
                Text(
                  '${journey.participants?.length ?? 1}',
                  style: TextStyle(
                    color: colors.silver,
                    fontSize: 11,
                  ),
                ),
                
                const SizedBox(width: 12),
                
                Icon(
                  Icons.speed,
                  color: colors.silver,
                  size: 12,
                ),
                const SizedBox(width: 4),
                Text(
                  '${journey.lagThresholdMeters}m',
                  style: TextStyle(
                    color: colors.silver,
                    fontSize: 11,
                  ),
                ),
                
                const Spacer(),
                
                Text(
                  _formatJourneyDate(journey.createdAt),
                  style: TextStyle(
                    color: colors.silver,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatJourneyDate(DateTime? date) {
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

  void _navigateToJourneyDetails(Journey journey) {
    JourneyNavigation.open(context, journey);
  }

  Widget _buildDivider(TulinkColors colors) {
    return Divider(
      color: colors.brushedSteel.withOpacity(0.3),
      height: 1,
      indent: 16,
      endIndent: 16,
    );
  }

  String _getInitials(String name) {
    List<String> nameParts = name.split(' ');
    if (nameParts.length >= 2) {
      return '${nameParts[0][0]}${nameParts[1][0]}'.toUpperCase();
    } else if (nameParts.isNotEmpty) {
      return nameParts[0].substring(0, 2).toUpperCase();
    }
    return 'U';
  }


  void _navigateToNotifications() {
    // Navigate to notifications screen
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Notifications feature coming soon')),
    );
  }

  void _navigateToPrivacy() {
    // Navigate to privacy screen
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Privacy settings coming soon')),
    );
  }

  void _navigateToLinkedAccounts() {
    // Navigate to linked accounts screen
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Linked accounts feature coming soon')),
    );
  }

  void _navigateToSupport() {
    // Navigate to support screen
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Help & Support coming soon')),
    );
  }

  void _showSignOutDialog() {
    final colors = Theme.of(context).tulinkColors;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.cardDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          'Sign Out',
          style: TextStyle(
            color: colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'Are you sure you want to sign out?',
          style: TextStyle(
            color: colors.silver,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: colors.silver,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.read<AuthProvider>().signOut();
            },
            child: Text(
              'Sign Out',
              style: TextStyle(
                color: colors.electricRed,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}