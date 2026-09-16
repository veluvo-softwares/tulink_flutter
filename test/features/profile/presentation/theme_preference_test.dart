import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:tulink_flutter/core/theme/app_theme.dart';
import 'package:tulink_flutter/core/theme/theme_provider.dart';
import 'package:tulink_flutter/features/profile/presentation/widgets/appearance_setting.dart';

void main() {
  testWidgets('appearance choices update the theme and selected indicator', (
    tester,
  ) async {
    final preference = ThemeProvider();
    addTearDown(preference.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: preference,
        child: Consumer<ThemeProvider>(
          builder: (context, theme, _) => MaterialApp(
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: theme.themeMode,
            home: const Scaffold(body: AppearanceSetting()),
          ),
        ),
      ),
    );
    for (final mode in [ThemeMode.dark, ThemeMode.light, ThemeMode.system]) {
      await tester.tap(find.text('Appearance'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      await tester.tap(find.text(AppearanceSetting.label(mode)).last);
      await tester.pumpAndSettle();
      expect(preference.themeMode, mode);
      expect(find.text(AppearanceSetting.label(mode)), findsOneWidget);
      final context = tester.element(find.byType(AppearanceSetting));
      expect(
        Theme.of(context).brightness,
        mode == ThemeMode.dark ? Brightness.dark : Brightness.light,
      );
    }
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(AppearanceSetting))).brightness,
      Brightness.dark,
    );
    tester.platformDispatcher.clearPlatformBrightnessTestValue();
  });
}
