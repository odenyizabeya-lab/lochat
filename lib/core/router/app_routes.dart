/// Central route paths for the app.
abstract final class AppRoutes {
  static const String splash = '/';
  static const String welcome = '/welcome';
  static const String login = '/login';
  static const String register = '/register';
  static const String forgotPassword = '/forgot-password';

  static const String home = '/home';
  static const String chats = '/chats';
  static const String profile = '/profile';
  static const String settings = '/settings';

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

  /// LoText AI assistant.
  static const String ai = '/ai';

  /// Voice/video call history.
  static const String callHistory = '/calls/history';

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
