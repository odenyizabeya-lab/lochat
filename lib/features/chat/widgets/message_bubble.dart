import 'package:flutter/material.dart';

import '../../../../core/utils/time_utils.dart';
import '../models/chat_message.dart';
import 'bubble_frame.dart';
import 'reply_preview.dart';
import 'whatsapp_style.dart';

/// WhatsApp-style text message bubble: rounded green/white box with a tail,
/// an optional reply quote, and the time + delivery ticks inline.
class WhatsAppTextBubble extends StatelessWidget {
  const WhatsAppTextBubble({
    super.key,
    required this.message,
    required this.fromMe,
    this.onLongPress,
    this.onReplyTap,
  });

  final ChatMessage message;
  final bool fromMe;
  final VoidCallback? onLongPress;
  final VoidCallback? onReplyTap;

  @override
  Widget build(BuildContext context) {
    final WhatsAppStyle style = WhatsAppStyle.of(context);
    final Color bubble = bubbleColorFor(style, fromMe);
    final bool hasReply = message.replyToId != null;

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
              message.text,
              style: TextStyle(
                color: style.text,
                fontSize: 15.5,
                height: 1.3,
              ),
            ),
          ),
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
