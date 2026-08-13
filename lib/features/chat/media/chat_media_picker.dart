import 'dart:typed_data';

/// Where chat media comes from. Mirrors the device gallery/camera.
enum ChatMediaSource { gallery, camera }

/// A picked, downscaled image ready to upload as an image message.
class PickedChatImage {
  const PickedChatImage({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
    this.width,
    this.height,
  });

  final Uint8List bytes;
  final String fileName;
  final String mimeType;
  final int sizeBytes;

  /// Source dimensions in pixels, when the platform reports them.
  final double? width;
  final double? height;
}

/// A picked video, optionally compressed, plus a thumbnail and metadata.
///
/// The video usually stays on disk ([filePath]) until upload, so large files
/// are never held fully in memory. [bytes] is set when the picker produced an
/// in-memory copy (used by tests and very small files).
class PickedChatVideo {
  const PickedChatVideo({
    required this.filePath,
    required this.fileName,
    required this.mimeType,
    this.thumbnailBytes,
    this.durationMs,
    this.width,
    this.height,
    this.sizeBytes,
    this.bytes,
  });

  final String filePath;
  final String fileName;
  final String mimeType;

  /// JPEG poster for the message bubble; null when the platform could not
  /// extract one (the bubble then falls back to a video icon).
  final Uint8List? thumbnailBytes;

  final int? durationMs;
  final double? width;
  final double? height;
  final int? sizeBytes;

  /// Preloaded file content; read from [filePath] when null.
  final Uint8List? bytes;
}

/// Contract for picking and preparing chat media.
///
/// The UI depends only on this interface; the production implementation is
/// [DeviceChatMediaPicker] (image_picker + compression). Tests inject a fake.
abstract interface class ChatMediaPicker {
  /// Picks a photo and returns it compressed and downscaled for chat, or null
  /// when the user cancels. Throws on permission or platform errors.
  Future<PickedChatImage?> pickImage({required ChatMediaSource source});

  /// Picks a video, compresses it, and extracts a thumbnail and duration.
  /// Returns null when the user cancels. Throws on permission or platform
  /// errors.
  Future<PickedChatVideo?> pickVideo({required ChatMediaSource source});
}
