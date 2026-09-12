import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tulink_flutter/core/theme/theme_provider.dart';
import 'package:tulink_flutter/features/profile/presentation/widgets/settings_menu_item.dart';

/// Local appearance control shared by the profile and its preference sheet.
class AppearanceSetting extends StatelessWidget {
  /// Creates the appearance row in Profile preferences.
  const AppearanceSetting({super.key});

  /// User-facing name of an appearance preference.
  static String label(ThemeMode mode) => switch (mode) {
    ThemeMode.light => 'Light',
    ThemeMode.dark => 'Dark',
    ThemeMode.system => 'System',
  };

  @override
  Widget build(BuildContext context) {
    final preference = context.watch<ThemeProvider>();
    return SettingsMenuItem(
      icon: Icons.brightness_6_outlined,
      title: 'Appearance',
      subtitle: label(preference.themeMode),
      onTap: () => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (sheetContext) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Appearance',
                    style: Theme.of(sheetContext).textTheme.titleLarge,
                  ),
                ),
                for (final mode in [
                  ThemeMode.light,
                  ThemeMode.dark,
                  ThemeMode.system,
                ])
                  Semantics(
                    checked: preference.themeMode == mode,
                    child: ListTile(
                      title: Text(label(mode)),
                      subtitle: Text(switch (mode) {
                        ThemeMode.light => 'Warm, light backgrounds',
                        ThemeMode.dark =>
                          'Teal backgrounds with orange actions',
                        ThemeMode.system => 'Match your device appearance',
                      }),
                      trailing: preference.themeMode == mode
                          ? Icon(
                              Icons.check_circle,
                              color: Theme.of(
                                sheetContext,
                              ).colorScheme.tertiary,
                            )
                          : null,
                      onTap: () {
                        preference.setThemeMode(mode);
                        Navigator.of(sheetContext).pop();
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
