import 'dart:async';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../chat/data/chat_repository.dart';
import '../../../features/profile/models/user_profile.dart';
import '../models/managed_call.dart';
import '../models/managed_conversation.dart';
import '../models/managed_message.dart';
import '../models/managed_status.dart';
import 'managed_chat_repository.dart';

class SupabaseManagedChatRepository implements ManagedChatRepository {
  SupabaseManagedChatRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Stream<List<ManagedConversation>> watchConversations(String managedAccountId) {
    return _client
        .from('managed_account_conversations')
        .stream(primaryKey: ['id'])
        .eq('managed_account_id', managedAccountId)
        .order('last_message_at', ascending: false)
        .map((List<Map<String, dynamic>> rows) =>
            rows.map(_toConversation).toList());
  }

  @override
  Stream<UserProfile?> watchPeerPresence(String peerUid) {
    return _client
        .from('profiles')
        .stream(primaryKey: ['uid'])
        .eq('uid', peerUid)
        .map((List<Map<String, dynamic>> rows) {
      if (rows.isEmpty) return null;
      final Map<String, dynamic> data = rows.first;
      return UserProfile(
        uid: (data['uid'] as String?) ?? peerUid,
        username: (data['username'] as String?) ?? '',
        displayName: (data['display_name'] as String?) ?? '',
        lotextId: _nullIfEmpty(data['lotext_id'] as String?),
        photoURL: _nullIfEmpty(data['photo_url'] as String?),
        isOnline: (data['is_online'] as bool?) ?? false,
        lastSeen: _toDate(data['last_seen']),
      );
    });
  }

  @override
  Future<String> ensureConversation({
    required String managedAccountId,
    required String peerUid,
  }) async {
    final List<Map<String, dynamic>> existing = await _client
        .from('managed_account_conversations')
        .select('id')
        .eq('managed_account_id', managedAccountId)
        .eq('peer_uid', peerUid)
        .limit(1);
    if (existing.isNotEmpty) {
      return existing.first['id'] as String;
    }
    final UserProfile? peer = await _fetchPeerProfile(peerUid);
    final Map<String, dynamic> row = <String, dynamic>{
      'managed_account_id': managedAccountId,
      'peer_uid': peerUid,
      'peer_display_name': peer?.displayName ?? '',
      'peer_username': peer?.username ?? '',
      'peer_photo_url': peer?.photoURL ?? '',
      'last_message_text': '',
      'last_sender_uid': null,
      'unread_count': 0,
      'last_message_type': 'text',
    };
    final List<Map<String, dynamic>> result = await _client
        .from('managed_account_conversations')
        .insert(row)
        .select('id')
        .limit(1);
    return result.first['id'] as String;
  }

