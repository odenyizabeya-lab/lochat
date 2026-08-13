import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../shared/widgets/lotext_button.dart';
import '../../../shared/widgets/presence_indicator.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../profile/models/contact.dart';
import '../../profile/profile_scope.dart';

/// Contacts tab. Private by design: it only ever shows people the signed-in
/// user explicitly added. Each row shows the contact's live photo, display
/// name, @username and presence; tapping opens their public profile.
class ContactsScreen extends StatelessWidget {
  const ContactsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Contacts')),
      body: SafeArea(
        child: StreamBuilder<List<Contact>>(
          stream: ProfileScope.of(context).watchContacts(),
          builder: (BuildContext context, AsyncSnapshot<List<Contact>> snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Could not load your contacts.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
              );
            }

            final List<Contact> contacts = snapshot.data ?? const <Contact>[];
            if (contacts.isEmpty) {
              return _buildEmpty(context, theme, scheme);
            }
            return ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: contacts.length,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 88),
              itemBuilder: (BuildContext context, int index) {
                final Contact contact = contacts[index];
                return _buildContactTile(context, theme, scheme, contact);
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context, ThemeData theme, ColorScheme scheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.person_add_alt_1_rounded, size: 56, color: scheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              'No contacts yet',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Add people by their exact LoText ID or username. Your contacts '
              'are private and only you can see them.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            LoTextButton(
              label: 'Add contact',
              icon: Icons.person_add_alt_1_rounded,
              isExpanded: true,
              onPressed: () => context.push(AppRoutes.addContact),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactTile(
    BuildContext context,
    ThemeData theme,
    ColorScheme scheme,
    Contact contact,
  ) {
    final String displayName = contact.profile.displayName.isNotEmpty
        ? contact.profile.displayName
        : contact.profile.username;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      leading: UserAvatar(
        name: displayName,
        photoURL: contact.profile.photoURL,
        size: 48,
      ),
      title: Text(
        displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          children: <Widget>[
            Flexible(
              child: Text(
                contact.profile.handle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: 8),
            PresenceIndicator(
              isOnline: contact.profile.isOnline,
              lastSeen: contact.profile.lastSeen,
            ),
          ],
        ),
      ),
      onTap: () => context.push(AppRoutes.publicProfileFor(contact.uid)),
    );
  }
}
