import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lotext/core/auth/auth_user.dart';
import 'package:lotext/features/chat/models/chat_message.dart';
import 'package:lotext/features/profile/models/user_profile.dart';
import 'package:lotext/shared/widgets/lotext_button.dart';

import '../../fakes.dart';
import '../../widget_test.dart' show pumpApp, openToolsTab;

/// Admin profile: the voice changer only appears for admins.
UserProfile adminMe() => const UserProfile(
  uid: 'me-uid',
  username: 'me',
  displayName: 'Me',
  lotextId: '111111111',
  isOnline: true,
  isAdmin: true,
);

UserProfile sarah() => UserProfile(
  uid: 'them-uid',
  username: 'sarah',
  displayName: 'Sarah Connor',
  lotextId: '284716093',
  isOnline: true,
);

void main() {
  Future<
    (
      FakeProfileRepository,
      FakeChatRepository,
      FakeChatAiService,
      FakeVoiceRecorder,
    )
  >
  pumpAdminChat(WidgetTester tester) async {
    final FakeProfileRepository profileRepo = FakeProfileRepository()
      ..seed(adminMe())
      ..seed(sarah())
      ..contacts['me-uid'] = <String>{'them-uid'};
    final FakeChatRepository chatRepo = FakeChatRepository(
      profileRepository: profileRepo,
    );
    final FakeChatAiService chatAi = FakeChatAiService();
    final FakeVoiceRecorder recorder = FakeVoiceRecorder();
    await pumpApp(
      tester,
      authService: FakeAuthService(
        initialUser: const AuthUser(uid: 'me-uid', email: 'me@lotext.app'),
      ),
      profileRepository: profileRepo,
      chatRepository: chatRepo,
      chatAiService: chatAi,
      voiceRecorder: recorder,
    );
    return (profileRepo, chatRepo, chatAi, recorder);
  }

  Future<void> openChatWithSarah(WidgetTester tester) async {
    await openToolsTab(tester);
    await tester.tap(find.text('Contacts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sarah Connor'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(LoTextButton, 'Message'));
    await tester.pumpAndSettle();
  }

  /// Picks the "Guy" voice from the voice-changer bottom sheet.
  Future<void> pickGuyVoice(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.record_voice_over_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guy'));
    await tester.pumpAndSettle();
    expect(find.text('Voice: Guy'), findsOneWidget);
  }

  testWidgets('type-to-speak sends a voice note in the selected voice', (
    WidgetTester tester,
  ) async {
    final (_, FakeChatRepository chatRepo, FakeChatAiService chatAi, _) =
        await pumpAdminChat(tester);
    await openChatWithSarah(tester);

    await pickGuyVoice(tester);
    expect(
      find.text('Type a message to send in Guy\u2019s voice'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField), 'Hello there');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    // The AI service was asked to speak the typed text in Guy's voice.
    expect(chatAi.synthCalls, hasLength(1));
    expect(chatAi.synthCalls.single.voiceName, 'en-US-GuyNeural');
    expect(chatAi.synthCalls.single.text, 'Hello there');
    expect(chatAi.synthCalls.single.audioBytes, isNull);

    // The message was created as a voice message stamped with the effect id.
    final String conversationId = chatRepo.conversationIdFor(
      'me-uid',
      'them-uid',
    );
    final List<ChatMessage> messages = chatRepo.messages[conversationId]!;
    expect(messages, hasLength(1));
    final ChatMessage message = messages.single;
    expect(message.type, MessageType.voice);
    expect(message.voiceEffect, 'voice_guy');
    expect(message.mimeType, 'audio/mpeg');
    expect(message.mediaUrl, isNotNull);
  });

  testWidgets(
    'record-to-respeak re-speaks the recording in the selected voice',
    (WidgetTester tester) async {
      final (
        _,
        FakeChatRepository chatRepo,
        FakeChatAiService chatAi,
        FakeVoiceRecorder recorder,
      ) = await pumpAdminChat(
        tester,
      );
      await openChatWithSarah(tester);

      await pickGuyVoice(tester);

      // Hold the mic: a recording is made and re-spoken through the AI service.
      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.mic_none_rounded)),
      );
      await tester.pump(const Duration(milliseconds: 700));
      expect(recorder.startCalls, 1);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(recorder.stopCalls, 1);
      expect(chatAi.synthCalls, hasLength(1));
      expect(chatAi.synthCalls.single.voiceName, 'en-US-GuyNeural');
      expect(chatAi.synthCalls.single.text, isNull);
      expect(chatAi.synthCalls.single.audioBytes, isNotNull);

      final String conversationId = chatRepo.conversationIdFor(
        'me-uid',
        'them-uid',
      );
      final List<ChatMessage> messages = chatRepo.messages[conversationId]!;
      expect(messages, hasLength(1));
      expect(messages.single.type, MessageType.voice);
      expect(messages.single.voiceEffect, 'voice_guy');
    },
  );

  testWidgets('voice messages still show the voice badge on the bubble', (
    WidgetTester tester,
  ) async {
    final (_, FakeChatRepository chatRepo, FakeChatAiService chatAi, _) =
        await pumpAdminChat(tester);
    await openChatWithSarah(tester);

    await pickGuyVoice(tester);
    await tester.enterText(find.byType(TextField), 'Speak to me');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    // The badge (Guy) renders next to the waveform inside the bubble.
    expect(find.text('Guy'), findsWidgets);
    expect(chatAi.synthCalls, hasLength(1));
    expect(
      chatRepo
          .messages[chatRepo.conversationIdFor('me-uid', 'them-uid')]!
          .single
          .voiceEffect,
      'voice_guy',
    );
  });

  testWidgets('synthesis failure shows an error and does not send', (
    WidgetTester tester,
  ) async {
    final (_, FakeChatRepository chatRepo, FakeChatAiService chatAi, _) =
        await pumpAdminChat(tester);
    await openChatWithSarah(tester);

    chatAi.failRequests = true;
    await pickGuyVoice(tester);
    await tester.enterText(find.byType(TextField), 'Hello there');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Voice synthesis failed'), findsOneWidget);
    final String conversationId = chatRepo.conversationIdFor(
      'me-uid',
      'them-uid',
    );
    expect(chatRepo.messages[conversationId], isNull);
  });
}
