import '../../profile/models/user_profile.dart';

/// A private 1-to-1 conversation between the signed-in user and one peer.
///
/// This is a derived view of a `conversations/{id}` document plus the peer's
/// live profile, so display names and presence stay current without a second
/// lookup in the UI.
class Conversation {
  const Conversation({
    required this.id,
    required this.peer,
    this.lastMessageText = '',
    this.lastMessageAt,
    this.lastSenderUid = '',
    this.lastSenderName = '',
    this.unreadCount = 0,
    this.typingUid,
    this.typingUntil,
  });

  /// Deterministic conversation ID (`<uidA>_<uidB>`, uids sorted), so the
  /// same pair of people always maps to the same conversation.
  final String id;

  /// The other participant's live public profile.
  final UserProfile peer;

  /// Denormalized text of the newest message (empty when none yet).
  final String lastMessageText;

  final DateTime? lastMessageAt;

  /// UID of whoever wrote the last message.
  final String lastSenderUid;

  /// Display name of the last sender at the time the message was written.
  final String lastSenderName;

  /// Unread count resolved for the signed-in viewer.
  final int unreadCount;

  /// UID of whichever participant is currently typing, if any.
  final String? typingUid;

  /// When the typing stamp expires. The indicator is shown until this instant.
  final DateTime? typingUntil;

  bool get hasLastMessage => lastMessageText.isNotEmpty;

  /// Whether [uid] wrote the last message (used for the "You:" prefix).
  bool lastSentBy(String uid) => lastSenderUid.isNotEmpty && lastSenderUid == uid;

  /// Whether the peer (any participant other than [viewerUid]) is currently
  /// typing. Own typing signals are ignored so a self-sent write can never
  /// surface "typing..." back to the typist.
  bool isTypingFrom(String viewerUid) {
    final String? typingUid = this.typingUid;
    final DateTime? typingUntil = this.typingUntil;
    if (typingUid == null ||
        typingUntil == null ||
        typingUid == viewerUid) {
      return false;
    }
    return typingUntil.isAfter(DateTime.now());
  }
}
