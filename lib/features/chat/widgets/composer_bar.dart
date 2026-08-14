import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/utils/time_utils.dart';
import '../../../../shared/languages.dart';
import '../chat_controller.dart';
import '../data/chat_ai_service.dart';
import '../data/chat_repository.dart';
import '../media/chat_media_picker.dart';
import '../media/voice_recorder.dart';
import '../models/chat_message.dart';
import '../models/voice_effect.dart';
import 'emoji_picker.dart';
import '../../../shared/language_picker_dialog.dart';
import 'reply_preview.dart';

/// The chat composer: text input, photo/video attachment (with an upload
/// progress preview), and press-and-hold voice recording.
///
/// Media is uploaded in the background with a live progress bar and can be
/// cancelled. Voice messages are recorded with long-press and sent on release
/// (or cancelled by dragging left or tapping cancel). When
/// [voiceEffectsEnabled] is true (admin only) a voice-changer button appears
/// so the admin can pick a man/woman voice before recording.
class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key,
    required this.chat,
    required this.conversationId,
    this.replyTo,
    this.replyToLabel,
    this.replyToSender,
    this.onReplyCleared,
    this.voiceEffectsEnabled = false,
    this.myLanguageCode,
  });

  final ChatController chat;
  final String conversationId;

  /// Message being replied to, shown as a quote banner above the input.
  final ChatMessage? replyTo;

  /// Display name for the author of [replyTo] (local composer banner).
  final String? replyToLabel;

  /// Author name stored on the sent reply (visible to the peer).
  final String? replyToSender;

  /// Called when the user dismisses the reply quote.
  final VoidCallback? onReplyCleared;

  /// When true (admins) a voice-changer picker is shown next to the mic.
  final bool voiceEffectsEnabled;

  /// The signed-in user's preferred language code (from their profile). Sent
  /// messages are stamped with it so the peer can decide whether to
  /// auto-translate. Null when unknown (e.g. tests without a profile).
  final String? myLanguageCode;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

enum _PickKind { image, video }

class _ChatComposerState extends State<ChatComposer> {
  final TextEditingController _input = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  bool _canSend = false;

  // Emoji panel state (WhatsApp-style docked panel, toggles with the system
  // keyboard). Recents and skin tone persist while the chat is open.
  bool _emojiOpen = false;
  String _skinTone = '';
  final List<String> _recentEmojis = <String>[];

  // Typing indicator: throttled so the peer receives at most one signal per
  // ~3s while the user is typing. The stamp expires server-side after 8s, so
  // a single call is enough to keep the indicator live for the next window.
  DateTime _lastTypingSignalAt = DateTime.fromMillisecondsSinceEpoch(0);

  _ComposerAttachment? _attachment;
  bool _uploading = false;
  double? _uploadProgress;
  MediaUploadTask? _uploadTask;
  StreamSubscription<double>? _progressSub;

  // Voice recording state.
  bool _recording = false;
  bool _cancelArmed = false;
  int _recordElapsedSeconds = 0;
  Timer? _recordTimer;

  // Voice changer (admin only): the preset applied to the next voice message.
  VoiceEffectPreset? _voiceEffect;

  @override
  void initState() {
    super.initState();
    _inputFocus.addListener(_onInputFocusChanged);
  }

