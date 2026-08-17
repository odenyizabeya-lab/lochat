import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/router/app_routes.dart';
import '../../core/utils/time_utils.dart';
import '../../features/chat/data/chat_ai_service.dart';
import '../../features/chat/data/chat_repository.dart';
import '../../features/chat/media/chat_media_picker.dart';
import '../../features/chat/media/media_playback.dart';
import '../../features/chat/media/voice_recorder.dart';
import '../../features/chat/models/chat_message.dart';
import '../../features/chat/widgets/bubble_frame.dart';
import '../../features/chat/widgets/chat_date_header.dart';
import '../../features/chat/widgets/media_message_bubble.dart';
import '../../features/chat/widgets/reply_preview.dart';
import '../../features/chat/widgets/voice_messages_player.dart';
import '../../features/chat/widgets/whatsapp_style.dart';
import '../../features/chat/widgets/whatsapp_wallpaper.dart';
import '../../features/profile/models/user_profile.dart';
import '../../shared/language_picker_dialog.dart';
import '../../shared/languages.dart';
import './managed_account_scope.dart';
import './managed_chat_controller.dart';
import './managed_chat_scope.dart';
import './models/managed_account.dart';
import './models/managed_call.dart';
import './models/managed_conversation.dart';
import './models/managed_message.dart';

enum _ManagedMessageAction { reply, copy, translate, delete }

enum _ManagedChatMenuAction { autoTranslate, changeLanguage }

class AdminManagedChatScreen extends StatefulWidget {
  const AdminManagedChatScreen({
    super.key,
    required this.conversationId,
    required this.managedAccountId,
  });

  final String conversationId;
  final String managedAccountId;

  @override
  State<AdminManagedChatScreen> createState() => _AdminManagedChatScreenState();
}

class _AdminManagedChatScreenState extends State<AdminManagedChatScreen> {
  ManagedChatController? _chat;
  List<ManagedMessage> _messages = <ManagedMessage>[];
  bool _loading = true;
  Object? _error;

  bool _hasMore = true;
  bool _loadingOlder = false;
  ManagedMessage? _oldestMessage;
  bool _followBottom = true;

  final ScrollController _scroll = ScrollController();
  StreamSubscription<List<ManagedMessage>>? _sub;
  StreamSubscription<List<ManagedConversation>>? _conversationsSub;
  StreamSubscription<UserProfile?>? _presenceSub;

  ManagedConversation? _conversation;
  UserProfile? _peerPresence;

  // Acknowledged message ids (delivered/read already sent).
  final Set<String> _ackedDelivered = <String>{};
  final Set<String> _ackedRead = <String>{};

  ManagedMessage? _replyTo;

  // ----- Auto-translate (incoming foreign-language messages) -----

  /// Admin-side translation master switch for this chat.
  bool _autoTranslate = true;

  /// Target language code for translations (defaults to English).
  String _targetLangCode = 'en';

  /// Message-id -> cached translation (never persisted).
  final Map<String, String> _translationCache = <String, String>{};

  /// Message ids currently being translated (avoid duplicate in-flight calls).
  final Set<String> _translationPending = <String>{};

  /// Message ids where the admin expanded "See original".
  final Set<String> _translationExpanded = <String>{};

  bool get _autoTranslateEnabled => _autoTranslate;

  String get _targetLangName => languageNameFor(_targetLangCode);

  String _translationKey(String messageId) => '$messageId|$_targetLangName';

