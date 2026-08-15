import 'package:lotext/features/ai/models/ai_user_profile.dart';

/// Quick AI actions available from the assistant composer. Each maps to a
/// server-side system prompt, so the provider still generates the content.
enum AiTask {
  reply('reply', 'Write reply'),
  rewrite('rewrite', 'Rewrite'),
  suggest('suggest', 'Suggest replies'),
  summarize('summarize', 'Summarize'),
  translate('translate', 'Translate');

  const AiTask(this.wireName, this.label, {this.profile = const AiUserProfile()});

  /// The value sent to the edge function.
  final String wireName;

  /// Short button label shown in the UI.
  final String label;

  /// Optional AI user profile to shape the assistant's persona.
  final AiUserProfile profile;

  static AiTask? fromWireName(String? name) => switch (name) {
        'reply' => AiTask.reply,
        'rewrite' => AiTask.rewrite,
        'suggest' => AiTask.suggest,
        'summarize' => AiTask.summarize,
        'translate' => AiTask.translate,
        _ => null,
      };
}
