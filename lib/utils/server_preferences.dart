import 'package:cloudreve/utils/global_setting.dart';
import 'package:cloudreve/utils/http_util.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Server selection is saved by URL, not an index into a build-dependent list.
class ServerPreferences {
  const ServerPreferences(this.urls, this.selectedUrl);

  static const listKey = 'servers.v2';
  static const selectionKey = 'servers.selected.v2';
  final List<String> urls;
  final String selectedUrl;

  static String normalizeOrEmpty(String? value) {
    if (value == null || value.trim().isEmpty) return '';
    try {
      return HttpUtil.normalizeApiBaseUrl(value);
    } on FormatException {
      return '';
    }
  }

  static ServerPreferences read(
    SharedPreferences prefs, {
    String currentUrl = '',
    String defaultUrl = '',
  }) {
    final migrated = prefs.containsKey(listKey);
    final legacy = prefs.getStringList(urlsKey) ?? const <String>[];
    final current = normalizeOrEmpty(currentUrl);
    final fallback = normalizeOrEmpty(defaultUrl);
    final candidates = migrated
        ? prefs.getStringList(listKey) ?? const <String>[]
        : <String>[
            if (current.isNotEmpty) current,
            if (fallback.isNotEmpty) fallback,
            ...legacy,
          ];
    final urls = candidates
        .map(normalizeOrEmpty)
        .where((url) => url.isNotEmpty)
        .toSet()
        .toList();
    String selected;
    if (migrated) {
      selected = normalizeOrEmpty(prefs.getString(selectionKey));
    } else if (current.isNotEmpty) {
      selected = current;
    } else if (prefs.containsKey(selectedIndexKey)) {
      // The old implicit entry 0 was not persisted. Do not guess its address.
      final index = (prefs.getInt(selectedIndexKey) ?? 0) - 1;
      selected = index >= 0 && index < legacy.length
          ? normalizeOrEmpty(legacy[index])
          : '';
    } else {
      selected = fallback;
    }
    return ServerPreferences(urls, urls.contains(selected) ? selected : '');
  }

  Future<void> save(SharedPreferences prefs) async {
    await prefs.setStringList(listKey, urls);
    await prefs.setString(selectionKey, selectedUrl);
  }
}
