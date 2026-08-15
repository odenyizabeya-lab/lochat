import 'dart:async';

import 'package:flutter/foundation.dart';

import './models/managed_account.dart';
import './data/managed_account_repository.dart';
import './data/managed_chat_repository.dart';

class ManagedAccountController extends ChangeNotifier {
  ManagedAccountController({
    required this.accountRepository,
    required this.chatRepository,
    required String adminUid,
  }) : _adminUid = adminUid;

  final ManagedAccountRepository accountRepository;
  final ManagedChatRepository chatRepository;
  String _adminUid;

  List<ManagedAccount> _accounts = const <ManagedAccount>[];
  ManagedAccount? _selectedAccount;
  bool _loading = true;
  Object? _error;

  List<ManagedAccount> get accounts => List.unmodifiable(_accounts);
  ManagedAccount? get selectedAccount => _selectedAccount;
  bool get loading => _loading;
  bool get hasError => _error != null;
  Object? get error => _error;
  bool get hasSelectedAccount => _selectedAccount != null;
  bool get canAddMore => _accounts.length < 10;
  int get usedSlots => _accounts.length;
  int get maxSlots => 10;

  String get adminUid => _adminUid;

  void updateAdminUid(String adminUid) {
    if (_adminUid == adminUid) return;
    _adminUid = adminUid;
    _accounts = const <ManagedAccount>[];
    _selectedAccount = null;
    _loading = true;
    _error = null;
    notifyListeners();
    load();
  }

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _accounts = await accountRepository.watchAccounts(_adminUid).first;
      if (_selectedAccount != null) {
        final bool stillExists =
            _accounts.any((ManagedAccount a) => a.id == _selectedAccount!.id);
        if (!stillExists) {
          _selectedAccount = _accounts.isNotEmpty ? _accounts.first : null;
        }
      } else if (_accounts.isNotEmpty) {
        _selectedAccount = _accounts.first;
      }
      _loading = false;
    } on Exception catch (e) {
      _error = e;
      _loading = false;
    }
    notifyListeners();
  }

  Future<void> selectAccount(ManagedAccount account) async {
    if (_selectedAccount?.id == account.id) return;
    _selectedAccount = account;
    notifyListeners();
  }

  Future<void> selectAccountById(String accountId) async {
    final ManagedAccount? account =
        _accounts.where((ManagedAccount a) => a.id == accountId).firstOrNull;
    if (account != null) {
      await selectAccount(account);
    }
  }

  Future<ManagedAccount> createAccount({
    required int slotIndex,
    required String username,
    required String displayName,
    String? lotextId,
    String? photoUrl,
  }) async {
    if (_accounts.length >= 10) {
      throw StateError('Maximum of 10 accounts reached.');
    }
    if (_accounts.any((ManagedAccount a) => a.slotIndex == slotIndex)) {
      throw StateError('Slot $slotIndex is already occupied.');
    }
    final ManagedAccount account = await accountRepository.createAccount(
      adminUid: _adminUid,
      slotIndex: slotIndex,
      username: username,
      displayName: displayName,
      lotextId: lotextId,
      photoUrl: photoUrl,
    );
    _accounts = List<ManagedAccount>.from(_accounts)..add(account);
    _accounts.sort((ManagedAccount a, ManagedAccount b) => a.slotIndex.compareTo(b.slotIndex));
    if (_selectedAccount == null) {
      _selectedAccount = account;
    }
    notifyListeners();
    return account;
  }

  Future<ManagedAccount> updateAccount(ManagedAccount account) async {
    final ManagedAccount updated = await accountRepository.updateAccount(account);
    _accounts = _accounts
        .map((ManagedAccount a) => a.id == updated.id ? updated : a)
        .toList();
    if (_selectedAccount?.id == updated.id) {
      _selectedAccount = updated;
    }
    notifyListeners();
    return updated;
  }

  Future<void> deleteAccount(String accountId) async {
    await accountRepository.deleteAccount(_adminUid, accountId);
    _accounts = _accounts.where((ManagedAccount a) => a.id != accountId).toList();
    if (_selectedAccount?.id == accountId) {
      _selectedAccount = _accounts.isNotEmpty ? _accounts.first : null;
    }
    notifyListeners();
  }

  Future<void> refresh() async {
    await load();
  }
}
