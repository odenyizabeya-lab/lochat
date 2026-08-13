import 'models/ai_message.dart';

/// The outcome of sending a message: the user's persisted message followed by
/// the assistant's reply.
class AiChatResult {
  const AiChatResult({required this.user, required this.assistant});

  final AiMessage user;
  final AiMessage assistant;
}
