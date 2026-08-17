import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lotext/core/theme/app_theme.dart';
import 'package:lotext/features/admin/admin_managed_call_history_screen.dart';
import 'package:lotext/features/admin/admin_managed_call_screen.dart';
import 'package:lotext/features/admin/admin_managed_status_viewer_screen.dart';
import 'package:lotext/features/admin/admin_managed_updates_screen.dart';
import 'package:lotext/features/admin/data/managed_account_repository.dart';
import 'package:lotext/features/admin/data/managed_chat_repository.dart';
import 'package:lotext/features/admin/managed_account_controller.dart';
import 'package:lotext/features/admin/managed_account_scope.dart';
import 'package:lotext/features/admin/managed_chat_controller.dart';
import 'package:lotext/features/admin/managed_chat_scope.dart';
import 'package:lotext/features/admin/models/managed_account.dart';
import 'package:lotext/features/admin/models/managed_call.dart';
import 'package:lotext/features/admin/models/managed_conversation.dart';
import 'package:lotext/features/admin/models/managed_message.dart';
import 'package:lotext/features/admin/models/managed_status.dart';
import 'package:lotext/features/chat/data/chat_repository.dart';
import 'package:lotext/features/chat/media/video_playback.dart';
import 'package:lotext/features/chat/media/voice_recorder.dart';
import 'package:lotext/features/profile/models/user_profile.dart';

const String _fontsDir = 'C:/src/flutter/bin/cache/artifacts/material_fonts';

Future<void> _loadRealFonts() async {
  final List<String> names = <String>[
    'roboto-regular.ttf',
    'roboto-medium.ttf',
    'roboto-bold.ttf',
    'roboto-italic.ttf',
  ];
  for (final String name in names) {
    final Uint8List bytes = File('$_fontsDir/$name').readAsBytesSync();
    final FontLoader loader = FontLoader('Roboto')
      ..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)));
    await loader.load();
  }
}

void main() {
  setUpAll(() async {
    await _loadRealFonts();
  });

  Future<void> pumpScreen(
    WidgetTester tester,
    Widget screen, {
    Duration? settle,
  }) async {
    tester.view.physicalSize = const Size(411, 890);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        debugShowCheckedModeBanner: false,
        home: screen,
      ),
    );
    if (settle != null) {
      await tester.pump(settle);
    } else {
      await tester.pumpAndSettle();
    }
  }

  Widget wrapManaged(Widget child, {ManagedChatRepository? chatRepository}) {
    final ManagedChatRepository repo =
        chatRepository ?? _FakeManagedChatRepository();
    final ManagedAccountController accounts = ManagedAccountController(
      accountRepository: _FakeManagedAccountRepository(),
      chatRepository: repo,
      adminUid: 'admin-1',
    )..load();
    final ManagedChatController chat = ManagedChatController(
      chatRepository: repo,
      accountController: accounts,
      mediaPicker: null,
      voiceRecorder: _FakeVoiceRecorder(),
      videoPlaybackFactory: (_) => _FakeVideoPlayback(),
    );
    accounts.selectAccount(
      ManagedAccount(
        id: 'account-1',
        adminUid: 'admin-1',
        slotIndex: 1,
        username: 'sandra25',
        displayName: 'Sandra',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ),
    );
    return ManagedAccountScope(
      controller: accounts,
      child: ManagedChatScope(controller: chat, child: child),
    );
  }

  testWidgets('admin call history capture', (WidgetTester tester) async {
    await pumpScreen(
      tester,
      wrapManaged(const AdminManagedCallHistoryScreen(managedAccountId: 'account-1')),
      settle: const Duration(milliseconds: 100),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await expectLater(
      find.byType(AdminManagedCallHistoryScreen),
      matchesGoldenFile('goldens/admin_call_history.png'),
    );
  });

  testWidgets('admin updates capture', (WidgetTester tester) async {
    await pumpScreen(
      tester,
      wrapManaged(const AdminManagedUpdatesScreen(managedAccountId: 'account-1')),
    );
    await expectLater(
      find.byType(AdminManagedUpdatesScreen),
      matchesGoldenFile('goldens/admin_updates.png'),
    );
  });

  testWidgets('admin status viewer capture', (WidgetTester tester) async {
    await pumpScreen(
      tester,
      wrapManaged(AdminManagedStatusViewerScreen(
        managedAccountId: 'account-1',
        statuses: <ManagedStatus>[
          ManagedStatus(
            id: 'ms-1',
            managedAccountId: 'account-1',
            type: ManagedStatusType.text,
            text: 'Good morning everyone!',
            createdAt: DateTime.now().subtract(const Duration(hours: 2)),
            expiresAt: DateTime.now().add(const Duration(hours: 22)),
          ),
          ManagedStatus(
            id: 'ms-2',
            managedAccountId: 'account-1',
            type: ManagedStatusType.text,
            text: 'New update coming soon.',
            createdAt: DateTime.now().subtract(const Duration(hours: 1)),
            expiresAt: DateTime.now().add(const Duration(hours: 23)),
          ),
        ],
        startIndex: 0,
      )),
      settle: const Duration(milliseconds: 400),
    );
    await expectLater(
      find.byType(AdminManagedStatusViewerScreen),
      matchesGoldenFile('goldens/admin_status_viewer.png'),
    );
  });

  testWidgets('admin active call capture', (WidgetTester tester) async {
    await pumpScreen(
      tester,
      wrapManaged(
        const AdminManagedCallScreen(
          callId: 'mc-ring',
          conversationId: 'conv-1',
          managedAccountId: 'account-1',
          peerName: 'Peer Test',
        ),
        chatRepository: _FakeRingingChatRepository(),
      ),
    );
    await expectLater(
      find.byType(AdminManagedCallScreen),
      matchesGoldenFile('goldens/admin_active_call.png'),
    );
  });
}

