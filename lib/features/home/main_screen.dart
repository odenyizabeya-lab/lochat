import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../chat/chat_scope.dart';
import '../chat/models/conversation.dart';

/// Hosts the four authenticated tabs (Chats / Calls / Updates / Tools) in a
/// bottom navigation bar backed by a [StatefulNavigationShell].
///
/// Detail screens (a chat, a profile, the AI assistant, ...) are pushed on top
/// of the shell and hide the bar, exactly like a native messaging app.
class MainScreen extends StatelessWidget {
  const MainScreen({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (int index) {
          navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          );
        },
        destinations: <NavigationDestination>[
          const NavigationDestination(
            icon: _UnreadBadge(icon: Icon(Icons.chat_bubble_outline_rounded)),
            selectedIcon: _UnreadBadge(icon: Icon(Icons.chat_bubble_rounded)),
            label: 'Chats',
          ),
          const NavigationDestination(
            icon: Icon(Icons.call_outlined),
            selectedIcon: Icon(Icons.call_rounded),
            label: 'Calls',
          ),
          const NavigationDestination(
            icon: Icon(Icons.donut_large_outlined),
            selectedIcon: Icon(Icons.donut_large_rounded),
            label: 'Updates',
          ),
          const NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view_rounded),
            label: 'Tools',
          ),
        ],
      ),
    );
  }
}

/// Unread total for the Chats tab badge, summed across all conversations.
class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.icon});

  final Widget icon;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Conversation>>(
      stream: ChatScope.of(context).watchConversations(),
      builder: (BuildContext context, AsyncSnapshot<List<Conversation>> snapshot) {
        final List<Conversation> conversations =
            snapshot.data ?? const <Conversation>[];
        final int unread = conversations.fold<int>(
          0,
          (int sum, Conversation c) => sum + c.unreadCount,
        );
        if (unread <= 0) return icon;
        return Badge(
          label: Text(unread > 99 ? '99+' : '$unread'),
          child: icon,
        );
      },
    );
  }
}
