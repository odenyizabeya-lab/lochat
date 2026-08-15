import 'package:flutter/widgets.dart';

import 'managed_account_controller.dart';
import 'data/supabase_managed_account_repository.dart';
import 'data/supabase_managed_chat_repository.dart';

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
      // Fallback: create a default controller with Supabase repositories
      final String tempAdminUid = 'temp-admin';
      final ManagedAccountController defaultController =
          ManagedAccountController(
        accountRepository: SupabaseManagedAccountRepository(),
        chatRepository: SupabaseManagedChatRepository(),
        adminUid: tempAdminUid,
      )..load();
      return defaultController;
    }
    return scope.notifier!;
  }

  static ManagedAccountController? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ManagedAccountScope>()?.notifier;
  }
}