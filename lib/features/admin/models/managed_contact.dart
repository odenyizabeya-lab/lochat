import 'package:flutter/foundation.dart';

@immutable
class ManagedContact {
  const ManagedContact({
    required this.managedAccountId,
    required this.contactUid,
    required this.displayName,
    required this.username,
    this.photoUrl,
    this.addedAt,
  });

  final String managedAccountId;
  final String contactUid;
  final String displayName;
  final String username;
  final String? photoUrl;
  final DateTime? addedAt;

  String get handle => '@$username';

  ManagedContact copyWith({
    String? managedAccountId,
    String? contactUid,
    String? displayName,
    String? username,
    String? photoUrl,
    DateTime? addedAt,
  }) {
    return ManagedContact(
      managedAccountId: managedAccountId ?? this.managedAccountId,
      contactUid: contactUid ?? this.contactUid,
      displayName: displayName ?? this.displayName,
      username: username ?? this.username,
      photoUrl: photoUrl ?? this.photoUrl,
      addedAt: addedAt ?? this.addedAt,
    );
  }
}
