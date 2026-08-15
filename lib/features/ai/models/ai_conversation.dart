import 'package:lotext/features/ai/models/ai_provider.dart';
import 'package:lotext/features/ai/models/ai_user_profile.dart';

/// One AI assistant conversation owned by the signed-in user.
class AiConversation {
  const AiConversation({
    required this.id,
    required this.title,
    required this.provider,
    required this.createdAt,
    required this.updatedAt,
    this.profile,
  });

  final String id;
  final String title;
  final AiProvider provider;
  final DateTime createdAt;
  final DateTime updatedAt;
  final AiUserProfile? profile;

  AiConversation copyWith({
    String? title,
    AiProvider? provider,
    DateTime? updatedAt,
    AiUserProfile? profile,
  }) {
    return AiConversation(
      id: id,
      title: title ?? this.title,
      provider: provider ?? this.provider,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      profile: profile ?? this.profile,
    );
  }

  factory AiConversation.fromJson(Map<String, dynamic> json) {
    return AiConversation(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? 'New chat',
      provider: AiProvider.fromWireName(json['provider'] as String?),
      createdAt: _parseDate(json['created_at']) ?? DateTime.now(),
      updatedAt: _parseDate(json['updated_at']) ?? DateTime.now(),
      profile: json['profile'] != null
          ? AiUserProfile.fromJson(json['profile'] as Map<String, dynamic>)
          : null,
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
