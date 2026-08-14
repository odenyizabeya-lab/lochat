import 'dart:async';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;

import '../../chat/data/chat_repository.dart' show MediaUploadTask;
import '../../profile/models/user_profile.dart';
import '../models/status_update.dart';
import 'status_repository.dart';

/// Production [StatusRepository] backed by Supabase (Postgres + Realtime +
/// Storage).
///
/// Storage layout:
/// - `statuses`    - one row per post. Inserts/deletes/view-stamps go through
///   SECURITY DEFINER RPCs ([post_status], [delete_status],
///   [mark_status_viewed]) so the author check, the 24h expiry and the
///   "author's contacts" visibility rule are enforced server-side.
/// - `status_views`- one row per viewer per status (PK status_id, viewer_uid).
/// - `status_media`- private bucket, objects at `{uid}/{statusId}` (and
///   `{uid}/{statusId}_thumb`). The DB stores object paths; signed URLs are
///   resolved at render time, like `chat_media`.
class SupabaseStatusRepository implements StatusRepository {
  SupabaseStatusRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// Object-path -> signed URL cache so realtime re-emissions don't re-sign
  /// every status. Entries are refreshed before expiry.
  final Map<String, String> _signedUrlCache = <String, String>{};
  final Map<String, DateTime> _signedUrlExpiresAt = <String, DateTime>{};
  static const int _signedUrlLifetimeSeconds = 3600;
  static const Duration _signedUrlRefreshMargin = Duration(minutes: 10);

  @override
  Stream<List<StatusGroup>> watchStatuses(String uid) {
    return Stream<List<StatusGroup>>.multi(
      (StreamController<List<StatusGroup>> controller) {
        Timer? debounce;
        Timer? periodic;
        bool refreshing = false;

        Future<void> refresh() async {
          if (refreshing) return;
          refreshing = true;
          try {
            final List<StatusGroup> groups = await _load(uid);
            if (!controller.isClosed) controller.add(groups);
          } catch (e, st) {
            if (!controller.isClosed) controller.addError(e, st);
          } finally {
            refreshing = false;
          }
        }

        // Realtime fires on any status/view change the caller can read. Debounce
        // bursts, then re-query: the query applies the expiry filter and resolves
        // fresh signed URLs, so the stream never goes stale or shows expired
        // posts. A 60s heartbeat also covers the "no events" case while the app
        // stays open past a post's 24h expiry.
        void scheduleRefresh() {
          debounce?.cancel();
          debounce = Timer(const Duration(milliseconds: 300), refresh);
        }

        final StreamSubscription<List<Map<String, dynamic>>> statusesSub =
            _client
                .from('statuses')
                .stream(primaryKey: <String>['id'])
                .listen((_) => scheduleRefresh());
        final StreamSubscription<List<Map<String, dynamic>>> viewsSub = _client
            .from('status_views')
            .stream(primaryKey: <String>['status_id', 'viewer_uid'])
            .listen((_) => scheduleRefresh());
        periodic = Timer.periodic(const Duration(seconds: 60), (_) {
          scheduleRefresh();
        });

        unawaited(refresh());

        controller.onCancel = () {
          debounce?.cancel();
          periodic?.cancel();
          statusesSub.cancel();
          viewsSub.cancel();
        };
      },
    );
  }

