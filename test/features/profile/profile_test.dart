import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lotext/core/auth/auth_user.dart';
import 'package:lotext/features/profile/models/user_profile.dart';
import 'package:lotext/shared/widgets/lotext_button.dart';

import '../../fakes.dart';
import '../../widget_test.dart' show pumpApp, openToolsTab;

UserProfile profileOf(String uid) => UserProfile(
      uid: uid,
      username: '',
      displayName: '',
      isOnline: true,
    );

UserProfile ada() => const UserProfile(
      uid: 'test-uid',
      username: 'ada',
      displayName: 'Ada Lovelace',
      lotextId: '728491630',
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
  testWidgets('new user is forced through username setup',
      (WidgetTester tester) async {
    final FakeProfileRepository repo = FakeProfileRepository()
      ..seed(profileOf('test-uid'));
    await pumpApp(
      tester,
      authService: FakeAuthService(
        initialUser: const AuthUser(uid: 'test-uid', email: 'new@lotext.app'),
      ),
      profileRepository: repo,
    );

    // Router should have parked the user on the choose-username screen.
    expect(find.text('Claim your @username'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('claiming a username moves the user into the app',
      (WidgetTester tester) async {
    final FakeProfileRepository repo = FakeProfileRepository()
      ..seed(profileOf('test-uid'));
    await pumpApp(
      tester,
      authService: FakeAuthService(
        initialUser: const AuthUser(uid: 'test-uid', email: 'new@lotext.app'),
      ),
      profileRepository: repo,
    );

    await tester.enterText(find.byType(TextField).first, 'Jerry_2026');
    // Let the debounce fire and the availability check resolve.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('Username available'), findsOneWidget);

    await tester.tap(find.widgetWithText(LoTextButton, 'Continue'));
    await tester.pumpAndSettle();

    // Username was claimed in the repository, lowercased.
    expect(repo.profiles['test-uid']!.username, 'jerry_2026');
    expect(repo.usernames, contains('jerry_2026'));
    // Router moved the user into the main screen.
    expect(find.text('LoText'), findsOneWidget);
  });

  testWidgets('taken usernames are rejected during setup',
      (WidgetTester tester) async {
    final FakeProfileRepository repo = FakeProfileRepository()
      ..seed(profileOf('test-uid'))
      ..seed(const UserProfile(
        uid: 'other-uid',
        username: 'taken',
        displayName: 'Taken',
      ));
    await pumpApp(
      tester,
      authService: FakeAuthService(
        initialUser: const AuthUser(uid: 'test-uid', email: 'new@lotext.app'),
      ),
      profileRepository: repo,
    );

    await tester.enterText(find.byType(TextField).first, 'Taken');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('Username already taken'), findsWidgets);
    // Continue stays disabled.
    final LoTextButton button = tester.widget<LoTextButton>(
      find.widgetWithText(LoTextButton, 'Continue'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('accounts without a LoText ID are back-filled on load',
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

    final String? lotextId = repo.profiles['test-uid']!.lotextId;
    expect(lotextId, isNotNull);
    expect(lotextId, matches(r'^\d{9}$'));
    expect(repo.lotextIds[lotextId], 'test-uid');
  });

  testWidgets('profile tab shows public fields, LoText ID and copy actions',
      (WidgetTester tester) async {
    final List<String> copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map<Object?, Object?>)['text']! as String);
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    final FakeProfileRepository repo = FakeProfileRepository()..seed(ada());
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

    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('@ada'), findsOneWidget);
    expect(find.text('Online'), findsOneWidget);
    expect(find.text('LoText ID: 728491630'), findsOneWidget);
    expect(find.text('Edit profile'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);

    // Copy username copies the bare handle (no @).
    await tester.tap(find.widgetWithText(LoTextButton, 'Copy username'));
    await tester.pumpAndSettle();
    expect(copied, contains('ada'));

    // Copy LoText ID copies the digits.
    await tester.tap(find.widgetWithText(LoTextButton, 'Copy LoText ID'));
    await tester.pumpAndSettle();
    expect(copied, contains('728491630'));
    expect(find.text('LoText ID copied to clipboard.'), findsOneWidget);
  });

  testWidgets('editing display name and username updates the profile',
      (WidgetTester tester) async {
    final FakeProfileRepository repo = FakeProfileRepository()
      ..seed(const UserProfile(
        uid: 'test-uid',
        username: 'ada',
        displayName: 'Ada',
        lotextId: '728491630',
        isOnline: true,
      ));
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
    await tester.tap(find.text('Edit profile'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Ada'),
      'Ada Lovelace',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'ada'),
      'AdaLovelace',
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(LoTextButton, 'Save changes'));
    await tester.pumpAndSettle();

    final UserProfile updated = repo.profiles['test-uid']!;
    expect(updated.displayName, 'Ada Lovelace');
    expect(updated.username, 'adalovelace');
    // Old username was released, new one registered.
    expect(repo.usernames, isNot(contains('ada')));
    expect(repo.usernames, contains('adalovelace'));
  });

  testWidgets('changing the profile photo applies the picked image',
      (WidgetTester tester) async {
    final FakeProfileRepository repo = FakeProfileRepository()
      ..seed(const UserProfile(
        uid: 'test-uid',
        username: 'ada',
        displayName: 'Ada',
        lotextId: '728491630',
        isOnline: true,
      ));
    await pumpApp(
      tester,
      authService: FakeAuthService(
        initialUser: const AuthUser(uid: 'test-uid', email: 'ada@lotext.app'),
      ),
      profileRepository: repo,
      photoPicker: FakePhotoPicker(photo: fakePhoto()),
    );

    await openToolsTab(tester);
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit profile'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Change photo'));
    await tester.pumpAndSettle();

    expect(
      repo.profiles['test-uid']!.photoURL,
      'https://fake.example/photo_test-uid.jpg',
    );
    expect(find.text('Profile photo updated'), findsOneWidget);
  });

  testWidgets('removing the profile photo clears the URL',
      (WidgetTester tester) async {
    final FakeProfileRepository repo = FakeProfileRepository()
      ..seed(const UserProfile(
        uid: 'test-uid',
        username: 'ada',
        displayName: 'Ada',
        lotextId: '728491630',
        photoURL: 'https://fake.example/photo_test-uid.jpg',
        isOnline: true,
      ));
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
    await tester.tap(find.text('Edit profile'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Remove photo'));
    await tester.pumpAndSettle();

    expect(repo.profiles['test-uid']!.photoURL, isNull);
  });

  testWidgets('add contact by username finds an exact match and adds them',
      (WidgetTester tester) async {
    final FakeProfileRepository repo = FakeProfileRepository()
      ..seed(const UserProfile(
        uid: 'me-uid',
        username: 'me',
        displayName: 'Me',
        lotextId: '111111111',
        isOnline: true,
      ))
      ..seed(sarah());
    await pumpApp(
      tester,
      authService: FakeAuthService(
        initialUser: const AuthUser(uid: 'me-uid', email: 'me@lotext.app'),
      ),
      profileRepository: repo,
    );

    // Home screen card opens the Add contact screen.
    await tester.tap(find.text('Add contact'));
    await tester.pumpAndSettle();
    expect(find.text('Add contact'), findsWidgets);

    // Switch to username lookup and enter an exact username.
    await tester.tap(find.text('Username'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Sarah');
    await tester.tap(find.widgetWithText(LoTextButton, 'Search'));
    await tester.pumpAndSettle();

    expect(find.text('Sarah Connor'), findsOneWidget);
    expect(find.text('@sarah'), findsOneWidget);
    expect(find.text('LoText ID: 284716093'), findsOneWidget);

    await tester.tap(find.widgetWithText(LoTextButton, 'Add contact'));
    await tester.pumpAndSettle();

    // Explicit add created the private, one-way contact.
    expect(repo.contacts['me-uid'], contains('them-uid'));
    // ...but did not add "me" to Sarah's list.
    expect(repo.contacts['them-uid'], isNull);
    expect(find.text('Already in your contacts'), findsOneWidget);
  });

  testWidgets('add contact by LoText ID finds an exact match',
      (WidgetTester tester) async {
    final FakeProfileRepository repo = FakeProfileRepository()
      ..seed(const UserProfile(
        uid: 'me-uid',
        username: 'me',
        displayName: 'Me',
        lotextId: '111111111',
        isOnline: true,
      ))
      ..seed(sarah());
    await pumpApp(
      tester,
      authService: FakeAuthService(
        initialUser: const AuthUser(uid: 'me-uid', email: 'me@lotext.app'),
      ),
      profileRepository: repo,
    );

    await tester.tap(find.text('Add contact'));
    await tester.pumpAndSettle();

    // LoText ID mode is the default.
    await tester.enterText(find.byType(TextField).first, '284716093');
    await tester.tap(find.widgetWithText(LoTextButton, 'Search'));
    await tester.pumpAndSettle();

    expect(find.text('Sarah Connor'), findsOneWidget);
    expect(find.text('@sarah'), findsOneWidget);

    await tester.tap(find.widgetWithText(LoTextButton, 'Add contact'));
    await tester.pumpAndSettle();
    expect(repo.contacts['me-uid'], contains('them-uid'));
  });

  testWidgets('partial or display-name searches return nothing',
      (WidgetTester tester) async {
    final FakeProfileRepository repo = FakeProfileRepository()
      ..seed(const UserProfile(
        uid: 'me-uid',
        username: 'me',
        displayName: 'Me',
        lotextId: '111111111',
        isOnline: true,
      ))
      ..seed(sarah());
    await pumpApp(
      tester,
      authService: FakeAuthService(
        initialUser: const AuthUser(uid: 'me-uid', email: 'me@lotext.app'),
      ),
      profileRepository: repo,
    );

    await tester.tap(find.text('Add contact'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Username'));
    await tester.pumpAndSettle();

    // Partial username: no result.
    await tester.enterText(find.byType(TextField).first, 'sar');
    await tester.tap(find.widgetWithText(LoTextButton, 'Search'));
    await tester.pumpAndSettle();
    expect(find.text('No one found'), findsOneWidget);

    // Display-name search is not supported: also no result.
    await tester.enterText(find.byType(TextField).first, 'Sarah Connor');
    await tester.tap(find.widgetWithText(LoTextButton, 'Search'));
    await tester.pumpAndSettle();
    expect(find.text('No one found'), findsOneWidget);
  });

  testWidgets('partial LoText IDs are rejected as invalid',
      (WidgetTester tester) async {
    final FakeProfileRepository repo = FakeProfileRepository()
      ..seed(const UserProfile(
        uid: 'me-uid',
        username: 'me',
        displayName: 'Me',
        lotextId: '111111111',
        isOnline: true,
      ));
    await pumpApp(
      tester,
      authService: FakeAuthService(
        initialUser: const AuthUser(uid: 'me-uid', email: 'me@lotext.app'),
      ),
      profileRepository: repo,
    );

    await tester.tap(find.text('Add contact'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '2847');
    await tester.tap(find.widgetWithText(LoTextButton, 'Search'));
    await tester.pumpAndSettle();

    expect(find.text('No one found'), findsNothing);
    expect(
      find.text('Enter a valid 9-digit LoText ID, for example 728491630.'),
      findsOneWidget,
    );
  });

  testWidgets('finding someone already in your contacts shows a notice',
      (WidgetTester tester) async {
    final FakeProfileRepository repo = FakeProfileRepository()
      ..seed(const UserProfile(
        uid: 'me-uid',
        username: 'me',
        displayName: 'Me',
        lotextId: '111111111',
        isOnline: true,
      ))
      ..seed(sarah());
    repo.contacts['me-uid'] = <String>{'them-uid'};
    await pumpApp(
      tester,
      authService: FakeAuthService(
        initialUser: const AuthUser(uid: 'me-uid', email: 'me@lotext.app'),
      ),
      profileRepository: repo,
    );

    await tester.tap(find.text('Add contact'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Username'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'sarah');
    await tester.tap(find.widgetWithText(LoTextButton, 'Search'));
    await tester.pumpAndSettle();

    expect(find.text('Sarah Connor'), findsOneWidget);
    expect(find.text('Already in your contacts'), findsOneWidget);
    expect(find.widgetWithText(LoTextButton, 'Add contact'), findsNothing);
  });

  testWidgets('searching yourself is blocked', (WidgetTester tester) async {
    final FakeProfileRepository repo = FakeProfileRepository()
      ..seed(const UserProfile(
        uid: 'me-uid',
        username: 'me',
        displayName: 'Me',
        lotextId: '111111111',
        isOnline: true,
      ));
    await pumpApp(
      tester,
      authService: FakeAuthService(
        initialUser: const AuthUser(uid: 'me-uid', email: 'me@lotext.app'),
      ),
      profileRepository: repo,
    );

    await tester.tap(find.text('Add contact'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Username'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'me');
    await tester.tap(find.widgetWithText(LoTextButton, 'Search'));
    await tester.pumpAndSettle();

    expect(find.text("That's you"), findsOneWidget);
    expect(find.widgetWithText(LoTextButton, 'Add contact'), findsNothing);
    expect(repo.contacts['me-uid'], isNull);
  });

  testWidgets(
      'a stale username registration pointing at you still finds the friend',
      (WidgetTester tester) async {
    final FakeProfileRepository repo = FakeProfileRepository()
      ..seed(const UserProfile(
        uid: 'me-uid',
        username: 'me',
        displayName: 'Me',
        lotextId: '111111111',
        isOnline: true,
      ))
      ..seed(sarah());
    // Corrupt the registry the way production data got corrupted: the friend's
    // username now maps to the signed-in user's uid.
    repo.usernames['sarah'] = 'me-uid';
    await pumpApp(
      tester,
      authService: FakeAuthService(
        initialUser: const AuthUser(uid: 'me-uid', email: 'me@lotext.app'),
      ),
      profileRepository: repo,
    );

    await tester.tap(find.text('Add contact'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Username'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'sarah');
    await tester.tap(find.widgetWithText(LoTextButton, 'Search'));
    await tester.pumpAndSettle();

    expect(find.text('Sarah Connor'), findsOneWidget);
    expect(find.text("That's you"), findsNothing);
    expect(find.widgetWithText(LoTextButton, 'Add contact'), findsOneWidget);
  });

  testWidgets(
      'a stale LoText ID registration pointing at you still finds the friend',
      (WidgetTester tester) async {
    final FakeProfileRepository repo = FakeProfileRepository()
      ..seed(const UserProfile(
        uid: 'me-uid',
        username: 'me',
        displayName: 'Me',
        lotextId: '111111111',
        isOnline: true,
      ))
      ..seed(sarah());
    // Corrupt the registry: the friend's LoText ID now maps to the signed-in
    // user's uid.
    repo.lotextIds['284716093'] = 'me-uid';
    await pumpApp(
      tester,
      authService: FakeAuthService(
        initialUser: const AuthUser(uid: 'me-uid', email: 'me@lotext.app'),
      ),
      profileRepository: repo,
    );

    await tester.tap(find.text('Add contact'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '284716093');
    await tester.tap(find.widgetWithText(LoTextButton, 'Search'));
    await tester.pumpAndSettle();

    expect(find.text('Sarah Connor'), findsOneWidget);
    expect(find.text("That's you"), findsNothing);
    expect(find.widgetWithText(LoTextButton, 'Add contact'), findsOneWidget);
  });

  testWidgets('signing out returns to the welcome screen',
      (WidgetTester tester) async {
    final FakeAuthService auth = FakeAuthService(
      initialUser: const AuthUser(uid: 'test-uid', email: 'ada@lotext.app'),
    );
    final FakeProfileRepository repo = FakeProfileRepository()
      ..seed(const UserProfile(
        uid: 'test-uid',
        username: 'ada',
        displayName: 'Ada',
      ));
    await pumpApp(tester, authService: auth, profileRepository: repo);

    await openToolsTab(tester);
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(LoTextButton, 'Sign out'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Welcome to', findRichText: true), findsOneWidget);
    expect(auth.currentUser, isNull);
  });
}
