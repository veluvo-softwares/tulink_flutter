import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/tulink_colors.dart';
import '../../domain/entities/invitation.dart';
import '../providers/invitation_provider.dart';
import '../pages/invite_participants_screen.dart';

class ParticipantListWidget extends StatefulWidget {
  final String journeyId;

  const ParticipantListWidget({
    super.key,
    required this.journeyId,
  });

  @override
  State<ParticipantListWidget> createState() => _ParticipantListWidgetState();
}

class _ParticipantListWidgetState extends State<ParticipantListWidget> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<InvitationProvider>().initializeForJourney(widget.journeyId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;

    return Consumer<InvitationProvider>(
      builder: (context, invitationProvider, child) {
        final participants = invitationProvider.participants;
        final pendingInvitations = invitationProvider.pendingInvitations;

        return participants.isEmpty && pendingInvitations.isEmpty
            ? _buildEmptyState(colors)
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Active Participants
                  ...participants.map(
                    (participant) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildParticipantCard(participant, colors, invitationProvider),
                    ),
                  ),
                  
                  // Pending Invitations
                  ...pendingInvitations.map(
                    (invitation) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildPendingInvitationCard(invitation, colors, invitationProvider),
                    ),
                  ),
                  
                  // Spacing before invite button
                  if (participants.isNotEmpty || pendingInvitations.isNotEmpty)
                    const SizedBox(height: 12),
                  
                  // Invite button
                  _buildInviteButton(colors),
                ],
              );
      },
    );
  }

  Widget _buildEmptyState(TulinkColors colors) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.group_add,
            size: 48,
            color: colors.silver.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No participants yet',
            style: TextStyle(
              color: colors.silver,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Invite drivers to join your convoy',
            style: TextStyle(
              color: colors.silver.withOpacity(0.7),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(context).pushNamed(
                InviteParticipantsScreen.routeName,
                arguments: widget.journeyId,
              );
            },
            icon: const Icon(Icons.add),
            label: const Text('INVITE DRIVERS'),
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.electricRed,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParticipantCard(JourneyParticipant participant, TulinkColors colors, InvitationProvider provider) {
    final isLeader = participant.isLeader;
    final name = participant.displayName;
    final vehicleNumber = participant.vehicleNumber;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.carbonBlack,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colors.brushedSteel.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isLeader ? colors.electricRed : colors.brushedSteel,
              borderRadius: BorderRadius.circular(8),
            ),
            child: participant.avatarUrl != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      participant.avatarUrl!,
                      fit: BoxFit.cover,
                    ),
                  )
                : Center(
                    child: Text(
                      participant.initials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
          ),

          const SizedBox(width: 12),

          // Name
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                color: colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),

          // Role and Vehicle info
          Row(
            children: [
              Text(
                isLeader ? 'LEAD' : 'FOLLOW',
                style: TextStyle(
                  color: colors.silver,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                ' • ',
                style: TextStyle(
                  color: colors.silver,
                  fontSize: 12,
                ),
              ),
              Text(
                'VEHICLE #$vehicleNumber',
                style: TextStyle(
                  color: colors.silver,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),

          const SizedBox(width: 8),

          // Host indicator for leader
          if (isLeader)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: colors.electricRed.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: colors.electricRed,
                  width: 1,
                ),
              ),
              child: Text(
                'LEADER',
                style: TextStyle(
                  color: colors.electricRed,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPendingInvitationCard(Invitation invitation, TulinkColors colors, InvitationProvider provider) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.cardDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.orange.withOpacity(0.5),
        ),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: colors.brushedSteel.withOpacity(0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: invitation.inviteeAvatarUrl != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      invitation.inviteeAvatarUrl!,
                      fit: BoxFit.cover,
                    ),
                  )
                : Center(
                    child: Text(
                      invitation.inviteeName?.isNotEmpty == true
                          ? invitation.inviteeName![0].toUpperCase()
                          : invitation.inviteeEmail[0].toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
          ),

          const SizedBox(width: 12),

          // Name/Email
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  invitation.inviteeName ?? invitation.inviteeEmail,
                  style: TextStyle(
                    color: colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (invitation.inviteeName != null)
                  Text(
                    invitation.inviteeEmail,
                    style: TextStyle(
                      color: colors.silver,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),

          // Pending status
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: Colors.orange,
                width: 1,
              ),
            ),
            child: Text(
              'PENDING',
              style: TextStyle(
                color: Colors.orange,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Cancel button
          IconButton(
            onPressed: () async {
              final success = await provider.cancelInvitation(invitation.id);
              if (success && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Invitation cancelled'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            icon: Icon(
              Icons.close,
              color: colors.silver,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInviteButton(TulinkColors colors) {
    return InkWell(
      onTap: () {
        Navigator.of(context).pushNamed(
          InviteParticipantsScreen.routeName,
          arguments: widget.journeyId,
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.cardDark,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: colors.brushedSteel.withOpacity(0.5),
            style: BorderStyle.solid,
          ),
        ),
        child: Row(
          children: [
            // Plus icon
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: colors.brushedSteel.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.add,
                color: colors.silver,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Invite another driver',
                style: TextStyle(
                  color: colors.silver,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}