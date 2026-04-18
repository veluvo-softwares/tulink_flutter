import 'package:flutter/material.dart';
import '../../../../core/theme/tulink_colors.dart';

class ProfileAvatar extends StatelessWidget {
  final String initials;
  final bool isOnline;
  final double size;
  final String? imageUrl;

  const ProfileAvatar({
    super.key,
    required this.initials,
    this.isOnline = false,
    this.size = 120,
    this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          // Main Avatar Container
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: colors.electricRed,
                width: 3,
              ),
              boxShadow: [
                BoxShadow(
                  color: colors.electricRed.withValues(alpha: 0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Container(
              margin: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
              ),
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
          
          // Online Status Indicator
          if (isOnline)
            Positioned(
              bottom: size * 0.1,
              right: size * 0.1,
              child: Container(
                width: size * 0.25,
                height: size * 0.25,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.green,
                  border: Border.all(
                    color: colors.carbonBlack,
                    width: 3,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.green.withValues(alpha: 0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
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
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            colors.brushedSteel,
            colors.brushedSteel.withValues(alpha: 0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            color: colors.white,
            fontSize: size * 0.35,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
          ),
        ),
      ),
    );
  }
}