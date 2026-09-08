import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloudreve/utils/http_util.dart';
import 'package:cloudreve/utils/request_cache.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

/// 缓存管理类
class CacheUtil {
  static final _trimJobs = <String, Future<void>>{};

  /// Images share a bounded memory layer and versioned, account-scoped disk
  /// entries. Neither tokens nor signed URLs are written into cache filenames.
  static Future<Uint8List> cachedBytes(
    String bucket,
    String identity,
    Future<Uint8List> Function() loader,
  ) {
    if (!{'image', 'thumb', 'avatar'}.contains(bucket)) {
      throw ArgumentError.value(bucket, 'bucket', 'Unknown image cache');
    }
    final generation = HttpUtil.cacheGeneration;
    final key = sha256
        .convert(
          utf8.encode(
            jsonEncode([
              HttpUtil.dio.options.baseUrl,
              HttpUtil.cacheUserId,
              identity,
            ]),
          ),
        )
        .toString();
    return ClientCache.images.get(
      ('disk-image', generation, bucket, key),
      () async {
        final directory = await getTemporaryDirectory();
        final file = File('${directory.path}/$bucket/v2-$key');
        const ttl = Duration(days: 3);
        try {
          if (await file.exists() &&
              (await file.lastModified()).add(ttl).isAfter(DateTime.now())) {
            final bytes = await file.readAsBytes();
            _scheduleTrim(file.parent, bucket);
            if (bytes.isNotEmpty) return bytes;
          }
        } on FileSystemException {
          // Cache clearing/eviction can race with an image read; reload safely.
        }
        final bytes = await loader();
        if (bytes.isEmpty) throw StateError('图片内容为空');
        if (generation == HttpUtil.cacheGeneration) {
          try {
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes, flush: true);
            _scheduleTrim(file.parent, bucket);
          } on FileSystemException {
            // A full disk or concurrent cache clearing must not break rendering.
          }
        }
        return bytes;
      },
      ttl: const Duration(minutes: 5),
      weightOf: (bytes) => bytes.length,
    );
  }

  static void _scheduleTrim(Directory directory, String bucket) {
    if (_trimJobs.containsKey(directory.path)) return;
    final job =
        Future<void>.delayed(
              const Duration(milliseconds: 200),
              () => trimImages(directory, bucket),
            )
            .catchError((Object _) {
              // Cache maintenance failures must not interrupt image rendering.
            })
            .whenComplete(() {
              _trimJobs.remove(directory.path);
            });
    _trimJobs[directory.path] = job;
  }

  /// Evicts only this client's versioned image files, never arbitrary content.
  static Future<void> trimImages(Directory directory, String bucket) async {
    if (!{'image', 'thumb', 'avatar'}.contains(bucket)) {
      throw ArgumentError.value(bucket, 'bucket', 'Unknown image cache');
    }
    if (!await directory.exists()) return;
    final entries = <({File file, FileStat stat})>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File ||
          !RegExp(r'^v2-[0-9a-f]{64}$')
              .hasMatch(entity.uri.pathSegments.last)) {
        continue;
      }
      try {
        entries.add((file: entity, stat: await entity.stat()));
      } on FileSystemException {
        /* cache cleared while listing */
      }
    }
    entries.sort((a, b) => b.stat.modified.compareTo(a.stat.modified));
    final limit =
        (bucket == 'image'
            ? 64
            : bucket == 'thumb'
            ? 24
            : 8) *
        1024 *
        1024;
    var used = 0;
    var count = 0;
    final cutoff = DateTime.now().subtract(const Duration(days: 3));
    for (final entry in entries) {
      if (entry.stat.modified.isAfter(cutoff) &&
          used + entry.stat.size <= limit &&
          count < 256) {
        used += entry.stat.size;
        count++;
      } else {
        try {
          await entry.file.delete();
        } on FileSystemException {
          /* already removed or currently in use */
        }
      }
    }
  }

  /// 获取缓存大小
  static Future<int> total() async {
    Directory tempDir = await getTemporaryDirectory();
    int total = await _reduce(tempDir);
    return total;
  }

  /// 清除缓存
  static Future<void> clear([String path = '']) async {
    ClientCache.clear();
    Directory tempDir = await getTemporaryDirectory();
    Directory pathDir = Directory(tempDir.path + path);
    await _delete(pathDir);
  }

  /// 递归缓存目录，计算缓存大小
  static Future<int> _reduce(FileSystemEntity file) async {
    /// 如果是一个文件，则直接返回文件大小
    if (file is File) {
      int length = await file.length();
      return length;
    }

    /// 如果是目录，则遍历目录并累计大小
    if (file is Directory) {
      final List<FileSystemEntity> children = file.listSync();

      int total = 0;

      if (children.isNotEmpty) {
        for (final FileSystemEntity child in children) {
          total += await _reduce(child);
        }
      }

      return total;
    }

    return 0;
  }

  /// 递归删除缓存目录和文件
  static Future<void> _delete(FileSystemEntity file) async {
    if (file is Directory) {
      final List<FileSystemEntity> children = file.listSync();
      for (final FileSystemEntity child in children) {
        await _delete(child);
      }
    } else {
      await file.delete();
    }
  }

  static Future<void> deleteCache(String cachePath) async {
    File cache = File(cachePath);
    if (cache.existsSync()) {
      cache.deleteSync();
    }
  }
}
