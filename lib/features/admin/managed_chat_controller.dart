import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../features/chat/data/chat_repository.dart';
import '../../features/chat/data/chat_ai_service.dart';
import '../../features/chat/data/supabase_chat_ai_service.dart';
import '../../features/chat/media/chat_media_picker.dart';
import '../../features/chat/media/device_chat_media_picker.dart';
import '../../features/chat/media/device_voice_recorder.dart';
import '../../features/chat/media/video_playback.dart';
import '../../features/chat/media/voice_recorder.dart';
import '../../features/chat/models/chat_message.dart';
import '../../../features/profile/models/user_profile.dart';
import './managed_account_controller.dart';
import './models/managed_account.dart';
import './models/managed_call.dart';
import './models/managed_conversation.dart';
import './models/managed_message.dart';
import './models/managed_status.dart';
import './data/managed_chat_repository.dart';

class ManagedChatController extends ChangeNotifier {
  ManagedChatController({
    required this.chatRepository,
    required this.accountController,
    ChatMediaPicker? mediaPicker,
    VoiceRecorder? voiceRecorder,
    ChatAiService? chatAi,
    VideoPlaybackControllerFactory? videoPlaybackFactory,
  })  : _mediaPicker = mediaPicker ?? DeviceChatMediaPicker(),
        _voiceRecorder = voiceRecorder ?? DeviceVoiceRecorder(),
        _chatAi = chatAi,
        _videoPlaybackFactory =
            videoPlaybackFactory ?? defaultDeviceVideoPlaybackController {
    accountController.addListener(_onAccountChanged);
    _onAccountChanged();
  }

  final ManagedChatRepository chatRepository;
  final ManagedAccountController accountController;
  final ChatMediaPicker _mediaPicker;
  final VoiceRecorder _voiceRecorder;
  final ChatAiService? _chatAi;
  final VideoPlaybackControllerFactory _videoPlaybackFactory;

  ChatAiService? _lazyChatAi;

  StreamSubscription<List<ManagedConversation>>? _conversationsSub;
  Stream<List<ManagedConversation>>? _conversationsStream;
  List<ManagedConversation>? _conversationsCache;
  final Map<String, Stream<List<ManagedMessage>>> _messageStreams =
      <String, Stream<List<ManagedMessage>>>{};
  String? _managedAccountId;

  String? get managedAccountId => _managedAccountId;
  ManagedAccount? get managedAccount => accountController.selectedAccount;
  bool get hasManagedAccount => _managedAccountId != null;

  ChatMediaPicker get mediaPicker => _mediaPicker;
  VoiceRecorder get voiceRecorder => _voiceRecorder;
  VideoPlaybackControllerFactory get videoPlaybackFactory =>
      _videoPlaybackFactory;

  /// AI helpers for in-chat translation (text messages).
  ///
  /// Lazily created so tests that inject fakes never touch the Supabase
  /// client; tests may inject a [ChatAiService] fake instead.
  ChatAiService get chatAi =>
      _chatAi ?? (_lazyChatAi ??= SupabaseChatAiService());

  void _onAccountChanged() {
    final String? newId = accountController.selectedAccount?.id;
    if (_managedAccountId == newId) return;
    _conversationsSub?.cancel();
    _conversationsSub = null;
    _conversationsStream = null;
    _conversationsCache = null;
    _messageStreams.clear();
    _managedAccountId = newId;
    notifyListeners();
  }

  Stream<List<ManagedConversation>> watchConversations() {
    final String? accountId = _managedAccountId;
    if (accountId == null) {
      return Stream<List<ManagedConversation>>.empty();
    }
    final Stream<List<ManagedConversation>> source =
        _conversationsStream ??= _createConversationsBroadcast(accountId);
    return Stream<List<ManagedConversation>>.multi(
      (StreamController<List<ManagedConversation>> controller) {
        final List<ManagedConversation>? latest = _conversationsCache;
        if (latest != null && !controller.isClosed) controller.add(latest);
        late final StreamSubscription<List<ManagedConversation>> sub;
        sub = source.listen(
          (List<ManagedConversation> value) {
            if (!controller.isClosed) controller.add(value);
          },
          onError: (Object e, StackTrace st) {
            if (!controller.isClosed) controller.addError(e, st);
          },
          onDone: () {
            if (!controller.isClosed) controller.close();
          },
        );
        controller.onCancel = () => sub.cancel();
      },
    );
  }

