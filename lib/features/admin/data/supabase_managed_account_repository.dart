import 'dart:async';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/managed_account.dart';
import 'managed_account_repository.dart';

class SupabaseManagedAccountRepository implements ManagedAccountRepository {
  SupabaseManagedAccountRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Stream<List<ManagedAccount>> watchAccounts(String adminUid) {
    return _client
        .from('admin_managed_accounts')
        .stream(primaryKey: ['id'])
        .eq('admin_uid', adminUid)
        .order('slot_index', ascending: true)
        .map((List<Map<String, dynamic>> rows) => rows
            .map(_toAccount)
            .toList());
  }

  @override
  Future<ManagedAccount?> fetchAccount(String adminUid, String accountId) async {
    final List<Map<String, dynamic>> rows = await _client
        .from('admin_managed_accounts')
        .select()
        .eq('admin_uid', adminUid)
        .eq('id', accountId)
        .limit(1);
    if (rows.isEmpty) return null;
    return _toAccount(rows.first);
  }

  @override
  Future<ManagedAccount> createAccount({
    required String adminUid,
    required int slotIndex,
    required String username,
    required String displayName,
    String? lotextId,
    String? photoUrl,
    Map<String, dynamic>? settings,
  }) async {
    final Map<String, dynamic> data = <String, dynamic>{
      'admin_uid': adminUid,
      'slot_index': slotIndex,
      'username': username,
      'display_name': displayName,
    };
    if (lotextId != null && lotextId.isNotEmpty) {
      data['lotext_id'] = lotextId;
    }
    if (photoUrl != null && photoUrl.isNotEmpty) {
      data['photo_url'] = photoUrl;
    }
    if (settings != null) {
      data['settings'] = settings;
    }

    final List<Map<String, dynamic>> rows = await _client
        .from('admin_managed_accounts')
        .insert(data)
        .select()
        .limit(1);
    return _toAccount(rows.first);
  }

  @override
  Future<ManagedAccount> updateAccount(ManagedAccount account) async {
    final Map<String, dynamic> data = <String, dynamic>{
      'username': account.username,
      'display_name': account.displayName,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (account.lotextId != null) {
      data['lotext_id'] = account.lotextId;
    } else {
      data['lotext_id'] = null;
    }
    if (account.photoUrl != null) {
      data['photo_url'] = account.photoUrl;
    } else {
      data['photo_url'] = null;
    }
    data['settings'] = account.settings;

    final List<Map<String, dynamic>> rows = await _client
        .from('admin_managed_accounts')
        .update(data)
        .eq('id', account.id)
        .eq('admin_uid', account.adminUid)
        .select()
        .limit(1);
    return _toAccount(rows.first);
  }

  @override
  Future<void> deleteAccount(String adminUid, String accountId) async {
    await _client
        .from('admin_managed_accounts')
        .delete()
        .eq('admin_uid', adminUid)
        .eq('id', accountId);
  }

  Future<String> uploadProfilePhoto({
    required String managedAccountId,
    required Uint8List bytes,
  }) async {
    await _client.storage.from('managed_account_photos').uploadBinary(
          managedAccountId,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: true,
          ),
        );
    return managedAccountId;
  }

  ManagedAccount _toAccount(Map<String, dynamic> data) {
    return ManagedAccount(
      id: (data['id'] as String?) ?? '',
      adminUid: (data['admin_uid'] as String?) ?? '',
      slotIndex: (data['slot_index'] as int?) ?? 0,
      lotextId: _nullIfEmpty(data['lotext_id'] as String?),
      username: (data['username'] as String?) ?? '',
      displayName: (data['display_name'] as String?) ?? '',
      photoUrl: _nullIfEmpty(data['photo_url'] as String?),
      settings: (data['settings'] as Map<String, dynamic>?) ?? const <String, dynamic>{},
      createdAt: _toDate(data['created_at']) ?? DateTime.now(),
      updatedAt: _toDate(data['updated_at']) ?? DateTime.now(),
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
