import 'dart:async';

import 'package:flutter/material.dart';

/// Toast types for different message categories
enum CarToastType {
  /// Success toast (green)
  success,
  /// Warning/info toast (orange)
  warning,
  /// Error toast (red)
  error,
}

/// A custom toast widget that animates like a car moving from left to right
class CarToast extends StatefulWidget {
  /// Create a car toast with the specified message and type
  const CarToast({
    super.key,
    required this.message,
    this.type = CarToastType.success,
    this.duration = const Duration(seconds: 2),
    this.onDismiss,
  });

  /// The message to display
  final String message;
  /// The type of toast (success, warning, error)
  final CarToastType type;
  /// Duration to display the toast
  final Duration duration;
  /// Callback when toast is dismissed
  final VoidCallback? onDismiss;

  @override
  State<CarToast> createState() => _CarToastState();
}

class _CarToastState extends State<CarToast>
    with TickerProviderStateMixin {
  late AnimationController _slideController;
  late AnimationController _fadeController;
  late Animation<Offset> _slideInAnimation;
  late Animation<Offset> _slideOutAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _startToastSequence();
  }

  void _initializeAnimations() {
    // Animation controller for sliding movement
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    // Animation controller for fade effects
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    // Slide in from left (car entering screen)
    _slideInAnimation = Tween<Offset>(
      begin: const Offset(-1.2, 0), // Start off-screen left
      end: Offset.zero, // Stop at normal position
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: const Interval(0.0, 0.4, curve: Curves.easeOutCubic),
    ));

    // Slide out to right (car exiting screen)
    _slideOutAnimation = Tween<Offset>(
      begin: Offset.zero, // Start at normal position
      end: const Offset(1.2, 0), // Exit off-screen right
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: const Interval(0.6, 1.0, curve: Curves.easeInCubic),
    ));

    // Fade animation for smooth appearance/disappearance
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(_fadeController);
  }

  Future<void> _startToastSequence() async {
    // Start fade in
    unawaited(_fadeController.forward());
    
    // Start slide in animation (car enters from left)
    await _slideController.animateTo(0.4);
    
    // Pause for reading time (car halts at top)
    await Future<void>.delayed(widget.duration);
    
    // Start slide out animation (car exits to right)
    await _slideController.forward();
    
    // Fade out
    await _fadeController.reverse();
    
    // Notify parent that toast is complete
    widget.onDismiss?.call();
  }

  @override
  void dispose() {
    _slideController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Color _getToastColor() {
    switch (widget.type) {
      case CarToastType.success:
        return const Color(0xFF10B981); // Green
      case CarToastType.warning:
        return const Color(0xFFF59E0B); // Orange
      case CarToastType.error:
        return const Color(0xFFEF4444); // Red
    }
  }

  Color _getTextColor() {
    // High contrast white text for dark theme with colored accents
    return Colors.white;
  }

  IconData _getToastIcon() {
    switch (widget.type) {
      case CarToastType.success:
        return Icons.check_circle;
      case CarToastType.warning:
        return Icons.warning;
      case CarToastType.error:
        return Icons.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_slideController, _fadeController]),
      builder: (context, child) {
        // Determine which slide animation to use
        Offset slideOffset;
        if (_slideController.value <= 0.4) {
          // Use slide in animation
          slideOffset = _slideInAnimation.value;
        } else {
          // Use slide out animation
          slideOffset = _slideOutAnimation.value;
        }

        return FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: AlwaysStoppedAnimation(slideOffset),
            child: Container(
              margin: const EdgeInsets.only(
                left: 16,
                right: 16,
                top: 8,
              ),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: _getToastColor(),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _getToastIcon(),
                        color: _getTextColor(),
                        size: 24,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          widget.message,
                          style: TextStyle(
                            color: _getTextColor(),
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}