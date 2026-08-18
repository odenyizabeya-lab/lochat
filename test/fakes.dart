import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' hide MessageType;
import 'package:lotext/core/auth/auth_service.dart';
import 'package:lotext/core/auth/auth_user.dart';
import 'package:lotext/features/ai/models/ai_user_profile.dart';
import 'package:lotext/features/ai/ai_assistant_service.dart';
import 'package:lotext/features/ai/ai_chat_result.dart';
import 'package:lotext/features/ai/models/ai_conversation.dart';
import 'package:lotext/features/ai/models/ai_message.dart';
import 'package:lotext/features/ai/models/ai_provider.dart';
import 'package:lotext/features/ai/models/ai_task.dart';
import 'package:lotext/features/admin/data/app_config_repository.dart';
import 'package:lotext/features/calls/models/call.dart';
import 'package:lotext/features/calls/rtc/call_rtc_controller.dart';
import 'package:lotext/features/calls/signaling/call_signaling_service.dart';
import 'package:lotext/features/chat/data/chat_ai_service.dart';
import 'package:lotext/features/chat/data/chat_repository.dart';
import 'package:lotext/features/chat/media/chat_media_picker.dart';
import 'package:lotext/features/chat/media/media_playback.dart';
import 'package:lotext/features/chat/media/video_playback.dart';
import 'package:lotext/features/chat/media/voice_recorder.dart';
import 'package:lotext/features/chat/models/chat_message.dart';
import 'package:lotext/features/chat/models/conversation.dart';
import 'package:lotext/features/profile/data/lotext_id_generator.dart';
import 'package:lotext/features/profile/data/photo_picker.dart';
import 'package:lotext/features/profile/data/profile_repository.dart';
import 'package:lotext/features/profile/models/contact.dart';
import 'package:lotext/features/profile/models/user_profile.dart';
import 'package:lotext/features/status/data/status_repository.dart';
import 'package:lotext/features/status/models/status_update.dart';

/// Canonical form of a username: trimmed and lowercased (like production).
String normalize(String value) => value.trim().toLowerCase();

/// A small placeholder photo used by tests that exercise photo picking.
PickedPhoto fakePhoto() =>
    PickedPhoto(bytes: Uint8List.fromList(<int>[1, 2, 3]), name: 'photo.jpg');

/// A fake [AuthService] for widget tests.
///
/// Like Supabase Auth, it emits the current user as soon as it is listened to
/// and then forwards every sign-in state change.
class FakeAuthService implements AuthService {
  FakeAuthService({AuthUser? initialUser}) : _currentUser = initialUser;

  final StreamController<AuthUser?> _changes =
      StreamController<AuthUser?>.broadcast();
  AuthUser? _currentUser;

  @override
  Stream<AuthUser?> get authStateChanges async* {
    yield _currentUser;
    yield* _changes.stream;
  }

  @override
  AuthUser? get currentUser => _currentUser;

  @override
  Future<void> createAccount({
    required String email,
    required String password,
  }) async {
    _currentUser = AuthUser(uid: 'test-uid', email: email);
    _changes.add(_currentUser);
  }

  @override
  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    _currentUser = AuthUser(uid: 'test-uid', email: email);
    _changes.add(_currentUser);
  }

  @override
  Future<void> sendPasswordReset({required String email}) async {}

  String? updatedPassword;
  String? updatedEmail;

  @override
  Future<void> updatePassword(String password) async {
    updatedPassword = password;
  }

  @override
  Future<void> updateEmail(String email) async {
    updatedEmail = email;
  }

  @override
  Future<void> signOut() async {
    _currentUser = null;
    _changes.add(null);
  }

  int deleteAccountCalls = 0;

  @override
  Future<void> deleteAccount() async {
    deleteAccountCalls++;
    _currentUser = null;
    _changes.add(null);
  }

  // ---- Two-factor verification ----

  /// Whether a verified TOTP factor exists for the user.
  bool totpEnabled = false;

  /// The TOTP code accepted by [verifyTotp].
  String totpCode = '123456';

  /// The email code accepted by [verifyEmailCode].
  String emailCode = '123456';

  /// How many times [sendEmailCode] has been called.
  int emailCodeSentCount = 0;

  /// Throws from every 2FA operation when true.
  bool failTwoFactor = false;

  /// The factor id passed to the most recent [startTotpChallenge].
  String? lastTotpFactorId;

  @override
  Future<bool> hasTotpFactor() async => totpEnabled;

  @override
  Future<TotpChallenge> startTotpChallenge({String? factorId}) async {
    if (failTwoFactor) throw Exception('2FA failed');
    if (!totpEnabled && factorId == null) {
      throw const MfaFactorNotEnrolledException();
    }
    lastTotpFactorId = factorId ?? 'totp-factor-1';
    return TotpChallenge(factorId: lastTotpFactorId!, challengeId: 'challenge-1');
  }

  @override
  Future<void> verifyTotp({
    required String factorId,
    required String challengeId,
    required String code,
  }) async {
    if (failTwoFactor) throw Exception('2FA failed');
    if (code != totpCode) throw Exception('Invalid code');
  }

  @override
  Future<TotpEnrollment> enrollTotp() async {
    if (failTwoFactor) throw Exception('2FA failed');
    totpEnabled = true;
    return const TotpEnrollment(
      factorId: 'totp-factor-1',
      secret: 'JBSWY3DPEHPK3PXP',
    );
  }

  @override
  Future<void> sendEmailCode({required String email}) async {
    if (failTwoFactor) throw Exception('2FA failed');
    emailCodeSentCount++;
  }

  @override
  Future<void> verifyEmailCode({
    required String email,
    required String code,
  }) async {
    if (failTwoFactor) throw Exception('2FA failed');
    if (code != emailCode) throw Exception('Invalid code');
  }
}

/// An in-memory [ProfileRepository] for widget tests.
///
/// Mirrors the production contract: usernames and LoText IDs are registered in
/// lookup registries and can only be claimed once; contacts are private and
/// one-way. Emits the current profile to watchers.
class FakeProfileRepository implements ProfileRepository {
  final Map<String, UserProfile> profiles = <String, UserProfile>{};
  final Map<String, String> usernames = <String, String>{}; // name -> uid
  final Map<String, String> lotextIds = <String, String>{}; // id -> uid

  /// ownerUid -> set of contact uids (private, one-way).
  final Map<String, Set<String>> contacts = <String, Set<String>>{};

  final Map<String, StreamController<UserProfile?>> _controllers =
      <String, StreamController<UserProfile?>>{};
  final Map<String, StreamController<List<Contact>>> _contactControllers =
      <String, StreamController<List<Contact>>>{};

