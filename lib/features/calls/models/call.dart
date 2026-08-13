/// Kind of a call.
enum CallType { audio, video }

/// Lifecycle of a call document.
///
/// `ringing` -> `active` when the callee answers, then `ended` when either
/// party hangs up. A call that is never answered becomes `missed` (the caller
/// cancelled) or `declined` (the callee explicitly declined).
enum CallStatus { ringing, active, ended, missed, declined }

/// A single call session between two users, mirrored in Firestore at
/// `calls/{callId}`.
class Call {
  const Call({
    required this.id,
    required this.conversationId,
    required this.type,
    required this.callerUid,
    required this.calleeUid,
    required this.status,
    required this.createdAt,
    this.answeredAt,
    this.endedAt,
    this.endedBy,
  });

  final String id;
  final String conversationId;
  final CallType type;
  final String callerUid;
  final String calleeUid;
  final CallStatus status;
  final DateTime createdAt;
  final DateTime? answeredAt;
  final DateTime? endedAt;

  /// The user who ended/declined the call, when known.
  final String? endedBy;

  bool get isVideo => type == CallType.video;

  bool isIncomingFor(String uid) => calleeUid == uid;

  /// Wall-clock duration while the call was active (null if never answered).
  Duration? get duration {
    final DateTime? start = answeredAt;
    final DateTime? end = endedAt;
    if (start == null) return null;
    return (end ?? DateTime.now()).difference(start);
  }

  /// True when the call is over (any terminal status).
  bool get isFinished =>
      status == CallStatus.ended ||
      status == CallStatus.missed ||
      status == CallStatus.declined;
}