  Stream<List<ManagedConversation>> _createConversationsBroadcast(
      String managedAccountId) {
    final StreamController<List<ManagedConversation>> controller =
        StreamController<List<ManagedConversation>>.broadcast();
    _conversationsSub = chatRepository
        .watchConversations(managedAccountId)
        .listen(
          (List<ManagedConversation> value) {
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

  Future<String> openConversation(String peerUid) async {
    final String? accountId = _managedAccountId;
    if (accountId == null) {
      throw StateError('No managed account selected.');
    }
    return chatRepository.ensureConversation(
      managedAccountId: accountId,
      peerUid: peerUid,
    );
  }

  Stream<List<ManagedMessage>> watchMessages(String conversationId) {
    return _messageStreams.putIfAbsent(
      conversationId,
      () => chatRepository.watchMessages(conversationId),
    );
  }

  /// Live presence (online flag + last seen) for a peer in a managed chat.
  Stream<UserProfile?> watchPeerPresence(String peerUid) {
    return chatRepository.watchPeerPresence(peerUid);
  }

  Future<List<ManagedMessage>> fetchMessagesBefore(
    String conversationId,
    ManagedMessage before,
  ) {
    return chatRepository.fetchMessagesBefore(conversationId, before);
  }

  Future<void> sendMessage({
    required String conversationId,
    required String text,
    String? replyToId,
    String? replyToType,
    String? replyToText,
    String? replyToSender,
    String? senderLang,
    String? originalText,
    String? sourceLang,
  }) {
    final String? accountId = _managedAccountId;
    if (accountId == null) {
      return Future<void>.value();
    }
    final String body = text.trim();
    if (body.isEmpty) return Future<void>.value();
    return chatRepository.sendMessage(
      conversationId: conversationId,
      managedAccountId: accountId,
      senderUid: accountId,
      text: body,
      replyToId: replyToId,
      replyToType: replyToType,
      replyToText: replyToType == 'text' ? replyToText : null,
      replyToSender: replyToSender,
      senderLang: senderLang,
      originalText: originalText,
      sourceLang: sourceLang,
    );
  }

  String newMessageId() =>
      'mm_${DateTime.now().microsecondsSinceEpoch}_${DateTime.now().millisecond}';

  Future<MediaUploadTask> uploadChatMedia({
    required String conversationId,
    required String messageId,
    required Uint8List bytes,
    required String contentType,
    required String fileName,
  }) {
    return chatRepository.uploadChatMedia(
      conversationId: conversationId,
      messageId: messageId,
      bytes: bytes,
      contentType: contentType,
      fileName: fileName,
    );
  }

  Future<MediaUploadTask> uploadChatThumbnail({
    required String conversationId,
    required String messageId,
    required Uint8List bytes,
    required String contentType,
  }) {
    return chatRepository.uploadChatThumbnail(
      conversationId: conversationId,
      messageId: messageId,
      bytes: bytes,
      contentType: contentType,
    );
  }

  Future<void> sendMediaMessage({
    required String conversationId,
    required String messageId,
    required MessageMedia media,
    String? replyToId,
    String? replyToType,
    String? replyToText,
    String? replyToSender,
    String? voiceEffect,
  }) {
    final String? accountId = _managedAccountId;
    if (accountId == null) return Future<void>.value();
    return chatRepository.sendMessage(
      conversationId: conversationId,
      managedAccountId: accountId,
      senderUid: accountId,
      text: '',
      messageId: messageId,
      type: _toManagedType(media.type),
      mediaUrl: media.url,
      thumbnailUrl: media.thumbnailUrl,
      durationMs: media.durationMs,
      width: media.width,
      height: media.height,
      fileName: media.fileName,
      mimeType: media.mimeType,
      sizeBytes: media.sizeBytes,
      voiceEffect: voiceEffect ?? media.voiceEffect,
      replyToId: replyToId,
      replyToType: replyToType,
      replyToText: replyToType == 'text' ? replyToText : null,
      replyToSender: replyToSender,
    );
  }

  Future<void> deleteMessage({
    required String conversationId,
    required String messageId,
  }) {
    return chatRepository.deleteMessage(
      conversationId: conversationId,
      messageId: messageId,
    );
  }

  Future<void> markConversationRead(String conversationId) {
    final String? accountId = _managedAccountId;
    if (accountId == null) return Future<void>.value();
    return chatRepository.markConversationRead(
      conversationId: conversationId,
      managedAccountId: accountId,
    );
  }

  Future<void> markMessagesDelivered(
    String conversationId,
    List<String> messageIds,
  ) {
    if (messageIds.isEmpty) return Future<void>.value();
    return chatRepository.markMessagesDelivered(conversationId, messageIds);
  }

  Future<void> markMessagesRead(
    String conversationId,
    List<String> messageIds,
  ) {
    if (messageIds.isEmpty) return Future<void>.value();
    return chatRepository.markMessagesRead(conversationId, messageIds);
  }

  Future<void> setTyping(String conversationId) {
    return chatRepository.setTyping(conversationId);
  }

  // ----- Managed calls -----

  Future<ManagedCall> startCall({
    required String conversationId,
    required String peerUid,
    required ManagedCallType type,
  }) {
    final String? accountId = _managedAccountId;
    if (accountId == null) {
      throw StateError('No managed account selected.');
    }
    return chatRepository.startCall(
      managedAccountId: accountId,
      conversationId: conversationId,
      peerUid: peerUid,
      type: type,
    );
  }

  Stream<ManagedCall> watchCall(String callId) {
    return chatRepository.watchCall(callId);
  }

  Future<ManagedCall?> fetchCall(String callId) {
    return chatRepository.fetchCall(callId);
  }

  Future<void> endCall({
    required String callId,
    required String byUid,
  }) {
    return chatRepository.endCall(callId: callId, byUid: byUid);
  }

  Future<void> answerCall(String callId) {
    return chatRepository.answerCall(callId);
  }

  Future<void> markMissed(String callId) {
    return chatRepository.markMissed(callId);
  }

  Future<void> declineCall(String callId) {
    return chatRepository.declineCall(callId);
  }

  Future<List<ManagedCall>> fetchCallHistory() {
    final String? accountId = _managedAccountId;
    if (accountId == null) return Future<List<ManagedCall>>.value(<ManagedCall>[]);
    return chatRepository.fetchCallHistory(accountId);
  }

  Stream<void> watchCallChanges() {
    final String? accountId = _managedAccountId;
    if (accountId == null) return Stream<void>.empty();
    return chatRepository.watchCallChanges(accountId);
  }

  // ----- Managed status -----

  Stream<List<ManagedStatusGroup>> watchStatuses() {
    final String? accountId = _managedAccountId;
    if (accountId == null) {
      return Stream<List<ManagedStatusGroup>>.empty();
    }
    return chatRepository.watchStatuses(accountId);
  }

  Future<String> postStatus({
    required ManagedStatusType type,
    String text = '',
    String? statusId,
    String? mediaUrl,
    String? thumbnailUrl,
    int? durationMs,
    double? width,
    double? height,
    String? mimeType,
  }) {
    final String? accountId = _managedAccountId;
    if (accountId == null) {
      throw StateError('No managed account selected.');
    }
    return chatRepository.postStatus(
      managedAccountId: accountId,
      type: type,
      text: text,
      statusId: statusId,
      mediaUrl: mediaUrl,
      thumbnailUrl: thumbnailUrl,
      durationMs: durationMs,
      width: width,
      height: height,
      mimeType: mimeType,
    );
  }

  Future<MediaUploadTask> uploadStatusMedia({
    required String statusId,
    required Uint8List bytes,
    required String contentType,
    required String fileName,
  }) {
    final String? accountId = _managedAccountId;
    if (accountId == null) {
      throw StateError('No managed account selected.');
    }
    return chatRepository.uploadStatusMedia(
      managedAccountId: accountId,
      statusId: statusId,
      bytes: bytes,
      contentType: contentType,
      fileName: fileName,
    );
  }

  Future<MediaUploadTask> uploadStatusThumbnail({
    required String statusId,
    required Uint8List bytes,
    required String contentType,
  }) {
    final String? accountId = _managedAccountId;
    if (accountId == null) {
      throw StateError('No managed account selected.');
    }
    return chatRepository.uploadStatusThumbnail(
      managedAccountId: accountId,
      statusId: statusId,
      bytes: bytes,
      contentType: contentType,
    );
  }

  Future<void> markStatusViewed(String statusId) {
    return chatRepository.markStatusViewed(statusId);
  }

  Future<void> deleteStatus(String statusId) {
    return chatRepository.deleteStatus(statusId);
  }

  Future<List<ManagedStatusViewer>> fetchStatusViewers(String statusId) {
    return chatRepository.fetchStatusViewers(statusId);
  }

  @override
  void dispose() {
    accountController.removeListener(_onAccountChanged);
    _conversationsSub?.cancel();
    super.dispose();
  }

  ManagedMessageType _toManagedType(MessageType type) => switch (type) {
        MessageType.image => ManagedMessageType.image,
        MessageType.video => ManagedMessageType.video,
        MessageType.voice => ManagedMessageType.voice,
        MessageType.text => ManagedMessageType.text,
      };
}