  /// Tapping into the text field closes the emoji panel and brings the system
  /// keyboard back (same behaviour as WhatsApp).
  void _onInputFocusChanged() {
    if (_inputFocus.hasFocus && _emojiOpen && mounted) {
      setState(() => _emojiOpen = false);
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _inputFocus.dispose();
    _progressSub?.cancel();
    unawaited(_uploadTask?.cancel());
    _recordTimer?.cancel();
    super.dispose();
  }

  void _onInputChanged() {
    final bool canSend = _input.text.trim().isNotEmpty;
    if (canSend != _canSend) setState(() => _canSend = canSend);
    _notifyTyping();
  }

  void _notifyTyping() {
    if (_input.text.trim().isEmpty) return;
    final DateTime now = DateTime.now();
    if (now.difference(_lastTypingSignalAt).inMilliseconds < 3000) return;
    _lastTypingSignalAt = now;
    unawaited(widget.chat.setTyping(widget.conversationId));
  }

  void _sendText() {
    final String text = _input.text.trim();
    if (text.isEmpty) return;
    final ChatMessage? replyTo = widget.replyTo;
    _input.clear();
    _onInputChanged();
    unawaited(
      widget.chat.sendMessage(
        conversationId: widget.conversationId,
        text: text,
        replyToId: replyTo?.id,
        replyToType: replyTo?.type.name,
        replyToText:
            replyTo?.type == MessageType.text ? replyTo?.text : null,
        replyToSender: widget.replyToSender,
        senderLang: widget.myLanguageCode,
      ),
    );
    widget.onReplyCleared?.call();
  }

  /// Inserts [emoji] at the current cursor position and tracks it as a recent.
  void _insertEmoji(String emoji) {
    final TextEditingValue value = _input.value;
    final int start = value.selection.baseOffset;
    final int end = value.selection.extentOffset;
    final int from =
        start >= 0 && end >= 0 && start <= end ? start : value.text.length;
    final int to =
        end >= 0 && end <= value.text.length ? end : value.text.length;
    final String text = value.text.replaceRange(from, to, emoji);
    _input.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: from + emoji.length),
    );
    _onInputChanged();
    setState(() {
      _recentEmojis.remove(emoji);
      _recentEmojis.insert(0, emoji);
      if (_recentEmojis.length > 30) {
        _recentEmojis.removeRange(30, _recentEmojis.length);
      }
    });
  }

  // ----- Translate before sending -----

  /// Translates the draft into a language the user picks, then lets them
  /// review the translation and send it (with the original kept for a
  /// "See original" toggle on the peer's side).
  Future<void> _translateDraft() async {
    final String text = _input.text.trim();
    if (text.isEmpty) return;
    final Language? target = await showLanguagePicker(
      context,
      title: 'Translate to',
    );
    if (target == null || !mounted) return;

    final ChatAiService chatAi = widget.chat.chatAi;
    final TextTranslationResult result;
    try {
      result = await chatAi.translateText(
        text: text,
        targetLanguage: target.name,
      );
    } on ChatAiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
      return;
    } on Exception {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not translate that message. Try again.'),
        ),
      );
      return;
    }
    if (!mounted) return;
    await _showTranslationPreview(
      original: text,
      translated: result.translation,
      targetName: target.name,
      sourceLanguage: result.sourceLanguage,
    );
  }

  Future<void> _showTranslationPreview({
    required String original,
    required String translated,
    required String targetName,
    required String sourceLanguage,
  }) async {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool? send = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(Icons.translate_rounded, color: scheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Translated to $targetName',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(translated, style: theme.textTheme.bodyLarge),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 12),
                Text(
                  'Original',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  original,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(true),
                    icon: const Icon(Icons.send_rounded),
                    label: const Text('Send translation'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (send != true || !mounted) return;

    final ChatMessage? replyTo = widget.replyTo;
    _input.clear();
    _onInputChanged();
    unawaited(
      widget.chat.sendMessage(
        conversationId: widget.conversationId,
        text: translated,
        replyToId: replyTo?.id,
        replyToType: replyTo?.type.name,
        replyToText:
            replyTo?.type == MessageType.text ? replyTo?.text : null,
        replyToSender: widget.replyToSender,
        senderLang: widget.myLanguageCode,
        originalText: original,
        sourceLang: sourceLanguage.isEmpty ? null : sourceLanguage,
      ),
    );
    widget.onReplyCleared?.call();
  }

  /// WhatsApp-style attachment tray: circular tiles that open each media
  /// source, instead of a plain list.
  Future<void> _showAttachSheet() async {
    final _PickChoice? choice = await showModalBottomSheet<_PickChoice>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    _attachTile(
                      context,
                      icon: Icons.photo_library_rounded,
                      color: const Color(0xFF008069),
                      label: 'Gallery',
                      value: const _PickChoice(
                          _PickKind.image, ChatMediaSource.gallery),
                    ),
                    _attachTile(
                      context,
                      icon: Icons.photo_camera_rounded,
                      color: const Color(0xFFE5422B),
                      label: 'Camera',
                      value: const _PickChoice(
                          _PickKind.image, ChatMediaSource.camera),
                    ),
                    _attachTile(
                      context,
                      icon: Icons.video_library_rounded,
                      color: const Color(0xFF5B66C7),
                      label: 'Video',
                      value: const _PickChoice(
                          _PickKind.video, ChatMediaSource.gallery),
                    ),
                    _attachTile(
                      context,
                      icon: Icons.videocam_rounded,
                      color: const Color(0xFF4A9E5F),
                      label: 'Camera video',
                      value: const _PickChoice(
                          _PickKind.video, ChatMediaSource.camera),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    if (choice == null || !mounted) return;
    await _pick(choice.kind, choice.source);
  }

  Widget _attachTile(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String label,
    required _PickChoice value,
  }) {
    final ThemeData theme = Theme.of(context);
    return InkWell(
      onTap: () => Navigator.of(context).pop(value),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pick(_PickKind kind, ChatMediaSource source) async {
    if (source == ChatMediaSource.camera) {
      final PermissionStatus status = await Permission.camera.request();
      if (!status.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Camera permission is needed to take photos.')),
          );
        }
        return;
      }
    }

    try {
      if (kind == _PickKind.image) {
        final PickedChatImage? image = await widget.chat.mediaPicker.pickImage(
          source: source,
        );
        if (image == null || !mounted) return;
        setState(() {
          _attachment = _ComposerAttachment(
            messageId: widget.chat.newMessageId(),
            type: MessageType.image,
            bytes: image.bytes,
            contentType: image.mimeType,
            fileName: image.fileName,
            width: image.width,
            height: image.height,
            sizeBytes: image.sizeBytes,
            label: 'Photo',
            previewBytes: image.bytes,
          );
        });
      } else {
        final PickedChatVideo? video = await widget.chat.mediaPicker.pickVideo(
          source: source,
        );
        if (video == null || !mounted) return;
        final Uint8List bytes =
            video.bytes ?? await File(video.filePath).readAsBytes();
        if (!mounted) return;
        setState(() {
          _attachment = _ComposerAttachment(
            messageId: widget.chat.newMessageId(),
            type: MessageType.video,
            bytes: bytes,
            contentType: video.mimeType,
            fileName: video.fileName,
            thumbnailBytes: video.thumbnailBytes,
            durationMs: video.durationMs,
            width: video.width,
            height: video.height,
            sizeBytes: video.sizeBytes,
            label: 'Video',
            previewBytes: video.thumbnailBytes,
          );
        });
      }
    } on PlatformException catch (e) {
      _showPickError(e.code);
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not pick that media. Try again.')),
        );
      }
    }
  }

  void _showPickError(String code) {
    if (!mounted) return;
    final String message = switch (code) {
      'camera_access_denied' || 'camera_access_restricted' =>
        'Camera permission is needed to take photos.',
      'photo_access_denied' || 'photo_access_restricted' =>
        'Gallery permission is needed to pick photos.',
      'video_access_denied' || 'video_access_restricted' =>
        'Gallery permission is needed to pick videos.',
      _ => 'Could not open that media source.',
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _sendAttachment() async {
    final _ComposerAttachment? attachment = _attachment;
    if (attachment == null || _uploading) return;
    final ChatController chat = widget.chat;

    setState(() {
      _uploading = true;
      _uploadProgress = 0;
    });

    try {
      final MediaUploadTask task = await chat.uploadChatMedia(
        conversationId: widget.conversationId,
        messageId: attachment.messageId,
        bytes: attachment.bytes,
        contentType: attachment.contentType,
        fileName: attachment.fileName,
      );
      if (!mounted) return;
      _uploadTask = task;
      _progressSub = task.progress.listen((double value) {
        if (mounted) setState(() => _uploadProgress = value);
      });
      final String url = await task.url;
      await _progressSub?.cancel();

      String? thumbnailUrl;
      final Uint8List? thumbnailBytes = attachment.thumbnailBytes;
      if (attachment.type == MessageType.video && thumbnailBytes != null) {
        final MediaUploadTask thumbTask = await chat.uploadChatThumbnail(
          conversationId: widget.conversationId,
          messageId: attachment.messageId,
          bytes: thumbnailBytes,
          contentType: 'image/jpeg',
        );
        thumbnailUrl = await thumbTask.url;
      }

      await chat.sendMediaMessage(
        conversationId: widget.conversationId,
        messageId: attachment.messageId,
        media: MessageMedia(
          type: attachment.type,
          url: url,
          thumbnailUrl: thumbnailUrl,
          durationMs: attachment.durationMs,
          width: attachment.width,
          height: attachment.height,
          fileName: attachment.fileName,
          mimeType: attachment.contentType,
          sizeBytes: attachment.sizeBytes,
          voiceEffect: attachment.voiceEffect,
        ),
        replyToId: widget.replyTo?.id,
        replyToType: widget.replyTo?.type.name,
        replyToText: widget.replyTo?.type == MessageType.text
            ? widget.replyTo?.text
            : null,
        replyToSender: widget.replyToSender,
        voiceEffect: attachment.voiceEffect,
      );
      if (!mounted) return;
      setState(() {
        _attachment = null;
        _uploading = false;
        _uploadProgress = null;
        _uploadTask = null;
      });
      widget.onReplyCleared?.call();
    } on Exception {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _uploadProgress = null;
        _uploadTask = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Upload failed. Check your connection and try again.'),
        ),
      );
    }
  }

  Future<void> _cancelAttachment() async {
    final MediaUploadTask? task = _uploadTask;
    _progressSub?.cancel();
    _progressSub = null;
    if (task != null) {
      try {
        await task.cancel();
      } on Exception {
        // Cancelling is best-effort; the UI state is cleared regardless.
      }
    }
    if (mounted) {
      setState(() {
        _attachment = null;
        _uploading = false;
        _uploadProgress = null;
        _uploadTask = null;
      });
    }
  }

  // ----- Voice recording (press-and-hold) -----

  Future<void> _startRecording() async {
    final ChatController chat = widget.chat;
    final bool allowed = await chat.voiceRecorder.ensurePermission();
    if (!allowed) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Microphone permission is needed to record voice messages.'),
          ),
        );
      }
      return;
    }
    try {
      await chat.voiceRecorder.startRecording();
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not start recording.')),
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _recording = true;
      _cancelArmed = false;
      _recordElapsedSeconds = 0;
    });
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (mounted) setState(() => _recordElapsedSeconds++);
    });
  }

  Future<void> _finishRecording() async {
    if (_cancelArmed) {
      await _stopRecording(shouldSend: false);
      return;
    }
    await _stopRecording(shouldSend: true);
  }

  Future<void> _stopRecording({required bool shouldSend}) async {
    _recordTimer?.cancel();
    _recordTimer = null;
    final ChatController chat = widget.chat;
    RecordedVoice? voice;
    try {
      if (shouldSend) {
        voice = await chat.voiceRecorder.stopRecording();
      } else {
        await chat.voiceRecorder.cancelRecording();
      }
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recording was interrupted.')),
        );
      }
    }
    if (!mounted) return;
    setState(() {
      _recording = false;
      _cancelArmed = false;
    });
    final RecordedVoice? clip = voice;
    if (clip != null && clip.durationMs > 0) {
      setState(() {
        _attachment = _ComposerAttachment(
          messageId: chat.newMessageId(),
          type: MessageType.voice,
          bytes: clip.bytes,
          contentType: clip.mimeType,
          fileName: clip.fileName,
          durationMs: clip.durationMs,
          sizeBytes: clip.bytes.length,
          label: 'Voice message',
          voiceEffect: _voiceEffect?.id,
        );
      });
      await _sendAttachment();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final ChatMessage? replyTo = widget.replyTo;

    return Container(
      color: Colors.transparent,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (_attachment != null)
              _AttachmentPreview(
                attachment: _attachment!,
                uploading: _uploading,
                progress: _uploadProgress,
                onCancel: _cancelAttachment,
                onSend: _sendAttachment,
              ),
            if (replyTo != null)
              _ReplyBanner(
                label: widget.replyToLabel ?? 'Message',
                preview: replyPreviewText(replyTo),
                onClose: () => widget.onReplyCleared?.call(),
              ),
            if (widget.voiceEffectsEnabled && _voiceEffect != null)
              _VoiceEffectBanner(
                effect: _voiceEffect!,
                onClear: () => setState(() => _voiceEffect = null),
              ),
            if (_recording)
              _RecordingPanel(
                elapsedSeconds: _recordElapsedSeconds,
                cancelArmed: _cancelArmed,
                onCancel: () {
                  setState(() => _cancelArmed = true);
                  unawaited(_stopRecording(shouldSend: false));
                },
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 8, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    IconButton(
                      tooltip: 'Attach',
                      onPressed: _uploading ? null : _showAttachSheet,
                      icon: const Icon(Icons.add_circle_outline_rounded),
                      color: scheme.primary,
                    ),
                    _buildEmojiButton(context),
                    Expanded(
                      child: TextField(
                        controller: _input,
                        focusNode: _inputFocus,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.newline,
                        onChanged: (_) => _onInputChanged(),
                        onSubmitted: (_) => _sendText(),
                        decoration: InputDecoration(
                          hintText: 'Message',
                          filled: true,
                          fillColor: scheme.surfaceContainerHighest,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (_canSend) _buildTranslateButton(context),
                    if (widget.voiceEffectsEnabled)
                      _buildVoiceEffectButton(context),
                    _buildSendMicToggle(context),
                  ],
                ),
              ),
            if (_emojiOpen && !_recording)
              _buildEmojiPanel(context),
          ],
        ),
      ),
    );
  }

  /// The docked WhatsApp-style emoji panel, shown in place of the keyboard.
  Widget _buildEmojiPanel(BuildContext context) {
    return EmojiPanel(
      onInsert: _insertEmoji,
      onKeyboard: () {
        setState(() => _emojiOpen = false);
        _inputFocus.requestFocus();
      },
      recents: _recentEmojis,
      skinTone: _skinTone,
      onSkinToneChanged: (String tone) => setState(() => _skinTone = tone),
    );
  }

  /// Emoji toggle on the left of the input, like WhatsApp: taps switch between
  /// the system keyboard and the emoji panel.
  Widget _buildEmojiButton(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool open = _emojiOpen;
    return IconButton(
      tooltip: open ? 'Show keyboard' : 'Emoji',
      onPressed: () {
        if (open) {
          setState(() => _emojiOpen = false);
          _inputFocus.requestFocus();
        } else {
          _inputFocus.unfocus();
          setState(() => _emojiOpen = true);
        }
      },
      icon: Icon(
        open ? Icons.keyboard_rounded : Icons.emoji_emotions_outlined,
        color: scheme.primary,
        size: 26,
      ),
    );
  }

  /// Translate-before-send: appears while there is draft text so the user can
  /// translate it and send the translation (original kept in the message).
  Widget _buildTranslateButton(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: 'Translate before sending',
      onPressed: _uploading ? null : () => unawaited(_translateDraft()),
      icon: Icon(Icons.translate_rounded, color: scheme.primary),
    );
  }

  /// Shows the mic (hold to record) when empty, the send button otherwise.
  Widget _buildSendMicToggle(BuildContext context) {
    final bool canSend = _canSend || _attachment != null;
    if (canSend) {
      return IconButton.filled(
        tooltip: _attachment != null ? 'Send attachment' : 'Send',
        onPressed:
            _attachment != null ? _sendAttachment : _sendText,
        icon: const Icon(Icons.send_rounded),
      );
    }
    return _buildMicButton(context);
  }

  Widget _buildMicButton(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onLongPressStart: (_) => unawaited(_startRecording()),
      onLongPressEnd: (_) => unawaited(_finishRecording()),
      onLongPressMoveUpdate: (LongPressMoveUpdateDetails details) {
        final bool armed =
            details.localOffsetFromOrigin.dx < -70 ||
            details.localOffsetFromOrigin.dy < -70;
        if (armed != _cancelArmed && mounted) {
          setState(() => _cancelArmed = armed);
        }
      },
      onLongPressCancel: () => unawaited(_stopRecording(shouldSend: false)),
      child: IconButton(
        tooltip: 'Hold to record a voice message',
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Press and hold to record a voice message.'),
            ),
          );
        },
        icon: Icon(
          _recording ? Icons.mic : Icons.mic_none_rounded,
          color: _recording ? scheme.onError : scheme.primary,
        ),
      ),
    );
  }

  // ----- Voice changer (admin only) -----

  Widget _buildVoiceEffectButton(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final VoiceEffectPreset? selected = _voiceEffect;
    return IconButton(
      tooltip: selected == null
          ? 'Voice changer: pick a man or woman voice'
          : 'Voice: ${selected.label} \u00b7 tap to change',
      onPressed: _uploading ? null : _showVoiceEffectPicker,
      icon: Icon(
        Icons.record_voice_over_rounded,
        color: selected == null ? scheme.onSurfaceVariant : scheme.primary,
        size: 26,
      ),
    );
  }

  Future<void> _showVoiceEffectPicker() async {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final VoiceEffectPreset? current = _voiceEffect;
    final Object? picked = await showModalBottomSheet<Object?>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) {
        Widget section(VoiceGender gender) {
          final List<VoiceEffectPreset> presets =
              gender == VoiceGender.man ? manVoicePresets : womanVoicePresets;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 2),
                child: Text(
                  gender == VoiceGender.man ? 'Man voices' : 'Woman voices',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              for (final VoiceEffectPreset preset in presets)
                ListTile(
                  leading: Icon(
                    preset.isMan
                        ? Icons.man_rounded
                        : Icons.woman_rounded,
                    color: scheme.primary,
                  ),
                  title: Text(preset.label),
                  subtitle: Text(
                    preset.isMan ? 'Deepens your voice' : 'Raises your voice',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  trailing: current?.id == preset.id
                      ? Icon(Icons.check_rounded, color: scheme.primary)
                      : null,
                  onTap: () => Navigator.of(context).pop(preset),
                ),
            ],
          );
        }

        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Text(
                    'Pick a voice for your next voice message. Everyone who '
                    'plays it will hear it with this voice.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ),
                section(VoiceGender.man),
                section(VoiceGender.woman),
                ListTile(
                  leading: Icon(Icons.voice_over_off_rounded,
                      color: scheme.onSurfaceVariant),
                  title: const Text('No voice changer'),
                  trailing: current == null
                      ? Icon(Icons.check_rounded, color: scheme.primary)
                      : null,
                  onTap: () => Navigator.of(context).pop(_kNoEffect),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
    if (picked == null || !mounted) return;
    if (identical(picked, _kNoEffect)) {
      setState(() => _voiceEffect = null);
    } else {
      setState(() => _voiceEffect = picked as VoiceEffectPreset);
    }
  }

  static const Object _kNoEffect = Object();
}

