/// Central place for app-wide constants.
abstract final class AppConstants {
  /// The public-facing name of the application.
  static const String appName = 'LoText';

  /// Short marketing tagline shown across onboarding screens.
  static const String tagline = 'Fast, private messaging made simple.';

  /// Current app version, mirrored from pubspec.yaml.
  static const String version = '1.0.0';

  /// The permanent admin email. Logging in with this address always lands
  /// on the Admin dashboard, and this account can manage the admin email and
  /// password from inside the Admin dashboard.
  static const String adminEmail = 'odenyizabeya@gmail.com';
}
