import 'package:flutter/material.dart';

import '../models/chat_message.dart';
import 'whatsapp_style.dart';

/// Renders the quoted message shown at the top of a reply bubble (and in the
/// composer while a reply is being written), WhatsApp-style: an accent bar, a
/// bold sender line and a one-line preview.
class ReplyPreview extends StatelessWidget {
  const ReplyPreview({
    super.key,
    required this.senderName,
    required this.preview,
    required this.isOutgoing,
    this.onTap,
  });

  /// Display name of the quoted message's author.
  final String senderName;

  /// One-line preview text of the quoted message.
  final String preview;

  /// True when this quote sits on an outgoing (green) bubble.
  final bool isOutgoing;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final WhatsAppStyle style = WhatsAppStyle.of(context);
    final Color textColor = isOutgoing ? style.text : style.text;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: textColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
        border: Border(
          left: BorderSide(color: style.replyAccent, width: 3),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              senderName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: style.replyAccent,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              preview,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: textColor.withValues(alpha: 0.75),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Resolves the one-line preview shown for a quoted [ChatMessage].
String replyPreviewText(ChatMessage? quoted) {
  if (quoted == null) return '';
  return switch (quoted.type) {
    MessageType.image => 'Photo',
    MessageType.video => 'Video',
    MessageType.voice => 'Voice message',
    MessageType.text => quoted.text,
  };
}

/// Resolves the preview for a stored reply from its [type] and [text] fields.
String replyPreviewFromFields(String? type, String? text) {
  return switch (type) {
    'image' => 'Photo',
    'video' => 'Video',
    'voice' => 'Voice message',
    _ => (text == null || text.isEmpty) ? 'Message' : text,
  };
}
