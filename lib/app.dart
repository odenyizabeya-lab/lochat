import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/auth/auth_controller.dart';
import 'core/auth/auth_scope.dart';
import 'core/constants/app_constants.dart';
import 'core/router/app_router.dart';
import 'core/router/app_routes.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'features/ai/ai_assistant_controller.dart';
import 'features/ai/ai_scope.dart';
import 'features/ai/supabase_ai_assistant_service.dart';
import 'features/calls/call_controller.dart';
import 'features/calls/call_scope.dart';
import 'features/calls/incoming_call_watcher.dart';
import 'features/calls/rtc/device_call_rtc_controller.dart';
import 'features/calls/signaling/supabase_call_signaling_service.dart';
import 'features/chat/chat_controller.dart';
import 'features/chat/chat_scope.dart';
import 'features/chat/data/chat_repository.dart';
import 'features/chat/data/supabase_chat_repository.dart';
import 'features/chat/media/device_chat_media_picker.dart';
import 'features/chat/media/device_voice_recorder.dart';
import 'features/chat/media/media_playback.dart';
import 'features/chat/media/video_playback.dart';
import 'features/chat/notifications_service.dart';
import 'features/profile/data/supabase_profile_repository.dart';
import 'features/profile/data/photo_picker.dart';
import 'features/profile/presence_observer.dart';
import 'features/profile/profile_controller.dart';
import 'features/profile/profile_scope.dart';

/// Root widget of the LoText application.
///
/// Owns the theme, authentication, profile, chat, calls and AI controllers,
/// exposes them to the rest of the tree through [AuthScope], [ProfileScope],
/// [ChatScope], [CallScope] and [AiScope], records online/offline presence
/// through [PresenceObserver], and wires push notifications to open the
/// matching conversation.
class LoTextApp extends StatefulWidget {
  const LoTextApp({
    super.key,
    this.authController,
    this.profileController,
    this.chatController,
    this.callController,
    this.aiController,
    this.notificationsService,
    this.demoMode = false,
  });

  /// Optional injected controllers (used by tests). When null, the app creates
  /// its own controllers backed by Supabase.
  final AuthController? authController;
  final ProfileController? profileController;
  final ChatController? chatController;
  final CallController? callController;
  final AiAssistantController? aiController;
  final NotificationsService? notificationsService;

  /// Runs the UI against injected in-memory services instead of Supabase:
  /// disables push notifications so no notification plugin is ever instantiated.
  final bool demoMode;

  @override
  State<LoTextApp> createState() => _LoTextAppState();
}

/// True under `flutter test`, so the real notification plugins are never
/// instantiated in widget tests. `flutter test` sets this as a runtime
/// environment variable rather than a compile-time define.
final bool _isTestEnvironment =
    !kIsWeb && Platform.environment['FLUTTER_TEST'] == 'true';

class _LoTextAppState extends State<LoTextApp> {
  late final ThemeController _themeController;
  late final AuthController _authController;
  late final ProfileController _profileController;
  late final ChatController _chatController;
  late final CallController _callController;
  late final AiAssistantController _aiController;
  NotificationsService? _notificationsService;
  IncomingCallWatcher? _incomingCallWatcher;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _themeController = ThemeController();
    _authController = widget.authController ?? AuthController();

    final ChatRepository chatRepository = widget.chatController?.repository ??
        SupabaseChatRepository();
    _chatController = widget.chatController ??
        ChatController(
          auth: _authController,
          repository: chatRepository,
          mediaPicker: DeviceChatMediaPicker(),
          voiceRecorder: DeviceVoiceRecorder(),
          voicePlayerFactory: DeviceVoicePlayer.new,
          videoPlaybackFactory: (String url) =>
              DeviceVideoPlaybackController(url: url),
        );

    _profileController = widget.profileController ??
        ProfileController(
          auth: _authController,
          repository: SupabaseProfileRepository(),
          photoPicker: const DevicePhotoPicker(),
        );

    _callController = widget.callController ??
        CallController(
          signaling: SupabaseCallSignalingService(),
          rtcFactory: ({required bool isVideo}) =>
              DeviceCallRtcController(isVideo: isVideo),
        );

    _aiController = widget.aiController ??
        AiAssistantController(
          auth: _authController,
          service: SupabaseAiAssistantService(),
        );

    if (widget.notificationsService != null) {
      _notificationsService = widget.notificationsService;
    } else if (!_isTestEnvironment && !widget.demoMode) {
      _notificationsService =
          NotificationsService(auth: _authController, chat: _chatController);
    }

    _router = createRouter(
      themeController: _themeController,
      authController: _authController,
      profileController: _profileController,
    );

    if (!_isTestEnvironment && !widget.demoMode) {
      _incomingCallWatcher = IncomingCallWatcher(
        auth: _authController,
        calls: _callController,
        router: _router,
      );
    }

    if (_notificationsService != null) {
      unawaited(_notificationsService!.init(
        onOpenConversation: (String conversationId) {
          _router.push(AppRoutes.chatFor(conversationId));
        },
      ));
    }
  }

  @override
  void dispose() {
    _router.dispose();
    _themeController.dispose();
    if (widget.notificationsService == null) {
      _notificationsService?.dispose();
    }
    _incomingCallWatcher?.dispose();
    if (widget.authController == null) {
      _authController.dispose();
    }
    if (widget.profileController == null) {
      _profileController.dispose();
    }
    if (widget.chatController == null) {
      _chatController.dispose();
    }
    if (widget.callController == null) {
      _callController.dispose();
    }
    if (widget.aiController == null) {
      _aiController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _themeController,
      builder: (BuildContext context, Widget? _) {
        return AuthScope(
          controller: _authController,
          child: ProfileScope(
            controller: _profileController,
            child: ChatScope(
              controller: _chatController,
              child: CallScope(
                controller: _callController,
                child: AiScope(
                  controller: _aiController,
                  child: PresenceObserver(
                    child: MaterialApp.router(
                      title: AppConstants.appName,
                      debugShowCheckedModeBanner: false,
                      theme: AppTheme.light,
                      darkTheme: AppTheme.dark,
                      themeMode: _themeController.mode,
                      routerConfig: _router,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
