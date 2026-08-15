import 'package:flutter/material.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/auth/auth_errors.dart';
import '../../../core/auth/auth_scope.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../../shared/widgets/lotext_button.dart';
import '../../../shared/widgets/lotext_text_field.dart';
import 'totp_setup_screen.dart';

/// The second verification step shown to the admin after their password.
///
/// The admin picks one of two methods:
///   * email code: a 6-digit code emailed by Supabase Auth;
///   * authenticator app: a TOTP code from a factor enrolled via GoTrue MFA.
///
/// The screen stays up while [AuthController.twoFactorPending] is true; the
/// router hands control to the Admin dashboard once the code verifies.
class TwoFactorScreen extends StatefulWidget {
  const TwoFactorScreen({super.key});

  @override
  State<TwoFactorScreen> createState() => _TwoFactorScreenState();
}

enum _Method { email, totp }

class _TwoFactorScreenState extends State<TwoFactorScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _codeController = TextEditingController();

  _Method _method = _Method.email;
  bool _codeSent = false;
  bool _isBusy = false;

  /// Whether the signed-in admin has a verified TOTP factor.
  bool? _totpAvailable;

  /// The pending TOTP challenge, once started.
  TotpChallenge? _challenge;

  AuthController get _auth => AuthScope.of(context);

  String get _email => _auth.currentUser?.email ?? AppConstants.adminEmail;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _sendEmailCode() async {
    setState(() => _isBusy = true);
    try {
      await _auth.sendEmailCode(email: _email);
      if (!mounted) return;
      setState(() => _codeSent = true);
      AppSnackbars.showInfo(context, 'Code sent to $_email.');
    } on Object catch (error) {
      if (!mounted) return;
      AppSnackbars.showError(context, AuthErrors.message(error));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _selectMethod(_Method method) async {
    if (method == _method) return;
    setState(() {
      _method = method;
      _challenge = null;
      _codeController.clear();
    });
    if (method == _Method.totp && _totpAvailable == null) {
      setState(() => _isBusy = true);
      try {
        final bool available = await _auth.hasTotpFactor();
        if (!mounted) return;
        setState(() => _totpAvailable = available);
        if (available) {
          await _startChallenge();
        }
      } on Object catch (error) {
        if (!mounted) return;
        AppSnackbars.showError(context, AuthErrors.message(error));
      } finally {
        if (mounted) setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _startChallenge() async {
    final TotpChallenge challenge = await _auth.startTotpChallenge();
    if (!mounted) return;
    setState(() => _challenge = challenge);
  }

  Future<void> _verify() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final String code = _codeController.text.trim();
    setState(() => _isBusy = true);
    try {
      if (_method == _Method.email) {
        await _auth.verifyEmailCode(email: _email, code: code);
      } else {
        final TotpChallenge? challenge = _challenge;
        if (challenge == null) return;
        await _auth.verifyTotp(
          factorId: challenge.factorId,
          challengeId: challenge.challengeId,
          code: code,
        );
      }
      if (!mounted) return;
      _auth.completeTwoFactor();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _codeController.clear());
      AppSnackbars.showError(context, AuthErrors.message(error));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _openTotpSetup() async {
    final bool? activated = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (BuildContext context) {
        return const TotpSetupScreen();
      }),
    );
    if (!mounted) return;
    if (activated == true) {
      setState(() => _totpAvailable = true);
      _auth.completeTwoFactor();
    }
  }

  Future<void> _signOut() async {
    await _auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Two-factor verification')),
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
                          Icons.verified_user_rounded,
                          size: 48,
                          color: scheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Almost there',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'One more step to keep your admin account safe. '
                      'Enter the 6-digit code from your email or your '
                      'authenticator app.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 24),
                    SegmentedButton<_Method>(
                      segments: const <ButtonSegment<_Method>>[
                        ButtonSegment<_Method>(
                          value: _Method.email,
                          label: Text('Email code'),
                          icon: Icon(Icons.email_outlined),
                        ),
                        ButtonSegment<_Method>(
                          value: _Method.totp,
                          label: Text('Authenticator'),
                          icon: Icon(Icons.smartphone_rounded),
                        ),
                      ],
                      selected: <_Method>{_method},
                      onSelectionChanged: (Set<_Method> selection) {
                        _selectMethod(selection.first);
                      },
                    ),
                    const SizedBox(height: 24),
                    if (_method == _Method.email) _buildEmailSection(theme, scheme)
                    else _buildTotpSection(theme, scheme),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: _isBusy ? null : _signOut,
                      child: const Text('Sign out instead'),
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

  Widget _buildEmailSection(ThemeData theme, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          _codeSent
              ? 'A verification code has been sent to $_email.'
              : 'We will email a 6-digit code to $_email.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        if (_codeSent) ...<Widget>[
          LoTextTextField(
            controller: _codeController,
            label: 'Verification code',
            icon: Icons.pin_outlined,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            validator: Validators.code,
            onFieldSubmitted: (_) => _verify(),
          ),
          const SizedBox(height: 16),
          LoTextButton(
            label: 'Verify & continue',
            isExpanded: true,
            isLoading: _isBusy,
            onPressed: _verify,
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _isBusy ? null : _sendEmailCode,
            child: const Text('Resend code'),
          ),
        ] else ...<Widget>[
          LoTextButton(
            label: 'Send code',
            icon: Icons.send_outlined,
            isExpanded: true,
            isLoading: _isBusy,
            onPressed: _sendEmailCode,
          ),
        ],
      ],
    );
  }

  Widget _buildTotpSection(ThemeData theme, ColorScheme scheme) {
    if (_totpAvailable == false) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'You have not set up an authenticator app yet. Set one up now '
            'to use it for this step.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          LoTextButton(
            label: 'Set up authenticator app',
            icon: Icons.add_box_outlined,
            isExpanded: true,
            isLoading: _isBusy,
            onPressed: _openTotpSetup,
          ),
        ],
      );
    }
    if (_totpAvailable == null || _challenge == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'Enter the 6-digit code shown in your authenticator app.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        LoTextTextField(
          controller: _codeController,
          label: 'Authenticator code',
          icon: Icons.pin_outlined,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          validator: Validators.code,
          onFieldSubmitted: (_) => _verify(),
        ),
        const SizedBox(height: 16),
        LoTextButton(
          label: 'Verify & continue',
          isExpanded: true,
          isLoading: _isBusy,
          onPressed: _verify,
        ),
      ],
    );
  }
}
