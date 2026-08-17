import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_routes.dart';
import '../../core/utils/time_utils.dart';
import './managed_chat_controller.dart';
import './managed_chat_scope.dart';
import './models/managed_call.dart';

/// Full-screen voice/video call for an admin-managed account.
///
/// Mirrors the user-side call screen but self-contained for the admin
/// dashboard: the call record lives in `managed_account_calls`. While
/// `ringing` the admin can answer (simulating the peer picking up) or hang up
/// (which records a missed call); while `active` a running timer tracks the
/// duration and hanging up records the ended call.
class AdminManagedCallScreen extends StatefulWidget {
  const AdminManagedCallScreen({
    super.key,
    required this.callId,
    required this.conversationId,
    required this.managedAccountId,
    required this.peerName,
    this.peerPhotoUrl,
  });

  final String callId;
  final String conversationId;
  final String managedAccountId;
  final String peerName;
  final String? peerPhotoUrl;

  @override
  State<AdminManagedCallScreen> createState() => _AdminManagedCallScreenState();
}

class _AdminManagedCallScreenState extends State<AdminManagedCallScreen> {
  ManagedChatController? _chat;
  ManagedCall? _call;
  StreamSubscription<ManagedCall>? _sub;
  bool _ended = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_chat != null) return;
    _chat = ManagedChatScope.of(context);
    _subscribe();
  }

  void _subscribe() {
    _sub = _chat!.watchCall(widget.callId).listen((ManagedCall call) {
      if (!mounted) return;
      setState(() => _call = call);
      if (call.isFinished) {
        _ended = true;
      }
    }, onError: (Object _) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _answer() async {
    await _chat!.answerCall(widget.callId);
  }

  Future<void> _hangUp() async {
    final ManagedCall? call = _call;
    if (call == null) return;
    if (call.status == ManagedCallStatus.ringing) {
      await _chat!.markMissed(widget.callId);
    } else {
      await _chat!.endCall(
        callId: widget.callId,
        byUid: widget.managedAccountId,
      );
    }
  }

  Future<void> _openChat() async {
    if (!mounted) return;
    context.push(AppRoutes.adminChat, extra: <String, dynamic>{
      'conversationId': widget.conversationId,
      'managedAccountId': widget.managedAccountId,
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool dark = theme.brightness == Brightness.dark;
    final ManagedCall? call = _call;

    final bool ringing = call?.status == ManagedCallStatus.ringing;
    final bool active = call?.status == ManagedCallStatus.active;
    final bool finished = call?.isFinished == true || _ended;

    return Scaffold(
      backgroundColor: dark ? const Color(0xFF0B141A) : const Color(0xFF008069),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            const Spacer(),
            CircleAvatar(
              radius: 56,
              backgroundColor: Colors.white24,
              backgroundImage: widget.peerPhotoUrl != null
                  ? NetworkImage(widget.peerPhotoUrl!)
                  : null,
              child: widget.peerPhotoUrl == null
                  ? Text(
                      widget.peerName.isNotEmpty
                          ? widget.peerName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 44,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 24),
            Text(
              widget.peerName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _statusLabel(ringing, active, finished, call),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 16,
              ),
            ),
            const Spacer(),
            if (active) _CallTimer(call: call!),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(bottom: 40),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  _CallButton(
                    icon: Icons.chat_bubble_rounded,
                    color: Colors.white24,
                    iconColor: Colors.white,
                    tooltip: 'Open chat',
                    onTap: finished ? _openChat : null,
                  ),
                  _CallButton(
                    icon: ringing
                        ? Icons.call_end_rounded
                        : Icons.call_end_rounded,
                    color: const Color(0xFFEA0038),
                    iconColor: Colors.white,
                    tooltip: ringing ? 'Decline' : 'End call',
                    onTap: active || ringing ? _hangUp : null,
                  ),
                  _CallButton(
                    icon: ringing ? Icons.call_rounded : Icons.phone_disabled,
                    color: ringing ? scheme.primary : Colors.white24,
                    iconColor: Colors.white,
                    tooltip: ringing ? 'Answer' : null,
                    onTap: ringing ? _answer : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(
      bool ringing, bool active, bool finished, ManagedCall? call) {
    if (finished) {
      switch (call?.status) {
        case ManagedCallStatus.missed:
          return 'Call missed';
        case ManagedCallStatus.declined:
          return 'Call declined';
        case ManagedCallStatus.ended:
          return 'Call ended';
        default:
          return 'Call ended';
      }
    }
    if (ringing) return 'Ringing\u2026';
    return 'Calling\u2026';
  }
}

class _CallTimer extends StatefulWidget {
  const _CallTimer({required this.call});

  final ManagedCall call;

  @override
  State<_CallTimer> createState() => _CallTimerState();
}

class _CallTimerState extends State<_CallTimer> {
  late final Timer _ticker;
  late DateTime _answeredAt;

  @override
  void initState() {
    super.initState();
    _answeredAt = widget.call.answeredAt ?? DateTime.now();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Duration elapsed = DateTime.now().difference(_answeredAt);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white12,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        formatDuration(elapsed),
        style: const TextStyle(color: Colors.white, fontSize: 16),
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  const _CallButton({
    required this.icon,
    required this.color,
    required this.iconColor,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final Color iconColor;
  final String? tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Widget circle = Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Icon(icon, color: iconColor, size: 28),
    );
    if (tooltip == null) return circle;
    return Tooltip(message: tooltip!, child: GestureDetector(onTap: onTap, child: circle));
  }
}