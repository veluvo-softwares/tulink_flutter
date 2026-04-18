import 'package:flutter/material.dart';
import '../theme/tulink_colors.dart';
import '../../features/journeys/domain/entities/journey.dart';

/// A reusable status indicator widget that displays journey status
/// with consistent styling across the app
class StatusIndicator extends StatelessWidget {
  final JourneyStatus status;
  final double fontSize;
  final EdgeInsetsGeometry? padding;

  const StatusIndicator({
    super.key,
    required this.status,
    this.fontSize = 10,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;

    return Container(
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _getStatusColor(status, colors).withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: _getStatusColor(status, colors),
          width: 1,
        ),
      ),
      child: Text(
        _getStatusText(status),
        style: TextStyle(
          color: _getStatusColor(status, colors),
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Color _getStatusColor(JourneyStatus status, TulinkColors colors) {
    switch (status) {
      case JourneyStatus.PENDING:
        return colors.electricRed;
      case JourneyStatus.ACTIVE:
        return Colors.green;
      case JourneyStatus.PAUSED:
        return Colors.orange;
      case JourneyStatus.COMPLETED:
        return colors.silver;
      case JourneyStatus.CANCELLED:
        return Colors.red;
    }
  }

  String _getStatusText(JourneyStatus status) {
    switch (status) {
      case JourneyStatus.PENDING:
        return 'PENDING';
      case JourneyStatus.ACTIVE:
        return 'ACTIVE';
      case JourneyStatus.PAUSED:
        return 'PAUSED';
      case JourneyStatus.COMPLETED:
        return 'COMPLETED';
      case JourneyStatus.CANCELLED:
        return 'CANCELLED';
    }
  }
}