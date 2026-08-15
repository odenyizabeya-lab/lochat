import 'dart:async';

import 'package:flutter/foundation.dart';

import '../constants/app_constants.dart';
import 'auth_service.dart';
import 'auth_user.dart';
import 'supabase_auth_service.dart';

/// App-wide authentication state.
///
/// Tracks the current [AuthUser], exposes whether the initial auth state has
/// been resolved, and delegates all operations to an [AuthService]. The app
/// router listens to this controller to redirect users based on sign-in state.
class AuthController extends ChangeNotifier {
  AuthController({AuthService? service})
    : _service = service ?? SupabaseAuthService() {
    _subscription = _service.authStateChanges.listen(
      _onAuthStateChanged,
      onError: (Object error, StackTrace stackTrace) {
        // GoTrue adds a stream error when a token refresh hits a transient
        // network failure. Without a handler the subscription is torn down
        // and the app stops reacting to later auth events (e.g. sign-out or
        // a successful refresh). Swallow it so the stream keeps flowing.
        debugPrint('authStateChanges stream error: $error');
      },
    );
  }

  final AuthService _service;
  StreamSubscription<AuthUser?>? _subscription;

  AuthUser? _user;
  bool _initialized = false;
  bool _twoFactorPending = false;

  /// The currently authenticated user, or null when signed out.
  AuthUser? get currentUser => _user;

  /// Whether the initial authentication state has been resolved.
  ///
  /// While false, the router keeps the user on the splash screen.
  bool get isInitialized => _initialized;

  /// Whether the second verification step is outstanding. Set after the
  /// permanent admin email signs in with their password; cleared when the
  /// 2FA code is verified (or the user signs out). The router keeps the user
  /// on the two-factor screen while this is true.
  bool get twoFactorPending => _twoFactorPending;

  void _onAuthStateChanged(AuthUser? user) {
    _user = user;
    _initialized = true;
    if (user == null) {
      _twoFactorPending = false;
    }
    notifyListeners();
  }

  Future<void> createAccount({
    required String email,
    required String password,
  }) {
    return _service.createAccount(email: email, password: password);
  }

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    await _service.signInWithEmail(email: email, password: password);
    // Read the user from the service (not the stream) — the stream event is
    // delivered asynchronously and may not have arrived yet.
    final String? signedInEmail = _service.currentUser?.email;
    if (signedInEmail != null &&
        signedInEmail.toLowerCase() == AppConstants.adminEmail.toLowerCase()) {
      _twoFactorPending = true;
      notifyListeners();
    }
  }

  /// Marks the second verification step as complete (the code was verified).
  void completeTwoFactor() {
    if (!_twoFactorPending) return;
    _twoFactorPending = false;
    notifyListeners();
  }

  Future<bool> hasTotpFactor() => _service.hasTotpFactor();

  Future<TotpChallenge> startTotpChallenge({String? factorId}) {
    return _service.startTotpChallenge(factorId: factorId);
  }

  Future<void> verifyTotp({
    required String factorId,
    required String challengeId,
    required String code,
  }) {
    return _service.verifyTotp(
      factorId: factorId,
      challengeId: challengeId,
      code: code,
    );
  }

  Future<TotpEnrollment> enrollTotp() => _service.enrollTotp();

  Future<void> sendEmailCode({required String email}) {
    return _service.sendEmailCode(email: email);
  }

  Future<void> verifyEmailCode({
    required String email,
    required String code,
  }) {
    return _service.verifyEmailCode(email: email, code: code);
  }

  Future<void> sendPasswordReset({required String email}) {
    return _service.sendPasswordReset(email: email);
  }

  Future<void> updatePassword(String password) {
    return _service.updatePassword(password);
  }

  Future<void> updateEmail(String email) {
    return _service.updateEmail(email);
  }

  Future<void> signOut() => _service.signOut();

  Future<void> deleteAccount() => _service.deleteAccount();

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
