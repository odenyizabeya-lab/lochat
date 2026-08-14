import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

/// Contract for playing a video message from a network URL and rendering it.
///
/// The UI depends only on this interface; the production implementation is
/// [DeviceVideoPlaybackController] (the `video_player` plugin). Tests inject a
/// fake whose [buildView] renders a placeholder.
abstract interface class VideoPlaybackController {
  Future<void> initialize();
  Future<void> play();
  Future<void> pause();
  Future<void> seekTo(Duration position);
  Future<void> setLooping(bool looping);
  Future<void> dispose();

  bool get isInitialized;
  bool get isPlaying;
  Duration? get duration;
  ValueListenable<Duration> get position;

  /// The platform video widget. Only callable after [initialize].
  Widget buildView();
}

/// Factory that builds a [VideoPlaybackController] for a network video URL.
typedef VideoPlaybackControllerFactory = VideoPlaybackController Function(
  String url,
);

/// Production default factory used by the app wiring.
VideoPlaybackController defaultDeviceVideoPlaybackController(String url) =>
    DeviceVideoPlaybackController(url: url);

/// Production [VideoPlaybackController] backed by video_player.
class DeviceVideoPlaybackController implements VideoPlaybackController {
  DeviceVideoPlaybackController({required String url})
      : _controller = VideoPlayerController.networkUrl(Uri.parse(url));

  final VideoPlayerController _controller;
  bool _initialized = false;

  final ValueNotifier<Duration> _position =
      ValueNotifier<Duration>(Duration.zero);

  @override
  bool get isInitialized => _initialized;

  @override
  bool get isPlaying => _controller.value.isPlaying;

  @override
  Duration? get duration => _controller.value.duration;

  @override
  ValueListenable<Duration> get position => _position;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    await _controller.initialize();
    _initialized = true;
    _controller.addListener(_sync);
  }

  void _sync() {
    _position.value = _controller.value.position;
  }

  @override
  Future<void> play() => _controller.play();

  @override
  Future<void> pause() => _controller.pause();

  @override
  Future<void> seekTo(Duration position) => _controller.seekTo(position);

  @override
  Future<void> setLooping(bool looping) => _controller.setLooping(looping);

  @override
  Widget buildView() => VideoPlayer(_controller);

  @override
  Future<void> dispose() async {
    _controller.removeListener(_sync);
    await _controller.dispose();
    _position.dispose();
  }
}