  StreamController<UserProfile?> _controllerFor(String uid) {
    return _controllers.putIfAbsent(
      uid,
      () => StreamController<UserProfile?>.broadcast(),
    );
  }

  StreamController<List<Contact>> _contactControllerFor(String ownerUid) {
    return _contactControllers.putIfAbsent(
      ownerUid,
      () => StreamController<List<Contact>>.broadcast(),
    );
  }

  void _emitContacts(String ownerUid) {
    final StreamController<List<Contact>>? controller =
        _contactControllers[ownerUid];
    if (controller != null && !controller.isClosed) {
      controller.add(_contactsOf(ownerUid));
    }
  }

  List<Contact> _contactsOf(String ownerUid) {
    final Set<String> uids = contacts[ownerUid] ?? const <String>{};
    final List<Contact> result = <Contact>[];
    for (final String uid in uids) {
      final UserProfile? profile = profiles[uid];
      if (profile != null) {
        result.add(Contact(uid: uid, profile: profile));
      }
    }
    return result;
  }

  /// Seeds a profile. Emits it to any current watchers.
  void seed(UserProfile profile) {
    profiles[profile.uid] = profile;
    if (profile.username.isNotEmpty) {
      usernames[normalize(profile.username)] = profile.uid;
    }
    if (profile.lotextId != null && profile.lotextId!.isNotEmpty) {
      lotextIds[profile.lotextId!] = profile.uid;
    }
    _controllerFor(profile.uid).add(profile);
  }

  @override
  Stream<UserProfile?> watchProfile(String uid) {
    final StreamController<UserProfile?> controller = _controllerFor(uid);
    final UserProfile? current = profiles[uid];
    // Emit the current state shortly after subscription (like Supabase).
    Future<void>.microtask(() {
      if (!controller.isClosed) controller.add(current);
    });
    return controller.stream;
  }

  @override
  Future<UserProfile?> fetchProfile(String uid) async => profiles[uid];

  @override
  Future<bool> isUsernameAvailable(String username) async =>
      !usernames.containsKey(normalize(username));

  @override
  Future<void> claimUsername({
    required String uid,
    required String newUsername,
    required String oldUsername,
  }) async {
    final String name = normalize(newUsername);
    if (usernames.containsKey(name) && usernames[name] != uid) {
      throw const UsernameUnavailableException();
    }
    if (oldUsername.isNotEmpty && oldUsername != name) {
      usernames.remove(oldUsername);
    }
    usernames[name] = uid;
    final UserProfile? existing = profiles[uid];
    final UserProfile updated = UserProfile(
      uid: uid,
      username: name,
      displayName: existing?.displayName ?? '',
      lotextId: existing?.lotextId,
      photoURL: existing?.photoURL,
      isOnline: existing?.isOnline ?? true,
      isAdmin: existing?.isAdmin ?? false,
      preferredLang: existing?.preferredLang,
      autoTranslate: existing?.autoTranslate ?? true,
      lastSeen: existing?.lastSeen,
      createdAt: existing?.createdAt,
      updatedAt: DateTime.now(),
    );
    profiles[uid] = updated;
    _controllerFor(uid).add(updated);
  }

  @override
  Future<void> updateDisplayName({
    required String uid,
    required String displayName,
  }) async {
    final UserProfile? existing = profiles[uid];
    if (existing == null) return;
    final UserProfile updated = existing.copyWith(
      displayName: displayName,
      updatedAt: DateTime.now(),
    );
    profiles[uid] = updated;
    _controllerFor(uid).add(updated);
  }

  @override
  Future<void> setPreferredLanguage({
    required String uid,
    required String code,
  }) async {
    final UserProfile? existing = profiles[uid];
    if (existing == null) return;
    final UserProfile updated = existing.copyWith(
      preferredLang: code,
      updatedAt: DateTime.now(),
    );
    profiles[uid] = updated;
    _controllerFor(uid).add(updated);
  }

  @override
  Future<void> setAutoTranslate({
    required String uid,
    required bool enabled,
  }) async {
    final UserProfile? existing = profiles[uid];
    if (existing == null) return;
    final UserProfile updated = existing.copyWith(
      autoTranslate: enabled,
      updatedAt: DateTime.now(),
    );
    profiles[uid] = updated;
    _controllerFor(uid).add(updated);
  }

  @override
  Future<String> uploadProfilePhoto({
    required String uid,
    required Uint8List bytes,
  }) async {
    return 'https://fake.example/photo_$uid.jpg';
  }

  @override
  Future<void> updatePhotoURL({
    required String uid,
    required String photoURL,
  }) async {
    final UserProfile? existing = profiles[uid];
    if (existing == null) return;
    final UserProfile updated = existing.copyWith(
      photoURL: photoURL,
      updatedAt: DateTime.now(),
    );
    profiles[uid] = updated;
    _controllerFor(uid).add(updated);
  }

  @override
  Future<void> removeProfilePhoto({required String uid}) async {
    final UserProfile? existing = profiles[uid];
    if (existing == null) return;
    final UserProfile updated = existing.withNoPhoto();
    profiles[uid] = updated;
    _controllerFor(uid).add(updated);
  }

  @override
  Future<void> setPresence({required String uid, required bool online}) async {
    final UserProfile? existing = profiles[uid];
    if (existing == null) return;
    final UserProfile updated = existing.copyWith(
      isOnline: online,
      lastSeen: online ? existing.lastSeen : DateTime.now(),
    );
    profiles[uid] = updated;
    _controllerFor(uid).add(updated);
  }

  @override
  Future<String> ensureLotextId({required String uid}) async {
    final UserProfile? existing = profiles[uid];
    final String? current = existing?.lotextId;
    if (current != null && current.isNotEmpty) return current;
    final String id = generateLotextId(Random());
    lotextIds[id] = uid;
    final UserProfile updated = UserProfile(
      uid: uid,
      username: existing?.username ?? '',
      displayName: existing?.displayName ?? '',
      lotextId: id,
      photoURL: existing?.photoURL,
      isOnline: existing?.isOnline ?? true,
      isAdmin: existing?.isAdmin ?? false,
      preferredLang: existing?.preferredLang,
      autoTranslate: existing?.autoTranslate ?? true,
      lastSeen: existing?.lastSeen,
      createdAt: existing?.createdAt,
      updatedAt: DateTime.now(),
    );
    profiles[uid] = updated;
    _controllerFor(uid).add(updated);
    return id;
  }

  @override
  Future<bool> claimOwnerAdmin({required String uid}) async {
    if (profiles.values.any((UserProfile p) => p.isAdmin)) return false;
    final UserProfile? existing = profiles[uid];
    if (existing == null) return false;
    final UserProfile updated = existing.copyWith(isAdmin: true);
    profiles[uid] = updated;
    _controllerFor(uid).add(updated);
    return true;
  }

