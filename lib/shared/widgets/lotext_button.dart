import 'package:flutter/material.dart';

/// The visual variants of [LoTextButton].
enum LoTextButtonVariant { primary, secondary, outline, text }

/// LoText's standard button with built-in loading and sizing support.
class LoTextButton extends StatelessWidget {
  const LoTextButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = LoTextButtonVariant.primary,
    this.isLoading = false,
    this.isExpanded = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final LoTextButtonVariant variant;
  final bool isLoading;
  final bool isExpanded;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final VoidCallback? onTap = isLoading ? null : onPressed;

    final Color spinnerColor = switch (variant) {
      LoTextButtonVariant.primary => scheme.onPrimary,
      LoTextButtonVariant.secondary => scheme.onSecondaryContainer,
      LoTextButtonVariant.outline || LoTextButtonVariant.text => scheme.primary,
    };

    final Widget child = isLoading
        ? SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: spinnerColor),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: 20),
                const SizedBox(width: 8),
              ],
              Text(label),
            ],
          );

    final RoundedRectangleBorder shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );
    final Size minSize = isExpanded ? const Size.fromHeight(54) : const Size(96, 52);

    final Widget button = switch (variant) {
      LoTextButtonVariant.primary => FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(minimumSize: minSize, shape: shape),
          child: child,
        ),
      LoTextButtonVariant.secondary => FilledButton.tonal(
          onPressed: onTap,
          style: FilledButton.styleFrom(minimumSize: minSize, shape: shape),
          child: child,
        ),
      LoTextButtonVariant.outline => OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(minimumSize: minSize, shape: shape),
          child: child,
        ),
      LoTextButtonVariant.text => TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(minimumSize: minSize, shape: shape),
          child: child,
        ),
    };

    return isExpanded
        ? SizedBox(width: double.infinity, child: button)
        : Center(child: button);
  }
}
