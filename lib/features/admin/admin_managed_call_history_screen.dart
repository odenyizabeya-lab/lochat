import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_routes.dart';
import '../../core/utils/time_utils.dart';
import '../../shared/widgets/empty_state_view.dart';
import '../../shared/widgets/error_view.dart';
import '../../shared/widgets/loading_view.dart';
import '../../shared/widgets/user_avatar.dart';
import './managed_chat_controller.dart';
import './managed_chat_scope.dart';
import './models/managed_call.dart';
import './models/managed_conversation.dart';

/// Call history for an admin-managed account, newest first. Refreshes live
/// through the realtime stream of `managed_account_calls`.
class AdminManagedCallHistoryScreen extends StatefulWidget {
  const AdminManagedCallHistoryScreen({
    super.key,
    required this.managedAccountId,
    this.embedded = false,
  });

  final String managedAccountId;

  /// When true the screen is shown inside the chat room tabs and skips its
  /// own Scaffold/AppBar (the hosting screen provides them).
  final bool embedded;

  @override
  State<AdminManagedCallHistoryScreen> createState() =>
      _AdminManagedCallHistoryScreenState();
}

class _AdminManagedCallHistoryScreenState
    extends State<AdminManagedCallHistoryScreen> {
  List<ManagedCall>? _calls;
  bool _error = false;
  StreamSubscription<void>? _changesSub;
  Map<String, String> _peerNames = <String, String>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _subscribe();
  }

  void _subscribe() {
    if (_changesSub != null) return;
    final ManagedChatController chat = ManagedChatScope.of(context);
    unawaited(_refresh());
    _changesSub = chat.watchCallChanges().listen((_) => unawaited(_refresh()));
  }

  Future<void> _refresh() async {
    final ManagedChatController chat = ManagedChatScope.of(context);
    try {
      final List<ManagedCall> calls = await chat.fetchCallHistory();
      final Map<String, String> names = <String, String>{};
      await for (final List<ManagedConversation> conversations
          in chat.watchConversations().take(1)) {
        for (final ManagedConversation conversation in conversations) {
          names[conversation.id] = conversation.peerDisplayName.isNotEmpty
              ? conversation.peerDisplayName
              : conversation.peerUsername;
        }
      }
      if (mounted) {
        setState(() {
          _calls = calls;
          _peerNames = names;
          _error = false;
        });
      }
    } on Exception {
      if (mounted) setState(() => _error = true);
    }
  }

  @override
  void dispose() {
    _changesSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(title: const Text('Call history')),
      body: SafeArea(child: _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_error && _calls == null) {
      return ErrorView(
        title: 'Could not load call history',
        onRetry: () {
          setState(() => _error = false);
          unawaited(_refresh());
        },
      );
    }
    if (_calls == null) {
      return const LoadingView(message: 'Loading calls\u2026');
    }
    if (_calls!.isEmpty) {
      return const EmptyStateView(
        icon: Icons.call_outlined,
        title: 'No calls yet',
        message:
            'Voice and video calls made from this account will show up here.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _calls!.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 88),
      itemBuilder: (BuildContext context, int index) {
        return _ManagedCallTile(
          call: _calls![index],
          peerName: _peerNames[_calls![index].conversationId] ?? 'LoText call',
          managedAccountId: widget.managedAccountId,
        );
      },
    );
  }
}

class _ManagedCallTile extends StatelessWidget {
  const _ManagedCallTile({
    required this.call,
    required this.peerName,
    required this.managedAccountId,
  });

  final ManagedCall call;
  final String peerName;
  final String managedAccountId;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool missed = call.isMissed;
    final Color accent = missed ? scheme.error : scheme.primary;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Stack(
        children: <Widget>[
          UserAvatar(name: peerName, size: 48),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: accent,
                shape: BoxShape.circle,
                border: Border.all(color: scheme.surface, width: 2),
              ),
              child: Icon(
                call.isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                size: 12,
                color: missed ? scheme.onError : scheme.onPrimary,
              ),
            ),
          ),
        ],
      ),
      title: Text(
        peerName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyLarge?.copyWith(
          fontWeight: missed ? FontWeight.w700 : FontWeight.w600,
        ),
      ),
      subtitle: Text(
        _subtitle(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: missed ? accent : scheme.onSurfaceVariant,
          fontWeight: missed ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      trailing: Text(
        formatChatTime(call.createdAt),
        style: theme.textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      onTap: () => context.push(AppRoutes.adminChat, extra: <String, dynamic>{
        'conversationId': call.conversationId,
        'managedAccountId': managedAccountId,
      }),
    );
  }

  String _subtitle() {
    final String type = call.isVideo ? 'video call' : 'voice call';
    switch (call.status) {
      case ManagedCallStatus.missed:
        return 'Missed $type';
      case ManagedCallStatus.declined:
        return 'Declined $type';
      case ManagedCallStatus.ringing:
        return 'Outgoing $type';
      case ManagedCallStatus.active:
      case ManagedCallStatus.ended:
        final Duration? duration = call.duration;
        final String durationText = (duration != null &&
                duration.inSeconds >= 1)
            ? ' \u00b7 ${formatDuration(duration)}'
            : '';
        return 'Outgoing $type$durationText';
    }
  }
}