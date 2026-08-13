import 'dart:async';

import 'package:flutter/widgets.dart';

import 'profile_controller.dart';
import 'profile_scope.dart';

/// Records online/offline presence based on app lifecycle transitions.
///
/// Writes happen only on meaningful transitions (app start, resume,
/// background, sign-out) - never on a timer, so Firestore is not spammed.
class PresenceObserver extends StatefulWidget {
  const PresenceObserver({super.key, required this.child});

  final Widget child;

  @override
  State<PresenceObserver> createState() => _PresenceObserverState();
}

class _PresenceObserverState extends State<PresenceObserver>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ProfileController? controller = ProfileScope.maybeOf(context);
    if (controller == null) return;
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(controller.setOnline());
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        unawaited(controller.setOffline());
      case AppLifecycleState.inactive:
        break; // transient (dialogs, app switcher); keep current state
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
