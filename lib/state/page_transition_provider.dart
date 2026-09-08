import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum PageTransitionStyle { none, fade, slide, scale }

extension PageTransitionStyleLabel on PageTransitionStyle {
  String get label => switch (this) {
    PageTransitionStyle.none => '关闭',
    PageTransitionStyle.fade => '淡入淡出',
    PageTransitionStyle.slide => '平滑滑动',
    PageTransitionStyle.scale => '轻柔缩放',
  };

  Duration get duration => switch (this) {
    PageTransitionStyle.none => Duration.zero,
    PageTransitionStyle.fade => const Duration(milliseconds: 180),
    PageTransitionStyle.slide => const Duration(milliseconds: 240),
    PageTransitionStyle.scale => const Duration(milliseconds: 220),
  };
}

class PageTransitionProvider extends ChangeNotifier {
  static const preferenceKey = 'settings.page_transition_style';

  PageTransitionStyle _style = PageTransitionStyle.slide;
  Future<void>? _initializing;
  SharedPreferences? _preferences;

  PageTransitionStyle get style => _style;

  Future<void> initialize() {
    _initializing ??= _load();
    return _initializing!;
  }

  Future<void> _load() async {
    final preferences = await SharedPreferences.getInstance();
    _preferences = preferences;
    final savedStyle = preferences.getString(preferenceKey);
    final restored = PageTransitionStyle.values.where(
      (style) => style.name == savedStyle,
    );
    if (restored.isEmpty || restored.first == _style) return;
    _style = restored.first;
    notifyListeners();
  }

  Future<void> setStyle(PageTransitionStyle style) async {
    await initialize();
    if (_style == style) return;
    _style = style;
    notifyListeners();
    await _preferences!.setString(preferenceKey, style.name);
  }
}
