import 'dart:async';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;

import '../../profile/models/user_profile.dart';
import '../models/chat_message.dart';
import '../models/conversation.dart';
import 'chat_repository.dart';

/// Production [ChatRepository] backed by Supabase (Postgres + Realtime +
/// Storage).
///
/// Storage layout:
/// - `conversations`    - one row per pair of users, keyed by the deterministic
///   [conversationIdFor] id. Holds participants, a denormalized summary of the
///   last message and per-participant unread counters.
/// - `messages`         - the actual messages, PK (id, conversation_id).
///   Inserts go through the `send_message` RPC so the summary and unread
///   counters update atomically with the message row.
/// - `chat_media`       - private bucket, objects at
///   `{conversationId}/{messageId}` (and `_thumb` for thumbnails). The DB
///   stores the object path; signed URLs are resolved at render time. Read and
///   write access are restricted to conversation participants by storage
///   policies.
/// - `device_tokens`    - FCM registration per user (kept for compatibility;
///   messages are surfaced through Realtime local notifications).
class SupabaseChatRepository implements ChatRepository {
  SupabaseChatRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// Object-path -> signed URL cache so realtime re-emissions don't re-sign
  /// every media message. Entries are refreshed ~10 minutes before expiry.
  final Map<String, String> _signedUrlCache = <String, String>{};
  final Map<String, DateTime> _signedUrlExpiresAt = <String, DateTime>{};
  static const int _signedUrlLifetimeSeconds = 3600;
  static const Duration _signedUrlRefreshMargin = Duration(minutes: 10);

  @override
  String conversationIdFor(String a, String b) {
    final List<String> ids = <String>[a, b]..sort();
    return '${ids[0]}_${ids[1]}';
  }

  @override
  Stream<List<Conversation>> watchConversations(String uid) {
    return _client
        .from('conversations')
        .stream(primaryKey: ['id'])
        .order('last_message_at', ascending: false)
        .asyncMap((List<Map<String, dynamic>> rows) async {
      final List<Conversation> result = <Conversation>[];
      for (final Map<String, dynamic> row in rows) {
        final List<String> participantIds = _participantIds(row);
        if (participantIds.length != 2 || !participantIds.contains(uid)) {
          continue;
        }
        final String peerUid =
            participantIds[0] == uid ? participantIds[1] : participantIds[0];
        final Map<String, dynamic>? unread =
            row['unread_counts'] as Map<String, dynamic>?;
        result.add(Conversation(
          id: row['id'] as String? ?? '',
          peer: await _loadPeerProfile(peerUid),
          lastMessageText: (row['last_message_text'] as String?) ?? '',
          lastMessageAt: _toDate(row['last_message_at']),
          lastSenderUid: (row['last_sender_uid'] as String?) ?? '',
          lastSenderName: (row['last_sender_name'] as String?) ?? '',
          unreadCount: (unread?[uid] as num?)?.toInt() ?? 0,
          typingUid: (row['typing_uid'] as String?) ?? '',
          typingUntil: _toDate(row['typing_until']),
          lastMessageType:
              _toType((row['last_message_type'] as String?) ?? 'text'),
          lastMessageDurationMs:
              (row['last_message_duration_ms'] as num?)?.toInt(),
        ));
      }
      return result;
    });
  }

  Future<UserProfile> _loadPeerProfile(String uid) async {
    final UserProfile? profile = await _fetchProfile(uid);
    return profile ??
        UserProfile(
          uid: uid,
          username: '',
          displayName: '',
        );
  }

  Future<UserProfile?> _fetchProfile(String uid) async {
    final List<Map<String, dynamic>> rows = await _client
        .from('profiles')
        .select()
        .eq('uid', uid)
        .limit(1);
    if (rows.isEmpty) return null;
    final Map<String, dynamic> data = rows.first;
    return UserProfile(
      uid: (data['uid'] as String?) ?? uid,
      username: (data['username'] as String?) ?? '',
      displayName: (data['display_name'] as String?) ?? '',
      lotextId: _nullIfEmpty(data['lotext_id'] as String?),
      photoURL: _nullIfEmpty(data['photo_url'] as String?),
      isOnline: (data['is_online'] as bool?) ?? false,
      lastSeen: _toDate(data['last_seen']),
    );
  }

