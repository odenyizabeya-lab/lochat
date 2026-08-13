import 'ai_chat_result.dart';
import 'models/ai_conversation.dart';
import 'models/ai_message.dart';
import 'models/ai_provider.dart';
import 'models/ai_task.dart';

/// Backend contract for the AI assistant.
///
/// The UI depends only on this interface; tests inject an in-memory fake. The
/// production implementation talks to the `ai-assistant` edge function, so no
/// AI provider key ever reaches the app.
abstract interface class AiAssistantService {
  /// All of the signed-in user's AI conversations, newest first.
  Future<List<AiConversation>> listConversations();

  /// Creates a new conversation with [title] (defaults to "New chat") backed
  /// by [provider].
  Future<AiConversation> createConversation({
    String title,
    required AiProvider provider,
  });

  /// Switches which provider serves [conversationId].
  Future<AiConversation> setProvider({
    required String conversationId,
    required AiProvider provider,
  });

  /// Deletes [conversationId] and its messages.
  Future<void> deleteConversation(String conversationId);

  /// All messages of [conversationId], oldest first.
  Future<List<AiMessage>> fetchMessages(String conversationId);

  /// Appends [content] as a user message, generates the assistant reply with
  /// the conversation's provider, persists it, and returns both messages.
  ///
  /// [task] selects a quick action (write reply / rewrite / suggest replies /
  /// summarize / translate); [targetLanguage] is used for translation.
  Future<AiChatResult> sendMessage({
    required String conversationId,
    required String content,
    AiTask? task,
    String? targetLanguage,
  });
}
