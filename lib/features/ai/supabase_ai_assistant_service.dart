import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:lotext/features/ai/models/ai_user_profile.dart';

import 'ai_assistant_exception.dart';
import 'ai_assistant_service.dart';
import 'ai_chat_result.dart';
import 'models/ai_conversation.dart';
import 'models/ai_message.dart';
import 'models/ai_provider.dart';
import 'models/ai_task.dart';

/// Production [AiAssistantService] backed by the `ai-assistant` edge function.
///
/// The function resolves the caller from the Supabase JWT (sent automatically
/// by [SupabaseClient.functions.invoke]) and holds every AI provider key, so
/// the app itself never sees them.
class SupabaseAiAssistantService implements AiAssistantService {
  SupabaseAiAssistantService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Future<List<AiConversation>> listConversations() async {
    final dynamic data = await _invoke(<String, dynamic>{'action': 'list'});
    final List conversations = (data as Map<String, dynamic>)['conversations']
            as List? ??
        const <dynamic>[];
    return conversations
        .map((dynamic row) =>
            AiConversation.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<AiConversation> createConversation({
    String title = 'New chat',
    required AiProvider provider,
  }) async {
    final dynamic data = await _invoke(<String, dynamic>{
      'action': 'create',
      'title': title,
      'provider': provider.wireName,
    });
    return AiConversation.fromJson(
      (data as Map<String, dynamic>)['conversation'] as Map<String, dynamic>,
    );
  }

  @override
  Future<AiConversation> setProvider({
    required String conversationId,
    required AiProvider provider,
  }) async {
    final dynamic data = await _invoke(<String, dynamic>{
      'action': 'setProvider',
      'conversationId': conversationId,
      'provider': provider.wireName,
    });
    return AiConversation.fromJson(
      (data as Map<String, dynamic>)['conversation'] as Map<String, dynamic>,
    );
  }

  @override
  Future<void> deleteConversation(String conversationId) async {
    await _invoke(<String, dynamic>{
      'action': 'delete',
      'conversationId': conversationId,
    });
  }

  @override
  Future<List<AiMessage>> fetchMessages(String conversationId) async {
    final dynamic data = await _invoke(<String, dynamic>{
      'action': 'history',
      'conversationId': conversationId,
    });
    final List messages = (data as Map<String, dynamic>)['messages'] as List? ??
        const <dynamic>[];
    return messages
        .map((dynamic row) => AiMessage.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<AiChatResult> sendMessage({
    required String conversationId,
    required String content,
    AiTask? task,
    String? targetLanguage,
    AiUserProfile? profile,
  }) async {
    final dynamic data = await _invoke(<String, dynamic>{
      'action': 'chat',
      'conversationId': conversationId,
      'content': content,
      'task': ?task?.wireName,
      'targetLanguage': ?targetLanguage,
      'profile': profile?.toJson(),
    });
    final Map<String, dynamic> map = data as Map<String, dynamic>;
    return AiChatResult(
      user: AiMessage.fromJson(map['user'] as Map<String, dynamic>),
      assistant:
          AiMessage.fromJson(map['assistant'] as Map<String, dynamic>),
    );
  }

  Future<dynamic> _invoke(Map<String, dynamic> body) async {
    try {
      final FunctionResponse response =
          await _client.functions.invoke('ai-assistant', body: body);
      final dynamic data = response.data;
      if (data is Map && data['error'] is String && (data['error'] as String).isNotEmpty) {
        throw AiAssistantException(data['error'] as String);
      }
      return data;
    } on AiAssistantException {
      rethrow;
    } on Exception catch (error) {
      final String message = error.toString().toLowerCase();
      if (message.contains('rate limit') || message.contains('quota')) {
        throw const AiAssistantException(
          'The AI service is busy right now. Please try again in a moment.',
        );
      }
      throw const AiAssistantException(
        'The AI assistant is unavailable right now. Please try again.',
      );
    }
  }
}
