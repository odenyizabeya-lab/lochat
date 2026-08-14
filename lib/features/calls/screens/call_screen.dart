import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/utils/time_utils.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../chat/chat_controller.dart';
import '../../chat/chat_scope.dart';
import '../call_controller.dart';
import '../call_scope.dart';
import '../call_session_controller.dart';
import '../models/call.dart';

/// Parameters for an outgoing call that has not connected yet; the screen
/// starts it right after navigation.
class OutgoingCallParams {
  const OutgoingCallParams({
    required this.calleeUid,
    required this.conversationId,
    required this.type,
  });

  final String calleeUid;
  final String conversationId;
  final CallType type;
}

/// The active (or outgoing) call screen for both voice and video calls.
///
/// Renders the peer's name, live status (ringing / connecting / elapsed time),
/// and the control bar (mute, camera, end). For video calls the remote stream
/// fills the screen with the local preview in the corner. When the call
/// finishes, a brief summary is shown before popping.
class CallScreen extends StatefulWidget {
  const CallScreen({super.key, required this.session, this.startParams});

  final CallSessionController session;
  final OutgoingCallParams? startParams;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  String? _peerName;
  String? _peerPhoto;
  bool _popping = false;

  /// Elapsed-time display ticks while the call is active.
  int _elapsedSeconds = 0;
  Timer? _elapsedTimer;
  DateTime? _answeredAt;

  @override
  void initState() {
    super.initState();
    _syncTimer();
    widget.session.addListener(_onSessionChanged);
    final OutgoingCallParams? params = widget.startParams;
    if (params != null) {
      unawaited(
        widget.session.startOutgoing(
          calleeUid: params.calleeUid,
          conversationId: params.conversationId,
          type: params.type,
        ),
      );
    }
  }

  void _onSessionChanged() {
    _syncTimer();
    final Call? call = widget.session.call;
    if (call != null && call.isFinished && !_popping) {
      _popping = true;
      _elapsedTimer?.cancel();
      Timer(const Duration(milliseconds: 1600), () {
        if (!mounted) return;
        final CallController? calls = CallScope.maybeOf(context);
        calls?.clearSession(widget.session);
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
    }
  }

  void _syncTimer() {
    final Call? call = widget.session.call;
    if (call == null || call.status != CallStatus.active) {
      if (_elapsedTimer != null) {
        _elapsedTimer?.cancel();
        _elapsedTimer = null;
      }
      _answeredAt = null;
      return;
    }
    if (identical(call.answeredAt, _answeredAt)) return;
    _answeredAt = call.answeredAt;
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSeconds++);
    });
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSessionChanged);
    _elapsedTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1D2E),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: widget.session,
          builder: (BuildContext context, Widget? _) {
            final CallSessionController session = widget.session;
            final Call? call = session.call;

            if (call == null) {
              return const Center(child: CircularProgressIndicator());
            }
            if (session.failed) {
              return _FailureView(
                message: session.failureMessage ?? 'Call failed.',
                onClose: () => Navigator.of(context).pop(),
              );
            }

            return _buildCall(context, session, call);
          },
        ),
      ),
    );
  }

  Widget _buildCall(
    BuildContext context,
    CallSessionController session,
    Call call,
  ) {
    final bool video = call.isVideo;
    final bool finished = call.isFinished;

    return Stack(
      children: <Widget>[
        // Remote video (video calls) or gradient background.
        Positioned.fill(
          child: video
              ? (session.rtc?.remoteView ??
                  const _GradientBackground(child: null))
              : const _GradientBackground(child: null),
        ),
        // Local camera preview in the corner of video calls.
        if (video && session.rtc != null)
          Positioned(
            top: 16,
            right: 16,
            child: Container(
              width: 110,
              height: 150,
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white24),
              ),
              clipBehavior: Clip.antiAlias,
              child: session.rtc!.localView ?? const SizedBox.shrink(),
            ),
          ),
        // Peer identity + status.
        Positioned(
          top: 24,
          left: 16,
          right: 16,
          child: _buildIdentity(context, session, call),
        ),
        // Controls.
        Positioned(
          left: 0,
          right: 0,
          bottom: 24,
          child: _buildControls(context, session, call),
        ),
        if (finished) ...<Widget>[
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.35),
              child: Center(
                child: _SummaryCard(call: call, session: session),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildIdentity(
    BuildContext context,
    CallSessionController session,
    Call call,
  ) {
    final String statusText = _statusText(call, session);
    return Column(
      children: <Widget>[
        UserAvatar(
          name: _peerName ?? 'Call',
          photoURL: _peerPhoto,
          size: 84,
        ),
        const SizedBox(height: 14),
        Text(
          _peerName ?? 'Call',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          statusText,
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        const SizedBox(height: 8),
        _ResolvePeer(
          conversationId: call.conversationId,
          onResolved: (String name, String? photo) {
            if (_peerName != name || _peerPhoto != photo) {
              setState(() {
                _peerName = name;
                _peerPhoto = photo;
              });
            }
          },
        ),
      ],
    );
  }

  String _statusText(Call call, CallSessionController session) {
    if (call.isFinished) return _finishedText(call, session);
    if (call.status == CallStatus.ringing) {
      return session.outgoing ? 'Ringing\u2026' : 'Calling\u2026';
    }
    if (call.status == CallStatus.active) {
      if (session.rtc == null) return 'Connecting\u2026';
      return formatDuration(Duration(seconds: _elapsedSeconds));
    }
    return 'Call ended';
  }

  String _finishedText(Call call, CallSessionController session) {
    return switch (call.status) {
      CallStatus.declined => 'Call declined',
      CallStatus.missed => session.outgoing ? 'Call cancelled' : 'Missed call',
      CallStatus.ended => 'Call ended',
      _ => 'Call ended',
    };
  }

  Widget _buildControls(
    BuildContext context,
    CallSessionController session,
    Call call,
  ) {
    if (call.isFinished) return const SizedBox.shrink();

    final List<Widget> buttons = <Widget>[];
    if (call.status == CallStatus.active) {
      buttons.add(_ControlButton(
        icon: session.muted ? Icons.mic_off_rounded : Icons.mic_rounded,
        label: session.muted ? 'Unmute' : 'Mute',
        onTap: () => unawaited(session.toggleMute()),
      ));
      if (call.isVideo) {
        buttons.add(_ControlButton(
          icon: session.cameraEnabled
              ? Icons.videocam_rounded
              : Icons.videocam_off_rounded,
          label: session.cameraEnabled ? 'Camera' : 'Camera off',
          onTap: () => unawaited(session.toggleCamera()),
        ));
        buttons.add(_ControlButton(
          icon: Icons.cameraswitch_rounded,
          label: 'Switch camera',
          onTap: () => unawaited(session.switchCamera()),
        ));
      }
    }

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        ...buttons,
        _EndCallButton(
          onTap: () {
            if (call.status == CallStatus.ringing && session.outgoing) {
              unawaited(session.cancelOutgoing());
            } else {
              unawaited(session.endCall());
            }
          },
        ),
      ],
    );
  }
}

