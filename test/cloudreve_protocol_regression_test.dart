import 'dart:convert';
import 'dart:typed_data';

import 'package:cloudreve/entity/login_result.dart';
import 'package:cloudreve/entity/m_file.dart';
import 'package:cloudreve/entity/share_link.dart';
import 'package:cloudreve/entity/storage_summary.dart';
import 'package:cloudreve/state/app_state.dart';
import 'package:cloudreve/utils/cloudreve_repository.dart';
import 'package:cloudreve/utils/http_util.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class ProtocolAdapter implements HttpClientAdapter {
  ProtocolAdapter(this.respond);
  final Object Function(RequestOptions) respond;
  final List<RequestOptions> requests = [];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(respond(options)),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> mediaFile({
  String name = 'song.flac',
  int size = 144449051,
  Map<String, String>? metadata,
  String? path,
}) => {
  'id': 'test-file',
  'type': 0,
  'name': name,
  'size': size,
  'path': path ?? 'cloudreve://my/$name',
  'metadata': metadata ?? {},
  'updated_at': '2026-09-05T00:00:00Z',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProtocolAdapter adapter;
  void mock(Object Function(RequestOptions) response) {
    adapter = ProtocolAdapter(response);
    HttpUtil.dio = Dio(
      BaseOptions(baseUrl: 'https://cloud.example.com/api/v4/'),
    )..httpClientAdapter = adapter;
    HttpUtil.clearAuthToken();
  }

  tearDown(HttpUtil.clearAuthToken);

  test('registration forwards site captcha and ticket, retaining email activation result', () async {
    mock((_) => {'code': 203, 'msg': 'Activation required'});
    final result = await CloudreveRepository.register(
      email: ' test@example.test ',
      password: 'test-password',
      captcha: ' 1234 ',
      ticket: 'ticket-1',
    );
    expect(result.code, 203);
    expect(adapter.requests.single.uri.path, '/api/v4/user');
    expect(adapter.requests.single.data, {
      'email': 'test@example.test',
      'password': 'test-password',
      'language': 'zh-CN',
      'captcha': '1234',
      'ticket': 'ticket-1',
    });
  });
  test(
    'registration reads the actual basic and login config sections',
    () async {
      mock(
        (request) => {
          'code': 0,
          'data': request.path.endsWith('basic')
              ? {'captcha_type': 'normal'}
              : {'reg_captcha': true, 'register_enabled': true},
        },
      );
      final config = await CloudreveRepository.fetchAuthConfig();
      expect(config.registerCaptcha, isTrue);
      expect(config.registerEnabled, isTrue);
      expect(config.captchaType, 'normal');
    },
  );
  test('rename uses uri and new_name, never metadata sys:name', () async {
    mock((_) => {'code': 0});
    expect(
      await CloudreveRepository.renameEntry(
        fileUri: 'cloudreve://my/old%20name.flac',
        newName: ' new name.flac ',
      ),
      isTrue,
    );
    expect(adapter.requests.single.uri.path, '/api/v4/file/rename');
    expect(adapter.requests.single.data, {
      'uri': 'cloudreve://my/old%20name.flac',
      'new_name': 'new name.flac',
    });
  });
  test(
    'rename reports server errors and rejects invalid names before sending',
    () async {
      mock((_) => {'code': 40001, 'msg': '同名文件已存在'});
      await expectLater(
        CloudreveRepository.renameEntry(fileUri: '/file', newName: 'taken'),
        throwsA(isA<CloudreveApiException>()),
      );
      await expectLater(
        CloudreveRepository.renameEntry(fileUri: '/file', newName: '../bad'),
        throwsA(isA<CloudreveApiException>()),
      );
      expect(adapter.requests.length, 1);
    },
  );
  test(
    'WebDAV decodes current object payload and traverses pagination',
    () async {
      mock(
        (request) => {
          'code': 0,
          'data': {
            'accounts': [
              {
                'id': request.queryParameters['next_page_token'] == null
                    ? 'one'
                    : 'two',
                'name': 'DAV',
                'password': 'test-only',
                'options': 'BA==',
              },
            ],
            'pagination': {
              if (request.queryParameters['next_page_token'] == null)
                'next_token': 'next',
            },
          },
        },
      );
      final accounts = await CloudreveRepository.fetchWebDavAccounts();
      expect(accounts.map((account) => account.id), ['one', 'two']);
      expect(accounts.first.password, 'test-only');
    },
  );
  test(
    'WebDAV legacy list remains compatible and errors are not empty success',
    () async {
      mock(
        (_) => {
          'code': 0,
          'data': [
            {
              'accounts': [
                {'id': 'legacy', 'name': 'Legacy'},
              ],
            },
          ],
        },
      );
      expect(
        (await CloudreveRepository.fetchWebDavAccounts()).single.id,
        'legacy',
      );
      mock((_) => {'code': 403, 'msg': '无权使用 WebDAV'});
      await expectLater(
        CloudreveRepository.fetchWebDavAccounts(),
        throwsA(isA<CloudreveApiException>()),
      );
    },
  );
  test('profile refresh uses current server user instead of stale cached login data', () async {
    mock(
      (_) => {
        'code': 0,
        'data': {
          'user': {
            ...UserData.empty().toJson(),
            'id': 'profile-id',
            'nickname': '新昵称',
            'anonymous': false,
          },
        },
      },
    );
    expect((await CloudreveRepository.fetchCurrentUser()).nickname, '新昵称');
    final state = AppState()
      ..updateSession(
        userData: UserData.empty(),
        storage: Storage(0, 100, 100),
      );
    var changed = 0;
    state.addListener(() => changed++);
    await state.applyNickname(' 新昵称 ');
    expect(state.userData!.nickname, '新昵称');
    expect(changed, 1);
    state.dispose();
  });
  test(
    'web shortcut resolves actual media size and latest renamed source URI',
    () async {
      final target = mediaFile(
        name: 'renamed.flac',
        path: 'cloudreve://AbCd@share/renamed.flac',
      );
      mock(
        (_) => {
          'code': 0,
          'data': {
            'single_file_view': true,
            'files': [target],
            'context_hint': 'share-context',
          },
        },
      );
      final shortcut = MFile.fromJson(
        mediaFile(
          size: 0,
          metadata: {'sys:shared_redirect': 'cloudreve://AbCd@share/old.flac'},
        ),
      );
      final originalPath = shortcut.path;
      await CloudreveRepository.resolveShortcut(shortcut);
      expect(shortcut.size, 144449051);
      expect(shortcut.contentUri, 'cloudreve://AbCd@share/renamed.flac');
      expect(shortcut.contentContextHint, 'share-context');
      expect(
        shortcut.path,
        originalPath,
        reason: 'Rename/delete must still target the local shortcut',
      );
      expect(
        adapter.requests.single.queryParameters['uri'],
        'cloudreve://AbCd@share',
      );
    },
  );
  test(
    'shortcut cannot turn into an arbitrary authenticated external request',
    () async {
      mock((_) => {'code': 0});
      final shortcut = MFile.fromJson(
        mediaFile(
          size: 0,
          metadata: {
            'sys:shared_redirect': 'https://untrusted.example/collect',
          },
        ),
      );
      await expectLater(
        CloudreveRepository.resolveShortcut(shortcut),
        throwsA(isA<CloudreveApiException>()),
      );
      expect(adapter.requests, isEmpty);
    },
  );
  test(
    'share import matches website shortcut metadata and never downloads HTML',
    () async {
      mock((_) => {'code': 0});
      final link = ShareLink.parse(
        '分享链接：https://cloud.example.com/s/AbCd 密码：1234',
        server: Uri.parse('https://cloud.example.com'),
      );
      expect(link.rootUri, 'cloudreve://AbCd:1234@share');
      final content = SharedContent(
        link: link,
        name: 'song.flac',
        folder: false,
        ownerId: 'share-owner',
        files: [MFile.fromJson(mediaFile(path: '${link.rootUri}/song.flac'))],
      );
      await CloudreveRepository.importShare(content, '/收藏');
      expect(adapter.requests.single.data, {
        'uri': 'cloudreve://my/%E6%94%B6%E8%97%8F/song.flac',
        'type': 'file',
        'err_on_conflict': true,
        'metadata': {
          'sys:shared_redirect': 'cloudreve://AbCd:1234@share/song.flac',
          'sys:shared_owner': 'share-owner',
        },
      });
      expect(adapter.requests.single.uri.path, '/api/v4/file/create');
    },
  );
  test('clipboard parser accepts private and web navigation links, refuses other sites', () {
    final site = Uri.parse('https://cloud.example.com');
    expect(
      ShareLink.parse(
        'https://cloud.example.com/s/AbCd/pass',
        server: site,
      ).password,
      'pass',
    );
    expect(
      ShareLink.parse(
        'https://cloud.example.com/home?path=cloudreve%3A%2F%2FAbCd%40share',
        server: site,
      ).id,
      'AbCd',
    );
    expect(
      () => ShareLink.parse('https://evil.example/s/AbCd', server: site),
      throwsFormatException,
    );
    expect(
      () => ShareLink.parse(
        'https://cloud.example.com@evil.example/s/AbCd',
        server: site,
      ),
      throwsFormatException,
    );
    expect(
      () => ShareLink.parse(
        'https://cloud.example.com/not-a-share',
        server: site,
      ),
      throwsFormatException,
    );
  });
  test('file size boundaries and invalid values do not overflow', () {
    expect(MFile.getFileSize(1024), '1.0KB');
    expect(MFile.getFileSize(double.infinity), '未知大小');
    expect(MFile.getFileSize(-1), '未知大小');
    expect(MFile.getFileSize(1e30), endsWith('YB'));
  });
}
