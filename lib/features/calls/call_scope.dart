import 'package:flutter/widgets.dart';

import 'call_controller.dart';

/// Exposes the app-wide [CallController] to descendant widgets.
class CallScope extends InheritedNotifier<CallController> {
  const CallScope({
    super.key,
    required CallController controller,
    required super.child,
  }) : super(notifier: controller);

  static CallController of(BuildContext context) {
    final CallScope? scope =
        context.dependOnInheritedWidgetOfExactType<CallScope>();
    assert(scope != null, 'No CallScope found in the widget tree.');
    return scope!.notifier!;
  }

  static CallController? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<CallScope>()?.notifier;
  }
}
