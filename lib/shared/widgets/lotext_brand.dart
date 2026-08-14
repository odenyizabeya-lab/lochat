import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';

/// The LoText logo mark: the official logo image (a chat bubble containing
/// the "LoText" wordmark).
class LoTextLogo extends StatelessWidget {
  const LoTextLogo({super.key, this.size = 56});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/logo.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );
  }
}

/// Logo mark plus the "LoText" wordmark, used on onboarding screens. The logo
/// image already contains the wordmark, so it is not repeated by default.
class LoTextBrand extends StatelessWidget {
  const LoTextBrand({super.key, this.size = 56, this.showWordmark = false});

  final double size;
  final bool showWordmark;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        LoTextLogo(size: size),
        if (showWordmark) ...<Widget>[
          SizedBox(height: size * 0.24),
          Text(
            AppConstants.appName,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ],
    );
  }
}
