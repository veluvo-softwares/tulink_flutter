import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/tulink_colors.dart';
import '../../domain/entities/invitation.dart';
import '../providers/invitation_provider.dart';
import '../widgets/journey_info_card.dart';

class InviteParticipantsScreen extends StatefulWidget {
  final String journeyId;

  const InviteParticipantsScreen({
    super.key,
    required this.journeyId,
  });

  static const String routeName = '/invite-participants';

  @override
  State<InviteParticipantsScreen> createState() => _InviteParticipantsScreenState();
}

class _InviteParticipantsScreenState extends State<InviteParticipantsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _inviteMessage = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<InvitationProvider>().initializeForJourney(widget.journeyId);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    context.read<InvitationProvider>().searchUsers(query);
  }

  Future<void> _sendInvitation(User user) async {
    final success = await context.read<InvitationProvider>().sendInvitation(
      journeyId: widget.journeyId,
      inviteeId: user.id,
      message: _inviteMessage.isNotEmpty ? _inviteMessage : null,
    );

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Invitation sent to ${user.displayName}'),
          backgroundColor: Colors.green,
        ),
      );
      _searchController.clear();
      setState(() {
        _inviteMessage = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;

    return Scaffold(
      backgroundColor: colors.carbonBlack,
      appBar: AppBar(
        backgroundColor: colors.carbonBlack,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Invite Participants',
          style: TextStyle(
            color: colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: Consumer<InvitationProvider>(
        builder: (context, invitationProvider, child) {
          return Column(
            children: [
              // Search Section
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SEARCH USERS',
                      style: TextStyle(
                        color: colors.silver,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _searchController,
                      onChanged: _onSearchChanged,
                      style: TextStyle(color: colors.white),
                      decoration: InputDecoration(
                        hintText: 'Enter email or name...',
                        hintStyle: TextStyle(color: colors.silver),
                        filled: true,
                        fillColor: colors.cardDark,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        prefixIcon: Icon(Icons.search, color: colors.silver),
                        suffixIcon: invitationProvider.isSearching
                            ? Padding(
                                padding: const EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: colors.electricRed,
                                  ),
                                ),
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Optional Message
                    Text(
                      'INVITATION MESSAGE (OPTIONAL)',
                      style: TextStyle(
                        color: colors.silver,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      onChanged: (value) {
                        setState(() {
                          _inviteMessage = value;
                        });
                      },
                      style: TextStyle(color: colors.white),
                      decoration: InputDecoration(
                        hintText: 'Add a personal message...',
                        hintStyle: TextStyle(color: colors.silver),
                        filled: true,
                        fillColor: colors.cardDark,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),

              // Search Results
              Expanded(
                child: _buildSearchResults(colors, invitationProvider),
              ),

              // Current Participants Section
              if (invitationProvider.participants.isNotEmpty)
                JourneyInfoCard(
                  margin: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      JourneyInfoCardHeader(
                        title: 'CURRENT PARTICIPANTS',
                        trailing: Text(
                          '${invitationProvider.totalParticipantsCount}',
                          style: TextStyle(
                            color: colors.silver,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          children: invitationProvider.participants
                              .map((participant) => _buildParticipantTile(participant, colors))
                              .toList(),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSearchResults(TulinkColors colors, InvitationProvider provider) {
    if (_searchController.text.isEmpty) {
      return _buildEmptySearchState(colors);
    }

    if (provider.isSearching) {
      return Center(
        child: CircularProgressIndicator(color: colors.electricRed),
      );
    }

    if (provider.searchResults.isEmpty) {
      return _buildNoResultsState(colors);
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: provider.searchResults.length,
      itemBuilder: (context, index) {
        final user = provider.searchResults[index];
        return _buildUserTile(user, colors, provider);
      },
    );
  }

  Widget _buildEmptySearchState(TulinkColors colors) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.person_search,
            size: 64,
            color: colors.silver.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'Search for users to invite',
            style: TextStyle(
              color: colors.silver,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Enter an email or name to find participants',
            style: TextStyle(
              color: colors.silver.withOpacity(0.7),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResultsState(TulinkColors colors) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off,
            size: 64,
            color: colors.silver.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No users found',
            style: TextStyle(
              color: colors.silver,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try a different search term',
            style: TextStyle(
              color: colors.silver.withOpacity(0.7),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserTile(User user, TulinkColors colors, InvitationProvider provider) {
    final isAlreadyInvited = provider.invitations.any(
      (invitation) => invitation.inviteeId == user.id && invitation.isPending,
    );
    
    final isAlreadyParticipant = provider.participants.any(
      (participant) => participant.userId == user.id,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.cardDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colors.brushedSteel.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colors.brushedSteel,
              borderRadius: BorderRadius.circular(8),
            ),
            child: user.avatarUrl != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      user.avatarUrl!,
                      fit: BoxFit.cover,
                    ),
                  )
                : Center(
                    child: Text(
                      user.displayName.isNotEmpty ? user.displayName[0].toUpperCase() : 'U',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
          ),
          
          const SizedBox(width: 12),
          
          // User Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.displayName,
                  style: TextStyle(
                    color: colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  user.email,
                  style: TextStyle(
                    color: colors.silver,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          
          // Action Button
          if (isAlreadyParticipant)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: colors.tulinkBlue.withOpacity(0.2),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: colors.tulinkBlue),
              ),
              child: Text(
                'JOINED',
                style: TextStyle(
                  color: colors.tulinkBlue,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          else if (isAlreadyInvited)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.2),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.orange),
              ),
              child: const Text(
                'PENDING',
                style: TextStyle(
                  color: Colors.orange,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          else
            ElevatedButton(
              onPressed: provider.isSendingInvitation
                  ? null
                  : () => _sendInvitation(user),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.electricRed,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              child: provider.isSendingInvitation
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'INVITE',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
        ],
      ),
    );
  }

  Widget _buildParticipantTile(JourneyParticipant participant, TulinkColors colors) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.carbonBlack,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: colors.brushedSteel.withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: participant.isLeader ? colors.electricRed : colors.brushedSteel,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: Text(
                participant.initials,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          
          const SizedBox(width: 8),
          
          Expanded(
            child: Text(
              participant.displayName,
              style: TextStyle(
                color: colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          
          if (participant.isLeader)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: colors.electricRed.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: colors.electricRed, width: 1),
              ),
              child: Text(
                'LEADER',
                style: TextStyle(
                  color: colors.electricRed,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }
}