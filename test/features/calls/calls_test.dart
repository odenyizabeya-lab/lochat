import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lotext/core/auth/auth_user.dart';
import 'package:lotext/features/calls/models/call.dart';
import 'package:lotext/features/profile/models/user_profile.dart';

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
      isOnline: true,
    );

UserProfile bob() => UserProfile(
      uid: 'bob-uid',
      username: 'bob',
      displayName: 'Bob Ross',
      lotextId: '503991482',
      isOnline: true,
    );

void main() {
  /// Seeds Sarah (and optionally Bob) as contacts with a ready conversation,
  /// pumps the fully wired app and opens the Calls tab.
  Future<(FakeProfileRepository, FakeChatRepository, FakeCallSignalingService)>
      pumpCallsApp(
    WidgetTester tester, {
    FakeCallSignalingService? signaling,
    bool includeBob = false,
  }) async {
    final FakeProfileRepository profileRepo = FakeProfileRepository()
      ..seed(me())
      ..seed(sarah());
    if (includeBob) profileRepo.seed(bob());
    profileRepo.contacts['me-uid'] =
        <String>{'them-uid', if (includeBob) 'bob-uid'};
    final FakeChatRepository chatRepo =
        FakeChatRepository(profileRepository: profileRepo);
    await chatRepo.ensureConversation(uid: 'me-uid', contactUid: 'them-uid');
    if (includeBob) {
      await chatRepo.ensureConversation(uid: 'me-uid', contactUid: 'bob-uid');
    }
    final FakeCallSignalingService callSignaling =
        signaling ?? FakeCallSignalingService();
    await pumpApp(
      tester,
      authService: FakeAuthService(
        initialUser: const AuthUser(uid: 'me-uid', email: 'me@lotext.app'),
      ),
      profileRepository: profileRepo,
      chatRepository: chatRepo,
      callSignalingService: callSignaling,
    );
    await tester.tap(find.byIcon(Icons.call_outlined));
    await tester.pumpAndSettle();
    return (profileRepo, chatRepo, callSignaling);
  }

  /// Inserts a call into the fake store so the tab can render it.
  void seedCall(
    FakeCallSignalingService signaling, {
    required String id,
    required String conversationId,
    CallType type = CallType.audio,
    CallStatus status = CallStatus.ended,
    required String callerUid,
    required String calleeUid,
    DateTime? createdAt,
    DateTime? answeredAt,
    DateTime? endedAt,
  }) {
    signaling.seedCall(Call(
      id: id,
      conversationId: conversationId,
      type: type,
      callerUid: callerUid,
      calleeUid: calleeUid,
      status: status,
      createdAt: createdAt ?? DateTime.now().subtract(const Duration(hours: 2)),
      answeredAt: answeredAt,
      endedAt: endedAt,
    ));
  }

  testWidgets('empty calls tab shows the quick actions and an empty state',
      (WidgetTester tester) async {
    await pumpCallsApp(tester);

    expect(find.text('RECENT'), findsOneWidget);
    expect(find.text('New call'), findsOneWidget);
    expect(find.text('New video call'), findsOneWidget);
    expect(find.text('No recent calls'), findsOneWidget);
  });

  testWidgets('call history lists peers with direction, type and duration',
      (WidgetTester tester) async {
    final (_, FakeChatRepository chatRepo, FakeCallSignalingService signaling) =
        await pumpCallsApp(tester);
    final String conversationId =
        chatRepo.conversationIdFor('me-uid', 'them-uid');
    final DateTime createdAt = DateTime.now().subtract(const Duration(hours: 1));
    seedCall(
      signaling,
      id: 'call-out',
      conversationId: conversationId,
      callerUid: 'me-uid',
      calleeUid: 'them-uid',
      createdAt: createdAt,
      answeredAt: createdAt.add(const Duration(minutes: 1)),
      endedAt: createdAt.add(const Duration(minutes: 3, seconds: 5)),
    );
    seedCall(
      signaling,
      id: 'call-in-missed',
      conversationId: conversationId,
      type: CallType.video,
      status: CallStatus.missed,
      callerUid: 'them-uid',
      calleeUid: 'me-uid',
    );
    seedCall(
      signaling,
      id: 'call-declined',
      conversationId: conversationId,
      type: CallType.video,
      status: CallStatus.declined,
      callerUid: 'them-uid',
      calleeUid: 'me-uid',
    );
    await tester.pumpAndSettle();

    expect(find.text('Sarah Connor'), findsNWidgets(3));
    expect(find.text('Outgoing voice call \u00b7 2:05'), findsOneWidget);
    expect(find.text('Missed video call'), findsOneWidget);
    expect(find.text('Declined video call'), findsOneWidget);
    expect(find.byTooltip('Call back'), findsNWidgets(3));
  });

  testWidgets('tapping a call tile opens the chat with that peer',
      (WidgetTester tester) async {
    final (_, FakeChatRepository chatRepo, FakeCallSignalingService signaling) =
        await pumpCallsApp(tester);
    seedCall(
      signaling,
      id: 'call-tap',
      conversationId: chatRepo.conversationIdFor('me-uid', 'them-uid'),
      callerUid: 'them-uid',
      calleeUid: 'me-uid',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sarah Connor'));
    await tester.pumpAndSettle();

    expect(find.text('@sarah \u00b7 Online'), findsOneWidget);
  });

  testWidgets('search filters the history by contact name',
      (WidgetTester tester) async {
    final (_, FakeChatRepository chatRepo, FakeCallSignalingService signaling) =
        await pumpCallsApp(tester, includeBob: true);
    seedCall(
      signaling,
      id: 'call-sarah',
      conversationId: chatRepo.conversationIdFor('me-uid', 'them-uid'),
      callerUid: 'them-uid',
      calleeUid: 'me-uid',
    );
    seedCall(
      signaling,
      id: 'call-bob',
      conversationId: chatRepo.conversationIdFor('me-uid', 'bob-uid'),
      callerUid: 'bob-uid',
      calleeUid: 'me-uid',
    );
    await tester.pumpAndSettle();
    expect(find.text('Sarah Connor'), findsOneWidget);
    expect(find.text('Bob Ross'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.search_rounded));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'sarah');
    await tester.pumpAndSettle();

    expect(find.text('Sarah Connor'), findsOneWidget);
    expect(find.text('Bob Ross'), findsNothing);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No results found'), findsOneWidget);
  });

  testWidgets('a new call change refreshes the history live',
      (WidgetTester tester) async {
    final (_, FakeChatRepository chatRepo, FakeCallSignalingService signaling) =
        await pumpCallsApp(tester);
    expect(find.text('No recent calls'), findsOneWidget);

    seedCall(
      signaling,
      id: 'call-live',
      conversationId: chatRepo.conversationIdFor('me-uid', 'them-uid'),
      callerUid: 'me-uid',
      calleeUid: 'them-uid',
    );
    await tester.pumpAndSettle();

    expect(find.text('No recent calls'), findsNothing);
    expect(find.text('Sarah Connor'), findsOneWidget);
  });

  testWidgets('the overflow menu opens the full call history screen',
      (WidgetTester tester) async {
    final (_, FakeChatRepository chatRepo, FakeCallSignalingService signaling) =
        await pumpCallsApp(tester);
    seedCall(
      signaling,
      id: 'call-hist',
      conversationId: chatRepo.conversationIdFor('me-uid', 'them-uid'),
      type: CallType.video,
      status: CallStatus.missed,
      callerUid: 'them-uid',
      calleeUid: 'me-uid',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Call history'));
    await tester.pumpAndSettle();

    // A detail screen: no quick actions, but the call is listed.
    expect(find.text('New call'), findsNothing);
    expect(find.text('Missed video call'), findsOneWidget);
  });

  testWidgets('call history screen shows an empty state without calls',
      (WidgetTester tester) async {
    await pumpCallsApp(tester);

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Call history'));
    await tester.pumpAndSettle();

    expect(find.text('No calls yet'), findsOneWidget);
  });

  testWidgets('a failed history load shows an error that can be retried',
      (WidgetTester tester) async {
    final FakeCallSignalingService signaling = FakeCallSignalingService()
      ..failRequests = true;
    final (_, FakeChatRepository chatRepo, _) =
        await pumpCallsApp(tester, signaling: signaling);
    expect(find.text('Could not load call history'), findsOneWidget);

    signaling.failRequests = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Could not load call history'), findsNothing);
    expect(find.text('No recent calls'), findsOneWidget);

    seedCall(
      signaling,
      id: 'call-err',
      conversationId: chatRepo.conversationIdFor('me-uid', 'them-uid'),
      callerUid: 'them-uid',
      calleeUid: 'me-uid',
    );
    await tester.pumpAndSettle();
    expect(find.text('Sarah Connor'), findsOneWidget);
  });

  testWidgets('a quick action opens the contact picker and starts a call',
      (WidgetTester tester) async {
    await pumpCallsApp(tester);

    await tester.tap(find.text('New call'));
    await tester.pumpAndSettle();
    expect(find.text('Sarah Connor'), findsOneWidget);

    await tester.tap(find.text('Sarah Connor'));
    await tester.pumpAndSettle();

    expect(find.text('Ringing\u2026'), findsOneWidget);
  });
}
