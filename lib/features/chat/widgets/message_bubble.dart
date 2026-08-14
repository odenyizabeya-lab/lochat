import 'package:flutter/material.dart';

import '../../../../core/utils/time_utils.dart';
import '../../../../shared/languages.dart';
import '../models/chat_message.dart';
import 'bubble_frame.dart';
import 'reply_preview.dart';
import 'whatsapp_style.dart';

/// WhatsApp-style text message bubble: rounded green/white box with a tail,
/// an optional reply quote, and the time + delivery ticks inline.
///
/// The bubble can show a translation instead of the original wording in two
/// situations:
///   * [autoTranslation] is the receiver's device-side translation of a
///     foreign-language message (never persisted), with [autoTranslationLabel]
///     describing it (e.g. "Translated from Spanish").
///   * the message itself was sent via "translate before sending", so
///     `message.originalText` holds the sender's original wording.
/// Either way [showOriginal] / [onToggleOriginal] switch the bubble between
/// the translation and the original text.
class WhatsAppTextBubble extends StatelessWidget {
  const WhatsAppTextBubble({
    super.key,
    required this.message,
    required this.fromMe,
    this.onLongPress,
    this.onReplyTap,
    this.autoTranslation,
    this.autoTranslationLabel,
    this.showOriginal = false,
    this.onToggleOriginal,
  });

  final ChatMessage message;
  final bool fromMe;
  final VoidCallback? onLongPress;
  final VoidCallback? onReplyTap;

  /// Device-side translation of a foreign-language incoming message, or null
  /// when the message is shown as written.
  final String? autoTranslation;

  /// Label for [autoTranslation], e.g. "Translated from Spanish".
  final String? autoTranslationLabel;

  /// Whether to show the original wording instead of the translation.
  final bool showOriginal;

  /// Toggles [showOriginal] for the peer's own translate-before-send
  /// messages (which carry [ChatMessage.originalText]).
  final VoidCallback? onToggleOriginal;

  @override
  Widget build(BuildContext context) {
    final WhatsAppStyle style = WhatsAppStyle.of(context);
    final Color bubble = bubbleColorFor(style, fromMe);
    final bool hasReply = message.replyToId != null;

    String displayText = message.text;
    String? note;
    bool canToggle = false;

    if (autoTranslation != null) {
      canToggle = true;
      note = autoTranslationLabel;
      displayText = showOriginal ? message.text : autoTranslation!;
    } else if (message.hasOriginal) {
      canToggle = true;
      if (showOriginal) {
        displayText = message.originalText!;
      } else {
        note = message.sourceLang == null
            ? 'Translated'
            : 'Translated from ${languageNameFor(message.sourceLang)}';
      }
    }

    return BubbleFrame(
      fromMe: fromMe,
      bubbleColor: bubble,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment:
            fromMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (hasReply) ...<Widget>[
            ReplyPreview(
              senderName: message.replyToSender ?? 'Message',
              preview: replyPreviewFromFields(
                  message.replyToType, message.replyToText),
              isOutgoing: fromMe,
              onTap: onReplyTap,
            ),
            const SizedBox(height: 2),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              displayText,
              style: TextStyle(
                color: style.text,
                fontSize: 15.5,
                height: 1.3,
              ),
            ),
          ),
          if (canToggle) ...<Widget>[
            const SizedBox(height: 4),
            InkWell(
              onTap: onToggleOriginal,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                child: Text(
                  showOriginal
                      ? 'Show translation'
                      : '${note ?? 'Translated'} \u00b7 See original',
                  style: TextStyle(
                    color: style.replyAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                    decorationColor: style.replyAccent,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 3),
          _BubbleFooter(message: message, fromMe: fromMe, style: style),
        ],
      ),
    );
  }
}

/// Time + delivery ticks (single / double / blue double) inside the bubble.
class _BubbleFooter extends StatelessWidget {
  const _BubbleFooter({
    required this.message,
    required this.fromMe,
    required this.style,
  });

  final ChatMessage message;
  final bool fromMe;
  final WhatsAppStyle style;

  @override
  Widget build(BuildContext context) {
    final Color tickColor = message.status == ChatMessageStatus.read
        ? style.readTick
        : style.meta;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          formatChatTime(message.createdAt),
          style: TextStyle(color: style.meta, fontSize: 11.5),
        ),
        if (fromMe) ...<Widget>[
          const SizedBox(width: 4),
          Icon(
            message.status == ChatMessageStatus.read ||
                    message.status == ChatMessageStatus.delivered
                ? Icons.done_all_rounded
                : Icons.done_rounded,
            size: 14,
            color: tickColor,
          ),
        ],
      ],
    );
  }
}
