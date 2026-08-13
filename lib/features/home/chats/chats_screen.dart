import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/utils/time_utils.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/lotext_button.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../chat/chat_scope.dart';
import '../../chat/models/conversation.dart';
import '../../profile/models/user_profile.dart';

/// Chats tab: all of the signed-in user's conversations, most recent first.
/// Each row shows the peer, a preview of the last message, its time, and an
/// unread badge. Tapping a row opens the conversation. A call-history card
/// sits above the list.
class ChatsScreen extends StatelessWidget {
  const ChatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Chats')),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _CallsCard(theme: theme, scheme: scheme),
            Expanded(
              child: StreamBuilder<List<Conversation>>(
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
                    return _buildEmpty(context, theme, scheme);
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: conversations.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, indent: 88),
                    itemBuilder: (BuildContext context, int index) =>
                        _buildTile(
                      context,
                      theme,
                      scheme,
                      conversations[index],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(
    BuildContext context,
    ThemeData theme,
    ColorScheme scheme,
  ) {
    return EmptyStateView(
      icon: Icons.chat_bubble_outline_rounded,
      title: 'No conversations yet',
      message:
          'Start a chat with one of your contacts to see it here. Messages '
          'are private to you and the person you chat with.',
      action: LoTextButton(
        label: 'Browse contacts',
        icon: Icons.contacts_outlined,
        isExpanded: true,
        onPressed: () => context.go(AppRoutes.contacts),
      ),
    );
  }

  Widget _buildTile(
    BuildContext context,
    ThemeData theme,
    ColorScheme scheme,
    Conversation conversation,
  ) {
    final UserProfile peer = conversation.peer;
    final String displayName = peer.displayName.isNotEmpty
        ? peer.displayName
        : peer.username;
    final String myUid = ChatScope.of(context).uid ?? '';
    final String preview = conversation.hasLastMessage
        ? (conversation.lastSentBy(myUid)
            ? 'You: ${conversation.lastMessageText}'
            : conversation.lastMessageText)
        : 'Say hello';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: UserAvatar(name: displayName, photoURL: peer.photoURL, size: 52),
      title: Text(
        displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        preview,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: conversation.unreadCount > 0
              ? scheme.onSurface
              : scheme.onSurfaceVariant,
          fontWeight: conversation.unreadCount > 0
              ? FontWeight.w600
              : FontWeight.w400,
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Text(
            formatChatTime(conversation.lastMessageAt),
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (conversation.unreadCount > 0) ...<Widget>[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              constraints: const BoxConstraints(minWidth: 22),
              child: Text(
                '${conversation.unreadCount}',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
      onTap: () => context.push(AppRoutes.chatFor(conversation.id)),
    );
  }
}

/// Compact entry card that opens the call-history screen.
class _CallsCard extends StatelessWidget {
  const _CallsCard({required this.theme, required this.scheme});

  final ThemeData theme;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Card(
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        child: InkWell(
          onTap: () => context.push(AppRoutes.callHistory),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: <Widget>[
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    Icons.phone_rounded,
                    color: scheme.onPrimaryContainer,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Calls',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Voice & video call history',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.arrow_forward_rounded,
                    color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