  @override
  Future<UserProfile?> fetchUserByLotextId(String lotextId) async {
    // Prefer the profile's own LoText ID (mirrors production: the registry
    // must never resolve a friend to the searcher themselves).
    for (final UserProfile profile in profiles.values) {
      if (profile.lotextId == lotextId) return profile;
    }
    final String? uid = lotextIds[lotextId];
    return uid == null ? null : profiles[uid];
  }

  @override
  Future<UserProfile?> fetchUserByUsername(String username) async {
    final String name = normalize(username);
    if (name.isEmpty) return null;
    // Prefer the profile's own username (mirrors production).
    for (final UserProfile profile in profiles.values) {
      if (profile.username == name) return profile;
    }
    final String? uid = usernames[name];
    return uid == null ? null : profiles[uid];
  }

  @override
  Future<bool> isContact({
    required String ownerUid,
    required String contactUid,
  }) async {
    return contacts[ownerUid]?.contains(contactUid) ?? false;
  }

  @override
  Future<void> addContact({
    required String ownerUid,
    required String contactUid,
  }) async {
    contacts.putIfAbsent(ownerUid, () => <String>{}).add(contactUid);
    _emitContacts(ownerUid);
  }

  @override
  Future<void> removeContact({
    required String ownerUid,
    required String contactUid,
  }) async {
    final Set<String>? set = contacts[ownerUid];
    if (set == null) return;
    set.remove(contactUid);
    _emitContacts(ownerUid);
  }

  @override
  Stream<List<Contact>> watchContacts(String ownerUid) {
    return Stream<List<Contact>>.multi((
      StreamController<List<Contact>> controller,
    ) {
      controller.add(_contactsOf(ownerUid));
      final StreamSubscription<List<Contact>> sub = _contactControllerFor(
        ownerUid,
      ).stream.listen(controller.add);
      controller.onCancel = () => sub.cancel();
    });
  }
}

/// A fake [AppConfigRepository] for widget tests.
///
/// When given a [FakeProfileRepository], the admin check is derived from its
/// profiles (mirroring production, where `is_admin()` reads the profiles
/// table), so claiming owner admin via the profile flow is reflected here too.
class FakeAppConfigRepository implements AppConfigRepository {
  FakeAppConfigRepository({this.admin = true, this.profileRepository});

  /// Fallback admin flag used when no [profileRepository] is supplied.
  bool admin;

  final FakeProfileRepository? profileRepository;

  /// Throws from every operation when true (used to test error states).
  bool failRequests = false;

  final Map<String, String> values = <String, String>{};

  bool _isAdmin() =>
      profileRepository?.profiles.values.any((UserProfile p) => p.isAdmin) ??
      admin;

  @override
  Future<bool> isAdmin() async {
    if (failRequests) throw Exception('config load failed');
    return _isAdmin();
  }

  @override
  Future<Map<String, String>> fetchAll() async {
    if (failRequests) throw Exception('config load failed');
    return Map<String, String>.unmodifiable(values);
  }

  @override
  Future<void> setValue(String key, String value) async {
    if (failRequests) throw Exception('config save failed');
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }
}

/// A fake [ProfilePhotoPicker] that returns a preset photo (or throws).
class FakePhotoPicker implements ProfilePhotoPicker {
  FakePhotoPicker({this.photo, this.fail = false});

  final PickedPhoto? photo;
  bool fail;
  int pickCalls = 0;

  @override
  Future<PickedPhoto?> pickPhoto() async {
    pickCalls++;
    if (fail) throw Exception('photo picker failed');
    return photo;
  }
}

/// Internal store backing [FakeChatRepository].
class FakeConversationData {
  FakeConversationData({required this.id, required this.participantIds});

  final String id;
  final List<String> participantIds;
  String lastMessageText = '';
  DateTime? lastMessageAt;
  String lastSenderUid = '';
  String lastSenderName = '';
  MessageType lastMessageType = MessageType.text;
  int? lastMessageDurationMs;
  final Map<String, int> unreadCounts = <String, int>{};
  String? typingUid;
  DateTime? typingUntil;
}

/// An in-memory [ChatRepository] for widget tests.
///
/// Mirrors the production contract: conversations are keyed by the same
/// deterministic id, opening one with a non-contact throws
/// [NotAContactException], sending bumps the peer's unread counter, and every
/// write is emitted to watchers (like Firestore snapshots).
class FakeChatRepository implements ChatRepository {
  FakeChatRepository({FakeProfileRepository? profileRepository})
    : profileRepository = profileRepository ?? FakeProfileRepository();

  /// Used to resolve peer profiles and the contact check.
  final FakeProfileRepository profileRepository;

  final Map<String, FakeConversationData> conversations =
      <String, FakeConversationData>{};
  final Map<String, List<ChatMessage>> messages = <String, List<ChatMessage>>{};

  final Set<String> registeredTokens = <String>{};

  final Map<String, StreamController<List<Conversation>>>
  _conversationControllers = <String, StreamController<List<Conversation>>>{};
  final Map<String, StreamController<List<ChatMessage>>> _messageControllers =
      <String, StreamController<List<ChatMessage>>>{};

  int _messageSeed = 0;

  StreamController<List<Conversation>> _conversationControllerFor(String uid) {
    return _conversationControllers.putIfAbsent(
      uid,
      () => StreamController<List<Conversation>>.broadcast(),
    );
  }

  StreamController<List<ChatMessage>> _messageControllerFor(
    String conversationId,
  ) {
    return _messageControllers.putIfAbsent(
      conversationId,
      () => StreamController<List<ChatMessage>>.broadcast(),
    );
  }

  void _emitConversations(String uid) {
    final StreamController<List<Conversation>>? controller =
        _conversationControllers[uid];
    if (controller != null && !controller.isClosed) {
      controller.add(_viewOf(uid));
    }
  }

  void _emitMessages(String conversationId) {
    final StreamController<List<ChatMessage>>? controller =
        _messageControllers[conversationId];
    if (controller != null && !controller.isClosed) {
      controller.add(_sortedMessages(conversationId));
    }
  }

  List<ChatMessage> _sortedMessages(String conversationId) {
    final List<ChatMessage> list =
        List<ChatMessage>.of(messages[conversationId] ?? const <ChatMessage>[])
          ..sort(
            (ChatMessage a, ChatMessage b) =>
                a.createdAt.compareTo(b.createdAt),
          );
    return list;
  }

