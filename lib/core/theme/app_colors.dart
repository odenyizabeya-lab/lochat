import 'package:flutter/material.dart';

/// LoText brand palette. Used directly for the logo and as the seed
/// for the Material color schemes in [AppTheme].
abstract final class AppColors {
  /// Primary brand color (indigo).
  static const Color brand = Color(0xFF4F46E5);

  /// Darker shade of the brand color for gradients and emphasis.
  static const Color brandDeep = Color(0xFF3730A3);

  /// Lighter shade of the brand color for accents.
  static const Color brandSoft = Color(0xFF818CF8);

  /// Gradient used for the LoText logo mark.
  static const List<Color> brandGradient = <Color>[
    Color(0xFF8B5CF6),
    Color(0xFF4F46E5),
  ];
}
