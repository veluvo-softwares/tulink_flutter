import 'package:flutter/material.dart';

import 'tulink_colors.dart';

class AppTheme {
  AppTheme._();

  static const _colors = TulinkColors.light;

  static ThemeData get tulinkTheme {
    const scheme = ColorScheme.light(
      primary: Color(0xFF075261),
      onPrimary: Color(0xFFFFFFFF),
      secondary: Color(0xFF12848D),
      onSecondary: Color(0xFFFFFFFF),
      tertiary: Color(0xFFF35D32),
      onTertiary: Color(0xFF1A1A19),
      error: Color(0xFFB42318),
      onError: Color(0xFFFFFFFF),
      surface: Color(0xFFFFFFFF),
      onSurface: Color(0xFF1A1A19),
      surfaceContainerHighest: Color(0xFFF9F4F0),
      onSurfaceVariant: Color(0xFF6F7472),
      outline: Color(0xFFE3DDD7),
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      fontFamily: 'Manrope',
      scaffoldBackgroundColor: _colors.warmSand,
      extensions: const [TulinkColors.light],
    );

    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        displaySmall: const TextStyle(
          fontSize: 34,
          height: 1.12,
          fontWeight: FontWeight.w800,
          color: Color(0xFF1A1A19),
        ),
        headlineMedium: const TextStyle(
          fontSize: 22,
          height: 1.18,
          fontWeight: FontWeight.w800,
          color: Color(0xFF1A1A19),
        ),
        headlineSmall: const TextStyle(
          fontSize: 22,
          height: 1.25,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1A1A19),
        ),
        titleLarge: const TextStyle(
          fontSize: 20,
          height: 1.25,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1A1A19),
        ),
        titleMedium: const TextStyle(
          fontSize: 16,
          height: 1.35,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1A1A19),
        ),
        bodyLarge: const TextStyle(
          fontSize: 16,
          height: 1.5,
          fontWeight: FontWeight.w400,
          color: Color(0xFF1A1A19),
        ),
        bodyMedium: const TextStyle(
          fontSize: 14,
          height: 1.45,
          fontWeight: FontWeight.w400,
          color: Color(0xFF6F7472),
        ),
        labelLarge: const TextStyle(
          fontSize: 16,
          height: 1.25,
          fontWeight: FontWeight.w700,
        ),
      ),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: false,
        backgroundColor: Color(0xFFF9F4F0),
        foregroundColor: Color(0xFF1A1A19),
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1A1A19),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(48, 56),
          elevation: 0,
          backgroundColor: _colors.deepTeal,
          foregroundColor: Colors.white,
          disabledBackgroundColor: _colors.divider,
          disabledForegroundColor: _colors.muted,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Manrope',
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 52),
          foregroundColor: _colors.deepTeal,
          side: const BorderSide(color: Color(0xFFE3DDD7)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Manrope',
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: _colors.deepTeal,
          textStyle: const TextStyle(
            fontFamily: 'Manrope',
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _colors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        hintStyle: const TextStyle(color: Color(0xFF7D817F)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE3DDD7)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE3DDD7)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF12848D), width: 2),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: _colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Color(0xFFF9F4F0),
        modalBackgroundColor: Color(0xFFF9F4F0),
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: _colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: _colors.deepTeal,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
