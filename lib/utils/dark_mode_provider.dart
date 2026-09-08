import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DarkModeProvider with ChangeNotifier {
  static const String preferenceKey = 'settings.dark_mode';

  DarkMode _darkMode = DarkMode.auto;
  Future<void>? _initializing;
  SharedPreferences? _preferences;

  DarkMode get darkMode => _darkMode;

  Future<void> initialize() {
    _initializing ??= _load();
    return _initializing!;
  }

  Future<void> _load() async {
    String? savedMode;
    try {
      final preferences = await SharedPreferences.getInstance();
      _preferences = preferences;
      savedMode = preferences.getString(preferenceKey);
    } catch (_) {
      // A corrupt local preference must not block the very first app frame.
      return;
    }
    final restored = DarkMode.values.where((mode) => mode.name == savedMode);
    if (restored.isEmpty || restored.first == _darkMode) return;
    _darkMode = restored.first;
    notifyListeners();
  }

  Future<void> changeMode(DarkMode darkMode) async {
    await initialize();
    if (_darkMode == darkMode) return;
    _preferences ??= await SharedPreferences.getInstance();
    _darkMode = darkMode;
    notifyListeners();
    await _preferences!.setString(preferenceKey, darkMode.name);
  }
}

enum DarkMode { close, open, auto }
