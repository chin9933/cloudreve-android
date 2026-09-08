import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloudreve/entity/login_result.dart';
import 'package:cloudreve/entity/m_file.dart';
import 'package:cloudreve/entity/share_link.dart';
import 'package:cloudreve/entity/site_auth_config.dart';
import 'package:cloudreve/entity/storage_summary.dart';
import 'package:cloudreve/utils/http_util.dart';
import 'package:cloudreve/utils/request_cache.dart';
import 'package:cloudreve_api_client/cloudreve_api_client.dart'
    as cloudreve_api;
import 'package:dio/dio.dart';

class CloudreveRepository {
  CloudreveRepository._();

  static const listingCacheDuration = Duration(seconds: 30);

  static _RepositoryCacheKey _key(String group, Object value) => (
    client: HttpUtil.dio,
    server: HttpUtil.dio.options.baseUrl,
    session: HttpUtil.cacheGeneration,
    group: group,
    value: value,
  );

  static void _invalidate(Set<String> groups) {
    bool matches(Object key) =>
        key is _RepositoryCacheKey && groups.contains(key.group);
    ClientCache.metadata.invalidateWhere(matches);
    ClientCache.search.invalidateWhere(matches);
    ClientCache.images.invalidateWhere(matches);
  }

  static void invalidateFiles() => _invalidate({
    'listing',
    'search',
    'shortcut',
    'capacity',
    'thumbnail',
    'download',
  });

  static void clearCache() => ClientCache.clear();

  static Future<Map<String, dynamic>> _shortcutData(
    String path,
    Map<String, dynamic> query,
  ) => ClientCache.metadata.get(
    _key('shortcut', (path, jsonEncode(query))),
    () => _getData(path, query: query),
    ttl: listingCacheDuration,
  );

  static cloudreve_api.FileApi get _fileApi => HttpUtil.apiClient.getFileApi();

  static cloudreve_api.FileUploadApi get _fileUploadApi =>
      HttpUtil.apiClient.getFileUploadApi();

  static cloudreve_api.UserApi get _userApi => HttpUtil.apiClient.getUserApi();

  static cloudreve_api.ShareApi get _shareApi =>
      HttpUtil.apiClient.getShareApi();

  static cloudreve_api.UserSettingApi get _userSettingApi =>
      HttpUtil.apiClient.getUserSettingApi();

  static Map<String, dynamic> checkedPayload(dynamic payload) {
    if (payload is! Map) throw const CloudreveApiException('服务器返回了无效数据');
    final json = Map<String, dynamic>.from(payload);
    if (json['code'] != 0) {
      throw CloudreveApiException(
        json['msg']?.toString().isNotEmpty == true
            ? json['msg'].toString()
            : '请求失败，请重试',
        code: json['code'] as int?,
      );
    }
    return json;
  }

  static Future<Map<String, dynamic>> _getData(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final response = await HttpUtil.dio.get<dynamic>(
      path,
      queryParameters: query,
    );
    final data = checkedPayload(response.data)['data'];
    if (data is! Map) throw const CloudreveApiException('服务器返回的数据格式不正确');
    return Map<String, dynamic>.from(data);
  }

  static Future<SiteAuthConfig> fetchAuthConfig() async {
    final values = await Future.wait([
      _getData('site/config/basic'),
      _getData('site/config/login'),
    ]);
    return SiteAuthConfig.fromJson(values[0], values[1]);
  }

  static Future<ImageCaptcha> fetchCaptcha() async =>
      ImageCaptcha.fromJson(await _getData('site/captcha'));

