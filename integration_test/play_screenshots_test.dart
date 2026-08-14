// Real store screenshots.
//
// Runs the REAL app (real main.dart, real Supabase) on an Android emulator or
// device and captures PNGs of the key screens through flutter drive:
//
//   flutter drive \
//     --driver=test_driver/integration_test.dart \
//     --target=integration_test/play_screenshots_test.dart \
//     --dart-define=LOTEXT_SUPABASE_URL=... \
//     --dart-define=LOTEXT_SUPABASE_KEY=... \
//     --dart-define=PLAY_EMAIL=... \
//     --dart-define=PLAY_PASSWORD=...
//
// If the account is already signed in on the device the test skips login and
// goes straight to the screens. Screenshots are written to
// docs/play/screenshots/ by the driver.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:lotext/main.dart' as app;
import 'package:lotext/shared/widgets/lotext_button.dart';

const String _email = String.fromEnvironment('PLAY_EMAIL');
const String _password = String.fromEnvironment('PLAY_PASSWORD');

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 40),
}) async {
  final DateTime end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}

Future<void> _pumpUntilAny(
  WidgetTester tester,
  List<Finder> finders, {
  Duration timeout = const Duration(seconds: 40),
}) async {
  final DateTime end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 250));
    for (final Finder finder in finders) {
      if (finder.evaluate().isNotEmpty) return;
    }
  }
  fail('Timed out waiting for any of $finders');
}

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('capture real screenshots', (WidgetTester tester) async {
    await app.main();
    await tester.pump(const Duration(milliseconds: 300));

    // On Android the Flutter surface must be converted to an image before
    // screenshots can be taken (no-op on other platforms).
    await binding.convertFlutterSurfaceToImage();

    // Wait for either the signed-out welcome screen or the signed-in shell.
    final Finder welcome = find.text('Welcome to LoText');
    final Finder shell = find.byType(NavigationBar);
    final DateTime deadline = DateTime.now().add(const Duration(seconds: 40));
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 250));
      if (welcome.evaluate().isNotEmpty ||
          shell.evaluate().isNotEmpty) {
        break;
      }
    }

    if (welcome.evaluate().isNotEmpty) {
      expect(
        _email.isNotEmpty && _password.isNotEmpty,
        isTrue,
        reason: 'PLAY_EMAIL and PLAY_PASSWORD must be passed via '
            '--dart-define to log in for screenshots.',
      );
      await tester.tap(find.text('Log in'));
      await _pumpUntil(tester, find.text('Welcome back'));

      await tester.enterText(find.byType(TextFormField).at(0), _email);
      await tester.enterText(find.byType(TextFormField).at(1), _password);
      await tester.testTextInput.receiveAction(TextInputAction.done);

      await _pumpUntil(tester, find.widgetWithText(LoTextButton, 'Log in'));
      await tester.tap(find.widgetWithText(LoTextButton, 'Log in'));

      // Router redirects to Home once signed in and the profile is loaded.
      await _pumpUntil(tester, find.byType(NavigationBar));
    }

    // 1. Chats tab (the messenger home).
    await _pumpUntilAny(
      tester,
      <Finder>[find.text('No conversations yet'), find.byType(ListTile)],
    );
    await tester.pump(const Duration(milliseconds: 800));
    await binding.takeScreenshot('1_chats');

    // 2. A conversation, if the account has one.
    final Finder tiles = find.descendant(
      of: find.byType(Scrollable).first,
      matching: find.byType(ListTile),
    );
    if (tiles.evaluate().isNotEmpty) {
      await tester.tap(tiles.first);
      await _pumpUntil(tester, find.byTooltip('Attach'));
      await tester.pump(const Duration(milliseconds: 1500));
      await binding.takeScreenshot('2_chat');
      // Back to the shell.
      await tester.tap(find.byType(BackButton));
      await _pumpUntil(tester, find.byType(NavigationBar));
    }

    // 3. Tools hub.
    await tester.tap(find.text('Tools'));
    await _pumpUntil(tester, find.text('LAST 7 DAYS PERFORMANCE'));
    await tester.pump(const Duration(milliseconds: 800));
    await binding.takeScreenshot('3_tools');

    // 4. Profile screen.
    await tester.tap(find.text('Profile'));
    await _pumpUntil(
      tester,
      find.widgetWithText(AppBar, 'Profile'),
    );
    await tester.pump(const Duration(milliseconds: 800));
    await binding.takeScreenshot('4_profile');
    await tester.tap(find.byType(BackButton));
    await _pumpUntil(tester, find.byType(NavigationBar));

    // 5. Settings screen.
    await tester.tap(find.text('Settings'));
    await _pumpUntil(
      tester,
      find.widgetWithText(AppBar, 'Settings'),
    );
    await tester.pump(const Duration(milliseconds: 800));
    await binding.takeScreenshot('5_settings');
  });
}
