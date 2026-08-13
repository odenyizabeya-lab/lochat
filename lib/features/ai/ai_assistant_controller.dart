import 'package:flutter/foundation.dart';

import '../../core/auth/auth_controller.dart';
import 'ai_assistant_exception.dart';
import 'ai_assistant_service.dart';
import 'ai_chat_result.dart';
import 'models/ai_conversation.dart';
import 'models/ai_message.dart';
import 'models/ai_provider.dart';
import 'models/ai_task.dart';

/// App-wide state for the AI assistant.
///
/// Follows the same pattern as [ChatController]: state is per signed-in user
/// and cleared when the user changes. Conversations are loaded on demand by
/// the AI screen; the controller keeps a lightweight cache so switching tabs
/// does not re-fetch.
class AiAssistantController extends ChangeNotifier {
  AiAssistantController({
    required this._auth,
    required this._service,
  }) {
    _auth.addListener(_handleAuthChange);
    _handleAuthChange();
  }

  final AuthController _auth;
  final AiAssistantService _service;

  List<AiConversation> _conversations = const <AiConversation>[];
  bool _conversationsLoading = false;
  String? _conversationsError;

  String? _selectedId;
  List<AiMessage> _messages = const <AiMessage>[];
  bool _messagesLoading = false;
  String? _messagesError;

  bool _sending = false;
  String? _sendingError;

  AiProvider _provider = AiProvider.openai;

  /// The provider applied to new conversations.
  AiProvider get provider => _provider;

  List<AiConversation> get conversations => _conversations;
  bool get conversationsLoading => _conversationsLoading;
  String? get conversationsError => _conversationsError;

  /// The conversation currently open in the chat view, or null when the user
  /// is on the conversation list / a fresh chat.
  AiConversation? get selectedConversation {
    for (final AiConversation conversation in _conversations) {
      if (conversation.id == _selectedId) return conversation;
    }
    return null;
  }

  List<AiMessage> get messages => _messages;
  bool get messagesLoading => _messagesLoading;
  String? get messagesError => _messagesError;

  bool get sending => _sending;
  String? get sendingError => _sendingError;

  /// Loads (or refreshes) the conversation list.
  Future<void> loadConversations() async {
    if (_conversationsLoading) return;
    _conversationsLoading = true;
    _conversationsError = null;
    notifyListeners();
    try {
      _conversations = await _service.listConversations();
    } on AiAssistantException catch (e) {
      _conversationsError = e.message;
    } catch (_) {
      _conversationsError = 'Could not load your AI chats. Please try again.';
    } finally {
      _conversationsLoading = false;
      notifyListeners();
    }
  }

  /// Opens a fresh, empty chat. The conversation row is only created
  /// server-side once the first message is sent, so "new chat" never leaves
  /// empty rows behind.
  void startNewChat() {
    _selectedId = null;
    _messages = const <AiMessage>[];
    _messagesLoading = false;
    _messagesError = null;
    _sendingError = null;
    notifyListeners();
  }

  /// Opens [conversationId] and loads its messages.
  Future<void> selectConversation(String id) async {
    if (_selectedId == id && !_messagesLoading) return;
    _selectedId = id;
    _messages = const <AiMessage>[];
    _messagesLoading = true;
    _messagesError = null;
    notifyListeners();
    try {
      _messages = await _service.fetchMessages(id);
    } on AiAssistantException catch (e) {
      _messagesError = e.message;
    } catch (_) {
      _messagesError = 'Could not load this chat. Please try again.';
    } finally {
      _messagesLoading = false;
      notifyListeners();
    }
  }

  /// Returns to the conversation list.
  void deselectConversation() {
    _selectedId = null;
    _messages = const <AiMessage>[];
    _messagesError = null;
    notifyListeners();
  }

