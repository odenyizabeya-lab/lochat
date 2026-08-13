/// The AI provider backing a conversation.
///
/// Keys live server-side in the `ai-assistant` edge function; the app only
/// sends the provider name.
enum AiProvider {
  openai('openai', 'OpenAI'),
  anthropic('anthropic', 'Claude'),
  gemini('gemini', 'Gemini');

  const AiProvider(this.wireName, this.label);

  /// The value sent to / received from the edge function.
  final String wireName;

  /// Human-readable provider name shown in the UI.
  final String label;

  static AiProvider fromWireName(String? name) => switch (name) {
        'anthropic' => AiProvider.anthropic,
        'gemini' => AiProvider.gemini,
        _ => AiProvider.openai,
      };
}
