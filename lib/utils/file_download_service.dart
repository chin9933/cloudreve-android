import 'dart:convert';
import 'dart:io';

import 'package:cloudreve/entity/m_file.dart';
import 'package:cloudreve/state/download_history_controller.dart';
import 'package:cloudreve/utils/cloudreve_repository.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

/// Transfers outlive the file page, but never the authenticated session.
class FileDownloadService {
  FileDownloadService({
    DownloadHistoryController? history,
    Dio Function()? clientFactory,
    Future<Directory> Function()? documentsDirectory,
    Future<Directory> Function()? temporaryDirectory,
  }) : history = history ?? DownloadHistoryController.instance,
       _clientFactory =
           clientFactory ??
           (() => Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 15),
               receiveTimeout: const Duration(seconds: 60),
             ),
           )),
       _documentsDirectory =
           documentsDirectory ?? getApplicationDocumentsDirectory,
       _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;

  static final instance = FileDownloadService();
  final DownloadHistoryController history;
  final Dio Function() _clientFactory;
  final Future<Directory> Function() _documentsDirectory;
  final Future<Directory> Function() _temporaryDirectory;
  final _inFlight = <String, Future<String>>{};

  Future<String> download(
    MFile file, {
    bool preview = false,
    String? contextHint,
    Future<String> Function(MFile file)? resolveUrl,
  }) {
    final key = '${history.revision}|$preview|${file.cacheVersion}';
    return _inFlight.putIfAbsent(key, () {
      final job = _download(file.copy(), preview, contextHint, resolveUrl);
      // Do not return remove(): its value is this same Future, which would
      // propagate a failed download into a second unobserved future.
      job.then<void>(
        (_) {
          _inFlight.remove(key);
        },
        onError: (Object _, StackTrace _) {
          _inFlight.remove(key);
        },
      );
      return job;
    });
  }

  Future<String> _download(
    MFile file,
    bool preview,
    String? contextHint,
    Future<String> Function(MFile file)? resolveUrl,
  ) async {
    final task = await history.begin(
      name: file.name,
      kind: preview ? TransferKind.preview : TransferKind.download,
      total: file.size,
    );
    final scope = history.scope!;
    final token = CancelToken();
    task.onCancel(() => token.cancel('cancelled'));
    Dio? client;
    File? partial;
    void ensureActive() {
      if (!task.active || token.isCancelled) {
        throw DioException(
          requestOptions: RequestOptions(),
          type: DioExceptionType.cancel,
        );
      }
    }

    try {
      ensureActive();
      if (resolveUrl == null) {
        await CloudreveRepository.resolveShortcut(file);
      }
      ensureActive();
      final base = await (preview
          ? _temporaryDirectory()
          : _documentsDirectory());
      ensureActive();
      final key = sha256.convert(utf8.encode(file.cacheVersion)).toString();
      final directory = Directory(
        '${base.path}/${preview ? 'file-previews' : 'downloads'}/$scope/$key',
      );
      await directory.create(recursive: true);
      var safeName = file.name.replaceAll(
        RegExp(r'[\\/:*?"<>|\x00-\x1f]'),
        '_',
      );
      if (safeName.isEmpty || safeName == '.' || safeName == '..') {
        safeName = 'file';
      }
      // Keep the extension for external viewers without allowing extreme paths.
      if (safeName.length > 120) {
        final dot = safeName.lastIndexOf('.');
        final suffix = dot > 0 && safeName.length - dot < 16
            ? safeName.substring(dot)
            : '';
        safeName = '${safeName.substring(0, 100)}$suffix';
      }
      final target = File('${directory.path}/$safeName');
      if (await target.exists() &&
          file.size > 0 &&
          await target.length() == file.size) {
        ensureActive();
        task.complete(localPath: target.path, bytes: await target.length());
        return target.path;
      }
      final url = resolveUrl != null
          ? await resolveUrl(file)
          : await CloudreveRepository.createDownloadUrl(
              file.contentUri,
              contextHint: file.contentContextHint ?? contextHint,
            );
      ensureActive();
      if (url == null || url.isEmpty) throw StateError('获取下载链接失败');
      partial = File('${target.path}.${task.id}.part');
      client = _clientFactory();
      final response = await client.download(
        url,
        partial.path,
        cancelToken: token,
        onReceiveProgress: task.progress,
      );
      ensureActive();
      final size = await partial.length();
      final declared = int.tryParse(
        response.headers.value(Headers.contentLengthHeader) ?? '',
      );
      if (response.statusCode != 200 ||
          (file.size > 0 && size != file.size) ||
          (declared != null &&
              !response.headers.map.containsKey('content-encoding') &&
              size != declared)) {
        throw StateError('文件下载不完整');
      }
      ensureActive();
      await partial.rename(target.path);
      ensureActive();
      task.complete(localPath: target.path, bytes: size);
      return target.path;
    } catch (error) {
      if (error is DioException && error.type == DioExceptionType.cancel) {
        task.cancel();
      } else {
        task.fail();
      }
      rethrow;
    } finally {
      client?.close();
      try {
        if (partial != null && await partial.exists()) await partial.delete();
      } on FileSystemException {
        // Only this task's partial file is eligible for cleanup.
      }
    }
  }

  Future<bool> isAvailable(DownloadRecord record) async {
    if (record.status != TransferStatus.completed) return false;
    final file = await _ownedLocalFile(record);
    if (file == null) return false;
    try {
      return await file.length() == record.received;
    } on FileSystemException {
      return false;
    }
  }

  Future<bool> deleteLocalFile(DownloadRecord record) async {
    final file = await _ownedLocalFile(record);
    if (file == null) return false;
    try {
      await file.delete();
      return true;
    } on FileSystemException {
      return false;
    }
  }

  Future<File?> _ownedLocalFile(DownloadRecord record) async {
    final scope = history.scope;
    final localPath = record.localPath;
    if (scope == null || localPath == null) return null;
    final base = await (record.kind == TransferKind.download
        ? _documentsDirectory()
        : _temporaryDirectory());
    final directory = Directory(
      '${base.path}/${record.kind == TransferKind.download ? 'downloads' : 'file-previews'}/$scope',
    );
    final file = File(localPath);
    try {
      if (!await directory.exists() || !await file.exists()) return null;
      final root = await directory.resolveSymbolicLinks();
      final resolved = await file.resolveSymbolicLinks();
      final separator = Platform.pathSeparator;
      final normalizedRoot = root.endsWith(separator)
          ? root
          : '$root$separator';
      if (!resolved.startsWith(normalizedRoot) || history.scope != scope) {
        return null;
      }
      return file;
    } on FileSystemException {
      return null;
    }
  }
}
