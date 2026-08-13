import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lotext/core/auth/auth_user.dart';
import 'package:lotext/features/chat/models/chat_message.dart';
import 'package:lotext/features/profile/models/user_profile.dart';
import 'package:lotext/shared/widgets/lotext_button.dart';

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

void main() {
  Future<(FakeProfileRepository, FakeChatRepository)> pumpChatApp(
    WidgetTester tester, {
    bool addSarahAsContact = true,
  }) async {
    final FakeProfileRepository profileRepo = FakeProfileRepository()
      ..seed(me())
      ..seed(sarah());
    if (addSarahAsContact) {
      profileRepo.contacts['me-uid'] = <String>{'them-uid'};
    }
    final FakeChatRepository chatRepo =
        FakeChatRepository(profileRepository: profileRepo);
    await pumpApp(
      tester,
      authService: FakeAuthService(
        initialUser: const AuthUser(uid: 'me-uid', email: 'me@lotext.app'),
      ),
      profileRepository: profileRepo,
      chatRepository: chatRepo,
    );
    return (profileRepo, chatRepo);
  }

  /// Navigates: Contacts tab -> Sarah's public profile -> Message.
  Future<void> openChatWithSarah(WidgetTester tester) async {
    await tester.tap(find.text('Contacts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sarah Connor'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(LoTextButton, 'Message'));
    await tester.pumpAndSettle();
  }

  testWidgets('tapping Message opens a chat and sending shows the bubble',
      (WidgetTester tester) async {
    final (_, FakeChatRepository chatRepo) = await pumpChatApp(tester);

    await openChatWithSarah(tester);

    // Conversation was created (deterministic id) and the app bar shows Sarah.
    final String conversationId =
        chatRepo.conversationIdFor('me-uid', 'them-uid');
    expect(chatRepo.conversations.containsKey(conversationId), isTrue);
    expect(find.text('Sarah Connor'), findsOneWidget);

    // Send a message; it appears as a bubble.
    await tester.enterText(find.byType(TextField), 'Hello Sarah');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Hello Sarah'), findsOneWidget);
    // The peer's unread counter was bumped by the send.
    expect(
      chatRepo.conversations[conversationId]!.unreadCounts['them-uid'],
      1,
    );
  });

  testWidgets('incoming messages are acknowledged as read while chat is open',
      (WidgetTester tester) async {
    final (_, FakeChatRepository chatRepo) = await pumpChatApp(tester);
    final String conversationId =
        chatRepo.conversationIdFor('me-uid', 'them-uid');

    await openChatWithSarah(tester);

    // Sarah sends while we have the chat open.
    await chatRepo.sendMessage(
      conversationId: conversationId,
      senderUid: 'them-uid',
      text: 'Are you there?',
    );
    await tester.pumpAndSettle();

    expect(find.text('Are you there?'), findsOneWidget);
    final List<ChatMessage> sent = chatRepo.messages[conversationId]!;
    expect(sent.last.senderUid, 'them-uid');
    expect(sent.last.status, ChatMessageStatus.read);
    expect(
      chatRepo.conversations[conversationId]!.unreadCounts['me-uid'],
      0,
    );
  });

  testWidgets('chats tab lists conversations with a preview and unread badge',
      (WidgetTester tester) async {
    final FakeProfileRepository profileRepo = FakeProfileRepository()
      ..seed(me())
      ..seed(sarah());
    profileRepo.contacts['me-uid'] = <String>{'them-uid'};
    final FakeChatRepository chatRepo =
        FakeChatRepository(profileRepository: profileRepo);
    await chatRepo.ensureConversation(uid: 'me-uid', contactUid: 'them-uid');
    await chatRepo.sendMessage(
      conversationId: chatRepo.conversationIdFor('me-uid', 'them-uid'),
      senderUid: 'them-uid',
      text: 'Hey Me',
    );

    await pumpApp(
      tester,
      authService: FakeAuthService(
        initialUser: const AuthUser(uid: 'me-uid', email: 'me@lotext.app'),
      ),
      profileRepository: profileRepo,
      chatRepository: chatRepo,
    );
    await tester.tap(find.text('Chats'));
    await tester.pumpAndSettle();

    expect(find.text('Sarah Connor'), findsOneWidget);
    expect(find.text('Hey Me'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('tapping a conversation from the chats tab opens it',
      (WidgetTester tester) async {
    final FakeProfileRepository profileRepo = FakeProfileRepository()
      ..seed(me())
      ..seed(sarah());
    profileRepo.contacts['me-uid'] = <String>{'them-uid'};
    final FakeChatRepository chatRepo =
        FakeChatRepository(profileRepository: profileRepo);
    await chatRepo.ensureConversation(uid: 'me-uid', contactUid: 'them-uid');
    await chatRepo.sendMessage(
      conversationId: chatRepo.conversationIdFor('me-uid', 'them-uid'),
      senderUid: 'them-uid',
      text: 'Hey Me',
    );

    await pumpApp(
      tester,
      authService: FakeAuthService(
        initialUser: const AuthUser(uid: 'me-uid', email: 'me@lotext.app'),
      ),
      profileRepository: profileRepo,
      chatRepository: chatRepo,
    );
    await tester.tap(find.text('Chats'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sarah Connor'));
    await tester.pumpAndSettle();

    // Chat opened: app bar shows the peer and the message is visible.
    expect(find.text('Sarah Connor'), findsOneWidget);
    expect(find.text('Hey Me'), findsOneWidget);
  });

  testWidgets('messaging a non-contact asks them to be added first',
      (WidgetTester tester) async {
    await pumpChatApp(tester, addSarahAsContact: false);

    // Contacts tab is empty -> Add contact screen -> search by username.
    await tester.tap(find.text('Contacts'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(LoTextButton, 'Add contact'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Username'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'sarah');
    await tester.tap(find.widgetWithText(LoTextButton, 'Search'));
    await tester.pumpAndSettle();

    // Open Sarah's profile from the search result.
    await tester.tap(find.text('Tap to view their profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(LoTextButton, 'Message'));
    await tester.pumpAndSettle();

    expect(
      find.text('Add them as a contact to start messaging.'),
      findsOneWidget,
    );
  });
}
