import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;

import '../models/contact.dart';
import '../models/user_profile.dart';
import 'lotext_id_generator.dart';
import 'profile_repository.dart';

/// Production [ProfileRepository] backed by Supabase (Postgres + Storage).
///
/// Uniqueness strategy: usernames live in a dedicated `usernames` registry and
/// LoText IDs in a `lotext_ids` registry, both with unique constraints. Claims
/// go through SECURITY DEFINER RPCs ([claimUsername] and [ensureLotextId]) so
/// the verify-and-register step is atomic. Contacts are stored one-way in
/// `contacts` so they stay private to the owner.
class SupabaseProfileRepository implements ProfileRepository {
  SupabaseProfileRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Stream<UserProfile?> watchProfile(String uid) {
    return _client
        .from('profiles')
        .stream(primaryKey: ['uid'])
        .eq('uid', uid)
        .map((List<Map<String, dynamic>> rows) =>
            rows.isEmpty ? null : _toProfile(rows.first));
  }

  @override
  Future<UserProfile?> fetchProfile(String uid) async {
    final List<Map<String, dynamic>> rows = await _client
        .from('profiles')
        .select()
        .eq('uid', uid)
        .limit(1);
    return rows.isEmpty ? null : _toProfile(rows.first);
  }

  @override
  Future<bool> isUsernameAvailable(String username) async {
    final String name = normalize(username);
    final res = await _client
        .from('usernames')
        .select('username')
        .eq('username', name)
        .count(CountOption.exact);
    return res.count == 0;
  }

  @override
  Future<void> claimUsername({
    required String uid,
    required String newUsername,
    required String oldUsername,
  }) async {
    try {
      await _client.rpc('claim_username', params: <String, dynamic>{
        'p_uid': uid,
        'p_new_username': newUsername,
        'p_old_username': oldUsername,
      });
    } on PostgrestException catch (e) {
      if (e.message.contains('USERNAME_UNAVAILABLE')) {
        throw const UsernameUnavailableException();
      }
      rethrow;
    }
  }

  @override
  Future<void> updateDisplayName({
    required String uid,
    required String displayName,
  }) async {
    await _client.from('profiles').update(<String, dynamic>{
      'display_name': displayName.trim(),
    }).eq('uid', uid);
  }

