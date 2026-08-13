import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/forgot_password/forgot_password_screen.dart';
import '../../features/auth/login/login_screen.dart';
import '../../features/auth/register/register_screen.dart';
import '../../features/auth/welcome/welcome_screen.dart';
import '../../features/ai/ai_assistant_screen.dart';
import '../../features/admin/admin_chat_room_screen.dart';
import '../../features/admin/admin_settings_screen.dart';
import '../../features/calls/call_session_controller.dart';
import '../../features/calls/models/call.dart';
import '../../features/calls/screens/call_history_screen.dart';
import '../../features/calls/screens/call_screen.dart';
import '../../features/calls/screens/incoming_call_screen.dart';
import '../../features/chat/chat_screen.dart';
import '../../features/chat/photo_viewer_screen.dart';
import '../../features/chat/video_player_screen.dart';
import '../../features/home/chats/chats_screen.dart';
import '../../features/home/contacts/contacts_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/home/main_screen.dart';
import '../../features/home/profile/profile_screen.dart';
import '../../features/profile/profile_controller.dart';
import '../../features/profile/screens/add_contact_screen.dart';
import '../../features/profile/screens/choose_username_screen.dart';
import '../../features/profile/screens/edit_profile_screen.dart';
import '../../features/profile/screens/public_profile_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/splash/splash_screen.dart';
import '../auth/auth_controller.dart';
import '../theme/theme_controller.dart';
import 'app_routes.dart';

/// Routes that only signed-out users may visit.
const List<String> _authOnlyRoutes = <String>[
  AppRoutes.welcome,
  AppRoutes.login,
  AppRoutes.register,
  AppRoutes.forgotPassword,
];

/// Routes that only admins may visit (the AI assistant, the admin dashboard
/// and the admin chat room). Regular users are redirected away by the router.
const List<String> _adminOnlyRoutes = <String>[
  AppRoutes.ai,
  AppRoutes.adminSettings,
  AppRoutes.adminChatRoom,
];

