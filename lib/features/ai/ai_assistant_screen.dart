import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/utils/time_utils.dart';
import '../../shared/widgets/app_snackbar.dart';
import '../../shared/widgets/error_view.dart';
import '../../shared/widgets/loading_view.dart';
import '../../shared/widgets/lotext_button.dart';
import 'ai_assistant_controller.dart';
import 'ai_scope.dart';
import 'models/ai_conversation.dart';
import 'models/ai_message.dart';
import 'models/ai_provider.dart';
import 'models/ai_task.dart';

/// The LoText AI Assistant: conversation list plus a chat view with a
/// provider switcher, quick actions, loading and error handling.
///
/// All content is generated server-side by the `ai-assistant` edge function;
/// this screen only renders it.
class AiAssistantScreen extends StatefulWidget {
  const AiAssistantScreen({super.key});

  @override
  State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends State<AiAssistantScreen> {
  final TextEditingController _composer = TextEditingController();
  bool _drafting = false;
  bool _conversationsLoaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_conversationsLoaded) return;
    _conversationsLoaded = true;
    // Defer so the controller's synchronous notifyListeners never runs during
    // the build phase.
    scheduleMicrotask(() {
      if (mounted) unawaited(AiScope.of(context).loadConversations());
    });
  }

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AiAssistantController controller = AiScope.of(context);
    final AiConversation? selected = controller.selectedConversation;
    final bool inChat = _drafting || selected != null;

    return Scaffold(
      appBar: AppBar(
        leading: inChat ? _backButton(context) : null,
        title: Text(
          inChat
              ? (selected?.title ?? 'New chat')
              : 'LoText AI',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: <Widget>[
          _ProviderMenu(controller: controller),
          IconButton(
            tooltip: 'New chat',
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: () {
              controller.startNewChat();
              setState(() => _drafting = true);
            },
          ),
        ],
      ),
      body: SafeArea(
        child: inChat ? _buildChat(context, controller) : _buildConversations(context, controller),
      ),
    );
  }

  Widget? _backButton(BuildContext context) {
    final AiAssistantController controller = AiScope.of(context);
    return IconButton(
      tooltip: 'Back to chats',
      icon: const Icon(Icons.arrow_back_rounded),
      onPressed: () {
        controller.deselectConversation();
        setState(() => _drafting = false);
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Conversation list
  // ---------------------------------------------------------------------------

  Widget _buildConversations(
    BuildContext context,
    AiAssistantController controller,
  ) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    if (controller.conversationsLoading && controller.conversations.isEmpty) {
      return const LoadingView(message: 'Loading chats\u2026');
    }
    if (controller.conversationsError != null &&
        controller.conversations.isEmpty) {
      return ErrorView(
        title: 'Could not load AI chats',
        message: controller.conversationsError,
        onRetry: () => unawaited(controller.loadConversations()),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        _buildHeroCard(context, controller),
        const SizedBox(height: 20),
        LoTextButton(
          label: 'Start a new chat',
          icon: Icons.add_comment_outlined,
          isExpanded: true,
          onPressed: () {
            controller.startNewChat();
            setState(() => _drafting = true);
          },
        ),
        const SizedBox(height: 28),
        Text(
          'Recent chats',
          style: theme.textTheme.labelLarge?.copyWith(
            color: scheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        if (controller.conversations.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'No chats yet. Ask LoText AI anything \u2014 writing help, '
              'summaries, translations and more.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          )
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: <Widget>[
                for (int i = 0; i < controller.conversations.length; i++) ...<Widget>[
                  if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                  _ConversationTile(
                    conversation: controller.conversations[i],
                    onTap: () {
                      setState(() => _drafting = false);
                      unawaited(controller.selectConversation(
                        controller.conversations[i].id,
                      ));
                    },
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildHeroCard(BuildContext context, AiAssistantController controller) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final AiConversation? selected = controller.selectedConversation;
    final AiProvider current = selected?.provider ?? controller.provider;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            scheme.primaryContainer,
            scheme.tertiaryContainer,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.auto_awesome_rounded, color: scheme.primary, size: 30),
          const SizedBox(height: 12),
          Text(
            'LoText AI',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Write and rewrite messages, suggest replies, summarize and '
            'translate text. Runs on $current and is private to you.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Chat view
  // ---------------------------------------------------------------------------

  Widget _buildChat(BuildContext context, AiAssistantController controller) {
    return Column(
      children: <Widget>[
        Expanded(child: _buildMessages(context, controller)),
        if (controller.sendingError != null) _ErrorBanner(
          message: controller.sendingError!,
          onDismiss: controller.clearSendError,
        ),
        _buildQuickActions(context, controller),
        _buildComposer(context, controller),
      ],
    );
  }

  Widget _buildMessages(BuildContext context, AiAssistantController controller) {
    if (controller.messagesLoading) {
      return const LoadingView(message: 'Loading messages\u2026');
    }
    if (controller.messagesError != null) {
      return ErrorView(
        title: 'Could not load this chat',
        message: controller.messagesError,
        onRetry: () {
          final String? id = controller.selectedConversation?.id;
          if (id != null) unawaited(controller.selectConversation(id));
        },
      );
    }

    final List<AiMessage> messages = controller.messages;
    if (messages.isEmpty && !controller.sending) {
      return _buildEmptyChat(context);
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      itemCount: messages.length + (controller.sending ? 1 : 0),
      itemBuilder: (BuildContext context, int index) {
        if (index == messages.length) {
          return const _TypingBubble();
        }
        return _MessageBubble(message: messages[index]);
      },
    );
  }

  Widget _buildEmptyChat(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final List<String> suggestions = <String>[
      'Write a friendly weekend message to a friend',
      'Suggest 3 quick replies to "See you tomorrow"',
      'Summarize: I have three meetings, a demo, and a report due Friday.',
    ];

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      children: <Widget>[
        Icon(Icons.auto_awesome_rounded, size: 48, color: scheme.primary),
        const SizedBox(height: 16),
        Text(
          'Ask LoText AI anything',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          'Type a message below, or try one of these:',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        for (final String suggestion in suggestions)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ActionChip(
              avatar: const Icon(Icons.north_east_rounded, size: 16),
              label: Text(suggestion),
              onPressed: () => _composer.text = suggestion,
            ),
          ),
      ],
    );
  }

  Widget _buildQuickActions(BuildContext context, AiAssistantController controller) {
    final bool busy = controller.sending;
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: <Widget>[
          for (final AiTask task in AiTask.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                avatar: Icon(_iconFor(task), size: 16),
                label: Text(task.label),
                onPressed: busy
                    ? null
                    : () => _sendWithTask(context, controller, task),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildComposer(BuildContext context, AiAssistantController controller) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool busy = controller.sending;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _composer,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(context, controller),
                decoration: InputDecoration(
                  hintText: 'Message LoText AI\u2026',
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: 'Send',
              onPressed: busy ? null : () => _send(context, controller),
              icon: const Icon(Icons.send_rounded),
              style: IconButton.styleFrom(backgroundColor: scheme.primary),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _send(BuildContext context, AiAssistantController controller) async {
    final String text = _composer.text.trim();
    if (text.isEmpty) {
      AppSnackbars.showInfo(context, 'Type a message first.');
      return;
    }
    FocusScope.of(context).unfocus();
    final bool ok = await controller.send(content: text);
    if (ok && mounted) _composer.clear();
  }

  Future<void> _sendWithTask(
    BuildContext context,
    AiAssistantController controller,
    AiTask task,
  ) async {
    final String text = _composer.text.trim();
    if (text.isEmpty) {
      AppSnackbars.showInfo(context, 'Type the text you want to work with first.');
      return;
    }
    String? targetLanguage;
    if (task == AiTask.translate) {
      targetLanguage = await _pickLanguage(context);
      if (targetLanguage == null) return;
    }
    if (!context.mounted) return;
    FocusScope.of(context).unfocus();
    final bool ok = await controller.send(
      content: text,
      task: task,
      targetLanguage: targetLanguage,
    );
    if (ok && mounted) _composer.clear();
  }

  Future<String?> _pickLanguage(BuildContext context) async {
    const List<String> languages = <String>[
      'English', 'Spanish', 'French', 'German', 'Italian', 'Portuguese',
      'Chinese', 'Japanese', 'Arabic', 'Hindi',
    ];
    return showDialog<String>(
      context: context,
      builder: (BuildContext context) => SimpleDialog(
        title: const Text('Translate to'),
        children: <Widget>[
          for (final String language in languages)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(language),
              child: Text(language),
            ),
        ],
      ),
    );
  }

  IconData _iconFor(AiTask task) => switch (task) {
        AiTask.reply => Icons.reply_rounded,
        AiTask.rewrite => Icons.auto_fix_high_rounded,
        AiTask.suggest => Icons.lightbulb_outline_rounded,
        AiTask.summarize => Icons.summarize_outlined,
        AiTask.translate => Icons.translate_rounded,
      };
}

/// Provider switcher shown in the app bar.
class _ProviderMenu extends StatelessWidget {
  const _ProviderMenu({required this.controller});

  final AiAssistantController controller;

  @override
  Widget build(BuildContext context) {
    final AiConversation? selected = controller.selectedConversation;
    final AiProvider current = selected?.provider ?? controller.provider;

    return PopupMenuButton<AiProvider>(
      tooltip: 'AI provider',
      icon: const Icon(Icons.auto_awesome_rounded),
      onSelected: (AiProvider provider) {
        if (provider != current) unawaited(controller.setProvider(provider));
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<AiProvider>>[
        for (final AiProvider provider in AiProvider.values)
          PopupMenuItem<AiProvider>(
            value: provider,
            child: Row(
              children: <Widget>[
                if (provider == current)
                  const Icon(Icons.check_rounded, size: 18)
                else
                  const SizedBox(width: 18),
                const SizedBox(width: 10),
                Text(provider.label),
              ],
            ),
          ),
      ],
    );
  }
}

/// A row in the conversation list.
class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.conversation, required this.onTap});

  final AiConversation conversation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return ListTile(
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.auto_awesome_rounded, color: scheme.onPrimaryContainer),
      ),
      title: Text(
        conversation.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '${conversation.provider.label} \u00b7 ${formatChatTime(conversation.updatedAt)}',
        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      ),
      trailing: IconButton(
        tooltip: 'Delete chat',
        icon: const Icon(Icons.delete_outline_rounded),
        onPressed: () => _confirmDelete(context),
      ),
      onTap: onTap,
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Delete this chat?'),
        content: const Text('This deletes the conversation and its history.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      if (!context.mounted) return;
      await AiScope.of(context).deleteConversation(conversation.id);
    }
  }
}

/// A user or assistant message bubble.
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final AiMessage message;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    if (message.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(top: 6, bottom: 6, left: 56),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(6),
            ),
          ),
          child: Text(
            message.content,
            style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onPrimary),
          ),
        ),
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.auto_awesome_rounded,
                size: 16, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              margin: const EdgeInsets.only(top: 2, bottom: 6, right: 56),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(6),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(18),
                ),
              ),
              child: Text(
                message.content,
                style: theme.textTheme.bodyLarge,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Animated "thinking" bubble while the assistant reply is in flight.
class _TypingBubble extends StatefulWidget {
  const _TypingBubble();

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble> {
  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        children: <Widget>[
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.auto_awesome_rounded,
                size: 16, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(width: 8),
          Container(
            margin: const EdgeInsets.only(top: 4, bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(6),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(18),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'LoText AI is thinking\u2026',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
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

/// Error banner shown above the composer when a send fails. The typed text is
/// preserved so the user can simply tap send again.
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Material(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
          child: Row(
            children: <Widget>[
              Icon(Icons.error_outline_rounded, color: scheme.error, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onErrorContainer,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Dismiss',
                onPressed: onDismiss,
                icon: Icon(Icons.close_rounded, color: scheme.error),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
