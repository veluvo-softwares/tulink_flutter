import 'package:flutter/material.dart';

/// Provider for managing theme state throughout the application
/// Tu-Link is dark mode only, following motorsports design principles
class ThemeProvider extends ChangeNotifier {
  /// Constructor - Tu-Link is dark mode only
  ThemeProvider();

  // Tu-Link is always dark mode
  static const ThemeMode _themeMode = ThemeMode.dark;

  /// Get the current theme mode (always dark for Tu-Link)
  ThemeMode get themeMode => _themeMode;

  /// Tu-Link is always dark mode
  bool get isDarkMode => true;

  /// Tu-Link is dark mode only - these methods are kept for compatibility
  /// but have no effect since the app is always in dark mode

  /// No-op: Tu-Link is dark mode only
  Future<void> setThemeMode(ThemeMode mode) async {
    // Tu-Link is dark mode only - ignore theme changes
    debugPrint('Tu-Link is dark mode only. Theme change ignored.');
  }

  /// No-op: Tu-Link is dark mode only
  Future<void> toggleTheme() async {
    // Tu-Link is dark mode only - no toggling available
    debugPrint('Tu-Link is dark mode only. Theme toggle ignored.');
  }

  /// No-op: Tu-Link is dark mode only
  Future<void> setSystemTheme() async {
    // Tu-Link is dark mode only
    debugPrint('Tu-Link is dark mode only. System theme ignored.');
  }

  /// No-op: Tu-Link is dark mode only
  Future<void> setLightTheme() async {
    // Tu-Link is dark mode only
    debugPrint('Tu-Link is dark mode only. Light theme not supported.');
  }

  /// No-op: Tu-Link is dark mode only (already the default)
  Future<void> setDarkTheme() async {
    // Already dark mode - no action needed
    debugPrint('Tu-Link is already in dark mode.');
  }
}