  List<Conversation> _viewOf(String uid) {
    final List<Conversation> result = <Conversation>[];
    for (final FakeConversationData data in conversations.values) {
      if (!data.participantIds.contains(uid)) continue;
      final String peerUid = data.participantIds[0] == uid
          ? data.participantIds[1]
          : data.participantIds[0];
      final UserProfile peer =
          profileRepository.profiles[peerUid] ??
          UserProfile(uid: peerUid, username: peerUid, displayName: '');
      result.add(
        Conversation(
          id: data.id,
          peer: peer,
          lastMessageText: data.lastMessageText,
          lastMessageAt: data.lastMessageAt,
          lastSenderUid: data.lastSenderUid,
          lastSenderName: data.lastSenderName,
          unreadCount: data.unreadCounts[uid] ?? 0,
          typingUid: data.typingUid,
          typingUntil: data.typingUntil,
          lastMessageType: data.lastMessageType,
          lastMessageDurationMs: data.lastMessageDurationMs,
        ),
      );
    }
    result.sort((Conversation a, Conversation b) {
      final DateTime? at = a.lastMessageAt;
      final DateTime? bt = b.lastMessageAt;
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });
    return result;
  }

  @override
  String conversationIdFor(String a, String b) {
    final List<String> ids = <String>[a, b]..sort();
    return '${ids[0]}_${ids[1]}';
  }

  @override
  Stream<List<Conversation>> watchConversations(String uid) {
    // Replays the current state to every new listener and forwards live
    // updates, mirroring how Firestore snapshots behave in production.
    return Stream<List<Conversation>>.multi((
      StreamController<List<Conversation>> controller,
    ) {
      controller.add(_viewOf(uid));
      final StreamSubscription<List<Conversation>> sub =
          _conversationControllerFor(uid).stream.listen(controller.add);
      controller.onCancel = () => sub.cancel();
    });
  }

  @override
  Future<String> ensureConversation({
    required String uid,
    required String contactUid,
  }) async {
    if (!(profileRepository.contacts[uid]?.contains(contactUid) ?? false)) {
      throw const NotAContactException();
    }
    final String id = conversationIdFor(uid, contactUid);
    if (!conversations.containsKey(id)) {
      conversations[id] = FakeConversationData(
        id: id,
        participantIds: <String>[uid, contactUid],
      );
      _emitConversations(uid);
      _emitConversations(contactUid);
    }
    return id;
  }

  @override
  Future<void> sendMessage({
    required String conversationId,
    required String senderUid,
    String text = '',
    String? messageId,
    MessageMedia? media,
    String? replyToId,
    String? replyToType,
    String? replyToText,
    String? replyToSender,
    String? voiceEffect,
    String? senderLang,
    String? originalText,
    String? sourceLang,
  }) async {
    final String id = messageId ?? 'msg-${_messageSeed++}';
    final ChatMessage message = ChatMessage(
      id: id,
      conversationId: conversationId,
      senderUid: senderUid,
      createdAt: DateTime.now(),
      type: media?.type ?? MessageType.text,
      text: text,
      mediaUrl: media?.url,
      thumbnailUrl: media?.thumbnailUrl,
      durationMs: media?.durationMs,
      width: media?.width,
      height: media?.height,
      fileName: media?.fileName,
      mimeType: media?.mimeType,
      sizeBytes: media?.sizeBytes,
      replyToId: replyToId,
      replyToType: replyToType,
      replyToText: replyToText,
      replyToSender: replyToSender,
      voiceEffect: voiceEffect,
      senderLang: senderLang,
      originalText: originalText,
      sourceLang: sourceLang,
    );
    messages.putIfAbsent(conversationId, () => <ChatMessage>[]).add(message);

    final FakeConversationData? data = conversations[conversationId];
    if (data != null) {
      data.lastMessageText = media == null ? text : '[${media.type.name}]';
      data.lastMessageType = media?.type ?? MessageType.text;
      data.lastMessageDurationMs = media?.durationMs;
      data.lastMessageAt = message.createdAt;
      data.lastSenderUid = senderUid;
      data.lastSenderName =
          profileRepository.profiles[senderUid]?.displayName ?? senderUid;
      if (data.typingUid == senderUid) {
        data.typingUid = null;
        data.typingUntil = null;
      }
      for (final String participant in data.participantIds) {
        if (participant != senderUid) {
          data.unreadCounts[participant] =
              (data.unreadCounts[participant] ?? 0) + 1;
        }
      }
      for (final String participant in data.participantIds) {
        _emitConversations(participant);
      }
    }
    _emitMessages(conversationId);
  }

  @override
  Future<void> deleteMessage({
    required String conversationId,
    required String messageId,
  }) async {
    final List<ChatMessage>? list = messages[conversationId];
    if (list == null) return;
    list.removeWhere((ChatMessage m) => m.id == messageId);
    _emitMessages(conversationId);
  }

  @override
  Future<MediaUploadTask> uploadChatMedia({
    required String conversationId,
    required String messageId,
    required Uint8List bytes,
    required String contentType,
    required String fileName,
  }) async {
    return FakeMediaUploadTask(
      resultUrl: 'https://fake.example/chat_media/$conversationId/$messageId',
    );
  }

  @override
  Future<MediaUploadTask> uploadChatThumbnail({
    required String conversationId,
    required String messageId,
    required Uint8List bytes,
    required String contentType,
  }) async {
    return FakeMediaUploadTask(
      resultUrl:
          'https://fake.example/chat_media/$conversationId/${messageId}_thumb',
    );
  }

  @override
  Stream<List<ChatMessage>> watchMessages(
    String conversationId, {
    int limit = 100,
  }) {
    return Stream<List<ChatMessage>>.multi((
      StreamController<List<ChatMessage>> controller,
    ) {
      controller.add(_sortedMessages(conversationId));
      final StreamSubscription<List<ChatMessage>> sub = _messageControllerFor(
        conversationId,
      ).stream.listen(controller.add);
      controller.onCancel = () => sub.cancel();
    });
  }

  @override
  Future<List<ChatMessage>> fetchMessagesBefore(
    String conversationId,
    ChatMessage before, {
    int limit = 50,
  }) async {
    final List<ChatMessage> list = _sortedMessages(
      conversationId,
    ).where((ChatMessage m) => m.createdAt.isBefore(before.createdAt)).toList();
    if (list.length <= limit) return list;
    return list.sublist(list.length - limit);
  }

  @override
  Future<void> markConversationRead({
    required String conversationId,
    required String uid,
  }) async {
    final FakeConversationData? data = conversations[conversationId];
    if (data == null) return;
    data.unreadCounts[uid] = 0;
    for (final String participant in data.participantIds) {
      _emitConversations(participant);
    }
  }

