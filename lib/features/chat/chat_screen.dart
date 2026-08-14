import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/utils/time_utils.dart';
import '../../../shared/languages.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/loading_view.dart';
import '../../../shared/widgets/user_avatar.dart';
import 'chat_controller.dart';
import 'chat_scope.dart';
import 'data/chat_ai_service.dart';
import 'models/chat_message.dart';
import 'models/conversation.dart';
import 'widgets/chat_date_header.dart';
import 'widgets/composer_bar.dart';
import '../../shared/language_picker_dialog.dart';
import 'widgets/media_message_bubble.dart';
import 'widgets/message_bubble.dart';
import 'widgets/voice_message_bubble.dart';
import 'widgets/voice_messages_player.dart';
import 'widgets/whatsapp_style.dart';
import 'widgets/whatsapp_wallpaper.dart';
import '../profile/models/user_profile.dart';
import '../profile/profile_scope.dart';
import '../calls/call_scope.dart';
import '../calls/models/call.dart';

/// 1-to-1 chat view styled like WhatsApp: doodle wallpaper, green/white
/// bubbles with a tail, date separators, an end-to-end encryption notice,
/// and a composer with emoji, attachments, voice recording and replies.
///
/// Long-pressing a message offers Reply / Copy / Delete. The conversation may
/// also be opened from a notification, so the peer's identity is resolved from
/// the live conversation stream rather than passed through the route.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.conversationId});

  final String conversationId;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

enum _MessageAction { reply, copy, delete, translate }

enum _ChatMenuAction { profile, autoTranslate }

class _ChatScreenState extends State<ChatScreen> {
  ChatController? _chat;
  String? _myUid;

  List<ChatMessage> _messages = <ChatMessage>[];
  bool _loading = true;
  Object? _error;

  bool _hasMore = true;
  bool _loadingOlder = false;
  ChatMessage? _oldestMessage;
  bool _followBottom = true;

  final ScrollController _scroll = ScrollController();
  StreamSubscription<List<ChatMessage>>? _sub;
  bool _subscribed = false;

  /// Stable conversations stream for the app bar (the peer's name and typing
  /// indicator). Created once so rebuilds don't churn subscriptions.
  Stream<List<Conversation>>? _conversationsStream;

  /// Shared player so only one voice message plays at a time.
  VoiceMessagesPlayer? _voicePlayer;

  /// Incoming message IDs already acknowledged, so status updates fire once.
  final List<String> _acknowledgedIds = <String>[];

  /// Peer's display name, resolved from the live conversation stream.
  String _peerName = 'Chat';

  /// Latest conversation snapshot, kept so the typing indicator can refresh
  /// itself when the peer's typing stamp expires without a new stream event.
  Conversation? _currentConversation;
  Timer? _typingRefreshTimer;

  /// Message the user is currently replying to.
  ChatMessage? _replyTo;

  // ----- Auto-translate (incoming foreign-language messages) -----

  /// Message-id-keyed cache of device-side translations. Keys use the target
  /// language name so switching language re-translates instead of showing a
  /// stale translation.
  final Map<String, String> _translationCache = <String, String>{};

  /// Message IDs currently being translated (avoid duplicate in-flight calls).
  final Set<String> _translationPending = <String>{};

  /// Message IDs where the user expanded "See original".
  final Set<String> _translationExpanded = <String>{};

  /// Per-chat override; null means "follow the profile setting".
  bool? _chatAutoTranslate;

  /// The signed-in user's preferred language code and master switch, read
  /// from the profile (kept up to date via [didChangeDependencies]).
  String _myPreferredLang = '';
  bool _profileAutoTranslate = true;

  bool get _autoTranslateEnabled => _chatAutoTranslate ?? _profileAutoTranslate;

  String get _targetLangName => languageNameFor(_myPreferredLang);

  String _translationKey(String messageId) => '$messageId|$_targetLangName';

  // Search-in-chat state.
  bool _searching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ChatController chat = ChatScope.of(context);

