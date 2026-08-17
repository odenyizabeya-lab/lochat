import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/utils/time_utils.dart';
import '../../features/profile/models/user_profile.dart';
import '../../shared/widgets/user_avatar.dart';
import '../../features/chat/media/video_playback.dart';
import './managed_chat_controller.dart';
import './managed_chat_scope.dart';
import './models/managed_status.dart';

/// Full-screen status viewer for an admin-managed account's statuses, in the
/// style of WhatsApp stories: a progress bar per item, tap left/right thirds to
/// navigate, pause on center tap, auto-advance for photos/text and the real
/// duration for videos.
class AdminManagedStatusViewerScreen extends StatefulWidget {
  const AdminManagedStatusViewerScreen({
    super.key,
    required this.managedAccountId,
    required this.statuses,
    this.startIndex = 0,
  });

  final String managedAccountId;
  final List<ManagedStatus> statuses;
  final int startIndex;

  @override
  State<AdminManagedStatusViewerScreen> createState() =>
      _AdminManagedStatusViewerScreenState();
}

class _AdminManagedStatusViewerScreenState
    extends State<AdminManagedStatusViewerScreen>
    with SingleTickerProviderStateMixin {
  static const Duration _photoDuration = Duration(seconds: 5);

  late int _index;
  late AnimationController _progress;
  ManagedChatController? _chat;
  bool _paused = false;
  bool _advancing = false;
  bool _initialized = false;
  bool _videoFailed = false;
  VideoPlaybackController? _video;
  List<ManagedStatusViewer>? _viewers;

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
    _chat ??= ManagedChatScope.of(context);
    if (_initialized) return;
    _initialized = true;
    _setupItem(_index);
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

    final ManagedStatus item = widget.statuses[index];

    _loadViewers(item.id);

    if (item.type == ManagedStatusType.video && item.mediaUrl != null) {
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

  void _playVideo(ManagedStatus item) {
    final String? url = item.mediaUrl;
    if (url == null) {
      _videoFailed = true;
      _progress
        ..stop()
        ..value = 0;
      if (!_paused) _progress.forward();
      return;
    }
    final VideoPlaybackController video = _videoFactory(url);
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

  VideoPlaybackController _videoFactory(String url) {
    final ManagedChatController? chat = _chat;
    if (chat == null) {
      return defaultDeviceVideoPlaybackController(url);
    }
    return chat.videoPlaybackFactory(url);
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

  Future<void> _loadViewers(String statusId) async {
    try {
      final List<ManagedStatusViewer> viewers =
          await _chat!.fetchStatusViewers(statusId);
      if (mounted) setState(() => _viewers = viewers);
    } catch (_) {
      // Leave the list empty.
    }
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

  void _advance() {
    if (_advancing) return;
    _advancing = true;
    if (_index + 1 < widget.statuses.length) {
      setState(() {
        _index += 1;
        _setupItem(_index);
      });
    } else {
      _close();
    }
  }

  void _back() {
    if (_advancing) return;
    _advancing = true;
    if (_index > 0) {
      setState(() {
        _index -= 1;
        _setupItem(_index);
      });
    } else {
      _close();
    }
  }

  void _close() {
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _delete(ManagedStatus item) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Delete status?'),
        content: const Text('This status will be removed permanently.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await _chat!.deleteStatus(item.id);
    } catch (_) {
      // The list stream will refresh anyway.
    }
    _advance();
  }

  @override
  Widget build(BuildContext context) {
    final ManagedStatus item = widget.statuses[_index];
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (TapUpDetails details) {
                  final double width = MediaQuery.of(context).size.width;
                  if (details.globalPosition.dx < width / 3) {
                    _back();
                  } else if (details.globalPosition.dx > width * 2 / 3) {
                    _advance();
                  } else {
                    _togglePause();
                  }
                },
                child: _content(item),
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              right: 8,
              child: _ProgressBar(
                total: widget.statuses.length,
                index: _index,
                animation: _progress,
              ),
            ),
            Positioned(
              top: 28,
              left: 16,
              right: 16,
              child: Row(
                children: <Widget>[
                  const CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.white24,
                    child: Icon(Icons.admin_panel_settings_rounded,
                        color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Your status \u00b7 ${formatChatTime(item.createdAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 15),
                    ),
                  ),
                  PopupMenuButton<String>(
                    color: Colors.white,
                    onSelected: (String value) {
                      if (value == 'delete') unawaited(_delete(item));
                    },
                    itemBuilder: (BuildContext context) =>
                        <PopupMenuEntry<String>>[
                      const PopupMenuItem<String>(
                        value: 'delete',
                        child: Row(
                          children: <Widget>[
                            Icon(Icons.delete_outline_rounded,
                                color: Colors.red),
                            SizedBox(width: 10),
                            Text('Delete'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (item.text.isNotEmpty)
              Positioned(
                left: 24,
                right: 24,
                bottom: 96,
                child: Text(
                  item.text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    shadows: <Shadow>[
                      Shadow(color: Colors.black54, blurRadius: 8),
                    ],
                  ),
                ),
              ),
            if (_viewers != null && _viewers!.isNotEmpty)
              Positioned(
                left: 16,
                right: 16,
                bottom: 24,
                child: _ViewersStrip(
                  viewers: _viewers!,
                  onExpand: () => _showViewersSheet(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _content(ManagedStatus item) {
    switch (item.type) {
      case ManagedStatusType.image:
        final String? url = item.mediaUrl;
        if (url == null) {
          return const Center(
            child: Icon(Icons.broken_image_outlined,
                color: Colors.white38, size: 64),
          );
        }
        return Image.network(url, fit: BoxFit.contain);
      case ManagedStatusType.video:
        final String? url = item.mediaUrl;
        if (url == null || _videoFailed) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (item.thumbnailUrl != null)
                  Image.network(item.thumbnailUrl!, fit: BoxFit.contain)
                else
                  const Icon(Icons.videocam_rounded,
                      color: Colors.white38, size: 64),
              ],
            ),
          );
        }
        return const SizedBox.expand();
      case ManagedStatusType.text:
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[Color(0xFF8B5CF6), Color(0xFF4F46E5)],
            ),
          ),
          alignment: Alignment.center,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              item.text.isEmpty ? 'Your status' : item.text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
    }
  }

  void _showViewersSheet() {
    final List<ManagedStatusViewer>? viewers = _viewers;
    if (viewers == null || viewers.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Text(
                'Seen by ${viewers.length}',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: <Widget>[
                  for (final ManagedStatusViewer viewer in viewers)
                    ListTile(
                      leading: UserAvatar(
                        name: _nameOf(viewer.profile),
                        photoURL: viewer.profile.photoURL,
                        size: 40,
                      ),
                      title: Text(_nameOf(viewer.profile)),
                      subtitle: Text(
                        formatChatTime(viewer.viewedAt),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _nameOf(UserProfile profile) {
    final String display = profile.displayName;
    final String username = profile.username;
    return display.isNotEmpty ? display : username;
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.total,
    required this.index,
    required this.animation,
  });

  final int total;
  final int index;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        for (int i = 0; i < total; i++)
          Expanded(
            child: Container(
              height: 3,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
              child: Stack(
                children: <Widget>[
                  if (i < index)
                    FractionallySizedBox(
                      widthFactor: 1,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  if (i == index)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: AnimatedBuilder(
                        animation: animation,
                        builder: (BuildContext context, Widget? child) {
                          return FractionallySizedBox(
                            widthFactor: animation.value,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ViewersStrip extends StatelessWidget {
  const _ViewersStrip({required this.viewers, required this.onExpand});

  final List<ManagedStatusViewer> viewers;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onExpand,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Icon(Icons.visibility_rounded, color: Colors.white70, size: 18),
          const SizedBox(width: 6),
          for (int i = 0; i < viewers.length && i < 4; i++)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: CircleAvatar(
                radius: 12,
                backgroundColor: Colors.white24,
                backgroundImage: viewers[i].profile.photoURL != null
                    ? NetworkImage(viewers[i].profile.photoURL!)
                    : null,
                child: viewers[i].profile.photoURL == null
                    ? Text(
                        _initial(viewers[i].profile),
                        style: const TextStyle(
                            color: Colors.white, fontSize: 10),
                      )
                    : null,
              ),
            ),
          if (viewers.length > 4)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                '+${viewers.length - 4}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          const SizedBox(width: 8),
          Text(
            '${viewers.length}',
            style: const TextStyle(
                color: Colors.white70, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  String _initial(UserProfile profile) {
    final String name = _nameOf(profile);
    return name.isEmpty ? '?' : name[0].toUpperCase();
  }

  String _nameOf(UserProfile profile) {
    final String display = profile.displayName;
    final String username = profile.username;
    return display.isNotEmpty ? display : username;
  }
}