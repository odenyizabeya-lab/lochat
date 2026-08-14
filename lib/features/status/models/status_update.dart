import '../../profile/models/user_profile.dart';

/// The kind of media a status update carries.
enum StatusType { text, image, video }

/// A single ephemeral status update.
///
/// Media URLs are resolved to fresh signed URLs by the repository at read
/// time, so [mediaUrl] is safe to hand straight to an image/video widget.
class StatusUpdate {
  const StatusUpdate({
    required this.id,
    required this.uid,
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
  final String uid;
  final StatusType type;
  final String text;
  final String? mediaUrl;
  final String? thumbnailUrl;
  final int? durationMs;
  final double? width;
  final double? height;
  final String? mimeType;
  final DateTime createdAt;
  final DateTime expiresAt;

  /// Whether the signed-in viewer has already seen this status.
  final bool isViewed;

  /// Number of people who viewed this status (author's own posts only).
  final int viewCount;

  StatusUpdate copyWith({bool? isViewed, int? viewCount}) {
    return StatusUpdate(
      id: id,
      uid: uid,
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

/// A person who viewed a status, used for the author's "Seen by" list.
class StatusViewer {
  const StatusViewer({
    required this.profile,
    required this.viewedAt,
  });

  final UserProfile profile;
  final DateTime viewedAt;
}

/// A contact's statuses grouped by author, the unit shown in the Updates list
/// and played in the status viewer.
class StatusGroup {
  const StatusGroup({
    required this.author,
    required this.statuses,
  });

  final UserProfile author;

  /// Newest first.
  final List<StatusUpdate> statuses;

  /// Whether any status in this group has not been seen by the viewer yet.
  bool get hasUnseen => statuses.any((StatusUpdate s) => !s.isViewed);
}
