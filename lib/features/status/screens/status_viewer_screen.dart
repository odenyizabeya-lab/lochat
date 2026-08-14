import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/utils/time_utils.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../chat/chat_scope.dart';
import '../../chat/data/chat_repository.dart' show NotAContactException;
import '../../chat/media/video_playback.dart';
import '../../profile/models/user_profile.dart';
import '../models/status_update.dart';
import '../status_controller.dart';
import '../status_scope.dart';

/// Full-screen status viewer, in the style of WhatsApp stories.
///
/// Plays one contact's statuses back to back: a progress bar per item, tap the
/// left/right thirds to go back/forward (the right edge advances; the last
/// item closes), a pause on center tap, auto-advance after ~5 seconds for
/// photos and text, and the actual duration for videos. Own statuses show
/// "Seen by" and a delete action; others show a Reply action.
class StatusViewerScreen extends StatefulWidget {
  const StatusViewerScreen({
    super.key,
    required this.group,
    required this.isOwn,
    this.startIndex = 0,
  });

  final StatusGroup group;
  final bool isOwn;
  final int startIndex;

  @override
  State<StatusViewerScreen> createState() => _StatusViewerScreenState();
}

class _StatusViewerScreenState extends State<StatusViewerScreen>
    with SingleTickerProviderStateMixin {
  static const Duration _photoDuration = Duration(seconds: 5);

  late int _index;
  late AnimationController _progress;
  late StatusController _status;
  VideoPlaybackController? _video;
  bool _videoFailed = false;
  bool _paused = false;
  bool _advancing = false;
  bool _initialized = false;
  final Set<String> _markedViewed = <String>{};
  List<StatusViewer>? _viewers;

  @override
  void initState() {
    super.initState();
    _index = widget.startIndex;
    _progress = AnimationController(vsync: this, duration: _photoDuration);
    _progress.addStatusListener(_onProgressStatus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Resolve the scope here (not initState) so `StatusScope.of` may register
    // its inherited dependency, then run the per-item setup exactly once.
    _status = StatusScope.of(context);
    if (_initialized) return;
    _initialized = true;
    _setupItem(_index);
  }

  @override
  void didUpdateWidget(StatusViewerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.group.statuses.length != widget.group.statuses.length) {
      _index = _index.clamp(0, widget.group.statuses.length - 1);
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    unawaited(_video?.dispose());
    super.dispose();
  }

  void _onProgressStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _advance();
    }
  }

  void _setupItem(int index) {
    unawaited(_video?.dispose());
    _video = null;
    _videoFailed = false;
    _advancing = false;
    _viewers = null;

    final StatusUpdate item = widget.group.statuses[index];

    if (widget.isOwn) {
      _loadViewers(item.id);
    } else {
      _markViewed(item.id);
    }

    if (item.type == StatusType.video && item.mediaUrl != null) {
      _playVideo(item);
    } else {
      _progress
        ..stop()
        ..value = 0;
      if (!_paused) {
        _progress.forward();
      }
    }
  }

  void _playVideo(StatusUpdate item) {
    final VideoPlaybackController video =
        _status.videoPlaybackFactory(item.mediaUrl!);
    _video = video;
    _progress.stop();
    unawaited(() async {
      try {
        await video.initialize();
        if (!mounted || _video != video) return;
        await video.setLooping(false);
        _videoFailed = false;
        if (mounted) setState(() {});
        video.position.addListener(_onVideoPosition);
        if (!_paused) {
          await video.play();
        }
      } catch (_) {
        if (!mounted || _video != video) return;
        setState(() => _videoFailed = true);
        _progress
          ..stop()
          ..value = 0;
        if (!_paused) {
          _progress.forward();
        }
      }
    }());
  }

  void _onVideoPosition() {
    final VideoPlaybackController? video = _video;
    if (video == null || _advancing) return;
    final Duration? duration = video.duration;
    if (duration == null || duration.inMilliseconds <= 0) return;
    if (video.position.value >= duration) {
      _advance();
    }
  }

  void _markViewed(String statusId) {
    if (_markedViewed.contains(statusId)) return;
    _markedViewed.add(statusId);
    unawaited(_status.markStatusViewed(statusId).catchError(
          (Object _) => <void>{},
        ));
  }

  Future<void> _loadViewers(String statusId) async {
    try {
      final List<StatusViewer> viewers =
          await _status.fetchStatusViewers(statusId);
      if (mounted) {
        setState(() => _viewers = viewers);
      }
    } catch (_) {
      // Seen-by is best effort; hide the row on failure.
    }
  }

  void _advance() {
    if (_advancing) return;
    _advancing = true;
    if (_index >= widget.group.statuses.length - 1) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _index += 1);
    _setupItem(_index);
  }

  void _goBack() {
    _advancing = true;
    if (_index <= 0) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _index -= 1);
    _setupItem(_index);
  }

  void _togglePause() {
    setState(() => _paused = !_paused);
    final VideoPlaybackController? video = _video;
    if (video != null && video.isInitialized) {
      if (_paused) {
        unawaited(video.pause());
      } else {
        unawaited(video.play());
      }
    } else if (!_videoFailed) {
      if (_paused) {
        _progress.stop();
      } else {
        _progress.forward();
      }
    }
  }

  void _handleTap(TapUpDetails details) {
    final Size size = MediaQuery.of(context).size;
    if (details.localPosition.dx < size.width / 3) {
      _goBack();
    } else if (details.localPosition.dx > size.width * 2 / 3) {
      _advance();
    } else {
      _togglePause();
    }
  }

  Future<void> _deleteOwn() async {
    final StatusUpdate item = widget.group.statuses[_index];
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Delete status?'),
        content: const Text(
            'This status will be deleted for everyone who can see it.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await _status.deleteStatus(item.id);
      if (!mounted) return;
      Navigator.of(context).pop();
      AppSnackbars.showInfo(context, 'Status deleted.');
    } catch (_) {
      if (mounted) AppSnackbars.showError(context, 'Could not delete status.');
    }
  }

  void _reply() {
    final UserProfile author = widget.group.author;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    unawaited(() async {
      try {
        final String conversationId =
            await ChatScope.of(context).openConversation(author.uid);
        router.push(AppRoutes.chatFor(conversationId));
      } on NotAContactException {
        messenger.showSnackBar(
          SnackBar(content: Text('Add ${author.displayName} as a contact to reply.')),
        );
      }
    }());
  }

  void _showViewers() {
    final List<StatusViewer> viewers = _viewers ?? const <StatusViewer>[];
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) => SafeArea(
        child: viewers.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No one has seen this status yet.'),
              )
            : ListView.builder(
                shrinkWrap: true,
                itemCount: viewers.length,
                itemBuilder: (BuildContext context, int index) {
                  final StatusViewer viewer = viewers[index];
                  return ListTile(
                    leading: UserAvatar(
                      name: viewer.profile.displayName.isNotEmpty
                          ? viewer.profile.displayName
                          : viewer.profile.username,
                      photoURL: viewer.profile.photoURL,
                      size: 40,
                    ),
                    title: Text(
                      viewer.profile.displayName.isNotEmpty
                          ? viewer.profile.displayName
                          : viewer.profile.username,
                    ),
                    subtitle: Text(formatChatTime(viewer.viewedAt)),
                  );
                },
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<StatusUpdate> statuses = widget.group.statuses;
    if (statuses.isEmpty) {
      return const Scaffold(body: SizedBox.shrink());
    }
    final StatusUpdate item = statuses[_index];
    final Listenable progressSource =
        item.type == StatusType.video && _video != null && !_videoFailed
            ? _video!.position
            : _progress;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: _handleTap,
              child: _buildItem(item),
            ),
          ),
          // Scrims for header/footer legibility.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Container(
                height: 110,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[Colors.black87, Colors.transparent],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Container(
                height: 90,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: <Color>[Colors.black87, Colors.transparent],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: <Widget>[
                _buildProgressRow(statuses, item, progressSource),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: _buildHeader(item),
                ),
                const Spacer(),
                _buildFooter(item),
              ],
            ),
          ),
          if (_paused)
            const Center(
              child: Icon(Icons.pause_circle_filled_rounded,
                  color: Colors.white70, size: 56),
            ),
        ],
      ),
    );
  }

  Widget _buildItem(StatusUpdate item) {
    switch (item.type) {
      case StatusType.image:
        if (item.mediaUrl != null) {
          return Image.network(
            item.mediaUrl!,
            fit: BoxFit.contain,
            width: double.infinity,
            height: double.infinity,
            loadingBuilder: (BuildContext context, Widget child,
                ImageChunkEvent? progress) {
              if (progress == null) return child;
              return const Center(
                child: CircularProgressIndicator(color: Colors.white38),
              );
            },
            errorBuilder: (BuildContext context, Object error, StackTrace? st) =>
                const Center(
              child: Icon(Icons.broken_image_outlined,
                  color: Colors.white38, size: 64),
            ),
          );
        }
        return _buildTextItem(item);
      case StatusType.video:
        final VideoPlaybackController? video = _video;
        if (video != null && video.isInitialized && !_videoFailed) {
          return Center(
            child: AspectRatio(
              aspectRatio: _videoAspectRatio(item),
              child: video.buildView(),
            ),
          );
        }
        if (item.thumbnailUrl != null) {
          return Image.network(
            item.thumbnailUrl!,
            fit: BoxFit.contain,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (BuildContext context, Object error, StackTrace? st) =>
                _buildTextItem(item),
          );
        }
        return _buildTextItem(item);
      case StatusType.text:
        return _buildTextItem(item);
    }
  }

  double _videoAspectRatio(StatusUpdate item) {
    if (item.width != null &&
        item.height != null &&
        item.width! > 0 &&
        item.height! > 0) {
      return item.width! / item.height!;
    }
    return 16 / 9;
  }

  Widget _buildTextItem(StatusUpdate item) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF8B5CF6), Color(0xFF4F46E5)],
        ),
      ),
      child: Center(
        child: SingleChildScrollView(
          child: Text(
            item.text.isEmpty ? '...' : item.text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProgressRow(
    List<StatusUpdate> statuses,
    StatusUpdate item,
    Listenable progressSource,
  ) {
    return ListenableBuilder(
      listenable: progressSource,
      builder: (BuildContext context, Widget? _) {
        final double current = _progressValue(item);
        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Row(
            children: <Widget>[
              for (int i = 0; i < statuses.length; i++)
                Expanded(
                  child: Container(
                    height: 3,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: i < _index
                          ? 1
                          : (i == _index ? current : 0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  double _progressValue(StatusUpdate item) {
    if (item.type == StatusType.video && !_videoFailed) {
      final VideoPlaybackController? video = _video;
      final Duration? duration = video?.duration;
      if (video == null ||
          duration == null ||
          duration.inMilliseconds <= 0) {
        return 0;
      }
      return (video.position.value.inMilliseconds /
              duration.inMilliseconds)
          .clamp(0.0, 1.0);
    }
    return _progress.value;
  }

  Widget _buildHeader(StatusUpdate item) {
    final String name = widget.group.author.displayName.isNotEmpty
        ? widget.group.author.displayName
        : widget.group.author.username;
    return Row(
      children: <Widget>[
        IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        UserAvatar(
          name: name,
          photoURL: widget.group.author.photoURL,
          size: 36,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              Text(
                formatChatTime(item.createdAt),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
        if (widget.isOwn)
          IconButton(
            tooltip: 'Delete status',
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.white),
            onPressed: _deleteOwn,
          ),
      ],
    );
  }

  Widget _buildFooter(StatusUpdate item) {
    if (widget.isOwn) {
      final int count = _viewers?.length ?? 0;
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            TextButton.icon(
              onPressed: count == 0 ? null : _showViewers,
              icon: const Icon(Icons.visibility_outlined,
                  color: Colors.white70, size: 20),
              label: Text(
                'Seen by $count',
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: 'Reply',
            icon: const Icon(Icons.reply_rounded, color: Colors.white),
            onPressed: _reply,
          ),
          const Spacer(),
          Text(
            'Reply to ${widget.group.author.displayName.isNotEmpty ? widget.group.author.displayName : widget.group.author.username}',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