  static Future<SharedContent> inspectShareLink(ShareLink link) async {
    final info = await _getData(
      'share/info/${Uri.encodeComponent(link.id)}',
      query: {
        if (link.password.isNotEmpty) 'password': link.password,
        'count_views': false,
      },
    );
    if (info['expired'] == true) throw const CloudreveApiException('分享已过期');
    if (info['unlocked'] != true) {
      throw const CloudreveApiException('请填写正确的分享密码');
    }
    final listing = await _getData(
      'file',
      query: {'uri': link.rootUri, 'page_size': 100},
    );
    return SharedContent(
      link: link,
      name: info['name']?.toString() ?? '分享文件',
      folder: info['source_type'] == 1,
      ownerId: (info['owner'] as Map?)?['id']?.toString() ?? '',
      files: (listing['files'] as List? ?? [])
          .whereType<Map>()
          .map((item) => MFile.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
    );
  }

  static Future<void> importShare(
    SharedContent content,
    String destination, {
    String? name,
  }) async {
    final dst = _buildUri(destination);
    final destinationUri = Uri.parse(dst);
    if (destinationUri.host != 'my' || destinationUri.userInfo.isNotEmpty) {
      throw const CloudreveApiException('只能转存到自己的文件夹');
    }
    final savedName = (name ?? content.name).trim();
    if (savedName.isEmpty ||
        savedName == '.' ||
        savedName == '..' ||
        RegExp(r'[/\\\x00]').hasMatch(savedName)) {
      throw const CloudreveApiException('请输入有效保存名称');
    }
    if (content.ownerId.isEmpty ||
        (!content.folder && content.files.length != 1)) {
      throw const CloudreveApiException('分享信息不完整，请重新读取链接');
    }
    // Match the deployed web client. Community Edition does not support
    // cross-filesystem COPY from share to my (40081). This explicit shortcut
    // keeps the shared target and owner; listing/players resolve the source.
    final target = content.folder
        ? content.link.rootUri
        : content.files.single.contentUri;
    final response = await HttpUtil.dio.post<dynamic>(
      'file/create',
      data: {
        'uri':
            '${dst.replaceFirst(RegExp(r'/$'), '')}/${Uri.encodeComponent(savedName)}',
        'type': content.folder ? 'folder' : 'file',
        'err_on_conflict': true,
        'metadata': {
          'sys:shared_redirect': target,
          'sys:shared_owner': content.ownerId,
        },
      },
    );
    checkedPayload(response.data);
    invalidateFiles();
  }

  static Future<UserData> fetchCurrentUser({bool forceRefresh = false}) =>
      ClientCache.metadata.get(
        _key('profile', 'current'),
        _fetchCurrentUser,
        ttl: const Duration(seconds: 60),
        forceRefresh: forceRefresh,
      );

  static Future<UserData> _fetchCurrentUser() async {
    final data = await _getData('site/config/basic');
    if (data['user'] is! Map || data['user']['anonymous'] == true) {
      throw const CloudreveApiException('登录已过期，请重新登录', code: 401);
    }
    return UserData.fromJson(Map<String, dynamic>.from(data['user'] as Map));
  }

  static Future<LoginResult> signIn({
    required String email,
    required String password,
  }) async {
    // Parse the login response permissively. Some Cloudreve builds return
    // extension fields that the generated OpenAPI model cannot deserialize.
    final response = await HttpUtil.dio.post<Map<String, dynamic>>(
      'session/token',
      data: <String, dynamic>{'email': email, 'password': password},
    );
    final data = response.data;
    if (data == null) {
      HttpUtil.clearAuthToken();
      return LoginResult(code: -1, data: null, msg: '登录失败', error: null);
    }

    final result = LoginResult.fromJson(data);
    if (result.isSuccess && result.data != null) {
      final token = result.data!.token;
      HttpUtil.updateAuthToken(
        accessToken: token.accessToken,
        accessExpires: token.accessExpires,
        refreshToken: token.refreshToken,
        refreshExpires: token.refreshExpires,
        userId: result.data!.user.id,
      );
    } else {
      HttpUtil.clearAuthToken();
    }
    return result;
  }

  static Future<TokenData?>? _refreshingToken;

  static Future<TokenData?> refreshTokenPair() {
    return _refreshingToken ??= _performTokenRefresh().whenComplete(
      () => _refreshingToken = null,
    );
  }

  static Future<TokenData?> _performTokenRefresh() async {
    final baseUrl = HttpUtil.dio.options.baseUrl;
    final refreshToken = HttpUtil.refreshToken;
    final refreshExpires = HttpUtil.refreshTokenExpiresAt;
    if (refreshToken == null ||
        refreshToken.isEmpty ||
        refreshExpires == null ||
        refreshExpires.isBefore(DateTime.now())) {
      return null;
    }

    final refreshClient = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
      ),
    );
    try {
      final response = await refreshClient.post<Map<String, dynamic>>(
        '/session/token/refresh',
        data: <String, dynamic>{'refresh_token': refreshToken},
      );
      final payload = response.data;
      if (payload == null || payload['code'] != 0 || payload['data'] is! Map) {
        return null;
      }

      final token = TokenData.fromJson(
        Map<String, dynamic>.from(payload['data'] as Map),
      );
      if (HttpUtil.refreshToken != refreshToken ||
          HttpUtil.dio.options.baseUrl != baseUrl) {
        return null;
      }
      HttpUtil.updateAuthToken(
        accessToken: token.accessToken,
        accessExpires: token.accessExpires,
        refreshToken: token.refreshToken,
        refreshExpires: token.refreshExpires,
        preserveSession: true,
      );
      return token;
    } finally {
      refreshClient.close();
    }
  }

  static Future<bool> ensureFreshToken() async {
    final expires = HttpUtil.accessTokenExpiresAt;
    if (HttpUtil.accessToken == null || expires == null) {
      return false;
    }
    if (expires.isAfter(DateTime.now().add(const Duration(minutes: 2)))) {
      return true;
    }
    return await refreshTokenPair() != null;
  }

  static Future<void> signOut() async {
    final refreshToken = HttpUtil.refreshToken;
    try {
      // The generated client attempts to deserialize the returned user and
      // fails against servers that expose custom permission fields.
      await HttpUtil.dio.delete<void>(
        'session/token',
        data: refreshToken == null || refreshToken.isEmpty
            ? null
            : <String, dynamic>{'refresh_token': refreshToken},
      );
    } finally {
      // A slow sign-out response must not clear a subsequently signed-in user.
      if (HttpUtil.refreshToken == refreshToken) HttpUtil.clearAuthToken();
    }
  }

  static Future<Storage?> fetchStorage({bool forceRefresh = false}) =>
      ClientCache.metadata.get(
        _key('capacity', 'current'),
        _fetchStorage,
        ttl: const Duration(seconds: 30),
        forceRefresh: forceRefresh,
      );

  static Future<Storage?> _fetchStorage() async {
    final response = await _userApi.userCapacityGet();
    final data = response.data?.data;
    if (data == null) {
      return null;
    }
    return Storage.fromApi(data);
  }

  static Future<List<cloudreve_api.StoragePolicy>> fetchUploadPolicies() =>
      ClientCache.metadata.get(
        _key('policies', 'upload'),
        _fetchUploadPolicies,
        ttl: const Duration(minutes: 2),
      );

  static Future<List<cloudreve_api.StoragePolicy>>
  _fetchUploadPolicies() async {
    try {
      final response = await _userSettingApi.userSettingPoliciesGet();
      final data = response.data;
      if (data == null || (data.code ?? -1) != 0) {
        return const [];
      }
      return data.data?.toList() ?? const [];
    } on DioException catch (error) {
      // Some Cloudreve installations do not expose the optional policy list
      // endpoint. In that case the upload API can select the mounted/default
      // policy when policy_id is omitted.
      if (error.response?.statusCode == 404) {
        return const [];
      }
      rethrow;
    }
  }

  static Future<void> uploadFile({
    required String localPath,
    required String fileName,
    required int fileSize,
    required String targetFolder,
    cloudreve_api.StoragePolicy? policy,
    CancelToken? cancelToken,
    ProgressCallback? onProgress,
  }) async {
    final targetPath = targetFolder == '/'
        ? '/$fileName'
        : '${targetFolder.endsWith('/') ? targetFolder.substring(0, targetFolder.length - 1) : targetFolder}/$fileName';
    final uri = _buildUri(targetPath);
    final source = File(localPath);
    if (!await source.exists()) {
      throw const CloudreveUploadException('无法读取所选文件');
    }
    fileSize = await source.length();

    final request = cloudreve_api.FileUploadPutRequest((b) {
      b
        ..uri = uri
        ..size = fileSize
        ..lastModified = source.lastModifiedSync().millisecondsSinceEpoch;
      final policyId = policy?.id;
      if (policyId != null && policyId.isNotEmpty) {
        b.policyId = policyId;
      }
    });
    final createResponse = await _fileUploadApi.fileUploadPut(
      fileUploadPutRequest: request,
      cancelToken: cancelToken,
    );
    final response = createResponse.data;
    final session = response?.data;
    if (response == null ||
        (response.code ?? -1) != 0 ||
        session == null ||
        session.sessionId == null) {
      throw CloudreveUploadException(response?.msg ?? '创建上传会话失败');
    }

    final sessionId = session.sessionId!;
    try {
      final policyType = session.storagePolicy?.type;
      final relayed = session.storagePolicy?.relay == true;
      final isRemote =
          policyType == cloudreve_api.StoragePolicyTypeEnum.remote && !relayed;
      if (!isRemote &&
          policyType != cloudreve_api.StoragePolicyTypeEnum.local &&
          !relayed) {
        throw CloudreveUploadException(
          '首版暂不支持 ${policyType?.name ?? '未知'} 存储策略上传',
        );
      }

      final chunkSize = session.chunkSize == null || session.chunkSize! <= 0
          ? fileSize
          : session.chunkSize!;
      final randomAccess = await source.open();
      var offset = 0;
      var index = 0;
      try {
        do {
          final remaining = fileSize - offset;
          final length = fileSize == 0
              ? 0
              : (remaining < chunkSize ? remaining : chunkSize);
          final bytes = await randomAccess.read(length);
          if (bytes.length != length) {
            throw const CloudreveUploadException('上传期间源文件发生变化，请重新选择文件');
          }
          if (isRemote) {
            final uploadUrls = session.uploadUrls?.toList() ?? const <String>[];
            if (uploadUrls.isEmpty || session.credential == null) {
              throw const CloudreveUploadException('远程上传地址或凭据缺失');
            }
            final uploadUri = Uri.parse(uploadUrls.first);
            final query = Map<String, String>.from(uploadUri.queryParameters)
              ..['chunk'] = index.toString();
            final remoteClient = Dio();
            try {
              final chunkResult = await remoteClient.postUri<dynamic>(
                uploadUri.replace(queryParameters: query),
                data: Stream<List<int>>.value(bytes),
                options: Options(
                  contentType: 'application/octet-stream',
                  headers: <String, dynamic>{
                    'Authorization': session.credential,
                    'Content-Length': length,
                  },
                ),
                cancelToken: cancelToken,
                onSendProgress: (sent, _) =>
                    onProgress?.call(offset + sent, fileSize),
              );
              checkedPayload(chunkResult.data);
            } finally {
              remoteClient.close();
            }
          } else {
            final chunk = MultipartFile.fromBytes(bytes, filename: fileName);
            final chunkResult = await _fileUploadApi
                .fileUploadSessionIdIndexPost(
                  sessionId: sessionId,
                  index: index,
                  contentLength: length,
                  body: chunk,
                  cancelToken: cancelToken,
                  onSendProgress: (sent, _) =>
                      onProgress?.call(offset + sent, fileSize),
                );
            if (chunkResult.data?.code != 0) {
              throw CloudreveUploadException(chunkResult.data?.msg ?? '上传分片失败');
            }
          }
          offset += length;
          index++;
        } while (offset < fileSize);
      } finally {
        await randomAccess.close();
      }
    } catch (_) {
      try {
        final deleteRequest = cloudreve_api.FileUploadDeleteRequest(
          (b) => b
            ..id = sessionId
            ..uri = uri,
        );
        await _fileUploadApi.fileUploadDelete(
          fileUploadDeleteRequest: deleteRequest,
        );
      } catch (_) {
        // The server may already have closed the upload session.
      }
      rethrow;
    }
    invalidateFiles();
  }

  static Future<FileListing> listFiles(
    String path, {
    int page = 0,
    int pageSize = 100,
    String? nextPageToken,
    bool forceRefresh = false,
  }) async {
    if (forceRefresh) _invalidate({'shortcut', 'search'});
    final key = _listingKey(
      path,
      page: page,
      pageSize: pageSize,
      nextPageToken: nextPageToken,
    );
    final listing = await ClientCache.metadata.get(
      key,
      () => _listFiles(
        path,
        page: page,
        pageSize: pageSize,
        nextPageToken: nextPageToken,
      ),
      ttl: listingCacheDuration,
      forceRefresh: forceRefresh,
      weightOf: (listing) => listing.files.length + 1,
    );
    return listing.copy(path: path);
  }

  static _RepositoryCacheKey _listingKey(
    String path, {
    int page = 0,
    int pageSize = 100,
    String? nextPageToken,
  }) {
    var uri = _buildUri(path);
    if (uri == 'cloudreve://my/') uri = 'cloudreve://my';
    return _key('listing', (uri, page, pageSize, nextPageToken ?? ''));
  }

  static FileListing? peekFiles(String path) => ClientCache.metadata
      .peek<FileListing>(_listingKey(path))
      ?.copy(path: path);

  static String _searchPath(String keyword) => keyword.trim().isEmpty
      ? '/'
      : 'cloudreve://my?name=${Uri.encodeComponent(keyword.trim())}';

  static FileListing? peekSearch(String keyword) {
    final key = _key('search', keyword.trim());
    var listing = ClientCache.search.peek<FileListing>(key);
    // Seed once from the existing root/listing cache without a loading flash.
    if (listing == null &&
        keyword.trim().isEmpty &&
        !ClientCache.search.isPending(key)) {
      listing = peekFiles(_searchPath(keyword));
      if (listing != null) {
        ClientCache.search.put(
          key,
          listing,
          ttl: null,
          weightOf: (value) => value.files.length + 1,
        );
      }
    }
    return listing?.copy(path: '/');
  }

  static Future<FileListing> _listFiles(
    String path, {
    int page = 0,
    int pageSize = 100,
    String? nextPageToken,
  }) async {
    final scope = _key('listing', 'scope');
    final uri = path == '/' || path.isEmpty
        ? 'cloudreve://my'
        : _buildUri(path);
    final response = await _fileApi.fileGet(
      uri: uri,
      page: page,
      pageSize: pageSize,
      nextPageToken: nextPageToken,
    );

    final data = response.data;
    if (scope != _key('listing', 'scope')) {
      throw const CloudreveApiException('登录状态已变化，请重新加载');
    }
    if (data == null || (data.code ?? -1) != 0) {
      throw CloudreveApiException(data?.msg ?? '文件列表加载失败', code: data?.code);
    }

    final list = data.data;
    if (list == null) {
      return FileListing.empty(path);
    }

    final fileResponses =
        list.files?.toList() ?? const <cloudreve_api.FileResponse>[];
    final files = fileResponses.map(MFile.fromFileResponse).toList();
    await _hydrateShortcuts(files);
    final map = <String, cloudreve_api.FileResponse>{};
    for (final file in fileResponses) {
      final id = file.id;
      if (id != null && id.isNotEmpty) {
        map[id] = file;
      }
    }
    return FileListing(
      path: path,
      files: files,
      contextHint: list.contextHint ?? '',
      fileMap: map,
      raw: data,
    );
  }

  static Future<FileListing> search(
    String keyword, {
    bool forceRefresh = false,
  }) async {
    final path = _searchPath(keyword);
    final listing = await ClientCache.search.get(
      _key('search', keyword.trim()),
      () async {
        if (!forceRefresh) {
          // Only the empty query shares the root request. Named searches must
          // never resurrect an older, short-lived directory-query snapshot.
          return path == '/' ? listFiles(path) : _listFiles(path);
        }
        _invalidate({'shortcut'});
        if (path != '/') return _listFiles(path);
        // Refresh this query without invalidating our own in-flight request.
        return ClientCache.metadata.get(
          _listingKey(path),
          () => _listFiles(path),
          ttl: listingCacheDuration,
          forceRefresh: true,
          weightOf: (value) => value.files.length + 1,
        );
      },
      ttl: null,
      forceRefresh: forceRefresh,
      weightOf: (value) => value.files.length + 1,
    );
    return listing.copy(path: '/');
  }

  static Future<cloudreve_api.FileCreatePost200Response?> createDirectory(
    String currentPath,
    String folderName,
  ) async {
    final fullPath = currentPath.endsWith('/')
        ? '$currentPath$folderName'
        : '$currentPath/$folderName';
    final request = cloudreve_api.FileCreatePostRequest(
      (b) => b
        ..uri = _buildUri(fullPath)
        ..type = cloudreve_api.FileCreatePostRequestTypeEnum.folder
        ..errOnConflict = true,
    );
    final response = await _fileApi.fileCreatePost(
      fileCreatePostRequest: request,
    );
    if (response.data?.code == 0) invalidateFiles();
    return response.data;
  }

  static Future<void> _hydrateShortcuts(List<MFile> files) async {
    final links = files.where((file) => file.shortcutUri != null).toList();
    // Resolve only shortcuts, with a small bound to avoid flooding the server.
    for (var offset = 0; offset < links.length; offset += 4) {
      await Future.wait(
        links.skip(offset).take(4).map((file) async {
          try {
            await resolveShortcut(file);
          } catch (_) {
            file.contentError = '分享已失效或无权访问';
          }
        }),
      );
    }
  }

  static Future<void> resolveShortcut(
    MFile file, {
    Set<String>? visited,
  }) async {
    final target = file.shortcutUri;
    if (target == null) return;
    final seen = visited ?? <String>{};
    if (seen.length >= 8 || !seen.add(target)) {
      throw const CloudreveApiException('分享快捷方式存在循环');
    }
    final uri = Uri.tryParse(target);
    if (uri == null ||
        uri.scheme != 'cloudreve' ||
        !['share', 'shared_with_me'].contains(uri.host) ||
        uri.userInfo.isEmpty) {
      throw const CloudreveApiException('分享快捷方式地址无效');
    }
    if (file.type == 'dir') {
      file.resolvedUri = target;
      return;
    }
    // Like the web client, refresh the share root to survive owner renames.
    final listing = await _shortcutData('file', {
      'uri': uri.replace(path: '', query: null, fragment: null).toString(),
      'page_size': 100,
    });
    final entries = (listing['files'] as List? ?? []).whereType<Map>().toList();
    Map? source;
    if (listing['single_file_view'] == true && entries.length == 1) {
      source = entries.single;
    } else {
      for (final entry in entries) {
        if (entry['path'] == target) {
          source = entry;
          break;
        }
      }
      source ??= await _shortcutData('file/info', {'uri': target});
    }
    final actual = MFile.fromJson(Map<String, dynamic>.from(source));
    if (actual.shortcutUri != null) {
      await resolveShortcut(actual, visited: seen);
    }
    file.resolvedUri = actual.contentUri;
    file.size = actual.size;
    file.contentVersion = actual.contentVersion ?? actual.date;
    file.contentContextHint =
        actual.contentContextHint ?? listing['context_hint']?.toString();
    file.contentError = null;
  }

  static Future<bool> deleteFiles({List<String> fileUris = const []}) async {
    if (fileUris.isEmpty) {
      return false;
    }
    final request = cloudreve_api.FileDeleteRequest(
      (b) => b..uris.replace(fileUris),
    );
    final response = await _fileApi.fileDelete(fileDeleteRequest: request);
    if (response.data?.code == 0) invalidateFiles();
    return response.data?.code == 0;
  }

  static Future<String?> createDownloadUrl(
    String fileUri, {
    String? contextHint,
  }) => ClientCache.metadata.get(
    _key('download', (fileUri, contextHint ?? '')),
    () => _createDownloadUrl(fileUri, contextHint: contextHint),
    ttl: Duration.zero,
  );

  static Future<String?> _createDownloadUrl(
    String fileUri, {
    String? contextHint,
  }) async {
    final request = cloudreve_api.FileUrlPostRequest(
      (b) => b
        ..uris.replace([_buildUri(fileUri)])
        ..noCache = true,
    );
    final response = await _fileApi.fileUrlPost(
      fileUrlPostRequest: request,
      xCrContextHint: contextHint,
    );

    final data = response.data;
    if (data == null || (data.code ?? -1) != 0) {
      return null;
    }
    final payload = data.data;
    final urls = payload?.urls;
    if (urls == null || urls.isEmpty) {
      return null;
    }
    final firstUrl = urls.first;
    return firstUrl.url;
  }

  static Future<Uint8List?> fetchThumbnailBytes(String fileUri) =>
      ClientCache.images.get(
        _key('thumbnail', fileUri),
        () => _fetchThumbnailBytes(fileUri),
        ttl: const Duration(minutes: 2),
        weightOf: (bytes) => bytes?.length ?? 1,
      );

  static Future<Uint8List?> _fetchThumbnailBytes(String fileUri) async {
    final response = await _fileApi.fileThumbGet(uri: fileUri);
    final data = response.data;
    if (data == null || (data.code ?? -1) != 0) {
      return null;
    }
    final thumb = data.data;
    if (thumb == null || thumb.obfuscated == true) {
      return null;
    }
    final url = thumb.url;
    if (url == null || url.isEmpty) {
      return null;
    }
    return fetchRaw(url);
  }

  static Future<cloudreve_api.FileThumbGet200Response?> fetchThumbnail(
    String fileUri,
  ) async {
    final response = await _fileApi.fileThumbGet(uri: fileUri);
    return response.data;
  }

  static Future<cloudreve_api.FileInfoGet200Response?> fetchFileInfo(
    String fileUri, {
    bool extended = false,
    bool folderSummary = false,
  }) async {
    final response = await _fileApi.fileInfoGet(
      uri: fileUri,
      extended: extended,
      folderSummary: folderSummary,
    );
    return response.data;
  }

  static Future<bool> renameEntry({
    required String fileUri,
    required String newName,
  }) async {
    final name = newName.trim();
    if (name.isEmpty ||
        name == '.' ||
        name == '..' ||
        RegExp(r'[/\\\x00]').hasMatch(name)) {
      throw const CloudreveApiException('请输入有效文件名，不能包含斜杠');
    }
    // The generated rename request incorrectly describes a FileResponse.
    // Cloudreve's actual RenameFileService accepts uri + new_name.
    final response = await HttpUtil.dio.post<dynamic>(
      'file/rename',
      data: {'uri': _buildUri(fileUri), 'new_name': name},
    );
    checkedPayload(response.data);
    invalidateFiles();
    return true;
  }

  static Future<cloudreve_api.FileRenamePost200Response?> renameFile({
    required cloudreve_api.FileRenamePostRequest request,
  }) async {
    final response = await _fileApi.fileRenamePost(
      fileRenamePostRequest: request,
    );
    if (response.data?.code == 0) invalidateFiles();
    return response.data;
  }

  static Future<cloudreve_api.FileMovePost200Response?> moveFiles({
    required cloudreve_api.FileMovePostRequest request,
  }) async {
    final response = await _fileApi.fileMovePost(fileMovePostRequest: request);
    if (response.data?.code == 0) invalidateFiles();
    return response.data;
  }

  static Future<LoginResult> register({
    required String email,
    required String password,
    String? captcha,
    String? ticket,
  }) async {
    final response = await HttpUtil.dio.post<Map<String, dynamic>>(
      'user',
      data: {
        'email': email.trim(),
        'password': password,
        'language': 'zh-CN',
        if (captcha != null) 'captcha': captcha.trim(),
        'ticket': ?ticket,
      },
    );
    final data = response.data;
    if (data == null) {
      return LoginResult(code: -1, data: null, msg: null, error: null);
    }
    return LoginResult(
      code: data['code'] as int? ?? -1,
      data: null,
      msg: data['msg']?.toString(),
      error: data['error']?.toString(),
      correlationId: data['correlation_id']?.toString(),
    );
  }

  static Future<Uint8List?> fetchRaw(String url) async {
    // Signed object URLs can belong to another server. Never attach the user's
    // API token/cookies, including when a URL redirects to a storage provider.
    final client = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
      ),
    );
    try {
      final target = Uri.parse(HttpUtil.dio.options.baseUrl).resolve(url);
      final response = await client.get<List<int>>(
        target.toString(),
        options: Options(responseType: ResponseType.bytes),
      );
      return response.data == null ? null : Uint8List.fromList(response.data!);
    } finally {
      client.close();
    }
  }

  static Future<Response<Uint8List>> fetchAvatar({
    required String userId,
    bool nocache = false,
  }) {
    return ClientCache.images.get(
      _key('avatar', userId),
      () async {
        final response = await HttpUtil.dio.get<Uint8List>(
          '/user/avatar/$userId',
          queryParameters: nocache ? <String, dynamic>{'nocache': true} : null,
          options: Options(responseType: ResponseType.bytes),
        );
        return response;
      },
      ttl: const Duration(minutes: 10),
      forceRefresh: nocache,
      weightOf: (response) => response.data?.length ?? 1,
    );
  }

  static Future<ShareListResult> fetchMyShares({
    int pageSize = 50,
    String? orderBy,
    String? orderDirection,
    String? nextPageToken,
  }) async {
    final response = await _shareApi.shareGet(
      pageSize: pageSize,
      orderBy: orderBy,
      orderDirection: orderDirection,
      nextPageToken: nextPageToken,
    );
    final data = response.data;
    if (data == null || (data.code ?? -1) != 0) {
      return ShareListResult.empty();
    }
    final list = data.data;
    if (list == null) {
      return ShareListResult.empty();
    }
    return ShareListResult(
      shares: list.shares?.toList() ?? const [],
      pagination: list.pagination,
    );
  }

  static cloudreve_api.PermissionSetting _defaultSharePermissions() {
    return cloudreve_api.PermissionSetting((b) {
      b
        ..anonymous = 'BQ=='
        ..everyone = 'AQ==';
    });
  }

  static Future<cloudreve_api.SharePut200Response?> createShare({
    required String uri,
    cloudreve_api.PermissionSetting? permissions,
    bool? isPrivate,
    bool? shareView,
    int? expire,
    int? price,
    String? password,
    bool? showReadme,
  }) async {
    final request = cloudreve_api.ShareCreateService((b) {
      b
        ..permissions.replace(permissions ?? _defaultSharePermissions())
        ..uri = uri
        ..shareView = shareView
        ..expire = expire
        ..price = price
        ..showReadme = showReadme
        ..isPrivate = isPrivate
        ..password = password;
    });
    final response = await _shareApi.sharePut(shareCreateService: request);
    return response.data;
  }

  static Future<cloudreve_api.ShareIdPost200Response?> updateShare({
    required String shareId,
    cloudreve_api.PermissionSetting? permissions,
    required String uri,
    bool? shareView,
    int? expire,
    int? price,
    bool? showReadme,
  }) async {
    final request = cloudreve_api.ShareIdPostRequest((b) {
      b
        ..permissions.replace(permissions ?? _defaultSharePermissions())
        ..uri = uri
        ..shareView = shareView
        ..expire = expire
        ..price = price
        ..showReadme = showReadme;
    });
    final response = await _shareApi.shareIdPost(
      id: shareId,
      shareIdPostRequest: request,
    );
    if (response.data?.code == 0) invalidateFiles();
    return response.data;
  }

  static Future<bool> deleteShare(String shareId) async {
    final response = await _shareApi.shareIdDelete(id: shareId);
    final data = response.data;
    if (data?.code == 0) invalidateFiles();
    return data != null && data.code == 0;
  }

  static Future<cloudreve_api.UserSettingPatch200Response?> updateNickname(
    String nick,
  ) async {
    final request = cloudreve_api.UserSettingPatchRequest(
      (b) => b..nick = nick.trim(),
    );
    final response = await _userSettingApi.userSettingPatch(
      userSettingPatchRequest: request,
    );
    if (response.data?.code == 0) _invalidate({'profile'});
    return response.data;
  }

  static Future<cloudreve_api.UserSettingPatch200Response?> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final request = cloudreve_api.UserSettingPatchRequest(
      (b) => b
        ..currentPassword = currentPassword
        ..newPassword = newPassword,
    );
    final response = await _userSettingApi.userSettingPatch(
      userSettingPatchRequest: request,
    );
    return response.data;
  }

  static Future<cloudreve_api.UserSettingAvatarPut200Response?>
  setAvatarFromGravatar() async {
    final response = await _userSettingApi.userSettingAvatarPut();
    if (response.data?.code == 0) _invalidate({'avatar', 'profile'});
    return response.data;
  }

  static Future<cloudreve_api.UserSettingAvatarPut200Response?>
  uploadAvatarBytes(List<int> bytes) async {
    final file = MultipartFile.fromBytes(bytes);
    final response = await _userSettingApi.userSettingAvatarPut(body: file);
    if (response.data?.code == 0) _invalidate({'avatar', 'profile'});
    return response.data;
  }

  static Future<List<cloudreve_api.DavAccount>> fetchWebDavAccounts({
    int pageSize = 100,
    String? nextPageToken,
  }) async {
    final accounts = <cloudreve_api.DavAccount>[];
    final seen = <String>{};
    String? cursor = nextPageToken;
    do {
      final response = await HttpUtil.dio.get<dynamic>(
        'devices/dav',
        queryParameters: {'page_size': pageSize, 'next_page_token': ?cursor},
      );
      final data = checkedPayload(response.data)['data'];
      // Current servers return an object; older generated schemas describe a list.
      final sections = data is Map
          ? [data]
          : data is List
          ? data
          : [];
      cursor = null;
      for (final section in sections.whereType<Map>()) {
        for (final item
            in (section['accounts'] as List? ?? const []).whereType<Map>()) {
          accounts.add(
            cloudreve_api.DavAccount(
              (b) => b
                ..id = item['id']?.toString()
                ..name = item['name']?.toString()
                ..uri = item['uri']?.toString()
                ..password = item['password']?.toString()
                ..createdAt = DateTime.tryParse(
                  item['created_at']?.toString() ?? '',
                )
                ..options = item['options']?.toString(),
            ),
          );
        }
        cursor = (section['pagination'] as Map?)?['next_token']?.toString();
      }
      if (cursor != null && cursor.isNotEmpty && !seen.add(cursor)) {
        throw const CloudreveApiException('WebDAV 分页异常，请重试');
      }
    } while (cursor != null && cursor.isNotEmpty);
    return accounts;
  }

  static String _buildUri(String path) {
    if (path.startsWith('cloudreve://')) return Uri.parse(path).toString();
    final trimmed = path.isEmpty ? '/' : path;
    if (trimmed == '/' || trimmed == '') {
      return 'cloudreve://my';
    }
    final segments = trimmed
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .map(Uri.encodeComponent)
        .join('/');
    return 'cloudreve://my/$segments';
  }
}

