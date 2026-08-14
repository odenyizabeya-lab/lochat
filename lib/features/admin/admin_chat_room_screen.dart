import 'package:flutter/material.dart';

import '../home/chats/chats_screen.dart';

/// The admin dashboard's chat room.
///
/// Not a group: this is the admin's ordinary 1-to-1 conversation list, shown
/// inside the admin dashboard. Anyone who adds the admin by username or LoText
/// ID chats with them like any other contact — the chat list and screen are
/// exactly the normal ones.
class AdminChatRoomScreen extends StatelessWidget {
  const AdminChatRoomScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ChatsScreen(
      title: 'Chat Room',
    );
  }
}
