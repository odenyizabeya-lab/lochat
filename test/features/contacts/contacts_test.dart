import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lotext/core/auth/auth_user.dart';
import 'package:lotext/features/profile/models/user_profile.dart';
import 'package:lotext/shared/widgets/lotext_button.dart';

import '../../fakes.dart';
import '../../widget_test.dart' show pumpApp, openToolsTab;

UserProfile me() => const UserProfile(
      uid: 'me-uid',
      username: 'me',
      displayName: 'Me',
      lotextId: '111111111',
      isOnline: true,
    );

UserProfile sarah() => UserProfile(
      uid: 'them-uid',
      username: 'sarah',
      displayName: 'Sarah Connor',
      lotextId: '284716093',
      isOnline: false,
      lastSeen: DateTime.utc(2026, 1, 1),
    );

void main() {
  Future<FakeProfileRepository> pumpWithContacts(WidgetTester tester) async {
    final FakeProfileRepository repo = FakeProfileRepository()
      ..seed(me())
      ..seed(sarah())
      ..seed(const UserProfile(
        uid: 'kyle-uid',
        username: 'kyle',
        displayName: 'Kyle Reese',
        lotextId: '903182475',
        isOnline: true,
      ));
    repo.contacts['me-uid'] = <String>{'them-uid', 'kyle-uid'};
    await pumpApp(
      tester,
      authService: FakeAuthService(
        initialUser: const AuthUser(uid: 'me-uid', email: 'me@lotext.app'),
      ),
      profileRepository: repo,
    );
    return repo;
  }

  testWidgets('contacts tab shows an empty state with an add action',
      (WidgetTester tester) async {
    final FakeProfileRepository repo = FakeProfileRepository()..seed(me());
    await pumpApp(
      tester,
      authService: FakeAuthService(
        initialUser: const AuthUser(uid: 'me-uid', email: 'me@lotext.app'),
      ),
      profileRepository: repo,
    );

    await openToolsTab(tester);
    await tester.tap(find.text('Contacts'));
    await tester.pumpAndSettle();

    expect(find.text('No contacts yet'), findsOneWidget);
    expect(find.widgetWithText(LoTextButton, 'Add contact'), findsOneWidget);

    await tester.tap(find.widgetWithText(LoTextButton, 'Add contact'));
    await tester.pumpAndSettle();
    expect(find.text('Add contact'), findsWidgets);
  });

  testWidgets('contacts list shows only explicitly added people',
      (WidgetTester tester) async {
    await pumpWithContacts(tester);

    await openToolsTab(tester);
    await tester.tap(find.text('Contacts'));
    await tester.pumpAndSettle();

    // Both added contacts are visible with live handles and presence.
    expect(find.text('Sarah Connor'), findsOneWidget);
    expect(find.text('@sarah'), findsOneWidget);
    expect(find.text('Kyle Reese'), findsOneWidget);
    expect(find.text('@kyle'), findsOneWidget);

    // Emails are never rendered anywhere in the app.
    expect(find.textContaining('@lotext.app'), findsNothing);
  });

  testWidgets('tapping a contact opens their public profile',
      (WidgetTester tester) async {
    await pumpWithContacts(tester);

    await openToolsTab(tester);
    await tester.tap(find.text('Contacts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sarah Connor'));
    await tester.pumpAndSettle();

    expect(find.text('Sarah Connor'), findsOneWidget);
    expect(find.text('LoText ID: 284716093'), findsOneWidget);
    expect(find.text('Message'), findsOneWidget);
    // Already a contact: removing is offered, adding is not.
    expect(find.widgetWithText(LoTextButton, 'Remove contact'), findsOneWidget);
    expect(find.widgetWithText(LoTextButton, 'Add contact'), findsNothing);

    // Message opens the private chat with the contact.
    await tester.tap(find.widgetWithText(LoTextButton, 'Message'));
    await tester.pumpAndSettle();
    expect(find.text('Sarah Connor'), findsOneWidget);
    expect(find.text('Message'), findsOneWidget);
    // Empty input shows the hold-to-record mic; typing swaps it for send.
    expect(find.byIcon(Icons.mic_none_rounded), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Hello');
    await tester.pump();
    expect(find.byIcon(Icons.send_rounded), findsOneWidget);
  });

  testWidgets('a new contact added elsewhere appears in the contacts list',
      (WidgetTester tester) async {
    final FakeProfileRepository repo = FakeProfileRepository()
      ..seed(me())
      ..seed(sarah());
    await pumpApp(
      tester,
      authService: FakeAuthService(
        initialUser: const AuthUser(uid: 'me-uid', email: 'me@lotext.app'),
      ),
      profileRepository: repo,
    );

    // Add Sarah through the Add contact screen.
    await tester.tap(find.text('Add contact'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Username'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'sarah');
    await tester.tap(find.widgetWithText(LoTextButton, 'Search'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(LoTextButton, 'Add contact'));
    await tester.pumpAndSettle();

    // The Contacts tab now lists her.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await openToolsTab(tester);
    await tester.tap(find.text('Contacts'));
    await tester.pumpAndSettle();
    expect(find.text('Sarah Connor'), findsOneWidget);
    expect(find.text('@sarah'), findsOneWidget);
  });

  testWidgets('removing a contact removes them from the list',
      (WidgetTester tester) async {
    final FakeProfileRepository repo = FakeProfileRepository()
      ..seed(me())
      ..seed(sarah());
    repo.contacts['me-uid'] = <String>{'them-uid'};
    await pumpApp(
      tester,
      authService: FakeAuthService(
        initialUser: const AuthUser(uid: 'me-uid', email: 'me@lotext.app'),
      ),
      profileRepository: repo,
    );

    await openToolsTab(tester);
    await tester.tap(find.text('Contacts'));
    await tester.pumpAndSettle();
    expect(find.text('Sarah Connor'), findsOneWidget);

    await tester.tap(find.text('Sarah Connor'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(LoTextButton, 'Remove contact'));
    await tester.pumpAndSettle();

    expect(repo.contacts['me-uid'], isNot(contains('them-uid')));

    // Back on the Contacts tab the list is now empty.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('No contacts yet'), findsOneWidget);
  });
}
