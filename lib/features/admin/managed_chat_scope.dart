import 'package:flutter/widgets.dart';

import 'managed_chat_controller.dart';

class ManagedChatScope extends InheritedNotifier<ManagedChatController> {
  const ManagedChatScope({
    super.key,
    required ManagedChatController controller,
    required super.child,
  }) : super(notifier: controller);

  static ManagedChatController of(BuildContext context) {
    final ManagedChatScope? scope =
        context.dependOnInheritedWidgetOfExactType<ManagedChatScope>();
    assert(scope != null, 'No ManagedChatScope found in the widget tree.');
    return scope!.notifier!;
  }

  static ManagedChatController? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ManagedChatScope>()?.notifier;
  }
}
