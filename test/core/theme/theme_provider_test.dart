import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/core/theme/theme_provider.dart';

void main() {
  test('defaults to light and rejects invalid stored values', () async {
    for (final value in [null, 'unknown', 42]) {
      final provider = ThemeProvider(loadPreference: () async => value);
      await provider.initializePreferences();
      expect(provider.themeMode, ThemeMode.light);
      provider.dispose();
    }
  });
  test('notifies once per selection and restores all modes', () async {
    Object? stored;
    final provider = ThemeProvider(
      savePreference: (value) async {
        stored = value;
      },
    );
    var notifications = 0;
    provider.addListener(() {
      notifications++;
    });
    for (final mode in [ThemeMode.dark, ThemeMode.system, ThemeMode.light]) {
      await provider.setThemeMode(mode);
      await provider.setThemeMode(mode);
      final restored = ThemeProvider(loadPreference: () async => stored);
      await restored.initializePreferences();
      expect(restored.themeMode, mode);
      restored.dispose();
    }
    expect(notifications, 3);
    provider.dispose();
  });
  test('failed storage keeps startup and switching usable', () async {
    final provider = ThemeProvider(
      loadPreference: () async => throw StateError('unavailable'),
      savePreference: (_) async => throw StateError('unavailable'),
    );
    await provider.initializePreferences();
    expect(provider.themeMode, ThemeMode.light);
    await provider.setDarkTheme();
    expect(provider.themeMode, ThemeMode.dark);
    await provider.toggleTheme();
    expect(provider.themeMode, ThemeMode.light);
    await provider.setSystemTheme();
    expect(provider.themeMode, ThemeMode.system);
    provider.dispose();
  });
}
