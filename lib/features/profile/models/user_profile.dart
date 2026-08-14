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
    this.isAdmin = false,
    this.preferredLang,
    this.autoTranslate = true,
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

  /// Whether this user may manage app configuration (AI provider keys).
  final bool isAdmin;

  /// ISO 639-1-ish language code (e.g. `en`, `fr`, `zh-CN`) the user prefers
  /// to read and write in. Incoming messages are auto-translated into this
  /// language; sent messages are stamped with it so the peer knows whether a
  /// translation is needed. Null until the user picks one (the app seeds it
  /// from the device locale).
  final String? preferredLang;

  /// Whether the app should auto-translate incoming messages written in a
  /// different language into [preferredLang]. Defaults to on.
  final bool autoTranslate;

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
    bool? isAdmin,
    String? preferredLang,
    bool? autoTranslate,
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
      isAdmin: isAdmin ?? this.isAdmin,
      preferredLang: preferredLang ?? this.preferredLang,
      autoTranslate: autoTranslate ?? this.autoTranslate,
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
      isAdmin: isAdmin,
      preferredLang: preferredLang,
      autoTranslate: autoTranslate,
      lastSeen: lastSeen,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
