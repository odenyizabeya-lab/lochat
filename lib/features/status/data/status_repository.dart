import 'dart:typed_data';

import '../../chat/data/chat_repository.dart' show MediaUploadTask;
import '../models/status_update.dart';

/// Contract for ephemeral status updates (the Updates tab).
///
/// The UI depends only on this interface; the production implementation is
/// [SupabaseStatusRepository]. Tests may supply a fake implementation.
abstract interface class StatusRepository {
  /// Live list of status groups for [uid]: the caller's own posts plus those
  /// of everyone whose status the caller can read. Newest first, groups sorted
  /// by their latest status.
  Stream<List<StatusGroup>> watchStatuses(String uid);

  /// Posts a status for [uid] and returns its id. Media statuses must have
  /// already been uploaded (the object path goes in [mediaUrl]). [statusId] is
  /// the client-generated id used for the storage path, so the row id matches
  /// the media object (which lets deletes find the objects).
  Future<String> postStatus({
    required String uid,
    required StatusType type,
    String text = '',
    String? statusId,
    String? mediaUrl,
    String? thumbnailUrl,
    int? durationMs,
    double? width,
    double? height,
    String? mimeType,
  });

  /// Uploads the status media and returns a handle whose [MediaUploadTask.url]
  /// is the stored object path (`{uid}/{statusId}`).
  Future<MediaUploadTask> uploadStatusMedia({
    required String uid,
    required String statusId,
    required Uint8List bytes,
    required String contentType,
    required String fileName,
  });

  /// Uploads a small poster (e.g. a video thumbnail) for [statusId].
  Future<MediaUploadTask> uploadStatusThumbnail({
    required String uid,
    required String statusId,
    required Uint8List bytes,
    required String contentType,
  });

  /// Marks [statusId] as viewed by the caller (idempotent; ignored when the
  /// caller is the author or not a contact).
  Future<void> markStatusViewed(String statusId);

  /// Deletes one of the caller's own statuses and its media.
  Future<void> deleteStatus(String statusId);

  /// People who viewed [statusId] (author's own statuses only), newest first.
  Future<List<StatusViewer>> fetchStatusViewers(String statusId);
}