  @override
  Future<String> ensureConversation({
    required String uid,
    required String contactUid,
  }) async {
    final List<Map<String, dynamic>> contact = await _client
        .from('contacts')
        .select('owner_uid')
        .eq('owner_uid', uid)
        .eq('contact_uid', contactUid)
        .limit(1);
    if (contact.isEmpty) {
      throw const NotAContactException();
    }

    final String id = conversationIdFor(uid, contactUid);
    // upsert keeps this idempotent - opening an existing conversation only
    // refreshes timestamps and never duplicates it. The deterministic id makes
    // duplicate conversations impossible by construction.
    final List<String> participants = <String>[uid, contactUid]..sort();
    await _client.from('conversations').upsert(<String, dynamic>{
      'id': id,
      'participant_ids': participants,
      'last_message_text': '',
      'last_sender_uid': null,
      'last_sender_name': '',
      'unread_counts': <String, int>{uid: 0, contactUid: 0},
    }, onConflict: 'id');
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
    final MessageType type = media?.type ?? MessageType.text;
    final String body = text.trim();
    if (type == MessageType.text && body.isEmpty) return;
    if (type != MessageType.text && (media == null || media.url.isEmpty)) {
      return;
    }

    try {
      await _client.rpc('send_message', params: <String, dynamic>{
        'p_conversation_id': conversationId,
        'p_sender_uid': senderUid,
        'p_text': body,
        'p_message_id': messageId,
        'p_type': type.name,
        'p_media_url': media?.url,
        'p_thumbnail_url': media?.thumbnailUrl,
        'p_duration_ms': media?.durationMs,
        'p_width': media?.width,
        'p_height': media?.height,
        'p_file_name': media?.fileName,
        'p_mime_type': media?.mimeType,
        'p_size_bytes': media?.sizeBytes,
        'p_reply_to_id': replyToId,
        'p_reply_to_type': replyToType,
        'p_reply_to_text': replyToText,
        'p_reply_to_sender': replyToSender,
        'p_voice_effect': voiceEffect ?? media?.voiceEffect,
        'p_lang': _nullIfEmpty(senderLang),
        'p_original_text': _nullIfEmpty(originalText),
        'p_source_lang': _nullIfEmpty(sourceLang),
      });
    } on PostgrestException catch (e) {
      if (e.message.contains('INVALID_CONVERSATION')) {
        throw StateError('Conversation $conversationId does not exist.');
      }
      if (e.message.contains('NOT_PARTICIPANT')) {
        throw StateError('Conversation $conversationId is invalid.');
      }
      rethrow;
    }
  }

  @override
  Future<void> deleteMessage({
    required String conversationId,
    required String messageId,
  }) async {
    await _client.rpc('delete_message', params: <String, dynamic>{
      'p_conversation_id': conversationId,
      'p_message_id': messageId,
    });
  }

  @override
  Future<MediaUploadTask> uploadChatMedia({
    required String conversationId,
    required String messageId,
    required Uint8List bytes,
    required String contentType,
    required String fileName,
  }) async {
    return _SupabaseMediaUploadTask(
      storage: _client.storage.from('chat_media'),
      path: '$conversationId/$messageId',
      bytes: bytes,
      contentType: contentType,
      fileName: fileName,
    );
  }

  @override
  Future<MediaUploadTask> uploadChatThumbnail({
    required String conversationId,
    required String messageId,
    required Uint8List bytes,
    required String contentType,
  }) async {
    return _SupabaseMediaUploadTask(
      storage: _client.storage.from('chat_media'),
      path: '$conversationId/${messageId}_thumb',
      bytes: bytes,
      contentType: contentType,
      fileName: '',
    );
  }

  @override
  Stream<List<ChatMessage>> watchMessages(String conversationId,
      {int limit = 100}) {
    return _client
        .from('messages')
        .stream(primaryKey: ['id', 'conversation_id'])
        .eq('conversation_id', conversationId)
        .order('created_at_ms', ascending: false)
        .limit(limit)
        .asyncMap((List<Map<String, dynamic>> rows) async {
      final List<ChatMessage> messages = <ChatMessage>[];
      for (final Map<String, dynamic> row in rows) {
        messages.add(await _toResolvedMessage(row));
      }
      return messages.reversed.toList();
    });
  }

