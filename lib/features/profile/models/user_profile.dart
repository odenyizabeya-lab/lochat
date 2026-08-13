/// A LoText user's public profile.
///
/// Public by design: it contains only information that is safe to show to
/// other signed-in users (username, display name, photo, presence). Email and
/// other private account data are intentionally not part of this model.
class UserProfile {
  const UserProfile({
    required this.uid,
    required this.username,
    required this.displayName,
    this.lotextId,
    this.photoURL,
    this.isOnline = false,
    this.lastSeen,
    this.createdAt,
    this.updatedAt,
  });

  final String uid;

  /// Canonical, always-lowercase username (e.g. `jerry`).
  final String username;

  /// Unique 9-digit LoText ID (e.g. `728491630`), safe to share.
  ///
  /// Assigned when the account is created; older accounts are back-filled with
  /// a generated ID the first time they are loaded.
  final String? lotextId;

  /// Name shown to other users (may contain spaces and capitals).
  final String displayName;

  /// Supabase Storage download URL, or null when no photo is set.
  final String? photoURL;

  final bool isOnline;
  final DateTime? lastSeen;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// "@username" handle, or empty when no username is claimed yet.
  String get handle => username.isEmpty ? '' : '@$username';

  bool get hasPhoto => photoURL != null && photoURL!.isNotEmpty;

  UserProfile copyWith({
    String? username,
    String? displayName,
    String? lotextId,
    String? photoURL,
    bool? isOnline,
    DateTime? lastSeen,
    DateTime? updatedAt,
  }) {
    return UserProfile(
      uid: uid,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      lotextId: lotextId ?? this.lotextId,
      photoURL: photoURL ?? this.photoURL,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Copies the profile but clears `photoURL` (used when a photo is removed).
  /// Built explicitly because [copyWith] cannot distinguish "not passed" from
  /// "explicitly null".
  UserProfile withNoPhoto() {
    return UserProfile(
      uid: uid,
      username: username,
      displayName: displayName,
      lotextId: lotextId,
      photoURL: null,
      isOnline: isOnline,
      lastSeen: lastSeen,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
