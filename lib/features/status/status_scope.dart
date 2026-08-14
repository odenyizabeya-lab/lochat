import 'package:flutter/widgets.dart';

import 'status_controller.dart';

/// Exposes the app-wide [StatusController] to descendant widgets.
class StatusScope extends InheritedNotifier<StatusController> {
  const StatusScope({
    super.key,
    required StatusController controller,
    required super.child,
  }) : super(notifier: controller);

  static StatusController of(BuildContext context) {
    final StatusScope? scope =
        context.dependOnInheritedWidgetOfExactType<StatusScope>();
    assert(scope != null, 'No StatusScope found in the widget tree.');
    return scope!.notifier!;
  }

  static StatusController? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<StatusScope>()?.notifier;
  }
}
