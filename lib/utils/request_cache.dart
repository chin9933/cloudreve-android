/// Bounded, session-only LRU cache. Concurrent readers share one request.
/// Errors never stick; invalidated in-flight work cannot refill the cache.
class RequestCache {
  RequestCache({
    this.maxEntries = 96,
    this.maxWeight = 12000,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final int maxEntries;
  final int maxWeight;
  final DateTime Function() _now;
  final _entries = <Object, _CacheEntry>{};
  final _pending = <Object, _PendingRequest>{};
  int _weight = 0;

  int get length => _entries.length;
  int get weight => _weight;
  bool isPending(Object key) => _pending.containsKey(key);

  _CacheEntry? _fresh(Object key) {
    final entry = _entries.remove(key);
    if (entry == null) return null;
    if (entry.expires != null && !entry.expires!.isAfter(_now())) {
      _weight -= entry.weight;
      return null;
    }
    _entries[key] = entry;
    return entry;
  }

  T? peek<T>(Object key) => _fresh(key)?.value as T?;

  /// A null TTL retains a snapshot until invalidation or bounded LRU eviction.
  void put<T>(
    Object key,
    T value, {
    required Duration? ttl,
    int Function(T)? weightOf,
  }) {
    _pending.remove(key);
    _store(key, value, ttl: ttl, weightOf: weightOf);
  }

  void _store<T>(
    Object key,
    T value, {
    required Duration? ttl,
    int Function(T)? weightOf,
  }) {
    final old = _entries.remove(key);
    if (old != null) _weight -= old.weight;
    if (ttl != null && ttl <= Duration.zero) return;
    final size = (weightOf?.call(value) ?? 1).clamp(1, 1 << 30);
    if (size > maxWeight) return;
    _entries[key] = _CacheEntry(
      value,
      ttl == null ? null : _now().add(ttl),
      size,
    );
    _weight += size;
    while (_entries.length > maxEntries || _weight > maxWeight) {
      _weight -= _entries.remove(_entries.keys.first)!.weight;
    }
  }

  Future<T> get<T>(
    Object key,
    Future<T> Function() loader, {
    required Duration? ttl,
    bool forceRefresh = false,
    int Function(T)? weightOf,
  }) {
    if (!forceRefresh) {
      final cached = _fresh(key);
      if (cached != null) return Future<T>.value(cached.value as T);
    }
    final pending = _pending[key];
    if (pending != null) return pending.future.then((value) => value as T);
    final request = _PendingRequest();
    _pending[key] = request;
    request.future = Future<T>.sync(loader)
        .then<T>((value) {
          if (identical(_pending[key], request)) {
            _store(key, value, ttl: ttl, weightOf: weightOf);
          }
          return value;
        })
        .whenComplete(() {
          if (identical(_pending[key], request)) _pending.remove(key);
        });
    return request.future.then((value) => value as T);
  }

  void invalidateWhere(bool Function(Object) matches) {
    for (final key in _entries.keys.where(matches).toList()) {
      _weight -= _entries.remove(key)!.weight;
    }
    _pending.removeWhere((key, _) => matches(key));
  }

  void clear() {
    _entries.clear();
    _pending.clear();
    _weight = 0;
  }
}

class _CacheEntry {
  _CacheEntry(this.value, this.expires, this.weight);
  final Object? value;
  final DateTime? expires;
  final int weight;
}

class _PendingRequest {
  late Future<Object?> future;
}

abstract final class ClientCache {
  // Metadata is bounded by both directory count and total retained file count.
  static final metadata = RequestCache();
  // Search snapshots are isolated from short-lived metadata eviction.
  static final search = RequestCache(maxEntries: 64, maxWeight: 6400);
  static final images = RequestCache(
    maxEntries: 64,
    maxWeight: 12 * 1024 * 1024,
  );

  static void clear() {
    metadata.clear();
    search.clear();
    images.clear();
  }
}
