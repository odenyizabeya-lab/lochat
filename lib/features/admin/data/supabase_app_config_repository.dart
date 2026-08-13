import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config_repository.dart';

/// Production [AppConfigRepository] backed by the `app_config` table.
///
/// Admin checks go through the `is_admin()` security-definer RPC; reads and
/// writes are gated by RLS, so a non-admin user can never touch these rows even
/// if the screen is reached directly.
class SupabaseAppConfigRepository implements AppConfigRepository {
  SupabaseAppConfigRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Future<bool> isAdmin() async {
    final dynamic result = await _client.rpc('is_admin');
    return result == true;
  }

  @override
  Future<Map<String, String>> fetchAll() async {
    final List<Map<String, dynamic>> rows =
        await _client.from('app_config').select('key, value');
    return <String, String>{
      for (final Map<String, dynamic> row in rows)
        row['key'] as String: row['value'] as String,
    };
  }

  @override
  Future<void> setValue(String key, String value) async {
    await _client.from('app_config').upsert(<String, dynamic>{
      'key': key,
      'value': value,
      'updated_by': _client.auth.currentUser?.id,
    }, onConflict: 'key');
  }

  @override
  Future<void> remove(String key) async {
    await _client.from('app_config').delete().eq('key', key);
  }
}
