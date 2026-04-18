import 'package:flutter/material.dart';
import '../../../../core/theme/tulink_colors.dart';
import '../../../../core/widgets/status_indicator.dart';
import '../../../journeys/domain/entities/journey.dart';
import '../../../journeys/presentation/widgets/journey_info_card.dart';
import '../../../journeys/presentation/widgets/journey_preview_map.dart';

class JourneyDetailsScreen extends StatelessWidget {
  final Journey journey;

  const JourneyDetailsScreen({
    super.key,
    required this.journey,
  });

  static const String routeName = '/journey-details';

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;

    return Scaffold(
      backgroundColor: colors.carbonBlack,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('JOURNEY DETAILS'),
        centerTitle: true,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Created Date
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    'JOURNEY • ',
                    style: TextStyle(
                      color: colors.silver,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    'CREATED ${_getTimeAgo(journey.createdAt)}',
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

            // Destination Card
            JourneyInfoCard(
              child: JourneyInfoCardContent(
                icon: Icon(
                  Icons.location_on,
                  color: colors.electricRed,
                  size: 24,
                ),
                title: 'DESTINATION',
                subtitle: journey.destinationAddress,
              ),
            ),

            const SizedBox(height: 16),

            // Map Section
            Container(
              height: 250,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: colors.cardDark,
                border: Border.all(
                  color: colors.brushedSteel.withOpacity(0.3),
                  width: 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: JourneyPreviewMap(journey: journey),
            ),

            const SizedBox(height: 16),

            // Journey Info Cards Row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: JourneyInfoCardGrid(
                items: [
                  JourneyInfoCardItem(
                    title: 'TYPE',
                    value: 'Convoy',
                    icon: Icons.route,
                  ),
                  JourneyInfoCardItem(
                    title: 'LAG LIMIT',
                    value: '${journey.lagThresholdMeters}m',
                    icon: Icons.speed,
                  ),
                  JourneyInfoCardItem(
                    title: 'PARTICIPANTS',
                    value: '${journey.participants?.length ?? 0}',
                    icon: Icons.group,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Participants Section
            if (journey.participants != null && journey.participants!.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'PARTICIPANTS',
                  style: TextStyle(
                    color: colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              
              const SizedBox(height: 12),
              
              JourneyInfoCard(
                child: Column(
                  children: [
                    for (int i = 0; i < journey.participants!.length; i++) ...[
                      _ParticipantItem(participant: journey.participants![i]),
                      if (i < journey.participants!.length - 1)
                        Divider(color: colors.brushedSteel.withOpacity(0.3), height: 1),
                    ],
                  ],
                ),
              ),
            ],

            const SizedBox(height: 20),

            // Journey Timeline (if completed or active)
            if (journey.status != JourneyStatus.PENDING) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'TIMELINE',
                  style: TextStyle(
                    color: colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              
              const SizedBox(height: 12),
              
              JourneyInfoCard(
                child: Column(
                  children: [
                    _TimelineItem(
                      icon: Icons.create,
                      title: 'Journey Created',
                      subtitle: _formatDateTime(journey.createdAt),
                      color: colors.silver,
                    ),
                    
                    if (journey.status == JourneyStatus.ACTIVE ||
                        journey.status == JourneyStatus.COMPLETED ||
                        journey.status == JourneyStatus.PAUSED) ...[
                      Divider(color: colors.brushedSteel.withOpacity(0.3), height: 1),
                      _TimelineItem(
                        icon: Icons.play_arrow,
                        title: 'Journey Started',
                        subtitle: journey.startedAt != null 
                            ? _formatDateTime(journey.startedAt)
                            : 'Started',
                        color: Colors.green,
                      ),
                    ],
                    
                    if (journey.status == JourneyStatus.COMPLETED) ...[
                      Divider(color: colors.brushedSteel.withOpacity(0.3), height: 1),
                      _TimelineItem(
                        icon: Icons.flag,
                        title: 'Journey Completed',
                        subtitle: journey.completedAt != null 
                            ? _formatDateTime(journey.completedAt)
                            : 'Completed',
                        color: colors.electricRed,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
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

  String _formatDateTime(DateTime? date) {
    if (date == null) return 'Unknown';
    
    return '${date.day}/${date.month}/${date.year} at ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

class _ParticipantItem extends StatelessWidget {
  final JourneyParticipant participant;

  const _ParticipantItem({required this.participant});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _getRoleColor(participant.role, colors).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _getRoleColor(participant.role, colors),
                width: 2,
              ),
            ),
            child: Icon(
              _getRoleIcon(participant.role),
              color: _getRoleColor(participant.role, colors),
              size: 20,
            ),
          ),
          
          const SizedBox(width: 12),
          
          // Participant info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  participant.userId, // This would typically be a name from user service
                  style: TextStyle(
                    color: colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _getRoleText(participant.role),
                  style: TextStyle(
                    color: _getRoleColor(participant.role, colors),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          
          // Status badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: _getParticipantStatusColor(participant.status, colors).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              _getParticipantStatusText(participant.status),
              style: TextStyle(
                color: _getParticipantStatusColor(participant.status, colors),
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  ParticipantRole _parseParticipantRole(String role) {
    switch (role.toUpperCase()) {
      case 'LEADER':
        return ParticipantRole.LEADER;
      case 'FOLLOWER':
        return ParticipantRole.FOLLOWER;
      default:
        return ParticipantRole.FOLLOWER;
    }
  }

  ParticipantStatus _parseParticipantStatus(String status) {
    switch (status.toUpperCase()) {
      case 'INVITED':
        return ParticipantStatus.INVITED;
      case 'ACTIVE':
        return ParticipantStatus.ACTIVE;
      case 'LEFT':
        return ParticipantStatus.LEFT;
      default:
        return ParticipantStatus.INVITED;
    }
  }

  Color _getRoleColor(String role, TulinkColors colors) {
    final roleEnum = _parseParticipantRole(role);
    switch (roleEnum) {
      case ParticipantRole.LEADER:
        return colors.electricRed;
      case ParticipantRole.FOLLOWER:
        return colors.silver;
    }
  }

  IconData _getRoleIcon(String role) {
    final roleEnum = _parseParticipantRole(role);
    switch (roleEnum) {
      case ParticipantRole.LEADER:
        return Icons.star;
      case ParticipantRole.FOLLOWER:
        return Icons.person;
    }
  }

  String _getRoleText(String role) {
    final roleEnum = _parseParticipantRole(role);
    switch (roleEnum) {
      case ParticipantRole.LEADER:
        return 'LEADER';
      case ParticipantRole.FOLLOWER:
        return 'FOLLOWER';
    }
  }

  Color _getParticipantStatusColor(String status, TulinkColors colors) {
    final statusEnum = _parseParticipantStatus(status);
    switch (statusEnum) {
      case ParticipantStatus.INVITED:
        return Colors.orange;
      case ParticipantStatus.ACTIVE:
        return Colors.green;
      case ParticipantStatus.LEFT:
        return Colors.red;
    }
  }

  String _getParticipantStatusText(String status) {
    final statusEnum = _parseParticipantStatus(status);
    switch (statusEnum) {
      case ParticipantStatus.INVITED:
        return 'INVITED';
      case ParticipantStatus.ACTIVE:
        return 'ACTIVE';
      case ParticipantStatus.LEFT:
        return 'LEFT';
    }
  }
}

class _TimelineItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  const _TimelineItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              icon,
              color: color,
              size: 18,
            ),
          ),
          
          const SizedBox(width: 12),
          
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: colors.silver,
                    fontSize: 12,
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