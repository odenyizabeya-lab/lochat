import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../core/auth/auth_controller.dart';
import 'data/photo_picker.dart';
import 'data/profile_repository.dart';
import 'models/contact.dart';
import 'models/user_profile.dart';

/// App-wide state for the signed-in user's profile.
///
/// Follows the [AuthController]: when a user signs in, this starts watching
/// their Firestore profile; when they sign out, the profile is cleared and a
/// final offline presence is recorded. The router listens to this controller
/// to force new users through username setup.
class ProfileController extends ChangeNotifier {
  ProfileController({
    required this._auth,
    required this._repository,
    ProfilePhotoPicker? photoPicker,
  }) : _photoPicker = photoPicker ?? const DevicePhotoPicker() {
    _auth.addListener(_handleAuthChange);
    _handleAuthChange();
  }

  final AuthController _auth;
  final ProfileRepository _repository;
  final ProfilePhotoPicker _photoPicker;

  StreamSubscription<UserProfile?>? _profileSubscription;
  String? _loadedUid;

  /// Guards against duplicate LoText ID back-fill attempts in one session.
  String? _lotextIdBackfillUid;

  /// Guards against duplicate preferred-language back-fills in one session.
  String? _preferredLangBackfillUid;

  /// Cached per-session contacts stream so rebuilds reuse one subscription.
  Stream<List<Contact>>? _contactsStream;

  UserProfile? _profile;
  bool _isInitialized = false;
  bool _isLoading = false;
  Object? _error;

  UserProfile? get profile => _profile;

  /// Whether the profile status is known for the current auth state.
  bool get isInitialized => _isInitialized;

  bool get isLoading => _isLoading;
  bool get hasProfile => _profile != null;
  bool get hasUsername => _profile?.username.isNotEmpty ?? false;
  Object? get error => _error;

  Future<void> _handleAuthChange() async {
    final String? uid = _auth.currentUser?.uid;

    if (_loadedUid != null && _loadedUid != uid) {
      // Previous user left: record offline presence before switching.
      await _repository.setPresence(uid: _loadedUid!, online: false);
    }

    final bool refreshingSameUser =
        uid != null && uid == _loadedUid && _profile != null;
    if (refreshingSameUser) {
      // Same user re-notified (e.g. a token refresh): refresh the profile
      // watch quietly. Crucially, do NOT flip _isInitialized back to false,
      // otherwise the router redirects to the splash route and any screen on
      // top of the stack (like an active call) is popped.
      await _profileSubscription?.cancel();
      _profileSubscription = null;
      _subscribeToProfile(uid);
      return;
    }
    _loadedUid = uid;

    await _profileSubscription?.cancel();
    _profileSubscription = null;
    _contactsStream = null;

    if (uid == null) {
      _profile = null;
      _isInitialized = true;
      _isLoading = false;
      _error = null;
      notifyListeners();
      return;
    }

    _profile = null;
    _isInitialized = false;
    _isLoading = true;
    _error = null;
    notifyListeners();

    _subscribeToProfile(uid);

    unawaited(_repository.setPresence(uid: uid, online: true));
  }

  void _subscribeToProfile(String uid) {
    _profileSubscription = _repository.watchProfile(uid).listen(
      (UserProfile? profile) {
        if (uid != _loadedUid) return;
        _profile = profile;
        _isLoading = false;
        _isInitialized = true;
        notifyListeners();
        // Accounts created before LoText IDs existed are back-filled with a
        // generated ID on first load. New accounts already have one.
        if (profile != null && (profile.lotextId ?? '').isEmpty) {
          unawaited(_backfillLotextId(uid));
        }
        // Accounts that never chose a language get the device locale so
        // auto-translation has a target from day one.
        if (profile != null && (profile.preferredLang ?? '').isEmpty) {
          unawaited(_backfillPreferredLang(uid));
        }
      },
      onError: (Object e) {
        _error = e;
        _isLoading = false;
        _isInitialized = true;
        notifyListeners();
      },
    );
  }

  /// Generates and claims a LoText ID when the profile is missing one.
  Future<void> _backfillLotextId(String uid) async {
    if (_lotextIdBackfillUid == uid) return;
    _lotextIdBackfillUid = uid;
    try {
      await _repository.ensureLotextId(uid: uid);
    } on Exception {
      // Non-fatal; the profile simply has no ID until the next successful run.
    }
  }

