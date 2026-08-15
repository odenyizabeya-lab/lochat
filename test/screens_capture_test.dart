import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lotext/core/theme/app_theme.dart';
import 'package:lotext/features/auth/admin_login/admin_login_screen.dart';
import 'package:lotext/features/auth/login/login_screen.dart';
import 'package:lotext/features/auth/register/register_screen.dart';
import 'package:lotext/features/auth/welcome/welcome_screen.dart';

const String _fontsDir = 'C:/src/flutter/bin/cache/artifacts/material_fonts';

Future<void> _loadRealFonts() async {
  final List<String> names = <String>[
    'roboto-regular.ttf',
    'roboto-medium.ttf',
    'roboto-bold.ttf',
    'roboto-italic.ttf',
  ];
  for (final String name in names) {
    final Uint8List bytes =
        File('$_fontsDir/$name').readAsBytesSync();
    final FontLoader loader = FontLoader('Roboto')
      ..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)));
    await loader.load();
  }
}

void main() {
  setUpAll(() async {
    await _loadRealFonts();
  });

  Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(411, 890);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        debugShowCheckedModeBanner: false,
        home: screen,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('welcome page capture', (WidgetTester tester) async {
    await pumpScreen(tester, const WelcomeScreen());
    await expectLater(
      find.byType(WelcomeScreen),
      matchesGoldenFile('goldens/welcome.png'),
    );
  });

  testWidgets('login page capture', (WidgetTester tester) async {
    await pumpScreen(tester, const LoginScreen());
    await expectLater(
      find.byType(LoginScreen),
      matchesGoldenFile('goldens/login.png'),
    );
  });

  testWidgets('register page capture', (WidgetTester tester) async {
    await pumpScreen(tester, const RegisterScreen());
    await expectLater(
      find.byType(RegisterScreen),
      matchesGoldenFile('goldens/register.png'),
    );
  });

  testWidgets('admin login page capture', (WidgetTester tester) async {
    await pumpScreen(tester, const AdminLoginScreen());
    await expectLater(
      find.byType(AdminLoginScreen),
      matchesGoldenFile('goldens/admin_login.png'),
    );
  });
}
