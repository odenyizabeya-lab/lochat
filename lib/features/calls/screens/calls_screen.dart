import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/time_utils.dart';
import '../../../shared/widgets/contact_picker_sheet.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/loading_view.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../chat/chat_controller.dart';
import '../../chat/chat_scope.dart';
import '../../chat/data/chat_repository.dart' show NotAContactException;
import '../../chat/models/conversation.dart';
import '../../profile/models/user_profile.dart';
import '../call_scope.dart';
import '../models/call.dart';

/// Calls tab: WhatsApp-style quick actions to start a voice or video call with
/// a contact (from the user's own private list), followed by the recent call
/// history with a one-tap call-back button.
///
/// The history refreshes live through
/// [CallSignalingService.watchCallChanges], and peer names come from the
/// signed-in user's conversations. The search icon filters the history by
/// contact name in real time.
class CallsScreen extends StatefulWidget {
  const CallsScreen({super.key});

  @override
  State<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends State<CallsScreen> {
  List<Call>? _calls;
  bool _error = false;
  String? _uid;
  StreamSubscription<void>? _changesSub;

  final TextEditingController _searchController = TextEditingController();
  bool _searching = false;
  String _query = '';

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
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _query = '';
        _searchController.clear();
      }
    });
  }

  Future<void> _startCall(CallType type) async {
    final UserProfile? peer = await showContactPicker(
      context,
      title: type == CallType.video ? 'New video call' : 'New call',
    );
    if (peer == null || !mounted) return;
    final ChatController chat = ChatScope.of(context);
    final String? myUid = chat.uid;
    if (myUid == null) return;
    try {
      final String conversationId = await chat.openConversation(peer.uid);
      if (!mounted) return;
      await _pushCall(peer.uid, conversationId, type);
    } on NotAContactException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add them as a contact to call.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start the call. Try again.')),
      );
    }
  }

  /// Starts a call with an already-known peer (used by history rows' call-back
  /// buttons, where the conversation already exists).
  Future<void> _callBack(UserProfile peer, String conversationId) async {
    final String? myUid = ChatScope.maybeOf(context)?.uid;
    if (myUid == null) return;
    try {
      if (!mounted) return;
      await _pushCall(peer.uid, conversationId, CallType.audio);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start the call. Try again.')),
      );
    }
  }

  Future<void> _pushCall(
    String calleeUid,
    String conversationId,
    CallType type,
  ) async {
    final String? myUid = ChatScope.maybeOf(context)?.uid;
    if (myUid == null) return;
    final session = CallScope.of(context).beginCall(myUid: myUid);
    await context.push(
      AppRoutes.activeCall,
      extra: <String, dynamic>{
        'session': session,
        'startParams': <String, dynamic>{
          'calleeUid': calleeUid,
          'conversationId': conversationId,
          'type': type == CallType.video ? 'video' : 'audio',
        },
      },
    );
  }

  void _onMenuSelected(String value) {
    switch (value) {
      case 'new-call':
        unawaited(_startCall(CallType.audio));
      case 'new-video':
        unawaited(_startCall(CallType.video));
      case 'history':
        context.push(AppRoutes.callHistory);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calls'),
        actions: <Widget>[
          IconButton(
            tooltip: _searching ? 'Close search' : 'Search calls',
            icon: Icon(_searching
                ? Icons.close_rounded
                : Icons.search_rounded),
            onPressed: _toggleSearch,
          ),
          PopupMenuButton<String>(
            tooltip: 'More options',
            onSelected: _onMenuSelected,
            itemBuilder: (BuildContext context) =>
                <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'new-call',
                child: _MenuRow(
                  icon: Icons.call_rounded,
                  label: 'New call',
                ),
              ),
              const PopupMenuItem<String>(
                value: 'new-video',
                child: _MenuRow(
                  icon: Icons.videocam_rounded,
                  label: 'New video call',
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'history',
                child: _MenuRow(
                  icon: Icons.history_rounded,
                  label: 'Call history',
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (_searching) _buildSearchField(theme),
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 12, 0, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  _QuickAction(
                    icon: Icons.call_rounded,
                    label: 'New call',
                    circleColor: AppColors.live,
                    iconColor: const Color(0xFF06332B),
                    onTap: () => unawaited(_startCall(CallType.audio)),
                  ),
                  _QuickAction(
                    icon: Icons.videocam_rounded,
                    label: 'New video call',
                    circleColor: theme.colorScheme.primary,
                    iconColor: theme.colorScheme.onPrimary,
                    onTap: () => unawaited(_startCall(CallType.video)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
              child: Text(
                'RECENT',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            Expanded(child: _buildHistory(theme)),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField(ThemeData theme) {
    final ColorScheme scheme = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: TextField(
        controller: _searchController,
        autofocus: true,
        textInputAction: TextInputAction.search,
        onChanged: (String value) => setState(() => _query = value.trim()),
        decoration: InputDecoration(
          hintText: 'Search calls',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: IconButton(
            tooltip: 'Clear search',
            icon: const Icon(Icons.close_rounded),
            onPressed: () {
              _searchController.clear();
              setState(() => _query = '');
            },
          ),
          filled: true,
          fillColor: isDark
              ? AppColors.darkSurfaceHigh
              : scheme.surfaceContainerHighest,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildHistory(ThemeData theme) {
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
        title: 'No recent calls',
        message:
            'Voice and video calls you make or receive will show up here.',
      );
    }

    return StreamBuilder<List<Conversation>>(
      stream: ChatScope.of(context).watchConversations(),
      builder: (BuildContext context,
          AsyncSnapshot<List<Conversation>> snapshot) {
        final Map<String, UserProfile> peers = <String, UserProfile>{};
        for (final Conversation conversation
            in snapshot.data ?? const <Conversation>[]) {
          peers[conversation.id] = conversation.peer;
        }

        final List<Call> calls = _query.isEmpty
            ? _calls!
            : _calls!.where((Call call) {
                final UserProfile? peer = peers[call.conversationId];
                if (peer == null) return false;
                final String name = peer.displayName.isNotEmpty
                    ? peer.displayName
                    : peer.username;
                return name.toLowerCase().contains(_query.toLowerCase());
              }).toList();

        if (calls.isEmpty) {
          return const EmptyStateView(
            icon: Icons.search_off_rounded,
            title: 'No results found',
            message: 'Try a different name.',
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: calls.length,
          separatorBuilder: (_, _) => const Divider(height: 1, indent: 88),
          itemBuilder: (BuildContext context, int index) {
            final Call call = calls[index];
            return _CallTile(
              call: call,
              myUid: _uid ?? '',
              peer: peers[call.conversationId],
              onCallBack: peers[call.conversationId] == null
                  ? null
                  : () => unawaited(_callBack(
                        peers[call.conversationId]!,
                        call.conversationId,
                      )),
            );
          },
        );
      },
    );
  }
}

/// Large circular quick action (WhatsApp-style) with a label underneath.
class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.circleColor,
    required this.iconColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color circleColor;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: circleColor,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 28),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 108,
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CallTile extends StatelessWidget {
  const _CallTile({
    required this.call,
    required this.myUid,
    required this.peer,
    required this.onCallBack,
  });

  final Call call;
  final String myUid;
  final UserProfile? peer;
  final VoidCallback? onCallBack;

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
      trailing: onCallBack == null
          ? null
          : IconButton(
              tooltip: 'Call back',
              icon: Icon(
                call.isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                color: scheme.primary,
              ),
              onPressed: onCallBack,
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

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
