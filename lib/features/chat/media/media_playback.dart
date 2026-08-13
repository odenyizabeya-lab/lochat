import 'package:just_audio/just_audio.dart';

/// Contract for playing a voice message from a network URL.
///
/// The UI depends only on this interface; the production implementation is
/// [DeviceVoicePlayer] (the `just_audio` plugin). Tests inject a fake.
abstract interface class VoicePlayer {
  Future<void> load(String url);
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> dispose();

  /// Current playback position.
  Stream<Duration> get position;

  /// Total length, null while unknown (e.g. loading).
  Stream<Duration?> get duration;

  /// Whether audio is currently playing.
  Stream<bool> get playing;

  /// True while the source is loading or buffering.
  Stream<bool> get loading;
}

/// Production [VoicePlayer] backed by just_audio.
class DeviceVoicePlayer implements VoicePlayer {
  DeviceVoicePlayer({AudioPlayer? player}) : _player = player ?? AudioPlayer();

  final AudioPlayer _player;

  @override
  Future<void> load(String url) async {
    await _player.setUrl(url, preload: true);
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();

  @override
  Stream<Duration> get position => _player.positionStream;

  @override
  Stream<Duration?> get duration => _player.durationStream;

  @override
  Stream<bool> get playing => _player.playingStream;

  @override
  Stream<bool> get loading => _player.playerStateStream.map(
        (PlayerState state) =>
            state.processingState == ProcessingState.loading ||
            state.processingState == ProcessingState.buffering,
      );
}
