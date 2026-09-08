import 'dart:async';

import 'package:cloudreve/entity/m_file.dart';
import 'package:cloudreve/utils/cloudreve_repository.dart';
import 'package:cloudreve/utils/http_util.dart';
import 'package:cloudreve/utils/request_cache.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cloudreve_protocol_regression_test.dart'
    show ProtocolAdapter, mediaFile;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProtocolAdapter adapter;
  var revision = 1;
  setUp(() {
    revision = 1;
    adapter = ProtocolAdapter(
      (request) => {
        'code': 0,
        'data': {
          'files': [mediaFile(name: 'file-$revision.flac')],
          'context_hint': 'test',
        },
      },
    );
    HttpUtil.dio = Dio(
      BaseOptions(baseUrl: 'https://cloud.example.com/api/v4/'),
    )..httpClientAdapter = adapter;
    HttpUtil.clearAuthToken();
  });
  tearDown(HttpUtil.clearAuthToken);

  test('peeking while root search refreshes cannot replace its pending refresh with old cache', () async {
    await CloudreveRepository.listFiles('/');
    final started = Completer<void>();
    final release = Completer<void>();
    HttpUtil.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          started.complete();
          await release.future;
          handler.next(options);
        },
      ),
    );
    revision = 2;
    final refreshed = CloudreveRepository.search('', forceRefresh: true);
    await started.future;
    expect(CloudreveRepository.peekSearch(''), isNull);
    release.complete();
    expect((await refreshed).files.single.name, 'file-2.flac');
    expect(
      CloudreveRepository.peekSearch('')!.files.single.name,
      'file-2.flac',
    );
    expect(adapter.requests.length, 2);
  });

  test('search survives normal metadata expiry/eviction and passive directory reload', () async {
    await CloudreveRepository.search('song');
    await CloudreveRepository.search('');
    ClientCache.metadata
        .clear(); // Directory TTL/eviction does not evict search.
    revision = 2;
    await CloudreveRepository.listFiles('/');
    final count = adapter.requests.length;
    expect(
      (await CloudreveRepository.search('song')).files.single.name,
      'file-1.flac',
    );
    expect(
      CloudreveRepository.peekSearch('')!.files.single.name,
      'file-1.flac',
    );
    expect(adapter.requests.length, count);
    expect(
      (await CloudreveRepository.search(
        'song',
        forceRefresh: true,
      )).files.single.name,
      'file-2.flac',
    );
    expect(
      (await CloudreveRepository.search('song')).files.single.name,
      'file-2.flac',
    );
    expect(adapter.requests.length, count + 1);
    revision = 3;
    await CloudreveRepository.listFiles('/', forceRefresh: true);
    expect(
      CloudreveRepository.peekSearch('')!.files.single.name,
      'file-3.flac',
    );
    expect(CloudreveRepository.peekSearch('song'), isNull);
    expect(
      (await CloudreveRepository.search('song')).files.single.name,
      'file-3.flac',
    );
  });

  test(
    'search is cleared on logout and does not reuse another account data',
    () async {
      await CloudreveRepository.search('song');
      HttpUtil.clearAuthToken();
      revision = 2;
      expect(CloudreveRepository.peekSearch('song'), isNull);
      expect(
        (await CloudreveRepository.search('song')).files.single.name,
        'file-2.flac',
      );
      expect(adapter.requests.length, 2);
    },
  );

  test('folder cursor pages have distinct cached responses', () async {
    await CloudreveRepository.listFiles('/folder', nextPageToken: 'a');
    await CloudreveRepository.listFiles('/folder', nextPageToken: 'b');
    await CloudreveRepository.listFiles('/folder', nextPageToken: 'b');
    expect(adapter.requests.length, 2);
    expect(adapter.requests.last.queryParameters['next_page_token'], 'b');
  });

  test(
    'home, files, empty search and root aliases share one request',
    () async {
      final result = await Future.wait([
        CloudreveRepository.listFiles('/'),
        CloudreveRepository.listFiles('cloudreve://my/'),
        CloudreveRepository.search('  '),
        for (var i = 0; i < 17; i++) CloudreveRepository.listFiles('/'),
      ]);
      expect(adapter.requests.length, 1);
      expect(result, hasLength(20));
      result.first.files.first.name = 'local mutation';
      result.first.files.clear();
      final again = await CloudreveRepository.listFiles('/');
      expect(again.files.single.name, 'file-1.flac');
      expect(adapter.requests.length, 1);
    },
  );

  test(
    'trimmed searches cache separately from folders and pagination',
    () async {
      await CloudreveRepository.search(' song ');
      await CloudreveRepository.search('song');
      expect(adapter.requests.length, 1);
      await CloudreveRepository.search('another');
      await CloudreveRepository.listFiles('/folder');
      await CloudreveRepository.listFiles('/folder', page: 1);
      await CloudreveRepository.listFiles('/folder', pageSize: 10);
      expect(adapter.requests.length, 5);
    },
  );

  test(
    'manual refresh bypasses fresh cache and replaces its contents',
    () async {
      await CloudreveRepository.listFiles('/');
      revision = 2;
      expect(
        (await CloudreveRepository.listFiles('/')).files.single.name,
        'file-1.flac',
      );
      expect(
        (await CloudreveRepository.listFiles(
          '/',
          forceRefresh: true,
        )).files.single.name,
        'file-2.flac',
      );
      expect(
        CloudreveRepository.peekSearch('')!.files.single.name,
        'file-2.flac',
      );
      expect(adapter.requests.length, 2);
    },
  );

  test('successful rename invalidates directory and search results', () async {
    await CloudreveRepository.listFiles('/');
    await CloudreveRepository.search('file');
    await CloudreveRepository.renameEntry(
      fileUri: '/file-1.flac',
      newName: 'file-2.flac',
    );
    revision = 2;
    expect(CloudreveRepository.peekSearch('file'), isNull);
    expect(
      (await CloudreveRepository.listFiles('/')).files.single.name,
      'file-2.flac',
    );
    await CloudreveRepository.search('file');
    expect(adapter.requests.length, 5);
  });

  test('rejected mutation does not invalidate valid cached listing', () async {
    adapter = ProtocolAdapter(
      (request) => request.method == 'POST'
          ? {'code': 40001, 'msg': 'name conflict'}
          : {
              'code': 0,
              'data': {
                'files': [mediaFile()],
              },
            },
    );
    HttpUtil.dio.httpClientAdapter = adapter;
    await CloudreveRepository.listFiles('/');
    await expectLater(
      CloudreveRepository.renameEntry(fileUri: '/song', newName: 'taken'),
      throwsA(isA<CloudreveApiException>()),
    );
    await CloudreveRepository.listFiles('/');
    expect(adapter.requests.length, 2);
  });

  test(
    'logout, another server, and another HTTP client cannot reuse old data',
    () async {
      await CloudreveRepository.listFiles('/');
      HttpUtil.clearAuthToken();
      revision = 2;
      expect(
        (await CloudreveRepository.listFiles('/')).files.single.name,
        'file-2.flac',
      );
      HttpUtil.dio.options.baseUrl = 'https://another.example/api/v4/';
      await CloudreveRepository.listFiles('/');
      expect(adapter.requests.length, 3);
      HttpUtil.dio = Dio(
        BaseOptions(baseUrl: 'https://cloud.example.com/api/v4/'),
      )..httpClientAdapter = adapter;
      await CloudreveRepository.listFiles('/');
      expect(adapter.requests.length, 4);
    },
  );

  test('shortcuts with same share root are resolved once across listing and playback', () async {
    final target = 'cloudreve://ShareId@share/song.flac';
    adapter = ProtocolAdapter((request) {
      final shared =
          request.queryParameters['uri'] == 'cloudreve://ShareId@share';
      return {
        'code': 0,
        'data': {
          'single_file_view': shared,
          'files': shared
              ? [mediaFile(path: target)]
              : [
                  {
                    ...mediaFile(
                      size: 0,
                      metadata: {'sys:shared_redirect': target},
                    ),
                    'id': 'shortcut-1',
                  },
                  {
                    ...mediaFile(
                      size: 0,
                      metadata: {'sys:shared_redirect': target},
                    ),
                    'id': 'shortcut-2',
                  },
                ],
        },
      };
    });
    HttpUtil.dio.httpClientAdapter = adapter;
    final listing = await CloudreveRepository.listFiles('/');
    expect(listing.files.map((f) => f.size), everyElement(144449051));
    await CloudreveRepository.resolveShortcut(listing.files.first);
    expect(adapter.requests.length, 2);
  });

  test(
    'content cache identity follows source version, not only placeholder name',
    () {
      final file = MFile.fromJson(mediaFile())..contentVersion = 'version-1';
      final key = file.cacheVersion;
      final copy = file.copy()..contentVersion = 'version-2';
      expect(copy.cacheVersion, isNot(key));
    },
  );

  test(
    'manual refresh also revalidates shared target size, not only placeholder',
    () async {
      var size = 100;
      const target = 'cloudreve://Shared@share/song.flac';
      adapter = ProtocolAdapter((request) {
        final shared =
            request.queryParameters['uri'] == 'cloudreve://Shared@share';
        return {
          'code': 0,
          'data': {
            'single_file_view': shared,
            'files': [
              shared
                  ? mediaFile(path: target, size: size)
                  : mediaFile(
                      size: 0,
                      metadata: {'sys:shared_redirect': target},
                    ),
            ],
          },
        };
      });
      HttpUtil.dio.httpClientAdapter = adapter;
      expect((await CloudreveRepository.listFiles('/')).files.single.size, 100);
      size = 200;
      expect(
        (await CloudreveRepository.listFiles(
          '/',
          forceRefresh: true,
        )).files.single.size,
        200,
      );
      expect(adapter.requests.length, 4);
    },
  );
}
