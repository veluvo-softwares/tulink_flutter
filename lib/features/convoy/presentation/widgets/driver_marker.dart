import 'package:flutter/material.dart';
import '../../domain/entities/member_position.dart';
import '../../../../core/theme/tulink_colors.dart';

/// Driver marker widget for convoy members on the map
/// Shows circular markers with initials and status indicators
class DriverMarker extends StatefulWidget {
  const DriverMarker({
    super.key,
    required this.position,
    required this.memberName,
    required this.userIndex,
    this.size = 48.0,
    this.onTap,
    this.showSpeed = false,
  });

  final MemberPosition position;
  final String memberName;
  final int userIndex; // 0-4 for color selection
  final double size;
  final VoidCallback? onTap;
  final bool showSpeed;

  @override
  State<DriverMarker> createState() => _DriverMarkerState();
}

class _DriverMarkerState extends State<DriverMarker>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Color palette for 5 different users
  static const List<Color> _driverColors = [
    Color(0xFFE53E3E), // Red
    Color(0xFF3182CE), // Blue  
    Color(0xFF38A169), // Green
    Color(0xFFDD6B20), // Orange
    Color(0xFF805AD5), // Purple
  ];

  @override
  void initState() {
    super.initState();
    
    // Setup pulsing animation for moving drivers
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    
    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.3,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    // Start pulsing if driver is moving
    if (widget.position.isMoving) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(DriverMarker oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Update pulsing based on movement status
    if (widget.position.isMoving && !oldWidget.position.isMoving) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.position.isMoving && oldWidget.position.isMoving) {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<TulinkColors>()!;
    final isStale = widget.position.isStale;
    final hasLowBattery = widget.position.hasLowBattery;
    final isMoving = widget.position.isMoving;
    final initials = _getInitials(widget.memberName);
    final driverColor = _getDriverColor();

    return GestureDetector(
      onTap: widget.onTap,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Pulsing ring for moving drivers
          if (isMoving && !isStale)
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Container(
                  width: widget.size * _pulseAnimation.value,
                  height: widget.size * _pulseAnimation.value,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: driverColor.withOpacity(0.3),
                      width: 2,
                    ),
                  ),
                );
              },
            ),

          // Main driver circle
          Transform.rotate(
            angle: (widget.position.normalizedHeading * 3.14159) / 180,
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isStale ? Colors.grey.shade600 : driverColor,
                border: Border.all(
                  color: _getBorderColor(isStale, hasLowBattery, driverColor),
                  width: 3,
                ),
                boxShadow: isStale ? null : [
                  BoxShadow(
                    color: driverColor.withOpacity(0.4),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  initials,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: widget.size * 0.35,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'Rajdhani',
                  ),
                ),
              ),
            ),
          ),

          // Speed indicator
          if (widget.showSpeed && isMoving && !isStale)
            Positioned(
              bottom: -8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: driverColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${widget.position.speedKmh.toStringAsFixed(0)} km/h',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),

          // Status indicator (top-right corner)
          if (hasLowBattery || widget.position.isLagging)
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hasLowBattery ? Colors.orange : Colors.red,
                  border: Border.all(color: Colors.white, width: 1),
                ),
                child: Icon(
                  hasLowBattery ? Icons.battery_alert : Icons.warning,
                  size: 8,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Get user initials from name
  String _getInitials(String name) {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) return '?';
    
    final words = trimmedName.split(' ');
    if (words.length == 1) {
      // Single name: return first letter
      return words[0].substring(0, 1).toUpperCase();
    } else {
      // Multiple names: return first letter of first and last name
      return (words[0].substring(0, 1) + words.last.substring(0, 1)).toUpperCase();
    }
  }

  /// Get driver color based on user index
  Color _getDriverColor() {
    return _driverColors[widget.userIndex % _driverColors.length];
  }

  /// Get border color based on status
  Color _getBorderColor(bool isStale, bool hasLowBattery, Color baseColor) {
    if (isStale) return Colors.grey.shade400;
    if (hasLowBattery) return Colors.orange;
    return Colors.white;
  }
}

/// Destination marker widget with checkered flag
class DestinationMarker extends StatelessWidget {
  const DestinationMarker({
    super.key,
    this.size = 56.0,
    this.onTap,
  });

  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black,
          border: Border.all(
            color: Colors.white,
            width: 3,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 8,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Icon(
          Icons.sports_score, // Checkered flag icon
          color: Colors.white,
          size: size * 0.6,
        ),
      ),
    );
  }
}

/// Extension for convoy-specific calculations
extension ConvoyMemberExtensions on MemberPosition {
  /// Check if member is considered stale (no updates for 30+ seconds)
  bool get isStale {
    final now = DateTime.now().millisecondsSinceEpoch;
    final timeDiff = now - timestamp;
    return timeDiff > 30000; // 30 seconds
  }

  /// Check if member is lagging behind convoy
  bool get isLagging {
    return statusChange == 'LAG';
  }

  /// Check if member has arrived at destination
  bool get hasArrived {
    return statusChange == 'ARRIVED';
  }

  /// Check if member has low battery
  bool get hasLowBattery {
    return batteryLevel != null && batteryLevel! < 20;
  }

  /// Get speed in km/h
  double get speedKmh {
    if (speed == null) return 0.0;
    return speed! * 3.6; // Convert m/s to km/h
  }

  /// Get normalized heading (0-360 degrees)
  double get normalizedHeading {
    if (heading == null) return 0.0;
    var normalized = heading! % 360;
    if (normalized < 0) normalized += 360;
    return normalized;
  }

  /// Get member status for display
  String get memberStatus {
    if (hasArrived) return 'ARRIVED';
    if (isLagging) return 'LAGGING';
    if (isStale) return 'OFFLINE';
    if (isMoving && speedKmh > 0.5) return 'MOVING';
    return 'STOPPED';
  }

  /// Get time since last update
  Duration get age {
    final now = DateTime.now().millisecondsSinceEpoch;
    return Duration(milliseconds: now - timestamp);
  }
}