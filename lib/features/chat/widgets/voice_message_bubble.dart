import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../../../core/utils/time_utils.dart';
import '../models/chat_message.dart';
import '../models/voice_effect.dart';
import 'bubble_frame.dart';
import 'reply_preview.dart';
import 'voice_messages_player.dart';
import 'whatsapp_style.dart';

/// Renders a WhatsApp-style voice message bubble: a play/pause control, a
/// decorative waveform that fills as the clip plays, the elapsed/total
/// duration, and the standard time + delivery ticks footer.
///
/// Tapping the bubble toggles playback on the shared [VoiceMessagesPlayer].
class VoiceMessageBubble extends StatelessWidget {
  const VoiceMessageBubble({
    super.key,
    required this.message,
    required this.fromMe,
    required this.player,
    this.onLongPress,
    this.onReplyTap,
  });

  final ChatMessage message;
  final bool fromMe;
  final VoiceMessagesPlayer player;
  final VoidCallback? onLongPress;
  final VoidCallback? onReplyTap;

  @override
  Widget build(BuildContext context) {
    final WhatsAppStyle style = WhatsAppStyle.of(context);
    final Color foreground = style.text;
    final Color bubble = bubbleColorFor(style, fromMe);
    final bool hasReply = message.replyToId != null;

    final Duration messageDuration = Duration(
      milliseconds: message.durationMs ?? 0,
    );

    return BubbleFrame(
      fromMe: fromMe,
      bubbleColor: bubble,
      onLongPress: onLongPress,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      child: Opacity(
        opacity: message.isPending ? 0.6 : 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
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
              const SizedBox(height: 4),
            ],
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _PlayButton(
                  foreground: foreground,
                  active: player.isActive(message.id),
                  playing: player.playing,
                  loading: player.loading,
                  onTap: () {
                    final String? url = message.mediaUrl;
                    if (url == null) return;
                    unawaited(
                      player.toggle(
                        messageId: message.id,
                        url: url,
                      ),
                    );
                  },
                ),
                const SizedBox(width: 8),
                _Waveform(
                  seed: message.id.hashCode,
                  active: player.isActive(message.id),
                  progress: player.isActive(message.id)
                      ? _progress(player, messageDuration)
                      : 0,
                  foreground: foreground,
                  tinted: bubble,
                ),
                const SizedBox(width: 8),
                _DurationText(
                  active: player.isActive(message.id),
                  position: player.position,
                  total: messageDuration,
                  color: foreground,
                ),
                if (voiceEffectPresetForId(message.voiceEffect) != null)
                  _VoiceEffectBadge(
                    effect: voiceEffectPresetForId(message.voiceEffect)!,
                    foreground: foreground,
                  ),
              ],
            ),
            const SizedBox(height: 2),
            _MessageFooter(
              message: message,
              fromMe: fromMe,
              style: style,
            ),
          ],
        ),
      ),
    );
  }

  double _progress(VoiceMessagesPlayer player, Duration total) {
    if (total.inMilliseconds <= 0) return 0;
    final double raw = player.position.inMilliseconds / total.inMilliseconds;
    return raw.clamp(0, 1);
  }
}

/// Circular play/pause (or loading spinner) button for the bubble.
class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.foreground,
    required this.active,
    required this.playing,
    required this.loading,
    required this.onTap,
  });

  final Color foreground;
  final bool active;
  final bool playing;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color fill = foreground.withValues(alpha: 0.18);
    Widget child;
    if (loading) {
      child = SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2.4,
          color: foreground,
        ),
      );
    } else {
      child = Icon(
        active && playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
        color: foreground,
        size: 28,
      );
    }
    return InkResponse(
      onTap: onTap,
      radius: 24,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
        child: Center(child: child),
      ),
    );
  }
}

/// Decorative waveform bars; the played portion is filled in [foreground],
/// the rest in a translucent tint.
class _Waveform extends StatelessWidget {
  const _Waveform({
    required this.seed,
    required this.active,
    required this.progress,
    required this.foreground,
    required this.tinted,
  });

  final int seed;
  final bool active;
  final double progress;
  final Color foreground;
  final Color tinted;

  static const int _barCount = 26;

  @override
  Widget build(BuildContext context) {
    final Random random = Random(seed);
    final List<double> heights = List<double>.generate(
      _barCount,
      (int index) => 5 + (random.nextDouble() * 13),
    );
    final int playedBars =
        active ? (progress * _barCount).round().clamp(0, _barCount) : 0;

    return SizedBox(
      width: 92,
      height: 26,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List<Widget>.generate(_barCount, (int index) {
          final bool played = index < playedBars;
          return Container(
            width: 2.2,
            height: heights[index],
            decoration: BoxDecoration(
              color: played ? foreground : tinted.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(1),
            ),
          );
        }),
      ),
    );
  }
}

/// Shows the elapsed/total duration while active, otherwise the total.
class _DurationText extends StatelessWidget {
  const _DurationText({
    required this.active,
    required this.position,
    required this.total,
    required this.color,
  });

  final bool active;
  final Duration position;
  final Duration total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final Duration shown = active ? position : total;
    return Text(
      formatDuration(shown),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
    );
  }
}

/// Small pill showing the voice-changer effect applied to a clip.
class _VoiceEffectBadge extends StatelessWidget {
  const _VoiceEffectBadge({required this.effect, required this.foreground});

  final VoiceEffectPreset effect;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: foreground.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            effect.isMan ? Icons.man_rounded : Icons.woman_rounded,
            size: 12,
            color: foreground,
          ),
          const SizedBox(width: 3),
          Text(
            effect.label,
            style: TextStyle(
              color: foreground,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// The standard time + delivery tick footer shared with text bubbles.
class _MessageFooter extends StatelessWidget {
  const _MessageFooter({
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
