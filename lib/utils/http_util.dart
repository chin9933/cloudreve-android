import 'dart:io';

import 'package:cloudreve/config/app_config.dart';
import 'package:cloudreve/utils/request_cache.dart';

import 'package:cloudreve_api_client/cloudreve_api_client.dart'
    as cloudreve_api;
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HttpUtil {
  static CookieJar cookieJar = CookieJar();

  static const String defaultSiteUrl = AppConfig.defaultSiteUrl;
  static final String defaultApiBaseUrl = defaultSiteUrl.trim().isEmpty
      ? ''
      : normalizeApiBaseUrl(defaultSiteUrl);

  static final String _baseUrl = defaultApiBaseUrl;

  static final BaseOptions _normalOption = BaseOptions(
    baseUrl: _baseUrl,
    connectTimeout: const Duration(milliseconds: 10000),
    receiveTimeout: const Duration(milliseconds: 10000),
  );
  static Dio dio = Dio(_normalOption);

  static String? _accessToken;
  static DateTime? _accessTokenExpiresAt;
  static String? _refreshToken;
  static DateTime? _refreshTokenExpiresAt;
  static cloudreve_api.CloudreveApiClient? _apiClient;
  static Dio? _clientDio;
  static int cacheGeneration = 0;
  static String? cacheUserId;

  static cloudreve_api.CloudreveApiClient get apiClient {
    if (!identical(_clientDio, dio)) {
      _apiClient = null;
      _clientDio = dio;
    }
    _apiClient ??= cloudreve_api.CloudreveApiClient(
      dio: dio,
      serializers: cloudreve_api.standardSerializers,
    );
    return _apiClient!;
  }

  static String normalizeApiBaseUrl(String value) {
    final trimmed = value.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('请输入有效的 HTTPS Cloudreve 地址');
    }

    var path = uri.path;
    if (path.isEmpty || path == '/') {
      path = '/api/v4/';
    } else if (path.endsWith('/api/v4')) {
      path = '$path/';
    } else if (!path.endsWith('/api/v4/')) {
      path = '${path.endsWith('/') ? path : '$path/'}api/v4/';
    }

    return uri.replace(path: path, query: null, fragment: null).toString();
  }

  static void switchServer(String value) {
    dio.options.baseUrl = normalizeApiBaseUrl(value);
    clearAuthToken();
  }

  static void clearServer() {
    dio.options.baseUrl = '';
    clearAuthToken();
  }

  static void updateAuthToken({
    required String accessToken,
    required DateTime accessExpires,
    required String refreshToken,
    required DateTime refreshExpires,
    bool preserveSession = false,
    String? userId,
  }) {
    if (!preserveSession) {
      cacheGeneration++;
      cacheUserId = userId;
      ClientCache.clear();
    }
    _accessToken = accessToken;
    _accessTokenExpiresAt = accessExpires;
    _refreshToken = refreshToken;
    _refreshTokenExpiresAt = refreshExpires;
    dio.options.headers['Authorization'] = 'Bearer $accessToken';
  }

  static void clearAuthToken() {
    cacheGeneration++;
    cacheUserId = null;
    ClientCache.clear();
    _accessToken = null;
    _accessTokenExpiresAt = null;
    _refreshToken = null;
    _refreshTokenExpiresAt = null;
    dio.options.headers.remove('Authorization');
  }

  static String? get accessToken => _accessToken;

  static DateTime? get accessTokenExpiresAt => _accessTokenExpiresAt;

  static String? get refreshToken => _refreshToken;

  static DateTime? get refreshTokenExpiresAt => _refreshTokenExpiresAt;
}

class GetCookieInterceptor extends CookieManager {
  GetCookieInterceptor(super.cookieJar);

  @override
  Future<void> onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) async {
    final cookies = response.headers[HttpHeaders.setCookieHeader];
    if (cookies != null && cookies.isNotEmpty) {
      await _saveCookie(cookies[0]);
    }
    handler.next(response);
  }

  Future<void> _saveCookie(String cookie) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(HttpHeaders.cookieHeader, cookie.toString());
  }
}