  // ----- In-chat search -----
  bool _searching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Voice playback.
  final VoiceMessagesPlayer _voicePlayer = VoiceMessagesPlayer(DeviceVoicePlayer.new);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_chat != null) return;
    _chat = ManagedChatScope.of(context);
    _subscribe();
  }

  void _subscribe() {
    _sub = _chat!.watchMessages(widget.conversationId).listen(
          (List<ManagedMessage> messages) {
            if (!mounted) return;
            setState(() {
              _messages = messages;
              _loading = false;
            });
            _acknowledgeIncoming(messages);
            _maybeAutoTranslate(messages);
            _scrollToBottomIfFollowing();
          },
          onError: (Object e) {
            if (!mounted) return;
            setState(() {
              _error = e;
              _loading = false;
            });
          },
        );

    _conversationsSub = _chat!.watchConversations().listen(
          (List<ManagedConversation> conversations) {
            if (!mounted) return;
            ManagedConversation? found;
            for (final ManagedConversation c in conversations) {
              if (c.id == widget.conversationId) {
                found = c;
                break;
              }
            }
            setState(() => _conversation = found);
            _subscribePresence();
          },
        );
  }

  /// Marks the chat as read on open and ack's incoming messages so the peer's
  /// ticks advance (delivered -> read) exactly like the user chat room.
  void _acknowledgeIncoming(List<ManagedMessage> messages) {
    final ManagedChatController? chat = _chat;
    if (chat == null) return;

    chat.markConversationRead(widget.conversationId);

    final List<String> delivered = <String>[];
    final List<String> read = <String>[];
    for (final ManagedMessage message in messages) {
      if (message.senderUid == widget.managedAccountId) continue;
      if (message.type == ManagedMessageType.text && (message.text ?? '').isEmpty) {
        continue;
      }
      if (!_ackedDelivered.contains(message.id)) {
        _ackedDelivered.add(message.id);
        delivered.add(message.id);
      }
      if (!_ackedRead.contains(message.id)) {
        _ackedRead.add(message.id);
        read.add(message.id);
      }
    }
    if (delivered.isNotEmpty) {
      unawaited(chat.markMessagesDelivered(widget.conversationId, delivered));
    }
    if (read.isNotEmpty) {
      unawaited(chat.markMessagesRead(widget.conversationId, read));
    }
  }

  // ---------------------------------------------------------------------
  // Auto-translate (incoming foreign-language messages)
  // ---------------------------------------------------------------------

  /// Queues device-side translations for incoming text messages whose stamped
  /// language differs from the admin's target language. The stamp means no AI
  /// language detection is needed, so this costs nothing for same-language
  /// messages.
  void _maybeAutoTranslate(List<ManagedMessage> messages) {
    final ManagedChatController? chat = _chat;
    if (chat == null) return;
    if (!_autoTranslateEnabled) return;
    final String targetLang = _targetLangCode;
    if (targetLang.isEmpty) return;

    final List<ManagedMessage> toTranslate = <ManagedMessage>[];
    for (final ManagedMessage message in messages) {
      if (message.senderUid == widget.managedAccountId) continue;
      if (message.type != ManagedMessageType.text) continue;
      if ((message.text ?? '').trim().isEmpty) continue;
      if (message.originalText != null &&
          message.originalText!.isNotEmpty) {
        continue; // already translated by the sender
      }
      final String? senderLang = message.senderLang;
      if (senderLang == null || senderLang.isEmpty) continue;
      if (senderLang.toLowerCase() == targetLang.toLowerCase()) continue;
      if (_translationCache.containsKey(_translationKey(message.id))) continue;
      if (_translationPending.contains(message.id)) continue;
      toTranslate.add(message);
    }
    if (toTranslate.isEmpty) return;
    unawaited(_translateMessages(toTranslate));
  }

  Future<void> _translateMessages(List<ManagedMessage> messages) async {
    final ManagedChatController? chat = _chat;
    if (chat == null) return;
    final String target = _targetLangName;
    for (final ManagedMessage message in messages) {
      if (_translationPending.contains(message.id)) continue;
      _translationPending.add(message.id);
      try {
        final TextTranslationResult result = await chat.chatAi.translateText(
          text: message.text ?? '',
          targetLanguage: target,
        );
        if (!mounted) return;
        if (result.translation.trim().isNotEmpty) {
          setState(() {
            _translationCache[_translationKey(message.id)] =
                result.translation;
          });
        }
      } on Exception {
        // Leave the message as written; the long-press Translate action is
        // the manual fallback.
      } finally {
        _translationPending.remove(message.id);
      }
    }
  }

  /// Fetches translations for messages already on screen (used when the admin
  /// turns auto-translate back on or switches the target language).
  Future<void> _translatePendingOnEnable() async {
    if (!_autoTranslateEnabled) return;
    final ManagedChatController? chat = _chat;
    if (chat == null) return;
    final List<ManagedMessage> messages = List<ManagedMessage>.of(_messages);
    // Small delay so the toggle tap registers before the AI calls stream in.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    _maybeAutoTranslate(messages);
  }

  /// Whether the peer's [message] should currently render its (cached)
  /// translation instead of the original wording.
  bool _showsTranslation(ManagedMessage message) {
    if (message.originalText != null && message.originalText!.isNotEmpty) {
      return false;
    }
    if (!_autoTranslateEnabled) return false;
    if (message.senderUid == widget.managedAccountId) return false;
    final String? senderLang = message.senderLang;
    if (senderLang == null || senderLang.isEmpty) return false;
    if (_targetLangCode.isEmpty) return false;
    if (senderLang.toLowerCase() == _targetLangCode.toLowerCase()) {
      return false;
    }
    return _translationCache.containsKey(_translationKey(message.id));
  }

  /// Manual fallback: translate a single text message into the current target
  /// language (used from the long-press menu).
  Future<void> _translateMessage(ManagedMessage message) async {
    final ManagedChatController? chat = _chat;
    if (chat == null) return;
    if (message.type != ManagedMessageType.text) return;
    if (_translationPending.contains(message.id)) return;
    _translationPending.add(message.id);
    try {
      final TextTranslationResult result = await chat.chatAi.translateText(
        text: message.text ?? '',
        targetLanguage: _targetLangName,
      );
      if (!mounted) return;
      if (result.translation.trim().isNotEmpty) {
        setState(() {
          _translationCache[_translationKey(message.id)] =
              result.translation;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not translate that message.')),
        );
      }
    } on ChatAiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } on Exception {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not translate that message.')),
      );
    } finally {
      _translationPending.remove(message.id);
    }
  }

  Future<void> _toggleAutoTranslate() async {
    setState(() {
      _autoTranslate = !_autoTranslate;
      _translationExpanded.clear();
    });
    if (_autoTranslate) {
      unawaited(_translatePendingOnEnable());
    } else {
      // Drop cached translations so the messages render as written.
      setState(_translationCache.clear);
    }
  }

  Future<void> _changeTargetLanguage() async {
    final Language? picked = await showLanguagePicker(
      context,
      title: 'Translate to',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _targetLangCode = picked.code;
      // Cached translations target the old language: drop them.
      _translationCache.clear();
      _translationExpanded.clear();
    });
    unawaited(_translatePendingOnEnable());
  }

  void _subscribePresence() {
    final ManagedConversation? conversation = _conversation;
    final ManagedChatController? chat = _chat;
    if (conversation == null || chat == null) return;
    final String peerUid = conversation.peerUid;
    if (peerUid.isEmpty) return;
    _presenceSub?.cancel();
    _presenceSub = chat.watchPeerPresence(peerUid).listen((UserProfile? profile) {
      if (!mounted) return;
      setState(() => _peerPresence = profile);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _conversationsSub?.cancel();
    _presenceSub?.cancel();
    _searchController.dispose();
    _voicePlayer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottomIfFollowing() {
    if (!_followBottom) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _scrollToMessage(String messageId) {
    final int index =
        _messages.indexWhere((ManagedMessage m) => m.id == messageId);
    if (index < 0 || !_scroll.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final double offset = _offsetForEntry(index);
      _scroll.animateTo(
        (offset - 80).clamp(0, _scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  double _offsetForEntry(int index) {
    const double itemExtent = 72;
    return index * itemExtent;
  }

  Future<void> _loadOlder() async {
    final ManagedChatController? chat = _chat;
    final ManagedMessage? before =
        _oldestMessage ?? (_messages.isEmpty ? null : _messages.first);
    if (chat == null || before == null || _loadingOlder || !_hasMore) return;
    _loadingOlder = true;
    try {
      final List<ManagedMessage> older = await chat.fetchMessagesBefore(
        widget.conversationId,
        before,
      );
      if (!mounted) return;
      setState(() {
        if (older.isNotEmpty) {
          _messages = <ManagedMessage>[...older, ..._messages];
          _oldestMessage = older.first;
        } else {
          _hasMore = false;
        }
        _loadingOlder = false;
      });
    } on Exception {
      if (!mounted) return;
      setState(() => _loadingOlder = false);
    }
  }

  // ---------------------------------------------------------------------
  // Message actions (reply / copy / delete)
  // ---------------------------------------------------------------------

  Future<void> _showMessageActions(ManagedMessage message, bool fromMe) async {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool isText = message.type == ManagedMessageType.text;

    final _ManagedMessageAction? action =
        await showModalBottomSheet<_ManagedMessageAction>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _ActionTile(
                icon: Icons.reply_rounded,
                label: 'Reply',
                value: _ManagedMessageAction.reply,
              ),
              if (isText)
                _ActionTile(
                  icon: Icons.copy_rounded,
                  label: 'Copy text',
                  value: _ManagedMessageAction.copy,
                ),
              if (isText)
                _ActionTile(
                  icon: Icons.translate_rounded,
                  label: 'Translate',
                  value: _ManagedMessageAction.translate,
                ),
              _ActionTile(
                icon: Icons.delete_outline_rounded,
                label: 'Delete for everyone',
                value: _ManagedMessageAction.delete,
                color: scheme.error,
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (action == null || !mounted) return;

    switch (action) {
      case _ManagedMessageAction.reply:
        setState(() {
          _replyTo = message;
          _scrollToBottomIfFollowing();
        });
      case _ManagedMessageAction.copy:
        if (message.text != null && message.text!.isNotEmpty) {
          await Clipboard.setData(ClipboardData(text: message.text!));
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Message copied')),
            );
          }
        }
      case _ManagedMessageAction.translate:
        await _translateMessage(message);
      case _ManagedMessageAction.delete:
        await _confirmDelete(message);
    }
  }

  Future<void> _confirmDelete(ManagedMessage message) async {
    final ThemeData theme = Theme.of(context);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text(
          'This message will be removed for everyone in this chat.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final ManagedChatController? chat = _chat;
    if (chat == null) return;
    try {
      await chat.deleteMessage(
        conversationId: widget.conversationId,
        messageId: message.id,
      );
    } on Exception {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete the message.')),
      );
    }
  }

  String? _replyToLabel(ManagedMessage? message) {
    if (message == null) return null;
    final bool fromMe = message.senderUid == widget.managedAccountId;
    return fromMe
        ? (ManagedAccountScope.of(context).selectedAccount?.displayName ?? 'You')
        : 'Peer';
  }

  /// Sender name stored on a sent reply (visible to the peer).
  String? _replyToSender(ManagedMessage? message) {
    if (message == null) return null;
    if (message.senderUid == widget.managedAccountId) {
      final String name =
          ManagedAccountScope.of(context).selectedAccount?.displayName ?? '';
      return name.isNotEmpty ? name : 'You';
    }
    return 'Peer';
  }

  // ---------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final WhatsAppStyle style = WhatsAppStyle.of(context);
    final ManagedAccount? account = ManagedAccountScope.of(context).selectedAccount;

    return Scaffold(
      appBar: _buildAppBar(context, style, account),
      body: SafeArea(
        child: WhatsAppWallpaper(
          child: Column(
            children: <Widget>[
              Expanded(child: _buildMessages(context)),
              _ManagedChatComposer(
                conversationId: widget.conversationId,
                chat: _chat!,
                replyTo: _replyTo,
                replyToLabel: _replyToLabel(_replyTo),
                replyToSender: _replyToSender(_replyTo),
                onReplyCleared: () => setState(() => _replyTo = null),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Presence line shown under the header name: typing, online, or last seen.
  String _presenceLine() {
    final ManagedConversation? conversation = _conversation;
    final String handle = conversation?.peerHandle ?? '';
    final bool peerTyping = _isPeerTyping(conversation);
    if (peerTyping) {
      return '$handle \u00b7 typing\u2026';
    }
    final UserProfile? presence = _peerPresence;
    if (presence != null && presence.isOnline) {
      return '$handle \u00b7 Online';
    }
    return handle.isEmpty
        ? 'Online'
        : '$handle \u00b7 ${formatLastSeen(presence?.lastSeen)}';
  }

  bool _isPeerTyping(ManagedConversation? conversation) {
    if (conversation == null) return false;
    final String? typingUid = conversation.typingUid;
    final DateTime? until = conversation.typingUntil;
    if (typingUid == null || typingUid.isEmpty || until == null) return false;
    return until.isAfter(DateTime.now());
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    WhatsAppStyle style,
    ManagedAccount? account,
  ) {
    if (_searching) {
      return AppBar(
        backgroundColor: style.header,
        foregroundColor: Colors.white,
        titleSpacing: 0,
        leading: IconButton(
          tooltip: 'Close search',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            _searchController.clear();
            setState(() {
              _searching = false;
              _searchQuery = '';
            });
          },
        ),
        title: TextField(
          controller: _searchController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          cursorColor: Colors.white,
          decoration: InputDecoration(
            hintText: 'Search messages',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
          ),
          onChanged: (String value) => setState(() => _searchQuery = value),
        ),
      );
    }

    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: Container(
        decoration: BoxDecoration(
          color: style.header,
          border: Border(
            bottom: BorderSide(color: Colors.black.withValues(alpha: 0.12)),
          ),
        ),
        child: AppBar(
          backgroundColor: style.header,
          foregroundColor: style.onHeader,
          elevation: 0,
          titleSpacing: 0,
          title: Row(
            children: <Widget>[
              CircleAvatar(
                radius: 19,
                backgroundImage: account?.photoUrl != null
                    ? NetworkImage(account!.photoUrl!)
                    : null,
                backgroundColor: const Color(0xFF6A7A85),
                foregroundColor: Colors.white,
                child: account?.photoUrl == null
                    ? Text(
                        account?.displayName.isNotEmpty == true
                            ? account!.displayName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(fontSize: 18),
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      _conversation?.peerDisplayName.isNotEmpty == true
                          ? _conversation!.peerDisplayName
                          : (account?.displayName ?? 'Chat'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      _presenceLine(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _isPeerTyping(_conversation)
                            ? const Color(0xFFA7F3D0)
                            : style.onHeaderSub,
                        fontSize: 12.5,
                        fontStyle: _isPeerTyping(_conversation)
                            ? FontStyle.italic
                            : FontStyle.normal,
                        fontWeight: _isPeerTyping(_conversation)
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: <Widget>[
            IconButton(
              tooltip: 'Voice call',
              icon: const Icon(Icons.call_rounded, color: Colors.white),
              onPressed: () => unawaited(_startCall(false)),
            ),
            IconButton(
              tooltip: 'Video call',
              icon: const Icon(Icons.videocam_rounded, color: Colors.white),
              onPressed: () => unawaited(_startCall(true)),
            ),
            IconButton(
              tooltip: 'Search',
              icon: const Icon(Icons.search_rounded, color: Colors.white),
              onPressed: () => setState(() => _searching = true),
            ),
            PopupMenuButton<_ManagedChatMenuAction>(
              tooltip: 'More options',
              icon: Icon(Icons.more_vert_rounded, color: style.onHeader),
              onSelected: (action) => _onChatMenuSelected(action),
              itemBuilder: (BuildContext context) =>
                  <PopupMenuEntry<_ManagedChatMenuAction>>[
                PopupMenuItem<_ManagedChatMenuAction>(
                  value: _ManagedChatMenuAction.autoTranslate,
                  child: Row(
                    children: <Widget>[
                      Icon(
                        _autoTranslateEnabled
                            ? Icons.translate_rounded
                            : Icons.translate_outlined,
                        color: _autoTranslateEnabled
                            ? Colors.black
                            : Colors.black45,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _autoTranslateEnabled
                            ? 'Auto-translate on'
                            : 'Auto-translate off',
                      ),
                    ],
                  ),
                ),
                PopupMenuItem<_ManagedChatMenuAction>(
                  value: _ManagedChatMenuAction.changeLanguage,
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.language_rounded),
                      const SizedBox(width: 12),
                      Text('Translate to: $_targetLangName'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _onChatMenuSelected(_ManagedChatMenuAction action) {
    switch (action) {
      case _ManagedChatMenuAction.autoTranslate:
        unawaited(_toggleAutoTranslate());
      case _ManagedChatMenuAction.changeLanguage:
        unawaited(_changeTargetLanguage());
    }
  }

  Future<void> _startCall(bool video) async {
    final ManagedConversation? conversation = _conversation;
    if (conversation == null || _chat == null) return;
    try {
      final ManagedCall call = await _chat!.startCall(
        conversationId: widget.conversationId,
        peerUid: conversation.peerUid,
        type: video ? ManagedCallType.video : ManagedCallType.audio,
      );
      if (!mounted) return;
      context.push(AppRoutes.adminCall, extra: <String, dynamic>{
        'callId': call.id,
        'conversationId': widget.conversationId,
        'managedAccountId': widget.managedAccountId,
        'peerName': conversation.peerDisplayName.isNotEmpty
            ? conversation.peerDisplayName
            : conversation.peerUsername,
        'peerPhotoUrl': conversation.peerPhotoUrl,
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start the call. Try again.')),
      );
    }
  }

  Widget _buildMessages(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final WhatsAppStyle style = WhatsAppStyle.of(context);

    if (_loading) {
      return const LoadingView(message: 'Loading messages\u2026');
    }
    if (_error != null) {
      return ErrorView(
        title: 'Could not load messages',
        message: 'Check your connection and try again.',
        onRetry: () {
          _sub?.cancel();
          _loading = true;
          _error = null;
          _subscribe();
          setState(() {});
        },
      );
    }
    if (_messages.isEmpty) {
      return _buildEmptyState(theme, style);
    }

    final List<Object> entries = _buildEntries();
    final bool searching = _searching && _searchQuery.trim().isNotEmpty;

    if (searching) {
      final String query = _searchQuery.trim().toLowerCase();
      final List<ManagedMessage> matches = _messages
          .where((ManagedMessage m) =>
              m.type == ManagedMessageType.text &&
              (m.text ?? '').toLowerCase().contains(query))
          .toList();
      if (matches.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.search_off_rounded, size: 56, color: style.meta),
                const SizedBox(height: 16),
                Text(
                  'No messages found',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        );
      }
      return ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        itemCount: matches.length,
        itemBuilder: (BuildContext context, int index) =>
            _buildBubble(context, matches[index]),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification notification) {
        if (notification.metrics.axis == Axis.vertical) _onScroll();
        return false;
      },
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        itemCount: entries.length + (_hasMore ? 1 : 0),
        itemBuilder: (BuildContext context, int index) {
          if (_hasMore && index == 0) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: _loadingOlder
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const SizedBox(width: 20, height: 20),
              ),
            );
          }
          final Object entry = entries[index - (_hasMore ? 1 : 0)];
          if (entry is DateTime) {
            return ChatDateHeader(day: entry);
          }
          if (entry is String) {
            return _buildEncryptionNotice();
          }
          if (entry is ManagedMessage) {
            return _buildBubble(context, entry);
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  /// Builds the list entries: encryption notice, then messages with date
  /// separators in between.
  List<Object> _buildEntries() {
    final List<Object> entries = <Object>['encryption'];
    DateTime? lastDay;
    for (final ManagedMessage message in _messages) {
      final DateTime day = DateTime(
        message.createdAt.year,
        message.createdAt.month,
        message.createdAt.day,
      );
      if (lastDay == null || !ChatDateHeader.isSameDay(lastDay, day)) {
        entries.add(day);
        lastDay = day;
      }
      entries.add(message);
    }
    return entries;
  }

  Widget _buildEncryptionNotice() {
    final WhatsAppStyle style = WhatsAppStyle.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 10, 28, 2),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.shield_outlined,
                size: 15,
                color: style.isDark
                    ? const Color(0xFF8696A0)
                    : const Color(0xFF1C7A63),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Messages are stored securely on LoText servers and '
                  'protected with access controls. This chat is private to '
                  'you and your contact. End-to-end encryption is coming '
                  'soon.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: style.isDark
                        ? const Color(0xFF8696A0)
                        : const Color(0xFF1C7A63),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBubble(BuildContext context, ManagedMessage message) {
    final bool fromMe = message.senderUid == widget.managedAccountId;
    return switch (message.type) {
      ManagedMessageType.text => _ManagedTextBubble(
          message: message,
          fromMe: fromMe,
          onLongPress: () => _showMessageActions(message, fromMe),
          onReplyTap: message.replyToId == null
              ? null
              : () => _scrollToMessage(message.replyToId!),
          autoTranslation:
              _showsTranslation(message) && !_translationExpanded.contains(message.id)
                  ? _translationCache[_translationKey(message.id)]
                  : null,
          autoTranslationLabel: message.senderLang == null
              ? null
              : 'Translated from ${languageNameFor(message.senderLang)}',
          showOriginal: _translationExpanded.contains(message.id),
          onToggleOriginal: () => setState(() {
            if (!_translationExpanded.add(message.id)) {
              _translationExpanded.remove(message.id);
            }
          }),
        ),
      ManagedMessageType.image => _ManagedImageBubble(
          message: message,
          fromMe: fromMe,
          onLongPress: () => _showMessageActions(message, fromMe),
          onReplyTap: message.replyToId == null
              ? null
              : () => _scrollToMessage(message.replyToId!),
        ),
      ManagedMessageType.video => _ManagedVideoBubble(
          message: message,
          fromMe: fromMe,
          onLongPress: () => _showMessageActions(message, fromMe),
          onReplyTap: message.replyToId == null
              ? null
              : () => _scrollToMessage(message.replyToId!),
        ),
      ManagedMessageType.voice => _ManagedVoiceBubble(
          message: message,
          fromMe: fromMe,
          player: _voicePlayer,
          onLongPress: () => _showMessageActions(message, fromMe),
          onReplyTap: message.replyToId == null
              ? null
              : () => _scrollToMessage(message.replyToId!),
        ),
    };
  }

  Widget _buildEmptyState(ThemeData theme, WhatsAppStyle style) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.waving_hand_rounded, size: 56, color: style.meta),
            const SizedBox(height: 16),
            Text(
              'Say Hi',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            _buildEncryptionNotice(),
          ],
        ),
      ),
    );
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final ScrollPosition position = _scroll.position;
    _followBottom = position.pixels >= position.maxScrollExtent - 120;
    if (position.pixels < 200) {
      unawaited(_loadOlder());
    }
  }
}

// ---------------------------------------------------------------------
// Managed message bubbles (WhatsApp-style)
// ---------------------------------------------------------------------

class _ManagedTextBubble extends StatelessWidget {
  const _ManagedTextBubble({
    required this.message,
    required this.fromMe,
    this.onLongPress,
    this.onReplyTap,
    this.autoTranslation,
    this.autoTranslationLabel,
    this.showOriginal = false,
    this.onToggleOriginal,
  });

  final ManagedMessage message;
  final bool fromMe;
  final VoidCallback? onLongPress;
  final VoidCallback? onReplyTap;

  /// Device-side translation of a foreign-language incoming message, or null
  /// when the message is shown as written.
  final String? autoTranslation;

  /// Label for [autoTranslation], e.g. "Translated from Spanish".
  final String? autoTranslationLabel;

  /// Whether to show the original wording instead of the translation.
  final bool showOriginal;

  /// Toggles [showOriginal] for the peer's own translate-before-send
  /// messages (which carry [ManagedMessage.originalText]).
  final VoidCallback? onToggleOriginal;

  @override
  Widget build(BuildContext context) {
    final WhatsAppStyle style = WhatsAppStyle.of(context);
    final bool hasReply = message.replyToId != null;

    String displayText = message.text ?? '';
    String? note;
    bool canToggle = false;

    if (autoTranslation != null) {
      canToggle = true;
      note = autoTranslationLabel;
      displayText = showOriginal ? (message.text ?? '') : autoTranslation!;
    } else if (message.originalText != null &&
        message.originalText!.isNotEmpty) {
      canToggle = true;
      if (showOriginal) {
        displayText = message.originalText!;
      } else {
        note = message.sourceLang == null
            ? 'Translated'
            : 'Translated from ${languageNameFor(message.sourceLang)}';
      }
    }

    return BubbleFrame(
      fromMe: fromMe,
      bubbleColor: bubbleColorFor(style, fromMe),
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment:
            fromMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (hasReply) ...<Widget>[
            ReplyPreview(
              senderName: message.replyToSender ?? 'Message',
              preview: replyPreviewFromFields(
                  message.replyToType, message.replyToText),
              isOutgoing: fromMe,
              onTap: onReplyTap,
            ),
            const SizedBox(height: 2),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              displayText,
              style: TextStyle(
                color: style.text,
                fontSize: 15.5,
                height: 1.3,
              ),
            ),
          ),
          if (canToggle) ...<Widget>[
            const SizedBox(height: 4),
            InkWell(
              onTap: onToggleOriginal,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                child: Text(
                  showOriginal
                      ? 'Show translation'
                      : '${note ?? 'Translated'} \u00b7 See original',
                  style: TextStyle(
                    color: style.replyAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                    decorationColor: style.replyAccent,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 3),
          _ManagedBubbleFooter(message: message, fromMe: fromMe, style: style),
        ],
      ),
    );
  }
}

class _ManagedImageBubble extends StatelessWidget {
  const _ManagedImageBubble({
    required this.message,
    required this.fromMe,
    this.onLongPress,
    this.onReplyTap,
  });

  final ManagedMessage message;
  final bool fromMe;
  final VoidCallback? onLongPress;
  final VoidCallback? onReplyTap;

  static const double _bubbleWidth = 230;
  static const double _bubbleHeight = 270;

  @override
  Widget build(BuildContext context) {
    final WhatsAppStyle style = WhatsAppStyle.of(context);
    final String? url = message.mediaUrl;
    final bool hasReply = message.replyToId != null;

    return BubbleFrame(
      fromMe: fromMe,
      bubbleColor: bubbleColorFor(style, fromMe),
      onLongPress: onLongPress,
      padding: const EdgeInsets.all(4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (hasReply) ...<Widget>[
            Padding(
              padding: const EdgeInsets.only(left: 4, right: 4, top: 2),
              child: ReplyPreview(
                senderName: message.replyToSender ?? 'Message',
                preview: replyPreviewFromFields(
                    message.replyToType, message.replyToText),
                isOutgoing: fromMe,
                onTap: onReplyTap,
              ),
            ),
            const SizedBox(height: 4),
          ],
          ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: url == null
                ? const _MissingMedia()
                : Stack(
                    children: <Widget>[
                      Positioned.fill(
                        child: GestureDetector(
                          onTap: () => context.push(
                            AppRoutes.photoViewer,
                            extra: <String, dynamic>{
                              'url': url,
                              'id': message.id,
                            },
                          ),
                          child: MediaImage(
                            url: url,
                            width: _bubbleWidth,
                            height: _bubbleHeight,
                          ),
                        ),
                      ),
                      Positioned(
                        right: 8,
                        bottom: 6,
                        child: _ManagedBubbleFooter(
                          message: message,
                          fromMe: fromMe,
                          style: style,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _ManagedVideoBubble extends StatelessWidget {
  const _ManagedVideoBubble({
    required this.message,
    required this.fromMe,
    this.onLongPress,
    this.onReplyTap,
  });

  final ManagedMessage message;
  final bool fromMe;
  final VoidCallback? onLongPress;
  final VoidCallback? onReplyTap;

  static const double _bubbleWidth = 230;
  static const double _bubbleHeight = 270;

  @override
  Widget build(BuildContext context) {
    final WhatsAppStyle style = WhatsAppStyle.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String? url = message.mediaUrl;
    final String? thumb = message.thumbnailUrl;
    final bool hasReply = message.replyToId != null;

    return BubbleFrame(
      fromMe: fromMe,
      bubbleColor: bubbleColorFor(style, fromMe),
      onLongPress: onLongPress,
      padding: const EdgeInsets.all(4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (hasReply) ...<Widget>[
            Padding(
              padding: const EdgeInsets.only(left: 4, right: 4, top: 2),
              child: ReplyPreview(
                senderName: message.replyToSender ?? 'Message',
                preview: replyPreviewFromFields(
                    message.replyToType, message.replyToText),
                isOutgoing: fromMe,
                onTap: onReplyTap,
              ),
            ),
            const SizedBox(height: 4),
          ],
          ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: url == null
                ? const _MissingMedia()
                : Stack(
                    children: <Widget>[
                      Positioned.fill(
                        child: GestureDetector(
                          onTap: () => context.push(
                            AppRoutes.videoPlayer,
                            extra: <String, dynamic>{
                              'url': url,
                              'messageId': message.id,
                            },
                          ),
                          child: thumb != null
                              ? MediaImage(
                                  url: thumb,
                                  width: _bubbleWidth,
                                  height: _bubbleHeight,
                                )
                              : Container(
                                  width: _bubbleWidth,
                                  height: _bubbleHeight,
                                  color: scheme.surfaceContainerHighest,
                                  child: Icon(
                                    Icons.play_circle_outline_rounded,
                                    color: scheme.onSurfaceVariant,
                                    size: 56,
                                  ),
                                ),
                        ),
                      ),
                      Positioned(
                        right: 8,
                        bottom: 6,
                        child: _ManagedBubbleFooter(
                          message: message,
                          fromMe: fromMe,
                          style: style,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Voice bubble mirroring the user chat's player-driven bubble, but for
/// [ManagedMessage].
class _ManagedVoiceBubble extends StatelessWidget {
  const _ManagedVoiceBubble({
    required this.message,
    required this.fromMe,
    required this.player,
    this.onLongPress,
    this.onReplyTap,
  });

  final ManagedMessage message;
  final bool fromMe;
  final VoiceMessagesPlayer player;
  final VoidCallback? onLongPress;
  final VoidCallback? onReplyTap;

  @override
  Widget build(BuildContext context) {
    final WhatsAppStyle style = WhatsAppStyle.of(context);
    final Color foreground = style.text;
    final Color bubble = bubbleColorFor(style, fromMe);
    final bool hasReply = message.replyToId != null;
    final Duration messageDuration =
        Duration(milliseconds: message.durationMs ?? 0);

    return BubbleFrame(
      fromMe: fromMe,
      bubbleColor: bubble,
      onLongPress: onLongPress,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (hasReply) ...<Widget>[
            ReplyPreview(
              senderName: message.replyToSender ?? 'Message',
              preview:
                  replyPreviewFromFields(message.replyToType, message.replyToText),
              isOutgoing: fromMe,
              onTap: onReplyTap,
            ),
            const SizedBox(height: 4),
          ],
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _PlayButton(
                foreground: foreground,
                active: player.isActive(message.id),
                playing: player.playing,
                loading: player.loading,
                onTap: () {
                  final String? url = message.mediaUrl;
                  if (url == null) return;
                  unawaited(player.toggle(messageId: message.id, url: url));
                },
              ),
              const SizedBox(width: 8),
              _ManagedWaveform(
                seed: message.id.hashCode,
                active: player.isActive(message.id),
                progress: player.isActive(message.id)
                    ? _progress(messageDuration)
                    : 0,
                foreground: foreground,
                tinted: bubble,
              ),
              const SizedBox(width: 8),
              _ManagedDurationText(
                active: player.isActive(message.id),
                position: player.position,
                total: messageDuration,
                color: foreground,
              ),
            ],
          ),
          const SizedBox(height: 2),
          _ManagedBubbleFooter(message: message, fromMe: fromMe, style: style),
        ],
      ),
    );
  }

  double _progress(Duration total) {
    if (total.inMilliseconds <= 0) return 0;
    final double raw = player.position.inMilliseconds / total.inMilliseconds;
    return raw.clamp(0, 1);
  }
}

/// Circular play/pause (or loading spinner) button for the voice bubble.
class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.foreground,
    required this.active,
    required this.playing,
    required this.loading,
    required this.onTap,
  });

  final Color foreground;
  final bool active;
  final bool playing;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color fill = foreground.withValues(alpha: 0.18);
    Widget child;
    if (loading) {
      child = SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2.4,
          color: foreground,
        ),
      );
    } else {
      child = Icon(
        active && playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
        color: foreground,
        size: 28,
      );
    }
    return InkResponse(
      onTap: onTap,
      radius: 24,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
        child: Center(child: child),
      ),
    );
  }
}

/// Decorative waveform bars; the played portion is filled in [foreground].
class _ManagedWaveform extends StatelessWidget {
  const _ManagedWaveform({
    required this.seed,
    required this.active,
    required this.progress,
    required this.foreground,
    required this.tinted,
  });

  final int seed;
  final bool active;
  final double progress;
  final Color foreground;
  final Color tinted;

  static const int _barCount = 26;

  @override
  Widget build(BuildContext context) {
    final List<double> heights = _heightsFor(seed);
    final int playedBars =
        active ? (progress * _barCount).round().clamp(0, _barCount) : 0;

    return SizedBox(
      width: 92,
      height: 26,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List<Widget>.generate(_barCount, (int index) {
          final bool played = index < playedBars;
          return Container(
            width: 2.2,
            height: heights[index],
            decoration: BoxDecoration(
              color: played ? foreground : tinted.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(1),
            ),
          );
        }),
      ),
    );
  }

  List<double> _heightsFor(int seed) {
    final math.Random random = math.Random(seed);
    return List<double>.generate(
      _barCount,
      (int index) => 5 + (random.nextDouble() * 13),
    );
  }
}

/// Shows the elapsed/total duration while active, otherwise the total.
class _ManagedDurationText extends StatelessWidget {
  const _ManagedDurationText({
    required this.active,
    required this.position,
    required this.total,
    required this.color,
  });

  final bool active;
  final Duration position;
  final Duration total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final Duration shown = active ? position : total;
    return Text(
      formatDuration(shown),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
    );
  }
}

/// Time + delivery ticks (single / double / blue double) inside the bubble.
class _ManagedBubbleFooter extends StatelessWidget {
  const _ManagedBubbleFooter({
    required this.message,
    required this.fromMe,
    required this.style,
  });

  final ManagedMessage message;
  final bool fromMe;
  final WhatsAppStyle style;

  @override
  Widget build(BuildContext context) {
    final Color tickColor = message.status == ManagedMessageStatus.read
        ? style.readTick
        : style.meta;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          formatChatTime(message.createdAt),
          style: TextStyle(color: style.meta, fontSize: 11.5),
        ),
        if (fromMe) ...<Widget>[
          const SizedBox(width: 4),
          Icon(
            message.status == ManagedMessageStatus.read ||
                    message.status == ManagedMessageStatus.delivered
                ? Icons.done_all_rounded
                : Icons.done_rounded,
            size: 14,
            color: tickColor,
          ),
        ],
      ],
    );
  }
}

class _MissingMedia extends StatelessWidget {
  const _MissingMedia();

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      width: 230,
      height: 270,
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(
        Icons.broken_image_outlined,
        color: scheme.onSurfaceVariant,
        size: 40,
      ),
    );
  }
}

// ---------------------------------------------------------------------
// WhatsApp-style composer
// ---------------------------------------------------------------------

enum _PickKind { image, video }

class _ComposerAttachment {
  const _ComposerAttachment({
    required this.messageId,
    required this.type,
    required this.bytes,
    required this.contentType,
    required this.fileName,
    this.thumbnailBytes,
    this.durationMs,
    this.width,
    this.height,
    this.sizeBytes,
    required this.label,
    this.previewBytes,
  });

  final String messageId;
  final MessageType type;
  final Uint8List bytes;
  final String contentType;
  final String fileName;
  final Uint8List? thumbnailBytes;
  final int? durationMs;
  final double? width;
  final double? height;
  final int? sizeBytes;
  final String label;
  final Uint8List? previewBytes;
}

class _ManagedChatComposer extends StatefulWidget {
  const _ManagedChatComposer({
    required this.conversationId,
    required this.chat,
    this.replyTo,
    this.replyToLabel,
    this.replyToSender,
    this.onReplyCleared,
  });

  final String conversationId;
  final ManagedChatController chat;
  final ManagedMessage? replyTo;
  final String? replyToLabel;
  final String? replyToSender;
  final VoidCallback? onReplyCleared;

  @override
  State<_ManagedChatComposer> createState() => _ManagedChatComposerState();
}

class _ManagedChatComposerState extends State<_ManagedChatComposer> {
  final TextEditingController _input = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  bool _canSend = false;
  bool _emojiOpen = false;
  final List<String> _recentEmojis = <String>[];

  _ComposerAttachment? _attachment;
  bool _uploading = false;
  double? _uploadProgress;
  MediaUploadTask? _uploadTask;
  StreamSubscription<double>? _progressSub;

  // Voice recording state.
  bool _recording = false;
  bool _cancelArmed = false;
  int _recordElapsedSeconds = 0;
  Timer? _recordTimer;

  DateTime _lastTypingSignalAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _input.addListener(_onInputChanged);
    _inputFocus.addListener(_onInputFocusChanged);
  }

  @override
  void dispose() {
    _input.removeListener(_onInputChanged);
    _inputFocus.removeListener(_onInputFocusChanged);
    _progressSub?.cancel();
    _recordTimer?.cancel();
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _onInputFocusChanged() {
    if (_inputFocus.hasFocus && _emojiOpen && mounted) {
      setState(() => _emojiOpen = false);
    }
  }

  void _onInputChanged() {
    final bool canSend = _input.text.trim().isNotEmpty;
    if (canSend != _canSend) setState(() => _canSend = canSend);
    _signalTyping();
  }

  /// Throttled typing signal so the peer's header shows "typing\u2026" while
  /// the admin writes (mirrors the user composer).
  void _signalTyping() {
    final DateTime now = DateTime.now();
    if (now.difference(_lastTypingSignalAt).inSeconds < 3) return;
    _lastTypingSignalAt = now;
    unawaited(widget.chat.setTyping(widget.conversationId));
  }

  Future<void> _sendText() async {
    final String text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    _onInputChanged();
    final ManagedMessage? replyTo = widget.replyTo;
    widget.onReplyCleared?.call();
    unawaited(
      widget.chat.sendMessage(
        conversationId: widget.conversationId,
        text: text,
        replyToId: replyTo?.id,
        replyToType: replyTo?.type.name,
        replyToText: replyTo?.text,
        replyToSender: widget.replyToSender,
      ),
    );
  }

  // ----- Translate before sending -----

  /// Translates the draft into a language the admin picks, then lets them
  /// review the translation and send it (with the original kept for a
  /// "See original" toggle on the peer's side).
  Future<void> _translateDraft() async {
    final String text = _input.text.trim();
    if (text.isEmpty) return;
    final Language? target = await showLanguagePicker(
      context,
      title: 'Translate to',
    );
    if (target == null || !mounted) return;

    final TextTranslationResult result;
    try {
      result = await widget.chat.chatAi.translateText(
        text: text,
        targetLanguage: target.name,
      );
    } on ChatAiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
      return;
    } on Exception {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not translate that message. Try again.'),
        ),
      );
      return;
    }
    if (!mounted) return;
    await _showTranslationPreview(
      original: text,
      translated: result.translation,
      targetName: target.name,
      sourceLanguage: result.sourceLanguage,
    );
  }

  Future<void> _showTranslationPreview({
    required String original,
    required String translated,
    required String targetName,
    required String sourceLanguage,
  }) async {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool? send = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(Icons.translate_rounded, color: scheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Translated to $targetName',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(translated, style: theme.textTheme.bodyLarge),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 12),
                Text(
                  'Original',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  original,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(true),
                    icon: const Icon(Icons.send_rounded),
                    label: const Text('Send translation'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (send != true || !mounted) return;

    final ManagedMessage? replyTo = widget.replyTo;
    _input.clear();
    _onInputChanged();
    unawaited(
      widget.chat.sendMessage(
        conversationId: widget.conversationId,
        text: translated,
        replyToId: replyTo?.id,
        replyToType: replyTo?.type.name,
        replyToText: replyTo?.text,
        replyToSender: widget.replyToSender,
        originalText: original,
        sourceLang: sourceLanguage.isEmpty ? null : sourceLanguage,
      ),
    );
    widget.onReplyCleared?.call();
  }

  // ----- Attachments (gallery / camera / video / camera video) -----

  Future<void> _showAttachSheet() async {
    final _PickChoice? choice = await showModalBottomSheet<_PickChoice>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    _attachTile(
                      context,
                      icon: Icons.photo_library_rounded,
                      color: const Color(0xFF008069),
                      label: 'Gallery',
                      value: const _PickChoice(
                        _PickKind.image,
                        ChatMediaSource.gallery,
                      ),
                    ),
                    _attachTile(
                      context,
                      icon: Icons.photo_camera_rounded,
                      color: const Color(0xFFE5422B),
                      label: 'Camera',
                      value: const _PickChoice(
                        _PickKind.image,
                        ChatMediaSource.camera,
                      ),
                    ),
                    _attachTile(
                      context,
                      icon: Icons.video_library_rounded,
                      color: const Color(0xFF5B66C7),
                      label: 'Video',
                      value: const _PickChoice(
                        _PickKind.video,
                        ChatMediaSource.gallery,
                      ),
                    ),
                    _attachTile(
                      context,
                      icon: Icons.videocam_rounded,
                      color: const Color(0xFF4A9E5F),
                      label: 'Camera video',
                      value: const _PickChoice(
                        _PickKind.video,
                        ChatMediaSource.camera,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    if (choice == null || !mounted) return;
    await _pick(choice.kind, choice.source);
  }

  Widget _attachTile(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String label,
    required _PickChoice value,
  }) {
    final ThemeData theme = Theme.of(context);
    return InkWell(
      onTap: () => Navigator.of(context).pop(value),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pick(_PickKind kind, ChatMediaSource source) async {
    if (source == ChatMediaSource.camera) {
      final PermissionStatus status = await Permission.camera.request();
      if (!status.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Camera permission is needed to take photos.'),
            ),
          );
        }
        return;
      }
    }

    try {
      if (kind == _PickKind.image) {
        final PickedChatImage? image =
            await widget.chat.mediaPicker.pickImage(source: source);
        if (image == null || !mounted) return;
        setState(() {
          _attachment = _ComposerAttachment(
            messageId: widget.chat.newMessageId(),
            type: MessageType.image,
            bytes: image.bytes,
            contentType: image.mimeType,
            fileName: image.fileName,
            width: image.width,
            height: image.height,
            sizeBytes: image.sizeBytes,
            label: 'Photo',
            previewBytes: image.bytes,
          );
        });
      } else {
        final PickedChatVideo? video =
            await widget.chat.mediaPicker.pickVideo(source: source);
        if (video == null || !mounted) return;
        final Uint8List bytes =
            video.bytes ?? await File(video.filePath).readAsBytes();
        if (!mounted) return;
        setState(() {
          _attachment = _ComposerAttachment(
            messageId: widget.chat.newMessageId(),
            type: MessageType.video,
            bytes: bytes,
            contentType: video.mimeType,
            fileName: video.fileName,
            thumbnailBytes: video.thumbnailBytes,
            durationMs: video.durationMs,
            width: video.width,
            height: video.height,
            sizeBytes: video.sizeBytes,
            label: 'Video',
            previewBytes: video.thumbnailBytes,
          );
        });
      }
    } on PlatformException catch (e) {
      _showPickError(e.code);
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not pick that media. Try again.'),
          ),
        );
      }
    }
  }

  void _showPickError(String code) {
    if (!mounted) return;
    final String message = switch (code) {
      'camera_access_denied' || 'camera_access_restricted' =>
        'Camera permission is needed to take photos.',
      'photo_access_denied' || 'photo_access_restricted' =>
        'Gallery permission is needed to pick photos.',
      'video_access_denied' || 'video_access_restricted' =>
        'Gallery permission is needed to pick videos.',
      _ => 'Could not open that media source.',
    };
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _sendAttachment() async {
    final _ComposerAttachment? attachment = _attachment;
    if (attachment == null || _uploading) return;
    final ManagedChatController chat = widget.chat;

    setState(() {
      _uploading = true;
      _uploadProgress = 0;
    });

    try {
      final MediaUploadTask task = await chat.uploadChatMedia(
        conversationId: widget.conversationId,
        messageId: attachment.messageId,
        bytes: attachment.bytes,
        contentType: attachment.contentType,
        fileName: attachment.fileName,
      );
      if (!mounted) return;
      _uploadTask = task;
      _progressSub = task.progress.listen((double value) {
        if (mounted) setState(() => _uploadProgress = value);
      });
      final String url = await task.url;
      await _progressSub?.cancel();

      String? thumbnailUrl;
      final Uint8List? thumbnailBytes = attachment.thumbnailBytes;
      if (attachment.type == MessageType.video && thumbnailBytes != null) {
        final MediaUploadTask thumbTask = await chat.uploadChatThumbnail(
          conversationId: widget.conversationId,
          messageId: attachment.messageId,
          bytes: thumbnailBytes,
          contentType: 'image/jpeg',
        );
        thumbnailUrl = await thumbTask.url;
      }

      await chat.sendMediaMessage(
        conversationId: widget.conversationId,
        messageId: attachment.messageId,
        media: MessageMedia(
          type: attachment.type,
          url: url,
          thumbnailUrl: thumbnailUrl,
          durationMs: attachment.durationMs,
          width: attachment.width,
          height: attachment.height,
          fileName: attachment.fileName,
          mimeType: attachment.contentType,
          sizeBytes: attachment.sizeBytes,
        ),
        replyToId: widget.replyTo?.id,
        replyToType: widget.replyTo?.type.name,
        replyToText: widget.replyTo?.text,
        replyToSender: widget.replyToSender,
      );
      if (!mounted) return;
      setState(() {
        _attachment = null;
        _uploading = false;
        _uploadProgress = null;
        _uploadTask = null;
      });
      widget.onReplyCleared?.call();
    } on Exception {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _uploadProgress = null;
        _uploadTask = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Upload failed. Check your connection and try again.'),
        ),
      );
    }
  }

  Future<void> _cancelAttachment() async {
    final MediaUploadTask? task = _uploadTask;
    _progressSub?.cancel();
    _progressSub = null;
    if (task != null) {
      try {
        await task.cancel();
      } on Exception {
        // Best-effort; UI is cleared regardless.
      }
    }
    if (mounted) {
      setState(() {
        _attachment = null;
        _uploading = false;
        _uploadProgress = null;
        _uploadTask = null;
      });
    }
  }

  // ----- Voice recording (press-and-hold) -----

  Future<void> _startRecording() async {
    final ManagedChatController chat = widget.chat;
    final bool allowed = await chat.voiceRecorder.ensurePermission();
    if (!allowed) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Microphone permission is needed to record voice messages.',
            ),
          ),
        );
      }
      return;
    }
    try {
      await chat.voiceRecorder.startRecording();
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not start recording.')),
        );
      }
      return;
    }
    if (!mounted) return;
    _inputFocus.unfocus();
    setState(() {
      _recording = true;
      _cancelArmed = false;
      _recordElapsedSeconds = 0;
    });
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (mounted) setState(() => _recordElapsedSeconds++);
    });
  }

  Future<void> _finishRecording() async {
    if (_cancelArmed) {
      await _stopRecording(shouldSend: false);
      return;
    }
    await _stopRecording(shouldSend: true);
  }

  Future<void> _stopRecording({required bool shouldSend}) async {
    _recordTimer?.cancel();
    _recordTimer = null;
    final ManagedChatController chat = widget.chat;
    RecordedVoice? voice;
    try {
      if (shouldSend) {
        voice = await chat.voiceRecorder.stopRecording();
      } else {
        await chat.voiceRecorder.cancelRecording();
      }
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recording was interrupted.')),
        );
      }
    }
    if (!mounted) return;
    setState(() {
      _recording = false;
      _cancelArmed = false;
    });
    final RecordedVoice? clip = voice;
    if (clip != null && clip.durationMs > 0) {
      setState(() {
        _attachment = _ComposerAttachment(
          messageId: chat.newMessageId(),
          type: MessageType.voice,
          bytes: clip.bytes,
          contentType: clip.mimeType,
          fileName: clip.fileName,
          durationMs: clip.durationMs,
          sizeBytes: clip.bytes.length,
          label: 'Voice message',
        );
      });
      await _sendAttachment();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final ManagedMessage? replyTo = widget.replyTo;

    return Container(
      color: Colors.transparent,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (_attachment != null)
              _AttachmentPreview(
                attachment: _attachment!,
                uploading: _uploading,
                progress: _uploadProgress,
                onCancel: _cancelAttachment,
                onSend: _sendAttachment,
              ),
            if (replyTo != null)
              _ReplyBanner(
                label: widget.replyToLabel ?? 'Message',
                preview: replyPreviewFromFields(
                    replyTo.replyToType, replyTo.replyToText),
                onClose: () => widget.onReplyCleared?.call(),
              ),
            Stack(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 6, 8, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      IconButton(
                        tooltip: 'Attach',
                        onPressed: _uploading ? null : _showAttachSheet,
                        icon: const Icon(Icons.add_circle_outline_rounded),
                        color: scheme.primary,
                      ),
                      _buildEmojiButton(context),
                      if (_canSend)
                        IconButton(
                          tooltip: 'Translate draft',
                          onPressed: _translateDraft,
                          icon: const Icon(Icons.translate_rounded),
                          color: scheme.primary,
                        ),
                      Expanded(
                        child: TextField(
                          controller: _input,
                          focusNode: _inputFocus,
                          minLines: 1,
                          maxLines: 4,
                          textInputAction: TextInputAction.newline,
                          onChanged: (_) => _onInputChanged(),
                          onSubmitted: (_) => _sendText(),
                          decoration: InputDecoration(
                            hintText: 'Message',
                            filled: true,
                            fillColor: scheme.surfaceContainerHighest,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(22),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (_canSend || _attachment != null)
                        IconButton.filled(
                          tooltip: 'Send',
                          onPressed: _uploading
                              ? null
                              : _attachment != null
                                  ? _sendAttachment
                                  : _sendText,
                          icon: const Icon(Icons.send_rounded),
                        )
                      else
                        _buildMicButton(context),
                    ],
                  ),
                ),
                if (_recording)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {},
                      child: _RecordingPanel(
                        elapsedSeconds: _recordElapsedSeconds,
                        cancelArmed: _cancelArmed,
                        onCancel: () {
                          setState(() => _cancelArmed = true);
                          unawaited(_stopRecording(shouldSend: false));
                        },
                      ),
                    ),
                  ),
              ],
            ),
            if (_emojiOpen && !_recording) _buildEmojiPanel(context),
          ],
        ),
      ),
    );
  }

  Widget _buildMicButton(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onLongPressStart: (_) => unawaited(_startRecording()),
      onLongPressEnd: (_) => unawaited(_finishRecording()),
      onLongPressMoveUpdate: (LongPressMoveUpdateDetails details) {
        final bool armed =
            details.localOffsetFromOrigin.dx < -70 ||
            details.localOffsetFromOrigin.dy < -70;
        if (armed != _cancelArmed && mounted) {
          setState(() => _cancelArmed = armed);
        }
      },
      onLongPressCancel: () => unawaited(_stopRecording(shouldSend: false)),
      child: IconButton(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Press and hold to record a voice message.'),
            ),
          );
        },
        icon: Icon(
          _recording ? Icons.mic : Icons.mic_none_rounded,
          color: _recording ? scheme.onError : scheme.primary,
        ),
      ),
    );
  }

  /// Docked WhatsApp-style emoji panel, shown in place of the keyboard.
  Widget _buildEmojiPanel(BuildContext context) {
    return EmojiPanel(
      onInsert: (String emoji) {
        final TextEditingValue value = _input.value;
        final int start = value.selection.baseOffset;
        final int end = value.selection.extentOffset;
        final int from = start >= 0 && end >= 0 && start <= end
            ? start
            : value.text.length;
        final int to = end >= 0 && end <= value.text.length
            ? end
            : value.text.length;
        final String text = value.text.replaceRange(from, to, emoji);
        _input.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: from + emoji.length),
        );
        _onInputChanged();
        setState(() {
          _recentEmojis.remove(emoji);
          _recentEmojis.insert(0, emoji);
          if (_recentEmojis.length > 30) {
            _recentEmojis.removeRange(30, _recentEmojis.length);
          }
        });
      },
      onKeyboard: () {
        setState(() => _emojiOpen = false);
        _inputFocus.requestFocus();
      },
      recents: _recentEmojis,
      skinTone: '',
      onSkinToneChanged: (_) {},
    );
  }

  /// Emoji toggle on the left of the input, like WhatsApp.
  Widget _buildEmojiButton(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool open = _emojiOpen;
    return IconButton(
      tooltip: open ? 'Show keyboard' : 'Emoji',
      onPressed: () {
        if (open) {
          setState(() => _emojiOpen = false);
          _inputFocus.requestFocus();
        } else {
          _inputFocus.unfocus();
          setState(() => _emojiOpen = true);
        }
      },
      icon: Icon(
        open ? Icons.keyboard_rounded : Icons.emoji_emotions_outlined,
        color: scheme.primary,
        size: 26,
      ),
    );
  }
}

