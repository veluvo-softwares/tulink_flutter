import 'package:flutter/material.dart';

import 'tulink_colors.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get tulinkTheme => lightTheme;

  static ThemeData get lightTheme => _build(TulinkColors.light);

  static ThemeData get darkTheme => _build(TulinkColors.dark);

  static ThemeData _build(TulinkColors colors) {
    final isDark = colors.isDark;
    final scheme = isDark
        ? ColorScheme.dark(
            primary: colors.sunsetOrange,
            onPrimary: const Color(0xFF1A1A19),
            secondary: colors.routeTeal,
            onSecondary: const Color(0xFF063C46),
            tertiary: const Color(0xFFFFAB91),
            onTertiary: const Color(0xFF1A1A19),
            error: const Color(0xFFFFB4AB),
            onError: const Color(0xFF690005),
            surface: colors.surface,
            onSurface: colors.ink,
            surfaceContainerHighest: const Color(0xFF0B6271),
            onSurfaceVariant: colors.muted,
            outline: colors.divider,
          )
        : const ColorScheme.light(
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
      brightness: scheme.brightness,
      colorScheme: scheme,
      fontFamily: 'Manrope',
      scaffoldBackgroundColor: colors.warmSand,
      extensions: [colors],
    );

    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        displaySmall: TextStyle(
          fontSize: 34,
          height: 1.12,
          fontWeight: FontWeight.w800,
          color: colors.ink,
        ),
        headlineMedium: TextStyle(
          fontSize: 22,
          height: 1.18,
          fontWeight: FontWeight.w800,
          color: colors.ink,
        ),
        headlineSmall: TextStyle(
          fontSize: 22,
          height: 1.25,
          fontWeight: FontWeight.w700,
          color: colors.ink,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          height: 1.25,
          fontWeight: FontWeight.w700,
          color: colors.ink,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          height: 1.35,
          fontWeight: FontWeight.w700,
          color: colors.ink,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          height: 1.5,
          fontWeight: FontWeight.w400,
          color: colors.ink,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          height: 1.45,
          fontWeight: FontWeight.w400,
          color: colors.muted,
        ),
        labelLarge: const TextStyle(
          fontSize: 16,
          height: 1.25,
          fontWeight: FontWeight.w700,
        ),
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: false,
        backgroundColor: colors.warmSand,
        foregroundColor: colors.ink,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: colors.ink,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(48, 56),
          elevation: 0,
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: colors.divider,
          disabledForegroundColor: colors.muted,
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
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: colors.divider,
          disabledForegroundColor: colors.muted,
          minimumSize: const Size(48, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      dividerTheme: DividerThemeData(color: colors.divider),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surface,
        indicatorColor: scheme.primary.withValues(alpha: .18),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colors.surface,
        indicatorColor: scheme.primary.withValues(alpha: .18),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? scheme.onPrimary : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? scheme.primary : null,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style:
            OutlinedButton.styleFrom(
              minimumSize: const Size(48, 52),
              foregroundColor: isDark ? scheme.tertiary : colors.deepTeal,
              backgroundColor: Colors.transparent,
              disabledForegroundColor: colors.muted,
              side: BorderSide(
                color: isDark ? scheme.tertiary : colors.divider,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              textStyle: const TextStyle(
                fontFamily: 'Manrope',
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ).copyWith(
              side: WidgetStateProperty.resolveWith(
                (states) => BorderSide(
                  color: states.contains(WidgetState.disabled)
                      ? colors.divider
                      : isDark
                      ? scheme.tertiary
                      : colors.divider,
                ),
              ),
            ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: isDark ? scheme.tertiary : colors.deepTeal,
          textStyle: const TextStyle(
            fontFamily: 'Manrope',
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        hintStyle: TextStyle(
          color: isDark ? colors.muted : const Color(0xFF7D817F),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: isDark ? scheme.primary : colors.routeTeal,
            width: 2,
          ),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.warmSand,
        modalBackgroundColor: colors.warmSand,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colors.deepTeal,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
