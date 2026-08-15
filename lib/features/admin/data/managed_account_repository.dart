import '../models/managed_account.dart';

abstract class ManagedAccountRepository {
  Stream<List<ManagedAccount>> watchAccounts(String adminUid);

  Future<ManagedAccount?> fetchAccount(String adminUid, String accountId);

  Future<ManagedAccount> createAccount({
    required String adminUid,
    required int slotIndex,
    required String username,
    required String displayName,
    String? lotextId,
    String? photoUrl,
    Map<String, dynamic>? settings,
  });

  Future<ManagedAccount> updateAccount(ManagedAccount account);

  Future<void> deleteAccount(String adminUid, String accountId);
}