/// Builds the app's [GoRouter].
///
/// Redirect rules, in order:
/// 1. auth state still resolving       -> splash
/// 2. signed out                       -> welcome (auth screens allowed)
/// 3. profile still resolving          -> splash
/// 4. signed in, no username yet       -> choose-username
/// 5. signed in with username          -> main screens; auth/splash -> home
GoRouter createRouter({
  required ThemeController themeController,
  required AuthController authController,
  required ProfileController profileController,
}) {
  return GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: Listenable.merge(<Listenable>[
      authController,
      profileController,
    ]),
    redirect: (BuildContext context, GoRouterState state) {
      final String location = state.matchedLocation;
      final bool signedIn = authController.currentUser != null;

      if (!authController.isInitialized) {
        return location == AppRoutes.splash ? null : AppRoutes.splash;
      }

      if (!signedIn) {
        if (location == AppRoutes.splash) return AppRoutes.welcome;
        return _authOnlyRoutes.contains(location) ? null : AppRoutes.welcome;
      }

      if (!profileController.isInitialized) {
        return location == AppRoutes.splash ? null : AppRoutes.splash;
      }

      if (!profileController.hasUsername) {
        return location == AppRoutes.chooseUsername
            ? null
            : AppRoutes.chooseUsername;
      }

      // The AI assistant and admin dashboard are for admins only.
      if (_adminOnlyRoutes.contains(location) &&
          !(profileController.profile?.isAdmin ?? false)) {
        return AppRoutes.home;
      }

      // Signed in with a username. Keep them out of the signed-out flow.
      if (location == AppRoutes.splash ||
          _authOnlyRoutes.contains(location) ||
          location == AppRoutes.chooseUsername) {
        return AppRoutes.home;
      }
      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.splash,
        name: 'splash',
        builder: (BuildContext context, GoRouterState state) =>
            const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.welcome,
        name: 'welcome',
        builder: (BuildContext context, GoRouterState state) =>
            const WelcomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        name: 'login',
        builder: (BuildContext context, GoRouterState state) =>
            const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.register,
        name: 'register',
        builder: (BuildContext context, GoRouterState state) =>
            const RegisterScreen(),
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        name: 'forgot-password',
        builder: (BuildContext context, GoRouterState state) =>
            const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: AppRoutes.chooseUsername,
        name: 'choose-username',
        builder: (BuildContext context, GoRouterState state) =>
            const ChooseUsernameScreen(),
      ),
      GoRoute(
        path: AppRoutes.editProfile,
        name: 'edit-profile',
        builder: (BuildContext context, GoRouterState state) =>
            const EditProfileScreen(),
      ),
      GoRoute(
        path: AppRoutes.addContact,
        name: 'add-contact',
        builder: (BuildContext context, GoRouterState state) =>
            const AddContactScreen(),
      ),
      GoRoute(
        path: AppRoutes.publicProfile,
        name: 'public-profile',
        builder: (BuildContext context, GoRouterState state) {
          final String? uid = state.pathParameters['uid'];
          return PublicProfileScreen(uid: uid ?? '');
        },
      ),
      GoRoute(
        path: AppRoutes.chat,
        name: 'chat',
        builder: (BuildContext context, GoRouterState state) {
          final String? conversationId = state.pathParameters['conversationId'];
          return ChatScreen(conversationId: conversationId ?? '');
        },
      ),
      GoRoute(
        path: AppRoutes.ai,
        name: 'ai',
        builder: (BuildContext context, GoRouterState state) =>
            const AiAssistantScreen(),
      ),
      GoRoute(
        path: AppRoutes.callHistory,
        name: 'call-history',
        builder: (BuildContext context, GoRouterState state) =>
            const CallHistoryScreen(),
      ),
      GoRoute(
        path: AppRoutes.photoViewer,
        name: 'photo-viewer',
        builder: (BuildContext context, GoRouterState state) {
          final Map<String, dynamic>? extra =
              state.extra is Map<String, dynamic>
                  ? state.extra as Map<String, dynamic>
                  : null;
          return PhotoViewerScreen(
            url: extra?['url'] as String? ?? '',
            messageId: extra?['id'] as String?,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.videoPlayer,
        name: 'video-player',
        builder: (BuildContext context, GoRouterState state) {
          final Map<String, dynamic>? extra =
              state.extra is Map<String, dynamic>
                  ? state.extra as Map<String, dynamic>
                  : null;
          return VideoPlayerScreen(
            url: extra?['url'] as String? ?? '',
            messageId: extra?['messageId'] as String?,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.incomingCall,
        name: 'incoming-call',
        builder: (BuildContext context, GoRouterState state) {
          final String? callId = state.pathParameters['callId'];
          final Map<String, dynamic>? extra =
              state.extra is Map<String, dynamic>
                  ? state.extra as Map<String, dynamic>
                  : null;
          return IncomingCallScreen(
            callId: callId ?? '',
            conversationId: extra?['conversationId'] as String? ?? '',
            isVideo: extra?['isVideo'] as bool? ?? false,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.activeCall,
        name: 'active-call',
        builder: (BuildContext context, GoRouterState state) {
          final Map<String, dynamic>? extra =
              state.extra is Map<String, dynamic>
                  ? state.extra as Map<String, dynamic>
                  : null;
          final session = extra?['session'];
          if (session is! CallSessionController) {
            return const CallNotFoundScreen();
          }
          final Object? startParamsRaw = extra?['startParams'];
          final Map<String, dynamic> startParams =
              startParamsRaw is Map<String, dynamic> ? startParamsRaw : const <String, dynamic>{};
          final Object? typeRaw = startParams['type'];
          return CallScreen(
            session: session,
            startParams: startParams.isEmpty
                ? null
                : OutgoingCallParams(
                    calleeUid: startParams['calleeUid'] as String? ?? '',
                    conversationId:
                        startParams['conversationId'] as String? ?? '',
                    type: typeRaw == 'video' ? CallType.video : CallType.audio,
                  ),
          );
        },
      ),
      StatefulShellRoute.indexedStack(
        builder: (BuildContext context, GoRouterState state,
            StatefulNavigationShell navigationShell) {
          return MainScreen(navigationShell: navigationShell);
        },
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.home,
                name: 'home',
                builder: (BuildContext context, GoRouterState state) =>
                    const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.chats,
                name: 'chats',
                builder: (BuildContext context, GoRouterState state) =>
                    const ChatsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.contacts,
                name: 'contacts',
                builder: (BuildContext context, GoRouterState state) =>
                    const ContactsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.profile,
                name: 'profile',
                builder: (BuildContext context, GoRouterState state) =>
                    const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.settings,
        name: 'settings',
        builder: (BuildContext context, GoRouterState state) =>
            SettingsScreen(themeController: themeController),
      ),
      GoRoute(
        path: AppRoutes.adminSettings,
        name: 'admin-settings',
        builder: (BuildContext context, GoRouterState state) =>
            const AdminSettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.adminChatRoom,
        name: 'admin-chat-room',
        builder: (BuildContext context, GoRouterState state) =>
            const AdminChatRoomScreen(),
      ),
    ],
  );
}
