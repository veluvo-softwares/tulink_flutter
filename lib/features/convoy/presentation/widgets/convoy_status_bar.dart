import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../domain/entities/convoy_snapshot.dart';
import '../../../../core/theme/tulink_colors.dart';

/// Top status bar widget showing convoy progress and member count
/// Displays journey status, member count, and connection state
class ConvoyStatusBar extends StatefulWidget {
  const ConvoyStatusBar({
    super.key,
    required this.snapshot,
    required this.connectionState,
    this.onTap,
    this.onBack,
  });

  final ConvoySnapshot? snapshot;
  final ConvoyConnectionState connectionState;
  final VoidCallback? onTap;
  final VoidCallback? onBack;

  @override
  State<ConvoyStatusBar> createState() => _ConvoyStatusBarState();
}

class _ConvoyStatusBarState extends State<ConvoyStatusBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    
    // Setup pulsing animation for status indicator
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    
    _pulseAnimation = Tween<double>(
      begin: 0.5,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
    
    _pulseController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<TulinkColors>()!;
    
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        margin: const EdgeInsets.only(top: 50, left: 16, right: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: colors.cardDark.withOpacity(0.95),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.brushedSteel.withOpacity(0.3)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            if (widget.onBack != null) ...[
              GestureDetector(
                onTap: widget.onBack,
                child: Container(
                  width: 34,
                  height: 34,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: colors.brushedSteel.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.arrow_back, color: colors.white, size: 18),
                ),
              ),
            ],
            _buildStatusIndicator(colors),
            const SizedBox(width: 10),
            Expanded(
              child: _buildStatusInfo(colors),
            ),
            _buildConnectionIndicator(colors),
          ],
        ),
      ),
    );
  }

  /// Build the pulsing status dot
  Widget _buildStatusIndicator(TulinkColors colors) {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: _getStatusColor(colors).withOpacity(_pulseAnimation.value),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: _getStatusColor(colors).withOpacity(0.3),
                blurRadius: 4,
                spreadRadius: 1,
              ),
            ],
          ),
        );
      },
    );
  }

  /// Build status text and member count
  Widget _buildStatusInfo(TulinkColors colors) {
    final snapshot = widget.snapshot;
    String statusText = 'CONNECTING...';
    String memberText = '';

    if (snapshot != null) {
      statusText = _getStatusText(snapshot);
      memberText = _getMemberCountText(snapshot);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          statusText,
          style: GoogleFonts.rajdhani(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: colors.white,
            letterSpacing: 0.5,
          ),
        ),
        if (memberText.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            memberText,
            style: GoogleFonts.rajdhani(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: colors.silver,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ],
    );
  }

  /// Build connection state indicator
  Widget _buildConnectionIndicator(TulinkColors colors) {
    IconData icon;
    Color iconColor;
    
    switch (widget.connectionState) {
      case ConvoyConnectionState.connected:
        icon = Icons.signal_wifi_4_bar;
        iconColor = Colors.green;
        break;
      case ConvoyConnectionState.connecting:
      case ConvoyConnectionState.reconnecting:
        icon = Icons.signal_wifi_0_bar;
        iconColor = Colors.orange;
        break;
      case ConvoyConnectionState.error:
        icon = Icons.signal_wifi_off;
        iconColor = Colors.red;
        break;
      case ConvoyConnectionState.disconnected:
      default:
        icon = Icons.signal_wifi_0_bar;
        iconColor = colors.silver;
        break;
    }
    
    return Icon(
      icon,
      size: 18,
      color: iconColor,
    );
  }

  /// Get status indicator color based on convoy state
  Color _getStatusColor(TulinkColors colors) {
    final snapshot = widget.snapshot;
    
    if (snapshot == null) return colors.silver;
    
    if (snapshot.laggingMembers.isNotEmpty) return Colors.orange;
    if (snapshot.allMembersArrived) return Colors.blue;
    if (snapshot.movingMemberCount > 0) return colors.electricRed;
    
    return Colors.green;
  }

  /// Get status text based on convoy state
  String _getStatusText(ConvoySnapshot snapshot) {
    if (snapshot.allMembersArrived) return 'ALL ARRIVED';
    if (snapshot.laggingMembers.isNotEmpty) return 'MEMBERS LAGGING';
    if (snapshot.movingMemberCount > 0) return 'IN PROGRESS';
    
    // For solo journeys, show journey status instead of waiting
    if (snapshot.totalMembers <= 1) return 'SOLO JOURNEY';
    
    if (!snapshot.hasActiveMembers) return 'WAITING';
    
    return 'CONVOY READY';
  }

  /// Get member count text
  String _getMemberCountText(ConvoySnapshot snapshot) {
    final total = snapshot.totalMembers;
    final active = snapshot.activeMemberCount;
    final moving = snapshot.movingMemberCount;
    
    if (total == 0) return 'NO MEMBERS';
    if (total == 1) return 'SOLO MODE';
    
    String baseText = '$total MEMBERS';
    
    if (active < total) {
      baseText += ' • $active ACTIVE';
    }
    
    if (moving > 0) {
      baseText += ' • $moving MOVING';
    }
    
    return baseText;
  }
}