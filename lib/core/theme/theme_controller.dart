import 'package:flutter/material.dart';

/// Holds the app-wide theme preference (system / light / dark).
///
/// Listened to by [LoTextApp] so switching the mode here rebuilds the
/// whole [MaterialApp] with the matching [ThemeData].
class ThemeController extends ChangeNotifier {
  ThemeController([this._mode = ThemeMode.system]);

  ThemeMode _mode;

  ThemeMode get mode => _mode;

  void setMode(ThemeMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
  }
}
