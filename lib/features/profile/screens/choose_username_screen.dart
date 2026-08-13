import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/utils/validators.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../../shared/widgets/lotext_button.dart';
import '../data/profile_repository.dart';
import '../profile_controller.dart';
import '../profile_scope.dart';

/// First-run screen shown until the signed-in user claims a unique username.
/// The app router blocks access to the main screens until this completes.
class ChooseUsernameScreen extends StatefulWidget {
  const ChooseUsernameScreen({super.key});

  @override
  State<ChooseUsernameScreen> createState() => _ChooseUsernameScreenState();
}

enum _Availability { unknown, checking, available, taken }

class _ChooseUsernameScreenState extends State<ChooseUsernameScreen> {
  final TextEditingController _usernameController = TextEditingController();

  Timer? _debounce;
  _Availability _availability = _Availability.unknown;
  bool _submitting = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _usernameController.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    setState(() => _availability = _Availability.unknown);
    _debounce = Timer(const Duration(milliseconds: 400), _checkAvailability);
  }

  Future<void> _checkAvailability() async {
    final String name = Validators.normalizeUsername(_usernameController.text);
    final String? validationError = Validators.username(name);
    if (validationError != null || name.isEmpty) {
      if (!mounted) return;
      setState(() => _availability = _Availability.unknown);
      return;
    }

    final ProfileController controller = ProfileScope.of(context);
    // A user re-typing their own current username is always available to
    // them (only relevant on the edit screen, kept here for safety).
    if (controller.profile?.username == name) {
      if (!mounted) return;
      setState(() => _availability = _Availability.available);
      return;
    }

    if (!mounted) return;
    setState(() => _availability = _Availability.checking);

    try {
      final bool available = await controller.isUsernameAvailable(name);
      if (!mounted) return;
      setState(() {
        _availability = available ? _Availability.available : _Availability.taken;
      });
    } catch (_) {
      if (!mounted) return;
      // Availability is unknown; don't block the UI, but don't claim either.
      setState(() => _availability = _Availability.unknown);
    }
  }

  bool get _isValid =>
      Validators.username(Validators.normalizeUsername(_usernameController.text)) ==
      null;

  bool get _canContinue => _isValid && _availability == _Availability.available && !_submitting;

  Future<void> _continue() async {
    if (!_canContinue) return;
    final ProfileController controller = ProfileScope.of(context);
    setState(() => _submitting = true);
    try {
      await controller.setUsername(
        Validators.normalizeUsername(_usernameController.text),
      );
      // Router redirects to the main screen once the username is set.
    } on UsernameUnavailableException {
      if (!mounted) return;
      setState(() => _availability = _Availability.taken);
    } catch (_) {
      if (!mounted) return;
      AppSnackbars.showError(context, 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose your username'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Icon(Icons.alternate_email_rounded, size: 56, color: scheme.primary),
                  const SizedBox(height: 16),
                  Text(
                    'Claim your @username',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'This is how people will find you on LoText. It must be '
                    'unique, 3-20 characters, and use only letters, numbers, '
                    'and underscores.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _usernameController,
                    onChanged: _onChanged,
                    textInputAction: TextInputAction.done,
                    autofocus: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    inputFormatters: <TextInputFormatter>[
                      LengthLimitingTextInputFormatter(20),
                      TextInputFormatter.withFunction(
                        (TextEditingValue oldValue, TextEditingValue newValue) {
                          final String lower = newValue.text.toLowerCase();
                          return newValue.copyWith(
                            text: lower,
                            selection: TextSelection.collapsed(offset: lower.length),
                          );
                        },
                      ),
                      FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9_]')),
                    ],
                    decoration: InputDecoration(
                      labelText: 'Username',
                      prefixText: '@ ',
                      hintText: 'jerry_2026',
                      errorText: _availability == _Availability.taken
                          ? 'Username already taken'
                          : Validators.username(
                              Validators.normalizeUsername(_usernameController.text),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildStatus(theme, scheme),
                  const SizedBox(height: 24),
                  LoTextButton(
                    label: 'Continue',
                    isExpanded: true,
                    isLoading: _submitting,
                    onPressed: _canContinue ? _continue : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatus(ThemeData theme, ColorScheme scheme) {
    switch (_availability) {
      case _Availability.checking:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Text('Checking availability\u2026', style: theme.textTheme.bodySmall),
          ],
        );
      case _Availability.available:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.check_circle_rounded, size: 16, color: Color(0xFF16A34A)),
            const SizedBox(width: 8),
            Text(
              'Username available',
              style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xFF16A34A)),
            ),
          ],
        );
      case _Availability.taken:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.cancel_rounded, size: 16, color: scheme.error),
            const SizedBox(width: 8),
            Text(
              'Username already taken',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
            ),
          ],
        );
      case _Availability.unknown:
        return const SizedBox.shrink();
    }
  }
}
