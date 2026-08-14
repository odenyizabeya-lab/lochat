import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/contact_picker_sheet.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../calls/call_controller.dart';
import '../../calls/call_scope.dart';
import '../../calls/models/call.dart';
import '../../chat/chat_controller.dart';
import '../../chat/chat_scope.dart';
import '../../chat/data/chat_repository.dart' show NotAContactException;
import '../../chat/models/conversation.dart';
import '../../profile/models/user_profile.dart';
import '../../profile/profile_scope.dart';

/// Tools tab: a hub for the signed-in user's profile, messaging actions and
/// settings.
///
/// A "Last 7 days performance" strip computes real numbers from the user's own
/// conversations and call history (no fabricated stats). Profile and Contacts
/// are pushed screens (not tabs), so this hub is the single entry point for
/// them. Admin-only entries (LoText AI and the admin dashboard) are only shown
/// to admins — never to regular users.
class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});

  Future<void> _startNewChat(BuildContext context) async {
    final UserProfile? peer = await showContactPicker(context);
    if (peer == null || !context.mounted) return;
    try {
      final ChatController chat = ChatScope.of(context);
      final String conversationId = await chat.openConversation(peer.uid);
      if (!context.mounted) return;
      await context.push(AppRoutes.chatFor(conversationId));
    } on NotAContactException {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add them as a contact to chat.')),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the chat. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final UserProfile? profile = ProfileScope.maybeOf(context)?.profile;
    final bool isAdmin = profile?.isAdmin ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tools'),
        actions: <Widget>[
          PopupMenuButton<String>(
            tooltip: 'More options',
            onSelected: (String value) {
              switch (value) {
                case 'profile':
                  context.push(AppRoutes.profile);
                case 'contacts':
                  context.push(AppRoutes.contacts);
                case 'add-contact':
                  context.push(AppRoutes.addContact);
                case 'settings':
                  context.push(AppRoutes.settings);
              }
            },
            itemBuilder: (BuildContext context) =>
                <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'profile',
                child: _MenuRow(
                  icon: Icons.person_outline_rounded,
                  label: 'Profile',
                ),
              ),
              const PopupMenuItem<String>(
                value: 'contacts',
                child: _MenuRow(
                  icon: Icons.contacts_outlined,
                  label: 'Contacts',
                ),
              ),
              const PopupMenuItem<String>(
                value: 'add-contact',
                child: _MenuRow(
                  icon: Icons.person_add_alt_1_rounded,
                  label: 'Add contact',
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
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: <Widget>[
            if (profile != null)
              _ProfileSummaryCard(
                profile: profile,
                onTap: () => context.push(AppRoutes.profile),
              ),
            _SectionHeader(
              theme: theme,
              scheme: scheme,
              label: 'LAST 7 DAYS PERFORMANCE',
            ),
            const _PerformanceStats(),
            _SectionHeader(theme: theme, scheme: scheme, label: 'MESSAGING'),
            ListTile(
              leading: Icon(Icons.chat_bubble_outline_rounded, color: scheme.primary),
              title: const Text('New chat'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => unawaited(_startNewChat(context)),
            ),
            ListTile(
              leading: Icon(Icons.contacts_outlined, color: scheme.primary),
              title: const Text('Contacts'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push(AppRoutes.contacts),
            ),
            ListTile(
              leading: Icon(Icons.person_add_alt_1_rounded, color: scheme.primary),
              title: const Text('Add contact'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push(AppRoutes.addContact),
            ),
            _SectionHeader(theme: theme, scheme: scheme, label: 'PROFILE'),
            ListTile(
              leading: Icon(Icons.person_outline_rounded, color: scheme.primary),
              title: const Text('Profile'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push(AppRoutes.profile),
            ),
            ListTile(
              leading: Icon(Icons.badge_outlined, color: scheme.primary),
              title: const Text('Edit profile'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.go(AppRoutes.editProfile),
            ),
            _SectionHeader(theme: theme, scheme: scheme, label: 'SETTINGS'),
            ListTile(
              leading: Icon(Icons.settings_outlined, color: scheme.primary),
              title: const Text('Settings'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push(AppRoutes.settings),
            ),
            if (isAdmin) ...<Widget>[
              _SectionHeader(theme: theme, scheme: scheme, label: 'ADMIN'),
              ListTile(
                leading:
                    Icon(Icons.auto_awesome_rounded, color: scheme.primary),
                title: const Text('LoText AI'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(AppRoutes.ai),
              ),
              ListTile(
                leading: Icon(
                  Icons.admin_panel_settings_outlined,
                  color: scheme.primary,
                ),
                title: const Text('Admin dashboard'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(AppRoutes.adminSettings),
              ),
            ],
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Profile, contacts and settings are also available in the '
                'overflow menu above.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact profile card at the top of the Tools hub.
class _ProfileSummaryCard extends StatelessWidget {
  const _ProfileSummaryCard({required this.profile, required this.onTap});

  final UserProfile profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final String displayName = profile.displayName.isNotEmpty
        ? profile.displayName
        : profile.username;

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: UserAvatar(
          name: displayName,
          photoURL: profile.photoURL,
          size: 56,
        ),
        title: Text(
          displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          profile.handle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.primary,
          ),
        ),
        trailing: Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
        onTap: onTap,
      ),
    );
  }
}

/// "Last 7 days performance" strip. Every number is derived from the signed-in
/// user's own conversations and call history — never fabricated.
class _PerformanceStats extends StatefulWidget {
  const _PerformanceStats();

  @override
  State<_PerformanceStats> createState() => _PerformanceStatsState();
}

class _PerformanceStatsState extends State<_PerformanceStats> {
  List<Conversation> _conversations = const <Conversation>[];
  List<Call> _calls = const <Call>[];
  StreamSubscription<List<Conversation>>? _convSub;
  StreamSubscription<void>? _callChangesSub;
  String? _uid;
  bool _subscribed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Inherited scopes can only be resolved here (not in initState).
    if (_subscribed) return;
    _subscribed = true;
    _uid = ChatScope.maybeOf(context)?.uid;
    _convSub = ChatScope.maybeOf(context)
        ?.watchConversations()
        .listen((List<Conversation> list) {
      if (mounted) setState(() => _conversations = list);
    });
    final CallController? calls = CallScope.maybeOf(context);
    final String? uid = _uid;
    if (calls != null && uid != null) {
      _callChangesSub = calls.signaling
          .watchCallChanges(uid: uid)
          .listen((_) => _loadCalls(calls, uid));
      _loadCalls(calls, uid);
    }
  }

  Future<void> _loadCalls(CallController calls, String uid) async {
    try {
      final List<Call> list = await calls.signaling.fetchCallHistory(uid: uid);
      if (mounted) setState(() => _calls = list);
    } on Exception {
      // Stats stay at their last known values on a fetch failure.
    }
  }

  @override
  void dispose() {
    _convSub?.cancel();
    _callChangesSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final DateTime weekAgo =
        DateTime.now().subtract(const Duration(days: 7));

    int activeChats = 0;
    int unread = 0;
    for (final Conversation conversation in _conversations) {
      final DateTime? lastAt = conversation.lastMessageAt;
      if (lastAt != null && lastAt.isAfter(weekAgo)) activeChats++;
      unread += conversation.unreadCount;
    }

    final String me = _uid ?? '';
    int calls7d = 0;
    int missed7d = 0;
    for (final Call call in _calls) {
      if (!call.createdAt.isAfter(weekAgo)) continue;
      calls7d++;
      if (call.status == CallStatus.missed ||
          (call.status == CallStatus.declined && call.calleeUid == me)) {
        missed7d++;
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 2.6,
        children: <Widget>[
          _StatTile(
            icon: Icons.forum_outlined,
            iconColor: scheme.primary,
            value: '$activeChats',
            label: 'Active chats',
          ),
          _StatTile(
            icon: Icons.mark_chat_unread_outlined,
            iconColor: AppColors.live,
            value: '$unread',
            label: 'Unread',
          ),
          _StatTile(
            icon: Icons.call_outlined,
            iconColor: scheme.primary,
            value: '$calls7d',
            label: 'Calls',
          ),
          _StatTile(
            icon: Icons.call_missed_outlined,
            iconColor: scheme.error,
            value: '$missed7d',
            label: 'Missed',
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 22, color: iconColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  value,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.theme,
    required this.scheme,
    required this.label,
  });

  final ThemeData theme;
  final ColorScheme scheme;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
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
