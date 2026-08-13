import 'package:flutter/material.dart';

/// Reusable circular user avatar with a photo, or an initials fallback when
/// no photo is set or the image fails to load.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.name,
    this.photoURL,
    this.size = 48,
    this.backgroundColor,
    this.foregroundColor,
  });

  final String name;
  final String? photoURL;
  final double size;

  /// Optional initials badge colors (fall back to the theme).
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final String initial =
        name.trim().isEmpty ? 'L' : name.trim()[0].toUpperCase();
    final bool hasPhoto = photoURL != null && photoURL!.isNotEmpty;

    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: hasPhoto
            ? Image.network(
                photoURL!,
                fit: BoxFit.cover,
                errorBuilder:
                    (BuildContext context, Object error, StackTrace? stack) {
                  return _Initials(
                    initial: initial,
                    scheme: scheme,
                    theme: theme,
                    backgroundColor: backgroundColor,
                    foregroundColor: foregroundColor,
                  );
                },
              )
            : _Initials(
                initial: initial,
                scheme: scheme,
                theme: theme,
                backgroundColor: backgroundColor,
                foregroundColor: foregroundColor,
              ),
      ),
    );
  }
}

class _Initials extends StatelessWidget {
  const _Initials({
    required this.initial,
    required this.scheme,
    required this.theme,
    this.backgroundColor,
    this.foregroundColor,
  });

  final String initial;
  final ColorScheme scheme;
  final ThemeData theme;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final Color bg = backgroundColor ?? scheme.primaryContainer;
    final Color fg = foregroundColor ?? scheme.onPrimaryContainer;
    return Container(
      color: bg,
      alignment: Alignment.center,
      child: Text(
        initial,
        style: theme.textTheme.titleLarge?.copyWith(
          color: fg,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
