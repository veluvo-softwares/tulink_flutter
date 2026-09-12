import 'package:flutter/material.dart';

/// Semantic colors for the warm, map-first Tulink product experience.
@immutable
class TulinkColors extends ThemeExtension<TulinkColors> {
  const TulinkColors({
    required this.deepTeal,
    required this.routeTeal,
    required this.sunsetOrange,
    required this.warmSand,
    required this.ink,
    required this.surface,
    required this.muted,
    required this.divider,
    this.isDark = false,
  });

  final bool isDark;

  final Color deepTeal;

  /// Brand-colored text and icons with sufficient contrast on theme surfaces.
  Color get foregroundAccent => isDark ? routeTeal : deepTeal;
  final Color routeTeal;
  final Color sunsetOrange;
  final Color warmSand;
  final Color ink;
  final Color surface;
  final Color muted;
  final Color divider;

  // Compatibility aliases keep screens outside the new map-first flow
  // readable while they migrate to the semantic palette above. Those screens
  // were designed as dark surfaces, so changing both their background and
  // foreground tokens in one pass can create invisible content.
  Color get electricRed => sunsetOrange;
  Color get brushedSteel =>
      isDark ? const Color(0xFF0B6271) : const Color(0xFF2A2A2A);
  Color get carbonBlack => isDark ? warmSand : const Color(0xFF0D0D0D);
  Color get white => Colors.white;
  Color get silver => const Color(0xFFC8C8C8);
  Color get cardDark => isDark ? surface : const Color(0xFF1E1E1E);
  Color get tulinkBlue => routeTeal;

  static const light = TulinkColors(
    deepTeal: Color(0xFF075261),
    routeTeal: Color(0xFF12848D),
    sunsetOrange: Color(0xFFF35D32),
    warmSand: Color(0xFFF9F4F0),
    ink: Color(0xFF1A1A19),
    surface: Color(0xFFFFFFFF),
    muted: Color(0xFF6F7472),
    divider: Color(0xFFE3DDD7),
  );

  static const dark = TulinkColors(
    isDark: true,
    deepTeal: Color(0xFF075261),
    routeTeal: Color(0xFF69CED1),
    sunsetOrange: Color(0xFFF35D32),
    warmSand: Color(0xFF063C46),
    ink: Color(0xFFF9F4F0),
    surface: Color(0xFF075261),
    muted: Color(0xFFB6D4D3),
    divider: Color(0xFF377B84),
  );

  @override
  TulinkColors copyWith({
    bool? isDark,
    Color? deepTeal,
    Color? routeTeal,
    Color? sunsetOrange,
    Color? warmSand,
    Color? ink,
    Color? surface,
    Color? muted,
    Color? divider,
  }) {
    return TulinkColors(
      isDark: isDark ?? this.isDark,
      deepTeal: deepTeal ?? this.deepTeal,
      routeTeal: routeTeal ?? this.routeTeal,
      sunsetOrange: sunsetOrange ?? this.sunsetOrange,
      warmSand: warmSand ?? this.warmSand,
      ink: ink ?? this.ink,
      surface: surface ?? this.surface,
      muted: muted ?? this.muted,
      divider: divider ?? this.divider,
    );
  }

  @override
  TulinkColors lerp(covariant TulinkColors? other, double t) {
    if (other == null) return this;
    return TulinkColors(
      isDark: t < 0.5 ? isDark : other.isDark,
      deepTeal: Color.lerp(deepTeal, other.deepTeal, t)!,
      routeTeal: Color.lerp(routeTeal, other.routeTeal, t)!,
      sunsetOrange: Color.lerp(sunsetOrange, other.sunsetOrange, t)!,
      warmSand: Color.lerp(warmSand, other.warmSand, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
    );
  }
}

extension TulinkColorsExtension on ThemeData {
  TulinkColors get tulinkColors =>
      extension<TulinkColors>() ?? TulinkColors.light;
}
