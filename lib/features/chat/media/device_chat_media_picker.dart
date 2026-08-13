import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart';

import 'chat_media_picker.dart';

/// Production [ChatMediaPicker] backed by image_picker, flutter_image_compress
/// and video_compress.
///
/// Photos are downscaled to at most 1920px and re-encoded as JPEG quality 85.
/// Videos are compressed to medium quality (H.264/AAC), capped at 2 minutes of
/// picking, and a small JPEG thumbnail is extracted for the bubble.
class DeviceChatMediaPicker implements ChatMediaPicker {
  DeviceChatMediaPicker({ImagePicker? picker})
      : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  static const int _maxImageDimension = 1920;
  static const int _imageQuality = 85;
  static const int _maxVideoSeconds = 120;
  static const Duration _thumbnailPosition = Duration(milliseconds: 1000);

  @override
  Future<PickedChatImage?> pickImage({required ChatMediaSource source}) async {
    final XFile? file = await _picker.pickImage(
      source: source == ChatMediaSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      maxWidth: 4096,
      maxHeight: 4096,
      imageQuality: 90,
    );
    if (file == null) return null;

    final Uint8List original = await file.readAsBytes();
    // Re-encode + downscale. autoCorrectionAngle handles EXIF rotation so the
    // bubble and viewer never show sideways photos from the camera.
    final Uint8List compressed = await FlutterImageCompress.compressWithList(
      original,
      minWidth: _maxImageDimension,
      minHeight: _maxImageDimension,
      quality: _imageQuality,
      autoCorrectionAngle: true,
      keepExif: false,
    );
    final String name = file.name.isEmpty ? 'photo.jpg' : file.name;
    return PickedChatImage(
      bytes: compressed,
      fileName: name,
      mimeType: 'image/jpeg',
      sizeBytes: compressed.length,
    );
  }

  @override
  Future<PickedChatVideo?> pickVideo({required ChatMediaSource source}) async {
    final XFile? file = await _picker.pickVideo(
      source: source == ChatMediaSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      maxDuration: const Duration(seconds: _maxVideoSeconds),
    );
    if (file == null) return null;

    final String path = file.path;
    final MediaInfo? compressed = await VideoCompress.compressVideo(
      path,
      quality: VideoQuality.MediumQuality,
      deleteOrigin: false,
    );
    final String finalPath = compressed?.path ?? path;

    final MediaInfo info = finalPath == path
        ? await VideoCompress.getMediaInfo(path)
        : await VideoCompress.getMediaInfo(finalPath);

    final Uint8List? thumbnail =
        await VideoCompress.getByteThumbnail(finalPath,
            quality: 50, position: _thumbnailPosition.inMilliseconds);

    final String name = file.name.isEmpty ? 'video.mp4' : file.name;
    return PickedChatVideo(
      filePath: finalPath,
      fileName: name,
      mimeType: 'video/mp4',
      thumbnailBytes: thumbnail,
      durationMs: (info.duration ?? 0).round(),
      width: info.width?.toDouble(),
      height: info.height?.toDouble(),
      sizeBytes: File(finalPath).existsSync() ? File(finalPath).lengthSync() : null,
    );
  }
}
