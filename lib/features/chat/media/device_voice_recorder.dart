import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'voice_recorder.dart';

/// Production [VoiceRecorder] backed by the `record` plugin.
///
/// Records mono AAC-LC at 64 kbps to a temporary m4a file, then reads the
/// bytes back for upload. The clip length is measured locally (the m4a header
/// duration is not read back; platform metadata varies).
class DeviceVoiceRecorder implements VoiceRecorder {
  DeviceVoiceRecorder({AudioRecorder? recorder})
      : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
  final Stopwatch _stopwatch = Stopwatch();
  String? _path;
  bool _recording = false;

  @override
  Future<bool> ensurePermission() => _recorder.hasPermission(request: true);

  @override
  Future<void> startRecording() async {
    if (_recording) return;
    final Directory dir = await getTemporaryDirectory();
    final String path =
        '${dir.path}/voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 64000,
        sampleRate: 44100,
        numChannels: 1,
      ),
      path: path,
    );
    _path = path;
    _recording = true;
    _stopwatch
      ..reset()
      ..start();
  }

  @override
  Future<RecordedVoice?> stopRecording() async {
    if (!_recording) return null;
    _stopwatch.stop();
    _recording = false;
    final String? path = (await _recorder.stop()) ?? _path;
    _path = null;
    if (path == null) return null;
    final File file = File(path);
    if (!file.existsSync()) return null;
    return RecordedVoice(
      bytes: file.readAsBytesSync(),
      durationMs: _stopwatch.elapsedMilliseconds,
      fileName: 'voice_${DateTime.now().microsecondsSinceEpoch}.m4a',
      mimeType: 'audio/aac',
    );
  }

  @override
  Future<void> cancelRecording() async {
    _stopwatch.stop();
    _recording = false;
    _path = null;
    await _recorder.cancel();
  }

  @override
  Future<void> dispose() => _recorder.dispose();
}