  @override
  Future<void> sendMessage({
    required String conversationId,
    required String managedAccountId,
    required String senderUid,
    required String text,
    String? messageId,
    ManagedMessageType type = ManagedMessageType.text,
    String? mediaUrl,
    String? thumbnailUrl,
    int? durationMs,
    double? width,
    double? height,
    String? fileName,
    String? mimeType,
    int? sizeBytes,
    String? voiceEffect,
    String? replyToId,
    String? replyToType,
    String? replyToText,
    String? replyToSender,
    String? senderLang,
    String? originalText,
    String? sourceLang,
  }) async {
    final String body = text.trim();
    if (type == ManagedMessageType.text && body.isEmpty) return;
    if (type != ManagedMessageType.text && (mediaUrl == null || mediaUrl.isEmpty)) {
      return;
    }

    final String mid = messageId ?? 'mm_${DateTime.now().microsecondsSinceEpoch}';
    final Map<String, dynamic> message = <String, dynamic>{
      'id': mid,
      'conversation_id': conversationId,
      'managed_account_id': managedAccountId,
      'sender_uid': senderUid,
      'type': _typeName(type),
      'text': body,
      'media_url': _nullIfEmpty(mediaUrl),
      'thumbnail_url': _nullIfEmpty(thumbnailUrl),
      'duration_ms': durationMs,
      'width': width,
      'height': height,
      'file_name': _nullIfEmpty(fileName),
      'mime_type': _nullIfEmpty(mimeType),
      'size_bytes': sizeBytes,
      'voice_effect': _nullIfEmpty(voiceEffect),
      'reply_to_id': _nullIfEmpty(replyToId),
      'reply_to_type': _nullIfEmpty(replyToType),
      'reply_to_text': _nullIfEmpty(replyToText),
      'reply_to_sender': _nullIfEmpty(replyToSender),
      'sender_lang': _nullIfEmpty(senderLang),
      'original_text': _nullIfEmpty(originalText),
      'source_lang': _nullIfEmpty(sourceLang),
      'status': 'sent',
    };

    final Map<String, dynamic> summary = <String, dynamic>{
      'last_message_text': body,
      'last_message_at': DateTime.now().toUtc().toIso8601String(),
      'last_sender_uid': senderUid,
      'last_message_type': _typeName(type),
      'last_message_duration_ms': durationMs,
    };

    await _client.rpc('send_managed_message', params: <String, dynamic>{
      'p_message': message,
      'p_conversation_id': conversationId,
      'p_summary': summary,
    });
  }

  @override
  Future<void> deleteMessage({
    required String conversationId,
    required String messageId,
  }) async {
    await _client
        .from('managed_account_messages')
        .delete()
        .eq('id', messageId)
        .eq('conversation_id', conversationId);
  }

