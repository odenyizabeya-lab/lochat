import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/theme_controller.dart';

/// App settings. Currently exposes the theme preference (system / light /
/// dark), which is fully functional through [ThemeController].
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.themeController});

  final ThemeController themeController;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: <Widget>[
            _SectionLabel(label: 'Appearance', scheme: scheme, theme: theme),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: ListenableBuilder(
                  listenable: themeController,
                  builder: (BuildContext context, Widget? _) {
                    return RadioGroup<ThemeMode>(
                      groupValue: themeController.mode,
                      onChanged: _setMode,
                      child: Column(
                        children: <Widget>[
                          RadioListTile<ThemeMode>(
                            value: ThemeMode.system,
                            secondary: const Icon(Icons.brightness_auto_outlined),
                            title: const Text('System'),
                            subtitle: const Text('Follow your device'),
                          ),
                          RadioListTile<ThemeMode>(
                            value: ThemeMode.light,
                            secondary: const Icon(Icons.light_mode_outlined),
                            title: const Text('Light'),
                            subtitle: const Text('Always use light mode'),
                          ),
                          RadioListTile<ThemeMode>(
                            value: ThemeMode.dark,
                            secondary: const Icon(Icons.dark_mode_outlined),
                            title: const Text('Dark'),
                            subtitle: const Text('Always use dark mode'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 24),
            _SectionLabel(label: 'About', scheme: scheme, theme: theme),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: <Widget>[
                  ListTile(
                    leading: Icon(Icons.info_outline_rounded, color: scheme.primary),
                    title: const Text('LoText'),
                    subtitle: const Text('Fast, private messaging made simple.'),
                  ),
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    leading: Icon(Icons.tag_rounded, color: scheme.primary),
                    title: const Text('Version'),
                    trailing: Text(
                      AppConstants.version,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _setMode(ThemeMode? mode) {
    if (mode != null) themeController.setMode(mode);
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.scheme, required this.theme});

  final String label;
  final ColorScheme scheme;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: theme.textTheme.labelLarge?.copyWith(
        color: scheme.primary,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}
