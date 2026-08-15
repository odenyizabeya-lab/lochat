import 'package:flutter/widgets.dart';

import 'managed_account_controller.dart';

class ManagedAccountScope extends InheritedNotifier<ManagedAccountController> {
  const ManagedAccountScope({
    super.key,
    required ManagedAccountController controller,
    required super.child,
  }) : super(notifier: controller);

  static ManagedAccountController of(BuildContext context) {
    final ManagedAccountScope? scope =
        context.dependOnInheritedWidgetOfExactType<ManagedAccountScope>();
    if (scope == null) {
      throw AssertionError('No ManagedAccountScope found in the widget tree.');
    }
    return scope.notifier!;
  }

  static ManagedAccountController? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ManagedAccountScope>()?.notifier;
  }
}