import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import './managed_account_controller.dart';
import './managed_account_scope.dart';
import './managed_chat_controller.dart';
import './managed_chat_scope.dart';
import './models/managed_account.dart';
import './models/managed_conversation.dart';
import './data/supabase_managed_chat_repository.dart';

/// The admin dashboard's chat room.
///
/// Shows a managed account selector and the conversations list for the
/// currently selected managed account. The admin can create up to 10 managed
/// accounts and switch between them.
class AdminChatRoomScreen extends StatelessWidget {
  const AdminChatRoomScreen({super.key});

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
      controller: ManagedChatController(
        chatRepository: SupabaseManagedChatRepository(),
        accountController: accountController,
      ),
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

class _ManagedChatsList extends StatelessWidget {
  const _ManagedChatsList();

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
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _newChat(context),
        icon: const Icon(Icons.edit_rounded),
        label: const Text('New chat'),
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(child: _buildConversations(context, chat)),
          ],
        ),
      ),
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
        if (conversations.isEmpty) {
          return _buildEmpty(context);
        }
        return ListView.separated(
          padding: const EdgeInsets.only(bottom: 88),
          itemCount: conversations.length,
          separatorBuilder: (_, __) => const Divider(height: 1, indent: 68),
          itemBuilder: (BuildContext context, int index) =>
              _buildConversationTile(context, chat, conversations[index]),
        );
      },
    );
  }

  Widget _buildConversationTile(
      BuildContext context, ManagedChatController chat,
      ManagedConversation conversation) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool unread = conversation.unreadCount > 0;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: CircleAvatar(
        radius: 26,
        backgroundImage: conversation.peerPhotoUrl != null
            ? NetworkImage(conversation.peerPhotoUrl!)
            : null,
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        child: conversation.peerPhotoUrl == null
            ? Text(
                conversation.peerDisplayName.isNotEmpty
                    ? conversation.peerDisplayName[0].toUpperCase()
                    : '?',
                style: theme.textTheme.titleMedium,
              )
            : null,
      ),
      title: Text(
        conversation.peerDisplayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyLarge?.copyWith(
          fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
        ),
      ),
      subtitle: _buildPreview(theme, scheme, conversation),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Text(
            conversation.lastMessageAt != null
                ? _formatTime(conversation.lastMessageAt!)
                : '',
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

  Widget _buildPreview(
      ThemeData theme, ColorScheme scheme, ManagedConversation conversation) {
    final String text = conversation.lastMessageText ?? '';
    if (text.isEmpty) return const SizedBox.shrink();
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    );
  }

  String _formatTime(DateTime time) {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime date = DateTime(time.year, time.month, time.day);
    final Duration diff = now.difference(time);
    if (diff.inDays == 0 && date == today) {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
    if (diff.inDays < 7) {
      return '${time.day}/${time.month}';
    }
    return '${time.day}/${time.month}/${time.year}';
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
          .select('uid, username, display_name, photo_url')
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
                hintText: 'Search contacts...',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onChanged: (String value) {
                final String q = value.toLowerCase();
                setState(() {
                  _results = _results.where((Map<String, dynamic> p) {
                    final String name = (p['display_name'] as String? ?? '').toLowerCase();
                    final String user = (p['username'] as String? ?? '').toLowerCase();
                    return name.contains(q) || user.contains(q);
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
                    return ListTile(
                      leading: CircleAvatar(
                        child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?'),
                      ),
                      title: Text(name),
                      subtitle: Text('@$user'),
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