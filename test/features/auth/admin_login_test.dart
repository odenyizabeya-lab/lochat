import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lotext/core/constants/app_constants.dart';
import 'package:lotext/features/profile/models/user_profile.dart';

import '../../widget_test.dart' show pumpApp;
import '../../fakes.dart';

/// Finds a [TextField] whose label matches [label].
Finder _fieldWithLabel(String label) => find.byWidgetPredicate(
      (Widget widget) =>
          widget is TextField && widget.decoration?.labelText == label,
    );

void main() {
  testWidgets('welcome screen offers an entry to the admin login',
      (WidgetTester tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Admin login'));
    await tester.pumpAndSettle();

    expect(find.text('Admin login'), findsNWidgets(2)); // AppBar + heading
    expect(find.text('Log in'), findsOneWidget);
  });

  testWidgets('admin email field is read-only and prefilled',
      (WidgetTester tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Admin login'));
    await tester.pumpAndSettle();

    final TextField emailField = tester.widget<TextField>(
      _fieldWithLabel('Admin email'),
    );
    expect(emailField.readOnly, isTrue);
    expect(emailField.controller?.text, AppConstants.adminEmail);
  });

  testWidgets('signing in with the admin email opens the admin dashboard',
      (WidgetTester tester) async {
    final FakeProfileRepository profileRepo = FakeProfileRepository()
      ..seed(const UserProfile(
        uid: 'test-uid',
        username: 'admin',
        displayName: 'Admin',
      ));
    final FakeAuthService authService = FakeAuthService();
    await pumpApp(tester, authService: authService, profileRepository: profileRepo);

    await tester.tap(find.text('Admin login'));
    await tester.pumpAndSettle();

    final Finder passwordField = find.byType(TextFormField).last;
    await tester.enterText(passwordField, 's3cret-admin');
    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();

    // The password step succeeds, but the admin must complete the 2FA step
    // before reaching the dashboard.
    expect(authService.currentUser?.email, AppConstants.adminEmail);
    expect(find.text('Two-factor verification'), findsOneWidget);

    await _completeTwoFactor(tester);

    expect(find.text('Admin dashboard'), findsOneWidget);
    expect(find.text('Change password'), findsOneWidget);
    expect(find.text('Change admin email'), findsOneWidget);
  });

  testWidgets('admin can change their password from the dashboard',
      (WidgetTester tester) async {
    final FakeProfileRepository profileRepo = FakeProfileRepository()
      ..seed(const UserProfile(
        uid: 'test-uid',
        username: 'admin',
        displayName: 'Admin',
      ));
    final FakeAuthService authService = FakeAuthService();
    await pumpApp(tester, authService: authService, profileRepository: profileRepo);
    await _openDashboard(tester);

    await tester.tap(find.text('Change password'));
    await tester.pumpAndSettle();
    expect(find.text('Change password'), findsNWidgets(2)); // tile + dialog title

    await tester.enterText(
      _fieldWithLabel('New password'),
      'new-admin-pass',
    );
    await tester.enterText(
      _fieldWithLabel('Confirm new password'),
      'new-admin-pass',
    );
    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();

    expect(authService.updatedPassword, 'new-admin-pass');
    expect(find.text('Password updated.'), findsOneWidget);
  });

  testWidgets('admin can change their email from the dashboard',
      (WidgetTester tester) async {
    final FakeProfileRepository profileRepo = FakeProfileRepository()
      ..seed(const UserProfile(
        uid: 'test-uid',
        username: 'admin',
        displayName: 'Admin',
      ));
    final FakeAuthService authService = FakeAuthService();
    await pumpApp(tester, authService: authService, profileRepository: profileRepo);
    await _openDashboard(tester);

    await tester.tap(find.text('Change admin email'));
    await tester.pumpAndSettle();

    await tester.enterText(
      _fieldWithLabel('New admin email'),
      'newadmin@lotext.app',
    );
    await tester.tap(find.text('Send link'));
    await tester.pumpAndSettle();

    expect(authService.updatedEmail, 'newadmin@lotext.app');
    expect(
      find.text('Confirmation email sent to newadmin@lotext.app.'),
      findsOneWidget,
    );
  });
}

/// Signs the admin in via the admin-login screen and waits for the dashboard.
Future<void> _openDashboard(WidgetTester tester) async {
  await tester.tap(find.text('Admin login'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextFormField).last, 's3cret-admin');
  await tester.tap(find.text('Log in'));
  await tester.pumpAndSettle();
  await _completeTwoFactor(tester);
}

/// Completes the 2FA step with the fake's default email code.
Future<void> _completeTwoFactor(WidgetTester tester) async {
  await tester.tap(find.text('Send code'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextFormField).last, '123456');
  await tester.tap(find.text('Verify & continue'));
  await tester.pumpAndSettle();
  // Let the "Code sent" info snackbar expire so it does not queue any snackbar
  // shown later in the same test.
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpAndSettle();
}
