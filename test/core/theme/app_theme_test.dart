import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/core/theme/app_theme.dart';
import 'package:tulink_flutter/core/theme/tulink_colors.dart';

double contrast(Color a, Color b) {
  final first = a.computeLuminance();
  final second = b.computeLuminance();
  return (first > second)
      ? (first + .05) / (second + .05)
      : (second + .05) / (first + .05);
}

void main() {
  test('light palette stays available and dark uses teal surfaces', () {
    expect(AppTheme.lightTheme.brightness, Brightness.light);
    expect(
      AppTheme.lightTheme.scaffoldBackgroundColor,
      const Color(0xFFF9F4F0),
    );
    expect(AppTheme.lightTheme.colorScheme.primary, const Color(0xFF075261));
    expect(AppTheme.darkTheme.brightness, Brightness.dark);
    expect(AppTheme.darkTheme.scaffoldBackgroundColor, const Color(0xFF063C46));
    expect(AppTheme.darkTheme.colorScheme.surface, const Color(0xFF075261));
    expect(TulinkColors.dark.cardDark, TulinkColors.dark.surface);
    expect(TulinkColors.light.cardDark, const Color(0xFF1E1E1E));
  });
  test('dark actions use orange and readable text with outlined tertiary', () {
    final theme = AppTheme.darkTheme;
    final scheme = theme.colorScheme;
    expect(scheme.primary, const Color(0xFFF35D32));
    expect(
      theme.switchTheme.trackColor!.resolve({WidgetState.selected}),
      scheme.primary,
    );
    expect(
      theme.switchTheme.trackColor!.resolve({
        WidgetState.selected,
        WidgetState.disabled,
      }),
      isNot(scheme.primary),
    );
    expect(
      theme.checkboxTheme.fillColor!.resolve({WidgetState.selected}),
      scheme.primary,
    );
    expect(theme.radioTheme.fillColor!.resolve({}), scheme.tertiary);
    expect(
      theme.iconButtonTheme.style!.foregroundColor!.resolve({}),
      scheme.tertiary,
    );
    expect(
      theme.segmentedButtonTheme.style!.backgroundColor!.resolve({
        WidgetState.selected,
      }),
      scheme.primary,
    );
    expect(
      theme.inputDecorationTheme.enabledBorder!.borderSide.color,
      scheme.tertiary,
    );
    expect(
      theme.inputDecorationTheme.focusedBorder!.borderSide.color,
      scheme.primary,
    );
    expect(
      theme.inputDecorationTheme.disabledBorder!.borderSide.color,
      isNot(scheme.tertiary),
    );
    expect(theme.textSelectionTheme.cursorColor, scheme.tertiary);
    expect(TulinkColors.dark.foregroundAccent, scheme.tertiary);
    expect(
      theme.filledButtonTheme.style!.backgroundColor!.resolve({}),
      scheme.primary,
    );
    expect(
      theme.elevatedButtonTheme.style!.foregroundColor!.resolve({}),
      scheme.onPrimary,
    );
    expect(
      theme.outlinedButtonTheme.style!.foregroundColor!.resolve({}),
      scheme.tertiary,
    );
    expect(
      theme.outlinedButtonTheme.style!.side!.resolve({})!.color,
      scheme.tertiary,
    );
    expect(
      theme.outlinedButtonTheme.style!.backgroundColor!.resolve({}),
      Colors.transparent,
    );
    expect(
      theme.filledButtonTheme.style!.backgroundColor!.resolve({
        WidgetState.disabled,
      }),
      isNot(scheme.primary),
    );
    expect(
      contrast(scheme.primary, scheme.onPrimary),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrast(scheme.surface, scheme.onSurface),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrast(scheme.surface, scheme.onSurfaceVariant),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrast(theme.scaffoldBackgroundColor, scheme.tertiary),
      greaterThanOrEqualTo(4.5),
    );
  });
  test('extension copy and interpolation retain endpoint values', () {
    expect(TulinkColors.dark.copyWith().ink, TulinkColors.dark.ink);
    expect(TulinkColors.dark.copyWith().isDark, isTrue);
    expect(
      TulinkColors.light.lerp(TulinkColors.dark, 0).surface,
      TulinkColors.light.surface,
    );
    expect(
      TulinkColors.light.lerp(TulinkColors.dark, 1).surface,
      TulinkColors.dark.surface,
    );
    expect(TulinkColors.light.lerp(TulinkColors.dark, 1).isDark, isTrue);
  });
}