  @override
  Future<List<ChatMessage>> fetchMessagesBefore(
    String conversationId,
    ChatMessage before, {
    int limit = 50,
  }) async {
    final List<Map<String, dynamic>> rows = await _client
        .from('messages')
        .select()
        .eq('conversation_id', conversationId)
        .lt('created_at_ms', before.createdAt.millisecondsSinceEpoch)
        .order('created_at_ms', ascending: false)
        .limit(limit);
    final List<ChatMessage> messages = <ChatMessage>[];
    for (final Map<String, dynamic> row in rows) {
      messages.add(await _toResolvedMessage(row));
    }
    return messages.reversed.toList();
  }

  @override
  Future<void> markConversationRead({
    required String conversationId,
    required String uid,
  }) async {
    await _client.rpc('mark_conversation_read', params: <String, dynamic>{
      'p_conversation_id': conversationId,
      'p_uid': uid,
    });
  }

  @override
  Future<void> markMessagesDelivered({
    required String conversationId,
    required List<String> messageIds,
  }) async {
    await _updateMessageStatus(conversationId, messageIds, 'delivered');
  }

  @override
  Future<void> markMessagesRead({
    required String conversationId,
    required List<String> messageIds,
  }) async {
    await _updateMessageStatus(conversationId, messageIds, 'read');
  }

  Future<void> _updateMessageStatus(
    String conversationId,
    List<String> messageIds,
    String status,
  ) async {
    final List<String> ids = messageIds.toSet().toList();
    if (ids.isEmpty) return;
    await _client.rpc('mark_message_status', params: <String, dynamic>{
      'p_conversation_id': conversationId,
      'p_message_ids': ids,
      'p_status': status,
    });
  }

