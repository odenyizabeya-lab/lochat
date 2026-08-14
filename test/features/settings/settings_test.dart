import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lotext/core/auth/auth_controller.dart';
import 'package:lotext/core/auth/auth_scope.dart';
import 'package:lotext/core/auth/auth_user.dart';
import 'package:lotext/core/theme/theme_controller.dart';
import 'package:lotext/features/settings/settings_screen.dart';

import '../../fakes.dart';

void main() {
  Widget buildApp(FakeAuthService service) {
    return MaterialApp(
      home: AuthScope(
        controller: AuthController(service: service),
        child: SettingsScreen(themeController: ThemeController()),
      ),
    );
  }

  Future<void> confirmDeletion(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Delete account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
    expect(find.text('Delete account?'), findsOneWidget);

    // The confirm button stays disabled until DELETE is typed.
    final Finder deleteButton = find.widgetWithText(FilledButton, 'Delete');
    await tester.tap(deleteButton);
    await tester.pump();
    expect(find.text('Delete account?'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'DELETE');
    await tester.pump();
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();
  }

  testWidgets('delete account requires typing DELETE and signs the user out', (
    WidgetTester tester,
  ) async {
    final FakeAuthService service = FakeAuthService(
      initialUser: const AuthUser(uid: 'test-uid', email: 'ada@lotext.app'),
    );
    await tester.pumpWidget(buildApp(service));
    await tester.pumpAndSettle();

    await confirmDeletion(tester);

    expect(service.deleteAccountCalls, 1);
    expect(service.currentUser, isNull);
    expect(find.text('Delete account?'), findsNothing);
  });

  testWidgets('a failed deletion keeps the user signed in and shows an error', (
    WidgetTester tester,
  ) async {
    final ThrowingDeleteAuthService service = ThrowingDeleteAuthService(
      initialUser: const AuthUser(uid: 'test-uid', email: 'ada@lotext.app'),
    );
    await tester.pumpWidget(buildApp(service));
    await tester.pumpAndSettle();

    await confirmDeletion(tester);

    expect(service.currentUser, isNotNull);
    expect(
      find.text('We could not delete your account. Please try again.'),
      findsOneWidget,
    );
  });
}

/// A [FakeAuthService] whose deleteAccount always fails.
class ThrowingDeleteAuthService extends FakeAuthService {
  ThrowingDeleteAuthService({super.initialUser});

  @override
  Future<void> deleteAccount() async {
    throw Exception('boom');
  }
}
