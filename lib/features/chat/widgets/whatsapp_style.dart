import 'package:flutter/material.dart';

/// WhatsApp chat-room palette for LoText.
///
/// The rest of the app keeps its own brand, but the conversation view mirrors
/// WhatsApp's real light/dark colors so it looks identical to the original.
class WhatsAppStyle {
  WhatsAppStyle(this.isDark);

  /// True when the app is in dark mode.
  final bool isDark;

  /// Chat header (app bar) background.
  Color get header =>
      isDark ? const Color(0xFF202C33) : const Color(0xFF008069);

  /// Foreground used on the chat header.
  Color get onHeader => Colors.white;

  /// Subtitle (presence line) color on the chat header.
  Color get onHeaderSub => Colors.white.withValues(alpha: 0.88);

  /// Chat wallpaper base color.
  Color get wallpaperBase =>
      isDark ? const Color(0xFF0B141A) : const Color(0xFFEFE7DD);

  /// Doodle marks drawn over the wallpaper.
  Color get wallpaperDoodle =>
      isDark ? const Color(0xFF111B21) : const Color(0xFFE1D9CB);

  /// Background of messages the signed-in user sent.
  Color get outgoingBubble =>
      isDark ? const Color(0xFF005C4B) : const Color(0xFFD9FDD3);

  /// Background of messages the peer sent.
  Color get incomingBubble =>
      isDark ? const Color(0xFF202C33) : const Color(0xFFFFFFFF);

  /// Message body color on top of either bubble.
  Color get text =>
      isDark ? const Color(0xFFE9EDEF) : const Color(0xFF111B21);

  /// Timestamp / tick color inside bubbles (muted).
  Color get meta =>
      isDark ? const Color(0xFF8696A0) : const Color(0xFF667781);

  /// Blue double tick for messages read by the peer.
  Color get readTick => const Color(0xFF53BDEB);

  /// Accent (left bar / sender name) of a reply quote.
  Color get replyAccent => const Color(0xFF00A884);

  /// Date separator chip text.
  Color get dateText =>
      isDark ? const Color(0xFF8696A0) : const Color(0xFF1C7A63);

  /// Date separator chip background.
  Color get dateChip =>
      isDark ? const Color(0xFF182229) : Colors.white.withValues(alpha: 0.9);

  static WhatsAppStyle of(BuildContext context) =>
      WhatsAppStyle(Theme.of(context).brightness == Brightness.dark);
}
