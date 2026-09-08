import 'dart:convert';

import 'package:cloudreve_api_client/cloudreve_api_client.dart'
    as cloudreve_api;

class MFile {
  MFile(
    this.date,
    this.id,
    this.name,
    this.path,
    this.pic,
    this.size,
    this.type,
  );
  late String date;
  late String id;
  late String name;
  late String path;
  late String pic;
  late int size;
  late String type;
  String? resolvedUri;
  String? contentContextHint;
  String? contentError;
  String? contentVersion;

  Map<String, dynamic> get metadata {
    try {
      final decoded = jsonDecode(pic);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
    } catch (_) {
      return {};
    }
  }

  String? get shortcutUri {
    final value = metadata['sys:shared_redirect']?.toString();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  String get contentUri => resolvedUri ?? shortcutUri ?? path;
  String get cacheVersion => '$contentUri|${contentVersion ?? date}|$size';
  String get displaySize =>
      contentError != null ? '分享不可用' : getFileSize(size.toDouble());

  MFile copy() => MFile(date, id, name, path, pic, size, type)
    ..resolvedUri = resolvedUri
    ..contentContextHint = contentContextHint
    ..contentVersion = contentVersion
    ..contentError = contentError;

  MFile.fromJson(Map<String, dynamic> map) {
    date = map['updated_at']?.toString() ?? map['created_at']?.toString() ?? '';
    id = (map['id'] ?? '').toString();
    name = map['name']?.toString() ?? '';
    path = map['path']?.toString() ?? '';
    pic = map['metadata'] is Map ? jsonEncode(map['metadata']) : '';
    size = _toInt(map['size']);
    type = map['type'] == 1 ? 'dir' : 'file';
  }

  factory MFile.fromFileResponse(cloudreve_api.FileResponse file) {
    final metadata = file.metadata?.asMap() ?? const <String, String>{};
    final updatedAt = file.updatedAt ?? file.createdAt;
    return MFile(
      updatedAt?.toIso8601String() ?? '',
      file.id ?? '',
      file.name ?? '',
      file.path ?? '',
      metadata.isEmpty ? '' : jsonEncode(metadata),
      file.size ?? 0,
      file.type == cloudreve_api.FileResponseTypeEnum.number1 ? 'dir' : 'file',
    );
  }

  static int _toInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    if (value is double) {
      return value.toInt();
    }
    return 0;
  }

  String getFormatDate() {
    if (date.length >= 19) {
      return '${date.substring(0, 10)} ${date.substring(11, 19)}';
    }
    return date;
  }

  static List<MFile> getFileList(
    List<dynamic> list, [
    int Function(MFile, MFile)? compare,
  ]) {
    var fileList = <MFile>[];
    for (var item in list) {
      if (item is Map<String, dynamic>) {
        var file = MFile.fromJson(item);
        fileList.add(file);
      }
    }
    if (compare != null) {
      fileList.sort(compare);
    }
    return fileList;
  }

  static final sizeList = <String>[
    'B',
    'KB',
    'MB',
    'GB',
    'TB',
    'PB',
    'EB',
    'ZB',
    'YB',
  ];

  static String getFileSize(double bytes, [int after = 1]) {
    if (!bytes.isFinite || bytes < 0) return '未知大小';
    int index = 0;
    while (bytes >= 1024 && index < sizeList.length - 1) {
      bytes /= 1024;
      index++;
    }
    return '${bytes.toStringAsFixed(after)}${sizeList[index]}';
  }
}

String getFormatDate(String date) {
  if (date.length >= 19) {
    return '${date.substring(0, 10)} ${date.substring(11, 19)}';
  }
  return date;
}
