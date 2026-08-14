import 'package:flutter/material.dart';

import '../../../shared/widgets/empty_state_view.dart';

/// Archived conversations.
///
/// There is no archive feature yet, so this screen is an honest empty state —
/// it never invents archived items. When archiving is added, this screen can
/// list the archived conversations behind the same ChatScope.
class ArchivedConversationsScreen extends StatelessWidget {
  const ArchivedConversationsScreen({super.key, this.title = 'Archived'});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: const SafeArea(
        child: EmptyStateView(
          icon: Icons.archive_outlined,
          title: 'No archived conversations',
          message:
              'When you archive a conversation it will be moved here. '
              'Nothing has been archived yet.',
        ),
      ),
    );
  }
}
