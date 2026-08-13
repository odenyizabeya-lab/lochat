import 'package:flutter/material.dart';

/// Consistent app-wide snackbars.
abstract final class AppSnackbars {
  static void showInfo(BuildContext context, String message) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), backgroundColor: scheme.inverseSurface),
      );
  }

  static void showError(BuildContext context, String message) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), backgroundColor: scheme.error),
      );
  }
}
