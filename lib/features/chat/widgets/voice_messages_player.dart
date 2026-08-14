import 'dart:async';

import 'package:flutter/foundation.dart';

import '../media/media_playback.dart';

/// A shared audio player for voice messages in the chat screen.
///
/// Only one clip plays at a time: starting a new clip stops the previous one.
/// Exposes the currently active clip id plus its playback state so each
/// [VoiceMessageBubble] can render a live play/pause and progress.
class VoiceMessagesPlayer extends ChangeNotifier {
  VoiceMessagesPlayer(VoicePlayer Function() factory) : _player = factory();

  final VoicePlayer _player;
  final List<StreamSubscription<Object?>> _subscriptions =
      <StreamSubscription<Object?>>[];
  bool _initialized = false;

  String? _activeId;
  bool _playing = false;
  bool _loading = false;
  Duration _position = Duration.zero;
  Duration? _duration;

  String? get activeId => _activeId;
  bool get playing => _playing;
  bool get loading => _loading;
  Duration get position => _position;
  Duration? get duration => _duration;

  bool isActive(String messageId) => _activeId == messageId;

  void _init() {
    if (_initialized) return;
    _initialized = true;
    _subscriptions.add(_player.position.listen((Duration value) {
      _position = value;
      notifyListeners();
    }));
    _subscriptions.add(_player.duration.listen((Duration? value) {
      _duration = value;
      notifyListeners();
    }));
    _subscriptions.add(_player.playing.listen((bool value) {
      _playing = value;
      notifyListeners();
    }));
    _subscriptions.add(_player.loading.listen((bool value) {
      _loading = value;
      notifyListeners();
    }));
  }

  /// Plays [url] for [messageId]; tapping the active message toggles
  /// play/pause instead.
  Future<void> toggle({
    required String messageId,
    required String url,
  }) async {
    _init();
    if (_activeId == messageId) {
      if (_playing) {
        await _player.pause();
      } else {
        await _player.play();
      }
      return;
    }
    if (_activeId != null) {
      await _player.stop();
    }
    _activeId = messageId;
    _position = Duration.zero;
    _loading = true;
    _playing = false;
    notifyListeners();
    await _player.load(url);
    _loading = false;
    notifyListeners();
    await _player.play();
  }

  /// Stops playback and resets the shared player.
  Future<void> stop() async {
    if (_activeId == null) return;
    _activeId = null;
    _playing = false;
    _loading = false;
    _position = Duration.zero;
    await _player.stop();
    notifyListeners();
  }

  @override
  void dispose() {
    for (final StreamSubscription<Object?> subscription in _subscriptions) {
      subscription.cancel();
    }
    _player.dispose();
    super.dispose();
  }
}
