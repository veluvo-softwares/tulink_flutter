import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'tulink_colors.dart';

/// Tu-Link app theme following motorsports-inspired dark design
/// Implements exact typography and color specifications
class AppTheme {
  AppTheme._();

  // Tu-Link brand colors (accessible via ThemeExtension)
  static const TulinkColors _colors = TulinkColors.dark;

  // Color scheme for dark theme (Tu-Link is dark mode only)
  static const ColorScheme _tulinkColorScheme = ColorScheme.dark(
    primary: Color(0xFFE8002D), // Electric red for CTAs and highlights
    onPrimary: Color(0xFFFFFFFF), // White text on red buttons
    secondary: Color(0xFF2A2A2A), // Steel grey for secondary elements
    onSecondary: Color(0xFFFFFFFF), // White text on secondary elements
    error: Color(0xFFE8002D), // Use electric red for errors/alerts
    onError: Color(0xFFFFFFFF), // White text on error states
    surface: Color(0xFF0D0D0D), // Deep carbon black background
    onSurface: Color(0xFFFFFFFF), // White text on surface
    surfaceContainerHighest: Color(0xFF1E1E1E), // Card surfaces
    onSurfaceVariant: Color(0xFFC8C8C8), // Secondary text
    outline: Color(0xFF404040), // Borders and dividers
  );

  /// Tu-Link theme configuration (dark mode only)
  /// Returns ThemeData with exact typography and styling specifications
  static ThemeData get tulinkTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: _tulinkColorScheme,
      fontFamily: GoogleFonts.inter().fontFamily,
      scaffoldBackgroundColor: _colors.carbonBlack,
      
      // Theme extensions for custom colors
      extensions: const [
        TulinkColors.dark,
      ],
      
      // AppBar theme - motorsports dashboard style
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: true,
        backgroundColor: Colors.transparent,
        foregroundColor: _colors.white,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: _colors.white,
        ),
      ),

      // Card theme - Brushed Steel Grey with 16px radius
      cardTheme: CardThemeData(
        elevation: 4,
        color: _colors.brushedSteel,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
        clipBehavior: Clip.antiAlias,
      ),

      // Global ElevatedButton theme - 16px radius, red background, bold Inter text
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _colors.electricRed,
          foregroundColor: _colors.white,
          elevation: 6,
          shadowColor: _colors.electricRed.withValues(alpha: 0.3),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w800, // Extra Bold
            color: _colors.white,
          ),
        ),
      ),

      // Secondary button theme - outlined with brushed steel
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _colors.white,
          side: BorderSide(color: _colors.brushedSteel, width: 2),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: _colors.white,
          ),
        ),
      ),

      // Text button theme - for small action links
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: _colors.electricRed,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w600, // Semi-Bold
            color: _colors.electricRed,
          ),
        ),
      ),

      // Global InputDecoration theme - steel grey fill, 16px radius, red focused border
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _colors.brushedSteel,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: _colors.brushedSteel),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: _colors.electricRed, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: _colors.electricRed, width: 2),
        ),
        hintStyle: GoogleFonts.inter(
          color: _colors.silver,
          fontSize: 15,
          fontWeight: FontWeight.w400,
        ),
        labelStyle: GoogleFonts.inter(
          color: _colors.silver,
          fontSize: 15,
          fontWeight: FontWeight.w400,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),

      // Bottom navigation bar theme - dark with red accents
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        type: BottomNavigationBarType.fixed,
        elevation: 8,
        backgroundColor: _colors.cardDark,
        selectedItemColor: _colors.electricRed,
        unselectedItemColor: _colors.silver,
        showUnselectedLabels: true,
        selectedLabelStyle: GoogleFonts.inter(
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
        unselectedLabelStyle: GoogleFonts.inter(
          fontWeight: FontWeight.w400,
          fontSize: 12,
        ),
      ),

      // Custom Typography Specification (Inter Family)
      textTheme: GoogleFonts.interTextTheme().copyWith(
        // Sign-In/Sign-Up Titles: Inter, Extra Bold, Size 32, White
        headlineLarge: GoogleFonts.inter(
          fontSize: 32,
          fontWeight: FontWeight.w800, // Extra Bold
          color: _colors.white,
        ),
        // Card Action Titles: Inter, Extra Bold, Size 20, White
        headlineMedium: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w800, // Extra Bold
          color: _colors.white,
        ),
        // Standard Body Text: Inter, Regular, Size 15, Silver
        bodyLarge: GoogleFonts.inter(
          fontSize: 15,
          fontWeight: FontWeight.w400, // Regular
          color: _colors.silver,
        ),
        bodyMedium: GoogleFonts.inter(
          fontSize: 15,
          fontWeight: FontWeight.w400, // Regular
          color: _colors.silver,
        ),
        // Small Action Links: Inter, Semi-Bold, Size 13, Electric Red
        bodySmall: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w600, // Semi-Bold
          color: _colors.electricRed,
        ),
        // Additional text styles
        labelLarge: GoogleFonts.inter(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: _colors.white,
        ),
        labelMedium: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: _colors.electricRed,
        ),
      ),

      // Floating Action Button theme
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: _colors.electricRed,
        foregroundColor: _colors.white,
        elevation: 8,
      ),

      // Dialog theme
      dialogTheme: DialogThemeData(
        backgroundColor: _colors.cardDark,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),

      // Snackbar theme
      snackBarTheme: SnackBarThemeData(
        backgroundColor: _colors.brushedSteel,
        contentTextStyle: GoogleFonts.inter(
          color: _colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w400,
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Alias for the main Tu-Link theme
  static ThemeData get darkTheme => tulinkTheme;
  
  /// Light theme is not supported - Tu-Link is dark mode only
  static ThemeData get lightTheme => tulinkTheme;
}