/// The kind of content a [ChatMessage] carries.
enum MessageType { text, image, video, voice }

/// Delivery states a private message moves through, in order.
enum ChatMessageStatus { sent, delivered, read }

/// A single private message inside a conversation.
///
/// Text messages only carry [text]. Media messages carry [mediaUrl] (a
/// Supabase Storage download URL) plus optional metadata ([thumbnailUrl],
/// [durationMs], [width]/[height], [fileName], [mimeType], [sizeBytes]); for
/// media messages [text] is always empty (captions are not supported yet).
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderUid,
    required this.createdAt,
    this.type = MessageType.text,
    this.text = '',
    this.mediaUrl,
    this.thumbnailUrl,
    this.durationMs,
    this.width,
    this.height,
    this.fileName,
    this.mimeType,
    this.sizeBytes,
    this.status = ChatMessageStatus.sent,
    this.isPending = false,
    this.replyToId,
    this.replyToType,
    this.replyToText,
    this.replyToSender,
  });

  final String id;
  final String conversationId;
  final String senderUid;
  final DateTime createdAt;

  /// The kind of content this message carries.
  final MessageType type;

  /// Body text for text messages; always empty for media messages.
  final String text;

  /// Private download URL for image/video/voice messages.
  final String? mediaUrl;

  /// Small poster image (video thumbnails).
  final String? thumbnailUrl;

  /// Playback length in milliseconds (video/voice messages).
  final int? durationMs;

  /// Source dimensions in pixels (image/video messages).
  final double? width;
  final double? height;

  /// Original file name of the uploaded attachment.
  final String? fileName;

  /// Media MIME type (e.g. image/jpeg, video/mp4, audio/aac).
  final String? mimeType;

  /// Uploaded file size in bytes.
  final int? sizeBytes;

  /// Delivery progress: sent -> delivered -> read. Only the receiver's device
  /// advances it, so the sender's UI can render single/double ticks.
  final ChatMessageStatus status;

  /// True while the client is still writing this message to Firestore
  /// (e.g. offline). The UI renders a dimmed bubble until it syncs.
  final bool isPending;

  /// ID of the message this one replies to (null when not a reply).
  final String? replyToId;

  /// [MessageType.name] of the quoted message.
  final String? replyToType;

  /// Body text of the quoted message (text messages only).
  final String? replyToText;

  /// Display name of the quoted message's author at reply time.
  final String? replyToSender;
}