  @override
  Future<String> uploadProfilePhoto({
    required String uid,
    required Uint8List bytes,
  }) async {
    await _client.storage.from('profile_photos').uploadBinary(
          uid,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: true,
          ),
        );
    return _client.storage.from('profile_photos').getPublicUrl(uid);
  }

  @override
  Future<void> updatePhotoURL({
    required String uid,
    required String photoURL,
  }) async {
    await _client.from('profiles').update(<String, dynamic>{
      'photo_url': photoURL,
    }).eq('uid', uid);
  }

  @override
  Future<void> removeProfilePhoto({required String uid}) async {
    await _client.storage.from('profile_photos').remove(<String>[uid]);
    await _client.from('profiles').update(<String, dynamic>{
      'photo_url': '',
    }).eq('uid', uid);
  }

  @override
  Future<void> setPresence({
    required String uid,
    required bool online,
  }) async {
    final Map<String, dynamic> data = <String, dynamic>{
      'is_online': online,
    };
    if (!online) {
      data['last_seen'] = DateTime.now().toUtc().toIso8601String();
    }
    final List<Map<String, dynamic>> updated = await _client
        .from('profiles')
        .update(data)
        .eq('uid', uid)
        .select();
    if (updated.isEmpty) {
      // Profile row may not exist yet (trigger race at sign-up).
      await _client.from('profiles').upsert(<String, dynamic>{
        'uid': uid,
        ...data,
      }, onConflict: 'uid');
    }
  }

  @override
  Future<String> ensureLotextId({required String uid}) async {
    final dynamic result = await _client.rpc('ensure_lotext_id', params: <String, dynamic>{
      'p_uid': uid,
    });
    return result?.toString() ?? '';
  }

  @override
  Future<bool> claimOwnerAdmin({required String uid}) async {
    final dynamic result = await _client.rpc('claim_owner_admin');
    return result == true;
  }

  @override
  Future<UserProfile?> fetchUserByLotextId(String lotextId) async {
    final String id = lotextId.trim();
    if (!isValidLotextId(id)) return null;
    final List<Map<String, dynamic>> rows = await _client
        .from('lotext_ids')
        .select('uid')
        .eq('id', id)
        .limit(1);
    if (rows.isEmpty) return null;
    return fetchProfile(rows.first['uid'] as String);
  }

  @override
  Future<UserProfile?> fetchUserByUsername(String username) async {
    final String name = normalize(username);
    if (name.isEmpty) return null;
    final List<Map<String, dynamic>> rows = await _client
        .from('usernames')
        .select('uid')
        .eq('username', name)
        .limit(1);
    if (rows.isEmpty) return null;
    return fetchProfile(rows.first['uid'] as String);
  }

  @override
  Future<bool> isContact({
    required String ownerUid,
    required String contactUid,
  }) async {
    final List<Map<String, dynamic>> rows = await _client
        .from('contacts')
        .select('owner_uid')
        .eq('owner_uid', ownerUid)
        .eq('contact_uid', contactUid)
        .limit(1);
    return rows.isNotEmpty;
  }

  @override
  Future<void> addContact({
    required String ownerUid,
    required String contactUid,
  }) async {
    await _client.from('contacts').upsert(<String, dynamic>{
      'owner_uid': ownerUid,
      'contact_uid': contactUid,
    }, onConflict: 'owner_uid,contact_uid');
  }

  @override
  Future<void> removeContact({
    required String ownerUid,
    required String contactUid,
  }) async {
    await _client
        .from('contacts')
        .delete()
        .eq('owner_uid', ownerUid)
        .eq('contact_uid', contactUid);
  }

  @override
  Stream<List<Contact>> watchContacts(String ownerUid) {
    return _client
        .from('contacts')
        .stream(primaryKey: ['owner_uid', 'contact_uid'])
        .eq('owner_uid', ownerUid)
        .asyncMap((List<Map<String, dynamic>> rows) async {
      final List<Contact> result = <Contact>[];
      for (final Map<String, dynamic> row in rows) {
        final String uid = row['contact_uid'] as String;
        final UserProfile? profile = await fetchProfile(uid);
        if (profile == null) continue;
        result.add(Contact(
          uid: uid,
          profile: profile,
          addedAt: _toDate(row['added_at']),
        ));
      }
      result.sort((Contact a, Contact b) {
        final DateTime? at = a.addedAt;
        final DateTime? bt = b.addedAt;
        if (at == null && bt == null) return 0;
        if (at == null) return 1;
        if (bt == null) return -1;
        return bt.compareTo(at);
      });
      return result;
    });
  }

  String normalize(String value) {
    String s = value.trim().toLowerCase();
    if (s.startsWith('@')) s = s.substring(1);
    return s;
  }

  UserProfile _toProfile(Map<String, dynamic> data) {
    return UserProfile(
      uid: (data['uid'] as String?) ?? '',
      username: (data['username'] as String?) ?? '',
      displayName: (data['display_name'] as String?) ?? '',
      lotextId: _nullIfEmpty(data['lotext_id'] as String?),
      photoURL: _nullIfEmpty(data['photo_url'] as String?),
      isOnline: (data['is_online'] as bool?) ?? false,
      isAdmin: (data['is_admin'] as bool?) ?? false,
      lastSeen: _toDate(data['last_seen']),
      createdAt: _toDate(data['created_at']),
      updatedAt: _toDate(data['updated_at']),
    );
  }

  String? _nullIfEmpty(String? value) =>
      (value == null || value.isEmpty) ? null : value;

  DateTime? _toDate(Object? value) {
    if (value is String) {
      final DateTime? parsed = DateTime.tryParse(value);
      return parsed?.toLocal();
    }
    return null;
  }
}