  @override
  Future<void> markMessagesDelivered({
    required String conversationId,
    required List<String> messageIds,
  }) async {
    _setStatuses(conversationId, messageIds, ChatMessageStatus.delivered);
  }

  @override
  Future<void> markMessagesRead({
    required String conversationId,
    required List<String> messageIds,
  }) async {
    _setStatuses(conversationId, messageIds, ChatMessageStatus.read);
  }

  void _setStatuses(
    String conversationId,
    List<String> messageIds,
    ChatMessageStatus status,
  ) {
    final List<ChatMessage>? list = messages[conversationId];
    if (list == null) return;
    final Set<String> ids = messageIds.toSet();
    for (int i = 0; i < list.length; i++) {
      final ChatMessage message = list[i];
      if (!ids.contains(message.id)) continue;
      if (message.status.index >= status.index) continue;
      list[i] = ChatMessage(
        id: message.id,
        conversationId: message.conversationId,
        senderUid: message.senderUid,
        createdAt: message.createdAt,
        type: message.type,
        text: message.text,
        mediaUrl: message.mediaUrl,
        thumbnailUrl: message.thumbnailUrl,
        durationMs: message.durationMs,
        width: message.width,
        height: message.height,
        fileName: message.fileName,
        mimeType: message.mimeType,
        sizeBytes: message.sizeBytes,
        status: status,
        isPending: message.isPending,
        replyToId: message.replyToId,
        replyToType: message.replyToType,
        replyToText: message.replyToText,
        replyToSender: message.replyToSender,
        voiceEffect: message.voiceEffect,
        senderLang: message.senderLang,
        originalText: message.originalText,
        sourceLang: message.sourceLang,
      );
    }
    _emitMessages(conversationId);
  }

  @override
  Future<void> setTyping({
    required String conversationId,
    required String uid,
  }) async {
    final FakeConversationData? data = conversations[conversationId];
    if (data == null || !data.participantIds.contains(uid)) return;
    data.typingUid = uid;
    data.typingUntil = DateTime.now().add(const Duration(seconds: 8));
    for (final String participant in data.participantIds) {
      _emitConversations(participant);
    }
  }

  /// Simulates the server-side expiry of a typing stamp.
  void expireTyping(String conversationId) {
    final FakeConversationData? data = conversations[conversationId];
    if (data == null) return;
    data.typingUid = null;
    data.typingUntil = null;
    for (final String participant in data.participantIds) {
      _emitConversations(participant);
    }
  }

  @override
  Future<void> registerFcmToken({
    required String uid,
    required String token,
  }) async {
    registeredTokens.add(token);
  }

  @override
  Future<void> unregisterFcmToken({
    required String uid,
    required String token,
  }) async {
    registeredTokens.remove(token);
  }
}

/// A fake [MediaUploadTask] that completes with a preset URL.
class FakeMediaUploadTask implements MediaUploadTask {
  FakeMediaUploadTask({this.resultUrl});

  final String? resultUrl;
  bool cancelled = false;

  @override
  Stream<double> get progress async* {
    yield 0.5;
    yield 1.0;
  }

  @override
  Future<String> get url async {
    if (cancelled) throw StateError('upload cancelled');
    return resultUrl ?? 'https://fake.example/upload';
  }

  @override
  Future<void> cancel() async {
    cancelled = true;
  }
}

/// A fake [ChatMediaPicker] that returns preset images/videos (or throws).
class FakeChatMediaPicker implements ChatMediaPicker {
  PickedChatImage? image;
  PickedChatVideo? video;
  bool failImages = false;
  bool failVideos = false;

  @override
  Future<PickedChatImage?> pickImage({required ChatMediaSource source}) async {
    if (failImages) throw Exception('picker failed');
    return image;
  }

  @override
  Future<PickedChatVideo?> pickVideo({required ChatMediaSource source}) async {
    if (failVideos) throw Exception('picker failed');
    return video;
  }
}

/// A fake [VoiceRecorder] that returns a short preset clip.
class FakeVoiceRecorder implements VoiceRecorder {
  bool permissionGranted = true;
  bool recording = false;
  int startCalls = 0;
  int stopCalls = 0;
  RecordedVoice? next;

  @override
  Future<bool> ensurePermission() async => permissionGranted;

  @override
  Future<void> startRecording() async {
    recording = true;
    startCalls++;
  }

  @override
  Future<RecordedVoice?> stopRecording() async {
    if (!recording) return null;
    recording = false;
    stopCalls++;
    return next ??
        RecordedVoice(
          bytes: Uint8List.fromList(<int>[1, 2, 3]),
          durationMs: 2000,
          fileName: 'voice.m4a',
          mimeType: 'audio/mp4',
        );
  }

  @override
  Future<void> cancelRecording() async {
    recording = false;
  }

  @override
  Future<void> dispose() async {}
}

/// A fake [VoicePlayer] that reports a fixed duration and no audio output.
class FakeVoicePlayer implements VoicePlayer {
  final StreamController<Duration> _position =
      StreamController<Duration>.broadcast();
  final StreamController<Duration?> _duration =
      StreamController<Duration?>.broadcast();
  final StreamController<bool> _playing = StreamController<bool>.broadcast();
  final StreamController<bool> _loading = StreamController<bool>.broadcast();

  String? url;
  int playCalls = 0;
  int pauseCalls = 0;

  @override
  Future<void> load(String url) async {
    this.url = url;
    if (!_duration.isClosed) _duration.add(const Duration(seconds: 30));
    if (!_loading.isClosed) _loading.add(false);
  }

  @override
  Future<void> play() async {
    playCalls++;
    if (!_playing.isClosed) _playing.add(true);
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    if (!_playing.isClosed) _playing.add(false);
  }

  @override
  Future<void> stop() async {
    if (!_playing.isClosed) _playing.add(false);
  }

  @override
  Future<void> dispose() async {
    await _position.close();
    await _duration.close();
    await _playing.close();
    await _loading.close();
  }

  @override
  Stream<Duration> get position => _position.stream;

  @override
  Stream<Duration?> get duration => _duration.stream;

  @override
  Stream<bool> get playing => _playing.stream;

  @override
  Stream<bool> get loading => _loading.stream;
}

/// A fake [VideoPlaybackController] that renders a black placeholder.
class FakeVideoPlaybackController implements VideoPlaybackController {
  final ValueNotifier<Duration> positionNotifier = ValueNotifier<Duration>(
    Duration.zero,
  );
  bool _initialized = false;
  bool playing = false;
  Duration? _duration;
  int playCalls = 0;
  int pauseCalls = 0;
  List<Duration> seeks = <Duration>[];

  @override
  Future<void> initialize() async {
    _initialized = true;
    _duration ??= const Duration(seconds: 30);
  }

