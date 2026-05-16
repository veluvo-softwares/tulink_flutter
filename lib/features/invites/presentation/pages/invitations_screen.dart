import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tulink_flutter/core/services/car_toast_service.dart';
import 'package:tulink_flutter/core/theme/tulink_colors.dart';
import 'package:tulink_flutter/features/invites/domain/entities/journey_invitation.dart';
import 'package:tulink_flutter/features/invites/presentation/providers/invite_provider.dart';
import 'package:tulink_flutter/features/journeys/presentation/pages/journey_preview_screen.dart';

class InvitationsScreen extends StatefulWidget {
  static const String routeName = '/invitations';

  const InvitationsScreen({super.key});

  @override
  State<InvitationsScreen> createState() => _InvitationsScreenState();
}

class _InvitationsScreenState extends State<InvitationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<InviteProvider>().fetchInvitations();
    });
  }

  Future<void> _onRefresh() async {
    await context.read<InviteProvider>().fetchInvitations();
  }

  Future<void> _acceptInvitation(JourneyInvitation invitation) async {
    final accepted = await context.read<InviteProvider>().acceptInvitation(
          invitation.journeyId,
        );

    if (!mounted) return;

    if (accepted) {
      context.showSuccessToast('You joined "${invitation.journeyName}"!');
      Navigator.of(context).pushNamed(
        JourneyPreviewScreen.routeName,
        arguments: invitation.journeyId,
      );
    } else {
      final error = context.read<InviteProvider>().acceptError;
      context.showErrorToast(error ?? 'Failed to accept invitation');
    }
  }

  String _timeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    if (name.isNotEmpty) return name[0].toUpperCase();
    return '?';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;

    return Scaffold(
      backgroundColor: colors.carbonBlack,
      appBar: AppBar(
        backgroundColor: colors.cardDark,
        foregroundColor: colors.white,
        elevation: 0,
        title: Text(
          'INVITATIONS',
          style: TextStyle(
            color: colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: colors.silver),
            onPressed: _onRefresh,
          ),
        ],
      ),
      body: Consumer<InviteProvider>(
        builder: (context, inviteProvider, _) {
          if (inviteProvider.isLoadingInvitations) {
            return Center(
              child: CircularProgressIndicator(color: colors.electricRed),
            );
          }

          if (inviteProvider.invitationsError != null &&
              inviteProvider.invitations.isEmpty) {
            return _buildErrorState(colors, inviteProvider.invitationsError!);
          }

          if (inviteProvider.invitations.isEmpty) {
            return _buildEmptyState(colors);
          }

          return RefreshIndicator(
            onRefresh: _onRefresh,
            color: colors.electricRed,
            backgroundColor: colors.cardDark,
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: inviteProvider.invitations.length,
              itemBuilder: (context, index) {
                final invitation = inviteProvider.invitations[index];
                final isAccepting = inviteProvider.isAccepting;
                return _InvitationCard(
                  invitation: invitation,
                  isAccepting: isAccepting,
                  timeAgo: _timeAgo(invitation.invitedAt),
                  getInitials: _getInitials,
                  onAccept: () => _acceptInvitation(invitation),
                  colors: colors,
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(TulinkColors colors) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.mail_outline, color: colors.silver, size: 72),
          const SizedBox(height: 20),
          Text(
            'No Invitations',
            style: TextStyle(
              color: colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You have no pending journey invitations',
            style: TextStyle(color: colors.silver, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(TulinkColors colors, String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, color: colors.electricRed, size: 56),
          const SizedBox(height: 16),
          Text(
            error,
            style: TextStyle(color: colors.silver, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _onRefresh,
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.electricRed,
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _InvitationCard extends StatelessWidget {
  final JourneyInvitation invitation;
  final bool isAccepting;
  final String timeAgo;
  final String Function(String) getInitials;
  final VoidCallback onAccept;
  final TulinkColors colors;

  const _InvitationCard({
    required this.invitation,
    required this.isAccepting,
    required this.timeAgo,
    required this.getInitials,
    required this.onAccept,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colors.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.brushedSteel.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with journey name and time
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: colors.electricRed.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: colors.electricRed.withOpacity(0.3),
                    ),
                  ),
                  child: Icon(
                    Icons.route,
                    color: colors.electricRed,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        invitation.journeyName,
                        style: TextStyle(
                          color: colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on,
                            color: colors.silver,
                            size: 12,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              invitation.destination,
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
                    ],
                  ),
                ),
                Text(
                  timeAgo,
                  style: TextStyle(
                    color: colors.silver.withOpacity(0.6),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),

          // Divider
          Divider(height: 1, color: colors.brushedSteel.withOpacity(0.3)),

          // Invited by section and accept button
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Row(
              children: [
                // Avatar
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: colors.tulinkBlue.withOpacity(0.2),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: colors.tulinkBlue.withOpacity(0.4),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      getInitials(invitation.invitedBy.displayName),
                      style: TextStyle(
                        color: colors.tulinkBlue,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'INVITED BY',
                        style: TextStyle(
                          color: colors.silver.withOpacity(0.6),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.8,
                        ),
                      ),
                      Text(
                        invitation.invitedBy.displayName,
                        style: TextStyle(
                          color: colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: isAccepting ? null : onAccept,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.electricRed,
                    disabledBackgroundColor: colors.brushedSteel,
                    foregroundColor: colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                  child: isAccepting
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.white,
                          ),
                        )
                      : const Text(
                          'Accept',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
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
