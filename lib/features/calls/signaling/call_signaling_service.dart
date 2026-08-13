import '../models/call.dart';

/// One ICE candidate that a peer wants the other side to add.
class CallCandidate {
  const CallCandidate({
    required this.senderUid,
    required this.candidate,
    required this.sdpMid,
    required this.sdpMLineIndex,
  });

  final String senderUid;

  /// The candidate string from the WebRTC layer.
  final String candidate;
  final String sdpMid;
  final int sdpMLineIndex;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'sender': senderUid,
        'candidate': candidate,
        'sdpMid': sdpMid,
        'sdpMLineIndex': sdpMLineIndex,
      };

  static CallCandidate? fromMap(Map<String, dynamic>? map, String fallbackSender) {
    if (map == null) return null;
    final int? index = map['sdpMLineIndex'] as int?;
    if (index == null) return null;
    return CallCandidate(
      senderUid: (map['sender'] as String?) ?? fallbackSender,
      candidate: (map['candidate'] as String?) ?? '',
      sdpMid: (map['sdpMid'] as String?) ?? '',
      sdpMLineIndex: index,
    );
  }
}

/// Supabase-backed signaling contract for calls.
///
/// Call lifecycle is stored in `calls/{callId}` and WebRTC signaling payloads
/// in subcollections (`offer`, `answer`, and a shared `candidates` array). The
/// UI depends only on this interface; tests inject a fake.
abstract interface class CallSignalingService {
  /// Creates a ringing call document and returns its ID.
  Future<String> createCall({
    required String callerUid,
    required String calleeUid,
    required CallType type,
    required String conversationId,
  });

  /// Live view of a single call document.
  Stream<Call> watchCall(String callId);

  /// One-shot read of a call document, or null when it does not exist.
  Future<Call?> fetchCall(String callId);

  /// Marks the call answered (only valid while ringing).
  Future<void> acceptCall(String callId);

  /// Marks the call as declined by the callee.
  Future<void> declineCall(String callId);

  /// Marks the call as ended by [byUid] (both parties hang up on active calls).
  Future<void> endCall(String callId, {required String byUid});

  /// Marks an unanswered call as missed (caller cancelled or ring timed out).
  Future<void> markMissed(String callId);

  /// Writes the caller's SDP offer.
  Future<void> writeOffer(String callId, String sdp);

  /// Reads the caller's SDP offer (null until written).
  Future<String?> fetchOffer(String callId);

  /// Writes the callee's SDP answer.
  Future<void> writeAnswer(String callId, String sdp);

  /// Reads the callee's SDP answer (null until written).
  Future<String?> fetchAnswer(String callId);

  /// Streams the answer once it is written.
  Stream<String> watchAnswer(String callId);

  /// Appends an ICE candidate from [candidate.senderUid].
  Future<void> addCandidate(String callId, CallCandidate candidate);

  /// Streams candidates from the other peer (sender != my uid).
  Stream<CallCandidate> watchCandidates(String callId,
      {required String excludeSender});

  /// One-shot list of candidates already written by the other peer.
  Future<List<CallCandidate>> fetchCandidates(String callId,
      {required String excludeSender});

  /// The signed-in user's call history (as caller or callee), newest first.
  Future<List<Call>> fetchCallHistory({required String uid});

  /// Emits whenever a call involving [uid] changes, so screens can refresh
  /// their call history live.
  Stream<void> watchCallChanges({required String uid});
}
