import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../features/chat/data/chat_repository.dart';
import '../../features/chat/media/chat_media_picker.dart';
import '../../features/chat/media/device_chat_media_picker.dart';
import '../../features/chat/media/device_voice_recorder.dart';
import '../../features/chat/media/media_playback.dart';
import '../../features/chat/media/voice_recorder.dart';
import '../../features/chat/models/chat_message.dart';
import './managed_account_controller.dart';
import './models/managed_account.dart';
import './models/managed_conversation.dart';
import './models/managed_message.dart';
import './data/managed_chat_repository.dart';

class ManagedChatController extends ChangeNotifier {
  ManagedChatController({
    required this.chatRepository,
    required this.accountController,
    ChatMediaPicker? mediaPicker,
    VoiceRecorder? voiceRecorder,
  })  : _mediaPicker = mediaPicker ?? DeviceChatMediaPicker(),
        _voiceRecorder = voiceRecorder ?? DeviceVoiceRecorder() {
    accountController.addListener(_onAccountChanged);
    _onAccountChanged();
  }

  final ManagedChatRepository chatRepository;
  final ManagedAccountController accountController;
  final ChatMediaPicker _mediaPicker;
  final VoiceRecorder _voiceRecorder;

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

  @override
  void dispose() {
    accountController.removeListener(_onAccountChanged);
    _conversationsSub?.cancel();
    for (final Stream<List<ManagedMessage>> stream in _messageStreams.values) {
      // ignore: cancel_subscriptions
    }
    super.dispose();
  }

  ManagedMessageType _toManagedType(MessageType type) => switch (type) {
        MessageType.image => ManagedMessageType.image,
        MessageType.video => ManagedMessageType.video,
        MessageType.voice => ManagedMessageType.voice,
        MessageType.text => ManagedMessageType.text,
      };
}
