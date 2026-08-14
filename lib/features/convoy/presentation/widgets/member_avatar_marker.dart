import 'package:flutter/material.dart';

import '../../domain/entities/member_position.dart';
import '../../../../core/theme/tulink_colors.dart';

/// Custom avatar marker widget for convoy members on the map
/// Displays member avatar with heading rotation, status indication, and styling
class MemberAvatarMarker extends StatelessWidget {
  const MemberAvatarMarker({
    super.key,
    required this.position,
    required this.memberName,
    this.avatarUrl,
    this.size = 40.0,
    this.onTap,
  });

  final MemberPosition position;
  final String memberName;
  final String? avatarUrl;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<TulinkColors>()!;
    final isStale = position.isStale;
    final hasLowBattery = position.hasLowBattery;

    return GestureDetector(
      onTap: onTap,
      child: Transform.rotate(
        angle:
            (position.normalizedHeading * 3.14159) /
            180, // Convert degrees to radians
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: _getBorderColor(colors, isStale, hasLowBattery),
              width: isStale ? 1.0 : 2.0,
            ),
            boxShadow: isStale
                ? null
                : [
                    BoxShadow(
                      color: colors.routeTeal.withValues(alpha: 0.3),
                      blurRadius: 4,
                      spreadRadius: 1,
                    ),
                  ],
          ),
          child: Opacity(
            opacity: isStale ? 0.5 : 1.0,
            child: ClipOval(child: _buildAvatarContent(colors)),
          ),
        ),
      ),
    );
  }

  /// Build avatar content (image or initials)
  Widget _buildAvatarContent(TulinkColors colors) {
    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      return Image.network(
        avatarUrl!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            _buildInitialsAvatar(colors),
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return _buildInitialsAvatar(colors);
        },
      );
    }

    return _buildInitialsAvatar(colors);
  }

  /// Build avatar with user initials
  Widget _buildInitialsAvatar(TulinkColors colors) {
    final initials = _getInitials(memberName);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: colors.deepTeal, shape: BoxShape.circle),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.4, // Scale font size with avatar size
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  /// Get border color based on member status
  Color _getBorderColor(TulinkColors colors, bool isStale, bool hasLowBattery) {
    if (isStale) return colors.muted.withValues(alpha: 0.5);
    if (hasLowBattery) return Colors.orange;
    return colors.routeTeal;
  }

  /// Get user initials from name
  String _getInitials(String name) {
    final words = name.trim().split(' ');
    if (words.isEmpty) return '?';

    if (words.length == 1) {
      return words[0].substring(0, 1).toUpperCase();
    }

    return (words[0].substring(0, 1) + words[1].substring(0, 1)).toUpperCase();
  }
}

/// Status chip widget for member status
class MemberStatusChip extends StatelessWidget {
  const MemberStatusChip({super.key, required this.status, this.size = 12.0});

  final String status;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<TulinkColors>()!;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: size * 0.6,
        vertical: size * 0.3,
      ),
      decoration: BoxDecoration(
        color: _getStatusColor(colors),
        borderRadius: BorderRadius.circular(size * 0.4),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.8,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Color _getStatusColor(TulinkColors colors) {
    switch (status.toUpperCase()) {
      case 'MOVING':
        return Colors.green;
      case 'STOPPED':
        return colors.muted;
      case 'ARRIVED':
        return Colors.blue;
      case 'LAG':
        return Colors.orange;
      case 'OFFLINE':
        return colors.muted;
      default:
        return colors.muted;
    }
  }
}
