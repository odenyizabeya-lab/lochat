import 'dart:typed_data';

import '../models/chat_message.dart';
import '../models/conversation.dart';

/// Thrown when a conversation is requested with someone who is not (yet) a
/// contact of the signed-in user. Screens map this to a friendly message.
class NotAContactException implements Exception {
  const NotAContactException();
}

/// Media payload for a [MessageType.image], [MessageType.video] or
/// [MessageType.voice] message. [type] must match the requested message type
/// and [url] must be a download URL that the message's participants can reach
/// (Supabase Storage for production).
class MessageMedia {
  const MessageMedia({
    required this.type,
    required this.url,
    this.thumbnailUrl,
    this.durationMs,
    this.width,
    this.height,
    this.fileName,
    this.mimeType,
    this.sizeBytes,
  });

  final MessageType type;
  final String url;
  final String? thumbnailUrl;
  final int? durationMs;
  final double? width;
  final double? height;
  final String? fileName;
  final String? mimeType;
  final int? sizeBytes;
}

/// Handle for an in-flight chat media upload to Supabase Storage.
///
/// Returned by [ChatRepository.uploadChatMedia] so the caller can stream
/// progress, wait for the permanent download URL, or cancel (e.g. the user
/// backs out of the composer mid-upload).
abstract interface class MediaUploadTask {
  /// Fraction of bytes transferred, 0..1 (best effort).
  Stream<double> get progress;

  /// Resolves to the permanent, rules-protected download URL on success.
  Future<String> get url;

  /// Aborts the upload. [url] then completes with an error.
  Future<void> cancel();
}

/// Contract for private 1-to-1 messaging data.
///
/// The UI depends only on this interface; the production implementation is
/// [SupabaseChatRepository]. Tests may supply a fake implementation.
abstract interface class ChatRepository {
  /// Deterministic, order-independent conversation ID for a pair of users.
  /// The same pair always maps to the same conversation, so duplicate
  /// conversations can never be created.
  String conversationIdFor(String a, String b);

  /// Live list of [uid]'s conversations, most recently active first. Emits an
  /// empty list while there are no conversations. Peer profiles are live, so
  /// names and presence stay up to date.
  Stream<List<Conversation>> watchConversations(String uid);

  /// Resolves the conversation with [contactUid], creating it when missing,
  /// and returns its ID. Throws [NotAContactException] when [contactUid] is
  /// not one of [uid]'s contacts.
  Future<String> ensureConversation({
    required String uid,
    required String contactUid,
  });

  /// Appends a message to the conversation and updates its summary (last
  /// message, last sender, and the receiver's unread counter). The message is
  /// written to [messageId] when provided so optimistic UI can reconcile with
  /// the same document.
  ///
  /// Text messages: [text] must be non-empty and [media] must be null.
  /// Media messages: [text] must be empty and [media] must be provided with a
  /// valid [MessageMedia.url] (upload it first via [uploadChatMedia]).
  ///
  /// When replying, [replyToId] plus [replyToType]/[replyToText]/
  /// [replyToSender] describe the quoted message so both sides can render the
  /// quote without a second lookup.
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
  });

  /// Removes a message for everyone in the conversation. Only the original
  /// sender may delete it (enforced server-side).
  Future<void> deleteMessage({
    required String conversationId,
    required String messageId,
  });

  /// Uploads [bytes] to the conversation's private media store and returns a
  /// handle with progress / result / cancellation. The file is stored at
  /// `chat_media/{conversationId}/{messageId}` so re-sending the same
  /// [messageId] is idempotent and retries reuse the same object.
  Future<MediaUploadTask> uploadChatMedia({
    required String conversationId,
    required String messageId,
    required Uint8List bytes,
    required String contentType,
    required String fileName,
  });

  /// Uploads a small poster (e.g. a video thumbnail) for [messageId] and
  /// returns a handle whose [MediaUploadTask.url] is the permanent download
  /// URL. Stored at `chat_media/{conversationId}/{messageId}_thumb` so
  /// retries reuse the same object.
  Future<MediaUploadTask> uploadChatThumbnail({
    required String conversationId,
    required String messageId,
    required Uint8List bytes,
    required String contentType,
  });

  /// Latest messages, ascending by creation time, capped at [limit].
  Stream<List<ChatMessage>> watchMessages(String conversationId,
      {int limit = 100});

  /// Older messages that precede [before], ascending, capped at [limit].
  Future<List<ChatMessage>> fetchMessagesBefore(
    String conversationId,
    ChatMessage before, {
    int limit = 50,
  });

  /// Resets [uid]'s unread counter in the conversation summary.
  Future<void> markConversationRead({
    required String conversationId,
    required String uid,
  });

  /// Marks messages as delivered to the receiver's device (status update
  /// only, no unread changes).
  Future<void> markMessagesDelivered({
    required String conversationId,
    required List<String> messageIds,
  });

  /// Marks messages as read by the receiver (status update only, no unread
  /// changes; call [markConversationRead] to reset the badge).
  Future<void> markMessagesRead({
    required String conversationId,
    required List<String> messageIds,
  });

  /// Registers (or refreshes) an FCM device token for the user. Idempotent:
  /// re-registering the same token just updates it. Used by the push
  /// notification Cloud Function to reach this device.
  Future<void> registerFcmToken({required String uid, required String token});

  /// Signals that [uid] is actively typing in the conversation.
  ///
  /// The stamp expires on the server after a few seconds, so callers should
  /// invoke this repeatedly (throttled) while the user keeps typing. Sending a
  /// message clears the sender's own stamp.
  Future<void> setTyping({
    required String conversationId,
    required String uid,
  });

  /// Removes an FCM device token (called when the user signs out on this
  /// device so the previous user stops receiving pushes here).
  Future<void> unregisterFcmToken({required String uid, required String token});
}
