import 'dart:convert';

import 'package:cloudreve/state/download_history_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/download_history_test_store.dart';

void main() {
  late MemoryDownloadHistoryStore store;
  late DownloadHistoryController history;
  setUp(() async {
    store = MemoryDownloadHistoryStore();
    history = DownloadHistoryController(store: store);
    await history.setAccount('https://cloud.example.com/api/v4/', 'user-a');
  });
  tearDown(() async {
    await history.settled;
    history.dispose();
  });

  test(
    'persists completed records without signed URLs or session tokens',
    () async {
      final task = await history.begin(
        name: 'report.pdf',
        kind: TransferKind.download,
        total: 5,
      );
      task.progress(3, 5);
      expect(history.records.single.progress, .6);
      task.complete(localPath: '/local/downloads/report.pdf', bytes: 5);
      await history.settled;
      final restored = DownloadHistoryController(store: store);
      await restored.setAccount('https://cloud.example.com/api/v4/', 'user-a');
      expect(restored.records.single.status, TransferStatus.completed);
      expect(restored.records.single.received, 5);
      final json = jsonDecode(store.values.values.single) as List;
      expect((json.single as Map).keys.toSet(), {
        'id',
        'name',
        'kind',
        'createdAt',
        'status',
        'received',
        'total',
        'localPath',
      });
      restored.dispose();
    },
  );

  test('unfinished work is interrupted after an application restart', () async {
    await history.begin(name: 'video.mp4', kind: TransferKind.download);
    await history.settled;
    final restored = DownloadHistoryController(store: store);
    await restored.setAccount('https://cloud.example.com/api/v4/', 'user-a');
    expect(restored.records.single.status, TransferStatus.interrupted);
    expect(restored.activeCount, 0);
    restored.dispose();
  });

  test(
    'switching accounts cancels transport and rejects stale callbacks',
    () async {
      var cancelled = false;
      final task = await history.begin(
        name: 'private.txt',
        kind: TransferKind.download,
      );
      task.onCancel(() => cancelled = true);
      await history.setAccount('https://cloud.example.com/api/v4/', 'user-b');
      expect(cancelled, isTrue);
      expect(history.records, isEmpty);
      task.complete(localPath: '/old/file', bytes: 12);
      expect(history.records, isEmpty);
      await history.setAccount('https://cloud.example.com/api/v4/', 'user-a');
      expect(history.records.single.status, TransferStatus.interrupted);
      await history.setAccount('https://another.example.com/api/v4/', 'user-a');
      expect(history.records, isEmpty);
      await history.setAccount(null, null);
      await expectLater(
        history.begin(name: 'no session', kind: TransferKind.image),
        throwsStateError,
      );
    },
  );

  test(
    'bounded history retains active work and removes oldest finished work',
    () async {
      final pending = await history.begin(
        name: 'pending',
        kind: TransferKind.download,
      );
      for (
        var index = 0;
        index < DownloadHistoryController.maxRecords;
        index++
      ) {
        (await history.begin(
          name: 'file-$index',
          kind: TransferKind.image,
        )).complete(bytes: 4);
      }
      expect(history.records, hasLength(DownloadHistoryController.maxRecords));
      expect(history.records.any((record) => record.id == pending.id), isTrue);
      expect(history.records.any((record) => record.name == 'file-0'), isFalse);
      history.clearFinished();
      expect(history.records.single.id, pending.id);
      pending.cancel();
      history.clearFinished();
      expect(history.records, isEmpty);
    },
  );

  test(
    'unknown totals are indeterminate and cancellation is terminal',
    () async {
      final task = await history.begin(
        name: 'unknown',
        kind: TransferKind.preview,
      );
      task.progress(20, -1);
      expect(history.records.single.progress, isNull);
      task.cancel();
      task.complete(bytes: 100);
      expect(history.records.single.status, TransferStatus.cancelled);
    },
  );

  test('persistence failures do not fail successful downloads', () async {
    store.failWrites = true;
    final task = await history.begin(
      name: 'local',
      kind: TransferKind.download,
    );
    task.complete(bytes: 4);
    await history.settled;
    expect(history.storageFailed, isTrue);
    expect(history.records.single.status, TransferStatus.completed);
  });

  test('removing selected records cancels active work and persists', () async {
    var cancelled = false;
    final active = await history.begin(
      name: 'active.bin',
      kind: TransferKind.download,
    );
    active.onCancel(() => cancelled = true);
    final removed = await history.begin(
      name: 'remove.pdf',
      kind: TransferKind.download,
    );
    removed.complete(bytes: 4);
    final retained = await history.begin(
      name: 'retain.txt',
      kind: TransferKind.download,
    );
    retained.complete(bytes: 2);

    history.removeRecords([active.id, removed.id]);
    expect(cancelled, isTrue);
    expect(history.records.single.id, retained.id);
    await history.settled;

    final restored = DownloadHistoryController(store: store);
    await restored.setAccount('https://cloud.example.com/api/v4/', 'user-a');
    expect(restored.records.single.id, retained.id);
    restored.dispose();
  });

  test('corrupt individual entries do not hide valid history', () async {
    (await history.begin(
      name: 'valid',
      kind: TransferKind.image,
    )).complete(bytes: 1);
    await history.settled;
    final key = store.values.keys.single;
    final rows = jsonDecode(store.values[key]!) as List;
    store.values[key] = jsonEncode([
      {'invalid': true},
      ...rows,
    ]);
    final restored = DownloadHistoryController(store: store);
    await restored.setAccount('https://cloud.example.com/api/v4/', 'user-a');
    expect(restored.records.single.name, 'valid');
    restored.dispose();
  });
}
