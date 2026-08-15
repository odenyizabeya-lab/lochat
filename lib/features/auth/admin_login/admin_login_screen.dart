import 'package:flutter/material.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/auth/auth_errors.dart';
import '../../../core/auth/auth_scope.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../../shared/widgets/lotext_button.dart';
import '../../../shared/widgets/lotext_text_field.dart';

/// Dedicated login for the LoText admin account.
///
/// The email is fixed to the app's permanent admin email
/// ([AppConstants.adminEmail]). After a successful sign-in the router sends
/// the admin straight to the Admin dashboard (see the router redirect rules).
class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController =
      TextEditingController(text: AppConstants.adminEmail);
  final TextEditingController _passwordController = TextEditingController();

  bool _isSubmitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final AuthController auth = AuthScope.of(context);
    setState(() => _isSubmitting = true);
    try {
      await auth.signInWithEmail(
        email: AppConstants.adminEmail,
        password: _passwordController.text,
      );
      // The router redirects the admin straight to the Admin dashboard.
    } on Object catch (error) {
      if (!mounted) return;
      AppSnackbars.showError(context, AuthErrors.message(error));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Admin login')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Center(
                      child: Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.admin_panel_settings_rounded,
                          size: 48,
                          color: scheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Admin login',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'This is the permanent admin account. Signing in takes '
                      'you straight to the Admin dashboard.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 32),
                    LoTextTextField(
                      controller: _emailController,
                      label: 'Admin email',
                      icon: Icons.alternate_email_rounded,
                      readOnly: true,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 16),
                    LoTextTextField(
                      controller: _passwordController,
                      label: 'Password',
                      icon: Icons.lock_outline_rounded,
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      autofillHints: const <String>[AutofillHints.password],
                      validator: Validators.password,
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 24),
                    LoTextButton(
                      label: 'Log in',
                      isExpanded: true,
                      isLoading: _isSubmitting,
                      onPressed: _submit,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
