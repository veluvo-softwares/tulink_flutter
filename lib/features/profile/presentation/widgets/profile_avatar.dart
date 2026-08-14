import 'package:flutter/material.dart';
import 'package:tulink_flutter/core/theme/tulink_colors.dart';

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    required this.initials,
    super.key,
    this.isOnline = false,
    this.size = 120,
    this.imageUrl,
  });

  final String initials;
  final bool isOnline;
  final double size;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: colors.surface, width: 4),
              boxShadow: [
                BoxShadow(
                  color: colors.deepTeal.withValues(alpha: 0.12),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Container(
              margin: const EdgeInsets.all(3),
              decoration: const BoxDecoration(shape: BoxShape.circle),
              child: ClipOval(
                child: imageUrl != null
                    ? Image.network(
                        imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return _buildInitialsAvatar(colors);
                        },
                      )
                    : _buildInitialsAvatar(colors),
              ),
            ),
          ),

          if (isOnline)
            Positioned(
              bottom: size * 0.1,
              right: size * 0.1,
              child: Container(
                width: size * 0.25,
                height: size * 0.25,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.routeTeal,
                  border: Border.all(color: colors.surface, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: colors.routeTeal.withValues(alpha: 0.25),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInitialsAvatar(TulinkColors colors) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(shape: BoxShape.circle, color: colors.deepTeal),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.35,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
          ),
        ),
      ),
    );
  }
}
