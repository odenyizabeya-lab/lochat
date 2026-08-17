import 'package:flutter/foundation.dart';

import '../../profile/models/user_profile.dart';

/// Kind of a managed status update.
enum ManagedStatusType { text, image, video }

/// A single status (update) posted by an admin-managed account.
@immutable
class ManagedStatus {
  const ManagedStatus({
    required this.id,
    required this.managedAccountId,
    required this.type,
    this.text = '',
    this.mediaUrl,
    this.thumbnailUrl,
    this.durationMs,
    this.width,
    this.height,
    this.mimeType,
    required this.createdAt,
    required this.expiresAt,
    this.isViewed = false,
    this.viewCount = 0,
  });

  final String id;
  final String managedAccountId;
  final ManagedStatusType type;
  final String text;
  final String? mediaUrl;
  final String? thumbnailUrl;
  final int? durationMs;
  final double? width;
  final double? height;
  final String? mimeType;
  final DateTime createdAt;
  final DateTime expiresAt;

  /// Whether the signed-in admin has seen it (own dashboard view).
  final bool isViewed;

  /// Total number of viewers (the admin's own posts only).
  final int viewCount;

  ManagedStatus copyWith({bool? isViewed, int? viewCount}) {
    return ManagedStatus(
      id: id,
      managedAccountId: managedAccountId,
      type: type,
      text: text,
      mediaUrl: mediaUrl,
      thumbnailUrl: thumbnailUrl,
      durationMs: durationMs,
      width: width,
      height: height,
      mimeType: mimeType,
      createdAt: createdAt,
      expiresAt: expiresAt,
      isViewed: isViewed ?? this.isViewed,
      viewCount: viewCount ?? this.viewCount,
    );
  }
}

/// A viewer of a managed status.
@immutable
class ManagedStatusViewer {
  const ManagedStatusViewer({required this.profile, required this.viewedAt});

  final UserProfile profile;
  final DateTime viewedAt;
}

/// Statuses posted by the same managed account, newest first.
@immutable
class ManagedStatusGroup {
  const ManagedStatusGroup({required this.managedAccountId, required this.statuses});

  final String managedAccountId;
  final List<ManagedStatus> statuses;

  bool get hasUnseen => statuses.any((ManagedStatus s) => !s.isViewed);
}