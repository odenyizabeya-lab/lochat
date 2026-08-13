/// Who authored an AI message.
enum AiRole {
  user,
  assistant;

  static AiRole fromWireName(String? name) =>
      name == 'assistant' ? AiRole.assistant : AiRole.user;
}

/// A single persisted message inside an AI conversation.
class AiMessage {
  const AiMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final AiRole role;
  final String content;
  final DateTime createdAt;

  bool get isUser => role == AiRole.user;

  factory AiMessage.fromJson(Map<String, dynamic> json) {
    return AiMessage(
      id: json['id'] as String? ?? '',
      role: AiRole.fromWireName(json['role'] as String?),
      content: json['content'] as String? ?? '',
      createdAt: _toDate(json['created_at']) ?? DateTime.now(),
    );
  }

  static DateTime? _toDate(Object? value) {
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
