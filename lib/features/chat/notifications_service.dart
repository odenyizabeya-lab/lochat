import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;

import '../../core/auth/auth_controller.dart';
import 'chat_controller.dart';

/// Bridges Supabase Realtime and local notifications for private chats.
///
/// Responsibilities:
/// - requests notification permission (iOS + Android 13+),
/// - subscribes to the `messages` Realtime stream for the signed-in user
///   (RLS only delivers events for conversations the user belongs to),
/// - shows a local notification for incoming messages,
/// - forwards notification taps to open the matching conversation.
///
/// Push (FCM) is intentionally not used; Realtime delivers messages to the
/// live app and local notifications surface them.
class NotificationsService {
  NotificationsService({
    required this._auth,
    required this._chat,
    SupabaseClient? client,
    FlutterLocalNotificationsPlugin? localNotifications,
  })  : _client = client ?? Supabase.instance.client,
        _local = localNotifications ?? FlutterLocalNotificationsPlugin() {
    _auth.addListener(_handleAuthChange);
    _handleAuthChange();
  }

  final AuthController _auth;
  final ChatController _chat;
  final SupabaseClient _client;
  final FlutterLocalNotificationsPlugin _local;

  /// Single slot for chat notifications; a new message replaces the old one.
  static const int _chatNotificationId = 1001;

  RealtimeChannel? _channel;
  bool _initialized = false;

  /// Cached display names so every incoming message does not re-query.
  final Map<String, String> _profileNames = <String, String>{};

  /// Sets up the plugin, requests permission, and subscribes to incoming
  /// messages. [onOpenConversation] is called whenever the user taps a chat
  /// notification.
  Future<void> init({
    void Function(String conversationId)? onOpenConversation,
  }) async {
    const InitializationSettings settings = InitializationSettings(
      android: AndroidInitializationSettings('ic_notification'),
      iOS: DarwinInitializationSettings(),
      macOS: DarwinInitializationSettings(),
    );
    await _local.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        final String? conversationId = response.payload;
        if (conversationId != null && conversationId.isNotEmpty) {
          onOpenConversation?.call(conversationId);
        }
      },
    );

    await _requestPermissions();
    _initialized = true;
    _subscribeToMessages();
  }

  Future<void> _requestPermissions() async {
    try {
      final AndroidFlutterLocalNotificationsPlugin? android = _local
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
      final IOSFlutterLocalNotificationsPlugin? ios = _local
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>();
      await ios?.requestPermissions(alert: true, badge: true, sound: true);
    } on Exception {
      // Permission denied or platform unavailable; the app still works, the
      // user just won't see notifications.
    }
  }

  void _subscribeToMessages() {
    if (!_initialized) return;
    final String? uid = _chat.uid;
    if (_channel != null) {
      unawaited(_channel!.unsubscribe());
      _channel = null;
    }
    if (uid == null) return;

    _channel = _client
        .channel('lotext_notifications_$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (PostgresChangePayload payload) {
            unawaited(_handleIncomingMessage(uid, payload.newRecord));
          },
        )
        .subscribe();
  }

  Future<void> _handleIncomingMessage(
    String myUid,
    Map<String, dynamic> record,
  ) async {
    final String? senderUid = record['sender_uid'] as String?;
    if (senderUid == null || senderUid == myUid) return;
    final String conversationId = record['conversation_id'] as String? ?? '';
    if (conversationId.isEmpty) return;

    final String title = await _senderName(senderUid);
    unawaited(_show(
      conversationId: conversationId,
      title: title,
      body: _bodyFor(record),
    ));
  }

  Future<String> _senderName(String uid) async {
    final String? cached = _profileNames[uid];
    if (cached != null) return cached;
    String name = '';
    try {
      final rows = await _client
          .from('profiles')
          .select('display_name')
          .eq('uid', uid)
          .limit(1);
      name = rows.isNotEmpty ? (rows.first['display_name'] as String?) ?? '' : '';
    } on Exception {
      name = '';
    }
    final String result = name.isEmpty ? 'New message' : name;
    _profileNames[uid] = result;
    return result;
  }

  String _bodyFor(Map<String, dynamic> record) {
    final String type = record['type'] as String? ?? 'text';
    return switch (type) {
      'text' => (record['text'] as String?) ?? '',
      'image' => 'Photo',
      'video' => 'Video',
      'voice' => 'Voice message',
      _ => 'Message',
    };
  }

  Future<void> _show({
    required String conversationId,
    required String title,
    required String body,
  }) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'chats',
      'Chat messages',
      channelDescription: 'Notifications for new private messages.',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.message,
    );
    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const NotificationDetails details =
        NotificationDetails(android: androidDetails, iOS: iosDetails);
    await _local.show(
      id: _chatNotificationId,
      title: title,
      body: body,
      notificationDetails: details,
      payload: conversationId,
    );
  }

  void _handleAuthChange() {
    // Re-subscribe when the signed-in user changes or signs out.
    _subscribeToMessages();
  }

  void dispose() {
    _auth.removeListener(_handleAuthChange);
    unawaited(_channel?.unsubscribe());
  }
}
