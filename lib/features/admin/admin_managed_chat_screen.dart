import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/router/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/time_utils.dart';
import '../../features/chat/data/chat_repository.dart';
import '../../features/chat/models/chat_message.dart';
import './managed_account_controller.dart';
import './managed_account_scope.dart';
import './managed_chat_controller.dart';
import './managed_chat_scope.dart';
import './models/managed_account.dart';
import './models/managed_conversation.dart';
import './models/managed_message.dart';

enum _ManagedMessageAction { reply, copy, delete }

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

  ManagedMessage? _replyTo;

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

  @override
  void dispose() {
    _sub?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadOlder() async {
    final ManagedChatController? chat = _chat;
    final ManagedMessage? before = _oldestMessage ?? (_messages.isEmpty ? null : _messages.first);
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

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final ManagedAccountController accountController = ManagedAccountScope.of(context);
    final ManagedAccount? account = accountController.selectedAccount;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: Row(
          children: <Widget>[
            CircleAvatar(
              radius: 18,
              backgroundImage: account?.photoUrl != null ? NetworkImage(account!.photoUrl!) : null,
              backgroundColor: scheme.primary,
              foregroundColor: scheme.onPrimary,
              child: account?.photoUrl == null
                  ? Text(
                      account?.displayName.isNotEmpty == true
                          ? account!.displayName[0].toUpperCase()
                          : '?',
                      style: theme.textTheme.titleSmall,
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
                    account?.displayName ?? 'Chat',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  Text(
                    account?.displayHandle ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onPrimaryContainer.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: <Widget>[
          PopupMenuButton<_ManagedMessageAction>(
            tooltip: 'More options',
            icon: Icon(Icons.more_vert_rounded, color: scheme.onPrimaryContainer),
            onSelected: (action) {
              switch (action) {
                case _ManagedMessageAction.reply:
                  // reply logic
                  break;
                case _ManagedMessageAction.copy:
                  break;
                case _ManagedMessageAction.delete:
                  break;
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<_ManagedMessageAction>>[
              const PopupMenuItem<_ManagedMessageAction>(
                value: _ManagedMessageAction.copy,
                child: Row(
                  children: <Widget>[
                    Icon(Icons.copy_rounded),
                    SizedBox(width: 12),
                    Text('Copy text'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(child: _buildMessages(context)),
            _ManagedChatComposer(
              conversationId: widget.conversationId,
              chat: _chat!,
              replyTo: _replyTo,
              onReplyCleared: () => setState(() => _replyTo = null),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessages(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    if (_loading) {
      return const LoadingView(message: 'Loading messages…');
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
      return _buildEmptyState(theme);
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification notification) {
        if (notification.metrics.axis == Axis.vertical) _onScroll();
        return false;
      },
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: _messages.length + (_hasMore ? 1 : 0),
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
          final ManagedMessage message = _messages[index - (_hasMore ? 1 : 0)];
          return _buildBubble(context, message);
        },
      ),
    );
  }

  Widget _buildBubble(BuildContext context, ManagedMessage message) {
    final bool fromMe = message.senderUid == widget.managedAccountId;
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final Color bubbleColor = fromMe
        ? AppColors.live
        : scheme.surfaceContainerHighest;
    final Color textColor = fromMe
        ? const Color(0xFF06332B)
        : scheme.onSurface;

    return Align(
      alignment: fromMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (message.type == ManagedMessageType.text) ...<Widget>[
              Text(
                message.text ?? '',
                style: TextStyle(color: textColor),
              ),
            ] else if (message.type == ManagedMessageType.voice) ...<Widget>[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.mic_rounded, size: 18, color: textColor),
                  const SizedBox(width: 8),
                  Text(
                    message.durationMs != null && message.durationMs! > 0
                        ? formatDuration(Duration(milliseconds: message.durationMs!))
                        : 'Voice message',
                    style: TextStyle(color: textColor),
                  ),
                ],
              ),
            ] else if (message.type == ManagedMessageType.image) ...<Widget>[
              if (message.mediaUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    message.mediaUrl!,
                    width: 200,
                    fit: BoxFit.cover,
                    errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) {
                      return const Icon(Icons.broken_image_rounded);
                    },
                  ),
                ),
            ] else if (message.type == ManagedMessageType.video) ...<Widget>[
              if (message.mediaUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    message.mediaUrl!,
                    width: 200,
                    fit: BoxFit.cover,
                    errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) {
                      return const Icon(Icons.broken_image_rounded);
                    },
                  ),
                ),
            ],
            const SizedBox(height: 4),
            Text(
              _formatTime(message.createdAt),
              style: theme.textTheme.labelSmall?.copyWith(
                color: fromMe
                    ? const Color(0xFF06332B).withValues(alpha: 0.7)
                    : scheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.waving_hand_rounded,
                size: 56, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              'Say Hi',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Send a message to start the conversation.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime date = DateTime(time.year, time.month, time.day);
    final Duration diff = now.difference(time);
    if (diff.inDays == 0 && date == today) {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
    if (diff.inDays < 7) {
      return '${time.day}/${time.month}';
    }
    return '${time.day}/${time.month}/${time.year}';
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

class _ManagedChatComposer extends StatefulWidget {
  const _ManagedChatComposer({
    required this.conversationId,
    required this.chat,
    this.replyTo,
    this.onReplyCleared,
  });

  final String conversationId;
  final ManagedChatController chat;
  final ManagedMessage? replyTo;
  final VoidCallback? onReplyCleared;

  @override
  State<_ManagedChatComposer> createState() => _ManagedChatComposerState();
}

class _ManagedChatComposerState extends State<_ManagedChatComposer> {
  final TextEditingController _input = TextEditingController();
  bool _canSend = false;
  bool _emojiOpen = false;
  final List<String> _recentEmojis = <String>[];

  @override
  void initState() {
    super.initState();
    _input.addListener(_onInputChanged);
  }

  @override
  void dispose() {
    _input.removeListener(_onInputChanged);
    _input.dispose();
    super.dispose();
  }

  void _onInputChanged() {
    final bool canSend = _input.text.trim().isNotEmpty;
    if (canSend != _canSend) setState(() => _canSend = canSend);
  }

  Future<void> _sendText() async {
    final String text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    _onInputChanged();
    widget.onReplyCleared?.call();
    unawaited(
      widget.chat.sendMessage(
        conversationId: widget.conversationId,
        text: text,
      ),
    );
  }

  Future<void> _sendImage() async {
    final XFile? picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;
    final Uint8List bytes = await picked.readAsBytes();
    final String messageId = widget.chat.newMessageId();
    final MediaUploadTask task = await widget.chat.uploadChatMedia(
      conversationId: widget.conversationId,
      messageId: messageId,
      bytes: bytes,
      contentType: 'image/jpeg',
      fileName: picked.name,
    );
    final String url = await task.url;
    if (!mounted) return;
    unawaited(
      widget.chat.sendMediaMessage(
        conversationId: widget.conversationId,
        messageId: messageId,
        media: MessageMedia(
          type: MessageType.image,
          url: url,
          fileName: picked.name,
          mimeType: 'image/jpeg',
          sizeBytes: bytes.length,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Container(
      color: scheme.surface,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (widget.replyTo != null)
              Container(
                color: scheme.surfaceContainerLow,
                padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                child: Row(
                  children: <Widget>[
                    Container(width: 3, height: 34, color: scheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.replyTo!.text ?? 'Message',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: widget.onReplyCleared,
                      icon: Icon(Icons.close, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 8, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  IconButton(
                    tooltip: 'Attach',
                    onPressed: _sendImage,
                    icon: const Icon(Icons.add_circle_outline_rounded),
                    color: scheme.primary,
                  ),
                  _buildEmojiButton(context),
                  Expanded(
                    child: TextField(
                      controller: _input,
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
                  if (_canSend)
                    IconButton.filled(
                      tooltip: 'Send',
                      onPressed: _sendText,
                      icon: const Icon(Icons.send_rounded),
                    )
                  else
                    IconButton(
                      tooltip: 'Microphone',
                      onPressed: () {},
                      icon: Icon(Icons.mic_none_rounded, color: scheme.primary),
                    ),
                ],
              ),
            ),
            if (_emojiOpen) _buildEmojiPanel(context),
          ],
        ),
      ),
    );
  }

  Widget _buildEmojiButton(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool open = _emojiOpen;
    return IconButton(
      tooltip: open ? 'Show keyboard' : 'Emoji',
      onPressed: () {
        setState(() => _emojiOpen = !open);
      },
      icon: Icon(
        open ? Icons.keyboard_rounded : Icons.emoji_emotions_outlined,
        color: scheme.primary,
        size: 26,
      ),
    );
  }

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
      },
      recents: _recentEmojis,
      skinTone: '',
      onSkinToneChanged: (_) {},
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