  @override
  Future<void> play() async {
    playing = true;
    playCalls++;
  }

  @override
  Future<void> pause() async {
    playing = false;
    pauseCalls++;
  }

  @override
  Future<void> seekTo(Duration position) async => seeks.add(position);

  @override
  Future<void> setLooping(bool looping) async {}

  @override
  Future<void> dispose() async => positionNotifier.dispose();

  @override
  Widget buildView() => Container(
    color: const Color(0xFF000000),
    child: const Center(child: Text('video')),
  );

  @override
  bool get isInitialized => _initialized;

  @override
  bool get isPlaying => playing;

  @override
  Duration? get duration => _duration;

  @override
  ValueListenable<Duration> get position => positionNotifier;
}

/// A fake [CallSignalingService] that keeps call state in memory and
/// broadcasts every update to [watchCall] subscribers.
class FakeCallSignalingService implements CallSignalingService {
  final Map<String, Call> _calls = <String, Call>{};
  final Map<String, StreamController<Call>> _watchers =
      <String, StreamController<Call>>{};
  final Map<String, String> _offers = <String, String>{};
  final Map<String, String> _answers = <String, String>{};
  final Map<String, StreamController<String>> _answerWatchers =
      <String, StreamController<String>>{};
  final Map<String, List<CallCandidate>> _candidates =
      <String, List<CallCandidate>>{};
  final StreamController<void> _changes = StreamController<void>.broadcast();

  int _nextId = 0;

  /// Throws from every fetch when true (used to test error states).
  bool failRequests = false;

  /// Seeds a call into the fake store (like Firestore data already present)
  /// and emits a change so live `watchCallChanges` subscribers refresh.
  void seedCall(Call call) {
    _calls[call.id] = call;
    _emit(call.id);
  }

  StreamController<Call> _watcher(String callId) =>
      _watchers.putIfAbsent(callId, StreamController<Call>.broadcast);

  StreamController<String> _answerWatcher(String callId) =>
      _answerWatchers.putIfAbsent(callId, StreamController<String>.broadcast);

  void _emit(String callId) {
    final Call? call = _calls[callId];
    if (call != null && _watchers[callId] != null) {
      _watchers[callId]!.add(call);
    }
    if (!_changes.isClosed) _changes.add(null);
  }

  @override
  Future<String> createCall({
    required String callerUid,
    required String calleeUid,
    required CallType type,
    required String conversationId,
  }) async {
    final String id = 'call-${_nextId++}';
    _calls[id] = Call(
      id: id,
      conversationId: conversationId,
      type: type,
      callerUid: callerUid,
      calleeUid: calleeUid,
      status: CallStatus.ringing,
      createdAt: DateTime.now(),
    );
    return id;
  }

  @override
  Stream<Call> watchCall(String callId) {
    final Call? existing = _calls[callId];
    final StreamController<Call> controller = _watcher(callId);
    if (existing != null) controller.add(existing);
    return controller.stream;
  }

  @override
  Future<Call?> fetchCall(String callId) async => _calls[callId];

  @override
  Future<void> acceptCall(String callId) async {
    final Call? call = _calls[callId];
    if (call == null) return;
    _calls[callId] = _copy(
      call,
      status: CallStatus.active,
      answeredAt: DateTime.now(),
    );
    _emit(callId);
  }

  @override
  Future<void> declineCall(String callId) async {
    final Call? call = _calls[callId];
    if (call == null) return;
    _calls[callId] = _copy(
      call,
      status: CallStatus.declined,
      endedAt: DateTime.now(),
      endedBy: call.calleeUid,
    );
    _emit(callId);
  }

  @override
  Future<void> endCall(String callId, {required String byUid}) async {
    final Call? call = _calls[callId];
    if (call == null) return;
    _calls[callId] = _copy(
      call,
      status: CallStatus.ended,
      endedAt: DateTime.now(),
      endedBy: byUid,
    );
    _emit(callId);
  }

  @override
  Future<void> markMissed(String callId) async {
    final Call? call = _calls[callId];
    if (call == null) return;
    _calls[callId] = _copy(
      call,
      status: CallStatus.missed,
      endedAt: DateTime.now(),
    );
    _emit(callId);
  }

  Call _copy(
    Call source, {
    CallStatus? status,
    DateTime? answeredAt,
    DateTime? endedAt,
    String? endedBy,
  }) {
    return Call(
      id: source.id,
      conversationId: source.conversationId,
      type: source.type,
      callerUid: source.callerUid,
      calleeUid: source.calleeUid,
      status: status ?? source.status,
      createdAt: source.createdAt,
      answeredAt: answeredAt ?? source.answeredAt,
      endedAt: endedAt ?? source.endedAt,
      endedBy: endedBy ?? source.endedBy,
    );
  }

  @override
  Future<void> writeOffer(String callId, String sdp) async {
    _offers[callId] = sdp;
  }

  @override
  Future<String?> fetchOffer(String callId) async => _offers[callId];

  @override
  Future<void> writeAnswer(String callId, String sdp) async {
    _answers[callId] = sdp;
    if (_answerWatchers[callId] != null) _answerWatchers[callId]!.add(sdp);
  }

  @override
  Future<String?> fetchAnswer(String callId) async => _answers[callId];

  @override
  Stream<String> watchAnswer(String callId) => _answerWatcher(callId).stream;

  @override
  Future<void> addCandidate(String callId, CallCandidate candidate) async {
    _candidates.putIfAbsent(callId, () => <CallCandidate>[]).add(candidate);
  }

  @override
  Stream<CallCandidate> watchCandidates(
    String callId, {
    required String excludeSender,
  }) {
    final List<CallCandidate> existing = _candidates[callId] ?? const [];
    final StreamController<CallCandidate> controller =
        StreamController<CallCandidate>.broadcast();
    for (final CallCandidate c in existing) {
      if (c.senderUid != excludeSender) controller.add(c);
    }
    return controller.stream;
  }

  @override
  Future<List<CallCandidate>> fetchCandidates(
    String callId, {
    required String excludeSender,
  }) async {
    final List<CallCandidate> all = _candidates[callId] ?? const [];
    return all
        .where((CallCandidate c) => c.senderUid != excludeSender)
        .toList();
  }

  @override
  Future<List<Call>> fetchCallHistory({required String uid}) async {
    if (failRequests) throw Exception('call history load failed');
    final List<Call> calls =
        _calls.values
            .where((Call c) => c.callerUid == uid || c.calleeUid == uid)
            .toList()
          ..sort((Call a, Call b) => b.createdAt.compareTo(a.createdAt));
    return calls;
  }

