import 'package:supabase_flutter/supabase_flutter.dart';

/// Thrown when sign-up succeeds but email confirmation is enabled, so the
/// account is not usable until the user confirms their email address.
class AuthEmailConfirmationRequired implements Exception {
  const AuthEmailConfirmationRequired();
}

/// Maps thrown authentication errors to safe, user-friendly messages.
///
/// Only generic messages are ever shown to the user; no raw error text or
/// technical details are exposed.
abstract final class AuthErrors {
  static String message(Object error) {
    if (error is AuthEmailConfirmationRequired) {
      return 'Check your email to confirm your account, then sign in.';
    }
    if (error is AuthException) {
      return _mapAuthException(error);
    }
    return 'Something went wrong. Please try again.';
  }

  static String _mapAuthException(AuthException error) {
    final String code = (error.code ?? '').toLowerCase();
    final String text = error.message.toLowerCase();
    final List<String> parts = <String>[code, text];

    bool matches(List<String> tokens) => tokens.every((String token) =>
        parts.any((String part) => part.contains(token)));

    if (matches(<String>['invalid_credentials']) ||
        matches(<String>['invalid', 'login', 'credentials']) ||
        matches(<String>['wrong_password']) ||
        matches(<String>['incorrect', 'password'])) {
      return 'Incorrect email or password.';
    }
    if (matches(<String>['email_not_confirmed']) ||
        matches(<String>['email', 'not', 'confirmed'])) {
      return 'Confirm your email address before signing in.';
    }
    if (matches(<String>['email_exists']) ||
        matches(<String>['user', 'already', 'registered']) ||
        matches(<String>['already', 'been', 'registered'])) {
      return 'An account already exists with that email. Try logging in.';
    }
    if (matches(<String>['weak_password']) ||
        matches(<String>['password', 'should', 'be', 'at', 'least'])) {
      return 'Your password is too weak. Use at least 6 characters.';
    }
    if (matches(<String>['validation_failed']) ||
        matches(<String>['invalid', 'email']) ||
        matches(<String>['validate', 'email'])) {
      return 'That email address looks invalid.';
    }
    if (matches(<String>['over_request_rate_limit']) ||
        matches(<String>['over_email_send_rate_limit']) ||
        matches(<String>['rate', 'limit']) ||
        matches(<String>['too', 'many', 'requests']) ||
        matches(<String>['too', 'many', 'email', 'attempts'])) {
      return 'Too many attempts. Please try again later.';
    }
    if (matches(<String>['signup_disabled']) ||
        matches(<String>['signups', 'not', 'allowed'])) {
      return 'Email and password sign-in is not enabled for this app yet.';
    }
    if (matches(<String>['user_not_found'])) {
      return 'Incorrect email or password.';
    }
    if (matches(<String>['retryable']) ||
        matches(<String>['connection']) ||
        matches(<String>['network'])) {
      return 'No internet connection. Please check and try again.';
    }
    return 'Something went wrong. Please try again.';
  }
}
