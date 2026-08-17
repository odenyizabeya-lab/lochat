import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/time_utils.dart';
import '../../features/profile/models/user_profile.dart';
import './admin_managed_call_history_screen.dart';
import './admin_managed_updates_screen.dart';
import './managed_account_controller.dart';
import './managed_account_scope.dart';
import './managed_chat_controller.dart';
import './managed_chat_scope.dart';
import './models/managed_account.dart';
import './models/managed_conversation.dart';
import './models/managed_message.dart';
import './data/supabase_managed_chat_repository.dart';

/// The admin dashboard's chat room.
///
/// Shows a managed account selector and the conversations list for the
/// currently selected managed account. The admin can create up to 10 managed
/// accounts and switch between them.
class AdminChatRoomScreen extends StatefulWidget {
  const AdminChatRoomScreen({super.key});

  @override
  State<AdminChatRoomScreen> createState() => _AdminChatRoomScreenState();
}

class _AdminChatRoomScreenState extends State<AdminChatRoomScreen> {
  ManagedChatController? _chatController;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ManagedAccountController accountController =
        ManagedAccountScope.of(context);
    final ManagedChatController? current = _chatController;
    if (current != null && !identical(current.accountController, accountController)) {
      current.dispose();
      _chatController = null;
    }
    _chatController ??= ManagedChatController(
      chatRepository: SupabaseManagedChatRepository(),
      accountController: accountController,
    );
  }

  @override
  void dispose() {
    _chatController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ManagedAccountController accountController =
        ManagedAccountScope.of(context);
    final ManagedAccount? selected = accountController.selectedAccount;
    final bool hasAccounts = accountController.accounts.isNotEmpty;

    if (selected == null) {
      if (!hasAccounts) {
        return _NoAccountsYet(
          onCreateFirst: () => context.push('/settings/admin/accounts'),
        );
      }
      return _AccountSwitcherNoSelection(
        accounts: accountController.accounts,
        onSelect: (account) =>
            accountController.selectAccountById(account.id),
      );
    }

    return ManagedChatScope(
      controller: _chatController!,
      child: const _ManagedChatsList(),
    );
  }
}

class _NoAccountsYet extends StatelessWidget {
  const _NoAccountsYet({required this.onCreateFirst});

  final VoidCallback onCreateFirst;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat Room'),
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.chat_bubble_outline_rounded,
                  size: 80, color: scheme.onSurfaceVariant),
              const SizedBox(height: 24),
              Text(
                'No accounts yet',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'You are the first admin. Create your first managed account to start chatting.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: onCreateFirst,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Create first account'),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => context.push('/settings/admin/accounts'),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Set up accounts manually'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountSwitcherNoSelection extends StatelessWidget {
  const _AccountSwitcherNoSelection({
    required this.accounts,
    required this.onSelect,
  });

  final List<ManagedAccount> accounts;
  final ValueChanged<ManagedAccount> onSelect;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat Room'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Manage accounts',
            icon: const Icon(Icons.people_rounded),
            onPressed: () =>
                context.push('/settings/admin/accounts'),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.chat_bubble_outline_rounded,
                  size: 56, color: scheme.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(
                'Select an account',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'You have ${accounts.length} account${accounts.length != 1 ? 's' : ''}. Select which one to chat with.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              ...accounts.map((ManagedAccount account) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundImage: account.photoUrl != null
                        ? NetworkImage(account.photoUrl!)
                        : null,
                    child: account.photoUrl == null
                        ? Text(
                            account.displayName.isNotEmpty
                                ? account.displayName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12),
                          )
                        : null,
                  ),
                  title: Text(account.displayName),
                  subtitle: Text('@${account.username}'),
                  tileColor: theme.colorScheme.surface,
                  onTap: () => onSelect(account),
                ),
              )),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () =>
                    context.push('/settings/admin/accounts'),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Manage accounts'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ManagedChatsList extends StatefulWidget {
  const _ManagedChatsList();

  @override
  State<_ManagedChatsList> createState() => _ManagedChatsListState();
}