class _FakeManagedAccountRepository implements ManagedAccountRepository {
  @override
  Stream<List<ManagedAccount>> watchAccounts(String adminUid) {
    return Stream<List<ManagedAccount>>.value(<ManagedAccount>[
      ManagedAccount(
        id: 'account-1',
        adminUid: 'admin-1',
        slotIndex: 1,
        username: 'sandra25',
        displayName: 'Sandra',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ),
    ]);
  }

  @override
  Future<ManagedAccount?> fetchAccount(String adminUid, String accountId) async {
    return ManagedAccount(
      id: 'account-1',
      adminUid: 'admin-1',
      slotIndex: 1,
      username: 'sandra25',
      displayName: 'Sandra',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );
  }

  @override
  Future<ManagedAccount> createAccount({
    required String adminUid,
    required int slotIndex,
    required String username,
    required String displayName,
    String? lotextId,
    String? photoUrl,
    Map<String, dynamic>? settings,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ManagedAccount> updateAccount(ManagedAccount account) {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteAccount(String adminUid, String accountId) async {}
}

class _FakeManagedChatRepository implements ManagedChatRepository {
  final List<ManagedCall> _calls = <ManagedCall>[
    ManagedCall(
      id: 'mc-1',
      managedAccountId: 'account-1',
      conversationId: 'conv-1',
      peerUid: 'peer-1',
      type: ManagedCallType.audio,
      status: ManagedCallStatus.missed,
      createdAt: DateTime.now().subtract(const Duration(hours: 1)),
    ),
    ManagedCall(
      id: 'mc-2',
      managedAccountId: 'account-1',
      conversationId: 'conv-2',
      peerUid: 'peer-2',
      type: ManagedCallType.video,
      status: ManagedCallStatus.ended,
      createdAt: DateTime.now().subtract(const Duration(minutes: 40)),
      answeredAt: DateTime.now().subtract(const Duration(minutes: 39)),
      endedAt: DateTime.now().subtract(const Duration(minutes: 38)),
    ),
    ManagedCall(
      id: 'mc-3',
      managedAccountId: 'account-1',
      conversationId: 'conv-3',
      peerUid: 'peer-3',
      type: ManagedCallType.audio,
      status: ManagedCallStatus.ended,
      createdAt: DateTime.now().subtract(const Duration(minutes: 20)),
      answeredAt: DateTime.now().subtract(const Duration(minutes: 19)),
      endedAt: DateTime.now().subtract(const Duration(minutes: 18)),
    ),
  ];

  final List<ManagedStatus> _statuses = <ManagedStatus>[
    ManagedStatus(
      id: 'ms-1',
      managedAccountId: 'account-1',
      type: ManagedStatusType.text,
      text: 'Good morning everyone!',
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      expiresAt: DateTime.now().add(const Duration(hours: 22)),
    ),
    ManagedStatus(
      id: 'ms-2',
      managedAccountId: 'account-1',
      type: ManagedStatusType.image,
      text: 'From the beach',
      createdAt: DateTime.now().subtract(const Duration(hours: 1)),
      expiresAt: DateTime.now().add(const Duration(hours: 23)),
    ),
  ];

  @override
  Stream<List<ManagedConversation>> watchConversations(String managedAccountId) {
    return Stream<List<ManagedConversation>>.value(const <ManagedConversation>[
      ManagedConversation(
        id: 'conv-1',
        managedAccountId: 'account-1',
        peerUid: 'peer-1',
        peerDisplayName: 'Peer Test',
        peerUsername: 'peertest',
        lastMessageText: 'Hello!',
        lastMessageAt: null,
      ),
      ManagedConversation(
        id: 'conv-2',
        managedAccountId: 'account-1',
        peerUid: 'peer-2',
        peerDisplayName: 'Anna',
        peerUsername: 'anna',
        lastMessageText: 'See you soon',
        lastMessageAt: null,
      ),
      ManagedConversation(
        id: 'conv-3',
        managedAccountId: 'account-1',
        peerUid: 'peer-3',
        peerDisplayName: 'Mike',
        peerUsername: 'mike',
        lastMessageText: 'Call me back',
        lastMessageAt: null,
      ),
    ]);
  }

  @override
  Stream<UserProfile?> watchPeerPresence(String peerUid) {
    return Stream<UserProfile?>.value(null);
  }

  @override
  Future<String> ensureConversation({
    required String managedAccountId,
    required String peerUid,
  }) async {
    return 'conv-1';
  }

  @override
  Future<void> sendMessage({
    required String conversationId,
    required String managedAccountId,
    required String senderUid,
    required String text,
    String? messageId,
    ManagedMessageType type = ManagedMessageType.text,
    String? mediaUrl,
    String? thumbnailUrl,
    int? durationMs,
    double? width,
    double? height,
    String? fileName,
    String? mimeType,
    int? sizeBytes,
    String? voiceEffect,
    String? replyToId,
    String? replyToType,
    String? replyToText,
    String? replyToSender,
    String? senderLang,
    String? originalText,
    String? sourceLang,
  }) async {}

  @override
  Future<void> deleteMessage({
    required String conversationId,
    required String messageId,
  }) async {}

  @override
  Stream<List<ManagedMessage>> watchMessages(String conversationId) {
    return Stream<List<ManagedMessage>>.value(const <ManagedMessage>[]);
  }

  @override
  Future<List<ManagedMessage>> fetchMessagesBefore(
    String conversationId,
    ManagedMessage before, {
    int limit = 50,
  }) async {
    return const <ManagedMessage>[];
  }

  @override
  Future<void> markConversationRead({
    required String conversationId,
    required String managedAccountId,
  }) async {}

  @override
  Future<void> markMessagesDelivered(
    String conversationId,
    List<String> messageIds,
  ) async {}

  @override
  Future<void> markMessagesRead(
    String conversationId,
    List<String> messageIds,
  ) async {}

  @override
  Future<void> setTyping(String conversationId) async {}

  @override
  Future<MediaUploadTask> uploadChatMedia({
    required String conversationId,
    required String messageId,
    required Uint8List bytes,
    required String contentType,
    required String fileName,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<MediaUploadTask> uploadChatThumbnail({
    required String conversationId,
    required String messageId,
    required Uint8List bytes,
    required String contentType,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ManagedCall> startCall({
    required String managedAccountId,
    required String conversationId,
    required String peerUid,
    required ManagedCallType type,
  }) async {
    final ManagedCall call = ManagedCall(
      id: 'mc-new',
      managedAccountId: managedAccountId,
      conversationId: conversationId,
      peerUid: peerUid,
      type: type,
      status: ManagedCallStatus.ringing,
      createdAt: DateTime.now(),
    );
    _calls.add(call);
    return call;
  }

  @override
  Stream<ManagedCall> watchCall(String callId) {
    return Stream<ManagedCall>.value(_calls.firstWhere(
      (ManagedCall c) => c.id == callId,
      orElse: () => _calls.first,
    ));
  }

  @override
  Future<ManagedCall?> fetchCall(String callId) async {
    return _calls.firstWhere(
      (ManagedCall c) => c.id == callId,
      orElse: () => _calls.first,
    );
  }

  @override
  Future<void> endCall({
    required String callId,
    required String byUid,
  }) async {}

  @override
  Future<void> answerCall(String callId) async {}

  @override
  Future<void> markMissed(String callId) async {}

  @override
  Future<void> declineCall(String callId) async {}

  @override
  Future<List<ManagedCall>> fetchCallHistory(String managedAccountId) async {
    return _calls;
  }

  @override
  Stream<void> watchCallChanges(String managedAccountId) {
    return Stream<void>.value(null);
  }

  @override
  Stream<List<ManagedStatusGroup>> watchStatuses(String managedAccountId) {
    return Stream<List<ManagedStatusGroup>>.value(<ManagedStatusGroup>[
      ManagedStatusGroup(
        managedAccountId: managedAccountId,
        statuses: _statuses,
      ),
    ]);
  }

  @override
  Future<String> postStatus({
    required String managedAccountId,
    required ManagedStatusType type,
    String text = '',
    String? statusId,
    String? mediaUrl,
    String? thumbnailUrl,
    int? durationMs,
    double? width,
    double? height,
    String? mimeType,
  }) async {
    return statusId ?? 'ms-new';
  }

  @override
  Future<MediaUploadTask> uploadStatusMedia({
    required String managedAccountId,
    required String statusId,
    required Uint8List bytes,
    required String contentType,
    required String fileName,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<MediaUploadTask> uploadStatusThumbnail({
    required String managedAccountId,
    required String statusId,
    required Uint8List bytes,
    required String contentType,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> markStatusViewed(String statusId) async {}

  @override
  Future<void> deleteStatus(String statusId) async {}

  @override
  Future<List<ManagedStatusViewer>> fetchStatusViewers(String statusId) async {
    return const <ManagedStatusViewer>[];
  }
}

class _FakeRingingChatRepository extends _FakeManagedChatRepository {
  @override
  Stream<ManagedCall> watchCall(String callId) {
    return Stream<ManagedCall>.value(ManagedCall(
      id: 'mc-ring',
      managedAccountId: 'account-1',
      conversationId: 'conv-1',
      peerUid: 'peer-1',
      type: ManagedCallType.video,
      status: ManagedCallStatus.ringing,
      createdAt: DateTime.now(),
    ));
  }

  @override
  Future<ManagedCall?> fetchCall(String callId) async {
    return ManagedCall(
      id: 'mc-ring',
      managedAccountId: 'account-1',
      conversationId: 'conv-1',
      peerUid: 'peer-1',
      type: ManagedCallType.video,
      status: ManagedCallStatus.ringing,
      createdAt: DateTime.now(),
    );
  }
}

class _FakeVoiceRecorder implements VoiceRecorder {
  @override
  Future<bool> ensurePermission() async => true;

  @override
  Future<void> startRecording() async {}

  @override
  Future<RecordedVoice?> stopRecording() async {
    return RecordedVoice(
      bytes: Uint8List.fromList(<int>[1, 2, 3]),
      durationMs: 2000,
      fileName: 'voice.m4a',
      mimeType: 'audio/mp4',
    );
  }

  @override
  Future<void> cancelRecording() async {}

  @override
  Future<void> dispose() async {}
}

class _FakeVideoPlayback implements VideoPlaybackController {
  @override
  Future<void> initialize() async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seekTo(Duration position) async {}

  @override
  Future<void> setLooping(bool looping) async {}

  @override
  Future<void> dispose() async {}

  @override
  bool get isInitialized => true;

  @override
  bool get isPlaying => false;

  @override
  Duration? get duration => const Duration(seconds: 5);

  @override
  ValueListenable<Duration> get position =>
      ValueNotifier<Duration>(Duration.zero);

  @override
  Widget buildView() => const SizedBox.shrink();
}