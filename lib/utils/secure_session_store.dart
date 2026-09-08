import 'dart:convert';

import 'package:cloudreve/entity/login_result.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StoredSession {
  const StoredSession({
    required this.apiBaseUrl,
    required this.token,
    required this.user,
  });

  final String apiBaseUrl;
  final TokenData token;
  final UserData user;
}

class SecureSessionStore {
  SecureSessionStore._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const String _sessionKey = 'cloudreve_session_v1';

  static Future<void> save({
    required String apiBaseUrl,
    required TokenData token,
    required UserData user,
  }) async {
    final payload = jsonEncode(<String, dynamic>{
      'api_base_url': apiBaseUrl,
      'token': token.toJson(),
      'user': user.toJson(),
    });
    await _storage.write(key: _sessionKey, value: payload);
  }

  static Future<StoredSession?> read() async {
    final payload = await _storage.read(key: _sessionKey);
    if (payload == null || payload.isEmpty) {
      return null;
    }

    try {
      final json = jsonDecode(payload) as Map<String, dynamic>;
      return StoredSession(
        apiBaseUrl: json['api_base_url'] as String,
        token: TokenData.fromJson(json['token'] as Map<String, dynamic>),
        user: UserData.fromJson(json['user'] as Map<String, dynamic>),
      );
    } catch (_) {
      await clear();
      return null;
    }
  }

  static Future<void> clear() => _storage.delete(key: _sessionKey);
}