  @override
  Future<void> registerFcmToken({
    required String uid,
    required String token,
  }) async {
    if (token.isEmpty) return;
    await _client.from('device_tokens').upsert(<String, dynamic>{
      'uid': uid,
      'token': token,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'uid,token');
  }

  @override
  Future<void> setTyping({
    required String conversationId,
    required String uid,
  }) async {
    await _client.rpc('set_typing', params: <String, dynamic>{
      'p_conversation_id': conversationId,
    });
  }

  @override
  Future<void> unregisterFcmToken({
    required String uid,
    required String token,
  }) async {
    if (token.isEmpty) return;
    await _client
        .from('device_tokens')
        .delete()
        .eq('uid', uid)
        .eq('token', token);
  }

  List<String> _participantIds(Map<String, dynamic> data) {
    return ((data['participant_ids'] as List<dynamic>?) ?? const <dynamic>[])
        .whereType<String>()
        .toList();
  }

  ChatMessage _toMessage(Map<String, dynamic> data) {
    final int createdAtMs = (data['created_at_ms'] as num?)?.toInt() ?? 0;
    return ChatMessage(
      id: (data['id'] as String?) ?? '',
      conversationId: (data['conversation_id'] as String?) ?? '',
      senderUid: (data['sender_uid'] as String?) ?? '',
      createdAt: _toDate(data['created_at']) ??
          DateTime.fromMillisecondsSinceEpoch(createdAtMs),
      type: _toType((data['type'] as String?) ?? 'text'),
      text: (data['text'] as String?) ?? '',
      mediaUrl: _nullIfEmpty(data['media_url'] as String?),
      thumbnailUrl: _nullIfEmpty(data['thumbnail_url'] as String?),
      durationMs: (data['duration_ms'] as num?)?.toInt(),
      width: (data['width'] as num?)?.toDouble(),
      height: (data['height'] as num?)?.toDouble(),
      fileName: _nullIfEmpty(data['file_name'] as String?),
      mimeType: _nullIfEmpty(data['mime_type'] as String?),
      sizeBytes: (data['size_bytes'] as num?)?.toInt(),
      status: _toStatus((data['status'] as String?) ?? 'sent'),
      isPending: false,
      replyToId: _nullIfEmpty(data['reply_to_id'] as String?),
      replyToType: _nullIfEmpty(data['reply_to_type'] as String?),
      replyToText: _nullIfEmpty(data['reply_to_text'] as String?),
      replyToSender: _nullIfEmpty(data['reply_to_sender'] as String?),
      voiceEffect: _nullIfEmpty(data['voice_effect'] as String?),
      senderLang: _nullIfEmpty(data['p_lang'] as String?),
      originalText: _nullIfEmpty(data['original_text'] as String?),
      sourceLang: _nullIfEmpty(data['source_lang'] as String?),
    );
  }

  /// Resolves stored object paths (and legacy public URLs) to fresh signed
  /// URLs, since the `chat_media` bucket is private.
  Future<ChatMessage> _toResolvedMessage(Map<String, dynamic> data) async {
    final String? rawMedia = _nullIfEmpty(data['media_url'] as String?);
    final String? rawThumb = _nullIfEmpty(data['thumbnail_url'] as String?);
    final ChatMessage message = _toMessage(data);
    return ChatMessage(
      id: message.id,
      conversationId: message.conversationId,
      senderUid: message.senderUid,
      createdAt: message.createdAt,
      type: message.type,
      text: message.text,
      mediaUrl: rawMedia == null
          ? null
          : await _resolveMediaUrl(rawMedia) ?? rawMedia,
      thumbnailUrl: rawThumb == null
          ? null
          : await _resolveMediaUrl(rawThumb) ?? rawThumb,
      durationMs: message.durationMs,
      width: message.width,
      height: message.height,
      fileName: message.fileName,
      mimeType: message.mimeType,
      sizeBytes: message.sizeBytes,
      status: message.status,
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

  Future<String?> _resolveMediaUrl(String value) async {
    final String path = _toObjectPath(value);
    final DateTime now = DateTime.now();
    final DateTime? cachedUntil = _signedUrlExpiresAt[path];
    if (cachedUntil != null && cachedUntil.isAfter(now)) {
      return _signedUrlCache[path];
    }
    try {
      final String url = await _client.storage
          .from('chat_media')
          .createSignedUrl(path, _signedUrlLifetimeSeconds);
      _signedUrlCache[path] = url;
      _signedUrlExpiresAt[path] = now
          .add(Duration(seconds: _signedUrlLifetimeSeconds))
          .subtract(_signedUrlRefreshMargin);
      return url;
    } catch (_) {
      return null;
    }
  }

  /// Extracts the object path relative to the `chat_media` bucket from either
  /// a stored path (`{conversationId}/{messageId}`) or a legacy public URL
  /// (`.../object/public/chat_media/{conversationId}/{messageId}`).
  String _toObjectPath(String value) {
    const String marker = '/object/public/';
    final int index = value.indexOf(marker);
    if (index != -1) {
      final String withBucket = value.substring(index + marker.length);
      final int slash = withBucket.indexOf('/');
      return slash == -1 ? withBucket : withBucket.substring(slash + 1);
    }
    return value;
  }

  MessageType _toType(String value) => switch (value) {
        'image' => MessageType.image,
        'video' => MessageType.video,
        'voice' => MessageType.voice,
        _ => MessageType.text,
      };

  ChatMessageStatus _toStatus(String value) => switch (value) {
        'delivered' => ChatMessageStatus.delivered,
        'read' => ChatMessageStatus.read,
        _ => ChatMessageStatus.sent,
      };

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

/// Bridges a Supabase upload to the app's [MediaUploadTask] contract.
///
/// Supabase Storage does not expose byte-level progress, so [progress] emits 0
/// when the upload starts and 1 when it finishes.
class _SupabaseMediaUploadTask implements MediaUploadTask {
  _SupabaseMediaUploadTask({
    required this._storage,
    required this._path,
    required this._bytes,
    required this._contentType,
    required this._fileName,
  });

  final StorageFileApi _storage;
  final String _path;
  final Uint8List _bytes;
  final String _contentType;
  final String _fileName;

  final StreamController<double> _progressController =
      StreamController<double>.broadcast();
  Future<void>? _uploadFuture;

  @override
  Stream<double> get progress => _progressController.stream;

  @override
  Future<String> get url async {
    await _upload();
    return _path;
  }

  Future<void> _upload() {
    if (_uploadFuture != null) return _uploadFuture!;
    _progressController.add(0);
    final Future<void> future = () async {
      try {
        await _storage.uploadBinary(
          _path,
          _bytes,
          fileOptions: FileOptions(
            contentType: _contentType,
            upsert: true,
            metadata: <String, String>{'fileName': _fileName},
          ),
        );
        if (!_progressController.isClosed) {
          _progressController.add(1);
        }
      } catch (_) {
        if (!_progressController.isClosed) {
          _progressController.close();
        }
        rethrow;
      }
    }();
    _uploadFuture = future;
    return future;
  }

  @override
  Future<void> cancel() async {
    if (_progressController.isClosed) return;
    await _progressController.close();
  }
}
