/// Build-time Supabase configuration.
///
/// The URL and publishable key are injected at build time through the
/// `--dart-define` flags below so no secrets are committed to the repository.
///
/// ```text
/// flutter run --dart-define=LOTEXT_SUPABASE_URL=https://project.supabase.co \
///             --dart-define=LOTEXT_SUPABASE_KEY=publishable-key
/// ```
abstract final class SupabaseConfig {
  static const String url = String.fromEnvironment('LOTEXT_SUPABASE_URL');

  static const String publishableKey =
      String.fromEnvironment('LOTEXT_SUPABASE_KEY');

  /// Whether both values were provided at build time.
  static bool get isConfigured => url.isNotEmpty && publishableKey.isNotEmpty;
}
