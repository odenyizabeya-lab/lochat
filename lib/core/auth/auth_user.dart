/// An authenticated user as seen by the rest of the app.
///
/// A thin, platform-independent model that screens depend on instead of
/// reaching into the Supabase SDK directly.
class AuthUser {
  const AuthUser({
    required this.uid,
    this.email,
    this.displayName,
    this.photoURL,
    this.isEmailVerified = false,
  });

  final String uid;
  final String? email;
  final String? displayName;
  final String? photoURL;

  /// Whether the email has been verified. LoText does not require this.
  final bool isEmailVerified;
}
