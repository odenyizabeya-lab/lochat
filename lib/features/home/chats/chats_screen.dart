import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/time_utils.dart';
import '../../../shared/widgets/contact_picker_sheet.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/lotext_button.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../chat/chat_controller.dart';
import '../../chat/chat_scope.dart';
import '../../chat/data/chat_repository.dart' show NotAContactException;
import '../../chat/models/chat_message.dart';
import '../../chat/models/conversation.dart';
import '../../profile/models/contact.dart';
import '../../profile/models/user_profile.dart';
import '../../profile/profile_scope.dart';

/// Chats tab: the messenger home. A bold "LoText" header with a three-dot
/// overflow menu, a rounded search field that filters conversations and
/// contacts, an Archived entry, and the conversation list with type-aware
/// previews, presence rings, timestamps and unread badges.
///
/// A "New chat" floating action button picks a contact (from the user's own
/// private list) and opens a conversation. The same widget backs the admin
/// dashboard's "Chat Room" via [title].
class ChatsScreen extends StatefulWidget {
  const ChatsScreen({
    super.key,
    this.title = 'LoText',
  });

  /// App bar title (the admin dashboard uses "Chat Room").
  final String title;

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) => setState(() => _query = value.trim());

  Future<void> _newChat() async {
    final UserProfile? peer = await showContactPicker(context);
    if (peer == null || !mounted) return;
    try {
      final ChatController chat = ChatScope.of(context);
      final String conversationId = await chat.openConversation(peer.uid);
      if (!mounted) return;
      await context.push(AppRoutes.chatFor(conversationId));
    } on NotAContactException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add them as a contact to chat.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the chat. Try again.')),
      );
    }
  }

  void _openArchived() {
    context.push(
      AppRoutes.chatsArchived,
      extra: <String, dynamic>{'title': widget.title},
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final UserProfile? profile = ProfileScope.maybeOf(context)?.profile;
    final bool isAdmin = profile?.isAdmin ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: <Widget>[
          IconButton(
            tooltip: 'Start a chat',
            icon: const Icon(Icons.photo_camera_outlined),
            onPressed: () => unawaited(_newChat()),
          ),
          PopupMenuButton<String>(
            tooltip: 'More options',
            onSelected: (String value) => _onMenuSelected(context, value),
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'new-chat',
                child: _MenuRow(icon: Icons.edit_rounded, label: 'New chat'),
              ),
              const PopupMenuItem<String>(
                value: 'add-contact',
                child: _MenuRow(
                  icon: Icons.person_add_alt_1_rounded,
                  label: 'Add contact',
                ),
              ),
              const PopupMenuItem<String>(
                value: 'contacts',
                child: _MenuRow(
                  icon: Icons.contacts_outlined,
                  label: 'Contacts',
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'settings',
                child: _MenuRow(
                  icon: Icons.settings_outlined,
                  label: 'Settings',
                ),
              ),
              if (isAdmin) ...<PopupMenuEntry<String>>[
                const PopupMenuDivider(),
                const PopupMenuItem<String>(
                  value: 'ai',
                  child: _MenuRow(
                    icon: Icons.auto_awesome_rounded,
                    label: 'LoText AI',
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'admin',
                  child: _MenuRow(
                    icon: Icons.admin_panel_settings_outlined,
                    label: 'Admin dashboard',
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newChat,
        icon: const Icon(Icons.edit_rounded),
        label: const Text('New chat'),
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _SearchField(
              controller: _searchController,
              onChanged: _onQueryChanged,
            ),
            if (_query.isEmpty) ...[
              _ArchivedRow(
                onTap: _openArchived,
                theme: theme,
              ),
              const SizedBox(height: 4),
            ],
            Expanded(
              child: _query.isEmpty
                  ? _buildConversations(theme)
                  : _buildSearchResults(theme),
            ),
          ],
        ),
      ),
    );
  }

  void _onMenuSelected(BuildContext context, String value) {
    switch (value) {
      case 'new-chat':
        unawaited(_newChat());
      case 'add-contact':
        context.push(AppRoutes.addContact);
      case 'contacts':
        context.push(AppRoutes.contacts);
      case 'settings':
        context.push(AppRoutes.settings);
      case 'ai':
        context.push(AppRoutes.ai);
      case 'admin':
        context.push(AppRoutes.adminSettings);
    }
  }

  Widget _buildConversations(ThemeData theme) {
    return StreamBuilder<List<Conversation>>(
      stream: ChatScope.of(context).watchConversations(),
      builder: (BuildContext context,
          AsyncSnapshot<List<Conversation>> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Could not load your conversations.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
            ),
          );
        }

        final List<Conversation> conversations =
            snapshot.data ?? const <Conversation>[];
        if (conversations.isEmpty) {
          return _buildEmpty(theme);
        }
        return ListView.separated(
          padding: const EdgeInsets.only(bottom: 88),
          itemCount: conversations.length,
          separatorBuilder: (_, _) =>
              const Divider(height: 1, indent: 80),
          itemBuilder: (BuildContext context, int index) =>
              _buildConversationTile(conversations[index]),
        );
      },
    );
  }

  Widget _buildSearchResults(ThemeData theme) {
    final String query = _query.toLowerCase();
    return StreamBuilder<List<Contact>>(
      stream: ProfileScope.of(context).watchContacts(),
      builder: (BuildContext context,
          AsyncSnapshot<List<Contact>> contactSnapshot) {
        final List<Contact> contacts =
            (contactSnapshot.data ?? const <Contact>[])
                .where((Contact c) =>
                    c.profile.displayName.toLowerCase().contains(query) ||
                    c.profile.username.toLowerCase().contains(query))
                .toList();
        return StreamBuilder<List<Conversation>>(
          stream: ChatScope.of(context).watchConversations(),
          builder: (BuildContext context,
              AsyncSnapshot<List<Conversation>> conversationSnapshot) {
            final List<Conversation> conversations =
                (conversationSnapshot.data ?? const <Conversation>[])
                    .where((Conversation c) {
              final String name = c.peer.displayName.isNotEmpty
                  ? c.peer.displayName
                  : c.peer.username;
              return name.toLowerCase().contains(query) ||
                  c.peer.username.toLowerCase().contains(query) ||
                  c.lastMessageText.toLowerCase().contains(query);
            }).toList();

            if (contacts.isEmpty && conversations.isEmpty) {
              return const EmptyStateView(
                icon: Icons.search_off_rounded,
                title: 'No results found',
                message: 'Try a different name, username or message.',
              );
            }

            final List<Widget> children = <Widget>[];
            if (contacts.isNotEmpty) {
              children.add(_SearchSectionHeader(theme: theme, label: 'Contacts'));
              for (final Contact contact in contacts) {
                children.add(_buildContactResult(contact));
              }
            }
            if (conversations.isNotEmpty) {
              children.add(_SearchSectionHeader(theme: theme, label: 'Chats'));
              for (final Conversation conversation in conversations) {
                children.add(_buildConversationTile(conversation));
              }
            }
            return ListView(
              padding: const EdgeInsets.only(bottom: 88),
              children: children,
            );
          },
        );
      },
    );
  }

  Widget _buildContactResult(Contact contact) {
    final String name = contact.profile.displayName.isNotEmpty
        ? contact.profile.displayName
        : contact.profile.username;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      leading: UserAvatar(
        name: name,
        photoURL: contact.profile.photoURL,
        size: 48,
      ),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        contact.profile.handle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
      onTap: () => context.push(AppRoutes.publicProfileFor(contact.uid)),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return EmptyStateView(
      icon: Icons.forum_outlined,
      title: 'No conversations yet',
      message:
          'Message a contact to get started. Conversations are private to '
          'you and the person you chat with.',
      action: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          LoTextButton(
            label: 'Add contact',
            icon: Icons.person_add_alt_1_rounded,
            isExpanded: true,
            onPressed: () => context.push(AppRoutes.addContact),
          ),
          const SizedBox(height: 12),
          LoTextButton(
            label: 'Browse contacts',
            icon: Icons.contacts_outlined,
            variant: LoTextButtonVariant.outline,
            isExpanded: true,
            onPressed: () => context.push(AppRoutes.contacts),
          ),
        ],
      ),
    );
  }

  Widget _buildConversationTile(Conversation conversation) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final UserProfile peer = conversation.peer;
    final String displayName = peer.displayName.isNotEmpty
        ? peer.displayName
        : peer.username;
    final String myUid = ChatScope.of(context).uid ?? '';
    final bool peerTyping = conversation.isTypingFrom(myUid);
    final bool unread = conversation.unreadCount > 0;
    final bool fromMe = conversation.lastSentBy(myUid);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: _PresenceAvatar(
        name: displayName,
        photoURL: peer.photoURL,
        online: peer.isOnline,
      ),
      title: Text(
        displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyLarge?.copyWith(
          fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
        ),
      ),
      subtitle: _buildPreview(
        theme,
        scheme,
        conversation,
        peerTyping,
        fromMe,
        unread,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Text(
            formatChatTime(conversation.lastMessageAt),
            style: theme.textTheme.labelSmall?.copyWith(
              color: unread ? AppColors.live : scheme.onSurfaceVariant,
              fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          if (unread) ...<Widget>[
            const SizedBox(height: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.live,
                borderRadius: BorderRadius.circular(12),
              ),
              constraints: const BoxConstraints(minWidth: 22),
              child: Text(
                '${conversation.unreadCount}',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: const Color(0xFF06332B),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ],
      ),
      onTap: () => context.push(AppRoutes.chatFor(conversation.id)),
    );
  }

  Widget _buildPreview(
    ThemeData theme,
    ColorScheme scheme,
    Conversation conversation,
    bool peerTyping,
    bool fromMe,
    bool unread,
  ) {
    final TextStyle baseStyle = theme.textTheme.bodyMedium!.copyWith(
      color: peerTyping
          ? AppColors.live
          : (unread ? scheme.onSurface : scheme.onSurfaceVariant),
      fontWeight: peerTyping
          ? FontWeight.w600
          : (unread ? FontWeight.w600 : FontWeight.w400),
      fontStyle: peerTyping ? FontStyle.italic : FontStyle.normal,
    );

    if (peerTyping) {
      return Text('typing\u2026', maxLines: 1, overflow: TextOverflow.ellipsis, style: baseStyle);
    }

    final (IconData icon, String text) = switch (conversation.lastMessageType) {
      MessageType.image => (Icons.photo_rounded, 'Photo'),
      MessageType.video => (Icons.videocam_rounded, 'Video'),
      MessageType.voice => (
          Icons.mic_rounded,
          _voicePreview(conversation.lastMessageDurationMs),
        ),
      MessageType.text => (Icons.chat_bubble_outline_rounded, conversation.lastMessageText),
    };

    final String prefix = fromMe ? 'You: ' : '';
    final double? iconSize = theme.textTheme.bodyMedium?.fontSize;
    final TextStyle iconStyle = baseStyle.copyWith(fontSize: iconSize);

    return Row(
      children: <Widget>[
        Icon(icon, size: iconSize, color: iconStyle.color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            prefix + text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: baseStyle,
          ),
        ),
      ],
    );
  }

  String _voicePreview(int? durationMs) {
    if (durationMs == null || durationMs <= 0) return 'Voice message';
    return 'Voice message (${formatDuration(Duration(milliseconds: durationMs))})';
  }
}

/// Rounded search field under the app bar.
class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
          filled: true,
          fillColor: isDark
              ? const Color(0xFF232730)
              : scheme.surfaceContainerHighest,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

/// Archived entry row (opens the archive screen, which is empty until the
/// archive feature exists — no fake data is ever shown).
class _ArchivedRow extends StatelessWidget {
  const _ArchivedRow({required this.onTap, required this.theme});

  final VoidCallback onTap;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = theme.colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(Icons.archive_rounded, color: scheme.onSurfaceVariant),
      ),
      title: Text(
        'Archived',
        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      trailing: Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
      onTap: onTap,
    );
  }
}

/// Avatar with a live presence ring for online contacts.
class _PresenceAvatar extends StatelessWidget {
  const _PresenceAvatar({
    required this.name,
    required this.photoURL,
    required this.online,
  });

  final String name;
  final String? photoURL;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final Widget avatar = UserAvatar(name: name, photoURL: photoURL, size: 50);
    if (!online) return avatar;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.live, width: 2),
      ),
      child: avatar,
    );
  }
}

class _SearchSectionHeader extends StatelessWidget {
  const _SearchSectionHeader({required this.theme, required this.label});

  final ThemeData theme;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      ],
    );
  }
}