  @override
  Stream<void> watchCallChanges({required String uid}) => _changes.stream;
}

/// A fake [CallRtcController] that never touches platform channels.
class FakeCallRtcController implements CallRtcController {
  bool _muted = false;
  bool _cameraEnabled = true;

  @override
  Future<void> initialize() async {}

  @override
  Future<RTCSessionDescription> createOffer() async =>
      RTCSessionDescription('sdp-offer', 'offer');

  @override
  Future<RTCSessionDescription> createAnswer(
    RTCSessionDescription offer,
  ) async => RTCSessionDescription('sdp-answer', 'answer');

  @override
  Future<void> setRemoteDescription(RTCSessionDescription answer) async {}

  @override
  Future<void> addIceCandidate(RTCIceCandidate candidate) async {}

  @override
  Stream<RTCIceCandidate> get localCandidates =>
      StreamController<RTCIceCandidate>.broadcast().stream;

  @override
  Stream<void> get connected => StreamController<void>.broadcast().stream;

  @override
  Future<void> toggleMute() async => _muted = !_muted;

  @override
  bool get muted => _muted;

  @override
  Future<void> toggleCamera() async => _cameraEnabled = !_cameraEnabled;

  @override
  Future<void> switchCamera() async {}

  @override
  bool get cameraEnabled => _cameraEnabled;

  @override
  Widget? get localView => null;

  @override
  Widget? get remoteView => null;

  @override
  Future<void> dispose() async {}
}

/// A fake [AiAssistantService] that stores conversations and messages in
/// memory and returns a canned assistant reply.
class FakeAiAssistantService implements AiAssistantService {
  final List<AiConversation> conversations = <AiConversation>[];
  final Map<String, List<AiMessage>> messagesByConversation =
      <String, List<AiMessage>>{};

  /// Thrown from every operation when true (used to test error states).
  bool failRequests = false;

  /// The reply returned for every message.
  String reply = 'Hello from fake AI';

  int _nextId = 0;

  @override
  Future<List<AiConversation>> listConversations() async {
    _maybeFail();
    return List<AiConversation>.unmodifiable(conversations);
  }

  @override
  Future<AiConversation> createConversation({
    String title = 'New chat',
    required AiProvider provider,
  }) async {
    _maybeFail();
    final AiConversation conversation = AiConversation(
      id: 'ai-${_nextId++}',
      title: title,
      provider: provider,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    conversations.insert(0, conversation);
    messagesByConversation[conversation.id] = <AiMessage>[];
    return conversation;
  }

  @override
  Future<AiConversation> setProvider({
    required String conversationId,
    required AiProvider provider,
  }) async {
    _maybeFail();
    final AiConversation conversation = _find(conversationId);
    final AiConversation updated = conversation.copyWith(
      provider: provider,
      updatedAt: DateTime.now(),
    );
    _replace(updated);
    return updated;
  }

  @override
  Future<void> deleteConversation(String conversationId) async {
    _maybeFail();
    conversations.removeWhere((AiConversation c) => c.id == conversationId);
    messagesByConversation.remove(conversationId);
  }

  @override
  Future<List<AiMessage>> fetchMessages(String conversationId) async {
    _maybeFail();
    return List<AiMessage>.unmodifiable(
      messagesByConversation[conversationId] ?? const <AiMessage>[],
    );
  }

  @override
  Future<AiChatResult> sendMessage({
    required String conversationId,
    required String content,
    AiTask? task,
    String? targetLanguage,
    AiUserProfile? profile,
  }) async {
    _maybeFail();
    final AiMessage userMessage = AiMessage(
      id: 'user-${_nextId++}',
      role: AiRole.user,
      content: content,
      createdAt: DateTime.now(),
    );
    final String taskSuffix = task != null ? ' (${task.wireName})' : '';
    final String assistantContent = task != null
        ? '$reply$taskSuffix'
        : (profile != null
            ? 'Profile: ${profile.displayName} - Adapted response'
            : reply);
    final AiMessage assistantMessage = AiMessage(
      id: 'assistant-${_nextId++}',
      role: AiRole.assistant,
      content: assistantContent,
      createdAt: DateTime.now(),
    );
    final List<AiMessage> list = messagesByConversation.putIfAbsent(
      conversationId,
      () => <AiMessage>[],
    );
    list.add(userMessage);
    list.add(assistantMessage);
    return AiChatResult(user: userMessage, assistant: assistantMessage);
  }

  AiConversation _find(String conversationId) {
    return conversations.firstWhere(
      (AiConversation c) => c.id == conversationId,
      orElse: () => throw StateError('Conversation $conversationId not found'),
    );
  }

  void _replace(AiConversation updated) {
    for (int i = 0; i < conversations.length; i++) {
      if (conversations[i].id == updated.id) {
        conversations[i] = updated;
        return;
      }
    }
  }

  void _maybeFail() {
    if (failRequests) {
      throw StateError('Fake AI failure');
    }
  }
}

/// An in-memory [StatusRepository] for widget tests.
///
/// Mirrors the production contract: statuses are grouped by author, newest
/// first, and groups are sorted by their latest post; viewing is idempotent and
/// tracked per viewer. Every write is emitted to watchers (like Supabase
/// Realtime). [viewerUid] plays the role of the RLS-authenticated caller, so
/// `markStatusViewed` and `deleteStatus` know who is acting.
class FakeStatusRepository implements StatusRepository {
  /// All statuses currently in the system, keyed by id.
  final Map<String, StatusUpdate> statuses = <String, StatusUpdate>{};

  /// Author profiles used to render groups.
  final Map<String, UserProfile> profiles = <String, UserProfile>{};

  /// statusId -> (viewerUid -> viewedAt).
  final Map<String, Map<String, DateTime>> views =
      <String, Map<String, DateTime>>{};

  /// The signed-in user, treated as the RLS-authenticated caller.
  String? viewerUid;

  final Map<String, StreamController<List<StatusGroup>>> _controllers =
      <String, StreamController<List<StatusGroup>>>{};

  int _seed = 0;

  StreamController<List<StatusGroup>> _controllerFor(String uid) {
    return _controllers.putIfAbsent(
      uid,
      () => StreamController<List<StatusGroup>>.broadcast(),
    );
  }

  /// Seeds an author profile used to render status groups.
  void seedProfile(UserProfile profile) {
    profiles[profile.uid] = profile;
  }

  /// Seeds a status, optionally marking which uids have already seen it.
  void seedStatus(StatusUpdate status, {Set<String> viewedBy = const {}}) {
    statuses[status.id] = status;
    for (final String viewer in viewedBy) {
      views.putIfAbsent(status.id, () => <String, DateTime>{})[viewer] =
          status.createdAt;
    }
    for (final String viewer in _controllers.keys) {
      _emit(viewer);
    }
  }

