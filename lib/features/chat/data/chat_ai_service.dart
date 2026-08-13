/// Thrown when an in-chat AI operation (translation) fails.
class ChatAiException implements Exception {
  const ChatAiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The result of translating a voice message: the transcript in the original
/// language plus its translation into the requested language.
class VoiceTranslationResult {
  const VoiceTranslationResult({
    required this.transcript,
    required this.translation,
  });

  final String transcript;
  final String translation;
}

/// AI-backed helpers for the chat screen.
///
/// Backed by the `ai-assistant` edge function (provider keys live on the
/// server / admin dashboard), so the app never holds an AI key. The chat UI
/// depends only on this interface; tests inject a fake.
abstract interface class ChatAiService {
  /// Translates [text] into [targetLanguage] (e.g. "French").
  Future<String> translateText({
    required String text,
    required String targetLanguage,
  });

  /// Transcribes the voice clip at [audioUrl] and translates the transcript
  /// into [targetLanguage], returning both.
  Future<VoiceTranslationResult> translateVoice({
    required String audioUrl,
    required String targetLanguage,
  });
}
