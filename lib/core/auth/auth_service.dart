import 'auth_user.dart';

/// A TOTP challenge waiting for the user's authenticator-app code.
class TotpChallenge {
  const TotpChallenge({required this.factorId, required this.challengeId});

  final String factorId;
  final String challengeId;
}

/// A freshly enrolled TOTP factor. The admin adds [secret] to their
/// authenticator app, then verifies a code to activate the factor.
class TotpEnrollment {
  const TotpEnrollment({required this.factorId, required this.secret});

  final String factorId;
  final String secret;
}

/// Thrown when a TOTP challenge is requested but no factor is enrolled.
class MfaFactorNotEnrolledException implements Exception {
  const MfaFactorNotEnrolledException();
}

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

  /// Updates the current user's password (sign-in credentials).
  Future<void> updatePassword(String password);

  /// Updates the current user's email address. The new address typically
  /// receives a confirmation email before it becomes active.
  Future<void> updateEmail(String email);

  Future<void> signOut();

  /// Whether the current user has a verified TOTP authenticator factor.
  Future<bool> hasTotpFactor();

  /// Starts a TOTP challenge against the first verified factor, or against the
  /// factor [factorId] when supplied (used right after enrolling).
  ///
  /// Throws [MfaFactorNotEnrolledException] when there is nothing to challenge.
  Future<TotpChallenge> startTotpChallenge({String? factorId});

  /// Verifies a TOTP code against [challenge]. On success the session is
  /// upgraded to the authenticated-assurance level required for the admin
  /// dashboard.
  Future<void> verifyTotp({
    required String factorId,
    required String challengeId,
    required String code,
  });

  /// Enrolls a new TOTP factor and returns its secret for display.
  Future<TotpEnrollment> enrollTotp();

  /// Sends a 6-digit verification code to [email] by email (2FA step).
  Future<void> sendEmailCode({required String email});

  /// Verifies the emailed 2FA code and completes sign-in.
  Future<void> verifyEmailCode({required String email, required String code});

  /// Permanently deletes the current user's account and all of their data.
  ///
  /// Throws on failure, in which case the user stays signed in. On success the
  /// session is invalidated and the app returns to the welcome screen.
  Future<void> deleteAccount();
}
