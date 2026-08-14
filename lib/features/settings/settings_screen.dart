import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/auth_scope.dart';
import '../../core/constants/app_constants.dart';
import '../../core/router/app_routes.dart';
import '../../core/theme/theme_controller.dart';
import '../profile/models/user_profile.dart';
import '../profile/profile_controller.dart';
import '../profile/profile_scope.dart';

/// App settings. Currently exposes the theme preference (system / light /
/// dark), which is fully functional through [ThemeController], plus an admin
/// section for managing AI provider keys (visible only to admins).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.themeController});

  final ThemeController themeController;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final UserProfile? profile = ProfileScope.maybeOf(context)?.profile;

    return _OwnerAdminBootstrap(
      child: Scaffold(
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
                              secondary: const Icon(
                                Icons.brightness_auto_outlined,
                              ),
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
                      leading: Icon(
                        Icons.info_outline_rounded,
                        color: scheme.primary,
                      ),
                      title: const Text('LoText'),
                      subtitle: const Text(
                        'Fast, private messaging made simple.',
                      ),
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
              if (profile?.isAdmin ?? false) ...<Widget>[
                const SizedBox(height: 24),
                _SectionLabel(label: 'Admin', scheme: scheme, theme: theme),
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    leading: Icon(
                      Icons.admin_panel_settings_outlined,
                      color: scheme.primary,
                    ),
                    title: const Text('Admin dashboard'),
                    subtitle: const Text('Manage AI provider keys'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.push(AppRoutes.adminSettings),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              _SectionLabel(label: 'Account', scheme: scheme, theme: theme),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: Icon(
                    Icons.delete_forever_outlined,
                    color: scheme.error,
                  ),
                  title: const Text('Delete account'),
                  subtitle: const Text(
                    'Permanently delete your account and all data',
                  ),
                  onTap: () => _confirmDeleteAccount(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _setMode(ThemeMode? mode) {
    if (mode != null) themeController.setMode(mode);
  }

  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => const _DeleteAccountDialog(),
    );
    if (confirmed != true || !context.mounted) return;
    final AuthController auth = AuthScope.of(context);
    try {
      await auth.deleteAccount();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('We could not delete your account. Please try again.'),
        ),
      );
    }
  }
}

/// Final confirmation for account deletion. Requires the user to type DELETE so
/// an accidental tap cannot wipe the account.
class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _confirmed = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    final bool confirmed = value.trim().toUpperCase() == 'DELETE';
    if (confirmed != _confirmed) {
      setState(() => _confirmed = confirmed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final ThemeData theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Delete account?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'This permanently deletes your account, profile, messages, '
            'contacts, statuses and AI chats. Your username and LoText ID are '
            'freed. This cannot be undone.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Text('Type DELETE to confirm:', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            onChanged: _onChanged,
            autocorrect: false,
            autofocus: true,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: 'DELETE',
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: _confirmed ? () => Navigator.of(context).pop(true) : null,
          child: const Text('Delete'),
        ),
      ],
    );
  }
}

/// Quietly claims owner admin for the very first user to open Settings (when
/// no admin exists yet), so the Admin dashboard appears without any SQL step.
class _OwnerAdminBootstrap extends StatefulWidget {
  const _OwnerAdminBootstrap({required this.child});

  final Widget child;

  @override
  State<_OwnerAdminBootstrap> createState() => _OwnerAdminBootstrapState();
}

class _OwnerAdminBootstrapState extends State<_OwnerAdminBootstrap> {
  bool _attempted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_attempted) return;
    final ProfileController? profile = ProfileScope.maybeOf(context);
    final UserProfile? current = profile?.profile;
    if (profile == null || current == null) return;
    if (current.isAdmin) return;
    _attempted = true;
    unawaited(profile.ensureOwnerAdmin());
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.label,
    required this.scheme,
    required this.theme,
  });

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
