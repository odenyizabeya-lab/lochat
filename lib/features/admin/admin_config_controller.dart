import 'package:flutter/foundation.dart';

import 'data/app_config_repository.dart';

/// Loads and edits the admin-managed app configuration (AI provider keys).
///
/// Resolves [isAdmin] from the user's profile row so the admin screen can show
/// a restricted message to non-admins before any data is fetched.
class AdminConfigController extends ChangeNotifier {
  AdminConfigController({required this._repository});

  final AppConfigRepository _repository;

  bool _isAdmin = false;
  bool _isLoading = true;
  Object? _error;
  Map<String, String> _values = <String, String>{};

  bool get isAdmin => _isAdmin;
  bool get isLoading => _isLoading;
  bool get hasError => _error != null;
  Object? get error => _error;
  Map<String, String> get values => _values;

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _isAdmin = await _repository.isAdmin();
      _values = _isAdmin
          ? Map<String, String>.from(await _repository.fetchAll())
          : <String, String>{};
      _isLoading = false;
    } on Exception catch (e) {
      _error = e;
      _isLoading = false;
    }
    notifyListeners();
  }

  /// Whether a config key currently has a non-empty value.
  bool hasValue(String key) => (_values[key] ?? '').isNotEmpty;

  /// The stored value for a config key, or null when unset.
  String? valueOf(String key) => _values[key];

  Future<void> setValue(String key, String value) async {
    final String trimmed = value.trim();
    await _repository.setValue(key, trimmed);
    _values[key] = trimmed;
    notifyListeners();
  }

  Future<void> remove(String key) async {
    await _repository.remove(key);
    _values.remove(key);
    notifyListeners();
  }
}