  void _emit(String uid) {
    final StreamController<List<StatusGroup>>? controller = _controllers[uid];
    if (controller != null && !controller.isClosed) {
      controller.add(_groupsFor(uid));
    }
  }

  List<StatusGroup> _groupsFor(String uid) {
    final Map<String, List<StatusUpdate>> grouped =
        <String, List<StatusUpdate>>{};
    for (final StatusUpdate raw in statuses.values) {
      final StatusUpdate status = raw.copyWith(
        isViewed: views[raw.id]?.containsKey(uid) ?? false,
      );
      grouped.putIfAbsent(status.uid, () => <StatusUpdate>[]).add(status);
    }
    for (final List<StatusUpdate> list in grouped.values) {
      list.sort((StatusUpdate a, StatusUpdate b) {
        return b.createdAt.compareTo(a.createdAt);
      });
    }
    final List<StatusGroup> groups = grouped.entries.map((
      MapEntry<String, List<StatusUpdate>> e,
    ) {
      return StatusGroup(
        author:
            profiles[e.key] ??
            UserProfile(uid: e.key, username: e.key, displayName: ''),
        statuses: e.value,
      );
    }).toList();
    groups.sort((StatusGroup a, StatusGroup b) {
      return b.statuses.first.createdAt.compareTo(a.statuses.first.createdAt);
    });
    return groups;
  }

  @override
  Stream<List<StatusGroup>> watchStatuses(String uid) {
    return Stream<List<StatusGroup>>.multi((
      StreamController<List<StatusGroup>> controller,
    ) {
      controller.add(_groupsFor(uid));
      final StreamSubscription<List<StatusGroup>> sub = _controllerFor(
        uid,
      ).stream.listen(controller.add);
      controller.onCancel = () => sub.cancel();
    });
  }

  @override
  Future<String> postStatus({
    required String uid,
    required StatusType type,
    String text = '',
    String? statusId,
    String? mediaUrl,
    String? thumbnailUrl,
    int? durationMs,
    double? width,
    double? height,
    String? mimeType,
  }) async {
    final String id = statusId ?? 'status-${_seed++}';
    final DateTime now = DateTime.now();
    statuses[id] = StatusUpdate(
      id: id,
      uid: uid,
      type: type,
      text: text,
      mediaUrl: mediaUrl,
      thumbnailUrl: thumbnailUrl,
      durationMs: durationMs,
      width: width,
      height: height,
      mimeType: mimeType,
      createdAt: now,
      expiresAt: now.add(const Duration(hours: 24)),
    );
    for (final String viewer in _controllers.keys) {
      _emit(viewer);
    }
    return id;
  }

  @override
  Future<MediaUploadTask> uploadStatusMedia({
    required String uid,
    required String statusId,
    required Uint8List bytes,
    required String contentType,
    required String fileName,
  }) async {
    return FakeMediaUploadTask(
      resultUrl: 'https://fake.example/status_media/$uid/$statusId',
    );
  }

  @override
  Future<MediaUploadTask> uploadStatusThumbnail({
    required String uid,
    required String statusId,
    required Uint8List bytes,
    required String contentType,
  }) async {
    return FakeMediaUploadTask(
      resultUrl: 'https://fake.example/status_media/$uid/${statusId}_thumb',
    );
  }

  @override
  Future<void> markStatusViewed(String statusId) async {
    final String? viewer = viewerUid;
    final StatusUpdate? status = statuses[statusId];
    if (viewer == null || status == null || status.uid == viewer) return;
    views.putIfAbsent(statusId, () => <String, DateTime>{})[viewer] =
        DateTime.now();
    for (final String uid in _controllers.keys) {
      _emit(uid);
    }
  }

  @override
  Future<void> deleteStatus(String statusId) async {
    final StatusUpdate? status = statuses[statusId];
    if (status == null) return;
    if (viewerUid != null && status.uid != viewerUid) return;
    statuses.remove(statusId);
    views.remove(statusId);
    for (final String uid in _controllers.keys) {
      _emit(uid);
    }
  }

  @override
  Future<List<StatusViewer>> fetchStatusViewers(String statusId) async {
    final Map<String, DateTime>? byUid = views[statusId];
    if (byUid == null) return const <StatusViewer>[];
    final List<StatusViewer> result = byUid.entries.map((
      MapEntry<String, DateTime> e,
    ) {
      return StatusViewer(
        profile:
            profiles[e.key] ??
            UserProfile(uid: e.key, username: e.key, displayName: ''),
        viewedAt: e.value,
      );
    }).toList();
    result.sort((StatusViewer a, StatusViewer b) {
      return b.viewedAt.compareTo(a.viewedAt);
    });
    return result;
  }
}

/// A fake [ChatAiService] that returns preset translations (or throws).
class FakeChatAiService implements ChatAiService {
  /// The translation returned for every request.
  String translation = 'Bonjour';

  /// English name of the "source" language reported for translations.
  String sourceLanguage = '';

  /// Thrown from every operation when true (used to test error states).
  bool failRequests = false;

  /// Every call is recorded for assertions.
  final List<({String text, String targetLanguage})> translateCalls =
      <({String text, String targetLanguage})>[];

  @override
  Future<TextTranslationResult> translateText({
    required String text,
    required String targetLanguage,
  }) async {
    if (failRequests) throw const ChatAiException('Translation failed');
    translateCalls.add((text: text, targetLanguage: targetLanguage));
    return TextTranslationResult(
      translation: translation,
      sourceLanguage: sourceLanguage,
    );
  }

  @override
  Future<VoiceTranslationResult> translateVoice({
    required String audioUrl,
    required String targetLanguage,
  }) async {
    if (failRequests) throw const ChatAiException('Translation failed');
    return VoiceTranslationResult(
      transcript: 'transcript',
      translation: translation,
    );
  }

  /// Audio bytes returned by [synthesizeVoice].
  Uint8List synthAudioBytes = Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6]);

  /// Every synthesis call is recorded for assertions.
  final List<({String voiceName, String? text, Uint8List? audioBytes})>
  synthCalls = <({String voiceName, String? text, Uint8List? audioBytes})>[];

  @override
  Future<VoiceSynthesisResult> synthesizeVoice({
    required String voiceName,
    String? text,
    Uint8List? audioBytes,
  }) async {
    if (failRequests) throw const ChatAiException('Voice synthesis failed');
    synthCalls.add((voiceName: voiceName, text: text, audioBytes: audioBytes));
    return VoiceSynthesisResult(
      audioBytes: synthAudioBytes,
      contentType: 'audio/mpeg',
    );
  }
}
