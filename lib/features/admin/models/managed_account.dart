import 'package:flutter/foundation.dart';

@immutable
class ManagedAccount {
  const ManagedAccount({
    required this.id,
    required this.adminUid,
    required this.slotIndex,
    this.lotextId,
    required this.username,
    required this.displayName,
    this.photoUrl,
    this.settings = const <String, dynamic>{},
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String adminUid;
  final int slotIndex;
  final String? lotextId;
  final String username;
  final String displayName;
  final String? photoUrl;
  final Map<String, dynamic> settings;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get displayHandle => '@$username';

  ManagedAccount copyWith({
    String? id,
    String? adminUid,
    int? slotIndex,
    String? lotextId,
    String? username,
    String? displayName,
    String? photoUrl,
    Map<String, dynamic>? settings,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ManagedAccount(
      id: id ?? this.id,
      adminUid: adminUid ?? this.adminUid,
      slotIndex: slotIndex ?? this.slotIndex,
      lotextId: lotextId ?? this.lotextId,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      settings: settings ?? this.settings,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
