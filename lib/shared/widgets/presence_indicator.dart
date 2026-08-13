import 'package:flutter/material.dart';

import '../../core/utils/time_utils.dart';

/// Small inline indicator showing a green dot + "Online", or a muted
/// "Last seen ..." label when offline.
class PresenceIndicator extends StatelessWidget {
  const PresenceIndicator({
    super.key,
    required this.isOnline,
    this.lastSeen,
  });

  final bool isOnline;
  final DateTime? lastSeen;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final Color dotColor = isOnline ? const Color(0xFF22C55E) : scheme.outline;
    final String label = isOnline ? 'Online' : formatLastSeen(lastSeen);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}
