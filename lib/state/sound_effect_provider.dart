import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores the device-level preference for Material interaction feedback.
///
/// This preference is deliberately isolated from music and video playback. It
/// must only be wired to Material widgets' `enableFeedback` properties.
class SoundEffectProvider extends ChangeNotifier {
  static const preferenceKey = 'ui_sound_effects_enabled';

  bool _enabled = true;
  Future<void>? _initializing;
  SharedPreferences? _preferences;

  bool get enabled => _enabled;

  Future<void> initialize() {
    _initializing ??= _load();
    return _initializing!;
  }

  Future<void> _load() async {
    final preferences = await SharedPreferences.getInstance();
    _preferences = preferences;
    final storedValue = preferences.getBool(preferenceKey) ?? true;
    final changed = _enabled != storedValue;
    _enabled = storedValue;
    if (changed) notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    await initialize();
    if (_enabled == value) return;

    _enabled = value;
    notifyListeners();
    await _preferences!.setBool(preferenceKey, value);
  }
}
