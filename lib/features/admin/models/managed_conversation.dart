import 'package:flutter/foundation.dart';

import 'managed_message.dart';

@immutable
class ManagedConversation {
  const ManagedConversation({
    required this.id,
    required this.managedAccountId,
    required this.peerUid,
    required this.peerDisplayName,
    required this.peerUsername,
    this.peerPhotoUrl,
    this.lastMessageText,
    this.lastMessageAt,
    this.lastSenderUid,
    this.unreadCount = 0,
    this.typingUid,
    this.typingUntil,
    this.lastMessageType = ManagedMessageType.text,
    this.lastMessageDurationMs,
    this.createdAt,
  });

  final String id;
  final String managedAccountId;
  final String peerUid;
  final String peerDisplayName;
  final String peerUsername;
  final String? peerPhotoUrl;
  final String? lastMessageText;
  final DateTime? lastMessageAt;
  final String? lastSenderUid;
  final int unreadCount;
  final String? typingUid;
  final DateTime? typingUntil;
  final ManagedMessageType lastMessageType;
  final int? lastMessageDurationMs;
  final DateTime? createdAt;

  String get peerHandle => '@$peerUsername';

  ManagedConversation copyWith({
    String? id,
    String? managedAccountId,
    String? peerUid,
    String? peerDisplayName,
    String? peerUsername,
    String? peerPhotoUrl,
    String? lastMessageText,
    DateTime? lastMessageAt,
    String? lastSenderUid,
    int? unreadCount,
    String? typingUid,
    DateTime? typingUntil,
    ManagedMessageType? lastMessageType,
    int? lastMessageDurationMs,
    DateTime? createdAt,
  }) {
    return ManagedConversation(
      id: id ?? this.id,
      managedAccountId: managedAccountId ?? this.managedAccountId,
      peerUid: peerUid ?? this.peerUid,
      peerDisplayName: peerDisplayName ?? this.peerDisplayName,
      peerUsername: peerUsername ?? this.peerUsername,
      peerPhotoUrl: peerPhotoUrl ?? this.peerPhotoUrl,
      lastMessageText: lastMessageText ?? this.lastMessageText,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      lastSenderUid: lastSenderUid ?? this.lastSenderUid,
      unreadCount: unreadCount ?? this.unreadCount,
      typingUid: typingUid ?? this.typingUid,
      typingUntil: typingUntil ?? this.typingUntil,
      lastMessageType: lastMessageType ?? this.lastMessageType,
      lastMessageDurationMs: lastMessageDurationMs ?? this.lastMessageDurationMs,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
