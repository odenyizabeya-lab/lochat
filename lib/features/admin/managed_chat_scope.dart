import 'package:flutter/widgets.dart';

import './managed_chat_controller.dart';
import './data/supabase_managed_account_repository.dart';
import './data/supabase_managed_chat_repository.dart';
import './managed_account_controller.dart';
import './managed_account_scope.dart';

class ManagedChatScope extends InheritedNotifier<ManagedChatController> {
  const ManagedChatScope({
    super.key,
    required ManagedChatController controller,
    required super.child,
  }) : super(notifier: controller);

  static ManagedChatController of(BuildContext context) {
    final ManagedChatScope? scope =
        context.dependOnInheritedWidgetOfExactType<ManagedChatScope>();
    if (scope == null) {
      // Fallback: create a default chat controller
      final ManagedAccountController accountController =
          ManagedAccountScope.maybeOf(context) ??
          ManagedAccountController(
            accountRepository: SupabaseManagedAccountRepository(),
            chatRepository: SupabaseManagedChatRepository(),
            adminUid: 'temp-admin',
          )..load();
      final ManagedChatController defaultController =
          ManagedChatController(
        chatRepository: SupabaseManagedChatRepository(),
        accountController: accountController,
      );
      return defaultController;
    }
    return scope.notifier!;
  }

  static ManagedChatController? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ManagedChatScope>()?.notifier;
  }
}