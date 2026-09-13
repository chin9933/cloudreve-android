import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum TransferKind { download, preview, image, audio, video, document }

enum TransferStatus {
  loading,
  completed,
  opened,
  failed,
  cancelled,
  interrupted,
}

@immutable
class DownloadRecord {
  const DownloadRecord({
    required this.id,
    required this.name,
    required this.kind,
    required this.createdAt,
    required this.status,
    this.received = 0,
    this.total = 0,
    this.localPath,
  });

  final String id;
  final String name;
  final TransferKind kind;
  final DateTime createdAt;
  final TransferStatus status;
  final int received;
  final int total;
  final String? localPath;
  bool get active => status == TransferStatus.loading;
  double? get progress => total > 0 ? (received / total).clamp(0.0, 1.0) : null;

  DownloadRecord copyWith({
    TransferStatus? status,
    int? received,
    int? total,
    String? localPath,
  }) => DownloadRecord(
    id: id,
    name: name,
    kind: kind,
    createdAt: createdAt,
    status: status ?? this.status,
    received: received ?? this.received,
    total: total ?? this.total,
    localPath: localPath ?? this.localPath,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'createdAt': createdAt.toIso8601String(),
    'status': status.name,
    'received': received,
    'total': total,
    if (localPath != null) 'localPath': localPath,
  };

  factory DownloadRecord.fromJson(Map<String, dynamic> json) => DownloadRecord(
    id: json['id'] as String,
    name: json['name'] as String,
    kind: TransferKind.values.byName(json['kind'] as String),
    createdAt: DateTime.parse(json['createdAt'] as String),
    status: TransferStatus.values.byName(json['status'] as String),
    received: ((json['received'] as num?)?.toInt() ?? 0).clamp(0, 1 << 62),
    total: ((json['total'] as num?)?.toInt() ?? 0).clamp(0, 1 << 62),
    localPath: json['localPath'] as String?,
  );
}

abstract interface class DownloadHistoryStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class PreferencesDownloadHistoryStore implements DownloadHistoryStore {
  @override
  Future<String?> read(String key) async =>
      (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<void> write(String key, String value) async {
    if (!await (await SharedPreferences.getInstance()).setString(key, value)) {
      throw StateError('无法保存下载记录');
    }
  }
}

/// Bounded, account-scoped local history. Never stores tokens or signed URLs.
class DownloadHistoryController extends ChangeNotifier {
  DownloadHistoryController({DownloadHistoryStore? store})
    : _store = store ?? PreferencesDownloadHistoryStore();

  static final instance = DownloadHistoryController();
  static const maxRecords = 200;
  final DownloadHistoryStore _store;
  final _cancelActions = <String, VoidCallback>{};
  List<DownloadRecord> _records = [];
  String? _scope;
  int _revision = 0;
  int _sequence = 0;
  Future<void> _ready = Future.value();
  Future<void> _writes = Future.value();
  Timer? _progressTimer;
  bool _disposed = false;
  bool storageFailed = false;

  String? get scope => _scope;
  int get revision => _revision;
  List<DownloadRecord> get records => List.unmodifiable(_records);
  int get activeCount => _records.where((record) => record.active).length;
  Future<void> get settled => _writes;

  Future<void> setAccount(String? server, String? userId) {
    final next =
        server == null || server.isEmpty || userId == null || userId.isEmpty
        ? null
        : sha256.convert(utf8.encode(jsonEncode([server, userId]))).toString();
    if (next == _scope) return _ready;
    for (final cancel in _cancelActions.values.toList()) {
      cancel();
    }
    _cancelActions.clear();
    if (_records.any((record) => record.active)) {
      _records = _records
          .map(
            (record) => record.active
                ? record.copyWith(status: TransferStatus.interrupted)
                : record,
          )
          .toList();
      _persist();
    }
    _revision++;
    _scope = next;
    _records = [];
    storageFailed = false;
    _progressTimer?.cancel();
    _progressTimer = null;
    _notify();
    _ready = _restore(next, _revision);
    return _ready;
  }

  Future<void> _restore(String? scope, int revision) async {
    if (scope == null) return;
    // Finish earlier writes before restoring the same account after a switch.
    await _writes;
    try {
      final value = await _store.read('download-history-v1-$scope');
      if (revision != _revision || _disposed) return;
      final rows = value == null ? <dynamic>[] : jsonDecode(value) as List;
      final records = <DownloadRecord>[];
      for (final row in rows.take(maxRecords)) {
        try {
          var record = DownloadRecord.fromJson(
            Map<String, dynamic>.from(row as Map),
          );
          if (record.active) {
            record = record.copyWith(status: TransferStatus.interrupted);
          }
          records.add(record);
        } catch (_) {
          // One damaged entry must not make the whole history unreadable.
        }
      }
      _records = records;
    } catch (_) {
      if (revision == _revision) storageFailed = true;
    }
    if (revision == _revision) _notify();
  }

