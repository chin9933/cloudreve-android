import 'dart:async';
import 'dart:convert';

import 'package:cloudreve/entity/share_link.dart';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Only fingerprints are retained, never link text or extraction passwords.
abstract final class ShareClipboardHistory {
  static const _key = 'share_clipboard_seen_v1';
  static Future<void>? _writing;

  static Future<bool> claim(ShareLink link, {required String scope}) async {
    while (_writing != null) {
      await _writing;
    }
    final done = Completer<void>();
    _writing = done.future;
    try {
      final fingerprint = sha256
          .convert(utf8.encode(jsonEncode([scope, link.id, link.password])))
          .toString();
      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getStringList(_key) ?? <String>[];
      if (seen.contains(fingerprint)) return false;
      final updated = [...seen, fingerprint];
      // Small bounded history survives reopening the app/dialog.
      return await prefs.setStringList(
        _key,
        updated.skip(updated.length > 512 ? updated.length - 512 : 0).toList(),
      );
    } finally {
      _writing = null;
      done.complete();
    }
  }
}
