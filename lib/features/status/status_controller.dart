import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/auth/auth_controller.dart';
import '../chat/data/chat_repository.dart' show MediaUploadTask;
import '../chat/media/chat_media_picker.dart';
import '../chat/media/device_chat_media_picker.dart';
import '../chat/media/video_playback.dart';
import 'data/status_repository.dart';
import 'models/status_update.dart';

/// App-wide state for ephemeral status updates.
///
/// Follows [ChatController]: the status stream is exposed lazily so screens
/// only subscribe while visible, and cached per session. The cache is
/// invalidated when the signed-in user changes. Also owns the media picker
/// and video player factory used by the status screens, so tests can inject
/// fakes.
class StatusController extends ChangeNotifier {
  StatusController({
    required AuthController auth,
    required StatusRepository repository,
    ChatMediaPicker? mediaPicker,
    VideoPlaybackControllerFactory? videoPlaybackFactory,
  })  : _auth = auth,
        _repository = repository,
        _mediaPicker = mediaPicker ?? DeviceChatMediaPicker(),
        _videoPlaybackFactory =
            videoPlaybackFactory ?? defaultDeviceVideoPlaybackController {
    _auth.addListener(_handleAuthChange);
    _handleAuthChange();
  }

  final AuthController _auth;
  final StatusRepository _repository;
  final ChatMediaPicker _mediaPicker;
  final VideoPlaybackControllerFactory _videoPlaybackFactory;  Stream<List<StatusGroup>>? _statusesStream;
  StreamSubscription<List<StatusGroup>>? _statusesSub;
  List<StatusGroup>? _statusesCache;
  String? _uid;

  /// UID of the signed-in user, or null when signed out.
  String? get uid => _uid;

  /// Media picking (photos/videos) for the status composer.
  ChatMediaPicker get mediaPicker => _mediaPicker;

  /// Builds a video player for a video status URL.
  VideoPlaybackControllerFactory get videoPlaybackFactory =>
      _videoPlaybackFactory;

  /// The underlying repository, exposed for reuse (e.g. tests).
  StatusRepository get repository => _repository;

  void _handleAuthChange() {
    final String? uid = _auth.currentUser?.uid;
    if (_uid == uid) return;
    _statusesSub?.cancel();
    _statusesSub = null;
    _statusesStream = null;
    _statusesCache = null;
    _uid = uid;
  }

  /// Live status groups for the signed-in user, newest first.
  ///
  /// Backed by one persistent subscription whose latest snapshot is cached.
  /// Each caller gets a fresh replay stream: it immediately emits the cached
  /// snapshot (so late subscribers never miss the current state) and then
  /// forwards live updates.
  Stream<List<StatusGroup>> watchStatuses() {
    final String? uid = _uid;
    if (uid == null) {
      return Stream<List<StatusGroup>>.empty();
    }
    final Stream<List<StatusGroup>> source =
        _statusesStream ??= _repository.watchStatuses(uid);
    return Stream<List<StatusGroup>>.multi(
      (StreamController<List<StatusGroup>> controller) {
        final List<StatusGroup>? latest = _statusesCache;
        if (latest != null && !controller.isClosed) controller.add(latest);
        late final StreamSubscription<List<StatusGroup>> sub;
        sub = source.listen(
          (List<StatusGroup> value) {
            _statusesCache = value;
            if (!controller.isClosed) controller.add(value);
          },
          onError: (Object e, StackTrace st) {
            if (!controller.isClosed) controller.addError(e, st);
          },
          onDone: () {
            if (!controller.isClosed) controller.close();
          },
        );
        controller.onCancel = () => sub.cancel();
      },
    );
  }

  /// Posts a status for the signed-in user and returns its id. Media statuses
  /// must have already been uploaded. [statusId] should be the id from
  /// [newStatusId] so the media path matches the posted row.
  Future<String> postStatus({
    required StatusType type,
    String text = '',
    String? statusId,
    String? mediaUrl,
    String? thumbnailUrl,
    int? durationMs,
    double? width,
    double? height,
    String? mimeType,
  }) {
    return _repository.postStatus(
      uid: _requireUid(),
      type: type,
      text: text,
      statusId: statusId,
      mediaUrl: mediaUrl,
      thumbnailUrl: thumbnailUrl,
      durationMs: durationMs,
      width: width,
      height: height,
      mimeType: mimeType,
    );
  }

  /// Uploads media for a status and returns a cancellable handle whose
  /// [MediaUploadTask.url] is the stored object path.
  Future<MediaUploadTask> uploadStatusMedia({
    required String statusId,
    required Uint8List bytes,
    required String contentType,
    required String fileName,
  }) {
    return _repository.uploadStatusMedia(
      uid: _requireUid(),
      statusId: statusId,
      bytes: bytes,
      contentType: contentType,
      fileName: fileName,
    );
  }

  /// Uploads a small poster (e.g. a video thumbnail) for a status.
  Future<MediaUploadTask> uploadStatusThumbnail({
    required String statusId,
    required Uint8List bytes,
    required String contentType,
  }) {
    return _repository.uploadStatusThumbnail(
      uid: _requireUid(),
      statusId: statusId,
      bytes: bytes,
      contentType: contentType,
    );
  }

  /// Marks [statusId] as viewed by the signed-in user (idempotent).
  Future<void> markStatusViewed(String statusId) {
    return _repository.markStatusViewed(statusId);
  }

  /// Deletes one of the signed-in user's own statuses and its media.
  Future<void> deleteStatus(String statusId) {
    return _repository.deleteStatus(statusId);
  }

  /// People who viewed [statusId], newest first.
  Future<List<StatusViewer>> fetchStatusViewers(String statusId) {
    return _repository.fetchStatusViewers(statusId);
  }

  /// A fresh client-generated status id. Pass the same id to
  /// [uploadStatusMedia] and [postStatus] so the media object path and the
  /// posted row stay linked.
  String newStatusId() =>
      's_${DateTime.now().microsecondsSinceEpoch}';

  String _requireUid() {
    final String? uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw StateError('No signed-in user.');
    }
    return uid;
  }

  @override
  void dispose() {
    _auth.removeListener(_handleAuthChange);
    super.dispose();
  }
}
