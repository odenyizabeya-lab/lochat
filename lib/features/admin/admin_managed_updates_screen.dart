import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_routes.dart';
import '../../shared/widgets/empty_state_view.dart';
import './managed_chat_controller.dart';
import './managed_chat_scope.dart';
import './models/managed_status.dart';

/// Updates hub for an admin-managed account: a "My status" row with the
/// account's current statuses (24h expiry), plus a composer entry point.
class AdminManagedUpdatesScreen extends StatefulWidget {
  const AdminManagedUpdatesScreen({
    super.key,
    required this.managedAccountId,
    this.embedded = false,
  });

  final String managedAccountId;

  /// When true the screen is shown inside the chat room tabs and skips its
  /// own Scaffold/AppBar (the hosting screen provides them).
  final bool embedded;

  @override
  State<AdminManagedUpdatesScreen> createState() =>
      _AdminManagedUpdatesScreenState();
}

class _AdminManagedUpdatesScreenState extends State<AdminManagedUpdatesScreen> {
  StreamSubscription<List<ManagedStatusGroup>>? _sub;
  ManagedStatusGroup? _group;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sub != null) return;
    final ManagedChatController chat = ManagedChatScope.of(context);
    _sub = chat.watchStatuses().listen((List<ManagedStatusGroup> groups) {
      if (!mounted) return;
      setState(() => _group = groups.isNotEmpty ? groups.first : null);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _openComposer() {
    context.push(AppRoutes.adminStatusComposer, extra: <String, dynamic>{
      'managedAccountId': widget.managedAccountId,
    });
  }

  void _openViewer() {
    final ManagedStatusGroup? group = _group;
    if (group == null || group.statuses.isEmpty) {
      _openComposer();
      return;
    }
    context.push(AppRoutes.adminStatusViewer, extra: <String, dynamic>{
      'managedAccountId': widget.managedAccountId,
      'statuses': group.statuses,
      'startIndex': 0,
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final ManagedStatusGroup? group = _group;
    final List<ManagedStatus> statuses =
        group?.statuses ?? const <ManagedStatus>[];
    final int count = statuses.length;

    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(
              title: const Text('Updates'),
              actions: <Widget>[
                IconButton(
                  tooltip: 'Add status',
                  icon: const Icon(Icons.photo_camera_outlined),
                  onPressed: _openComposer,
                ),
              ],
            ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
              child: Text(
                'STATUS',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            ListTile(
              leading: _MyStatusRing(
                count: count,
                onTap: _openViewer,
              ),
              title: Text(
                count > 0 ? 'My status' : 'My status',
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                count > 0
                    ? 'Tap to view ${count == 1 ? 'update' : 'updates'}'
                    : 'Add to your status',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              trailing: Icon(
                count > 0
                    ? Icons.chevron_right_rounded
                    : Icons.add_a_photo_outlined,
                color: scheme.onSurfaceVariant,
              ),
              onTap: count > 0 ? _openViewer : _openComposer,
            ),
            if (count == 0)
              const Padding(
                padding: EdgeInsets.only(top: 48),
                child: EmptyStateView(
                  icon: Icons.add_a_photo_outlined,
                  title: 'No status yet',
                  message:
                      'Post a photo, video, or text status that disappears after 24 hours.',
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openComposer,
        icon: const Icon(Icons.edit_rounded),
        label: const Text('Add status'),
      ),
    );
  }
}

class _MyStatusRing extends StatelessWidget {
  const _MyStatusRing({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: count > 0
                ? scheme.primary
                : scheme.outlineVariant,
            width: 2.5,
          ),
        ),
        child: CircleAvatar(
          radius: 22,
          backgroundColor: count > 0
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest,
          child: Icon(
            count > 0 ? Icons.done_all_rounded : Icons.add_rounded,
            color: count > 0
                ? scheme.onPrimaryContainer
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}