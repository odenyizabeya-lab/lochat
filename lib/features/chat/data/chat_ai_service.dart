import 'dart:typed_data';

/// Thrown when an in-chat AI operation (translation) fails.
class ChatAiException implements Exception {
  const ChatAiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The result of translating a text message: the translation plus a
/// best-effort English name of the source language (e.g. "French"), used for
/// the "Translated from X" label. Empty when the provider could not tell.
class TextTranslationResult {
  const TextTranslationResult({
    required this.translation,
    this.sourceLanguage = '',
  });

  final String translation;
  final String sourceLanguage;
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

/// The result of creating a voice-changer message: the synthesized audio to
/// upload and send as the voice note.
class VoiceSynthesisResult {
  const VoiceSynthesisResult({
    required this.audioBytes,
    required this.contentType,
  });

  /// MP3 bytes of the synthesized speech (Microsoft Edge neural voice).
  final Uint8List audioBytes;

  /// MIME type of [audioBytes] (always `audio/mpeg` today).
  final String contentType;
}

/// AI-backed helpers for the chat screen.
///
/// Backed by the `ai-assistant` edge function (provider keys live on the
/// server / admin dashboard), so the app never holds an AI key. The chat UI
/// depends only on this interface; tests inject a fake.
abstract interface class ChatAiService {
  /// Translates [text] into [targetLanguage] (e.g. "French").
  Future<TextTranslationResult> translateText({
    required String text,
    required String targetLanguage,
  });

  /// Transcribes the voice clip at [audioUrl] and translates the transcript
  /// into [targetLanguage], returning both.
  Future<VoiceTranslationResult> translateVoice({
    required String audioUrl,
    required String targetLanguage,
  });

  /// Speaks [text] in the neural voice [voiceName] (type-to-speak), or — when
  /// [audioBytes] holds a recording — transcribes it and re-speaks it in that
  /// voice (record-to-respeak). Exactly one of [text]/[audioBytes] is set.
  Future<VoiceSynthesisResult> synthesizeVoice({
    required String voiceName,
    String? text,
    Uint8List? audioBytes,
  });
}
