import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/utils/time_utils.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/loading_view.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../chat/chat_scope.dart';
import '../../chat/models/conversation.dart';
import '../../profile/models/user_profile.dart';
import '../call_scope.dart';
import '../models/call.dart';

/// Voice and video call history for the signed-in user (as caller or callee),
/// newest first. Refreshes live through [CallSignalingService.watchCallChanges].
class CallHistoryScreen extends StatefulWidget {
  const CallHistoryScreen({super.key});

  @override
  State<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends State<CallHistoryScreen> {
  List<Call>? _calls;
  bool _error = false;
  String? _uid;
  StreamSubscription<void>? _changesSub;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Resolve the scope here (not initState) so `ChatScope.maybeOf` may
    // register its inherited dependency, then subscribe exactly once.
    final String? uid = ChatScope.maybeOf(context)?.uid;
    if (uid == null || uid == _uid) return;
    _subscribe(uid);
  }

  void _subscribe(String uid) {
    _uid = uid;
    unawaited(_refresh());
    _changesSub = CallScope.of(context)
        .signaling
        .watchCallChanges(uid: uid)
        .listen((_) => unawaited(_refresh()));
  }

  Future<void> _refresh() async {
    final String? uid = _uid;
    if (uid == null) return;
    try {
      final List<Call> calls =
          await CallScope.of(context).signaling.fetchCallHistory(uid: uid);
      if (mounted) {
        setState(() {
          _calls = calls;
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
      appBar: AppBar(title: const Text('Calls')),
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
            'Voice and video calls you make or receive will show up here.',
      );
    }

    return StreamBuilder<List<Conversation>>(
      stream: ChatScope.of(context).watchConversations(),
      builder: (BuildContext context, AsyncSnapshot<List<Conversation>> snapshot) {
        final Map<String, UserProfile> peers = <String, UserProfile>{};
        for (final Conversation conversation
            in snapshot.data ?? const <Conversation>[]) {
          peers[conversation.id] = conversation.peer;
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: _calls!.length,
          separatorBuilder: (_, _) => const Divider(height: 1, indent: 88),
          itemBuilder: (BuildContext context, int index) {
            return _CallTile(
              call: _calls![index],
              myUid: _uid ?? '',
              peer: peers[_calls![index].conversationId],
            );
          },
        );
      },
    );
  }
}

class _CallTile extends StatelessWidget {
  const _CallTile({required this.call, required this.myUid, this.peer});

  final Call call;
  final String myUid;
  final UserProfile? peer;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool missed = call.status == CallStatus.missed ||
        (call.status == CallStatus.declined && call.calleeUid == myUid);

    final String displayName =
        peer == null ? 'LoText call' : _nameOf(peer!);
    final Color accent = missed ? scheme.error : scheme.primary;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Stack(
        children: <Widget>[
          UserAvatar(name: displayName, photoURL: peer?.photoURL, size: 48),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: accent,
                shape: BoxShape.circle,
                border: Border.all(color: theme.colorScheme.surface, width: 2),
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
        displayName,
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
      onTap: () => context.push(AppRoutes.chatFor(call.conversationId)),
    );
  }

  String _nameOf(UserProfile peer) {
    return peer.displayName.isNotEmpty ? peer.displayName : peer.username;
  }

  String _subtitle() {
    final String type = call.isVideo ? 'video call' : 'voice call';
    switch (call.status) {
      case CallStatus.missed:
        return 'Missed $type';
      case CallStatus.declined:
        return call.calleeUid == myUid ? 'Declined $type' : 'Call cancelled';
      case CallStatus.active:
      case CallStatus.ended:
        final String direction =
            call.callerUid == myUid ? 'Outgoing' : 'Incoming';
        final Duration? duration = call.duration;
        final String durationText = (duration != null &&
                duration.inSeconds >= 1)
            ? ' \u00b7 ${formatDuration(duration)}'
            : '';
        return '$direction $type$durationText';
      case CallStatus.ringing:
        final String direction =
            call.callerUid == myUid ? 'Outgoing' : 'Incoming';
        return '$direction $type';
    }
  }
}
