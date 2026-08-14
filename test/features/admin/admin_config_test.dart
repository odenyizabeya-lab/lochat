import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lotext/core/auth/auth_controller.dart';
import 'package:lotext/core/auth/auth_user.dart';
import 'package:lotext/features/admin/admin_settings_screen.dart';
import 'package:lotext/features/profile/models/user_profile.dart';
import 'package:lotext/features/profile/profile_controller.dart';
import 'package:lotext/features/profile/profile_scope.dart';

import '../../fakes.dart';
import '../../widget_test.dart' show pumpApp, openToolsTab;

void main() {
  group('Settings screen admin section', () {
    testWidgets('is hidden for a non-admin user when an admin exists',
        (WidgetTester tester) async {
      final FakeProfileRepository repo = FakeProfileRepository()
        ..seed(const UserProfile(
          uid: 'owner-uid',
          username: 'owner',
          displayName: 'Owner',
          isAdmin: true,
        ))
        ..seed(const UserProfile(
          uid: 'test-uid',
          username: 'ada',
          displayName: 'Ada',
        ));
      await _openSettings(tester, repo);

      expect(find.text('Admin dashboard'), findsNothing);
    });

    testWidgets('is visible to an admin user', (WidgetTester tester) async {
      final FakeProfileRepository repo = FakeProfileRepository()
        ..seed(const UserProfile(
          uid: 'test-uid',
          username: 'ada',
          displayName: 'Ada',
          isAdmin: true,
        ));
      await _openSettings(tester, repo);

      await tester.scrollUntilVisible(find.text('Admin dashboard'), 120);
      await tester.pumpAndSettle();
      expect(find.text('Admin dashboard'), findsOneWidget);
      expect(find.text('Manage AI provider keys'), findsOneWidget);
    });

    testWidgets('first user to open settings is auto-promoted to admin',
        (WidgetTester tester) async {
      final FakeProfileRepository repo = FakeProfileRepository()
        ..seed(const UserProfile(
          uid: 'test-uid',
          username: 'ada',
          displayName: 'Ada',
        ));
      await _openSettings(tester, repo);
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Admin dashboard'), 120);
      await tester.pumpAndSettle();
      expect(find.text('Admin dashboard'), findsOneWidget);
      expect(find.text('Manage AI provider keys'), findsOneWidget);
      expect(repo.profiles['test-uid']?.isAdmin, isTrue);
    });
  });

  group('AdminSettingsScreen', () {
    testWidgets('shows a restricted notice to non-admins',
        (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: AdminSettingsScreen(
          repository: FakeAppConfigRepository(admin: false),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Only admins can manage provider keys.'), findsOneWidget);
      expect(find.text('OpenAI'), findsNothing);
    });

    testWidgets('a non-admin reaching the dashboard directly claims owner admin',
        (WidgetTester tester) async {
      final FakeProfileRepository profileRepo = FakeProfileRepository()
        ..seed(const UserProfile(
          uid: 'test-uid',
          username: 'ada',
          displayName: 'Ada',
        ));
      final AuthController auth = AuthController(
        service: FakeAuthService(
          initialUser:
              const AuthUser(uid: 'test-uid', email: 'ada@lotext.app'),
        ),
      );
      final ProfileController profileController = ProfileController(
        auth: auth,
        repository: profileRepo,
      );
      addTearDown(profileController.dispose);
      addTearDown(auth.dispose);
      await tester.binding.setSurfaceSize(const Size(412, 892));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(MaterialApp(
        home: ProfileScope(
          controller: profileController,
          child: AdminSettingsScreen(
            repository: FakeAppConfigRepository(profileRepository: profileRepo),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(profileRepo.profiles['test-uid']?.isAdmin, isTrue);
      expect(find.text('OpenAI'), findsOneWidget);
      expect(find.text('Only admins can manage provider keys.'), findsNothing);
    });

    testWidgets('lists known providers and their status',
        (WidgetTester tester) async {
      final FakeAppConfigRepository repo = FakeAppConfigRepository()
        ..values['OPENAI_API_KEY'] = 'sk-abcdef1234567890';
      await _pumpAdminScreen(tester, repo);

      expect(find.text('OpenAI'), findsOneWidget);
      expect(find.text('Anthropic'), findsOneWidget);
      expect(find.text('Google Gemini'), findsOneWidget);
      expect(find.text('sk-a\u2022\u2022\u2022\u20227890'), findsOneWidget);
      expect(find.text('Not set'), findsNWidgets(2));
      expect(find.text('AI assistant'), findsOneWidget);
    });

    testWidgets('saves a key entered in the editor dialog',
        (WidgetTester tester) async {
      final FakeAppConfigRepository repo = FakeAppConfigRepository();
      await _pumpAdminScreen(tester, repo);

      await tester.tap(find.text('Google Gemini'));
      await tester.pumpAndSettle();
      expect(find.text('Google Gemini key'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'AIzaSy-test-key-000');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(repo.values['GEMINI_API_KEY'], 'AIzaSy-test-key-000');
      expect(find.text('Google Gemini key saved.'), findsOneWidget);
    });

    testWidgets('removes a key after confirmation', (WidgetTester tester) async {
      final FakeAppConfigRepository repo = FakeAppConfigRepository()
        ..values['ANTHROPIC_API_KEY'] = 'sk-ant-test-value-1234';
      await _pumpAdminScreen(tester, repo);
      expect(find.text('Not set'), findsNWidgets(2));

      final Finder anthropicRow =
          find.widgetWithText(ListTile, 'Anthropic');
      await tester.tap(find.descendant(
        of: anthropicRow,
        matching: find.byTooltip('Remove the key'),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Remove Anthropic key?'), findsOneWidget);

      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      expect(repo.values.containsKey('ANTHROPIC_API_KEY'), isFalse);
      expect(find.text('Not set'), findsNWidgets(3));
    });

    testWidgets('shows an error state with retry', (WidgetTester tester) async {
      final FakeAppConfigRepository repo =
          FakeAppConfigRepository()..failRequests = true;
      await _pumpAdminScreen(tester, repo);

      expect(
        find.text('Could not load the admin configuration.'),
        findsOneWidget,
      );

      repo.failRequests = false;
      repo.values['OPENAI_API_KEY'] = 'sk-abcdef1234567890';
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('OpenAI'), findsOneWidget);
    });
  });
}

Future<void> _openSettings(
  WidgetTester tester,
  FakeProfileRepository repo,
) async {
  await pumpApp(
    tester,
    authService: FakeAuthService(
      initialUser: const AuthUser(uid: 'test-uid', email: 'ada@lotext.app'),
    ),
    profileRepository: repo,
  );
  await openToolsTab(tester);
  await tester.tap(find.text('Profile'));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(find.text('Settings'), 120);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Settings'));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(find.text('Version'), 120);
  await tester.pumpAndSettle();
}

Future<void> _pumpAdminScreen(
  WidgetTester tester,
  FakeAppConfigRepository repo,
) async {
  await tester.binding.setSurfaceSize(const Size(412, 892));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(home: AdminSettingsScreen(repository: repo)),
  );
  await tester.pumpAndSettle();
}
