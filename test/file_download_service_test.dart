import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloudreve/entity/m_file.dart';
import 'package:cloudreve/state/download_history_controller.dart';
import 'package:cloudreve/utils/file_download_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/download_history_test_store.dart';

class _Adapter implements HttpClientAdapter {
  int requests = 0;
  int status = 200;
  final bytes = <int>[1, 2, 3, 4];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests++;
    return ResponseBody.fromBytes(
      bytes,
      status,
      headers: {
        Headers.contentLengthHeader: ['${bytes.length}'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Directory root;
  late DownloadHistoryController history;
  late FileDownloadService service;
  late _Adapter adapter;
  var resolutions = 0;
  MFile file(String path, {String name = 'example.bin', int size = 4}) =>
      MFile('2026-09-09', path, name, path, '', size, 'file');
  Future<String> resolve(MFile _) async {
    resolutions++;
    return 'https://media.example.com/file?signature=not-persisted';
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('cloudreve-history-test-');
    history = DownloadHistoryController(store: MemoryDownloadHistoryStore());
    await history.setAccount('https://cloud.example.com/api/v4/', 'a');
    adapter = _Adapter();
    resolutions = 0;
    service = FileDownloadService(
      history: history,
      clientFactory: () => Dio()..httpClientAdapter = adapter,
      documentsDirectory: () async => Directory('${root.path}/documents'),
      temporaryDirectory: () async => Directory('${root.path}/cache'),
    );
  });
  tearDown(() async {
    await history.settled;
    history.dispose();
    // This is only the unique temporary directory created by this test.
    expect(root.path, startsWith(Directory.systemTemp.path));
    expect(
      root.uri.pathSegments.where(
        (part) => part.startsWith('cloudreve-history-test-'),
      ),
      hasLength(1),
    );
    await root.delete(recursive: true);
  });

  test(
    'deduplicates concurrent requests and reuses a complete local download',
    () async {
      final first = service.download(file('/one'), resolveUrl: resolve);
      final second = service.download(file('/one'), resolveUrl: resolve);
      expect(identical(first, second), isTrue);
      final saved = await first;
      expect(await second, saved);
      expect(adapter.requests, 1);
      expect(history.records, hasLength(1));
      expect(history.records.single.status, TransferStatus.completed);
      expect(await File(saved).readAsBytes(), adapter.bytes);
      expect(await service.isAvailable(history.records.single), isTrue);
      expect(await service.download(file('/one'), resolveUrl: resolve), saved);
      expect(adapter.requests, 1);
      expect(
        resolutions,
        1,
        reason: 'A cache hit must not request another signed URL',
      );
    },
  );

  test('same names in different folders never reuse each other', () async {
    final a = await service.download(file('/a/same.bin'), resolveUrl: resolve);
    final b = await service.download(file('/b/same.bin'), resolveUrl: resolve);
    expect(a, isNot(b));
    expect(adapter.requests, 2);
  });

  test(
    'a truncated object fails and leaves no partial or completed file',
    () async {
      await expectLater(
        service.download(file('/broken', size: 9), resolveUrl: resolve),
        throwsStateError,
      );
      expect(history.records.single.status, TransferStatus.failed);
      expect(history.records.single.localPath, isNull);
      expect(
        await root
            .list(recursive: true)
            .where((entry) => entry is File)
            .toList(),
        isEmpty,
      );
    },
  );

  test(
    'HTTP failures are recorded and never become successful files',
    () async {
      adapter.status = 403;
      await expectLater(
        service.download(file('/denied'), resolveUrl: resolve),
        throwsA(isA<DioException>()),
      );
      expect(history.records.single.status, TransferStatus.failed);
      expect(
        await root
            .list(recursive: true)
            .where((entry) => entry is File)
            .toList(),
        isEmpty,
      );
    },
  );

  test(
    'cancellation while resolving a URL prevents any content request',
    () async {
      final resolving = Completer<String>();
      final reachedResolver = Completer<void>();
      final job = service.download(
        file('/cancel'),
        resolveUrl: (_) {
          reachedResolver.complete();
          return resolving.future;
        },
      );
      final assertion = expectLater(
        job,
        throwsA(
          isA<DioException>().having(
            (error) => error.type,
            'type',
            DioExceptionType.cancel,
          ),
        ),
      );
      await reachedResolver.future;
      history.cancel(history.records.single.id);
      resolving.complete('https://media.example.com/cancel');
      await assertion;
      expect(adapter.requests, 0);
      expect(history.records.single.status, TransferStatus.cancelled);
    },
  );

  test('cache clearing does not remove explicit downloads', () async {
    final saved = await service.download(
      file('/document'),
      resolveUrl: resolve,
    );
    final cached = await service.download(
      file('/archive'),
      preview: true,
      resolveUrl: resolve,
    );
    final previewRecord = history.records.first;
    final downloadRecord = history.records.last;
    final cache = Directory('${root.path}/cache');
    expect(cache.absolute.path, startsWith(root.absolute.path));
    await cache.delete(recursive: true);
    expect(await File(saved).exists(), isTrue);
    expect(await File(cached).exists(), isFalse);
    expect(await service.isAvailable(previewRecord), isFalse);
    expect(await service.isAvailable(downloadRecord), isTrue);
    history.clearFinished();
    expect(
      await File(saved).exists(),
      isTrue,
      reason: 'Clearing history does not delete downloads',
    );
  });

  test(
    'a cancelled record never exposes a stale completed-file path',
    () async {
      final saved = await service.download(
        file('/cancelled-after-save'),
        resolveUrl: resolve,
      );
      final completed = history.records.single;
      final cancelled = DownloadRecord(
        id: completed.id,
        name: completed.name,
        kind: completed.kind,
        createdAt: completed.createdAt,
        status: TransferStatus.cancelled,
        received: completed.received,
        total: completed.total,
        localPath: completed.localPath,
      );

      expect(await File(saved).exists(), isTrue);
      expect(await service.isAvailable(cancelled), isFalse);
    },
  );

  test('a different account cannot open the old account local file', () async {
    await service.download(file('/private'), resolveUrl: resolve);
    final record = history.records.single;
    await history.setAccount('https://cloud.example.com/api/v4/', 'b');
    expect(await service.isAvailable(record), isFalse);
    expect(history.records, isEmpty);
  });

  test(
    'local deletion is limited to the current account download root',
    () async {
      final saved = await service.download(file('/owned'), resolveUrl: resolve);
      final record = history.records.single;
      expect(await service.deleteLocalFile(record), isTrue);
      expect(await File(saved).exists(), isFalse);

      final outside = File('${root.path}/outside.bin');
      await outside.writeAsBytes(adapter.bytes);
      final forged = record.copyWith(localPath: outside.path);
      expect(await service.deleteLocalFile(forged), isFalse);
      expect(await outside.exists(), isTrue);
    },
  );
}
