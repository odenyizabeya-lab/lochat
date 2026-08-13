import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/router/app_routes.dart';
import '../../../shared/widgets/lotext_brand.dart';
import '../../../shared/widgets/lotext_button.dart';

/// First post-splash screen: introduces LoText and points to
/// account creation or log in.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const SizedBox(height: 24),
                  const LoTextBrand(size: 88, showWordmark: false),
                  const SizedBox(height: 28),
                  Text(
                    'Welcome to LoText',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    AppConstants.tagline,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 40),
                  LoTextButton(
                    label: 'Create your account',
                    isExpanded: true,
                    onPressed: () => context.go(AppRoutes.register),
                  ),
                  const SizedBox(height: 12),
                  LoTextButton(
                    label: 'Log in',
                    variant: LoTextButtonVariant.secondary,
                    isExpanded: true,
                    onPressed: () => context.go(AppRoutes.login),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    '${AppConstants.appName} ${AppConstants.version}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
