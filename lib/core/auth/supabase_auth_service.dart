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
  Future<void> signOut() async {
    await _client.auth.signOut();
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
