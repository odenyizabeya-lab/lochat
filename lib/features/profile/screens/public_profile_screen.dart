import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/loading_view.dart';
import '../../../shared/widgets/lotext_button.dart';
import '../../../shared/widgets/presence_indicator.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../chat/chat_controller.dart';
import '../../chat/data/chat_repository.dart' show NotAContactException;
import '../../chat/chat_scope.dart';
import '../models/user_profile.dart';
import '../profile_controller.dart';
import '../profile_scope.dart';

/// Public profile view of another user: photo, display name, @username,
/// LoText ID, presence, contact actions, and a Message button that opens a
/// private 1-to-1 conversation (messaging requires being a contact).
class PublicProfileScreen extends StatefulWidget {
  const PublicProfileScreen({super.key, required this.uid});

  final String uid;

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  UserProfile? _profile;
  bool _loading = true;
  Object? _error;
  bool _didLoad = false;

  bool _isSelf = false;
  bool _isContact = false;
  bool _contactBusy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didLoad) return;
    _didLoad = true;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ProfileController controller = ProfileScope.of(context);
      final UserProfile? profile = await controller.fetchProfile(widget.uid);
      if (!mounted) return;

      final String myUid = controller.profile?.uid ?? '';
      bool isContact = false;
      if (profile != null && profile.uid != myUid) {
        isContact = await controller.isContact(profile.uid);
      }
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _isSelf = profile?.uid == myUid;
        _isContact = isContact;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _message() async {
    final UserProfile? profile = _profile;
    if (profile == null) return;
    try {
      final ChatController chat = ChatScope.of(context);
      final String conversationId = await chat.openConversation(profile.uid);
      if (!mounted) return;
      await context.push(AppRoutes.chatFor(conversationId));
    } on NotAContactException {
      if (!mounted) return;
      AppSnackbars.showInfo(
        context,
        'Add them as a contact to start messaging.',
      );
    } catch (_) {
      if (!mounted) return;
      AppSnackbars.showError(context, 'Could not open the chat. Try again.');
    }
  }

  Future<void> _toggleContact() async {
    final UserProfile? profile = _profile;
    if (profile == null) return;
    setState(() => _contactBusy = true);
    try {
      final ProfileController controller = ProfileScope.of(context);
      if (_isContact) {
        await controller.removeContact(profile.uid);
      } else {
        await controller.addContact(profile.uid);
      }
      if (!mounted) return;
      setState(() {
        _isContact = !_isContact;
        _contactBusy = false;
      });
      AppSnackbars.showInfo(
        context,
        _isContact ? 'Added to your contacts.' : 'Removed from your contacts.',
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _contactBusy = false);
      AppSnackbars.showError(context, 'Something went wrong. Try again.');
    }
  }

  Future<void> _copyLotextId(String lotextId) async {
    await Clipboard.setData(ClipboardData(text: lotextId));
    if (!mounted) return;
    AppSnackbars.showInfo(context, 'LoText ID copied to clipboard.');
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: SafeArea(
        child: _loading
            ? const LoadingView(message: 'Loading profile\u2026')
            : _error != null
                ? ErrorView(
                    title: 'Could not load profile',
                    message: 'Check your connection and try again.',
                    onRetry: _load,
                  )
                : _profile == null
                    ? const ErrorView(title: 'User not found')
                    : _buildProfile(theme, scheme),
      ),
    );
  }

  Widget _buildProfile(ThemeData theme, ColorScheme scheme) {
    final UserProfile profile = _profile!;
    final String displayName = profile.displayName.isNotEmpty
        ? profile.displayName
        : profile.username;
    final String lotextId = profile.lotextId ?? '';

    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        const SizedBox(height: 16),
        Center(
          child: UserAvatar(
            name: displayName,
            photoURL: profile.photoURL,
            size: 104,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          displayName,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          profile.handle,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(color: scheme.primary),
        ),
        if (lotextId.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            'LoText ID: $lotextId',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              letterSpacing: 0.8,
            ),
          ),
        ],
        const SizedBox(height: 12),
        Center(
          child: PresenceIndicator(
            isOnline: profile.isOnline,
            lastSeen: profile.lastSeen,
          ),
        ),
        const SizedBox(height: 32),
        if (_isSelf)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              'That\u2019s you',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          )
        else ...<Widget>[
          LoTextButton(
            label: _isContact ? 'Remove contact' : 'Add contact',
            icon: _isContact
                ? Icons.person_remove_alt_1_rounded
                : Icons.person_add_alt_1_rounded,
            variant: _isContact
                ? LoTextButtonVariant.outline
                : LoTextButtonVariant.secondary,
            isExpanded: true,
            isLoading: _contactBusy,
            onPressed: _contactBusy ? null : _toggleContact,
          ),
          const SizedBox(height: 12),
          LoTextButton(
            label: 'Message',
            icon: Icons.chat_bubble_outline_rounded,
            isExpanded: true,
            onPressed: _message,
          ),
          const SizedBox(height: 12),
        ],
        if (!_isSelf && lotextId.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          LoTextButton(
            label: 'Copy LoText ID',
            icon: Icons.copy_rounded,
            variant: LoTextButtonVariant.outline,
            isExpanded: true,
            onPressed: () => _copyLotextId(lotextId),
          ),
        ],
      ],
    );
  }
}
