import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/utils/time_utils.dart';
import '../models/chat_message.dart';
import 'bubble_frame.dart';
import 'reply_preview.dart';
import 'whatsapp_style.dart';

/// Loads a network image with a spinner while downloading and a broken-image
/// placeholder on failure.
class MediaImage extends StatelessWidget {
  const MediaImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Widget fallback = Container(
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(
        Icons.broken_image_outlined,
        color: scheme.onSurfaceVariant,
        size: 32,
      ),
    );
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: Image.network(
        url,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
            fallback,
        loadingBuilder: (BuildContext context, Widget child,
            ImageChunkEvent? loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            width: width,
            height: height,
            color: scheme.surfaceContainerHighest,
            alignment: Alignment.center,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded /
                      loadingProgress.expectedTotalBytes!
                  : null,
            ),
          );
        },
      ),
    );
  }
}

/// A chat bubble for an image message, styled like WhatsApp: the photo on the
/// bubble background with the time + ticks overlaid on the corner.
class ImageMessageBubble extends StatelessWidget {
  const ImageMessageBubble({
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

  static const double _bubbleWidth = 230;
  static const double _bubbleHeight = 270;

  @override
  Widget build(BuildContext context) {
    final WhatsAppStyle style = WhatsAppStyle.of(context);
    final String? url = message.mediaUrl;
    final bool hasReply = message.replyToId != null;

    return BubbleFrame(
      fromMe: fromMe,
      bubbleColor: bubbleColorFor(style, fromMe),
      onLongPress: onLongPress,
      padding: const EdgeInsets.all(4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (hasReply) ...<Widget>[
            Padding(
              padding: const EdgeInsets.only(left: 4, right: 4, top: 2),
              child: ReplyPreview(
                senderName: message.replyToSender ?? 'Message',
                preview: replyPreviewFromFields(
                    message.replyToType, message.replyToText),
                isOutgoing: fromMe,
                onTap: onReplyTap,
              ),
            ),
            const SizedBox(height: 4),
          ],
          ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: Opacity(
              opacity: message.isPending ? 0.6 : 1,
              child: url == null
                  ? const _MissingMedia()
                  : Stack(
                      children: <Widget>[
                        Positioned.fill(
                          child: GestureDetector(
                            onTap: () => context.push(
                              AppRoutes.photoViewer,
                              extra: <String, dynamic>{
                                'url': url,
                                'id': message.id,
                              },
                            ),
                            child: MediaImage(
                              url: url,
                              width: _bubbleWidth,
                              height: _bubbleHeight,
                            ),
                          ),
                        ),
                        Positioned(
                          right: 8,
                          bottom: 6,
                          child: _MediaFooter(
                            message: message,
                            fromMe: fromMe,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A chat bubble for a video message, WhatsApp-style: thumbnail, play button,
/// duration chip and the time + ticks overlay.
class VideoMessageBubble extends StatelessWidget {
  const VideoMessageBubble({
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
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String? url = message.mediaUrl;
    final String? thumb = message.thumbnailUrl;
    final bool hasReply = message.replyToId != null;

    return BubbleFrame(
      fromMe: fromMe,
      bubbleColor: bubbleColorFor(style, fromMe),
      onLongPress: onLongPress,
      padding: const EdgeInsets.all(4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (hasReply) ...<Widget>[
            Padding(
              padding: const EdgeInsets.only(left: 4, right: 4, top: 2),
              child: ReplyPreview(
                senderName: message.replyToSender ?? 'Message',
                preview: replyPreviewFromFields(
                    message.replyToType, message.replyToText),
                isOutgoing: fromMe,
                onTap: onReplyTap,
              ),
            ),
            const SizedBox(height: 4),
          ],
          ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: Opacity(
              opacity: message.isPending ? 0.6 : 1,
              child: url == null
                  ? const _MissingMedia()
                  : Stack(
                      children: <Widget>[
                        Positioned.fill(
                          child: GestureDetector(
                            onTap: () => _openPlayer(context, url),
                            child: thumb != null
                                ? MediaImage(
                                    url: thumb,
                                    width: ImageMessageBubble._bubbleWidth,
                                    height: ImageMessageBubble._bubbleHeight,
                                  )
                                : Container(
                                    width: ImageMessageBubble._bubbleWidth,
                                    height: ImageMessageBubble._bubbleHeight,
                                    color: scheme.surfaceContainerHighest,
                                    child: Icon(
                                      Icons.play_circle_outline_rounded,
                                      color: scheme.onSurfaceVariant,
                                      size: 56,
                                    ),
                                  ),
                          ),
                        ),
                        Center(
                          child: GestureDetector(
                            onTap: () => _openPlayer(context, url),
                            child: Container(
                              width: 54,
                              height: 54,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.45),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 36,
                              ),
                            ),
                          ),
                        ),
                        if (message.durationMs != null)
                          Positioned(
                            left: 8,
                            bottom: 8,
                            child: _DurationChip(
                              durationMs: message.durationMs!,
                            ),
                          ),
                        Positioned(
                          right: 8,
                          bottom: 6,
                          child: _MediaFooter(
                            message: message,
                            fromMe: fromMe,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  void _openPlayer(BuildContext context, String url) {
    context.push(
      AppRoutes.videoPlayer,
      extra: <String, dynamic>{
        'url': url,
        'messageId': message.id,
      },
    );
  }
}

class _MissingMedia extends StatelessWidget {
  const _MissingMedia();

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      width: ImageMessageBubble._bubbleWidth,
      height: ImageMessageBubble._bubbleHeight,
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(
        Icons.hide_image_outlined,
        color: scheme.onSurfaceVariant,
        size: 40,
      ),
    );
  }
}

/// Time + delivery ticks overlaid on the corner of a media bubble.
class _MediaFooter extends StatelessWidget {
  const _MediaFooter({required this.message, required this.fromMe});

  final ChatMessage message;
  final bool fromMe;

  @override
  Widget build(BuildContext context) {
    final WhatsAppStyle style = WhatsAppStyle.of(context);
    final Color textColor = message.status == ChatMessageStatus.read
        ? style.readTick
        : Colors.white;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          formatChatTime(message.createdAt),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: textColor,
                shadows: const <Shadow>[
                  Shadow(color: Colors.black54, blurRadius: 3),
                ],
              ),
        ),
        if (fromMe) ...<Widget>[
          const SizedBox(width: 3),
          Icon(
            message.status == ChatMessageStatus.read ||
                    message.status == ChatMessageStatus.delivered
                ? Icons.done_all_rounded
                : Icons.done_rounded,
            size: 14,
            color: textColor,
          ),
        ],
      ],
    );
  }
}

class _DurationChip extends StatelessWidget {
  const _DurationChip({required this.durationMs});

  final int durationMs;

  @override
  Widget build(BuildContext context) {
    final Duration duration = Duration(milliseconds: durationMs);
    final String minutes = duration.inMinutes.toString();
    final String seconds =
        (duration.inSeconds % 60).toString().padLeft(2, '0');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$minutes:$seconds',
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: Colors.white),
      ),
    );
  }
}
