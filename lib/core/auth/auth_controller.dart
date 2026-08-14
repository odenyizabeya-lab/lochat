import 'dart:async';

import 'package:flutter/foundation.dart';

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

  /// The currently authenticated user, or null when signed out.
  AuthUser? get currentUser => _user;

  /// Whether the initial authentication state has been resolved.
  ///
  /// While false, the router keeps the user on the splash screen.
  bool get isInitialized => _initialized;

  void _onAuthStateChanged(AuthUser? user) {
    _user = user;
    _initialized = true;
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
  }) {
    return _service.signInWithEmail(email: email, password: password);
  }

  Future<void> sendPasswordReset({required String email}) {
    return _service.sendPasswordReset(email: email);
  }

  Future<void> signOut() => _service.signOut();

  Future<void> deleteAccount() => _service.deleteAccount();

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
