import 'package:flutter/widgets.dart';

import 'chat_controller.dart';

/// Exposes the app-wide [ChatController] to descendant widgets.
class ChatScope extends InheritedNotifier<ChatController> {
  const ChatScope({
    super.key,
    required ChatController controller,
    required super.child,
  }) : super(notifier: controller);

  static ChatController of(BuildContext context) {
    final ChatScope? scope =
        context.dependOnInheritedWidgetOfExactType<ChatScope>();
    assert(scope != null, 'No ChatScope found in the widget tree.');
    return scope!.notifier!;
  }

  static ChatController? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ChatScope>()?.notifier;
  }
}