  /// Deletes a conversation (and its messages) from the server and the list.
  Future<void> deleteConversation(String id) async {
    try {
      await _service.deleteConversation(id);
      _conversations =
          _conversations.where((AiConversation c) => c.id != id).toList();
      if (_selectedId == id) {
        _selectedId = null;
        _messages = const <AiMessage>[];
      }
      notifyListeners();
    } on AiAssistantException catch (e) {
      _sendingError = e.message;
    } catch (_) {
      _sendingError = 'Could not delete the chat. Please try again.';
    }
  }

  /// Switches which provider backs the selected conversation (and becomes the
  /// default for new chats).
  Future<void> setProvider(AiProvider provider) async {
    final String? selectedId = _selectedId;
    _provider = provider;
    if (selectedId != null) {
      try {
        final AiConversation updated = await _service.setProvider(
          conversationId: selectedId,
          provider: provider,
        );
        _replaceConversation(updated);
      } on AiAssistantException catch (e) {
        _sendingError = e.message;
      } catch (_) {
        _sendingError = 'Could not switch the AI provider. Please try again.';
      }
    }
    notifyListeners();
  }

  /// Sends [content] (optionally with a quick [task]) and appends both the
  /// persisted user message and the assistant reply. Returns true on success.
  ///
  /// When no conversation is open yet, one is created on the fly.
  Future<bool> send({
    required String content,
    AiTask? task,
    String? targetLanguage,
  }) async {
    final String trimmed = content.trim();
    if (_sending || trimmed.isEmpty) return false;

    _sending = true;
    _sendingError = null;
    notifyListeners();
    try {
      String conversationId = _selectedId ?? '';
      if (conversationId.isEmpty) {
        final AiConversation conversation = await _service.createConversation(
          title: 'New chat',
          provider: _provider,
        );
        conversationId = conversation.id;
        _selectedId = conversationId;
        _conversations = <AiConversation>[conversation, ..._conversations];
      }
      final AiChatResult result = await _service.sendMessage(
        conversationId: conversationId,
        content: trimmed,
        task: task,
        targetLanguage: targetLanguage,
      );
      _messages = <AiMessage>[..._messages, result.user, result.assistant];
      _syncConversationHeader(trimmed);
      return true;
    } on AiAssistantException catch (e) {
      _sendingError = e.message;
      return false;
    } catch (_) {
      _sendingError = 'Something went wrong. Please try again.';
      return false;
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  /// Clears the transient send/provider error shown in the composer.
  void clearSendError() {
    if (_sendingError != null) {
      _sendingError = null;
      notifyListeners();
    }
  }

  void _replaceConversation(AiConversation updated) {
    _conversations = _conversations
        .map((AiConversation c) => c.id == updated.id ? updated : c)
        .toList();
  }

  /// After a successful send, name a "New chat" after its first message and
  /// keep the list ordered by recency.
  void _syncConversationHeader(String content) {
    final String id = _selectedId ?? '';
    bool changed = false;
    final List<AiConversation> updated = <AiConversation>[];
    for (final AiConversation conversation in _conversations) {
      if (conversation.id != id) {
        updated.add(conversation);
        continue;
      }
      final String title = conversation.title == 'New chat'
          ? (content.length > 40 ? '${content.substring(0, 40)}\u2026' : content)
          : conversation.title;
      updated.add(conversation.copyWith(
        title: title,
        updatedAt: DateTime.now(),
      ));
      changed = true;
    }
    if (changed) {
      updated.sort(
        (AiConversation a, AiConversation b) =>
            b.updatedAt.compareTo(a.updatedAt),
      );
      _conversations = updated;
    }
  }

  void _handleAuthChange() {
    final String? uid = _auth.currentUser?.uid;
    if (uid == null) return;
    _reset();
  }

  void _reset() {
    _conversations = const <AiConversation>[];
    _conversationsLoading = false;
    _conversationsError = null;
    _selectedId = null;
    _messages = const <AiMessage>[];
    _messagesLoading = false;
    _messagesError = null;
    _sending = false;
    _sendingError = null;
    _provider = AiProvider.openai;
  }

  @override
  void dispose() {
    _auth.removeListener(_handleAuthChange);
    super.dispose();
  }
}
