import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Reusable circular user avatar with a photo, or an initials fallback when
/// no photo is set or the image fails to load.
///
/// Since the `profile_photos` bucket is private, [photoURL] is usually an
/// object path (the user's uid); it is resolved to a short-lived signed URL
/// before the image is fetched. Full http(s) URLs are used as-is.
class UserAvatar extends StatefulWidget {
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
  State<UserAvatar> createState() => _UserAvatarState();
}

class _UserAvatarState extends State<UserAvatar> {
  static const int _signedUrlLifetimeSeconds = 3600;

  String? _resolvedURL;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(UserAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photoURL != widget.photoURL) {
      _resolve();
    }
  }

  Future<void> _resolve() async {
    final String? raw = widget.photoURL;
    if (raw == null || raw.isEmpty) {
      _resolvedURL = null;
      return;
    }
    final String? path = _toObjectPath(raw);
    if (path == null) {
      _resolvedURL = raw;
      return;
    }
    try {
      final String url = await Supabase.instance.client.storage
          .from('profile_photos')
          .createSignedUrl(path, _signedUrlLifetimeSeconds);
      if (mounted && _resolvedURL != url) {
        setState(() => _resolvedURL = url);
      }
    } catch (_) {
      if (mounted && _resolvedURL != null) {
        setState(() => _resolvedURL = null);
      }
    }
  }

  /// Returns the object path relative to `profile_photos` for a stored path or
  /// a legacy public URL, or null when [raw] is already a usable URL.
  String? _toObjectPath(String raw) {
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      const String marker = '/object/public/';
      final int index = raw.indexOf(marker);
      if (index == -1) return null;
      final String withBucket = raw.substring(index + marker.length);
      final int slash = withBucket.indexOf('/');
      return slash == -1 ? withBucket : withBucket.substring(slash + 1);
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final String initial =
        widget.name.trim().isEmpty ? 'L' : widget.name.trim()[0].toUpperCase();
    final String? photoURL = _resolvedURL;
    final bool hasPhoto = photoURL != null && photoURL.isNotEmpty;

    return ClipOval(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: hasPhoto
            ? CachedNetworkImage(
                imageUrl: photoURL,
                width: widget.size,
                height: widget.size,
                fit: BoxFit.cover,
                // Decode only enough pixels for the avatar size.
                memCacheWidth: _pixelSize(context, widget.size),
                memCacheHeight: _pixelSize(context, widget.size),
                placeholder: (BuildContext context, String url) => _Initials(
                  initial: initial,
                  scheme: scheme,
                  theme: theme,
                  backgroundColor: widget.backgroundColor,
                  foregroundColor: widget.foregroundColor,
                ),
                errorWidget: (BuildContext context, String url, Object error) =>
                    _Initials(
                  initial: initial,
                  scheme: scheme,
                  theme: theme,
                  backgroundColor: widget.backgroundColor,
                  foregroundColor: widget.foregroundColor,
                ),
              )
            : _Initials(
                initial: initial,
                scheme: scheme,
                theme: theme,
                backgroundColor: widget.backgroundColor,
                foregroundColor: widget.foregroundColor,
              ),
      ),
    );
  }

  static int _pixelSize(BuildContext context, double size) =>
      (size * MediaQuery.devicePixelRatioOf(context)).round();
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
