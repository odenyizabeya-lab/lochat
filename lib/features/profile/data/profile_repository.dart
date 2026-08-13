import 'dart:typed_data';

import '../models/contact.dart';
import '../models/user_profile.dart';

/// Thrown when a username is claimed by another user. Never expose raw
/// exception text to the UI; screens map this to a friendly message.
class UsernameUnavailableException implements Exception {
  const UsernameUnavailableException();
}

/// Thrown when a LoText ID has already been allocated to another account.
class LotextIdTakenException implements Exception {
  const LotextIdTakenException();
}

/// Contract for profile data used by the app.
///
/// The UI depends only on this interface; the production implementation is
/// [SupabaseProfileRepository]. Tests may supply a fake implementation.
abstract interface class ProfileRepository {
  /// Real-time stream of a profile document.
  Stream<UserProfile?> watchProfile(String uid);

  /// One-shot read of a profile document (e.g. another user's public profile).
  Future<UserProfile?> fetchProfile(String uid);

  /// Whether the lowercase username is still free to claim.
  Future<bool> isUsernameAvailable(String username);

  /// Transactionally claims a username for the given user.
  ///
  /// Atomically: verifies the new username is free, registers it, releases the
  /// previous username (if any), and updates the user's profile. Throws
  /// [UsernameUnavailableException] when the name is already taken.
  Future<void> claimUsername({
    required String uid,
    required String newUsername,
    required String oldUsername,
  });

  Future<void> updateDisplayName({
    required String uid,
    required String displayName,
  });

  /// Uploads photo bytes for the user and returns the download URL.
  Future<String> uploadProfilePhoto({
    required String uid,
    required Uint8List bytes,
  });

  Future<void> updatePhotoURL({
    required String uid,
    required String photoURL,
  });

  Future<void> removeProfilePhoto({required String uid});

  /// Records a presence transition. Call only on meaningful transitions
  /// (app start/resume -> online, background/sign-out -> offline).
  Future<void> setPresence({
    required String uid,
    required bool online,
  });

  /// Ensures the user owns a LoText ID, generating and claiming one (in a
  /// transaction against the `lotextIds/{id}` registry) when missing. Returns
  /// the current ID. Used to back-fill accounts created before LoText IDs
  /// existed; new accounts get theirs from the account-creation function.
  Future<String> ensureLotextId({required String uid});

  /// Exact-match lookup by 9-digit LoText ID. Returns null when no account has
  /// that ID. Never returns partial or "similar" matches.
  Future<UserProfile?> fetchUserByLotextId(String lotextId);

  /// Exact-match lookup by canonical (trimmed, `@`-stripped, lowercase)
  /// username. Returns null when no account has that username.
  Future<UserProfile?> fetchUserByUsername(String username);

  /// Whether [contactUid] is already one of [ownerUid]'s contacts.
  Future<bool> isContact({
    required String ownerUid,
    required String contactUid,
  });

  /// Adds [contactUid] to [ownerUid]'s private contact list. Idempotent:
  /// adding an existing contact does not create a duplicate.
  Future<void> addContact({
    required String ownerUid,
    required String contactUid,
  });

  /// Removes [contactUid] from [ownerUid]'s private contact list.
  Future<void> removeContact({
    required String ownerUid,
    required String contactUid,
  });

  /// Real-time stream of [ownerUid]'s contacts (private, one-way). Emits an
  /// empty list while there are no contacts. The emitted profiles are live so
  /// presence and display names stay up to date.
  Stream<List<Contact>> watchContacts(String ownerUid);
}
