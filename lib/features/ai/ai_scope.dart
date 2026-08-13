import 'package:flutter/widgets.dart';

import 'ai_assistant_controller.dart';

/// Exposes the app-wide [AiAssistantController] to descendant widgets.
class AiScope extends InheritedNotifier<AiAssistantController> {
  const AiScope({
    super.key,
    required AiAssistantController controller,
    required super.child,
  }) : super(notifier: controller);

  static AiAssistantController of(BuildContext context) {
    final AiScope? scope =
        context.dependOnInheritedWidgetOfExactType<AiScope>();
    assert(scope != null, 'No AiScope found in the widget tree.');
    return scope!.notifier!;
  }

  static AiAssistantController? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AiScope>()?.notifier;
  }
}
