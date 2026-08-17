import 'package:flutter/foundation.dart';

/// Kind of a managed call.
enum ManagedCallType { audio, video }

/// Lifecycle of a managed call record.
///
/// `ringing` -> `active` when "answered", then `ended` when hung up. A call
/// that is never answered becomes `missed` (the caller cancelled) or `declined`.
enum ManagedCallStatus { ringing, active, ended, missed, declined }

/// A single voice/video call placed by an admin-managed account.
@immutable
class ManagedCall {
  const ManagedCall({
    required this.id,
    required this.managedAccountId,
    required this.conversationId,
    required this.peerUid,
    required this.type,
    required this.status,
    required this.createdAt,
    this.answeredAt,
    this.endedAt,
    this.endedBy,
  });

  final String id;
  final String managedAccountId;
  final String conversationId;
  final String peerUid;
  final ManagedCallType type;
  final ManagedCallStatus status;
  final DateTime createdAt;
  final DateTime? answeredAt;
  final DateTime? endedAt;

  /// The uid that ended/declined the call, when known.
  final String? endedBy;

  bool get isVideo => type == ManagedCallType.video;

  bool isIncomingFor(String uid) => false; // managed calls are outgoing.

  /// Wall-clock duration while the call was active (null if never answered).
  Duration? get duration {
    final DateTime? start = answeredAt;
    final DateTime? end = endedAt;
    if (start == null) return null;
    return (end ?? DateTime.now()).difference(start);
  }

  /// True when the call is over (any terminal status).
  bool get isFinished =>
      status == ManagedCallStatus.ended ||
      status == ManagedCallStatus.missed ||
      status == ManagedCallStatus.declined;

  bool get isMissed =>
      status == ManagedCallStatus.missed ||
      (status == ManagedCallStatus.declined && endedBy != null);
}