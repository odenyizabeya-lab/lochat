import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../shared/widgets/app_snackbar.dart';
import '../../chat/data/chat_repository.dart' show MediaUploadTask;
import '../../chat/media/chat_media_picker.dart';
import '../models/status_update.dart';
import '../status_controller.dart';
import '../status_scope.dart';

/// Full-screen status composer: pick a photo/video (camera or gallery), add an
/// optional caption, and post. With no media, the caption itself becomes a
/// text status.
class StatusComposerScreen extends StatefulWidget {
  const StatusComposerScreen({super.key});

  @override
  State<StatusComposerScreen> createState() => _StatusComposerScreenState();
}

class _StatusComposerScreenState extends State<StatusComposerScreen> {
  final TextEditingController _captionController = TextEditingController();
  PickedChatImage? _image;
  PickedChatVideo? _video;
  bool _posting = false;

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ChatMediaSource source) async {
    try {
      final PickedChatImage? image =
          await StatusScope.of(context).mediaPicker.pickImage(source: source);
      if (image == null || !mounted) return;
      setState(() {
        _image = image;
        _video = null;
      });
    } catch (_) {
      if (mounted) AppSnackbars.showError(context, 'Could not pick a photo.');
    }
  }

  Future<void> _pickVideo(ChatMediaSource source) async {
    try {
      final PickedChatVideo? video =
          await StatusScope.of(context).mediaPicker.pickVideo(source: source);
      if (video == null || !mounted) return;
      setState(() {
        _video = video;
        _image = null;
      });
    } catch (_) {
      if (mounted) AppSnackbars.showError(context, 'Could not pick a video.');
    }
  }

  Future<void> _post() async {
    final String caption = _captionController.text.trim();
    if (_posting) return;
    if (_image == null && _video == null && caption.isEmpty) {
      AppSnackbars.showInfo(context, 'Add a photo, video, or some text first.');
      return;
    }
    setState(() => _posting = true);
    try {
      final StatusController status = StatusScope.of(context);
      final String statusId = status.newStatusId();

      if (_image != null) {
        final PickedChatImage image = _image!;
        final MediaUploadTask task = await status.uploadStatusMedia(
          statusId: statusId,
          bytes: image.bytes,
          contentType: image.mimeType,
          fileName: image.fileName,
        );
        final String path = await task.url;
        await status.postStatus(
          type: StatusType.image,
          text: caption,
          statusId: statusId,
          mediaUrl: path,
          width: image.width,
          height: image.height,
          mimeType: image.mimeType,
        );
      } else if (_video != null) {
        final PickedChatVideo video = _video!;
        final Uint8List bytes =
            video.bytes ?? await File(video.filePath).readAsBytes();
        final MediaUploadTask task = await status.uploadStatusMedia(
          statusId: statusId,
          bytes: bytes,
          contentType: video.mimeType,
          fileName: video.fileName,
        );
        final String path = await task.url;
        String? thumbnailPath;
        if (video.thumbnailBytes != null) {
          final MediaUploadTask thumbTask = await status.uploadStatusThumbnail(
            statusId: statusId,
            bytes: video.thumbnailBytes!,
            contentType: 'image/jpeg',
          );
          thumbnailPath = await thumbTask.url;
        }
        await status.postStatus(
          type: StatusType.video,
          text: caption,
          statusId: statusId,
          mediaUrl: path,
          thumbnailUrl: thumbnailPath,
          durationMs: video.durationMs,
          width: video.width,
          height: video.height,
          mimeType: video.mimeType,
        );
      } else {
        await status.postStatus(
          type: StatusType.text,
          text: caption,
          statusId: statusId,
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
      AppSnackbars.showInfo(context, 'Status posted.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _posting = false);
      AppSnackbars.showError(context, 'Could not post your status.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFF0C0E12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C0E12),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close_rounded),
          onPressed: _posting ? null : () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Add to your status',
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Post status',
            icon: const Icon(Icons.send_rounded),
            onPressed: _posting ? null : _post,
          ),
        ],
        bottom: _posting
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(minHeight: 3),
              )
            : null,
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(child: _buildPreview(theme, scheme)),
            _buildCaption(scheme),
            _buildSourceRow(scheme),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(ThemeData theme, ColorScheme scheme) {
    if (_image != null) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: Image.memory(_image!.bytes, fit: BoxFit.contain),
      );
    }
    if (_video != null) {
      final PickedChatVideo video = _video!;
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            if (video.thumbnailBytes != null)
              Image.memory(video.thumbnailBytes!, fit: BoxFit.contain)
            else
              const Icon(Icons.videocam_rounded, size: 64, color: Colors.white38),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 4),
                  Text(
                    _formatDuration(video.durationMs),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    // No media yet: a hint centered on the brand gradient.
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF8B5CF6), Color(0xFF4F46E5)],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.add_a_photo_outlined,
                color: Colors.white, size: 48),
            const SizedBox(height: 12),
            Text(
              'Take a photo or pick from your gallery',
              style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 6),
            Text(
              'Or just add some text below',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCaption(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: TextField(
        controller: _captionController,
        maxLength: 500,
        style: const TextStyle(color: Colors.white),
        cursorColor: Colors.white,
        decoration: InputDecoration(
          hintText: 'Add a caption...',
          hintStyle: const TextStyle(color: Colors.white54),
          counterStyle: const TextStyle(color: Colors.white38),
          filled: true,
          fillColor: const Color(0xFF1C2027),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          suffixIcon: IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.clear_rounded, color: Colors.white54),
            onPressed: _captionController.clear,
          ),
        ),
      ),
    );
  }

  Widget _buildSourceRow(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: <Widget>[
          _SourceAction(
            icon: Icons.camera_alt_rounded,
            label: 'Camera',
            onTap: () => _pickImage(ChatMediaSource.camera),
          ),
          _SourceAction(
            icon: Icons.photo_library_rounded,
            label: 'Photo',
            onTap: () => _pickImage(ChatMediaSource.gallery),
          ),
          _SourceAction(
            icon: Icons.videocam_rounded,
            label: 'Video',
            onTap: () => _pickVideo(ChatMediaSource.gallery),
          ),
          _SourceAction(
            icon: Icons.text_fields_rounded,
            label: 'Text',
            onTap: () => FocusScope.of(context).requestFocus(),
          ),
        ],
      ),
    );
  }

  String _formatDuration(int? ms) {
    if (ms == null) return '0:00';
    final int totalSeconds = (ms / 1000).round();
    final int minutes = totalSeconds ~/ 60;
    final int seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

class _SourceAction extends StatelessWidget {
  const _SourceAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, color: Colors.white, size: 28),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
