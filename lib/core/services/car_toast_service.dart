import 'package:flutter/material.dart';

import 'package:tulink_flutter/core/widgets/car_toast.dart';

/// A service for displaying animated car-like toast messages
class CarToastService {
  /// Get the singleton instance
  factory CarToastService() => _instance;

  CarToastService._internal();

  static final CarToastService _instance = CarToastService._internal();

  OverlayEntry? _currentToastEntry;
  bool _isToastVisible = false;

  /// Show a success toast (green)
  static void showSuccess(String message, {BuildContext? context}) {
    _instance._showToast(
      message: message,
      type: CarToastType.success,
      context: context,
    );
  }

  /// Show a warning/info toast (orange)
  static void showWarning(String message, {BuildContext? context}) {
    _instance._showToast(
      message: message,
      type: CarToastType.warning,
      context: context,
    );
  }

  /// Show an error toast (red)
  static void showError(String message, {BuildContext? context}) {
    _instance._showToast(
      message: message,
      type: CarToastType.error,
      context: context,
    );
  }

  /// Show an info toast (silver — neutral)
  static void showInfo(String message, {BuildContext? context}) {
    _instance._showToast(
      message: message,
      type: CarToastType.info,
      context: context,
    );
  }

  /// Generic method to show any type of toast
  void _showToast({
    required String message,
    required CarToastType type,
    Duration duration = const Duration(seconds: 2),
    BuildContext? context,
  }) {
    // Prevent multiple toasts from stacking
    if (_isToastVisible) {
      _dismissCurrentToast();
    }

    // Get the overlay from the current context or navigator
    OverlayState? overlay;
    
    if (context != null) {
      overlay = Overlay.of(context);
    } else {
      // Try to get overlay from navigator key if available
      final navigatorContext = _getNavigatorContext();
      if (navigatorContext != null) {
        overlay = Overlay.of(navigatorContext);
      }
    }

    if (overlay == null) {
      debugPrint('CarToastService: No overlay available to show toast');
      return;
    }

    _isToastVisible = true;

    _currentToastEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 16,
        left: 0,
        right: 0,
        child: CarToast(
          message: message,
          type: type,
          duration: duration,
          onDismiss: _dismissCurrentToast,
        ),
      ),
    );

    overlay.insert(_currentToastEntry!);
  }

  /// Dismiss the current toast if any
  void _dismissCurrentToast() {
    if (_currentToastEntry != null && _isToastVisible) {
      _currentToastEntry!.remove();
      _currentToastEntry = null;
      _isToastVisible = false;
    }
  }

  /// Try to get the navigator context for overlay access
  BuildContext? _getNavigatorContext() {
    try {
      // This will work if you have a global navigator key set up
      // You might need to adjust this based on your app structure
      return WidgetsBinding.instance.focusManager.primaryFocus?.context;
    } catch (e) {
      debugPrint('CarToastService: Could not get navigator context: $e');
      return null;
    }
  }

  /// Clean up resources
  static void dispose() {
    _instance._dismissCurrentToast();
  }
}

/// Extension for easy access to toast methods from BuildContext
extension CarToastExtension on BuildContext {
  /// Show a success toast
  void showSuccessToast(String message) {
    CarToastService.showSuccess(message, context: this);
  }

  /// Show a warning toast
  void showWarningToast(String message) {
    CarToastService.showWarning(message, context: this);
  }

  /// Show an error toast
  void showErrorToast(String message) {
    CarToastService.showError(message, context: this);
  }

  /// Show an info toast
  void showInfoToast(String message) {
    CarToastService.showInfo(message, context: this);
  }
}
