import 'package:flutter/widgets.dart';

import 'profile_controller.dart';

/// Exposes the app-wide [ProfileController] to descendant widgets.
class ProfileScope extends InheritedNotifier<ProfileController> {
  const ProfileScope({
    super.key,
    required ProfileController controller,
    required super.child,
  }) : super(notifier: controller);

  static ProfileController of(BuildContext context) {
    final ProfileScope? scope =
        context.dependOnInheritedWidgetOfExactType<ProfileScope>();
    assert(scope != null, 'No ProfileScope found in the widget tree.');
    return scope!.notifier!;
  }

  static ProfileController? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ProfileScope>()?.notifier;
  }
}