  @override
  Stream<List<ManagedMessage>> watchMessages(String conversationId) {
    return _client
        .from('managed_account_messages')
        .stream(primaryKey: ['id', 'conversation_id'])
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: false)
        .limit(100)
        .asyncMap((List<Map<String, dynamic>> rows) async {
      final List<ManagedMessage> messages = <ManagedMessage>[];
      for (final Map<String, dynamic> row in rows) {
        messages.add(_toMessage(row));
      }
      return messages.reversed.toList();
    });
  }

  @override
  Future<List<ManagedMessage>> fetchMessagesBefore(
    String conversationId,
    ManagedMessage before, {
    int limit = 50,
  }) async {
    final List<Map<String, dynamic>> rows = await _client
        .from('managed_account_messages')
        .select()
        .eq('conversation_id', conversationId)
        .lt('created_at', before.createdAt.toUtc().toIso8601String())
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map(_toMessage).toList().reversed.toList();
  }

  @override
  Future<void> markConversationRead({
    required String conversationId,
    required String managedAccountId,
  }) async {
    await _client
        .from('managed_account_conversations')
        .update(<String, dynamic>{
      'unread_count': 0,
      'typing_uid': null,
      'typing_until': null,
    }).eq('id', conversationId)
    .eq('managed_account_id', managedAccountId);
  }

  @override
  Future<void> markMessagesDelivered(
    String conversationId,
    List<String> messageIds,
  ) {
    return _updateStatus(conversationId, messageIds, 'delivered');
  }

  @override
  Future<void> markMessagesRead(
    String conversationId,
    List<String> messageIds,
  ) {
    return _updateStatus(conversationId, messageIds, 'read');
  }

  Future<void> _updateStatus(
    String conversationId,
    List<String> messageIds,
    String status,
  ) async {
    if (messageIds.isEmpty) return;
    final List<String> ids = messageIds.toSet().toList();
    for (final String id in ids) {
      await _client
          .from('managed_account_messages')
          .update(<String, dynamic>{'status': status})
          .eq('id', id)
          .eq('conversation_id', conversationId);
    }
  }

  @override
  Future<void> setTyping(String conversationId) async {
    await _client.rpc('set_managed_typing', params: <String, dynamic>{
      'p_conversation_id': conversationId,
    });
  }

  @override
  Future<MediaUploadTask> uploadChatMedia({
    required String conversationId,
    required String messageId,
    required Uint8List bytes,
    required String contentType,
    required String fileName,
  }) {
    return Future.value(_ManagedMediaUploadTask(
      storage: _client.storage.from('managed_chat_media'),
      path: '$conversationId/$messageId',
      bytes: bytes,
      contentType: contentType,
      fileName: fileName,
    ));
  }

  @override
  Future<MediaUploadTask> uploadChatThumbnail({
    required String conversationId,
    required String messageId,
    required Uint8List bytes,
    required String contentType,
  }) {
    return Future.value(_ManagedMediaUploadTask(
      storage: _client.storage.from('managed_chat_media'),
      path: '$conversationId/${messageId}_thumb',
      bytes: bytes,
      contentType: contentType,
      fileName: '',
    ));
  }

  // ----- Managed calls -----

  @override
  Future<ManagedCall> startCall({
    required String managedAccountId,
    required String conversationId,
    required String peerUid,
    required ManagedCallType type,
  }) async {
    final String id = 'mc_${DateTime.now().microsecondsSinceEpoch}';
    await _client.from('managed_account_calls').insert(<String, dynamic>{
      'id': id,
      'managed_account_id': managedAccountId,
      'conversation_id': conversationId,
      'peer_uid': peerUid,
      'type': type == ManagedCallType.video ? 'video' : 'audio',
      'status': 'ringing',
    });
    return ManagedCall(
      id: id,
      managedAccountId: managedAccountId,
      conversationId: conversationId,
      peerUid: peerUid,
      type: type,
      status: ManagedCallStatus.ringing,
      createdAt: DateTime.now(),
    );
  }

  @override
  Stream<ManagedCall> watchCall(String callId) {
    return _client
        .from('managed_account_calls')
        .stream(primaryKey: ['id'])
        .eq('id', callId)
        .map((List<Map<String, dynamic>> rows) {
      if (rows.isEmpty) {
        return ManagedCall(
          id: callId,
          managedAccountId: '',
          conversationId: '',
          peerUid: '',
          type: ManagedCallType.audio,
          status: ManagedCallStatus.ended,
          createdAt: DateTime.now(),
        );
      }
      return _toCall(rows.first);
    });
  }

  @override
  Future<ManagedCall?> fetchCall(String callId) async {
    final List<Map<String, dynamic>> rows = await _client
        .from('managed_account_calls')
        .select()
        .eq('id', callId)
        .limit(1);
    if (rows.isEmpty) return null;
    return _toCall(rows.first);
  }

  @override
  Future<void> endCall({
    required String callId,
    required String byUid,
  }) async {
    await _client.from('managed_account_calls').update(<String, dynamic>{
      'status': 'ended',
      'ended_at': DateTime.now().toUtc().toIso8601String(),
      'ended_by': byUid,
    }).eq('id', callId);
  }

  @override
  Future<void> answerCall(String callId) async {
    await _client.from('managed_account_calls').update(<String, dynamic>{
      'status': 'active',
      'answered_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', callId);
  }

  @override
  Future<void> markMissed(String callId) async {
    await _client.from('managed_account_calls').update(<String, dynamic>{
      'status': 'missed',
      'ended_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', callId);
  }

  @override
  Future<void> declineCall(String callId) async {
    await _client.from('managed_account_calls').update(<String, dynamic>{
      'status': 'declined',
      'ended_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', callId);
  }

  @override
  Future<List<ManagedCall>> fetchCallHistory(String managedAccountId) async {
    final List<Map<String, dynamic>> rows = await _client
        .from('managed_account_calls')
        .select()
        .eq('managed_account_id', managedAccountId)
        .order('created_at', ascending: false)
        .limit(100);
    return rows.map(_toCall).toList();
  }

  @override
  Stream<void> watchCallChanges(String managedAccountId) {
    return _client
        .from('managed_account_calls')
        .stream(primaryKey: ['id'])
        .eq('managed_account_id', managedAccountId)
        .map((List<Map<String, dynamic>> _) {});
  }

  // ----- Managed status -----

  @override
  Stream<List<ManagedStatusGroup>> watchStatuses(String managedAccountId) {
    return _client
        .from('managed_account_statuses')
        .stream(primaryKey: ['id'])
        .eq('managed_account_id', managedAccountId)
        .order('created_at_ms', ascending: false)
        .asyncMap((List<Map<String, dynamic>> rows) async {
      final List<ManagedStatus> statuses = <ManagedStatus>[];
      for (final Map<String, dynamic> row in rows) {
        final ManagedStatus status = await _toManagedStatus(row);
        if (status.expiresAt.isAfter(DateTime.now())) {
          statuses.add(status);
        }
      }
      if (statuses.isEmpty) return <ManagedStatusGroup>[];
      return <ManagedStatusGroup>[
        ManagedStatusGroup(
          managedAccountId: managedAccountId,
          statuses: statuses,
        ),
      ];
    });
  }

  @override
  Future<String> postStatus({
    required String managedAccountId,
    required ManagedStatusType type,
    String text = '',
    String? statusId,
    String? mediaUrl,
    String? thumbnailUrl,
    int? durationMs,
    double? width,
    double? height,
    String? mimeType,
  }) async {
    final String id = statusId ?? 'ms_${DateTime.now().microsecondsSinceEpoch}';
    await _client.rpc('post_managed_status', params: <String, dynamic>{
      'p_status': <String, dynamic>{
        'id': id,
        'managed_account_id': managedAccountId,
        'type': _statusTypeName(type),
        'text': text,
        'media_url': mediaUrl,
        'thumbnail_url': thumbnailUrl,
        'duration_ms': durationMs,
        'width': width,
        'height': height,
        'mime_type': mimeType,
      },
    });
    return id;
  }

  @override
  Future<MediaUploadTask> uploadStatusMedia({
    required String managedAccountId,
    required String statusId,
    required Uint8List bytes,
    required String contentType,
    required String fileName,
  }) {
    return Future.value(_ManagedMediaUploadTask(
      storage: _client.storage.from('managed_status_media'),
      path: '$managedAccountId/$statusId',
      bytes: bytes,
      contentType: contentType,
      fileName: fileName,
    ));
  }

  @override
  Future<MediaUploadTask> uploadStatusThumbnail({
    required String managedAccountId,
    required String statusId,
    required Uint8List bytes,
    required String contentType,
  }) {
    return Future.value(_ManagedMediaUploadTask(
      storage: _client.storage.from('managed_status_media'),
      path: '$managedAccountId/${statusId}_thumb',
      bytes: bytes,
      contentType: contentType,
      fileName: '',
    ));
  }

  @override
  Future<void> markStatusViewed(String statusId) async {
    await _client.rpc('mark_managed_status_viewed',
        params: <String, dynamic>{'p_status_id': statusId});
  }

  @override
  Future<void> deleteStatus(String statusId) async {
    await _client.rpc('delete_managed_status',
        params: <String, dynamic>{'p_status_id': statusId});
  }

  @override
  Future<List<ManagedStatusViewer>> fetchStatusViewers(String statusId) async {
    final List<Map<String, dynamic>> rows = await _client
        .from('managed_account_status_views')
        .select('viewer_uid, viewed_at')
        .eq('status_id', statusId)
        .order('viewed_at', ascending: false);
    final List<ManagedStatusViewer> viewers = <ManagedStatusViewer>[];
    for (final Map<String, dynamic> row in rows) {
      final String viewerUid = (row['viewer_uid'] as String?) ?? '';
      final UserProfile? profile = viewerUid.isEmpty
          ? null
          : await _fetchPeerProfile(viewerUid);
      viewers.add(ManagedStatusViewer(
        profile: profile ??
            UserProfile(uid: viewerUid, username: '', displayName: ''),
        viewedAt: _toDate(row['viewed_at']) ?? DateTime.now(),
      ));
    }
    return viewers;
  }

  Future<UserProfile?> _fetchPeerProfile(String uid) async {
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

  ManagedConversation _toConversation(Map<String, dynamic> data) {
    return ManagedConversation(
      id: (data['id'] as String?) ?? '',
      managedAccountId: (data['managed_account_id'] as String?) ?? '',
      peerUid: (data['peer_uid'] as String?) ?? '',
      peerDisplayName: (data['peer_display_name'] as String?) ?? '',
      peerUsername: (data['peer_username'] as String?) ?? '',
      peerPhotoUrl: _nullIfEmpty(data['peer_photo_url'] as String?),
      lastMessageText: _nullIfEmpty(data['last_message_text'] as String?),
      lastMessageAt: _toDate(data['last_message_at']),
      lastSenderUid: _nullIfEmpty(data['last_sender_uid'] as String?),
      unreadCount: (data['unread_count'] as int?) ?? 0,
      typingUid: _nullIfEmpty(data['typing_uid'] as String?),
      typingUntil: _toDate(data['typing_until']),
      lastMessageType: _toType((data['last_message_type'] as String?) ?? 'text'),
      lastMessageDurationMs: (data['last_message_duration_ms'] as int?) ?? 0,
      createdAt: _toDate(data['created_at']),
    );
  }

  ManagedMessage _toMessage(Map<String, dynamic> data) {
    final int createdAtMs = (data['created_at_ms'] as num?)?.toInt() ?? 0;
    return ManagedMessage(
      id: (data['id'] as String?) ?? '',
      conversationId: (data['conversation_id'] as String?) ?? '',
      managedAccountId: (data['managed_account_id'] as String?) ?? '',
      senderUid: (data['sender_uid'] as String?) ?? '',
      type: _toType((data['type'] as String?) ?? 'text'),
      text: _nullIfEmpty(data['text'] as String?),
      mediaUrl: _nullIfEmpty(data['media_url'] as String?),
      thumbnailUrl: _nullIfEmpty(data['thumbnail_url'] as String?),
      durationMs: (data['duration_ms'] as int?) ?? 0,
      width: (data['width'] as num?)?.toDouble(),
      height: (data['height'] as num?)?.toDouble(),
      fileName: _nullIfEmpty(data['file_name'] as String?),
      mimeType: _nullIfEmpty(data['mime_type'] as String?),
      sizeBytes: (data['size_bytes'] as int?) ?? 0,
      voiceEffect: _nullIfEmpty(data['voice_effect'] as String?),
      replyToId: _nullIfEmpty(data['reply_to_id'] as String?),
      replyToType: _nullIfEmpty(data['reply_to_type'] as String?),
      replyToText: _nullIfEmpty(data['reply_to_text'] as String?),
      replyToSender: _nullIfEmpty(data['reply_to_sender'] as String?),
      senderLang: _nullIfEmpty(data['sender_lang'] as String?),
      originalText: _nullIfEmpty(data['original_text'] as String?),
      sourceLang: _nullIfEmpty(data['source_lang'] as String?),
      status: _toStatus((data['status'] as String?) ?? 'sent'),
      createdAt: _toDate(data['created_at']) ??
          DateTime.fromMillisecondsSinceEpoch(createdAtMs),
    );
  }

  ManagedMessageType _toType(String value) => switch (value) {
        'image' => ManagedMessageType.image,
        'video' => ManagedMessageType.video,
        'voice' => ManagedMessageType.voice,
        _ => ManagedMessageType.text,
      };

  ManagedCall _toCall(Map<String, dynamic> data) {
    return ManagedCall(
      id: (data['id'] as String?) ?? '',
      managedAccountId: (data['managed_account_id'] as String?) ?? '',
      conversationId: (data['conversation_id'] as String?) ?? '',
      peerUid: (data['peer_uid'] as String?) ?? '',
      type: (data['type'] as String?) == 'video'
          ? ManagedCallType.video
          : ManagedCallType.audio,
      status: _toCallStatus((data['status'] as String?) ?? 'ringing'),
      createdAt: _toDate(data['created_at']) ?? DateTime.now(),
      answeredAt: _toDate(data['answered_at']),
      endedAt: _toDate(data['ended_at']),
      endedBy: _nullIfEmpty(data['ended_by'] as String?),
    );
  }

  ManagedCallStatus _toCallStatus(String value) => switch (value) {
        'active' => ManagedCallStatus.active,
        'ended' => ManagedCallStatus.ended,
        'missed' => ManagedCallStatus.missed,
        'declined' => ManagedCallStatus.declined,
        _ => ManagedCallStatus.ringing,
      };

  Future<ManagedStatus> _toManagedStatus(Map<String, dynamic> data) async {
    final int createdAtMs = (data['created_at_ms'] as num?)?.toInt() ?? 0;
    final String? media = _nullIfEmpty(data['media_url'] as String?);
    final String? thumb = _nullIfEmpty(data['thumbnail_url'] as String?);
    return ManagedStatus(
      id: (data['id'] as String?) ?? '',
      managedAccountId: (data['managed_account_id'] as String?) ?? '',
      type: _toStatusType((data['type'] as String?) ?? 'text'),
      text: (data['text'] as String?) ?? '',
      mediaUrl: await _resolveStatusMediaUrl(media),
      thumbnailUrl: await _resolveStatusMediaUrl(thumb),
      durationMs: (data['duration_ms'] as num?)?.toInt(),
      width: (data['width'] as num?)?.toDouble(),
      height: (data['height'] as num?)?.toDouble(),
      mimeType: _nullIfEmpty(data['mime_type'] as String?),
      createdAt: _toDate(data['created_at']) ??
          DateTime.fromMillisecondsSinceEpoch(createdAtMs),
      expiresAt: _toDate(data['expires_at']) ?? DateTime.now(),
    );
  }

  Future<String?> _resolveStatusMediaUrl(String? path) async {
    if (path == null || path.isEmpty) return null;
    if (path.contains('http')) return path;
    try {
      return _client.storage.from('managed_status_media').getPublicUrl(path);
    } catch (_) {
      return null;
    }
  }

  ManagedStatusType _toStatusType(String value) => switch (value) {
        'image' => ManagedStatusType.image,
        'video' => ManagedStatusType.video,
        _ => ManagedStatusType.text,
      };

  String _statusTypeName(ManagedStatusType type) => switch (type) {
        ManagedStatusType.image => 'image',
        ManagedStatusType.video => 'video',
        ManagedStatusType.text => 'text',
      };

  String _typeName(ManagedMessageType type) => switch (type) {
        ManagedMessageType.image => 'image',
        ManagedMessageType.video => 'video',
        ManagedMessageType.voice => 'voice',
        ManagedMessageType.text => 'text',
      };

  ManagedMessageStatus _toStatus(String value) => switch (value) {
        'delivered' => ManagedMessageStatus.delivered,
        'read' => ManagedMessageStatus.read,
        _ => ManagedMessageStatus.sent,
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

class _ManagedMediaUploadTask implements MediaUploadTask {
  _ManagedMediaUploadTask({
    required this.storage,
    required this.path,
    required this.bytes,
    required this.contentType,
    required this.fileName,
  });

  final StorageFileApi storage;
  final String path;
  final Uint8List bytes;
  final String contentType;
  final String fileName;

  final StreamController<double> _progressController =
      StreamController<double>.broadcast();
  Future<void>? _uploadFuture;

  @override
  Stream<double> get progress => _progressController.stream;

  @override
  Future<String> get url async {
    await _upload();
    return path;
  }

  Future<void> _upload() {
    if (_uploadFuture != null) return _uploadFuture!;
    _progressController.add(0);
    final Future<void> future = () async {
      try {
        await storage.uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: contentType,
            upsert: true,
            metadata: <String, String>{'fileName': fileName},
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
    if (!_progressController.isClosed) {
      await _progressController.close();
    }
  }
}
