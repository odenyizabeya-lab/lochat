/// A user-facing error from the AI assistant backend. The message is safe to
/// show in the UI.
class AiAssistantException implements Exception {
  const AiAssistantException(this.message);

  final String message;

  @override
  String toString() => 'AiAssistantException: $message';
}