    // Keep the auto-translate target in sync with the profile (this re-runs
    // whenever the profile stream notifies, e.g. the user edits their
    // preferred language or flips the master switch).
    final UserProfile? profile = ProfileScope.maybeOf(context)?.profile;
    final String preferredLang = profile?.preferredLang ?? '';
    final bool profileAutoTranslate = profile?.autoTranslate ?? true;
    final bool langChanged = preferredLang != _myPreferredLang;
    final bool switchChanged =
        profileAutoTranslate != _profileAutoTranslate;
    _myPreferredLang = preferredLang;
    _profileAutoTranslate = profileAutoTranslate;
    if (langChanged) {
      // Cached translations target the old language: drop them.
      _translationCache.clear();
      _translationExpanded.clear();
    }

    if (!_subscribed) {
      _subscribed = true;
      _chat = chat;
      _myUid = chat.uid;
      _voicePlayer = VoiceMessagesPlayer(chat.voicePlayerFactory);
      _subscribe();
      _typingRefreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        final Conversation? conversation = _currentConversation;
        if (conversation != null &&
            conversation.isTypingFrom(_myUid ?? '')) {
          setState(() {});
        }
      });
    } else if (langChanged || switchChanged) {
      // Language or the master switch changed while the chat is open:
      // re-evaluate the messages already on screen.
      unawaited(_translatePendingOnEnable());
    }
  }

  void _subscribe() {
    _conversationsStream = _chat!.watchConversations();
    _sub = _chat!.watchMessages(widget.conversationId).listen(
          (List<ChatMessage> messages) {
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
  }

  /// Marks messages from the peer as delivered + read and clears the unread
  /// badge, as long as this screen is open.
  void _acknowledgeIncoming(List<ChatMessage> messages) {
    final ChatController? chat = _chat;
    final String? myUid = _myUid;
    if (chat == null || myUid == null) return;
    final List<String> incomingIds = messages
        .where((ChatMessage m) => m.senderUid != myUid)
        .map((ChatMessage m) => m.id)
        .where((String id) => !_acknowledgedIds.contains(id))
        .toList();
    if (incomingIds.isEmpty) return;
    _acknowledgedIds.addAll(incomingIds);
    unawaited(chat.markMessagesDelivered(widget.conversationId, incomingIds));
    unawaited(chat.markMessagesRead(widget.conversationId, incomingIds));
    unawaited(chat.markConversationRead(widget.conversationId));
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

  // ---------------------------------------------------------------------
  // Auto-translate (incoming foreign-language messages)
  // ---------------------------------------------------------------------

  /// Queues device-side translations for incoming text messages whose stamped
  /// language differs from the signed-in user's preferred language. The stamp
  /// means no AI language detection is needed, so this costs nothing for
  /// same-language messages.
  void _maybeAutoTranslate(List<ChatMessage> messages) {
    final ChatController? chat = _chat;
    final String? myUid = _myUid;
    if (chat == null || myUid == null) return;
    if (!_autoTranslateEnabled) return;
    final String myLang = _myPreferredLang;
    if (myLang.isEmpty) return;

    final List<ChatMessage> toTranslate = <ChatMessage>[];
    for (final ChatMessage message in messages) {
      if (message.senderUid == myUid) continue;
      if (message.type != MessageType.text) continue;
      if (message.text.trim().isEmpty) continue;
      if (message.hasOriginal) continue; // already translated by the sender
      final String? senderLang = message.senderLang;
      if (senderLang == null || senderLang.isEmpty) continue;
      if (senderLang.toLowerCase() == myLang.toLowerCase()) continue;
      if (_translationCache.containsKey(_translationKey(message.id))) continue;
      if (_translationPending.contains(message.id)) continue;
      toTranslate.add(message);
    }
    if (toTranslate.isEmpty) return;
    unawaited(_translateMessages(toTranslate));
  }

  Future<void> _translateMessages(List<ChatMessage> messages) async {
    final ChatController? chat = _chat;
    if (chat == null) return;
    final String target = _targetLangName;
    for (final ChatMessage message in messages) {
      if (_translationPending.contains(message.id)) continue;
      _translationPending.add(message.id);
      try {
        final TextTranslationResult result = await chat.chatAi.translateText(
          text: message.text,
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

  /// Fetches translations for messages already on screen (used when the user
  /// turns auto-translate back on).
  Future<void> _translatePendingOnEnable() async {
    if (!_autoTranslateEnabled) return;
    final ChatController? chat = _chat;
    if (chat == null) return;
    final List<ChatMessage> messages = List<ChatMessage>.of(_messages);
    // Small delay so the toggle tap registers before the AI calls stream in.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    _maybeAutoTranslate(messages);
  }

  /// Whether the peer's [message] should currently render its (cached)
  /// translation instead of the original wording.
  bool _showsTranslation(ChatMessage message) {
    if (message.hasOriginal) return false;
    if (!_autoTranslateEnabled) return false;
    if (message.senderUid == _myUid) return false;
    final String? senderLang = message.senderLang;
    if (senderLang == null || senderLang.isEmpty) return false;
    if (_myPreferredLang.isEmpty) return false;
    if (senderLang.toLowerCase() == _myPreferredLang.toLowerCase()) {
      return false;
    }
    return _translationCache.containsKey(_translationKey(message.id));
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final ScrollPosition position = _scroll.position;
    _followBottom = position.pixels >= position.maxScrollExtent - 120;
    if (position.pixels < 200) {
      unawaited(_loadOlder());
    }
  }

  Future<void> _loadOlder() async {
    final ChatController? chat = _chat;
    final ChatMessage? before = _oldestMessage ?? (_messages.isEmpty ? null : _messages.first);
    if (chat == null || before == null || _loadingOlder || !_hasMore) return;
    _loadingOlder = true;
    try {
      final List<ChatMessage> older = await chat.fetchMessagesBefore(
        widget.conversationId,
        before,
      );
      if (!mounted) return;
      setState(() {
        if (older.isNotEmpty) {
          _messages = <ChatMessage>[...older, ..._messages];
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

  @override
  void dispose() {
    _typingRefreshTimer?.cancel();
    unawaited(_chat?.markConversationRead(widget.conversationId));
    _sub?.cancel();
    _voicePlayer?.dispose();
    _scroll.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Message list helpers
  // ---------------------------------------------------------------------

  bool get _isSearching => _searching && _searchQuery.trim().isNotEmpty;

  List<ChatMessage> get _visibleMessages {
    if (!_isSearching) return _messages;
    final String query = _searchQuery.trim().toLowerCase();
    return _messages
        .where((ChatMessage m) =>
            m.type == MessageType.text && m.text.toLowerCase().contains(query))
        .toList();
  }

  /// Builds the flat list of list items: encryption notice, date separators
  /// and messages (or just matching messages while searching).
  List<Object> get _entries {
    final List<ChatMessage> visible = _visibleMessages;
    if (_isSearching) {
      return List<Object>.of(visible);
    }
    final List<Object> entries = <Object>[_encryptionNotice];
    DateTime? lastDay;
    for (final ChatMessage message in visible) {
      final DateTime day =
          DateTime(message.createdAt.year, message.createdAt.month, message.createdAt.day);
      if (lastDay == null || !ChatDateHeader.isSameDay(lastDay, day)) {
        entries.add(day);
        lastDay = day;
      }
      entries.add(message);
    }
    return entries;
  }

  Object get _encryptionNotice => 'encryption';

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

  Widget _buildBubble(ChatMessage message) {
    final bool fromMe = message.senderUid == _myUid;
    return switch (message.type) {
      MessageType.text => WhatsAppTextBubble(
          message: message,
          fromMe: fromMe,
          onLongPress: () => _showMessageActions(message, fromMe),
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
      MessageType.image => ImageMessageBubble(
          message: message,
          fromMe: fromMe,
          onLongPress: () => _showMessageActions(message, fromMe),
        ),
      MessageType.video => VideoMessageBubble(
          message: message,
          fromMe: fromMe,
          onLongPress: () => _showMessageActions(message, fromMe),
        ),
      MessageType.voice => VoiceMessageBubble(
          message: message,
          fromMe: fromMe,
          player: _voicePlayer!,
          onLongPress: () => _showMessageActions(message, fromMe),
        ),
    };
  }

  // ---------------------------------------------------------------------
  // Message actions (reply / copy / delete)
  // ---------------------------------------------------------------------

  Future<void> _showMessageActions(ChatMessage message, bool fromMe) async {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool isText = message.type == MessageType.text;

    final _MessageAction? action = await showModalBottomSheet<_MessageAction>(
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
                value: _MessageAction.reply,
              ),
              if (isText)
                _ActionTile(
                  icon: Icons.copy_rounded,
                  label: 'Copy text',
                  value: _MessageAction.copy,
                ),
              if (isText || message.type == MessageType.voice)
                _ActionTile(
                  icon: Icons.translate_rounded,
                  label: isText ? 'Translate' : 'Translate voice',
                  value: _MessageAction.translate,
                ),
              if (fromMe)
                _ActionTile(
                  icon: Icons.delete_outline_rounded,
                  label: 'Delete for everyone',
                  value: _MessageAction.delete,
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
      case _MessageAction.reply:
        setState(() {
          _replyTo = message;
          _scrollToBottomIfFollowing();
        });
      case _MessageAction.copy:
        if (message.text.isNotEmpty) {
          await Clipboard.setData(ClipboardData(text: message.text));
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Message copied')),
            );
          }
        }
      case _MessageAction.delete:
        await _confirmDelete(message);
      case _MessageAction.translate:
        await _translateMessage(message);
    }
  }

  Future<void> _confirmDelete(ChatMessage message) async {
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
    final ChatController? chat = _chat;
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

  // ---------------------------------------------------------------------
  // Translation (text + voice messages)
  // ---------------------------------------------------------------------

  /// Asks the user for a target language, translates [message], and shows the
  /// result. Voice messages are transcribed first (via the AI edge function).
  Future<void> _translateMessage(ChatMessage message) async {
    final Language? target = await showLanguagePicker(
      context,
      title: 'Translate to',
    );
    if (target == null || !mounted) return;
    final ChatController? chat = _chat;
    if (chat == null) return;

    final bool isVoice = message.type == MessageType.voice;
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) =>
          _TranslatingDialog(language: target.name),
    ));

    try {
      if (isVoice) {
        final String? url = message.mediaUrl;
        if (url == null) return;
        final VoiceTranslationResult result = await chat.chatAi.translateVoice(
          audioUrl: url,
          targetLanguage: target.name,
        );
        if (!mounted) return;
        Navigator.of(context).pop();
        _showTranslationResult(
          original: result.transcript,
          translated: result.translation,
          languageName: target.name,
          isVoice: true,
        );
      } else {
        final TextTranslationResult result = await chat.chatAi.translateText(
          text: message.text,
          targetLanguage: target.name,
        );
        if (!mounted) return;
        Navigator.of(context).pop();
        _showTranslationResult(
          original: message.text,
          translated: result.translation,
          languageName: target.name,
          isVoice: false,
        );
      }
    } on ChatAiException catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } on Exception {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not translate that message. Try again.'),
        ),
      );
    }
  }

  void _showTranslationResult({
    required String original,
    required String translated,
    required String languageName,
    required bool isVoice,
  }) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext context) {
        final ThemeData theme = Theme.of(context);
        final ColorScheme scheme = theme.colorScheme;
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
                        isVoice
                            ? 'Translated voice to $languageName'
                            : 'Translated to $languageName',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(translated, style: theme.textTheme.bodyLarge),
                if (original.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  Text(
                    isVoice ? 'Original transcript' : 'Original',
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
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: _buildAppBar(context),
      ),
      body: SafeArea(
        child: WhatsAppWallpaper(
          child: Column(
            children: <Widget>[
              Expanded(child: _buildMessages(context)),
              ChatComposer(
                chat: _chat!,
                conversationId: widget.conversationId,
                replyTo: _replyTo,
                replyToLabel: _replyToLabel(_replyTo),
                replyToSender: _replyToSender(_replyTo),
                onReplyCleared: () => setState(() => _replyTo = null),
                voiceEffectsEnabled: _isAdmin,
                myLanguageCode: _myPreferredLang.isEmpty ? null : _myPreferredLang,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _replyToLabel(ChatMessage? message) {
    if (message == null) return null;
    final bool fromMe = message.senderUid == _myUid;
    return fromMe ? 'You' : _peerName;
  }

  /// Author name stored on a sent reply. The peer must see the real name of
  /// the quoted message's author, so replying to your own message uses your
  /// own display name rather than the local "You" label.
  String? _replyToSender(ChatMessage? message) {
    if (message == null) return null;
    if (message.senderUid == _myUid) {
      final UserProfile? profile = ProfileScope.of(context).profile;
      final String name = profile?.displayName ?? '';
      if (name.isNotEmpty) return name;
      final String username = profile?.username ?? '';
      return username.isNotEmpty ? username : 'You';
    }
    return _peerName;
  }

  /// Whether the signed-in user is an admin (shows the voice changer).
  bool get _isAdmin => ProfileScope.of(context).profile?.isAdmin ?? false;

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    final WhatsAppStyle style = WhatsAppStyle.of(context);

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
            hintStyle: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
            ),
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
      child: StreamBuilder<List<Conversation>>(
        stream: _conversationsStream,
        builder: (BuildContext context,
            AsyncSnapshot<List<Conversation>> snapshot) {
          final List<Conversation> conversations =
              snapshot.data ?? const <Conversation>[];
          Conversation? conversation;
          for (final Conversation c in conversations) {
            if (c.id == widget.conversationId) {
              conversation = c;
              break;
            }
          }
          final String displayName = conversation == null
              ? 'Chat'
              : (conversation.peer.displayName.isNotEmpty
                  ? conversation.peer.displayName
                  : conversation.peer.username);
          _peerName = displayName;
          _currentConversation = conversation;
          final bool peerTyping = conversation?.isTypingFrom(_myUid ?? '') ?? false;

          return Container(
            decoration: BoxDecoration(
              color: style.header,
              border: Border(
                bottom: BorderSide(
                  color: Colors.black.withValues(alpha: 0.12),
                ),
              ),
            ),
            child: AppBar(
              backgroundColor: style.header,
              foregroundColor: Colors.white,
              elevation: 0,
              titleSpacing: 0,
              title: InkWell(
                onTap: conversation == null
                    ? null
                    : () => context.push(
                        AppRoutes.publicProfileFor(conversation!.peer.uid)),
                borderRadius: BorderRadius.circular(6),
                child: Row(
                  children: <Widget>[
                    UserAvatar(
                      name: displayName,
                      photoURL: conversation?.peer.photoURL,
                      size: 38,
                      backgroundColor: const Color(0xFF6A7A85),
                      foregroundColor: Colors.white,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            displayName,
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
                            _presenceLine(conversation),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: peerTyping
                                  ? const Color(0xFFA7F3D0)
                                  : style.onHeaderSub,
                              fontSize: 12.5,
                              fontStyle: peerTyping
                                  ? FontStyle.italic
                                  : FontStyle.normal,
                              fontWeight: peerTyping
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                IconButton(
                  tooltip: 'Video call',
                  icon: const Icon(Icons.videocam_rounded, color: Colors.white),
                  onPressed: conversation == null
                      ? null
                      : () => _startCall(conversation!.peer.uid, CallType.video),
                ),
                IconButton(
                  tooltip: 'Voice call',
                  icon: const Icon(Icons.call_rounded, color: Colors.white),
                  onPressed: conversation == null
                      ? null
                      : () => _startCall(conversation!.peer.uid, CallType.audio),
                ),
                IconButton(
                  tooltip: 'Search',
                  icon: const Icon(Icons.search_rounded, color: Colors.white),
                  onPressed: () => setState(() => _searching = true),
                ),
                PopupMenuButton<_ChatMenuAction>(
                  tooltip: 'More options',
                  icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
                  onSelected: _onMenuSelected,
                  itemBuilder: (BuildContext context) =>
                      <PopupMenuEntry<_ChatMenuAction>>[
                    PopupMenuItem<_ChatMenuAction>(
                      value: _ChatMenuAction.profile,
                      child: const Row(
                        children: <Widget>[
                          Icon(Icons.person_outline_rounded),
                          SizedBox(width: 12),
                          Text('View profile'),
                        ],
                      ),
                    ),
                    PopupMenuItem<_ChatMenuAction>(
                      value: _ChatMenuAction.autoTranslate,
                      child: Row(
                        children: <Widget>[
                          const Icon(Icons.translate_rounded),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _autoTranslateEnabled
                                  ? 'Auto-translate: on'
                                  : 'Auto-translate: off',
                            ),
                          ),
                          if (_autoTranslateEnabled)
                            const Icon(Icons.check_rounded),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _onMenuSelected(_ChatMenuAction action) {
    switch (action) {
      case _ChatMenuAction.profile:
        final Conversation? conversation = _currentConversation;
        if (conversation == null) return;
        context.push(AppRoutes.publicProfileFor(conversation.peer.uid));
      case _ChatMenuAction.autoTranslate:
        setState(() {
          final bool next = !_autoTranslateEnabled;
          // Back to "follow my settings" when it matches the profile.
          _chatAutoTranslate = next == _profileAutoTranslate ? null : next;
          if (next) {
            unawaited(_translatePendingOnEnable());
          }
        });
    }
  }

  String _presenceLine(Conversation? conversation) {
    if (conversation == null) return '';
    final UserProfile peer = conversation.peer;
    final String handle = '@${peer.username}';
    if (conversation.isTypingFrom(_myUid ?? '')) {
      return '$handle \u00b7 typing\u2026';
    }
    final String presence =
        peer.isOnline ? 'Online' : formatLastSeen(peer.lastSeen);
    return '$handle \u00b7 $presence';
  }

  void _startCall(String peerUid, CallType type) {
    final ChatController? chat = _chat;
    final String? myUid = _myUid;
    if (chat == null || myUid == null) return;
    final session = CallScope.of(context).beginCall(myUid: myUid);
    context.push(
      AppRoutes.activeCall,
      extra: <String, dynamic>{
        'session': session,
        'startParams': <String, dynamic>{
          'calleeUid': peerUid,
          'conversationId': widget.conversationId,
          'type': type == CallType.video ? 'video' : 'audio',
        },
      },
    );
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
    if (_isSearching && _visibleMessages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.search_off_rounded,
                  size: 56, color: style.meta),
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

    final List<Object> entries = _entries;
    final bool searching = _isSearching;
    final int offset = searching || !_hasMore ? 0 : 1;

    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification notification) {
        if (notification.metrics.axis == Axis.vertical) _onScroll();
        return false;
      },
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        itemCount: entries.length + offset,
        itemBuilder: (BuildContext context, int index) {
          if (offset == 1 && index == 0) {
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
          final Object entry = entries[index - offset];
          if (entry is DateTime) {
            return ChatDateHeader(day: entry);
          }
          if (entry is ChatMessage) {
            return _buildBubble(entry);
          }
          return _buildEncryptionNotice();
        },
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme, WhatsAppStyle style) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.waving_hand_rounded,
                size: 56, color: style.meta),
            const SizedBox(height: 16),
            Text(
              'Say Hi',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            _buildEncryptionNotice(),
          ],
        ),
      ),
    );
  }
}

/// Modal shown while a translation is in flight.
class _TranslatingDialog extends StatelessWidget {
  const _TranslatingDialog({required this.language});

  final String language;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: Row(
        children: <Widget>[
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          const SizedBox(width: 20),
          Expanded(child: Text('Translating into $language\u2026')),
        ],
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
  final _MessageAction value;
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
