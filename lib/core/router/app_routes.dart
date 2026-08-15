/// Central route paths for the app.
abstract final class AppRoutes {
  static const String splash = '/';
  static const String welcome = '/welcome';
  static const String login = '/login';
  static const String adminLogin = '/admin-login';
  static const String register = '/register';
  static const String forgotPassword = '/forgot-password';

  /// The second verification step after the admin's password (email code or
  /// authenticator app). Signed-in only; the router keeps the admin here while
  /// [AuthController.twoFactorPending] is true.
  static const String twoFactor = '/two-factor';

  static const String home = '/home';
  static const String chats = '/chats';
  static const String calls = '/calls';
  static const String updates = '/updates';
  static const String tools = '/tools';
  static const String profile = '/profile';
  static const String settings = '/settings';

  /// Admin dashboard for AI provider keys (admins only).
  static const String adminSettings = '/settings/admin';

  /// Admin chat room: the admin's 1-to-1 conversations (admins only).
  static const String adminChatRoom = '/settings/admin/chat-room';

  /// Admin managed accounts (admins only).
  static const String adminAccounts = '/settings/admin/accounts';

  /// Individual managed account chat (admins only).
  static const String adminChat = '/settings/admin/chat';

  // Contacts.
  static const String contacts = '/contacts';
  static const String addContact = '/add-contact';

  // Profile / username setup.
  static const String chooseUsername = '/choose-username';
  static const String editProfile = '/edit-profile';
  static const String publicProfile = '/profile/:uid';

  static String publicProfileFor(String uid) => '/profile/$uid';

  // Chat.
  static const String chat = '/chat/:conversationId';

  static String chatFor(String conversationId) => '/chat/$conversationId';

  /// Archived conversations (empty until the archive feature exists; never
  /// shows fake data).
  static const String chatsArchived = '/chats/archived';

  /// LoText AI assistant.
  static const String ai = '/ai';

  /// Voice/video call history.
  static const String callHistory = '/calls/history';

  /// Status composer (Updates tab). Full screen over the shell.
  static const String statusComposer = '/updates/compose';

  /// Status viewer. `extra` must be a map with 'group' (StatusGroup) and
  /// 'isOwn' (bool).
  static const String statusViewer = '/updates/viewer';

  /// Full-screen photo viewer. `extra` must be a map with 'url' (String) and
  /// optional 'id' (String).
  static const String photoViewer = '/chat/photo-viewer';

  /// Full-screen video player. `extra` must be a map with 'url' (String) and
  /// optional 'messageId' (String).
  static const String videoPlayer = '/chat/video-player';

  /// Full-screen incoming call. `extra` carries 'conversationId' (String).
  static const String incomingCall = '/calls/incoming/:callId';

  /// Active call screen. `extra` carries 'session' (CallSessionController).
  static const String activeCall = '/calls/active';
}
