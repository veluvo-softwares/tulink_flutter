import 'package:flutter/material.dart';
import 'dart:async';
import '../../../../core/theme/tulink_colors.dart';

class ConvoyCountdownWidget extends StatefulWidget {
  final VoidCallback onCountdownComplete;
  final VoidCallback onCancel;
  final int countdownSeconds;

  const ConvoyCountdownWidget({
    super.key,
    required this.onCountdownComplete,
    required this.onCancel,
    this.countdownSeconds = 3,
  });

  @override
  State<ConvoyCountdownWidget> createState() => _ConvoyCountdownWidgetState();
}

class _ConvoyCountdownWidgetState extends State<ConvoyCountdownWidget>
    with TickerProviderStateMixin {
  late AnimationController _scaleController;
  late AnimationController _fadeController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  
  Timer? _countdownTimer;
  int _currentCount = 0;
  bool _isCompleted = false;

  @override
  void initState() {
    super.initState();
    _currentCount = widget.countdownSeconds;
    
    // Initialize animations
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _scaleAnimation = Tween<double>(
      begin: 0.5,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _scaleController,
      curve: Curves.elasticOut,
    ));
    
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    ));

    // Start countdown
    _startCountdown();
  }

  void _startCountdown() {
    _fadeController.forward();
    _animateNumber();
    
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_currentCount <= 1) {
        timer.cancel();
        _completeCountdown();
      } else {
        setState(() {
          _currentCount--;
        });
        _animateNumber();
      }
    });
  }

  void _animateNumber() {
    _scaleController.reset();
    _scaleController.forward();
  }

  void _completeCountdown() {
    setState(() {
      _isCompleted = true;
    });
    
    // Show "GO!" briefly before calling completion
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        widget.onCountdownComplete();
      }
    });
  }

  void _cancelCountdown() {
    _countdownTimer?.cancel();
    _fadeController.reverse().then((_) {
      if (mounted) {
        widget.onCancel();
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _scaleController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;
    
    return AnimatedBuilder(
      animation: _fadeAnimation,
      builder: (context, child) {
        return Container(
          color: Colors.black.withOpacity(0.8 * _fadeAnimation.value),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Main countdown display
                AnimatedBuilder(
                  animation: _scaleAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _scaleAnimation.value,
                      child: Container(
                        width: 200,
                        height: 200,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colors.carbonBlack,
                          border: Border.all(
                            color: colors.electricRed,
                            width: 4,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: colors.electricRed.withOpacity(0.3),
                              blurRadius: 20,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: Center(
                          child: _isCompleted
                              ? Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.rocket_launch,
                                      color: colors.electricRed,
                                      size: 48,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'GO!',
                                      style: TextStyle(
                                        color: colors.electricRed,
                                        fontSize: 32,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 2,
                                      ),
                                    ),
                                  ],
                                )
                              : Text(
                                  '$_currentCount',
                                  style: TextStyle(
                                    color: colors.electricRed,
                                    fontSize: 80,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 40),

                // Status text
                Text(
                  _isCompleted 
                      ? 'Starting Convoy...' 
                      : 'Starting convoy in...',
                  style: TextStyle(
                    color: colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),

                const SizedBox(height: 60),

                // Cancel button (only show if not completed)
                if (!_isCompleted)
                  ElevatedButton(
                    onPressed: _cancelCountdown,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.cardDark,
                      foregroundColor: colors.white,
                      side: BorderSide(color: colors.brushedSteel),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 12,
                      ),
                    ),
                    child: const Text(
                      'CANCEL',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),

                // Completion indicator
                if (_isCompleted)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: colors.electricRed.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: colors.electricRed.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            color: colors.electricRed,
                            strokeWidth: 2,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Initializing convoy systems...',
                          style: TextStyle(
                            color: colors.electricRed,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}