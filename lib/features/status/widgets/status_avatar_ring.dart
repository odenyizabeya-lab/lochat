import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/user_avatar.dart';

/// A circular avatar wrapped in a gradient "story" ring, in the style of
/// WhatsApp statuses.
///
/// [hasStatus] draws a colorful gradient ring; when false the plain avatar is
/// shown (the owner has not posted yet). [seen] fades the ring to a neutral
/// grey once everything has been viewed.
class StatusAvatarRing extends StatelessWidget {
  const StatusAvatarRing({
    super.key,
    required this.name,
    this.photoURL,
    this.size = 52,
    this.hasStatus = false,
    this.seen = false,
  });

  final String name;
  final String? photoURL;
  final double size;
  final bool hasStatus;
  final bool seen;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Widget avatar = UserAvatar(
      name: name,
      photoURL: photoURL,
      size: size,
    );
    if (!hasStatus) return avatar;

    final List<Color> colors = seen
        ? <Color>[scheme.outlineVariant, scheme.outlineVariant]
        : const <Color>[
            Color(0xFF8B5CF6),
            Color(0xFF4F46E5),
            AppColors.live,
          ];
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: avatar,
    );
  }
}
