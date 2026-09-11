import 'package:flutter/material.dart';

/// Manages local appearance independently from account preferences.
class ThemeProvider extends ChangeNotifier {
  /// Optional storage callbacks keep the preference testable without Hive.
  ThemeProvider({
    Future<Object?> Function()? loadPreference,
    Future<void> Function(String)? savePreference,
  }) : _loadPreference = loadPreference,
       _savePreference = savePreference;

  final Future<Object?> Function()? _loadPreference;
  final Future<void> Function(String)? _savePreference;
  ThemeMode _themeMode = ThemeMode.light;
  Future<void> _pendingSave = Future<void>.value();
  int _revision = 0;

  /// The explicit mode; Flutter resolves system mode using platform brightness.
  ThemeMode get themeMode => _themeMode;

  /// Whether dark mode was explicitly selected.
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  /// Restores only recognized values, preserving light for new installations.
  Future<void> initializePreferences() async {
    final revision = _revision;
    try {
      final stored = await _loadPreference?.call();
      if (revision != _revision) return;
      final restored = switch (stored) {
        'dark' => ThemeMode.dark,
        'system' => ThemeMode.system,
        _ => ThemeMode.light,
      };
      if (restored == _themeMode) return;
      _themeMode = restored;
      notifyListeners();
    } on Object catch (_) {
      // Local storage failure must not block startup.
    }
  }

  /// Applies immediately and serializes saves so the latest selection wins.
  Future<void> setThemeMode(ThemeMode mode) {
    if (mode == _themeMode) return _pendingSave;
    _revision++;
    _themeMode = mode;
    notifyListeners();
    _pendingSave = _pendingSave.then((_) async {
      try {
        await _savePreference?.call(mode.name);
      } on Object catch (_) {
        // Continue using the in-memory preference if local storage is unavailable.
      }
    });
    return _pendingSave;
  }

  /// Toggles between explicit light and dark appearances.
  Future<void> toggleTheme() =>
      setThemeMode(isDarkMode ? ThemeMode.light : ThemeMode.dark);

  /// Follows the device appearance.
  Future<void> setSystemTheme() => setThemeMode(ThemeMode.system);

  /// Selects the existing light appearance.
  Future<void> setLightTheme() => setThemeMode(ThemeMode.light);

  /// Selects teal dark mode.
  Future<void> setDarkTheme() => setThemeMode(ThemeMode.dark);
}
