import 'package:flutter/material.dart';

/// Custom theme extension for Tu-Link brand colors
/// Provides access to brand colors via Theme.of(context).extension<TulinkColors>()
@immutable
class TulinkColors extends ThemeExtension<TulinkColors> {
  const TulinkColors({
    required this.electricRed,
    required this.brushedSteel,
    required this.carbonBlack,
    required this.white,
    required this.silver,
    required this.cardDark,
    required this.tulinkBlue,
  });

  /// Electric Red (#E8002D) - Primary accent color for CTAs and highlights
  final Color electricRed;
  
  /// Brushed Steel Grey (#2A2A2A) - Secondary color for containers
  final Color brushedSteel;
  
  /// Deep Carbon Black (#0D0D0D) - Primary background color
  final Color carbonBlack;
  
  /// White (#FFFFFF) - Primary text color
  final Color white;
  
  /// Silver (#C8C8C8) - Secondary text color
  final Color silver;
  
  /// Card Dark (#1E1E1E) - Card background color
  final Color cardDark;
  
  /// Tu-Link Blue (#0066FF) - Racing blue accent
  final Color tulinkBlue;

  @override
  TulinkColors copyWith({
    Color? electricRed,
    Color? brushedSteel,
    Color? carbonBlack,
    Color? white,
    Color? silver,
    Color? cardDark,
    Color? tulinkBlue,
  }) {
    return TulinkColors(
      electricRed: electricRed ?? this.electricRed,
      brushedSteel: brushedSteel ?? this.brushedSteel,
      carbonBlack: carbonBlack ?? this.carbonBlack,
      white: white ?? this.white,
      silver: silver ?? this.silver,
      cardDark: cardDark ?? this.cardDark,
      tulinkBlue: tulinkBlue ?? this.tulinkBlue,
    );
  }

  @override
  TulinkColors lerp(TulinkColors? other, double t) {
    if (other is! TulinkColors) {
      return this;
    }
    return TulinkColors(
      electricRed: Color.lerp(electricRed, other.electricRed, t)!,
      brushedSteel: Color.lerp(brushedSteel, other.brushedSteel, t)!,
      carbonBlack: Color.lerp(carbonBlack, other.carbonBlack, t)!,
      white: Color.lerp(white, other.white, t)!,
      silver: Color.lerp(silver, other.silver, t)!,
      cardDark: Color.lerp(cardDark, other.cardDark, t)!,
      tulinkBlue: Color.lerp(tulinkBlue, other.tulinkBlue, t)!,
    );
  }

  /// Default Tu-Link colors
  static const TulinkColors light = TulinkColors(
    electricRed: Color(0xFFE8002D),
    brushedSteel: Color(0xFF2A2A2A),
    carbonBlack: Color(0xFF0D0D0D),
    white: Color(0xFFFFFFFF),
    silver: Color(0xFFC8C8C8),
    cardDark: Color(0xFF1E1E1E),
    tulinkBlue: Color(0xFF0066FF),
  );

  /// Dark mode colors (same as light for Tu-Link)
  static const TulinkColors dark = TulinkColors(
    electricRed: Color(0xFFE8002D),
    brushedSteel: Color(0xFF2A2A2A),
    carbonBlack: Color(0xFF0D0D0D),
    white: Color(0xFFFFFFFF),
    silver: Color(0xFFC8C8C8),
    cardDark: Color(0xFF1E1E1E),
    tulinkBlue: Color(0xFF0066FF),
  );
}

/// Extension on ThemeData to easily access Tu-Link colors
extension TulinkColorsExtension on ThemeData {
  TulinkColors get tulinkColors =>
      extension<TulinkColors>() ?? TulinkColors.dark;
}