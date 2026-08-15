import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/auth/auth_errors.dart';
import '../../../core/auth/auth_scope.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../../shared/widgets/lotext_button.dart';
import '../../../shared/widgets/lotext_text_field.dart';

/// Enrolls a TOTP authenticator factor for the admin account.
///
/// Shows the newly generated secret, then asks the admin to type the current
/// code from their authenticator app to activate the factor. Pops with `true`
/// once activated (the session is then at the required assurance level).
class TotpSetupScreen extends StatefulWidget {
  const TotpSetupScreen({super.key});

  @override
  State<TotpSetupScreen> createState() => _TotpSetupScreenState();
}

class _TotpSetupScreenState extends State<TotpSetupScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _codeController = TextEditingController();

  TotpEnrollment? _enrollment;
  bool _isBusy = false;
  bool _failed = false;
  bool _startedEnrollment = false;

  AuthController get _auth => AuthScope.of(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The auth controller is looked up via an inherited widget, which is only
    // allowed from didChangeDependencies (not initState).
    if (!_startedEnrollment) {
      _startedEnrollment = true;
      _enroll();
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _enroll() async {
    setState(() {
      _isBusy = true;
      _failed = false;
    });
    try {
      final TotpEnrollment enrollment = await _auth.enrollTotp();
      if (!mounted) return;
      setState(() => _enrollment = enrollment);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _failed = true);
      AppSnackbars.showError(context, AuthErrors.message(error));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _copySecret() async {
    final String? secret = _enrollment?.secret;
    if (secret == null) return;
    await Clipboard.setData(ClipboardData(text: secret));
    if (!mounted) return;
    AppSnackbars.showInfo(context, 'Secret copied to your clipboard.');
  }

  Future<void> _activate() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final TotpEnrollment? enrollment = _enrollment;
    if (enrollment == null) return;
    final String code = _codeController.text.trim();
    setState(() => _isBusy = true);
    try {
      final TotpChallenge challenge = await _auth.startTotpChallenge(
        factorId: enrollment.factorId,
      );
      await _auth.verifyTotp(
        factorId: challenge.factorId,
        challengeId: challenge.challengeId,
        code: code,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _codeController.clear());
      AppSnackbars.showError(context, AuthErrors.message(error));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Set up authenticator')),
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
                          Icons.qr_code_2_rounded,
                          size: 48,
                          color: scheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Add this account to your authenticator app',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Open your authenticator app (Google Authenticator, '
                      'Aegis, Authy, ...), add a new account, and paste this '
                      'secret. Then enter the 6-digit code it shows to '
                      'activate.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (_enrollment != null) ...<Widget>[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            SelectableText(
                              _enrollment!.secret,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontFamily: 'monospace',
                                letterSpacing: 1.5,
                              ),
                            ),
                            const SizedBox(height: 12),
                            LoTextButton(
                              label: 'Copy secret',
                              icon: Icons.copy_rounded,
                              variant: LoTextButtonVariant.outline,
                              onPressed: _copySecret,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      LoTextTextField(
                        controller: _codeController,
                        label: '6-digit code',
                        icon: Icons.pin_outlined,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        validator: Validators.code,
                        onFieldSubmitted: (_) => _activate(),
                      ),
                      const SizedBox(height: 16),
                      LoTextButton(
                        label: 'Activate',
                        isExpanded: true,
                        isLoading: _isBusy,
                        onPressed: _activate,
                      ),
                    ] else if (_failed) ...<Widget>[
                      Text(
                        'Could not start the authenticator setup.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.error,
                        ),
                      ),
                      const SizedBox(height: 16),
                      LoTextButton(
                        label: 'Try again',
                        isExpanded: true,
                        isLoading: _isBusy,
                        onPressed: _enroll,
                      ),
                    ] else ...<Widget>[
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ],
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
