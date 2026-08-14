import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../chat/chat_controller.dart';
import '../../chat/chat_scope.dart';
import '../../chat/models/conversation.dart';
import '../call_controller.dart';
import '../call_scope.dart';
import '../call_session_controller.dart';
import '../models/call.dart';

/// Full-screen incoming call: peer identity, accept/decline actions, and a
/// ring timeout that marks the call missed if never answered.
class IncomingCallScreen extends StatefulWidget {
  const IncomingCallScreen({
    super.key,
    required this.callId,
    required this.conversationId,
    this.isVideo = false,
  });

  final String callId;
  final String conversationId;

  /// Whether the caller initiated a video call (false = voice call).
  final bool isVideo;

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> {
  String? _peerName;
  String? _peerPhoto;
  bool _accepting = false;
  bool _handled = false;

  StreamSubscription<List<Conversation>>? _peerSub;
  Timer? _ringTimer;

  @override
  void initState() {
    super.initState();
    _scheduleRingTimeout();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_peerSub == null) {
      _resolvePeer();
    }
  }

  @override
  void dispose() {
    _peerSub?.cancel();
    _ringTimer?.cancel();
    super.dispose();
  }

  void _resolvePeer() {
    final ChatController chat = ChatScope.of(context);
    _peerSub = chat.watchConversations().listen((conversations) {
      if (!mounted) return;
      for (final conversation in conversations) {
        if (conversation.id == widget.conversationId) {
          final String name = conversation.peer.displayName.isNotEmpty
              ? conversation.peer.displayName
              : conversation.peer.username;
          if (_peerName != name || _peerPhoto != conversation.peer.photoURL) {
            setState(() {
              _peerName = name;
              _peerPhoto = conversation.peer.photoURL;
            });
          }
          break;
        }
      }
    });
  }

  /// Marks the call missed if it rings for 45s without an answer.
  void _scheduleRingTimeout() {
    _ringTimer = Timer(const Duration(seconds: 45), () {
      if (!mounted || _handled) return;
      _handled = true;
      unawaited(
        CallScope.of(context).signaling.markMissed(widget.callId).catchError((
          Object e,
        ) {
          // Dismiss the ring screen regardless; a failed status write must not
          // crash the app or leave the caller hanging forever.
          debugPrint('markMissed failed: $e');
        }),
      );
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    });
  }

  Future<void> _accept() async {
    if (_handled || _accepting) return;
    setState(() {
      _accepting = true;
      _handled = true;
    });
    // The ring timeout must not fire while accept is in progress (e.g. the
    // camera/mic permission dialog is up), so cancel it up front.
    _ringTimer?.cancel();
    final CallController calls = CallScope.of(context);
    final CallSessionController session = calls.prepareIncoming(
      myUid: ChatScope.of(context).uid ?? '',
      callId: widget.callId,
    );
    await session.acceptIncoming();
    if (!mounted) return;
    final Call? call = session.call;
    if (session.failed || (call != null && call.isFinished)) {
      if (session.failed) {
        // e.g. camera/mic permission denied; decline so the caller's ring
        // screen is dismissed rather than timing out.
        unawaited(
          CallScope.of(context).signaling.declineCall(widget.callId).catchError(
            (Object e) {
              debugPrint('declineCall failed: $e');
            },
          ),
        );
      }
      calls.clearSession(session);
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      return;
    }
    setState(() => _handled = true);
    context.pushReplacement(
      AppRoutes.activeCall,
      extra: <String, dynamic>{'session': session},
    );
  }

  Future<void> _decline() async {
    if (_handled) return;
    _handled = true;
    unawaited(
      CallScope.of(context).signaling.declineCall(widget.callId).catchError((
        Object e,
      ) {
        debugPrint('declineCall failed: $e');
      }),
    );
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool accepting = _accepting;

    return Scaffold(
      backgroundColor: const Color(0xFF0B1D2E),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              UserAvatar(
                name: _peerName ?? 'Call',
                photoURL: _peerPhoto,
                size: 96,
              ),
              const SizedBox(height: 18),
              Text(
                _peerName ?? 'Incoming call',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.isVideo
                    ? 'Incoming video call\u2026'
                    : 'Incoming voice call\u2026',
                style: const TextStyle(color: Colors.white70, fontSize: 15),
              ),
              const SizedBox(height: 48),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  _RingButton(
                    color: scheme.error,
                    icon: Icons.call_end_rounded,
                    onTap: accepting ? null : _decline,
                  ),
                  const SizedBox(width: 48),
                  _RingButton(
                    color: scheme.primary,
                    icon: accepting
                        ? Icons.hourglass_top_rounded
                        : Icons.call_rounded,
                    onTap: _accept,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                accepting ? 'Connecting\u2026' : 'Answer to connect',
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingButton extends StatelessWidget {
  const _RingButton({
    required this.color,
    required this.icon,
    required this.onTap,
  });

  final Color color;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 40,
      child: Container(
        width: 76,
        height: 76,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Icon(icon, color: Colors.white, size: 36),
      ),
    );
  }
}
