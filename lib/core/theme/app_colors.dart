import 'package:flutter/material.dart';

/// LoText brand palette. Used directly for the logo and as the seed
/// for the Material color schemes in [AppTheme].
abstract final class AppColors {
  /// Primary brand color (blue, matching the LoText logo).
  static const Color brand = Color(0xFF0741F7);

  /// Darker shade of the brand color for gradients and emphasis.
  static const Color brandDeep = Color(0xFF062EAD);

  /// Lighter shade of the brand color for accents.
  static const Color brandSoft = Color(0xFF5B8DFF);

  /// Gradient used for the LoText logo mark.
  static const List<Color> brandGradient = <Color>[
    Color(0xFF0A4BFF),
    Color(0xFF0741F7),
  ];

  /// Live accent (teal): online rings, unread badges, typing and call accents.
  /// Kept separate from the indigo brand so "live" states are unmistakable,
  /// while staying an original LoText color rather than a WhatsApp copy.
  static const Color live = Color(0xFF2DD4BF);
  static const Color liveDeep = Color(0xFF0F766E);

  /// Dark messenger chrome.
  static const Color darkScaffold = Color(0xFF0C0E12);
  static const Color darkSurface = Color(0xFF15181E);
  static const Color darkSurfaceHigh = Color(0xFF1C2027);
  static const Color darkBorder = Color(0xFF262B33);

  /// Light messenger chrome.
  static const Color lightScaffold = Color(0xFFF2F3F6);
  static const Color lightSurface = Color(0xFFFFFFFF);
}
