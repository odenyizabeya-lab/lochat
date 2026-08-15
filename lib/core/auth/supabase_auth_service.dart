import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;

import 'auth_errors.dart';
import 'auth_service.dart';
import 'auth_user.dart';

/// Production [AuthService] backed by Supabase Auth (GoTrue).
class SupabaseAuthService implements AuthService {
  SupabaseAuthService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  Stream<AuthUser?>? _stateStream;

  @override
  Stream<AuthUser?> get authStateChanges {
    return _stateStream ??= _client.auth.onAuthStateChange.map(
      (AuthState state) => _fromUser(state.session?.user),
    );
  }

  @override
  AuthUser? get currentUser => _fromUser(_client.auth.currentUser);

  @override
  Future<void> createAccount({
    required String email,
    required String password,
  }) async {
    final AuthResponse response = await _client.auth.signUp(
      email: email,
      password: password,
    );
    if (response.session == null) {
      // Email confirmation is enabled: the account exists but is not yet
      // usable. The auth stream will sign the user in after confirmation.
      throw const AuthEmailConfirmationRequired();
    }
  }

  @override
  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  @override
  Future<void> sendPasswordReset({required String email}) async {
    await _client.auth.resetPasswordForEmail(email);
  }

  @override
  Future<void> updatePassword(String password) async {
    await _client.auth.updateUser(UserAttributes(password: password));
  }

  @override
  Future<void> updateEmail(String email) async {
    // Supabase emails a confirmation link to the new address; the change only
    // takes effect once it is confirmed.
    await _client.auth.updateUser(UserAttributes(email: email));
  }

  @override
  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  @override
  Future<bool> hasTotpFactor() async {
    final AuthMFAListFactorsResponse factors = await _client.auth.mfa
        .listFactors();
    return factors.totp.isNotEmpty;
  }

  @override
  Future<TotpChallenge> startTotpChallenge({String? factorId}) async {
    String? id = factorId;
    if (id == null) {
      final AuthMFAListFactorsResponse factors = await _client.auth.mfa
          .listFactors();
      if (factors.totp.isEmpty) {
        throw const MfaFactorNotEnrolledException();
      }
      id = factors.totp.first.id;
    }
    final AuthMFAChallengeResponse challenge = await _client.auth.mfa
        .challenge(factorId: id);
    return TotpChallenge(factorId: id, challengeId: challenge.id);
  }

  @override
  Future<void> verifyTotp({
    required String factorId,
    required String challengeId,
    required String code,
  }) async {
    await _client.auth.mfa.verify(
      factorId: factorId,
      challengeId: challengeId,
      code: code,
    );
  }

  @override
  Future<TotpEnrollment> enrollTotp() async {
    final AuthMFAEnrollResponse enrollment = await _client.auth.mfa.enroll(
      factorType: FactorType.totp,
      issuer: 'LoText',
      friendlyName: 'Admin',
    );
    final String? secret = enrollment.totp?.secret;
    if (secret == null || secret.isEmpty) {
      throw const AuthException(
        'TOTP enrollment returned no secret.',
        code: 'mfa_enrollment_failed',
      );
    }
    return TotpEnrollment(factorId: enrollment.id, secret: secret);
  }

  @override
  Future<void> sendEmailCode({required String email}) async {
    await _client.auth.signInWithOtp(
      email: email,
      shouldCreateUser: false,
      emailRedirectTo: 'lotext://two-factor',
    );
  }

  @override
  Future<void> verifyEmailCode({
    required String email,
    required String code,
  }) async {
    await _client.auth.verifyOTP(
      email: email,
      token: code,
      type: OtpType.email,
    );
  }

  @override
  Future<void> deleteAccount() async {
    // The delete-account edge function resolves the caller from the current
    // JWT and permanently deletes the user (and all their data) with the
    // service role. See supabase/functions/delete-account.
    await _client.functions.invoke('delete-account', body: <String, dynamic>{});
    // The user no longer exists on the server, so a global sign-out would 401.
    // Clear the local session so the app returns to the welcome screen.
    await _client.auth.signOut(scope: SignOutScope.local);
  }

  AuthUser? _fromUser(User? user) {
    if (user == null) return null;
    return AuthUser(
      uid: user.id,
      email: user.email,
      displayName: user.userMetadata?['display_name'] as String?,
      photoURL: user.userMetadata?['photo_url'] as String?,
      isEmailVerified: user.emailConfirmedAt != null,
    );
  }
}
