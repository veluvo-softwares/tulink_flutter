import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../domain/entities/convoy_snapshot.dart';
import '../../domain/entities/member_position.dart';
import 'member_avatar_marker.dart';
import '../../../../core/theme/tulink_colors.dart';

/// Bottom sheet widget showing convoy member list with detailed status
/// Displays each member's status, speed, distance, and other convoy info
class ConvoyBottomSheet extends StatelessWidget {
  const ConvoyBottomSheet({
    super.key,
    required this.snapshot,
    this.onMemberTap,
    this.onClose,
  });

  final ConvoySnapshot snapshot;
  final void Function(MemberPosition member)? onMemberTap;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<TulinkColors>()!;
    
    return Container(
      decoration: BoxDecoration(
        color: colors.carbonBlack,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: colors.brushedSteel.withOpacity(0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(colors),
          _buildMemberList(colors),
        ],
      ),
    );
  }

  /// Build bottom sheet header with convoy summary
  Widget _buildHeader(TulinkColors colors) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.brushedSteel.withOpacity(0.3)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.silver.withOpacity(0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          // Header row
          Row(
            children: [
              Expanded(
                child: Text(
                  'CONVOY STATUS',
                  style: GoogleFonts.rajdhani(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              if (onClose != null)
                IconButton(
                  onPressed: onClose,
                  icon: Icon(Icons.close, color: colors.silver),
                  style: IconButton.styleFrom(
                    backgroundColor: colors.brushedSteel.withOpacity(0.3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
            ],
          ),
          
          const SizedBox(height: 12),
          
          // Convoy summary
          _buildConvoySummary(colors),
        ],
      ),
    );
  }

  /// Build convoy summary stats
  Widget _buildConvoySummary(TulinkColors colors) {
    return Row(
      children: [
        _buildSummaryItem(
          colors,
          'TOTAL',
          snapshot.totalMembers.toString(),
        ),
        const SizedBox(width: 24),
        _buildSummaryItem(
          colors,
          'ACTIVE',
          snapshot.activeMemberCount.toString(),
        ),
        const SizedBox(width: 24),
        _buildSummaryItem(
          colors,
          'MOVING',
          snapshot.movingMemberCount.toString(),
        ),
        const SizedBox(width: 24),
        _buildSummaryItem(
          colors,
          'STATUS',
          snapshot.statusSummary,
          isStatus: true,
        ),
      ],
    );
  }

  Widget _buildSummaryItem(
    TulinkColors colors,
    String label,
    String value, {
    bool isStatus = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.rajdhani(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.silver,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.rajdhani(
            fontSize: isStatus ? 12 : 16,
            fontWeight: FontWeight.w700,
            color: isStatus ? _getStatusColor(value, colors) : colors.white,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }

  /// Build scrollable member list
  Widget _buildMemberList(TulinkColors colors) {
    final members = snapshot.membersList;
    
    if (members.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(40),
        child: Center(
          child: Text(
            'No convoy members',
            style: GoogleFonts.rajdhani(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: colors.silver,
            ),
          ),
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 300),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: members.length,
        itemBuilder: (context, index) {
          return _buildMemberItem(colors, members[index]);
        },
      ),
    );
  }

  /// Build individual member item
  Widget _buildMemberItem(TulinkColors colors, MemberPosition member) {
    return InkWell(
      onTap: () => onMemberTap?.call(member),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: colors.brushedSteel.withOpacity(0.1)),
          ),
        ),
        child: Row(
          children: [
            // Avatar
            MemberAvatarMarker(
              position: member,
              memberName: member.userId, // TODO: Get actual member name
              size: 40,
            ),
            
            const SizedBox(width: 16),
            
            // Member info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          member.userId, // TODO: Get actual member name
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: colors.white,
                          ),
                        ),
                      ),
                      MemberStatusChip(status: member.memberStatus),
                    ],
                  ),
                  
                  const SizedBox(height: 8),
                  
                  Row(
                    children: [
                      _buildMemberStat(colors, 'SPEED', '${member.speedKmh.toStringAsFixed(1)} km/h'),
                      const SizedBox(width: 20),
                      _buildMemberStat(colors, 'UPDATED', _getTimeAgo(member.age)),
                      if (member.batteryLevel != null) ...[
                        const SizedBox(width: 20),
                        _buildMemberStat(
                          colors,
                          'BATTERY',
                          '${member.batteryLevel}%',
                          isWarning: member.hasLowBattery,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemberStat(
    TulinkColors colors,
    String label,
    String value, {
    bool isWarning = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.rajdhani(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: colors.silver,
            letterSpacing: 0.5,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.rajdhani(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isWarning ? Colors.orange : colors.white,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }

  Color _getStatusColor(String status, TulinkColors colors) {
    switch (status.toUpperCase()) {
      case 'IN PROGRESS':
        return colors.electricRed;
      case 'ALL ARRIVED':
        return Colors.blue;
      case 'MEMBERS LAGGING':
        return Colors.orange;
      case 'WAITING':
        return colors.silver;
      default:
        return colors.white;
    }
  }

  String _getTimeAgo(Duration age) {
    final seconds = age.inSeconds;
    if (seconds < 60) return '${seconds}s ago';
    
    final minutes = age.inMinutes;
    if (minutes < 60) return '${minutes}m ago';
    
    final hours = age.inHours;
    return '${hours}h ago';
  }
}