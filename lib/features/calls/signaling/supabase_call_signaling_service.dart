import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;

import '../models/call.dart';
import 'call_signaling_service.dart';

/// Production [CallSignalingService] backed by Supabase (Postgres + Realtime).
///
/// Each call is one row in `calls` (lifecycle + SDP offer/answer), and ICE
/// candidates live in `call_candidates`, one row per candidate. RLS restricts
/// access to the two participants of a call.
class SupabaseCallSignalingService implements CallSignalingService {
  SupabaseCallSignalingService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Future<String> createCall({
    required String callerUid,
    required String calleeUid,
    required CallType type,
    required String conversationId,
  }) async {
    final List<Map<String, dynamic>> rows = await _client.from('calls').insert(<String, dynamic>{
      'type': type == CallType.video ? 'video' : 'audio',
      'conversation_id': conversationId,
      'caller_uid': callerUid,
      'callee_uid': calleeUid,
      'status': 'ringing',
    }).select('id');
    return (rows.first['id'] as String?) ?? '';
  }

  @override
  Stream<Call> watchCall(String callId) {
    return _client
        .from('calls')
        .stream(primaryKey: ['id'])
        .eq('id', callId)
        .map((List<Map<String, dynamic>> rows) =>
            _toCall(callId, rows.isEmpty ? const <String, dynamic>{} : rows.first));
  }

  @override
  Future<Call?> fetchCall(String callId) async {
    final List<Map<String, dynamic>> rows = await _client
        .from('calls')
        .select()
        .eq('id', callId)
        .limit(1);
    return rows.isEmpty ? null : _toCall(callId, rows.first);
  }

  Future<void> _transitionTo(
    String callId,
    CallStatus status, {
    DateTime? answeredAt,
    DateTime? endedAt,
    String? endedBy,
  }) async {
    // Guard the ringing -> active transition only: if the call already moved
    // on (the other side hung up), the answer is dropped.
    if (status == CallStatus.active) {
      final Call? current = await fetchCall(callId);
      if (current == null || current.status != CallStatus.ringing) return;
    }
    final Map<String, dynamic> update = <String, dynamic>{
      'status': _statusName(status),
    };
    if (answeredAt != null) {
      update['answered_at'] = answeredAt.toUtc().toIso8601String();
    }
    if (endedAt != null) {
      update['ended_at'] = endedAt.toUtc().toIso8601String();
    }
    if (endedBy != null) {
      update['ended_by'] = endedBy.isEmpty ? null : endedBy;
    }
    await _client.from('calls').update(update).eq('id', callId);
  }

  @override
  Future<void> acceptCall(String callId) async {
    await _transitionTo(
      callId,
      CallStatus.active,
      answeredAt: DateTime.now(),
    );
  }

  @override
  Future<void> declineCall(String callId) async {
    await _transitionTo(
      callId,
      CallStatus.declined,
      endedAt: DateTime.now(),
      endedBy: '',
    );
  }

  @override
  Future<void> endCall(String callId, {required String byUid}) async {
    await _transitionTo(
      callId,
      CallStatus.ended,
      endedAt: DateTime.now(),
      endedBy: byUid,
    );
  }

  @override
  Future<void> markMissed(String callId) async {
    await _transitionTo(
      callId,
      CallStatus.missed,
      endedAt: DateTime.now(),
    );
  }

  @override
  Future<void> writeOffer(String callId, String sdp) async {
    await _client.from('calls').update(<String, dynamic>{
      'offer_sdp': sdp,
    }).eq('id', callId);
  }

  @override
  Future<String?> fetchOffer(String callId) async {
    final List<Map<String, dynamic>> rows = await _client
        .from('calls')
        .select('offer_sdp')
        .eq('id', callId)
        .limit(1);
    if (rows.isEmpty) return null;
    final String? sdp = rows.first['offer_sdp'] as String?;
    return (sdp == null || sdp.isEmpty) ? null : sdp;
  }

  @override
  Future<void> writeAnswer(String callId, String sdp) async {
    await _client.from('calls').update(<String, dynamic>{
      'answer_sdp': sdp,
    }).eq('id', callId);
  }

  @override
  Future<String?> fetchAnswer(String callId) async {
    final List<Map<String, dynamic>> rows = await _client
        .from('calls')
        .select('answer_sdp')
        .eq('id', callId)
        .limit(1);
    if (rows.isEmpty) return null;
    final String? sdp = rows.first['answer_sdp'] as String?;
    return (sdp == null || sdp.isEmpty) ? null : sdp;
  }

