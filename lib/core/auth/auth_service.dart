import 'auth_user.dart';

/// Contract for authentication used by the whole app.
///
/// The UI depends only on this interface; the production implementation is
/// [SupabaseAuthService]. Tests may supply a fake implementation.
abstract interface class AuthService {
  /// Emits the current user whenever the sign-in state changes.
  Stream<AuthUser?> get authStateChanges;

  /// The currently authenticated user, or null when signed out.
  AuthUser? get currentUser;

  /// Creates an account and signs the user in immediately.
  Future<void> createAccount({required String email, required String password});

  Future<void> signInWithEmail({
    required String email,
    required String password,
  });

  Future<void> sendPasswordReset({required String email});

  Future<void> signOut();

  /// Permanently deletes the current user's account and all of their data.
  ///
  /// Throws on failure, in which case the user stays signed in. On success the
  /// session is invalidated and the app returns to the welcome screen.
  Future<void> deleteAccount();
}
