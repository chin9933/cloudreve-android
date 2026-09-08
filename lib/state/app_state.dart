import 'dart:io';

import 'package:cloudreve/entity/login_result.dart';
import 'package:cloudreve/entity/storage_summary.dart';
import 'package:cloudreve/utils/cloudreve_repository.dart';
import 'package:cloudreve/utils/global_setting.dart';
import 'package:cloudreve/utils/http_util.dart';
import 'package:cloudreve/utils/secure_session_store.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppState extends ChangeNotifier {
  bool _isInitialized = false;
  bool _isLoggedIn = false;
  UserData? _userData;
  Storage? _storage;
  Future<void>? _initializing;
  int _sessionGeneration = 0;

  bool get isInitialized => _isInitialized;
  bool get isLoggedIn => _isLoggedIn;
  UserData? get userData => _userData;
  Storage? get storage => _storage;

  Future<void> initialize() {
    _initializing ??= _doInitialize();
    return _initializing!;
  }

  Future<void> _doInitialize() async {
    try {
      HttpUtil.dio.interceptors.add(CookieManager(HttpUtil.cookieJar));
    } catch (_) {
      // ignore duplicate additions
    }

    await _ensurePermissions();
    await _prepareCacheDirectories();

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final bool remembered = prefs.getBool(isRememberKey) ?? false;
    final bool wasLoggedIn = prefs.getBool(isLoginKey) ?? false;

    if (wasLoggedIn && remembered) {
      await _attemptAutoLogin(prefs);
    } else {
      _isLoggedIn = false;
    }

    _isInitialized = true;
    notifyListeners();
  }

  Future<void> _ensurePermissions() async {
    final notificationStatus = await Permission.notification.status;
    if (!notificationStatus.isGranted) {
      await Permission.notification.request();
    }
    final storageStatus = await Permission.storage.status;
    if (!storageStatus.isGranted) {
      await Permission.storage.request();
    }
  }

  Future<void> _prepareCacheDirectories() async {
    final Directory temp = await getTemporaryDirectory();
    final Directory imageTemp = Directory('${temp.path}$cacheImagePath');
    final Directory thumbTemp = Directory('${temp.path}$cacheThumbPath');
    final Directory avatarTemp = Directory('${temp.path}$cacheAvatarPath');
    if (!imageTemp.existsSync()) {
      imageTemp.createSync(recursive: true);
    }
    if (!thumbTemp.existsSync()) {
      thumbTemp.createSync(recursive: true);
    }
    if (!avatarTemp.existsSync()) {
      avatarTemp.createSync(recursive: true);
    }
  }

  Future<void> _attemptAutoLogin(SharedPreferences prefs) async {
    final stored = await SecureSessionStore.read();
    if (stored == null) {
      _isLoggedIn = false;
      return;
    }

    try {
      HttpUtil.switchServer(stored.apiBaseUrl);
      HttpUtil.updateAuthToken(
        accessToken: stored.token.accessToken,
        accessExpires: stored.token.accessExpires,
        refreshToken: stored.token.refreshToken,
        refreshExpires: stored.token.refreshExpires,
        userId: stored.user.id,
      );
      if (!await CloudreveRepository.ensureFreshToken()) {
        throw StateError('登录凭据已过期');
      }
      final Storage storage =
          await CloudreveRepository.fetchStorage() ?? Storage(0, 0, 0);
      _userData = await CloudreveRepository.fetchCurrentUser();
      _storage = storage;
      _isLoggedIn = true;
      await _persistCurrentSession();
    } catch (_) {
      await SecureSessionStore.clear();
      await prefs.setBool(isLoginKey, false);
      HttpUtil.clearAuthToken();
      _isLoggedIn = false;
    }
  }

  void updateSession({required UserData userData, required Storage storage}) {
    _sessionGeneration++;
    _userData = userData;
    _storage = storage;
    _isLoggedIn = true;
    if (!_isInitialized) {
      _isInitialized = true;
    }
    notifyListeners();
  }

  Future<void> refreshSession({bool forceRefresh = false}) async {
    if (!_isLoggedIn || _userData == null) {
      return;
    }
    final generation = _sessionGeneration;
    try {
      if (!await CloudreveRepository.ensureFreshToken()) {
        return;
      }
      final values = await Future.wait<Object?>([
        CloudreveRepository.fetchStorage(forceRefresh: forceRefresh),
        CloudreveRepository.fetchCurrentUser(forceRefresh: forceRefresh),
      ]);
      if (generation != _sessionGeneration || !_isLoggedIn) return;
      _storage = values[0] as Storage? ?? _storage ?? Storage(0, 0, 0);
      _userData = values[1] as UserData;
      await _persistCurrentSession();
      notifyListeners();
    } catch (_) {
      // Keep the current session during transient network failures.
    }
  }

  Future<void> _persistCurrentSession() async {
    final user = _userData;
    final accessToken = HttpUtil.accessToken;
    final accessExpires = HttpUtil.accessTokenExpiresAt;
    final refreshToken = HttpUtil.refreshToken;
    final refreshExpires = HttpUtil.refreshTokenExpiresAt;
    if (user == null ||
        accessToken == null ||
        accessExpires == null ||
        refreshToken == null ||
        refreshExpires == null) {
      return;
    }
    await SecureSessionStore.save(
      apiBaseUrl: HttpUtil.dio.options.baseUrl,
      token: TokenData(
        accessToken: accessToken,
        accessExpires: accessExpires,
        refreshToken: refreshToken,
        refreshExpires: refreshExpires,
      ),
      user: user,
    );
  }

  Future<void> applyNickname(String nickname) async {
    if (_userData == null) return;
    _sessionGeneration++;
    _userData = UserData.fromJson({
      ..._userData!.toJson(),
      'nickname': nickname.trim(),
    });
    notifyListeners();
    await _persistCurrentSession();
  }

  Future<void> logout() async {
    _sessionGeneration++;
    // Start revocation while the token is still available, but never let a
    // server/schema error prevent the local session from being cleared.
    final remoteLogout = CloudreveRepository.signOut().timeout(
      const Duration(seconds: 4),
    );
    HttpUtil.clearAuthToken();
    _userData = null;
    _storage = null;
    _isLoggedIn = false;
    notifyListeners();

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(isLoginKey, false);
    await prefs.remove(usernameKey);
    await prefs.remove(passwordKey);
    await SecureSessionStore.clear();
    try {
      await remoteLogout;
    } catch (_) {
      // Local logout is authoritative; remote token revocation is best effort.
    }
  }
}
