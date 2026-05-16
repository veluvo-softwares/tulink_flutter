import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tulink_flutter/core/services/car_toast_service.dart';
import 'package:tulink_flutter/core/theme/tulink_colors.dart';
import 'package:tulink_flutter/features/invites/domain/entities/user_search_result.dart';
import 'package:tulink_flutter/features/invites/presentation/providers/invite_provider.dart';
import 'package:tulink_flutter/features/journeys/domain/entities/journey.dart';
import 'package:tulink_flutter/features/journeys/presentation/providers/journey_provider.dart';

class InviteParticipantsScreen extends StatefulWidget {
  final String journeyId;
  static const String routeName = '/invite-participants';

  const InviteParticipantsScreen({super.key, required this.journeyId});

  @override
  State<InviteParticipantsScreen> createState() =>
      _InviteParticipantsScreenState();
}

class _InviteParticipantsScreenState extends State<InviteParticipantsScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Refresh journey data for up-to-date participants list
      context.read<JourneyProvider>().fetchJourneyById(widget.journeyId);
      // Reset invite session state
      context.read<InviteProvider>().resetInviteSession();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    final trimmed = query.trim();

    if (trimmed.length < 2) {
      context.read<InviteProvider>().clearSearch();
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) {
        context.read<InviteProvider>().searchUsers(trimmed);
      }
    });
  }

  Future<void> _invite(UserSearchResult user) async {
    final success = await context.read<InviteProvider>().sendInvite(
          journeyId: widget.journeyId,
          invitedUserId: user.uid,
        );

    if (!mounted) return;

    if (success) {
      context.showSuccessToast('Invitation sent to ${user.displayName}');
      // Refresh journey to see the new INVITED participant
      context.read<JourneyProvider>().fetchJourneyById(widget.journeyId);
    } else {
      final error = context.read<InviteProvider>().inviteError;
      context.showErrorToast(error ?? 'Failed to send invitation');
    }
  }

  bool _isAlreadyParticipant(String uid, List<Participant>? participants) {
    if (participants == null) return false;
    return participants.any(
      (p) => p.userId == uid && p.status.toUpperCase() != 'LEFT',
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    if (name.isNotEmpty) return name[0].toUpperCase();
    return '?';
  }

  Color _statusColor(String status, TulinkColors colors) {
    switch (status.toUpperCase()) {
      case 'ACTIVE':
        return Colors.green;
      case 'ACCEPTED':
        return colors.tulinkBlue;
      case 'INVITED':
        return Colors.orange;
      case 'LEFT':
        return colors.electricRed;
      default:
        return colors.silver;
    }
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
          'INVITE PARTICIPANTS',
          style: TextStyle(
            color: colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
      ),
      body: Consumer2<InviteProvider, JourneyProvider>(
        builder: (context, inviteProvider, journeyProvider, _) {
          final journey = journeyProvider.currentJourney;
          final participants = journey?.participants;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Search bar
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Container(
                  decoration: BoxDecoration(
                    color: colors.cardDark,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: colors.brushedSteel.withOpacity(0.4),
                    ),
                  ),
                  child: TextField(
                    controller: _searchController,
                    style: TextStyle(color: colors.white, fontSize: 15),
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: 'Search by name or username...',
                      hintStyle:
                          TextStyle(color: colors.silver.withOpacity(0.6)),
                      prefixIcon: Icon(Icons.search, color: colors.silver),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear, color: colors.silver),
                              onPressed: () {
                                _searchController.clear();
                                context.read<InviteProvider>().clearSearch();
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 4),

              // Hint text
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Type at least 2 characters to search',
                  style: TextStyle(
                    color: colors.silver.withOpacity(0.5),
                    fontSize: 11,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Search results or participants list
              Expanded(
                child: _searchController.text.trim().length >= 2
                    ? _buildSearchResults(
                        inviteProvider,
                        participants,
                        colors,
                      )
                    : _buildParticipantsList(participants, colors),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSearchResults(
    InviteProvider inviteProvider,
    List<Participant>? participants,
    TulinkColors colors,
  ) {
    if (inviteProvider.isSearching) {
      return Center(
        child: CircularProgressIndicator(color: colors.electricRed),
      );
    }

    if (inviteProvider.searchError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            inviteProvider.searchError!,
            style: TextStyle(color: colors.silver),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (inviteProvider.searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_search, color: colors.silver, size: 56),
            const SizedBox(height: 12),
            Text(
              'No users found',
              style: TextStyle(color: colors.silver, fontSize: 15),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            'SEARCH RESULTS (${inviteProvider.searchResults.length})',
            style: TextStyle(
              color: colors.silver,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: inviteProvider.searchResults.length,
            itemBuilder: (context, index) {
              final user = inviteProvider.searchResults[index];
              final alreadyParticipant =
                  _isAlreadyParticipant(user.uid, participants);
              final alreadyInvited =
                  inviteProvider.invitedUserIds.contains(user.uid);

              return _UserSearchCard(
                user: user,
                alreadyParticipant: alreadyParticipant,
                alreadyInvited: alreadyInvited,
                isInviting: inviteProvider.isInviting,
                getInitials: _getInitials,
                onInvite: () => _invite(user),
                colors: colors,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildParticipantsList(
    List<Participant>? participants,
    TulinkColors colors,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text(
            'CURRENT PARTICIPANTS (${participants?.length ?? 0})',
            style: TextStyle(
              color: colors.silver,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
        ),
        if (participants == null || participants.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.group_add, color: colors.silver, size: 64),
                  const SizedBox(height: 16),
                  Text(
                    'Search for people to invite',
                    style: TextStyle(color: colors.silver, fontSize: 15),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Use the search bar above to find participants',
                    style: TextStyle(
                      color: colors.silver.withOpacity(0.6),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: participants.length,
              itemBuilder: (context, index) {
                final p = participants[index];
                final isLeader = p.role.toUpperCase() == 'LEADER';
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.cardDark,
                    borderRadius: BorderRadius.circular(10),
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
                          color: isLeader
                              ? colors.electricRed.withOpacity(0.15)
                              : colors.tulinkBlue.withOpacity(0.15),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isLeader
                                ? colors.electricRed.withOpacity(0.4)
                                : colors.tulinkBlue.withOpacity(0.4),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            _getInitials(p.displayName ?? p.userId),
                            style: TextStyle(
                              color: isLeader
                                  ? colors.electricRed
                                  : colors.tulinkBlue,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.displayName ?? p.userId,
                              style: TextStyle(
                                color: colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              p.role.toUpperCase(),
                              style: TextStyle(
                                color: isLeader
                                    ? colors.electricRed
                                    : colors.silver,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Status badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _statusColor(p.status, colors).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: _statusColor(p.status, colors).withOpacity(0.4),
                          ),
                        ),
                        child: Text(
                          p.status.toUpperCase(),
                          style: TextStyle(
                            color: _statusColor(p.status, colors),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _UserSearchCard extends StatelessWidget {
  final UserSearchResult user;
  final bool alreadyParticipant;
  final bool alreadyInvited;
  final bool isInviting;
  final String Function(String) getInitials;
  final VoidCallback onInvite;
  final TulinkColors colors;

  const _UserSearchCard({
    required this.user,
    required this.alreadyParticipant,
    required this.alreadyInvited,
    required this.isInviting,
    required this.getInitials,
    required this.onInvite,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final canInvite = !alreadyParticipant && !alreadyInvited;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.cardDark,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.brushedSteel.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          // Avatar with initials
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.brushedSteel,
              shape: BoxShape.circle,
              border: Border.all(color: colors.silver.withOpacity(0.2)),
            ),
            child: Center(
              child: Text(
                getInitials(user.displayName),
                style: TextStyle(
                  color: colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // User info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.displayName,
                  style: TextStyle(
                    color: colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  user.email,
                  style: TextStyle(
                    color: colors.silver,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (user.phoneNumber != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    user.phoneNumber!,
                    style: TextStyle(
                      color: colors.silver.withOpacity(0.7),
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Invite button
          if (alreadyParticipant)
            _StatusChip(label: 'In Journey', color: colors.tulinkBlue, colors: colors)
          else if (alreadyInvited)
            _StatusChip(label: 'Invited', color: Colors.orange, colors: colors)
          else
            ElevatedButton(
              onPressed: isInviting ? null : onInvite,
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.electricRed,
                disabledBackgroundColor: colors.brushedSteel,
                foregroundColor: colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: isInviting
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.white,
                      ),
                    )
                  : const Text(
                      'Invite',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  final TulinkColors colors;

  const _StatusChip({
    required this.label,
    required this.color,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
