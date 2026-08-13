import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_routes.dart';
import '../profile/models/user_profile.dart';
import '../profile/profile_controller.dart';
import '../profile/profile_scope.dart';
import 'admin_config_controller.dart';
import 'data/app_config_repository.dart';
import 'data/supabase_app_config_repository.dart';

/// One AI provider whose API key can be managed from the Admin dashboard.
class AdminKeyOption {
  const AdminKeyOption({required this.key, required this.provider});

  /// Config row key (matches the env var the edge function looks up).
  final String key;

  /// Human-readable provider name.
  final String provider;
}

/// Admin dashboard for managing AI provider API keys.
///
/// Keys are stored in the `app_config` table (RLS: admins only) and read by
/// the `ai-assistant` edge function as a fallback when no environment secret
/// is set, so a key saved here takes effect immediately without a redeploy.
class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key, this.repository});

  /// Injectable for tests; defaults to the Supabase-backed repository.
  final AppConfigRepository? repository;

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  late final AdminConfigController _controller;
  bool _ownerClaimAttempted = false;

  static const List<AdminKeyOption> _keyOptions = <AdminKeyOption>[
    AdminKeyOption(key: 'OPENAI_API_KEY', provider: 'OpenAI'),
    AdminKeyOption(key: 'ANTHROPIC_API_KEY', provider: 'Anthropic'),
    AdminKeyOption(key: 'GEMINI_API_KEY', provider: 'Google Gemini'),
  ];

  @override
  void initState() {
    super.initState();
    _controller = AdminConfigController(
      repository: widget.repository ?? SupabaseAppConfigRepository(),
    );
    _controller.load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ownerClaimAttempted) return;
    final ProfileController? profile = ProfileScope.maybeOf(context);
    final UserProfile? current = profile?.profile;
    if (profile == null || current == null) return;
    if (current.isAdmin) return;
    _ownerClaimAttempted = true;
    unawaited(_claimOwnerAdmin(profile));
  }

  /// Bootstrap: when reached directly and no admin exists yet, claim owner
  /// admin and reload so the keys appear without reopening the screen.
  Future<void> _claimOwnerAdmin(ProfileController profile) async {
    final bool granted = await profile.ensureOwnerAdmin();
    if (granted && mounted) {
      await _controller.load();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Admin dashboard')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _controller,
          builder: (BuildContext context, Widget? _) {
            if (_controller.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (_controller.hasError) {
              return _ErrorState(
                message: 'Could not load the admin configuration.',
                onRetry: _controller.load,
              );
            }
            if (!_controller.isAdmin) {
              return const _RestrictedNotice();
            }
            return ListView(
              padding: const EdgeInsets.all(20),
              children: <Widget>[
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => context.push(AppRoutes.ai),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: <Widget>[
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: <Color>[
                                  scheme.primaryContainer,
                                  scheme.tertiaryContainer,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              Icons.auto_awesome_rounded,
                              color: scheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  'AI assistant',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Write, rewrite, summarize and translate.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.arrow_forward_rounded,
                            color: scheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => context.push(AppRoutes.adminChatRoom),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: <Widget>[
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: <Color>[
                                  scheme.primaryContainer,
                                  scheme.tertiaryContainer,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              Icons.chat_bubble_rounded,
                              color: scheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  'Chat Room',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Your conversations with LoText users.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.arrow_forward_rounded,
                            color: scheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _InfoBanner(theme: theme, scheme: scheme),
                const SizedBox(height: 16),
                Card(
                  child: Column(
                    children: <Widget>[
                      for (int i = 0; i < _keyOptions.length; i++) ...<Widget>[
                        if (i > 0) const Divider(height: 1, indent: 56),
                        _KeyTile(
                          option: _keyOptions[i],
                          controller: _controller,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _KeyTile extends StatelessWidget {
  const _KeyTile({required this.option, required this.controller});

  final AdminKeyOption option;
  final AdminConfigController controller;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final String? value = controller.valueOf(option.key);
    final bool isSet = controller.hasValue(option.key);

    return ListTile(
      leading: Icon(
        Icons.key_rounded,
        color: isSet ? scheme.primary : scheme.outline,
      ),
      title: Text(option.provider),
      subtitle: Text(
        isSet ? _mask(value!) : 'Not set',
        style: theme.textTheme.bodySmall?.copyWith(
          color: isSet ? scheme.onSurfaceVariant : scheme.error,
          fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            icon: const Icon(Icons.visibility_outlined),
            tooltip: 'View or change the key',
            onPressed: () => _editKey(context),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: 'Remove the key',
            onPressed: isSet ? () => _confirmRemove(context) : null,
          ),
        ],
      ),
      onTap: () => _editKey(context),
    );
  }

  Future<void> _editKey(BuildContext context) async {
    final String? saved = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => _KeyEditorDialog(
        title: '${option.provider} key',
        configKey: option.key,
        currentValue: controller.valueOf(option.key),
      ),
    );
    if (saved != null && context.mounted) {
      await controller.setValue(option.key, saved);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${option.provider} key saved.')),
        );
      }
    }
  }

  Future<void> _confirmRemove(BuildContext context) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('Remove ${option.provider} key?'),
        content: const Text(
          'The AI provider will no longer be usable until a new key is set.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await controller.remove(option.key);
    }
  }

  String _mask(String value) {
    if (value.length <= 8) return '\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022';
    return '${value.substring(0, 4)}\u2022\u2022\u2022\u2022'
        '${value.substring(value.length - 4)}';
  }
}

class _KeyEditorDialog extends StatefulWidget {
  const _KeyEditorDialog({
    required this.title,
    required this.configKey,
    required this.currentValue,
  });

  final String title;
  final String configKey;
  final String? currentValue;

  @override
  State<_KeyEditorDialog> createState() => _KeyEditorDialogState();
}

class _KeyEditorDialogState extends State<_KeyEditorDialog> {
  late final TextEditingController _textController;
  bool _obscured = true;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.currentValue ?? '');
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _textController,
        obscureText: _obscured,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(
          labelText: widget.configKey,
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            icon: Icon(
              _obscured
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
            onPressed: () => setState(() => _obscured = !_obscured),
          ),
        ),
        onSubmitted: _save,
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => _save(_textController.text),
          child: const Text('Save'),
        ),
      ],
    );
  }

  void _save(String value) {
    if (value.trim().isEmpty) return;
    Navigator.of(context).pop(value);
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.theme, required this.scheme});

  final ThemeData theme;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.info_outline_rounded, color: scheme.primary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Keys saved here are used by the AI assistant when no secret is '
              'configured for this function. A key set in the Supabase CLI '
              'always takes priority.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RestrictedNotice extends StatelessWidget {
  const _RestrictedNotice();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.admin_panel_settings_outlined,
                size: 48, color: scheme.outline),
            const SizedBox(height: 12),
            Text(
              'Only admins can manage provider keys.',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.error_outline_rounded, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
