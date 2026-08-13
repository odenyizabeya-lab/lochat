import 'ai_provider.dart';

/// One AI assistant conversation owned by the signed-in user.
class AiConversation {
  const AiConversation({
    required this.id,
    required this.title,
    required this.provider,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final AiProvider provider;
  final DateTime createdAt;
  final DateTime updatedAt;

  AiConversation copyWith({
    String? title,
    AiProvider? provider,
    DateTime? updatedAt,
  }) {
    return AiConversation(
      id: id,
      title: title ?? this.title,
      provider: provider ?? this.provider,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory AiConversation.fromJson(Map<String, dynamic> json) {
    return AiConversation(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? 'New chat',
      provider: AiProvider.fromWireName(json['provider'] as String?),
      createdAt: _toDate(json['created_at']) ?? DateTime.now(),
      updatedAt: _toDate(json['updated_at']) ?? DateTime.now(),
    );
  }

  static DateTime? _toDate(Object? value) {
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