/// Shown when the active-call route is opened without a live session (e.g. a
/// stale deep link after the app restarted).
class CallNotFoundScreen extends StatelessWidget {
  const CallNotFoundScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1D2E),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.phone_disabled_rounded,
                  color: Colors.white70, size: 56),
              const SizedBox(height: 16),
              const Text(
                'This call is no longer active.',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Back'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          InkResponse(
            onTap: onTap,
            radius: 30,
            child: Container(
              width: 60,
              height: 60,
              decoration: const BoxDecoration(
                color: Colors.white12,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _EndCallButton extends StatelessWidget {
  const _EndCallButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: InkResponse(
        onTap: onTap,
        radius: 34,
        child: Container(
          width: 68,
          height: 68,
          decoration: const BoxDecoration(
            color: Color(0xFFE53935),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 32),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.call, required this.session});

  final Call call;
  final CallSessionController session;

  @override
  Widget build(BuildContext context) {
    final Duration? duration = call.duration;
    final String? durationText =
        duration == null ? null : formatDuration(duration);
    final String title = _title();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Icon(Icons.call_end_rounded, color: Colors.white, size: 48),
        const SizedBox(height: 12),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (durationText != null) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            durationText,
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ],
    );
  }

  String _title() {
    return switch (call.status) {
      CallStatus.declined => 'Call declined',
      CallStatus.missed => session.outgoing ? 'Call cancelled' : 'Missed call',
      CallStatus.ended => 'Call ended',
      _ => 'Call ended',
    };
  }
}

/// Resolves the peer's name and photo from the live conversations stream.
class _ResolvePeer extends StatefulWidget {
  const _ResolvePeer({
    required this.conversationId,
    required this.onResolved,
  });

  final String conversationId;
  final void Function(String name, String? photo) onResolved;

  @override
  State<_ResolvePeer> createState() => _ResolvePeerState();
}

class _ResolvePeerState extends State<_ResolvePeer> {
  @override
  Widget build(BuildContext context) {
    final ChatController chat = ChatScope.of(context);
    return StreamBuilder(
      stream: chat.watchConversations(),
      builder: (BuildContext context, AsyncSnapshot snapshot) {
        final List conversations = snapshot.data ?? const <dynamic>[];
        for (final dynamic conversation in conversations) {
          if (conversation.id == widget.conversationId) {
            final String name = conversation.peer.displayName.isNotEmpty
                ? conversation.peer.displayName
                : conversation.peer.username;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) widget.onResolved(name, conversation.peer.photoURL);
            });
            break;
          }
        }
        return const SizedBox.shrink();
      },
    );
  }
}

class _GradientBackground extends StatelessWidget {
  const _GradientBackground({required this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0xFF12324A), Color(0xFF0B1D2E)],
        ),
      ),
      child: child,
    );
  }
}

class _FailureView extends StatelessWidget {
  const _FailureView({required this.message, required this.onClose});

  final String message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.phone_disabled_rounded, color: Colors.white70, size: 56),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: onClose,
            child: const Text('Back'),
          ),
        ],
      ),
    );
  }
}
