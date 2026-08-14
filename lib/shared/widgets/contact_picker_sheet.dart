import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_routes.dart';
import '../../features/profile/models/contact.dart';
import '../../features/profile/models/user_profile.dart';
import '../../features/profile/profile_scope.dart';
import 'user_avatar.dart';

/// Shows a modal bottom sheet listing the signed-in user's contacts and
/// resolves to the picked [UserProfile], or null when dismissed.
///
/// Used by "New chat" and the Calls quick actions — both flows pick a person
/// from the user's own, private contact list (never a public directory).
Future<UserProfile?> showContactPicker(
  BuildContext context, {
  String title = 'New chat',
}) {
  return showModalBottomSheet<UserProfile>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext context) => _ContactPickerSheet(title: title),
  );
}

class _ContactPickerSheet extends StatelessWidget {
  const _ContactPickerSheet({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              child: StreamBuilder<List<Contact>>(
                stream: ProfileScope.of(context).watchContacts(),
                builder: (BuildContext context,
                    AsyncSnapshot<List<Contact>> snapshot) {
                  final List<Contact> contacts =
                      snapshot.data ?? const <Contact>[];
                  if (contacts.isEmpty) {
                    return _EmptyContacts(
                      theme: theme,
                      scheme: scheme,
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.only(bottom: 12),
                    itemCount: contacts.length,
                    itemBuilder: (BuildContext context, int index) {
                      final Contact contact = contacts[index];
                      final String name = contact.profile.displayName.isNotEmpty
                          ? contact.profile.displayName
                          : contact.profile.username;
                      return ListTile(
                        leading: UserAvatar(
                          name: name,
                          photoURL: contact.profile.photoURL,
                          size: 44,
                        ),
                        title: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          contact.profile.handle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        onTap: () => Navigator.of(context)
                            .pop(contact.profile),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyContacts extends StatelessWidget {
  const _EmptyContacts({required this.theme, required this.scheme});

  final ThemeData theme;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.person_add_alt_1_rounded,
              size: 44,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'No contacts yet',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Add people by their exact LoText ID or username first.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                context.push(AppRoutes.addContact);
              },
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Add contact'),
            ),
          ],
        ),
      ),
    );
  }
}
