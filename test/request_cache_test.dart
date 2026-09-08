import 'dart:async';

import 'package:cloudreve/utils/request_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'search snapshots do not expire with time, but respect invalidation',
    () async {
      var now = DateTime.utc(2026);
      final cache = RequestCache(now: () => now);
      var calls = 0;
      Future<int> read({bool refresh = false}) => cache.get(
        'search',
        () async => ++calls,
        ttl: null,
        forceRefresh: refresh,
      );
      expect(await read(), 1);
      now = now.add(const Duration(days: 365));
      expect(await read(), 1);
      expect(await read(refresh: true), 2);
      cache.invalidateWhere((key) => key == 'search');
      expect(await read(), 3);
    },
  );

  test('non-expiring snapshots still have bounded LRU weight and size', () {
    final cache = RequestCache(maxEntries: 2, maxWeight: 3);
    cache.put('a', 1, ttl: null);
    cache.put('b', 1, ttl: null);
    cache.peek<int>('a');
    cache.put('c', 2, ttl: null, weightOf: (value) => value);
    expect(cache.peek<int>('b'), isNull);
    expect(cache.length, 2);
    expect(cache.weight, 3);
  });

  test('20 concurrent readers and subsequent reads use one loader', () async {
    final cache = RequestCache();
    final pending = Completer<int>();
    var calls = 0;
    Future<int> load() {
      calls++;
      return pending.future;
    }

    final futures = List.generate(
      20,
      (_) => cache.get('files', load, ttl: const Duration(seconds: 30)),
    );
    expect(calls, 1);
    pending.complete(7);
    expect(await Future.wait(futures), everyElement(7));
    expect(await cache.get('files', load, ttl: const Duration(seconds: 30)), 7);
    expect(calls, 1);
  });

  test('TTL expiry really reloads, including exact expiry instant', () async {
    var now = DateTime.utc(2026);
    final cache = RequestCache(now: () => now);
    var calls = 0;
    Future<int> read() =>
        cache.get('key', () async => ++calls, ttl: const Duration(seconds: 30));
    expect(await read(), 1);
    now = now.add(const Duration(seconds: 29));
    expect(await read(), 1);
    now = now.add(const Duration(seconds: 1));
    expect(cache.peek<int>('key'), isNull);
    expect(await read(), 2);
  });

  test(
    'failed or synchronously throwing loaders do not poison cache',
    () async {
      final cache = RequestCache();
      await expectLater(
        cache.get<int>(
          'key',
          () => throw StateError('offline'),
          ttl: const Duration(minutes: 1),
        ),
        throwsStateError,
      );
      expect(cache.length, 0);
      expect(
        await cache.get('key', () async => 2, ttl: const Duration(minutes: 1)),
        2,
      );
    },
  );

  test(
    'LRU obeys both item and weight caps, skipping oversized items',
    () async {
      final cache = RequestCache(maxEntries: 2, maxWeight: 4);
      Future<int> add(String key, int weight) => cache.get(
        key,
        () async => weight,
        ttl: const Duration(minutes: 1),
        weightOf: (value) => value,
      );
      await add('a', 2);
      await add('b', 2);
      expect(cache.peek<int>('a'), 2);
      await add('c', 2);
      expect(cache.peek<int>('b'), isNull);
      expect(cache.length, 2);
      expect(cache.weight, 4);
      await add('huge', 10);
      expect(cache.peek<int>('huge'), isNull);
      expect(cache.weight, 4);
    },
  );

  test('invalidated old response cannot replace fresh response', () async {
    final cache = RequestCache();
    final old = Completer<int>();
    final request = cache.get(
      'key',
      () => old.future,
      ttl: const Duration(minutes: 1),
    );
    cache.invalidateWhere((key) => key == 'key');
    await cache.get('key', () async => 2, ttl: const Duration(minutes: 1));
    old.complete(1);
    expect(await request, 1);
    expect(cache.peek<int>('key'), 2);
  });

  test(
    'force refresh bypasses cached value but merges concurrent refreshes',
    () async {
      final cache = RequestCache();
      await cache.get('key', () async => 1, ttl: const Duration(minutes: 1));
      final next = Completer<int>();
      var calls = 0;
      final futures = List.generate(
        5,
        (_) => cache.get(
          'key',
          () {
            calls++;
            return next.future;
          },
          ttl: const Duration(minutes: 1),
          forceRefresh: true,
        ),
      );
      expect(calls, 1);
      next.complete(2);
      expect(await Future.wait(futures), everyElement(2));
    },
  );

  test(
    'zero TTL merges only in-flight work and never retains signed URLs',
    () async {
      final cache = RequestCache();
      var calls = 0;
      Future<int> read() =>
          cache.get('url', () async => ++calls, ttl: Duration.zero);
      expect(await Future.wait([read(), read()]), [1, 1]);
      expect(cache.length, 0);
      expect(await read(), 2);
    },
  );

  test('clearing during an in-flight response keeps cache empty', () async {
    final cache = RequestCache();
    final pending = Completer<int>();
    final result = cache.get(
      'key',
      () => pending.future,
      ttl: const Duration(minutes: 1),
    );
    cache.clear();
    pending.complete(3);
    await result;
    expect(cache.peek<int>('key'), isNull);
  });
}
