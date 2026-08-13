import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/utils/time_utils.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/loading_view.dart';
import '../../../shared/widgets/user_avatar.dart';
import 'chat_controller.dart';
import 'chat_scope.dart';
import 'models/chat_message.dart';
import 'models/conversation.dart';
import 'widgets/chat_date_header.dart';
import 'widgets/composer_bar.dart';
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

enum _MessageAction { reply, copy, delete }

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

  /// Shared player so only one voice message plays at a time.
  VoiceMessagesPlayer? _voicePlayer;

  /// Incoming message IDs already acknowledged, so status updates fire once.
  final List<String> _acknowledgedIds = <String>[];

  /// Peer's display name, resolved from the live conversation stream.
  String _peerName = 'Chat';

  /// Message the user is currently replying to.
  ChatMessage? _replyTo;

  // Search-in-chat state.
  bool _searching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ChatController chat = ChatScope.of(context);
    if (!_subscribed) {
      _subscribed = true;
      _chat = chat;
      _myUid = chat.uid;
      _voicePlayer = VoiceMessagesPlayer(chat.voicePlayerFactory);
      _subscribe();
    }
  }

  void _subscribe() {
    _sub = _chat!.watchMessages(widget.conversationId).listen(
          (List<ChatMessage> messages) {
            if (!mounted) return;
            setState(() {
              _messages = messages;
              _loading = false;
            });
            _acknowledgeIncoming(messages);
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
        stream: _chat!.watchConversations(),
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

          return AppBar(
            backgroundColor: style.header,
            foregroundColor: Colors.white,
            titleSpacing: 0,
            title: Row(
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
                          color: style.onHeaderSub,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: <Widget>[
              IconButton(
                tooltip: 'Search',
                icon: const Icon(Icons.search_rounded, color: Colors.white),
                onPressed: () => setState(() => _searching = true),
              ),
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
                tooltip: 'View profile',
                icon: const Icon(Icons.info_outline_rounded, color: Colors.white),
                onPressed: conversation == null
                    ? null
                    : () => context.push(
                        AppRoutes.publicProfileFor(conversation!.peer.uid)),
              ),
            ],
          );
        },
      ),
    );
  }

  String _presenceLine(Conversation? conversation) {
    if (conversation == null) return '';
    final UserProfile peer = conversation.peer;
    return peer.isOnline
        ? 'Online'
        : formatLastSeen(peer.lastSeen);
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
