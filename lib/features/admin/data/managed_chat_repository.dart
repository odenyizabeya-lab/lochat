import 'dart:async';
import 'dart:typed_data';

import '../../../features/profile/models/user_profile.dart';
import '../../chat/data/chat_repository.dart';
import '../models/managed_call.dart';
import '../models/managed_conversation.dart';
import '../models/managed_message.dart';
import '../models/managed_status.dart';

abstract class ManagedChatRepository {
  Stream<List<ManagedConversation>> watchConversations(String managedAccountId);

  /// Live presence (online flag + last seen) for a peer, streamed from the
  /// shared `profiles` table so the admin chat mirrors the user chat room.
  Stream<UserProfile?> watchPeerPresence(String peerUid);

  Future<String> ensureConversation({
    required String managedAccountId,
    required String peerUid,
  });

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
  });

  Future<void> deleteMessage({
    required String conversationId,
    required String messageId,
  });

  Stream<List<ManagedMessage>> watchMessages(String conversationId);

  Future<List<ManagedMessage>> fetchMessagesBefore(
    String conversationId,
    ManagedMessage before, {
    int limit = 50,
  });

  Future<void> markConversationRead({
    required String conversationId,
    required String managedAccountId,
  });

  Future<void> markMessagesDelivered(
    String conversationId,
    List<String> messageIds,
  );

  Future<void> markMessagesRead(
    String conversationId,
    List<String> messageIds,
  );

  Future<void> setTyping(String conversationId);

  Future<MediaUploadTask> uploadChatMedia({
    required String conversationId,
    required String messageId,
    required Uint8List bytes,
    required String contentType,
    required String fileName,
  });

  Future<MediaUploadTask> uploadChatThumbnail({
    required String conversationId,
    required String messageId,
    required Uint8List bytes,
    required String contentType,
  });

  // ----- Managed calls -----

  Future<ManagedCall> startCall({
    required String managedAccountId,
    required String conversationId,
    required String peerUid,
    required ManagedCallType type,
  });

  Stream<ManagedCall> watchCall(String callId);

  Future<ManagedCall?> fetchCall(String callId);

  Future<void> endCall({
    required String callId,
    required String byUid,
  });

  Future<void> answerCall(String callId);

  Future<void> markMissed(String callId);

  Future<void> declineCall(String callId);

  Future<List<ManagedCall>> fetchCallHistory(String managedAccountId);

  Stream<void> watchCallChanges(String managedAccountId);

  // ----- Managed status -----

  Stream<List<ManagedStatusGroup>> watchStatuses(String managedAccountId);

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
  });

  Future<MediaUploadTask> uploadStatusMedia({
    required String managedAccountId,
    required String statusId,
    required Uint8List bytes,
    required String contentType,
    required String fileName,
  });

  Future<MediaUploadTask> uploadStatusThumbnail({
    required String managedAccountId,
    required String statusId,
    required Uint8List bytes,
    required String contentType,
  });

  Future<void> markStatusViewed(String statusId);

  Future<void> deleteStatus(String statusId);

  Future<List<ManagedStatusViewer>> fetchStatusViewers(String statusId);
}
