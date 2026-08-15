import 'dart:async';
import 'dart:typed_data';

import '../../chat/data/chat_repository.dart';
import '../models/managed_conversation.dart';
import '../models/managed_message.dart';

abstract class ManagedChatRepository {
  Stream<List<ManagedConversation>> watchConversations(String managedAccountId);

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
}
