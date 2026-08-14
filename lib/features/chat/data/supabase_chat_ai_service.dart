import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'chat_ai_service.dart';

/// Production [ChatAiService] backed by the `ai-assistant` edge function.
///
/// The function verifies the caller's JWT, holds every AI provider key
/// (env secret or the `app_config` values managed in the Admin dashboard) and
/// calls the provider on the server, so the app never sees a key.
class SupabaseChatAiService implements ChatAiService {
  SupabaseChatAiService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Future<TextTranslationResult> translateText({
    required String text,
    required String targetLanguage,
  }) async {
    final dynamic data = await _invoke(<String, dynamic>{
      'action': 'translateText',
      'text': text,
      'targetLanguage': targetLanguage,
    });
    final Map<String, dynamic> map = data as Map<String, dynamic>;
    return TextTranslationResult(
      translation: map['translation'] as String? ?? '',
      sourceLanguage: map['sourceLanguage'] as String? ?? '',
    );
  }

  @override
  Future<VoiceTranslationResult> translateVoice({
    required String audioUrl,
    required String targetLanguage,
  }) async {
    final dynamic data = await _invoke(<String, dynamic>{
      'action': 'transcribe',
      'audioUrl': audioUrl,
      'targetLanguage': targetLanguage,
    });
    final Map<String, dynamic> map = data as Map<String, dynamic>;
    return VoiceTranslationResult(
      transcript: map['transcript'] as String? ?? '',
      translation: map['translation'] as String? ?? '',
    );
  }

  @override
  Future<VoiceSynthesisResult> synthesizeVoice({
    required String voiceName,
    String? text,
    Uint8List? audioBytes,
  }) async {
    final dynamic data = await _invoke(<String, dynamic>{
      'action': 'synthesizeVoice',
      'voiceName': voiceName,
      if (text != null && text.trim().isNotEmpty) 'text': text,
      if (audioBytes != null) 'audioBase64': base64Encode(audioBytes),
    });
    final Map<String, dynamic> map = data as Map<String, dynamic>;
    final String audioBase64 = map['audioBase64'] as String? ?? '';
    if (audioBase64.isEmpty) {
      throw const ChatAiException('Could not create the voice message.');
    }
    return VoiceSynthesisResult(
      audioBytes: base64Decode(audioBase64),
      contentType: map['contentType'] as String? ?? 'audio/mpeg',
    );
  }

  Future<dynamic> _invoke(Map<String, dynamic> body) async {
    try {
      final FunctionResponse response =
          await _client.functions.invoke('ai-assistant', body: body);
      final dynamic data = response.data;
      if (data is Map &&
          data['error'] is String &&
          (data['error'] as String).isNotEmpty) {
        throw ChatAiException(data['error'] as String);
      }
      return data;
    } on ChatAiException {
      rethrow;
    } on Exception {
      throw const ChatAiException(
        'Translation is unavailable right now. Please try again.',
      );
    }
  }
}
