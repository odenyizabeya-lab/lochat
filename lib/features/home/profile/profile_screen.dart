import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/auth/auth_scope.dart';
import '../../../core/router/app_routes.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/loading_view.dart';
import '../../../shared/widgets/lotext_button.dart';
import '../../../shared/widgets/presence_indicator.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../profile/models/user_profile.dart';
import '../../profile/profile_controller.dart';
import '../../profile/profile_scope.dart';

/// Profile tab. Shows the signed-in user's public profile (photo, display
/// name, @username, LoText ID, presence), copy actions, an Edit profile
/// action, settings, and sign out.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _signingOut = false;

  Future<void> _signOut() async {
    final AuthController auth = AuthScope.of(context);
    setState(() => _signingOut = true);
    try {
      await auth.signOut();
      // Router redirects to the welcome flow automatically.
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  Future<void> _copyToClipboard(String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    AppSnackbars.showInfo(context, '$label copied to clipboard.');
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final ProfileController controller = ProfileScope.of(context);
    final UserProfile? profile = controller.profile;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: SafeArea(
        child: controller.isLoading
            ? const LoadingView(message: 'Loading profile\u2026')
            : controller.error != null
                ? ErrorView(
                    title: 'Could not load your profile',
                    message: 'Check your connection and try again.',
                    onRetry: controller.reload,
                  )
                : profile == null
                    ? _buildNoProfile(theme, scheme)
                    : _buildProfile(theme, scheme, controller, profile),
      ),
    );
  }

  Widget _buildNoProfile(ThemeData theme, ColorScheme scheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.person_outline_rounded, size: 64, color: scheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              'Set up your profile',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose a username to get started.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            LoTextButton(
              label: 'Choose username',
              isExpanded: true,
              onPressed: () => context.go(AppRoutes.chooseUsername),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfile(
    ThemeData theme,
    ColorScheme scheme,
    ProfileController controller,
    UserProfile profile,
  ) {
    final String displayName = profile.displayName.isNotEmpty
        ? profile.displayName
        : profile.username;
    final String lotextId = profile.lotextId ?? '';

    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: <Widget>[
                UserAvatar(
                  name: displayName,
                  photoURL: profile.photoURL,
                  size: 96,
                ),
                const SizedBox(height: 16),
                Text(
                  displayName,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  profile.handle,
                  style: theme.textTheme.bodyMedium?.copyWith(color: scheme.primary),
                ),
                const SizedBox(height: 12),
                PresenceIndicator(
                  isOnline: profile.isOnline,
                  lastSeen: profile.lastSeen,
                ),
                const SizedBox(height: 20),
                if (lotextId.isNotEmpty) ...<Widget>[
                  _LotextIdPanel(theme: theme, scheme: scheme, lotextId: lotextId),
                  const SizedBox(height: 16),
                ],
                LoTextButton(
                  label: 'Copy username',
                  icon: Icons.copy_rounded,
                  variant: LoTextButtonVariant.outline,
                  isExpanded: true,
                  onPressed: profile.username.isEmpty
                      ? null
                      : () => _copyToClipboard(profile.username, 'Username'),
                ),
                if (lotextId.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  LoTextButton(
                    label: 'Copy LoText ID',
                    icon: Icons.copy_rounded,
                    variant: LoTextButtonVariant.outline,
                    isExpanded: true,
                    onPressed: () => _copyToClipboard(lotextId, 'LoText ID'),
                  ),
                ],
                const SizedBox(height: 20),
                LoTextButton(
                  label: 'Edit profile',
                  icon: Icons.edit_outlined,
                  isExpanded: true,
                  onPressed: () => context.go(AppRoutes.editProfile),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: Icon(Icons.settings_outlined, color: scheme.primary),
            title: const Text('Settings'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.go(AppRoutes.settings),
          ),
        ),
        const SizedBox(height: 16),
        LoTextButton(
          label: 'Sign out',
          variant: LoTextButtonVariant.outline,
          icon: Icons.logout_rounded,
          isExpanded: true,
          isLoading: _signingOut,
          onPressed: _signOut,
        ),
      ],
    );
  }
}

class _LotextIdPanel extends StatelessWidget {
  const _LotextIdPanel({
    required this.theme,
    required this.scheme,
    required this.lotextId,
  });

  final ThemeData theme;
  final ColorScheme scheme;
  final String lotextId;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: <Widget>[
          Text(
            'LoText ID: $lotextId',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Your unique LoText ID. Share it with people you want to connect '
            'with.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
