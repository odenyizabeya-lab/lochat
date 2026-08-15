/// User profile data that the AI assistant uses to chat as the user.
///
/// This information is stored server-side and passed to the AI on each
/// conversation so the assistant can mimic the user's name, writing style,
/// personality, and preferences.
class AiUserProfile {
  const AiUserProfile({
    this.displayName = '',
    this.username = '',
    this.writeGoodEnglish = true,
    this.personality = 'balanced', // balanced, caring, business, funny, etc.
    this.preferredTopics = const <String>[],
    this.avoidTopics = const <String>[],
    this.favoritePhrases = const <String>[],
  });

  /// The name the AI should use when referring to itself or responding.
  final String displayName;

  /// The username/handle the AI should use.
  final String username;

  /// Whether the user writes good English - if false, the AI will adapt to
  /// the user's level while still being understandable.
  final bool writeGoodEnglish;

  /// Overall personality style for the AI to adopt.
  /// - balanced: Normal friendly conversation
  /// - caring: Warm, empathetic, supportive
  /// - business: Professional, concise, task-oriented
  /// - funny: Light-hearted, jokes, humor
  /// - flirty: Playful, romantic undertones
  final String personality;

  /// Topics the AI should focus on or prioritize in conversation.
  final List<String> preferredTopics;

  /// Topics the AI should avoid or handle carefully.
  final List<String> avoidTopics;

  /// Phrases or styles the user commonly uses.
  final List<String> favoritePhrases;

  AiUserProfile copyWith({
    String? displayName,
    String? username,
    bool? writeGoodEnglish,
    String? personality,
    List<String>? preferredTopics,
    List<String>? avoidTopics,
    List<String>? favoritePhrases,
  }) {
    return AiUserProfile(
      displayName: displayName ?? this.displayName,
      username: username ?? this.username,
      writeGoodEnglish: writeGoodEnglish ?? this.writeGoodEnglish,
      personality: personality ?? this.personality,
      preferredTopics: preferredTopics ?? this.preferredTopics,
      avoidTopics: avoidTopics ?? this.avoidTopics,
      favoritePhrases: favoritePhrases ?? this.favoritePhrases,
    );
  }

  /// Create a profile from a user's display name and known characteristics.
  factory AiUserProfile.fromUser({
    required String displayName,
    required String username,
    bool writeGoodEnglish = true,
    String personality = 'balanced',
  }) {
    return AiUserProfile(
      displayName: displayName,
      username: username,
      writeGoodEnglish: writeGoodEnglish,
      personality: personality,
    );
  }

  @override
  String toString() {
    return 'AiUserProfile{displayName: $displayName, username: $username, '
        'writeGoodEnglish: $writeGoodEnglish, personality: $personality}';
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'displayName': displayName,
        'username': username,
        'writeGoodEnglish': writeGoodEnglish,
        'personality': personality,
        'preferredTopics': preferredTopics,
        'avoidTopics': avoidTopics,
        'favoritePhrases': favoritePhrases,
      };

  factory AiUserProfile.fromJson(Map<String, dynamic> json) => AiUserProfile(
    displayName: json['displayName'] as String? ?? '',
    username: json['username'] as String? ?? '',
    writeGoodEnglish: json['writeGoodEnglish'] as bool? ?? true,
    personality: json['personality'] as String? ?? 'balanced',
    preferredTopics: (json['preferredTopics'] as List<dynamic>?)
        ?.map((e) => e as String)
        .toList() ??
        <String>[],
    avoidTopics: (json['avoidTopics'] as List<dynamic>?)
        ?.map((e) => e as String)
        .toList() ??
        <String>[],
    favoritePhrases: (json['favoritePhrases'] as List<dynamic>?)
        ?.map((e) => e as String)
        .toList() ??
        <String>[],
  );
}