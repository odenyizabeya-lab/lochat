import 'dart:typed_data';

/// A recorded voice clip, ready to upload as a voice message.
class RecordedVoice {
  const RecordedVoice({
    required this.bytes,
    required this.durationMs,
    required this.fileName,
    required this.mimeType,
  });

  final Uint8List bytes;
  final int durationMs;
  final String fileName;
  final String mimeType;
}

/// Contract for press-and-hold voice recording.
///
/// The UI depends only on this interface; the production implementation is
/// [DeviceVoiceRecorder] (the `record` plugin). Tests inject a fake.
abstract interface class VoiceRecorder {
  /// Requests the microphone permission if needed. Returns true when the
  /// recorder is allowed to record.
  Future<bool> ensurePermission();

  /// Starts a new recording session. Call only after [ensurePermission].
  Future<void> startRecording();

  /// Stops the session and returns the recorded clip, or null when nothing
  /// was captured.
  Future<RecordedVoice?> stopRecording();

  /// Stops and discards the current recording (user cancelled).
  Future<void> cancelRecording();

  /// Releases platform resources.
  Future<void> dispose();
}