  @override
  Stream<String> watchAnswer(String callId) {
    return _client
        .from('calls')
        .stream(primaryKey: ['id'])
        .eq('id', callId)
        .map((List<Map<String, dynamic>> rows) =>
            (rows.isEmpty ? '' : (rows.first['answer_sdp'] as String?)) ?? '')
        .where((String sdp) => sdp.isNotEmpty)
        .distinct();
  }

  @override
  Future<void> addCandidate(String callId, CallCandidate candidate) async {
    await _client.from('call_candidates').insert(<String, dynamic>{
      'call_id': callId,
      'sender_uid': candidate.senderUid,
      'candidate': candidate.candidate,
      'sdp_mid': candidate.sdpMid,
      'sdp_ml_index': candidate.sdpMLineIndex,
    });
  }

  @override
  Stream<CallCandidate> watchCandidates(String callId,
      {required String excludeSender}) {
    return _client
        .from('call_candidates')
        .stream(primaryKey: ['id'])
        .eq('call_id', callId)
        .map((List<Map<String, dynamic>> rows) => rows
            .map<CallCandidate>(_toCandidate)
            .where((CallCandidate c) => c.senderUid != excludeSender)
            .toList())
        .expand((List<CallCandidate> candidates) => candidates);
  }

  @override
  Future<List<CallCandidate>> fetchCandidates(String callId,
      {required String excludeSender}) async {
    final List<Map<String, dynamic>> rows = await _client
        .from('call_candidates')
        .select()
        .eq('call_id', callId);
    return rows
        .map<CallCandidate>(_toCandidate)
        .where((CallCandidate c) => c.senderUid != excludeSender)
        .toList();
  }

  @override
  Future<List<Call>> fetchCallHistory({required String uid}) async {
    final List<Map<String, dynamic>> rows = await _client
        .from('calls')
        .select()
        .or('caller_uid.eq.$uid,callee_uid.eq.$uid')
        .order('created_at', ascending: false)
        .limit(100);
    return rows
        .map((Map<String, dynamic> row) =>
            _toCall((row['id'] as String?) ?? '', row))
        .toList();
  }

  @override
  Stream<void> watchCallChanges({required String uid}) {
    // Realtime filters combine with AND only, so a call involving [uid] is
    // covered by two channels: one for calls the user started, one for calls
    // they received.
    final StreamController<void> controller = StreamController<void>();
    void emit() {
      if (!controller.isClosed) controller.add(null);
    }

    final RealtimeChannel callerChannel = _client
        .channel('call_changes_caller_$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'calls',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'caller_uid',
            value: uid,
          ),
          callback: (PostgresChangePayload _) => emit(),
        )
        .subscribe();
    final RealtimeChannel calleeChannel = _client
        .channel('call_changes_callee_$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'calls',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'callee_uid',
            value: uid,
          ),
          callback: (PostgresChangePayload _) => emit(),
        )
        .subscribe();
    controller.onCancel = () {
      unawaited(callerChannel.unsubscribe());
      unawaited(calleeChannel.unsubscribe());
    };
    return controller.stream;
  }

  CallCandidate _toCandidate(Map<String, dynamic> row) {    return CallCandidate(
      senderUid: (row['sender_uid'] as String?) ?? '',
      candidate: (row['candidate'] as String?) ?? '',
      sdpMid: (row['sdp_mid'] as String?) ?? '',
      sdpMLineIndex: (row['sdp_ml_index'] as num?)?.toInt() ?? 0,
    );
  }

  Call _toCall(String callId, Map<String, dynamic> data) {
    return Call(
      id: callId,
      conversationId: (data['conversation_id'] as String?) ?? '',
      type: (data['type'] as String?) == 'video'
          ? CallType.video
          : CallType.audio,
      callerUid: (data['caller_uid'] as String?) ?? '',
      calleeUid: (data['callee_uid'] as String?) ?? '',
      status: _statusFrom((data['status'] as String?) ?? 'ringing'),
      createdAt: _toDate(data['created_at']) ?? DateTime.now(),
      answeredAt: _toDate(data['answered_at']),
      endedAt: _toDate(data['ended_at']),
      endedBy: data['ended_by'] as String?,
    );
  }

  CallStatus _statusFrom(String name) => switch (name) {
        'active' => CallStatus.active,
        'ended' => CallStatus.ended,
        'missed' => CallStatus.missed,
        'declined' => CallStatus.declined,
        _ => CallStatus.ringing,
      };

  String _statusName(CallStatus status) => switch (status) {
        CallStatus.active => 'active',
        CallStatus.ended => 'ended',
        CallStatus.missed => 'missed',
        CallStatus.declined => 'declined',
        CallStatus.ringing => 'ringing',
      };

  DateTime? _toDate(Object? value) {
    if (value is String) {
      final DateTime? parsed = DateTime.tryParse(value);
      return parsed?.toLocal();
    }
    return null;
  }
}
