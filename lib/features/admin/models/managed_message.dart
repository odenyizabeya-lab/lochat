import 'package:flutter/foundation.dart';

enum ManagedMessageType { text, image, video, voice }

enum ManagedMessageStatus { sent, delivered, read }

@immutable
class ManagedMessage {
  const ManagedMessage({
    required this.id,
    required this.conversationId,
    required this.managedAccountId,
    required this.senderUid,
    required this.type,
    this.text,
    this.mediaUrl,
    this.thumbnailUrl,
    this.durationMs,
    this.width,
    this.height,
    this.fileName,
    this.mimeType,
    this.sizeBytes,
    this.voiceEffect,
    this.replyToId,
    this.replyToType,
    this.replyToText,
    this.replyToSender,
    this.senderLang,
    this.originalText,
    this.sourceLang,
    this.status = ManagedMessageStatus.sent,
    required this.createdAt,
    this.isPending = false,
  });

  final String id;
  final String conversationId;
  final String managedAccountId;
  final String senderUid;
  final ManagedMessageType type;
  final String? text;
  final String? mediaUrl;
  final String? thumbnailUrl;
  final int? durationMs;
  final double? width;
  final double? height;
  final String? fileName;
  final String? mimeType;
  final int? sizeBytes;
  final String? voiceEffect;
  final String? replyToId;
  final String? replyToType;
  final String? replyToText;
  final String? replyToSender;
  final String? senderLang;
  final String? originalText;
  final String? sourceLang;
  final ManagedMessageStatus status;
  final DateTime createdAt;
  final bool isPending;

  ManagedMessage copyWith({
    String? id,
    String? conversationId,
    String? managedAccountId,
    String? senderUid,
    ManagedMessageType? type,
    String? text,
    String? mediaUrl,
    String? thumbnailUrl,
    int? durationMs,
    double? width,
    double? height,
    String? fileName,
    String? mimeType,
    int? sizeBytes,
    String? voiceEffect,
    String? replyToId,
    String? replyToType,
    String? replyToText,
    String? replyToSender,
    String? senderLang,
    String? originalText,
    String? sourceLang,
    ManagedMessageStatus? status,
    DateTime? createdAt,
    bool? isPending,
  }) {
    return ManagedMessage(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      managedAccountId: managedAccountId ?? this.managedAccountId,
      senderUid: senderUid ?? this.senderUid,
      type: type ?? this.type,
      text: text ?? this.text,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      durationMs: durationMs ?? this.durationMs,
      width: width ?? this.width,
      height: height ?? this.height,
      fileName: fileName ?? this.fileName,
      mimeType: mimeType ?? this.mimeType,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      voiceEffect: voiceEffect ?? this.voiceEffect,
      replyToId: replyToId ?? this.replyToId,
      replyToType: replyToType ?? this.replyToType,
      replyToText: replyToText ?? this.replyToText,
      replyToSender: replyToSender ?? this.replyToSender,
      senderLang: senderLang ?? this.senderLang,
      originalText: originalText ?? this.originalText,
      sourceLang: sourceLang ?? this.sourceLang,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      isPending: isPending ?? this.isPending,
    );
  }
}