  Future<DownloadHandle> begin({
    required String name,
    required TransferKind kind,
    int total = 0,
  }) async {
    final revision = _revision;
    await _ready;
    if (_disposed || _scope == null || revision != _revision) {
      throw StateError('登录状态已变更');
    }
    if (activeCount >= maxRecords) throw StateError('进行中的任务过多');
    while (_records.length >= maxRecords) {
      _records.removeAt(_records.lastIndexWhere((record) => !record.active));
    }
    final now = DateTime.now();
    final id = '${now.microsecondsSinceEpoch}-${_sequence++}';
    _records.insert(
      0,
      DownloadRecord(
        id: id,
        name: name,
        kind: kind,
        createdAt: now,
        status: TransferStatus.loading,
        total: total > 0 ? total : 0,
      ),
    );
    _persist();
    _notify();
    return DownloadHandle._(this, id, revision);
  }

  bool canCancel(String id) => _cancelActions.containsKey(id);

  void cancel(String id) {
    _cancelActions.remove(id)?.call();
    _finish(id, _revision, TransferStatus.cancelled);
  }

  void clearFinished() {
    _records.removeWhere((record) => !record.active);
    _persist();
    _notify();
  }

  void removeRecords(Iterable<String> recordIds) {
    final ids = recordIds.toSet();
    if (ids.isEmpty || !_records.any((record) => ids.contains(record.id))) {
      return;
    }
    for (final id in ids) {
      _cancelActions.remove(id)?.call();
    }
    _records.removeWhere((record) => ids.contains(record.id));
    _persist();
    _notify();
  }

  bool _active(String id, int revision) =>
      !_disposed &&
      revision == _revision &&
      _records.any((record) => record.id == id && record.active);

  void _progress(String id, int revision, int received, int total) {
    if (!_active(id, revision)) return;
    final index = _records.indexWhere((record) => record.id == id);
    _records[index] = _records[index].copyWith(
      received: received < 0 ? 0 : received,
      total: total > 0 ? total : _records[index].total,
    );
    // Do not rebuild widgets or write preferences for every network chunk.
    _progressTimer ??= Timer(const Duration(milliseconds: 200), () {
      _progressTimer = null;
      _notify();
    });
  }

  void _finish(
    String id,
    int revision,
    TransferStatus status, {
    String? localPath,
    int? bytes,
  }) {
    if (!_active(id, revision)) return;
    final index = _records.indexWhere((record) => record.id == id);
    _records[index] = _records[index].copyWith(
      status: status,
      localPath: localPath,
      received: bytes,
      total: bytes,
    );
    _cancelActions.remove(id);
    _persist();
    _notify();
  }

  void _persist() {
    final scope = _scope;
    if (scope == null) return;
    final value = jsonEncode(
      _records.map((record) => record.toJson()).toList(),
    );
    _writes = _writes
        .then((_) => _store.write('download-history-v1-$scope', value))
        .catchError((Object _) {
          if (scope == _scope && !_disposed) {
            storageFailed = true;
            _notify();
          }
        });
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _progressTimer?.cancel();
    for (final cancel in _cancelActions.values.toList()) {
      cancel();
    }
    _cancelActions.clear();
    super.dispose();
  }
}

class DownloadHandle {
  DownloadHandle._(this._owner, this.id, this.revision);
  final DownloadHistoryController _owner;
  final String id;
  final int revision;
  bool get active => _owner._active(id, revision);
  void onCancel(VoidCallback action) {
    if (!active) {
      action();
      return;
    }
    _owner._cancelActions[id] = action;
    _owner._notify();
  }

  void progress(int received, int total) =>
      _owner._progress(id, revision, received, total);
  void complete({String? localPath, int? bytes}) => _owner._finish(
    id,
    revision,
    TransferStatus.completed,
    localPath: localPath,
    bytes: bytes,
  );
  void opened() => _owner._finish(id, revision, TransferStatus.opened);
  void fail() => _owner._finish(id, revision, TransferStatus.failed);
  void cancel() {
    if (revision == _owner.revision) _owner.cancel(id);
  }
}
