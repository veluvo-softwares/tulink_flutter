import 'package:flutter/material.dart';
import 'package:tulink_flutter/core/theme/tulink_colors.dart';
import 'package:tulink_flutter/core/utils/user_pin_utils.dart';

class UserMapPin extends StatelessWidget {
  final String displayName;
  final String? imageUrl;
  final bool isMe;
  final int userIndex; // Position of user in journey (0, 1, 2, etc.)

  const UserMapPin({
    super.key,
    required this.displayName,
    this.imageUrl,
    this.isMe = false,
    this.userIndex = 0,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;
    final userColor = isMe ? colors.electricRed : UserPinUtils.getUserColor(userIndex);
    final initials = UserPinUtils.extractInitials(displayName);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Name Tag with user initials
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: colors.cardDark.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: userColor,
              width: 2,
            ),
          ),
          child: Text(
            initials,
            style: TextStyle(
              color: colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(height: 4),
        // Avatar Circle with color-coded outline
        Stack(
          alignment: Alignment.center,
          children: [
            // Outer Ring (Color-coded border)
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: userColor,
                boxShadow: [
                  BoxShadow(
                    color: userColor.withValues(alpha: 0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            // Inner Circle (Avatar or Initials)
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.cardDark,
                image: imageUrl != null
                    ? DecorationImage(
                        image: NetworkImage(imageUrl!),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: imageUrl == null
                  ? Center(
                      child: Text(
                        initials,
                        style: TextStyle(
                          color: userColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    )
                  : null,
            ),
          ],
        ),
        // Pin Pointer with matching color
        CustomPaint(
          size: const Size(14, 10),
          painter: _TrianglePainter(color: userColor),
        ),
      ],
    );
  }
}

class _TrianglePainter extends CustomPainter {
  final Color color;

  _TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