class _ManagedChatsListState extends State<_ManagedChatsList>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  late final TabController _tabController =
      TabController(length: 3, vsync: this);

  @override
  void initState() {
    super.initState();
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ManagedChatController chat = ManagedChatScope.of(context);
    final ManagedAccountController accounts = ManagedAccountScope.of(context);
    final ManagedAccount? selected = accounts.selectedAccount;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            accountSwitcher(
              context: context,
              selected: selected,
              accounts: accounts,
              onSelect: (account) =>
                  accounts.selectAccount(account),
            ),
            const SizedBox(width: 8),
            const Text('Chat Room'),
          ],
        ),
        actions: <Widget>[
          PopupMenuButton<String>(
            tooltip: 'More options',
            onSelected: (String value) => _onMenuSelected(context, value),
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'new-chat',
                child: Row(
                  children: <Widget>[
                    Icon(Icons.edit_rounded),
                    SizedBox(width: 14),
                    Text('New chat'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'accounts',
                child: Row(
                  children: <Widget>[
                    Icon(Icons.people_rounded),
                    SizedBox(width: 14),
                    Text('Manage accounts'),
                  ],
                ),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.live,
          labelColor: AppColors.live,
          unselectedLabelColor: Colors.white70,
          tabs: const <Widget>[
            Tab(text: 'Chats'),
            Tab(text: 'Updates'),
            Tab(text: 'Calls'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: <Widget>[
          SafeArea(
            child: Column(
              children: <Widget>[
                _ChatListSearchField(
                  controller: _searchController,
                  onChanged: (String value) => setState(
                      () => _searchQuery = value.trim().toLowerCase()),
                ),
                Expanded(child: _buildConversations(context, chat)),
              ],
            ),
          ),
          AdminManagedUpdatesScreen(
            managedAccountId: selected?.id ?? '',
            embedded: true,
          ),
          AdminManagedCallHistoryScreen(
            managedAccountId: selected?.id ?? '',
            embedded: true,
          ),
        ],
      ),
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton.extended(
              onPressed: () => _newChat(context),
              icon: const Icon(Icons.edit_rounded),
              label: const Text('New chat'),
            )
          : null,
    );
  }

  Widget accountSwitcher({
    required BuildContext context,
    required ManagedAccount? selected,
    required ManagedAccountController accounts,
    required ValueChanged<ManagedAccount> onSelect,
  }) {
    return GestureDetector(
      onTap: () => _showAccountPicker(context, accounts),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CircleAvatar(
              radius: 12,
              backgroundImage: selected?.photoUrl != null
                  ? NetworkImage(selected!.photoUrl!)
                  : null,
              backgroundColor: Colors.white,
              child: selected?.photoUrl == null
                  ? Text(
                      selected?.displayName.isNotEmpty == true
                          ? selected!.displayName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    )
                  : null,
            ),
            const SizedBox(width: 6),
            Text(
              selected?.displayName ?? 'Select account',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const Icon(Icons.arrow_drop_down_rounded, color: Colors.white, size: 20),
          ],
        ),
      ),
    );
  }

  void _showAccountPicker(BuildContext context, ManagedAccountController accounts) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Text(
                  'Switch account',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              const Divider(height: 1),
              for (final ManagedAccount account in accounts.accounts)
                ListTile(
                  leading: CircleAvatar(
                    backgroundImage: account.photoUrl != null
                        ? NetworkImage(account.photoUrl!)
                        : null,
                    child: account.photoUrl == null
                        ? Text(account.displayName.isNotEmpty
                            ? account.displayName[0].toUpperCase()
                            : '?')
                        : null,
                  ),
                  title: Text(account.displayName),
                  subtitle: Text(account.displayHandle),
                  trailing: accounts.selectedAccount?.id == account.id
                      ? Icon(Icons.check_rounded,
                          color: Theme.of(context).colorScheme.primary)
                      : null,
                  onTap: () {
                    accounts.selectAccount(account);
                    Navigator.of(context).pop();
                  },
                ),
              ListTile(
                leading: const Icon(Icons.settings_rounded),
                title: const Text('Manage accounts'),
                onTap: () {
                  Navigator.of(context).pop();
                  context.push('/settings/admin/accounts');
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _buildConversations(BuildContext context, ManagedChatController chat) {
    if (!chat.hasManagedAccount) {
      return const Center(child: Text('No account selected'));
    }
    return StreamBuilder<List<ManagedConversation>>(
      stream: chat.watchConversations(),
      builder: (BuildContext context, AsyncSnapshot<List<ManagedConversation>> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Could not load conversations.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          );
        }
        final List<ManagedConversation> conversations =
            snapshot.data ?? const <ManagedConversation>[];
        final List<ManagedConversation> filtered = _searchQuery.isEmpty
            ? conversations
            : conversations
                .where((ManagedConversation c) =>
                    c.peerDisplayName.toLowerCase().contains(_searchQuery) ||
                    c.peerUsername.toLowerCase().contains(_searchQuery) ||
                    (c.lastMessageText ?? '')
                        .toLowerCase()
                        .contains(_searchQuery))
                .toList();
        if (filtered.isEmpty) {
          if (conversations.isEmpty) return _buildEmpty(context);
          return Center(
            child: Text(
              'No matches for "${_searchController.text.trim()}".',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.only(bottom: 88),
          itemCount: filtered.length,
          separatorBuilder: (_, __) => const Divider(height: 1, indent: 68),
          itemBuilder: (BuildContext context, int index) =>
              _ManagedChatTile(chat: chat, conversation: filtered[index]),
        );
      },
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.waving_hand_rounded,
                size: 56, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              'Say Hi',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Text(
              'Start a new chat to begin messaging.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  void _newChat(BuildContext context) async {
    final String? peerUid = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) => const _PickContactDialog(),
    );
    if (peerUid == null || !context.mounted) return;
    try {
      final ManagedChatController chat = ManagedChatScope.of(context);
      final String conversationId = await chat.openConversation(peerUid);
      if (!context.mounted) return;
      context.push('/settings/admin/chat', extra: <String, dynamic>{
        'conversationId': conversationId,
        'managedAccountId': chat.managedAccountId,
      });
    } on Exception {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the chat. Try again.')),
      );
    }
  }

  void _onMenuSelected(BuildContext context, String value) {
    switch (value) {
      case 'new-chat':
        _newChat(context);
      case 'accounts':
        context.push('/settings/admin/accounts');
    }
  }
}

class _PickContactDialog extends StatefulWidget {
  const _PickContactDialog();

  @override
  State<_PickContactDialog> createState() => _PickContactDialogState();
}

class _PickContactDialogState extends State<_PickContactDialog> {
  final TextEditingController _search = TextEditingController();
  List<Map<String, dynamic>> _results = const <Map<String, dynamic>>[];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = Supabase.instance.client;
      final List<Map<String, dynamic>> profiles = await client
          .from('profiles')
          .select('uid, username, display_name, photo_url, lotext_id')
          .order('display_name');
      if (mounted) {
        setState(() {
          _results = profiles;
          _loading = false;
        });
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New chat'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: _search,
              decoration: const InputDecoration(
                hintText: 'Search by name, @username or ID...',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onChanged: (String value) {
                final String q = value.trim().toLowerCase();
                setState(() {
                  _results = _results.where((Map<String, dynamic> p) {
                    final String name = (p['display_name'] as String? ?? '').toLowerCase();
                    final String user = (p['username'] as String? ?? '').toLowerCase();
                    final String id = (p['lotext_id'] as String? ?? '').toLowerCase();
                    return name.contains(q) || user.contains(q) || id.contains(q);
                  }).toList();
                });
              },
            ),
            const SizedBox(height: 12),
            if (_loading)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (_error != null)
              Text('Could not load contacts.')
            else if (_results.isEmpty)
              const Text('No contacts found.')
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _results.length,
                  itemBuilder: (BuildContext context, int index) {
                    final Map<String, dynamic> p = _results[index];
                    final String name = p['display_name'] as String? ?? '';
                    final String user = p['username'] as String? ?? '';
                    final String uid = p['uid'] as String? ?? '';
                    final String id = p['lotext_id'] as String? ?? '';
                    return ListTile(
                      leading: CircleAvatar(
                        child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?'),
                      ),
                      title: Text(name),
                      subtitle: Text(
                        id.isNotEmpty ? '@$user  ·  $id' : '@$user',
                      ),
                      onTap: () => Navigator.of(context).pop(uid),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

/// Rounded search field under the app bar of the admin chat room list.
class _ChatListSearchField extends StatelessWidget {
  const _ChatListSearchField({
    required this.controller,
    required this.onChanged,
  });

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

/// A conversation tile that mirrors the user chats list: live presence ring,
/// "typing..." indicator, and a type-aware preview with a "You:" prefix.
class _ManagedChatTile extends StatefulWidget {
  const _ManagedChatTile({
    required this.chat,
    required this.conversation,
  });

  final ManagedChatController chat;
  final ManagedConversation conversation;

  @override
  State<_ManagedChatTile> createState() => _ManagedChatTileState();
}

class _ManagedChatTileState extends State<_ManagedChatTile> {
  StreamSubscription<UserProfile?>? _presenceSub;
  UserProfile? _peer;

  @override
  void initState() {
    super.initState();
    _subscribePresence();
  }

  @override
  void didUpdateWidget(_ManagedChatTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversation.peerUid != widget.conversation.peerUid) {
      _subscribePresence();
    }
  }

  void _subscribePresence() {
    _presenceSub?.cancel();
    final String peerUid = widget.conversation.peerUid;
    if (peerUid.isEmpty) return;
    _presenceSub = widget.chat.watchPeerPresence(peerUid).listen((UserProfile? profile) {
      if (!mounted) return;
      setState(() => _peer = profile);
    });
  }

  @override
  void dispose() {
    _presenceSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final ManagedConversation conversation = widget.conversation;
    final bool unread = conversation.unreadCount > 0;
    final String? managedAccountId = widget.chat.managedAccountId;
    final bool peerTyping = _isPeerTyping(conversation, managedAccountId);
    final bool fromMe = managedAccountId != null &&
        (conversation.lastSenderUid ?? '').isNotEmpty &&
        conversation.lastSenderUid == managedAccountId;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: _PresenceAvatar(
        name: conversation.peerDisplayName,
        photoURL: conversation.peerPhotoUrl,
        online: _peer?.isOnline ?? false,
      ),
      title: Text(
        conversation.peerDisplayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyLarge?.copyWith(
          fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
        ),
      ),
      subtitle: _buildPreview(theme, scheme, peerTyping, fromMe, unread),
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
      onTap: () {
        context.push('/settings/admin/chat', extra: <String, dynamic>{
          'conversationId': conversation.id,
          'managedAccountId': conversation.managedAccountId,
        });
      },
    );
  }

  bool _isPeerTyping(
      ManagedConversation conversation, String? viewerUid) {
    final String? typingUid = conversation.typingUid;
    final DateTime? typingUntil = conversation.typingUntil;
    if (typingUid == null ||
        typingUntil == null ||
        typingUid == viewerUid) {
      return false;
    }
    return typingUntil.isAfter(DateTime.now());
  }

  Widget _buildPreview(
    ThemeData theme,
    ColorScheme scheme,
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
      return Text('typing\u2026',
          maxLines: 1, overflow: TextOverflow.ellipsis, style: baseStyle);
    }

    final ManagedConversation conversation = widget.conversation;
    final (IconData icon, String text) = switch (conversation.lastMessageType) {
      ManagedMessageType.image => (Icons.photo_rounded, 'Photo'),
      ManagedMessageType.video => (Icons.videocam_rounded, 'Video'),
      ManagedMessageType.voice => (
          Icons.mic_rounded,
          _voicePreview(conversation.lastMessageDurationMs),
        ),
      ManagedMessageType.text => (
          Icons.chat_bubble_outline_rounded,
          conversation.lastMessageText ?? '',
        ),
    };

    if (conversation.lastMessageType == ManagedMessageType.text &&
        (conversation.lastMessageText ?? '').isEmpty) {
      return const SizedBox.shrink();
    }

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

/// Avatar with a live green ring when the peer is online (WhatsApp style).
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
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Widget avatar = CircleAvatar(
      radius: 26,
      backgroundImage: photoURL != null ? NetworkImage(photoURL!) : null,
      backgroundColor: scheme.primaryContainer,
      foregroundColor: scheme.onPrimaryContainer,
      child: photoURL == null
          ? Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: theme.textTheme.titleMedium,
            )
          : null,
    );
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