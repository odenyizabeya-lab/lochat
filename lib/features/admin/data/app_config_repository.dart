/// Reads and writes LoText app configuration (AI provider keys).
///
/// Rows live in the `app_config` table and are protected by RLS: only users
/// flagged as admins (`profiles.is_admin`) can read or write anything here.
/// The `ai-assistant` edge function reads the same values with the service
/// role as a fallback when no environment secret is set.
abstract class AppConfigRepository {
  /// Whether the signed-in user is an admin.
  Future<bool> isAdmin();

  /// All stored config entries, keyed by their config key.
  Future<Map<String, String>> fetchAll();

  /// Creates or replaces a single config entry.
  Future<void> setValue(String key, String value);

  /// Deletes a config entry (a no-op when it does not exist).
  Future<void> remove(String key);
}
