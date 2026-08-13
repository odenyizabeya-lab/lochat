import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/utils/time_utils.dart';
import 'media/video_playback.dart';

/// Full-screen video player with play/pause, a seek bar, and elapsed/total
/// time. Opens from video message bubbles.
///
/// Accepts an optional injected [VideoPlaybackController] so tests can supply a
/// fake; production builds its own [DeviceVideoPlaybackController].
class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({
    super.key,
    required this.url,
    this.messageId,
    this.controller,
  });

  final String url;
  final String? messageId;

  /// Injectable player for tests; defaults to the device player.
  final VideoPlaybackController? controller;

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final VideoPlaybackController _controller;
  VoidCallback? _positionListener;

  bool _initializing = true;
  bool _failed = false;
  bool _controlsVisible = true;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ?? defaultDeviceVideoPlaybackController(widget.url);
    _init();
  }

  Future<void> _init() async {
    try {
      await _controller.initialize();
      if (!mounted) return;
      _positionListener = () {
        if (mounted) setState(() => _position = _controller.position.value);
      };
      _controller.position.addListener(_positionListener!);
      await _controller.setLooping(false);
      await _controller.play();
      if (!mounted) return;
      setState(() => _initializing = false);
    } on Exception {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _failed = true;
      });
    }
  }

  @override
  void dispose() {
    final VoidCallback? listener = _positionListener;
    if (listener != null) _controller.position.removeListener(listener);
    unawaited(_controller.dispose());
    super.dispose();
  }

  void _togglePlay() {
    if (_controller.isPlaying) {
      unawaited(_controller.pause());
    } else {
      unawaited(_controller.play());
    }
  }

  void _seek(Duration position) {
    _position = position;
    unawaited(_controller.seekTo(position));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: _buildStage(context),
            ),
            _buildControls(context),
          ],
        ),
      ),
    );
  }

  Widget _buildStage(BuildContext context) {
    if (_initializing) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_failed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.videocam_off_outlined,
              color: Colors.white70,
              size: 56,
            ),
            const SizedBox(height: 12),
            const Text(
              'Could not play this video.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                setState(() {
                  _initializing = true;
                  _failed = false;
                });
                unawaited(_init());
              },
              child: const Text('Try again'),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _controlsVisible = !_controlsVisible),
      child: Center(
        child: _controller.buildView(),
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    if (_initializing || _failed) {
      return const SizedBox(height: 8);
    }
    if (!_controlsVisible) {
      return const SizedBox(height: 8);
    }

    final Duration? total = _controller.duration;
    final double maxMs =
        (total == null || total.inMilliseconds <= 0) ? 1 : total.inMilliseconds.toDouble();

    return Container(
      color: Colors.black,
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: _controller.isPlaying ? 'Pause' : 'Play',
            onPressed: _togglePlay,
            icon: Icon(
              _controller.isPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              color: Colors.white,
            ),
          ),
          Expanded(
            child: Slider(
              min: 0,
              max: maxMs,
              value: _position.inMilliseconds
                  .clamp(0, maxMs.toInt())
                  .toDouble(),
              onChanged: (double value) => _seek(Duration(milliseconds: value.round())),
              onChangeEnd: (double value) => _seek(Duration(milliseconds: value.round())),
            ),
          ),
          Text(
            '${formatDuration(_position)} / ${formatDuration(total ?? Duration.zero)}',
            style: theme.textTheme.labelMedium?.copyWith(color: Colors.white70),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}
