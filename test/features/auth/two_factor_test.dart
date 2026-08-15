import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lotext/features/profile/models/user_profile.dart';

import '../../fakes.dart';
import '../../widget_test.dart' show pumpApp;

/// Signs the admin in with the password and waits for the two-factor screen.
Future<FakeAuthService> _loginAsAdmin(
  WidgetTester tester, {
  required FakeAuthService authService,
}) async {
  final FakeProfileRepository profileRepo = FakeProfileRepository()
    ..seed(const UserProfile(
      uid: 'test-uid',
      username: 'admin',
      displayName: 'Admin',
    ));
  await pumpApp(tester, authService: authService, profileRepository: profileRepo);

  await tester.tap(find.text('Admin login'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextFormField).last, 's3cret-admin');
  await tester.tap(find.text('Log in'));
  await tester.pumpAndSettle();
  return authService;
}

void main() {
  testWidgets('admin is held on the two-factor screen after the password step',
      (WidgetTester tester) async {
    await _loginAsAdmin(tester, authService: FakeAuthService());

    expect(find.text('Two-factor verification'), findsOneWidget);
    expect(find.text('Admin dashboard'), findsNothing);
    expect(find.text('Send code'), findsOneWidget);
  });

  testWidgets('email code method completes 2FA and reaches the dashboard',
      (WidgetTester tester) async {
    final FakeAuthService authService = await _loginAsAdmin(
      tester,
      authService: FakeAuthService(),
    );

    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();
    expect(authService.emailCodeSentCount, 1);
    expect(find.textContaining('code has been sent'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).last, '123456');
    await tester.tap(find.text('Verify & continue'));
    await tester.pumpAndSettle();

    expect(find.text('Admin dashboard'), findsOneWidget);
    expect(find.text('Two-factor verification'), findsNothing);
  });

  testWidgets('an incorrect email code keeps the admin on the 2FA screen',
      (WidgetTester tester) async {
    await _loginAsAdmin(tester, authService: FakeAuthService());

    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).last, '000000');
    await tester.tap(find.text('Verify & continue'));
    await tester.pumpAndSettle();

    expect(find.text('Two-factor verification'), findsOneWidget);
    expect(find.text('Admin dashboard'), findsNothing);
  });

  testWidgets('authenticator method verifies a TOTP code',
      (WidgetTester tester) async {
    await _loginAsAdmin(
      tester,
      authService: FakeAuthService()..totpEnabled = true,
    );

    await tester.tap(find.text('Authenticator'));
    await tester.pumpAndSettle();

    expect(find.text('Authenticator code'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).last, '123456');
    await tester.tap(find.text('Verify & continue'));
    await tester.pumpAndSettle();

    expect(find.text('Admin dashboard'), findsOneWidget);
  });

  testWidgets('authenticator setup enrolls a factor and completes 2FA',
      (WidgetTester tester) async {
    final FakeAuthService authService = await _loginAsAdmin(
      tester,
      authService: FakeAuthService(),
    );
    expect(authService.totpEnabled, isFalse);

    await tester.tap(find.text('Authenticator'));
    await tester.pumpAndSettle();
    expect(find.text('Set up authenticator app'), findsOneWidget);

    await tester.tap(find.text('Set up authenticator app'));
    await tester.pumpAndSettle();

    // The enrolled secret is shown for the authenticator app.
    expect(find.text('Copy secret'), findsOneWidget);
    expect(authService.totpEnabled, isTrue);

    await tester.enterText(find.byType(TextFormField).last, '123456');
    await tester.tap(find.text('Activate'));
    await tester.pumpAndSettle();

    expect(find.text('Admin dashboard'), findsOneWidget);
  });

  testWidgets('signing out from the 2FA screen returns to the welcome screen',
      (WidgetTester tester) async {
    await _loginAsAdmin(tester, authService: FakeAuthService());

    await tester.tap(find.text('Sign out instead'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Welcome to', findRichText: true), findsOneWidget);
    expect(find.text('Two-factor verification'), findsNothing);
  });
}
