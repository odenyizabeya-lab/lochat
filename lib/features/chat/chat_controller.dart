import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/auth/auth_controller.dart';
import 'data/chat_repository.dart';
import 'media/chat_media_picker.dart';
import 'media/device_chat_media_picker.dart';
import 'media/device_voice_recorder.dart';
import 'media/media_playback.dart';
import 'media/video_playback.dart';
import 'media/voice_recorder.dart';
import 'models/chat_message.dart';
import 'models/conversation.dart';

/// Factory that builds a [VideoPlaybackController] for a network video URL.
typedef VideoPlaybackControllerFactory = VideoPlaybackController Function(
  String url,
);

/// Factory that builds a [VoicePlayer] for the chat's voice messages.
typedef VoicePlayerFactory = VoicePlayer Function();

/// App-wide state for private 1-to-1 messaging.
///
/// Follows [AuthController] like [ProfileController]: conversation and message
/// streams are exposed lazily so screens only subscribe while visible, and
/// cached per session. The cache is invalidated when the signed-in user
/// changes. Also owns the media picking/recording/playback services used by
/// the chat screen, so tests can inject fakes.
class ChatController extends ChangeNotifier {
  ChatController({
    required this._auth,
    required this._repository,
    ChatMediaPicker? mediaPicker,
    VoiceRecorder? voiceRecorder,
    VoicePlayerFactory? voicePlayerFactory,
    VideoPlaybackControllerFactory? videoPlaybackFactory,
  })  : _mediaPicker = mediaPicker ?? DeviceChatMediaPicker(),
        _voiceRecorder = voiceRecorder ?? DeviceVoiceRecorder(),
        _voicePlayerFactory = voicePlayerFactory ?? DeviceVoicePlayer.new,
        _videoPlaybackFactory =
            videoPlaybackFactory ?? defaultDeviceVideoPlaybackController {
    _auth.addListener(_handleAuthChange);
    _handleAuthChange();
  }

  final AuthController _auth;
  final ChatRepository _repository;
  final ChatMediaPicker _mediaPicker;
  final VoiceRecorder _voiceRecorder;
  final VoicePlayerFactory _voicePlayerFactory;
  final VideoPlaybackControllerFactory _videoPlaybackFactory;

  int _messageSeed = 0;

  /// The underlying repository, exposed so callers can reuse the same
  /// instance (e.g. the app builds [NotificationsService] on the same source).
  ChatRepository get repository => _repository;

  /// Media picking (photos/videos) for the composer.
  ChatMediaPicker get mediaPicker => _mediaPicker;

  /// Press-and-hold voice recording for the composer.
  VoiceRecorder get voiceRecorder => _voiceRecorder;

  /// Builds the shared voice player for the chat screen.
  VoicePlayerFactory get voicePlayerFactory => _voicePlayerFactory;

  /// Builds a video player for a video message URL.
  VideoPlaybackControllerFactory get videoPlaybackFactory =>
      _videoPlaybackFactory;

  Stream<List<Conversation>>? _conversationsStream;
  StreamSubscription<List<Conversation>>? _conversationsSub;
  List<Conversation>? _conversationsCache;
  final Map<String, Stream<List<ChatMessage>>> _messageStreams =
      <String, Stream<List<ChatMessage>>>{};
  String? _uid;

  /// UID of the signed-in user, or null when signed out.
  String? get uid => _uid;

  void _handleAuthChange() {
    final String? uid = _auth.currentUser?.uid;
    if (_uid == uid) return;
    _conversationsSub?.cancel();
    _conversationsSub = null;
    _conversationsStream = null;
    _conversationsCache = null;
    _messageStreams.clear();
    _uid = uid;
  }

  /// Live conversation list for the signed-in user, most recent first.
  ///
  /// Wraps the underlying (single-subscription) realtime stream in a broadcast
  /// stream backed by one persistent subscription, so multiple screens (e.g.
  /// the chats list and the chat app bar) can subscribe/unsubscribe freely
  /// without dropping the realtime channel. Because a broadcast controller does
  /// not replay past events to late subscribers, each caller gets a fresh
  /// wrapper that re-emits the latest cached snapshot as soon as it subscribes.
  Stream<List<Conversation>> watchConversations() {
    final Stream<List<Conversation>> source =
        _conversationsStream ??= _createConversationsBroadcast();
    late final StreamController<List<Conversation>> controller;
    StreamSubscription<List<Conversation>>? forwardSub;
    controller = StreamController<List<Conversation>>.broadcast(
      onListen: () {
        final List<Conversation>? latest = _conversationsCache;
        if (latest != null && !controller.isClosed) controller.add(latest);
      },
      onCancel: () {
        forwardSub?.cancel();
      },
    );
    forwardSub = source.listen(
      (List<Conversation> value) {
        if (!controller.isClosed) controller.add(value);
      },
      onError: (Object e, StackTrace st) {
        if (!controller.isClosed) controller.addError(e, st);
      },
      onDone: () {
        if (!controller.isClosed) controller.close();
      },
    );
    return controller.stream;
  }

  Stream<List<Conversation>> _createConversationsBroadcast() {
    final StreamController<List<Conversation>> controller =
        StreamController<List<Conversation>>.broadcast();
    _conversationsSub = _repository.watchConversations(_requireUid()).listen(
          (List<Conversation> value) {
            _conversationsCache = value;
            if (!controller.isClosed) controller.add(value);
          },
          onError: (Object e, StackTrace st) {
            if (!controller.isClosed) controller.addError(e, st);
          },
          onDone: () {
            if (!controller.isClosed) controller.close();
          },
        );
    return controller.stream;
  }