  Future<List<StatusGroup>> _load(String uid) async {
    final List<Map<String, dynamic>> rows = await _client
        .from('statuses')
        .select()
        .gt('expires_at', DateTime.now().toUtc().toIso8601String())
        .order('created_at_ms', ascending: false)
        .limit(200);
    if (rows.isEmpty) return <StatusGroup>[];

    final List<StatusUpdate> statuses = <StatusUpdate>[];
    final List<String> authorIds = <String>[];
    final List<String> myStatusIds = <String>[];
    for (final Map<String, dynamic> row in rows) {
      final StatusUpdate status = await _toStatus(row);
      statuses.add(status);
      final String author = status.uid;
      if (!authorIds.contains(author)) authorIds.add(author);
      if (author == uid) myStatusIds.add(status.id);
    }

    // Statuses this viewer has already seen.
    final List<Map<String, dynamic>> myViews = await _client
        .from('status_views')
        .select('status_id')
        .eq('viewer_uid', uid);
    final Set<String> viewed =
        myViews.map((Map<String, dynamic> r) => r['status_id'] as String).toSet();

    // "Seen by" counts for the caller's own statuses.
    final Map<String, int> viewCounts = <String, int>{};
    if (myStatusIds.isNotEmpty) {
      final List<Map<String, dynamic>> viewRows = await _client
          .from('status_views')
          .select('status_id')
          .inFilter('status_id', myStatusIds);
      for (final Map<String, dynamic> r in viewRows) {
        final String id = r['status_id'] as String;
        viewCounts[id] = (viewCounts[id] ?? 0) + 1;
      }
    }

    // Author profiles (avatars, names) for the status rows.
    final Map<String, UserProfile> profiles = <String, UserProfile>{};
    if (authorIds.isNotEmpty) {
      final List<Map<String, dynamic>> profileRows = await _client
          .from('profiles')
          .select()
          .inFilter('uid', authorIds);
      for (final Map<String, dynamic> r in profileRows) {
        final UserProfile profile = _toProfile(r);
        profiles[profile.uid] = profile;
      }
    }

    // Group newest-first statuses by author, groups sorted by their latest post.
    final Map<String, List<StatusUpdate>> grouped = <String, List<StatusUpdate>>{};
    for (final StatusUpdate raw in statuses) {
      final StatusUpdate status = raw.copyWith(
        isViewed: viewed.contains(raw.id),
        viewCount: viewCounts[raw.id] ?? 0,
      );
      grouped.putIfAbsent(status.uid, () => <StatusUpdate>[]).add(status);
    }

    final List<StatusGroup> groups = grouped.entries.map((MapEntry<String, List<StatusUpdate>> e) {
      final String authorId = e.key;
      final UserProfile profile = profiles[authorId] ??
          UserProfile(uid: authorId, username: '', displayName: '');
      return StatusGroup(author: profile, statuses: e.value);
    }).toList();
    groups.sort((StatusGroup a, StatusGroup b) =>
        b.statuses.first.createdAt.compareTo(a.statuses.first.createdAt));
    return groups;
  }