class CloudreveApiException implements Exception {
  const CloudreveApiException(this.message, {this.code});
  final String message;
  final int? code;
  @override
  String toString() => message;
}

class FileListing {
  FileListing({
    required this.path,
    required this.files,
    required this.contextHint,
    required this.fileMap,
    this.raw,
  });

  FileListing.empty(this.path)
    : files = const [],
      contextHint = '',
      fileMap = const <String, cloudreve_api.FileResponse>{},
      raw = null;

  final String path;
  final List<MFile> files;
  final String contextHint;
  final Map<String, cloudreve_api.FileResponse> fileMap;
  final cloudreve_api.FileGet200Response? raw;

  FileListing copy({String? path}) => FileListing(
    path: path ?? this.path,
    files: files.map((file) => file.copy()).toList(),
    contextHint: contextHint,
    fileMap: Map.of(fileMap),
    raw: raw,
  );

  cloudreve_api.FileResponse? findResponseById(String id) => fileMap[id];
}

typedef _RepositoryCacheKey = ({
  Object client,
  String server,
  int session,
  String group,
  Object value,
});

class ShareListResult {
  ShareListResult({required this.shares, required this.pagination});

  ShareListResult.empty() : shares = const [], pagination = null;

  final List<cloudreve_api.Share> shares;
  final cloudreve_api.ListShareResponsePagination? pagination;

  String? get nextToken {
    final token = pagination?.nextToken;
    if (token == null || token.isEmpty) {
      return null;
    }
    return token;
  }
}

class CloudreveUploadException implements Exception {
  const CloudreveUploadException(this.message);

  final String message;

  @override
  String toString() => message;
}