  /// Live messages for [conversationId], ascending by creation time.
  Stream<List<ChatMessage>> watchMessages(String conversationId) {
    return _messageStreams.putIfAbsent(
      conversationId,
      () => _repository.watchMessages(conversationId),
    );
  }

  /// Older messages that precede [before], ascending.
  Future<List<ChatMessage>> fetchMessagesBefore(
    String conversationId,
    ChatMessage before,
  ) {
    return _repository.fetchMessagesBefore(conversationId, before);
  }

  /// Opens (creating if needed) the conversation with a contact and returns
  /// its ID. Throws [NotAContactException] when the user is not a contact.
  Future<String> openConversation(String contactUid) {
    return _repository.ensureConversation(
      uid: _requireUid(),
      contactUid: contactUid,
    );
  }

  /// Sends [text] to the conversation. Empty/whitespace text is ignored.
  /// When [replyToId] is provided the message is sent as a reply to that
  /// message, carrying the quote context for both sides to render.
  Future<void> sendMessage({
    required String conversationId,
    required String text,
    String? replyToId,
    String? replyToType,
    String? replyToText,
    String? replyToSender,
  }) {
    final String body = text.trim();
    if (body.isEmpty) return Future<void>.value();
    return _repository.sendMessage(
      conversationId: conversationId,
      senderUid: _requireUid(),
      text: body,
      replyToId: replyToId,
      replyToType: replyToType,
      replyToText: replyToText,
      replyToSender: replyToSender,
    );
  }

  /// A fresh client-generated message id. Pass the same id to
  /// [uploadChatMedia] and [sendMediaMessage] so the optimistic message and
  /// its storage object stay linked.
  String newMessageId() => 'm_${DateTime.now().microsecondsSinceEpoch}_${_messageSeed++}';

  /// Uploads media for a pending message and returns a cancellable handle.
  Future<MediaUploadTask> uploadChatMedia({
    required String conversationId,
    required String messageId,
    required Uint8List bytes,
    required String contentType,
    required String fileName,
  }) {
    return _repository.uploadChatMedia(
      conversationId: conversationId,
      messageId: messageId,
      bytes: bytes,
      contentType: contentType,
      fileName: fileName,
    );
  }

  /// Uploads a small poster (e.g. a video thumbnail) for [messageId] and
  /// returns a handle whose [MediaUploadTask.url] is the permanent download
  /// URL.
  Future<MediaUploadTask> uploadChatThumbnail({
    required String conversationId,
    required String messageId,
    required Uint8List bytes,
    required String contentType,
  }) {
    return _repository.uploadChatThumbnail(
      conversationId: conversationId,
      messageId: messageId,
      bytes: bytes,
      contentType: contentType,
    );
  }

  /// Sends a message whose media has already been uploaded to [MessageMedia.url].
  Future<void> sendMediaMessage({
    required String conversationId,
    required String messageId,
    required MessageMedia media,
    String? replyToId,
    String? replyToType,
    String? replyToText,
    String? replyToSender,
  }) {
    return _repository.sendMessage(
      conversationId: conversationId,
      senderUid: _requireUid(),
      messageId: messageId,
      media: media,
      replyToId: replyToId,
      replyToType: replyToType,
      replyToText: replyToText,
      replyToSender: replyToSender,
    );
  }

  /// Deletes a message for everyone in the conversation (own messages only).
  Future<void> deleteMessage({
    required String conversationId,
    required String messageId,
  }) {
    return _repository.deleteMessage(
      conversationId: conversationId,
      messageId: messageId,
    );
  }

  /// Resets the signed-in user's unread badge in the conversation.
  Future<void> markConversationRead(String conversationId) {
    final String? uid = _uid;
    if (uid == null) return Future<void>.value();
    return _repository.markConversationRead(
      conversationId: conversationId,
      uid: uid,
    );
  }

  Future<void> markMessagesDelivered(
    String conversationId,
    List<String> messageIds,
  ) {
    if (messageIds.isEmpty) return Future<void>.value();
    return _repository.markMessagesDelivered(
      conversationId: conversationId,
      messageIds: messageIds,
    );
  }

  Future<void> markMessagesRead(
    String conversationId,
    List<String> messageIds,
  ) {
    if (messageIds.isEmpty) return Future<void>.value();
    return _repository.markMessagesRead(
      conversationId: conversationId,
      messageIds: messageIds,
    );
  }

  /// Registers the FCM device token for the signed-in user (push
  /// notifications). Called by [NotificationsService].
  Future<void> registerFcmToken(String token) {
    return _repository.registerFcmToken(uid: _requireUid(), token: token);
  }

  /// Removes the FCM device token for [uid] (called on sign-out so the
  /// previous user stops receiving pushes on this device).
  Future<void> unregisterFcmToken({required String uid, required String token}) {
    return _repository.unregisterFcmToken(uid: uid, token: token);
  }

  String _requireUid() {
    final String? uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw StateError('No signed-in user.');
    }
    return uid;
  }

  @override
  void dispose() {
    _auth.removeListener(_handleAuthChange);
    super.dispose();
  }
}
