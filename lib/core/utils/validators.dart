/// Input validators and normalizers used by the app's forms.
abstract final class Validators {
  static final RegExp _emailRegExp = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  static final RegExp _usernameRegExp = RegExp(r'^[a-z0-9_]{3,20}$');

  /// Normalizes a username: trims whitespace and lowercases it. Uniqueness is
  /// always enforced on the lowercased form.
  static String normalizeUsername(String value) => value.trim().toLowerCase();

  /// Validates a LoText username (3-20 chars, lowercase letters, numbers,
  /// underscores only; no spaces). Call AFTER [normalizeUsername].
  static String? username(String? value) {
    final String text = value?.trim() ?? '';
    if (text.isEmpty) {
      return 'Choose a username';
    }
    if (text.length < 3 || text.length > 20) {
      return 'Username must be 3-20 characters';
    }
    if (!_usernameRegExp.hasMatch(text)) {
      return 'Only letters, numbers, and underscores are allowed';
    }
    return null;
  }

  /// Validates a profile display name (may contain spaces; max 50 characters).
  static String? displayName(String? value) {
    final String trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return 'Enter a display name';
    }
    if (trimmed.length > 50) {
      return 'Display name must be 50 characters or fewer';
    }
    return null;
  }

  /// Validates an email address.
  static String? email(String? value) {
    final String trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return 'Enter your email address';
    }
    if (!_emailRegExp.hasMatch(trimmed)) {
      return 'Enter a valid email address';
    }
    return null;
  }

  /// Validates a password (minimum length).
  static String? password(String? value) {
    final String text = value ?? '';
    if (text.isEmpty) {
      return 'Enter a password';
    }
    if (text.length < 6) {
      return 'Password must be at least 6 characters';
    }
    return null;
  }

  /// Validates that a confirmation password matches the original.
  static String? confirmPassword(String? value, String password) {
    final String text = value ?? '';
    if (text.isEmpty) {
      return 'Re-enter your password';
    }
    if (text != password) {
      return 'Passwords do not match';
    }
    return null;
  }
}
