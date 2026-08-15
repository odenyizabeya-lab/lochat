import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:lotext/app.dart';
import 'package:lotext/core/auth/auth_controller.dart';
import 'package:lotext/core/auth/auth_user.dart';
import 'package:lotext/core/router/app_routes.dart';
import 'package:lotext/features/ai/ai_assistant_controller.dart';
import 'package:lotext/features/calls/call_controller.dart';
import 'package:lotext/features/chat/chat_controller.dart';
import 'package:lotext/features/profile/models/user_profile.dart';
import 'package:lotext/features/profile/profile_controller.dart';
import 'package:lotext/features/status/status_controller.dart';
import 'package:lotext/shared/widgets/lotext_button.dart';

import 'fakes.dart';

/// Builds a fully wired test app with fake auth, profile, chat, calls and AI
/// services.
///
/// All widget tests render at a realistic Android phone size (412x892 logical
/// pixels) so overflow/layout bugs that only show up on phones are caught.
Future<(AuthController, ProfileController, FakeProfileRepository)> pumpApp(
  WidgetTester tester, {
  FakeAuthService? authService,
  FakeProfileRepository? profileRepository,
  FakeChatRepository? chatRepository,
  FakePhotoPicker? photoPicker,
  FakeAiAssistantService? aiService,
  FakeStatusRepository? statusRepository,
  FakeCallSignalingService? callSignalingService,
  FakeChatAiService? chatAiService,
  FakeVoiceRecorder? voiceRecorder,
}) async {
  final FakeAuthService service = authService ?? FakeAuthService();
  final FakeProfileRepository profileRepo =
      profileRepository ?? FakeProfileRepository();
  final FakeChatRepository chatRepo =
      chatRepository ?? FakeChatRepository(profileRepository: profileRepo);
  final AuthController authController = AuthController(service: service);
  final ProfileController profileController = ProfileController(
    auth: authController,
    repository: profileRepo,
    photoPicker: photoPicker ?? FakePhotoPicker(),
  );
  final ChatController chatController = ChatController(
    auth: authController,
    repository: chatRepo,
    chatAi: chatAiService,
    voiceRecorder: voiceRecorder,
  );
  final CallController callController = CallController(
    signaling: callSignalingService ?? FakeCallSignalingService(),
    rtcFactory: ({required bool isVideo}) => FakeCallRtcController(),
  );
  final AiAssistantController aiController = AiAssistantController(
    auth: authController,
    service: aiService ?? FakeAiAssistantService(),
  );
  final FakeStatusRepository statusRepo =
      statusRepository ?? FakeStatusRepository();
  final StatusController statusController = StatusController(
    auth: authController,
    repository: statusRepo,
    mediaPicker: FakeChatMediaPicker(),
    videoPlaybackFactory: (String url) => FakeVideoPlaybackController(),
  );
  authController.addListener(() {
    statusRepo.viewerUid = authController.currentUser?.uid;
  });
  statusRepo.viewerUid = authController.currentUser?.uid;
  await tester.binding.setSurfaceSize(const Size(412, 892));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    LoTextApp(
      authController: authController,
      profileController: profileController,
      chatController: chatController,
      callController: callController,
      aiController: aiController,
      statusController: statusController,
    ),
  );
  await tester.pumpAndSettle();
  return (authController, profileController, profileRepo);
}

/// Opens the Tools tab (the redesigned hub that hosts Contacts and Profile
/// entries, since the bottom bar is now Chats / Calls / Updates / Tools).
Future<void> openToolsTab(WidgetTester tester) async {
  await tester.tap(find.text('Tools'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('signed-out user sees the welcome screen', (WidgetTester tester) async {
    await pumpApp(tester);

    expect(find.textContaining('Welcome to', findRichText: true), findsOneWidget);
    expect(find.text('Create your account'), findsOneWidget);
  });

  testWidgets('signed-in user with username lands on the main screen',
      (WidgetTester tester) async {
    final FakeProfileRepository repo = FakeProfileRepository()
      ..seed(const UserProfile(
        uid: 'test-uid',
        username: 'ada',
        displayName: 'Ada',
        isOnline: true,
      ));
    await pumpApp(
      tester,
      authService: FakeAuthService(
        initialUser: const AuthUser(uid: 'test-uid', email: 'ada@lotext.app'),
      ),
      profileRepository: repo,
    );

    expect(find.text('LoText'), findsOneWidget);
    expect(find.text('Chats'), findsWidgets);
  });

  testWidgets('signing in from the login screen opens the main screen',
      (WidgetTester tester) async {
    final FakeProfileRepository repo = FakeProfileRepository()
      ..seed(const UserProfile(
        uid: 'test-uid',
        username: 'ada',
        displayName: 'Ada',
      ));
    await pumpApp(tester, profileRepository: repo);

    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(0), 'ada@lotext.app');
    await tester.enterText(find.byType(TextFormField).at(1), 'secret123');
    await tester.tap(find.widgetWithText(LoTextButton, 'Log in'));
    await tester.pumpAndSettle();

    expect(find.text('LoText'), findsOneWidget);
    expect(find.text('Chats'), findsWidgets);
  });

  group('AI assistant gating', () {
    Future<GoRouter> signedInRouter(
      WidgetTester tester, {
      required bool isAdmin,
    }) async {
      final FakeProfileRepository repo = FakeProfileRepository()
        ..seed(UserProfile(
          uid: 'test-uid',
          username: 'ada',
          displayName: 'Ada',
          isAdmin: isAdmin,
        ));
      await pumpApp(
        tester,
        authService: FakeAuthService(
          initialUser: const AuthUser(uid: 'test-uid', email: 'ada@lotext.app'),
        ),
        profileRepository: repo,
      );
      return GoRouter.of(tester.element(find.text('LoText')));
    }

    testWidgets('the AI card is not shown on the chats screen',
        (WidgetTester tester) async {
      await signedInRouter(tester, isAdmin: true);
      expect(find.text('LoText AI'), findsNothing);
    });

    testWidgets('a non-admin cannot open the AI assistant',
        (WidgetTester tester) async {
      final GoRouter router = await signedInRouter(tester, isAdmin: false);

      router.push(AppRoutes.ai);
      await tester.pumpAndSettle();
      expect(find.text('LoText AI'), findsNothing);
      expect(find.text('LoText'), findsOneWidget);

      router.push(AppRoutes.adminSettings);
      await tester.pumpAndSettle();
      expect(find.text('Only admins can manage provider keys.'), findsNothing);
      expect(find.text('LoText'), findsOneWidget);
    });

    testWidgets('an admin can open the AI assistant',
        (WidgetTester tester) async {
      final GoRouter router = await signedInRouter(tester, isAdmin: true);

      router.push(AppRoutes.ai);
      await tester.pumpAndSettle();
      expect(find.text('LoText AI'), findsWidgets);
    });
  });
}
