import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lotext/core/auth/auth_user.dart';
import 'package:lotext/features/profile/models/user_profile.dart';
import 'package:lotext/features/status/models/status_update.dart';
import 'package:lotext/features/status/screens/status_viewer_screen.dart';

import '../../fakes.dart';
import '../../widget_test.dart' show pumpApp;

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

StatusUpdate textStatus({
  required String id,
  required String uid,
  required String text,
  bool viewedByMe = false,
}) {
  return StatusUpdate(
    id: id,
    uid: uid,
    type: StatusType.text,
    text: text,
    createdAt: DateTime.now(),
    expiresAt: DateTime.now().add(const Duration(hours: 24)),
  );
}

void main() {
  /// Pumps the app signed in as [me] and switches to the Updates tab.
  Future<FakeStatusRepository> pumpUpdates(
    WidgetTester tester, {
    FakeStatusRepository? statusRepository,
  }) async {
    final FakeProfileRepository repo = FakeProfileRepository()
      ..seed(me())
      ..seed(sarah());
    final FakeStatusRepository statusRepo =
        statusRepository ?? (FakeStatusRepository()..seedProfile(sarah()));
    await pumpApp(
      tester,
      authService: FakeAuthService(
        initialUser: const AuthUser(uid: 'me-uid', email: 'me@lotext.app'),
      ),
      profileRepository: repo,
      statusRepository: statusRepo,
    );
    await tester.tap(find.text('Updates'));
    await tester.pumpAndSettle();
    return statusRepo;
  }

  /// Opens a status viewer and lets the route transition finish without
  /// running out the 5s auto-advance timer.
  Future<void> openViewer(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Pauses the auto-advance progress so later pumps stay put.
  Future<void> pauseViewer(WidgetTester tester) async {
    await tester.tapAt(tester.getCenter(find.byType(StatusViewerScreen)));
    await tester.pump();
  }

  testWidgets('updates tab shows an empty state with an add action',
      (WidgetTester tester) async {
    await pumpUpdates(tester);

    expect(find.text('My status'), findsOneWidget);
    expect(find.text('Tap to add status update'), findsOneWidget);
    expect(find.text('No recent updates'), findsOneWidget);
    expect(find.text('RECENT UPDATES'), findsOneWidget);
  });

  testWidgets('a contact status is listed and opens in the viewer',
      (WidgetTester tester) async {
    final FakeStatusRepository statusRepo = FakeStatusRepository()
      ..seedProfile(sarah())
      ..seedStatus(textStatus(id: 's1', uid: 'them-uid', text: 'Busy today'));
    await pumpUpdates(tester, statusRepository: statusRepo);

    expect(find.text('Sarah Connor'), findsOneWidget);
    expect(find.text('Just now'), findsOneWidget);

    await tester.tap(find.text('Sarah Connor'));
    await openViewer(tester);

    expect(find.text('Busy today'), findsOneWidget);
    expect(statusRepo.views['s1']?.containsKey('me-uid'), isTrue);

    await pauseViewer(tester);
  });

  testWidgets('posting a text status updates "My status"',
      (WidgetTester tester) async {
    await pumpUpdates(tester);

    await tester.tap(find.byTooltip('Add status'));
    await tester.pumpAndSettle();
    expect(find.text('Add to your status'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Good morning');
    await tester.tap(find.byTooltip('Post status'));
    await tester.pumpAndSettle();

    expect(find.text('My status'), findsOneWidget);
    expect(find.text('1 update'), findsOneWidget);
    expect(find.text('Tap to add status update'), findsNothing);
  });

  testWidgets('an author can delete their own status',
      (WidgetTester tester) async {
    final FakeStatusRepository statusRepo = FakeStatusRepository()
      ..seedProfile(me())
      ..seedStatus(textStatus(id: 'my1', uid: 'me-uid', text: 'My update'));
    await pumpUpdates(tester, statusRepository: statusRepo);

    expect(find.text('1 update'), findsOneWidget);

    await tester.tap(find.text('My status'));
    await openViewer(tester);
    expect(find.text('My update'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete status'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Delete status?'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('My status'), findsOneWidget);
    expect(find.text('Tap to add status update'), findsOneWidget);
    expect(statusRepo.statuses.containsKey('my1'), isFalse);
  });
}