  @override
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
  }) async {
    final dynamic result = await _client.rpc('post_status', params: <String, dynamic>{
      'p_type': type.name,
      'p_text': text.trim(),
      'p_status_id': _nullIfEmpty(statusId),
      'p_media_url': _nullIfEmpty(mediaUrl),
      'p_thumbnail_url': _nullIfEmpty(thumbnailUrl),
      'p_duration_ms': durationMs,
      'p_width': width,
      'p_height': height,
      'p_mime_type': _nullIfEmpty(mimeType),
    });
    return result?.toString() ?? '';
  }

  @override
  Future<MediaUploadTask> uploadStatusMedia({
    required String uid,
    required String statusId,
    required Uint8List bytes,
    required String contentType,
    required String fileName,
  }) {
    return Future<MediaUploadTask>.value(_SupabaseStatusUploadTask(
      storage: _client.storage.from('status_media'),
      path: '$uid/$statusId',
      bytes: bytes,
      contentType: contentType,
      fileName: fileName,
    ));
  }

  @override
  Future<MediaUploadTask> uploadStatusThumbnail({
    required String uid,
    required String statusId,
    required Uint8List bytes,
    required String contentType,
  }) {
    return Future<MediaUploadTask>.value(_SupabaseStatusUploadTask(
      storage: _client.storage.from('status_media'),
      path: '$uid/${statusId}_thumb',
      bytes: bytes,
      contentType: contentType,
      fileName: '',
    ));
  }

  @override
  Future<void> markStatusViewed(String statusId) async {
    await _client.rpc('mark_status_viewed', params: <String, dynamic>{
      'p_status_id': statusId,
    });
  }

  @override
  Future<void> deleteStatus(String statusId) async {
    await _client.rpc('delete_status', params: <String, dynamic>{
      'p_status_id': statusId,
    });
  }

  @override
  Future<List<StatusViewer>> fetchStatusViewers(String statusId) async {
    final List<Map<String, dynamic>> rows = await _client
        .from('status_views')
        .select()
        .eq('status_id', statusId)
        .order('viewed_at', ascending: false)
        .limit(100);
    if (rows.isEmpty) return <StatusViewer>[];
    final List<String> uids = <String>[];
    for (final Map<String, dynamic> row in rows) {
      final String viewerUid = row['viewer_uid'] as String;
      if (!uids.contains(viewerUid)) uids.add(viewerUid);
    }
    final Map<String, UserProfile> profiles = <String, UserProfile>{};
    final List<Map<String, dynamic>> profileRows = await _client
        .from('profiles')
        .select()
        .inFilter('uid', uids);
    for (final Map<String, dynamic> r in profileRows) {
      final UserProfile profile = _toProfile(r);
      profiles[profile.uid] = profile;
    }
    return rows.map((Map<String, dynamic> row) {
      final String viewerUid = row['viewer_uid'] as String;
      return StatusViewer(
        profile: profiles[viewerUid] ??
            UserProfile(uid: viewerUid, username: '', displayName: ''),
        viewedAt: _toDate(row['viewed_at']) ?? DateTime.now(),
      );
    }).toList();
  }

  Future<StatusUpdate> _toStatus(Map<String, dynamic> data) {
    final int createdAtMs = (data['created_at_ms'] as num?)?.toInt() ?? 0;
    return Future<StatusUpdate>(() async {
      return StatusUpdate(
        id: (data['id'] as String?) ?? '',
        uid: (data['uid'] as String?) ?? '',
        type: _toType((data['type'] as String?) ?? 'text'),
        text: (data['text'] as String?) ?? '',
        mediaUrl: await _resolveMediaUrl(_nullIfEmpty(data['media_url'] as String?)),
        thumbnailUrl:
            await _resolveMediaUrl(_nullIfEmpty(data['thumbnail_url'] as String?)),
        durationMs: (data['duration_ms'] as num?)?.toInt(),
        width: (data['width'] as num?)?.toDouble(),
        height: (data['height'] as num?)?.toDouble(),
        mimeType: _nullIfEmpty(data['mime_type'] as String?),
        createdAt: _toDate(data['created_at']) ??
            DateTime.fromMillisecondsSinceEpoch(createdAtMs),
        expiresAt: _toDate(data['expires_at']) ?? DateTime.now(),
      );
    });
  }

  Future<String?> _resolveMediaUrl(String? path) async {
    if (path == null || path.isEmpty) return null;
    final DateTime now = DateTime.now();
    final DateTime? cachedUntil = _signedUrlExpiresAt[path];
    if (cachedUntil != null && cachedUntil.isAfter(now)) {
      return _signedUrlCache[path];
    }
    try {
      final String url = await _client.storage
          .from('status_media')
          .createSignedUrl(path, _signedUrlLifetimeSeconds);
      _signedUrlCache[path] = url;
      _signedUrlExpiresAt[path] = now
          .add(const Duration(seconds: _signedUrlLifetimeSeconds))
          .subtract(_signedUrlRefreshMargin);
      return url;
    } catch (_) {
      return null;
    }
  }

  StatusType _toType(String value) => switch (value) {
        'image' => StatusType.image,
        'video' => StatusType.video,
        _ => StatusType.text,
      };

  UserProfile _toProfile(Map<String, dynamic> data) {
    return UserProfile(
      uid: (data['uid'] as String?) ?? '',
      username: (data['username'] as String?) ?? '',
      displayName: (data['display_name'] as String?) ?? '',
      lotextId: _nullIfEmpty(data['lotext_id'] as String?),
      photoURL: _nullIfEmpty(data['photo_url'] as String?),
      isOnline: (data['is_online'] as bool?) ?? false,
      lastSeen: _toDate(data['last_seen']),
    );
  }

  String? _nullIfEmpty(String? value) =>
      (value == null || value.isEmpty) ? null : value;

  DateTime? _toDate(Object? value) {
    if (value is String) {
      final DateTime? parsed = DateTime.tryParse(value);
      return parsed?.toLocal();
    }
    return null;
  }
}

/// Bridges a Supabase status upload to the app's [MediaUploadTask] contract.
class _SupabaseStatusUploadTask implements MediaUploadTask {
  _SupabaseStatusUploadTask({
    required this._storage,
    required this._path,
    required this._bytes,
    required this._contentType,
    required this._fileName,
  });

  final StorageFileApi _storage;
  final String _path;
  final Uint8List _bytes;
  final String _contentType;
  final String _fileName;

  final StreamController<double> _progressController =
      StreamController<double>.broadcast();
  Future<void>? _uploadFuture;

  @override
  Stream<double> get progress => _progressController.stream;

  @override
  Future<String> get url async {
    await _upload();
    return _path;
  }

  Future<void> _upload() {
    if (_uploadFuture != null) return _uploadFuture!;
    _progressController.add(0);
    final Future<void> future = () async {
      try {
        await _storage.uploadBinary(
          _path,
          _bytes,
          fileOptions: FileOptions(
            contentType: _contentType,
            upsert: true,
            metadata: <String, String>{'fileName': _fileName},
          ),
        );
        if (!_progressController.isClosed) {
          _progressController.add(1);
        }
      } catch (_) {
        if (!_progressController.isClosed) {
          _progressController.close();
        }
        rethrow;
      }
    }();
    _uploadFuture = future;
    return future;
  }

  @override
  Future<void> cancel() async {
    if (_progressController.isClosed) return;
    await _progressController.close();
  }
}
