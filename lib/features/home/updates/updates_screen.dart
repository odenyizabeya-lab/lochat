import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/time_utils.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../profile/models/user_profile.dart';
import '../../profile/profile_scope.dart';
import '../../status/models/status_update.dart';
import '../../status/status_controller.dart';
import '../../status/status_scope.dart';
import '../../status/widgets/status_avatar_ring.dart';

/// Updates tab: the status hub.
///
/// Shows the caller's own statuses ("My status"), then live updates from
/// contacts (newest first, unseen ones first), and the viewer/composer
/// entry points. Statuses disappear after 24 hours (enforced server-side).
class UpdatesScreen extends StatelessWidget {
  const UpdatesScreen({super.key});

  void _openComposer(BuildContext context) {
    context.push(AppRoutes.statusComposer);
  }

  void _openViewer(
    BuildContext context, {
    required StatusGroup group,
    required bool isOwn,
  }) {
    context.push(
      AppRoutes.statusViewer,
      extra: <String, dynamic>{
        'group': group,
        'isOwn': isOwn,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final StatusController statuses = StatusScope.of(context);
    final String? myUid = statuses.uid;
    final UserProfile? profile = ProfileScope.maybeOf(context)?.profile;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Updates'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Add status',
            icon: const Icon(Icons.photo_camera_outlined),
            onPressed: () => _openComposer(context),
          ),
          PopupMenuButton<String>(
            tooltip: 'More options',
            onSelected: (String value) {
              switch (value) {
                case 'add-status':
                  _openComposer(context);
                case 'settings':
                  context.push(AppRoutes.settings);
              }
            },
            itemBuilder: (BuildContext context) =>
                <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'add-status',
                child: _MenuRow(
                  icon: Icons.add_a_photo_outlined,
                  label: 'Add status',
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'settings',
                child: _MenuRow(
                  icon: Icons.settings_outlined,
                  label: 'Settings',
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<List<StatusGroup>>(
          stream: statuses.watchStatuses(),
          builder: (BuildContext context,
              AsyncSnapshot<List<StatusGroup>> snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Text(
                  'Could not load statuses.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.error,
                  ),
                ),
              );
            }
            final List<StatusGroup> groups =
                snapshot.data ?? const <StatusGroup>[];

            final List<StatusGroup> myStatuses =
                myUid == null ? const <StatusGroup>[] : _ownGroups(groups, myUid);
            final StatusGroup? myGroup = myStatuses.isNotEmpty
                ? myStatuses.first
                : null;
            final List<StatusGroup> contacts = groups
                .where((StatusGroup g) => g.author.uid != myUid)
                .toList()
              ..sort((StatusGroup a, StatusGroup b) {
                if (a.hasUnseen != b.hasUnseen) return a.hasUnseen ? -1 : 1;
                return b.statuses.first.createdAt
                    .compareTo(a.statuses.first.createdAt);
              });

            return ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: <Widget>[
                _SectionHeader(
                  theme: theme,
                  scheme: scheme,
                  label: 'STATUS',
                ),
                _MyStatusRow(
                  profile: profile,
                  count: myGroup?.statuses.length ?? 0,
                  hasStatus: myGroup != null,
                  onTap: () {
                    if (myGroup != null) {
                      _openViewer(context, group: myGroup, isOwn: true);
                    } else {
                      _openComposer(context);
                    }
                  },
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'Your status updates disappear after 24 hours.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                _SectionHeader(
                  theme: theme,
                  scheme: scheme,
                  label: 'RECENT UPDATES',
                ),
                if (contacts.isEmpty)
                  const EmptyStateView(
                    icon: Icons.donut_large_outlined,
                    title: 'No recent updates',
                    message:
                        'When your contacts post updates, they will appear here.',
                  )
                else
                  for (final StatusGroup group in contacts)
                    _ContactStatusRow(
                      group: group,
                      onTap: () =>
                          _openViewer(context, group: group, isOwn: false),
                    ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Text(
                    'Your status and last seen are private. Only your contacts '
                    'can see your status updates.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  List<StatusGroup> _ownGroups(List<StatusGroup> groups, String uid) {
    final List<StatusGroup> own =
        groups.where((StatusGroup g) => g.author.uid == uid).toList();
    own.sort((StatusGroup a, StatusGroup b) =>
        b.statuses.first.createdAt.compareTo(a.statuses.first.createdAt));
    return own;
  }
}

class _MyStatusRow extends StatelessWidget {
  const _MyStatusRow({
    required this.profile,
    required this.count,
    required this.hasStatus,
    required this.onTap,
  });

  final UserProfile? profile;
  final int count;
  final bool hasStatus;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final String name = profile?.displayName.isNotEmpty == true
        ? profile!.displayName
        : (profile?.username ?? 'You');

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          StatusAvatarRing(
            name: name,
            photoURL: profile?.photoURL,
            size: 52,
            hasStatus: hasStatus,
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: AppColors.live,
                shape: BoxShape.circle,
                border: Border.all(color: scheme.surface, width: 2),
              ),
              child: const Icon(
                Icons.add_rounded,
                size: 16,
                color: Color(0xFF06332B),
              ),
            ),
          ),
        ],
      ),
      title: Text(
        'My status',
        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        hasStatus
            ? (count == 1 ? '1 update' : '$count updates')
            : 'Tap to add status update',
        style: theme.textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      onTap: onTap,
    );
  }
}

class _ContactStatusRow extends StatelessWidget {
  const _ContactStatusRow({required this.group, required this.onTap});

  final StatusGroup group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final String name = group.author.displayName.isNotEmpty
        ? group.author.displayName
        : group.author.username;
    final StatusUpdate latest = group.statuses.first;
    final int extra = group.statuses.length - 1;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: SizedBox(
        width: 58,
        height: 58,
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            StatusAvatarRing(
              name: name,
              photoURL: group.author.photoURL,
              size: 52,
              hasStatus: true,
              seen: !group.hasUnseen,
            ),
            if (extra > 0)
              Positioned(
                right: -4,
                bottom: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Text(
                    '+$extra',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      title: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        _relativeTime(latest.createdAt),
        style: theme.textTheme.bodySmall?.copyWith(
          color: group.hasUnseen
              ? AppColors.liveDeep
              : scheme.onSurfaceVariant,
          fontWeight: group.hasUnseen ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      onTap: onTap,
    );
  }

  String _relativeTime(DateTime time) {
    final Duration diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes} ${diff.inMinutes == 1 ? 'min' : 'mins'} ago';
    }
    if (diff.inHours < 24) {
      return '${diff.inHours} ${diff.inHours == 1 ? 'hour' : 'hours'} ago';
    }
    return formatChatTime(time);
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.theme,
    required this.scheme,
    required this.label,
  });

  final ThemeData theme;
  final ColorScheme scheme;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon,
            size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      ],
    );
  }
}