class _PickChoice {
  const _PickChoice(this.kind, this.source);

  final _PickKind kind;
  final ChatMediaSource source;
}

/// Preview card shown above the input while an attachment is being sent.
class _AttachmentPreview extends StatelessWidget {
  const _AttachmentPreview({
    required this.attachment,
    required this.uploading,
    required this.progress,
    required this.onCancel,
    required this.onSend,
  });

  final _ComposerAttachment attachment;
  final bool uploading;
  final double? progress;
  final VoidCallback onCancel;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final double? value = progress;

    return Container(
      color: scheme.surfaceContainerLow,
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      child: Row(
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: attachment.previewBytes != null
                ? Image.memory(
                    attachment.previewBytes!,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                  )
                : Container(
                    width: 48,
                    height: 48,
                    color: scheme.surfaceContainerHighest,
                    child: Icon(
                      attachment.type == MessageType.voice
                          ? Icons.mic_rounded
                          : Icons.videocam_rounded,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  attachment.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                if (uploading && value != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: value,
                      minHeight: 5,
                      backgroundColor: scheme.surfaceContainerHighest,
                    ),
                  )
                else
                  Text(
                    'Ready to send',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Cancel',
            onPressed: onCancel,
            icon: Icon(Icons.close, color: scheme.onSurfaceVariant),
          ),
          IconButton.filled(
            tooltip: 'Send',
            onPressed: uploading ? null : onSend,
            icon: const Icon(Icons.send_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}

/// Full-screen overlay shown while recording a voice message.
class _RecordingPanel extends StatelessWidget {
  const _RecordingPanel({
    required this.elapsedSeconds,
    required this.cancelArmed,
    required this.onCancel,
  });

  final int elapsedSeconds;
  final bool cancelArmed;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String minutes =
        (elapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final String seconds = (elapsedSeconds % 60).toString().padLeft(2, '0');

    return ColoredBox(
      color: scheme.surfaceContainerLow.withValues(alpha: 0.96),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              cancelArmed ? Icons.cancel_rounded : Icons.mic_rounded,
              color: cancelArmed ? scheme.error : scheme.error,
              size: 44,
            ),
            const SizedBox(height: 12),
            Text(
              '$minutes:$seconds',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              cancelArmed
                  ? 'Release to cancel'
                  : 'Release to send \u00b7 slide left to cancel',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            TextButton.icon(
              onPressed: onCancel,
              icon: const Icon(Icons.close_rounded),
              label: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Quote banner shown above the composer input while a reply is being written.
class _ReplyBanner extends StatelessWidget {
  const _ReplyBanner({
    required this.label,
    required this.preview,
    required this.onClose,
  });

  final String label;
  final String preview;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surfaceContainerLow,
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      child: Row(
        children: <Widget>[
          Container(width: 3, height: 34, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onClose,
            icon: Icon(Icons.close, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class EmojiPanel extends StatelessWidget {
  const EmojiPanel({
    super.key,
    required this.onInsert,
    required this.onKeyboard,
    required this.recents,
    required this.skinTone,
    required this.onSkinToneChanged,
  });

  final ValueChanged<String> onInsert;
  final VoidCallback onKeyboard;
  final List<String> recents;
  final String skinTone;
  final ValueChanged<String> onSkinToneChanged;

  static const List<String> _common = <String>[
    '😀', '😂', '🥰', '😎', '🤔', '👍', '👎', '🎉',
    '❤️', '🔥', '👏', '🙏', '😊', '🥳', '😢', '😡',
  ];

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      height: 260,
      color: theme.colorScheme.surface,
      child: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 8,
          childAspectRatio: 1,
        ),
        itemCount: _common.length,
        itemBuilder: (BuildContext context, int index) {
          return InkWell(
            onTap: () => onInsert(_common[index]),
            child: Center(
              child: Text(
                _common[index],
                style: const TextStyle(fontSize: 24),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// One row of the message long-press action sheet.
class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.value,
    this.color,
  });

  final IconData icon;
  final String label;
  final _ManagedMessageAction value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: color ?? scheme.primary),
      title: Text(
        label,
        style: TextStyle(color: color ?? scheme.onSurface),
      ),
      onTap: () => Navigator.of(context).pop(value),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({
    super.key,
    required this.title,
    required this.message,
    required this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.error_outline_rounded, size: 48),
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(message),
        ],
      ),
    );
  }
}