  /// Seeds the profile's preferred language from the device locale when the
  /// user never picked one (so auto-translation has a target immediately).
  Future<void> _backfillPreferredLang(String uid) async {
    if (_preferredLangBackfillUid == uid) return;
    _preferredLangBackfillUid = uid;
    final String? code = _deviceLanguageCode();
    if (code == null || code.isEmpty) return;
    try {
      await _repository.setPreferredLanguage(uid: uid, code: code);
    } on Exception {
      // Non-fatal; the profile simply has no language until the user picks one.
    }
  }

  String? _deviceLanguageCode() {
    try {
      return WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    } catch (_) {
      return null;
    }
  }

  /// Re-runs the auth-change handler (used by retry buttons).
  Future<void> reload() => _handleAuthChange();

  /// Ensures the signed-in user can manage app configuration. Already-admin
  /// users get true immediately; otherwise the "first user" bootstrap claims
  /// admin if no admin exists yet. Returns true when the user is (now) admin.
  /// The profile stream carries the flag flip back to the UI.
  Future<bool> ensureOwnerAdmin() {
    if (_profile?.isAdmin ?? false) return Future<bool>.value(true);
    return _repository.claimOwnerAdmin(uid: _requireUid());
  }

  Future<void> setUsername(String username) {
    return _repository.claimUsername(
      uid: _requireUid(),
      newUsername: username,
      oldUsername: _profile?.username ?? '',
    );
  }

  Future<void> setDisplayName(String displayName) {
    return _repository.updateDisplayName(
      uid: _requireUid(),
      displayName: displayName,
    );
  }

  /// Sets the user's preferred language code (e.g. `en`, `fr`, `zh-CN`).
  /// Incoming messages are auto-translated into this language.
  Future<void> setPreferredLanguage(String code) {
    return _repository.setPreferredLanguage(
      uid: _requireUid(),
      code: code,
    );
  }

  /// Turns auto-translation of incoming foreign-language messages on/off.
  Future<void> setAutoTranslate(bool enabled) {
    return _repository.setAutoTranslate(
      uid: _requireUid(),
      enabled: enabled,
    );
  }

  Future<bool> isUsernameAvailable(String username) {
    return _repository.isUsernameAvailable(username);
  }

  /// Picks a photo from the device, uploads it, and updates the profile URL.
  /// Returns true when a photo was applied, false when the user cancelled.
  Future<bool> updateProfilePhoto() async {
    final PickedPhoto? picked = await _photoPicker.pickPhoto();
    if (picked == null) return false;
    final String url = await _repository.uploadProfilePhoto(
      uid: _requireUid(),
      bytes: picked.bytes,
    );
    await _repository.updatePhotoURL(uid: _requireUid(), photoURL: url);
    return true;
  }

  Future<void> removeProfilePhoto() {
    return _repository.removeProfilePhoto(uid: _requireUid());
  }

  Future<void> setOnline() async {
    final String? uid = _loadedUid;
    if (uid != null) await _repository.setPresence(uid: uid, online: true);
  }

  Future<void> setOffline() async {
    final String? uid = _loadedUid;
    if (uid != null) await _repository.setPresence(uid: uid, online: false);
  }

  /// One-shot read of another user's profile (public profile screen).
  Future<UserProfile?> fetchProfile(String uid) {
    return _repository.fetchProfile(uid);
  }

  /// Exact-match lookup by 9-digit LoText ID (no partial matches).
  Future<UserProfile?> fetchUserByLotextId(String lotextId) {
    return _repository.fetchUserByLotextId(lotextId);
  }

  /// Exact-match lookup by canonical username (accepts `@`-prefixed input).
  Future<UserProfile?> fetchUserByUsername(String username) {
    return _repository.fetchUserByUsername(username);
  }

  Future<bool> isContact(String contactUid) {
    return _repository.isContact(
      ownerUid: _requireUid(),
      contactUid: contactUid,
    );
  }

  Future<void> addContact(String contactUid) {
    return _repository.addContact(
      ownerUid: _requireUid(),
      contactUid: contactUid,
    );
  }

  Future<void> removeContact(String contactUid) {
    return _repository.removeContact(
      ownerUid: _requireUid(),
      contactUid: contactUid,
    );
  }

  /// Real-time stream of the signed-in user's private contact list.
  Stream<List<Contact>> watchContacts() {
    return _contactsStream ??= _repository.watchContacts(_requireUid());
  }

  String _requireUid() {
    final String? uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw StateError('No signed-in user.');
    }
    return uid;
  }

  @override
  void dispose() {
    _auth.removeListener(_handleAuthChange);
    _profileSubscription?.cancel();
    super.dispose();
  }
}
