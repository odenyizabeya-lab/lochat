import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;

import '../../core/auth/auth_controller.dart';
import '../../core/router/app_routes.dart';
import 'call_controller.dart';

/// Routes an incoming ringing call to the callee's device.
///
/// [CallController.beginCall] / [IncomingCallScreen] handle the call itself;
/// this watcher is what actually *notifies* the callee: it subscribes to new
/// `calls` rows addressed to the signed-in user and pushes the incoming-call
/// route. Without it the `/calls/incoming/:callId` screen would never appear.
///
/// On start it also checks for a call that was already ringing when the app
/// launched (realtime does not replay past inserts). Calls already being shown
/// are deduplicated, and a call is skipped while another call session is
/// active (the user is busy).
class IncomingCallWatcher {
  IncomingCallWatcher({
    required this._auth,
    required this._calls,
    required this._router,
    SupabaseClient? client,
  }) : _client = client ?? Supabase.instance.client {
    _auth.addListener(_handleAuthChange);
    _handleAuthChange();
  }

  final AuthController _auth;
  final CallController _calls;
  final GoRouter _router;
  final SupabaseClient _client;

  RealtimeChannel? _channel;
  final Set<String> _seen = <String>{};
  Timer? _syncTimer;
  String? _uid;

  void _handleAuthChange() {
    final String? uid = _auth.currentUser?.uid;
    if (uid == _uid) return;
    _uid = uid;
    _teardown();
    _subscribe();
  }

  void _subscribe() {
    final String? uid = _uid;
    if (uid == null) return;
    _channel = _client
        .channel('incoming_calls_$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'calls',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'callee_uid',
            value: uid,
          ),
          callback: (PostgresChangePayload payload) {
            _onNewCall(payload.newRecord);
          },
        )
        .subscribe((RealtimeSubscribeStatus status, Object? error) {
          // If the realtime socket dropped and reconnected, an insert that
          // happened while it was down is never replayed. Re-sync ringing
          // calls so the callee still gets notified (self-heal).
          if (status == RealtimeSubscribeStatus.channelError ||
              status == RealtimeSubscribeStatus.closed) {
            _syncTimer ??= Timer(const Duration(seconds: 5), () {
              _syncTimer = null;
              if (_uid != null) unawaited(_catchUp(_uid!));
            });
          }
        });
    // Route a call that was already ringing when the app started.
    unawaited(_catchUp(uid));
  }

  Future<void> _catchUp(String uid) async {
    try {
      final List<Map<String, dynamic>> rows = await _client
          .from('calls')
          .select()
          .eq('callee_uid', uid)
          .eq('status', 'ringing')
          .limit(1);
      if (rows.isEmpty) return;
      _onNewCall(rows.first);
    } on Exception {
      // Non-fatal; realtime catches the next insert.
    }
  }

  void _onNewCall(Map<String, dynamic> record) {
    if (_calls.activeSession != null) return;
    final String? callId = record['id'] as String?;
    if (callId == null || callId.isEmpty || _seen.contains(callId)) return;
    _seen.add(callId);
    final String conversationId = record['conversation_id'] as String? ?? '';
    final String type = record['type'] as String? ?? 'audio';
    unawaited(
      _router.push(
        AppRoutes.incomingCall.replaceFirst(':callId', callId),
        extra: <String, dynamic>{
          'conversationId': conversationId,
          'isVideo': type == 'video',
        },
      ),
    );
  }

  void _teardown() {
    _syncTimer?.cancel();
    _syncTimer = null;
    if (_channel != null) {
      unawaited(_channel!.unsubscribe());
      _channel = null;
    }
  }

  void dispose() {
    _auth.removeListener(_handleAuthChange);
    _teardown();
  }
}
