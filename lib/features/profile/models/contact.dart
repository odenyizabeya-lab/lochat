import 'user_profile.dart';

/// A contact the signed-in user explicitly added.
///
/// Contacts are private and one-way: storing one here does not add the
/// signed-in user to the other person's contact list.
class Contact {
  const Contact({
    required this.uid,
    required this.profile,
    this.addedAt,
  });

  final String uid;

  /// Snapshot of the contact's public profile, refreshed from the live
  /// presence/user stream so display name, photo and presence stay current.
  final UserProfile profile;

  final DateTime? addedAt;
}