/// Quote banner shown above the input while replying, with a close button.
class _ReplyBanner extends StatelessWidget {
  const _ReplyBanner({
    required this.label,
    required this.preview,
    required this.onClose,
  });

  final String label;
  final String preview;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Container(
      color: scheme.surfaceContainerLow,
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      child: Row(
        children: <Widget>[
          Container(width: 3, height: 34, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Cancel reply',
            onPressed: onClose,
            icon: Icon(Icons.close, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Banner shown above the input while a voice-changer voice is selected.
class _VoiceEffectBanner extends StatelessWidget {
  const _VoiceEffectBanner({required this.effect, required this.onClear});

  final VoiceEffectPreset effect;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Container(
      color: scheme.surfaceContainerLow,
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      child: Row(
        children: <Widget>[
          Icon(
            effect.isMan ? Icons.man_rounded : Icons.woman_rounded,
            size: 18,
            color: scheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Voice changer: ${effect.label}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(
            onPressed: onClear,
            child: const Text('Off'),
          ),
        ],
      ),
    );
  }
}

/// Photo/video/voice picked but not yet sent. Holds the bytes to upload and
/// everything needed to build the final [MessageMedia].
class _ComposerAttachment {
  const _ComposerAttachment({
    required this.messageId,
    required this.type,
    required this.bytes,
    required this.contentType,
    required this.fileName,
    this.thumbnailBytes,
    this.previewBytes,
    this.durationMs,
    this.width,
    this.height,
    this.sizeBytes,
    this.label,
    this.voiceEffect,
  });

  final String messageId;
  final MessageType type;
  final Uint8List bytes;
  final String contentType;
  final String fileName;
  final Uint8List? thumbnailBytes;

  /// Bytes shown in the composer preview before upload.
  final Uint8List? previewBytes;

  final int? durationMs;
  final double? width;
  final double? height;
  final int? sizeBytes;
  final String? label;

  /// Voice-changer preset id applied to a voice message.
  final String? voiceEffect;
}

class _PickChoice {
  const _PickChoice(this.kind, this.source);

  final _PickKind kind;
  final ChatMediaSource source;
}

/// Preview card shown above the input row while media is pending/uploading.
class _AttachmentPreview extends StatelessWidget {
  const _AttachmentPreview({
    required this.attachment,
    required this.uploading,
    required this.progress,
    required this.onCancel,
    required this.onSend,
  });

  final _ComposerAttachment attachment;
  final bool uploading;
  final double? progress;
  final VoidCallback onCancel;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Uint8List? preview = attachment.previewBytes;

    Widget thumbnail;
    if (preview != null) {
      thumbnail = ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.memory(
          preview,
          width: 46,
          height: 46,
          fit: BoxFit.cover,
          errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
              _iconThumb(scheme),
        ),
      );
    } else {
      thumbnail = _iconThumb(scheme);
    }

    final String detail = uploading
        ? 'Uploading ${((progress ?? 0) * 100).round()}%'
        : _describe(attachment);

    return Container(
      color: scheme.surfaceContainerLow,
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              thumbnail,
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      attachment.label ?? 'Attachment',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    if (uploading) ...<Widget>[
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: progress,
                        minHeight: 4,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              if (!uploading)
                TextButton(
                  onPressed: onSend,
                  child: const Text('Send'),
                ),
              IconButton(
                tooltip: uploading ? 'Cancel upload' : 'Remove attachment',
                onPressed: onCancel,
                icon: Icon(
                  uploading ? Icons.close : Icons.close,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _iconThumb(ColorScheme scheme) {
    final IconData icon = switch (attachment.type) {
      MessageType.image => Icons.image_outlined,
      MessageType.video => Icons.movie_outlined,
      MessageType.voice => Icons.mic_none_rounded,
      MessageType.text => Icons.article_outlined,
    };
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: scheme.onSurfaceVariant),
    );
  }

  String _describe(_ComposerAttachment a) {
    final String size =
        a.sizeBytes == null ? '' : '${_formatBytes(a.sizeBytes!)} \u00b7 ';
    if (a.durationMs != null && a.type != MessageType.image) {
      return '$size${formatDuration(Duration(milliseconds: a.durationMs!))}';
    }
    return '$size${a.fileName}';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Shown while the user holds the mic: a pulsing dot, an elapsed timer, and a
/// cancel control.
class _RecordingPanel extends StatelessWidget {
  const _RecordingPanel({
    required this.elapsedSeconds,
    required this.cancelArmed,
    required this.onCancel,
  });

  final int elapsedSeconds;
  final bool cancelArmed;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final String elapsed = formatDuration(Duration(seconds: elapsedSeconds));

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      color: scheme.surfaceContainerLow,
      child: Row(
        children: <Widget>[
          const _PulsingDot(),
          const SizedBox(width: 12),
          Text(
            elapsed,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 12),
          Icon(
            cancelArmed ? Icons.keyboard_arrow_left : Icons.mic,
            size: 18,
            color: cancelArmed ? scheme.error : scheme.primary,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              cancelArmed
                  ? 'Release to cancel'
                  : 'Release to send \u00b7 slide left to cancel',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          TextButton(
            onPressed: onCancel,
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1).animate(_controller),
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: scheme.error, shape: BoxShape.circle),
      ),
    );
  }
}
