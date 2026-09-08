import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:cloudreve/component/cloudreve_video_player.dart';
import 'package:cloudreve/component/file_visual.dart';
import 'package:cloudreve/component/inline_audio_player.dart';
import 'package:cloudreve/component/rename_file_dialog.dart';
import 'package:cloudreve/component/share_dialog.dart';
import 'package:cloudreve/component/share_result_dialog.dart';
import 'package:cloudreve/entity/m_file.dart';
import 'package:cloudreve/state/audio_player_controller.dart';
import 'package:cloudreve/state/sound_effect_provider.dart';
import 'package:cloudreve/theme/app_theme.dart';
import 'package:cloudreve/utils/cache_util.dart';
import 'package:cloudreve/utils/cloudreve_repository.dart';
import 'package:cloudreve/utils/http_util.dart';
import 'package:dio/dio.dart';
import 'package:enough_convert/gbk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_view/photo_view.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

enum Mode { list, grid }

final imageRex = RegExp(
  r'.*\.(jpg|gif|bmp|png|jpeg|webp)$',
  caseSensitive: false,
);
final pdfRex = RegExp(r'.*\.(pdf)$', caseSensitive: false);
final wordRegex = RegExp(r'.*\.(doc|docx)$', caseSensitive: false);
final zipRegex = RegExp(r'.*\.(zip|rar|7z|tar|gz)$', caseSensitive: false);
final apkRegex = RegExp(r'.*\.(apk)$', caseSensitive: false);
final zipPreviewRegex = RegExp(r'.*\.(zip)$', caseSensitive: false);
final audioPreviewRegex = RegExp(
  r'.*\.(mp3|flac|wav|aac|m4a|ogg|opus)$',
  caseSensitive: false,
);
final browserPreviewRegex = RegExp(
  r'.*\.(pdf|txt|md|json|xml|yaml|yml|csv|log|ini|conf|dart|js|ts|tsx|jsx|css|html|htm|py|java|kt|c|cpp|h|hpp|sh)$',
  caseSensitive: false,
);
final videoRegex = RegExp(
  r'.*\.(avi|mp4|mpg|mpeg|mov|flv|mkv|wmv|webm)$',
  caseSensitive: false,
);

Map<int, CancelToken> downloadCancelTokenMap = {};

Icon getIcon(MFile file) {
  final visual = fileVisualFor(file);
  return Icon(visual.icon, color: visual.foreground);
}

class Home extends StatefulWidget {
  /// 修改path函数
  final void Function(String) changePath;

  /// 文件排序比较函数
  final int Function(MFile, MFile)? compare;

  /// 路径
  final String path;

  /// 访问文件数据
  final Future<FileListing> fileResp;

  /// 刷新函数
  final Future<void> Function(bool) refresh;

  /// 类型
  final Mode mode;

  final MFile? openFile;

  final void Function(MFile? file) setOpenFile;

  const Home({
    super.key,
    required this.changePath,
    required this.path,
    required this.fileResp,
    required this.refresh,
    required this.mode,
    this.compare,
    this.openFile,
    required this.setOpenFile,
  });

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  late final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin;
  late final CloudreveAudioController _audioController;

  /// 默认下载路径
  late String _downPath;
  late final Future<void> _downloadDirectoryReady;
  MFile? _scheduledPreview;
  FileListing? _currentListing;

  @override
  void initState() {
    super.initState();
    _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    _audioController = CloudreveAudioController();
    _downloadDirectoryReady = _initDownPath();
    _downloadDirectoryReady.ignore();
    _scheduleRequestedPreview();
  }

  @override
  void dispose() {
    _audioController.dispose();
    super.dispose();
  }

  Future<void> _initDownPath() async {
    _downPath = (await getTemporaryDirectory()).path;
  }

  @override
  void didUpdateWidget(covariant Home oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleRequestedPreview();
  }

  void _scheduleRequestedPreview() {
    final file = widget.openFile;
    if (file == null || identical(file, _scheduledPreview)) return;
    _scheduledPreview = file;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(widget.openFile, file)) return;
      _scheduledPreview = null;
      _setOpenFile(null);
      _openFileButtonTap(context, file);
    });
  }

  String get _path => widget.path;
  Mode get _mode => widget.mode;
  Future<FileListing> get _fileResp => widget.fileResp;
  void Function(String) get _changePath => widget.changePath;
  Future<void> Function(bool) get _refreshCallback => widget.refresh;
  int Function(MFile, MFile)? get _compare => widget.compare;
  void Function(MFile? file) get _setOpenFile => widget.setOpenFile;

  @override
  Widget build(BuildContext context) {
    final mode = _mode;
    final compare = _compare;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        children: [
          // Keep playback controls reachable while a folder refreshes or a
          // listing request fails. Playback itself is independent of the
          // current directory request.
          InlineAudioPlayer(controller: _audioController),
          const SizedBox(height: 12),
          Expanded(
            child: FutureBuilder<FileListing>(
              future: _fileResp,
              builder: (BuildContext context, AsyncSnapshot<FileListing> snapshot) {
                if (snapshot.hasError) {
                  return _buildStateView(
                    icon: Icons.cloud_off_outlined,
                    title: '无法加载文件',
                    subtitle: '请检查网络连接后重试',
                    actionLabel: '重新加载',
                    onAction: () => _refreshCallback(true),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final listing = snapshot.data!;
                _currentListing = listing;
                final fileList = List<MFile>.from(listing.files);
                if (compare != null) {
                  fileList.sort(compare);
                }

                if (fileList.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: () => _refresh(context),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(
                        bottom: CloudreveTheme.pageBottomInset,
                      ),
                      children: [
                        const SizedBox(height: 84),
                        _buildStateView(
                          icon: Icons.folder_open_rounded,
                          title: '这个文件夹是空的',
                          subtitle: '点击下方加号上传文件或新建文件夹',
                        ),
                      ],
                    ),
                  );
                }

                return Scrollbar(
                  child: RefreshIndicator(
                    onRefresh: () => _refresh(context),
                    child: mode == Mode.list
                        ? ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.only(
                              bottom: CloudreveTheme.pageBottomInset,
                            ),
                            itemCount: fileList.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) =>
                                _buildListItem(context, fileList[index]),
                          )
                        : GridView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.only(
                              bottom: CloudreveTheme.pageBottomInset,
                            ),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  mainAxisSpacing: 12,
                                  crossAxisSpacing: 12,
                                  childAspectRatio: 0.92,
                                ),
                            itemCount: fileList.length,
                            itemBuilder: (context, index) =>
                                _buildGridItem(context, fileList[index], index),
                          ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStateView({
    required IconData icon,
    required String title,
    required String subtitle,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: CloudreveColors.primarySoft,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: CloudreveColors.primary),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 12),
              TextButton(onPressed: onAction, child: Text(actionLabel)),
            ],
          ],
        ),
      ),
    );
  }

  /// 构建网格项
  Widget _buildGridItem(BuildContext context, MFile file, int index) {
    Widget headImage;
    if (!imageRex.hasMatch(file.name)) {
      headImage = Center(child: FileIconBadge(file: file, size: 68));
    } else {
      headImage = FutureBuilder(
        future: _geThumbImage(file),
        builder: (BuildContext context, AsyncSnapshot<Uint8List> snapshot) {
          if (snapshot.hasData) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.memory(
                snapshot.data!,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                errorBuilder:
                    (BuildContext context, Object o, StackTrace? stackTrace) {
                      return Center(child: FileIconBadge(file: file, size: 68));
                    },
              ),
            );
          }
          if (snapshot.hasError) {
            return Center(child: FileIconBadge(file: file, size: 68));
          }
          return const Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
          );
        },
      );
    }

    return myInkWell(
      borderRadius: BorderRadius.circular(20),
      child: Ink(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.55),
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(child: headImage),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: _FileMoreButton(
                      onPressed: () => file.type == 'file'
                          ? _fileLongPress(context, file)
                          : _dirLongPress(context, file),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                file.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                file.type == 'dir' ? file.getFormatDate() : file.displaySize,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
      context: context,
      file: file,
    );
  }

  /// 构建头部
  /// 构建文件列表浏览
  Widget _buildListItem(BuildContext context, MFile file) {
    return myInkWell(
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        padding: const EdgeInsets.fromLTRB(12, 11, 6, 11),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.55),
          ),
        ),
        child: Row(
          children: [
            FileIconBadge(file: file, size: 48),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    file.type == 'dir'
                        ? file.getFormatDate()
                        : '${file.getFormatDate()} · ${file.displaySize}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            _FileMoreButton(
              onPressed: () => file.type == 'file'
                  ? _fileLongPress(context, file)
                  : _dirLongPress(context, file),
            ),
          ],
        ),
      ),
      context: context,
      file: file,
    );
  }

  /// 目录单击事件
  void _dirTap(MFile file) {
    if (file.shortcutUri != null || _path.startsWith('cloudreve://')) {
      _changePath(file.contentUri);
    } else if (_path == '/') {
      _changePath(_path + file.name);
    } else {
      _changePath('$_path/${file.name}');
    }
  }

  /// 目录长按事件
  void _dirLongPress(BuildContext context, MFile file) {
    _showEntryDetails(context, file, allowOpen: true, allowDownload: false);
  }

  /// 文件长按事件
  void _fileLongPress(
    BuildContext context,
    MFile file, {
    bool del = true,
    bool rename = true,
    bool share = true,
    bool download = true,
  }) {
    _showEntryDetails(
      context,
      file,
      allowDelete: del,
      allowRename: rename,
      allowShare: share,
      allowOpen: true,
      allowDownload: download,
    );
  }

  Future<void> _showEntryDetails(
    BuildContext context,
    MFile file, {
    bool allowDelete = true,
    bool allowRename = true,
    bool allowShare = true,
    bool allowOpen = true,
    bool allowDownload = true,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            2,
            20,
            20 + MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  FileIconBadge(file: file, size: 62),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          file.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          file.type == 'dir'
                              ? '文件夹 · ${file.getFormatDate()}'
                              : '${file.displaySize} · ${file.getFormatDate()}',
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              CloudrevePanel(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 12,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    if (allowOpen)
                      _FileAction(
                        icon: file.type == 'dir'
                            ? Icons.folder_open_rounded
                            : Icons.visibility_outlined,
                        label: file.type == 'dir' ? '打开' : '预览',
                        onTap: () {
                          if (file.type == 'dir') {
                            Navigator.pop(sheetContext);
                            _dirTap(file);
                          } else {
                            _openFileButtonTap(context, file, sheetContext);
                          }
                        },
                      ),
                    if (allowDownload && file.type == 'file')
                      _FileAction(
                        icon: Icons.download_rounded,
                        label: '下载',
                        onTap: () =>
                            _downloadButtonTap(context, sheetContext, file),
                      ),
                    if (allowShare)
                      _FileAction(
                        icon: Icons.ios_share_rounded,
                        label: '分享',
                        onTap: () => _shareButtonTap(sheetContext, file),
                      ),
                    if (allowRename)
                      _FileAction(
                        icon: Icons.edit_outlined,
                        label: '重命名',
                        onTap: () =>
                            _renameButtonTap(context, sheetContext, file),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Text(
                '文件信息',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              CloudrevePanel(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 7,
                ),
                child: Column(
                  children: [
                    _FileInfoRow(
                      label: '类型',
                      value: file.type == 'dir'
                          ? '文件夹'
                          : _fileTypeLabel(file.name),
                    ),
                    const Divider(height: 1),
                    _FileInfoRow(
                      label: '大小',
                      value: file.type == 'dir' ? '—' : file.displaySize,
                    ),
                    const Divider(height: 1),
                    _FileInfoRow(
                      label: '位置',
                      value: _path == '/' ? '我的文件' : _path,
                    ),
                    const Divider(height: 1),
                    _FileInfoRow(label: '修改时间', value: file.getFormatDate()),
                  ],
                ),
              ),
              if (allowDelete) ...[
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: () => _deleteEntry(context, sheetContext, file),
                    style: TextButton.styleFrom(
                      foregroundColor: CloudreveColors.danger,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: Text(file.type == 'dir' ? '删除文件夹' : '删除文件'),
                  ),
                ),
              ],
              const SizedBox(height: 2),
              Center(
                child: Text(
                  file.type == 'dir'
                      ? 'Cloudreve 文件夹'
                      : _fileTypeLabel(file.name),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteEntry(
    BuildContext context,
    BuildContext sheetContext,
    MFile file,
  ) async {
    final confirmed = await showDialog<bool>(
      context: sheetContext,
      builder: (dialogContext) => AlertDialog(
        title: Text(file.type == 'dir' ? '删除文件夹？' : '删除文件？'),
        content: Text('“${file.name}”删除后会进入回收站。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: CloudreveColors.danger,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    // Removing a shortcut must remove the local shortcut, never its source.
    final success = await CloudreveRepository.deleteFiles(
      fileUris: [file.path],
    );
    if (!context.mounted) return;
    if (success) {
      if (sheetContext.mounted) Navigator.pop(sheetContext);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已移入回收站')));
      _refreshCallback(true);
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('删除失败，请重试')));
    }
  }

  String _fileTypeLabel(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return '文件';
    return '${name.substring(dot + 1).toUpperCase()} 文件';
  }

  /// Cache by content version, not just file ID (also works for search results).
  Future<Uint8List> _geThumbImage(MFile file) =>
      CacheUtil.cachedBytes('thumb', file.cacheVersion, () async {
        final bytes = await CloudreveRepository.fetchThumbnailBytes(
          file.contentUri,
        );
        if (bytes == null || bytes.isEmpty) throw StateError('暂无缩略图');
        return bytes;
      });

  Future<Uint8List> _getImage(MFile file) =>
      CacheUtil.cachedBytes('image', file.cacheVersion, () async {
        final url = await _ensureDownloadUrl(
          file.id,
          file.contentUri,
          contextHint: file.contentContextHint ?? _currentListing?.contextHint,
        );
        if (url == null) throw StateError('获取图片链接失败');
        final bytes = await CloudreveRepository.fetchRaw(url);
        if (bytes == null || bytes.isEmpty) throw StateError('图片内容为空');
        return bytes;
      });

  /// 图片点击事件
  void _imageTap(BuildContext context, MFile file) {
    final image = _getImage(file);
    image.ignore();
    Navigator.of(context).push(
      cloudrevePageRoute<void>(
        context,
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: Text(file.name, overflow: TextOverflow.ellipsis),
          ),
          body: FutureBuilder<Uint8List>(
            future: image,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _PreviewErrorState(
                  message: '图片加载失败，请检查网络后重试',
                  onClose: () => Navigator.pop(context),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return PhotoView(
                imageProvider: MemoryImage(snapshot.data!),
                backgroundDecoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// 刷新函数
  Future<void> _refresh(BuildContext context) => _refreshCallback(true);

  /// 下载按钮点击
  void _downloadButtonTap(
    BuildContext context,
    BuildContext? dialogContext,
    MFile file,
  ) async {
    await _downloadDirectoryReady;
    if (!context.mounted) return;
    final fileUri = _uriForFile(file);
    if (fileUri == null) {
      return;
    }
    final targetPath = _temporaryFilePath(file.name);
    File f = File(targetPath);
    var exist = await f.exists();
    if (!context.mounted) return;
    if (exist) {
      if (dialogContext != null && dialogContext.mounted) {
        Navigator.pop(dialogContext);
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('文件已存在')));
    } else {
      final contextHint = _currentListing?.contextHint;
      final url = await _ensureDownloadUrl(
        file.id,
        fileUri,
        contextHint: contextHint,
      );
      if (!context.mounted) return;
      if (url == null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('获取下载链接失败')));
        return;
      }
      Dio dio = Dio();
      if (dialogContext != null && dialogContext.mounted) {
        Navigator.pop(dialogContext);
      }
      int fileHashCode = file.hashCode;
      CancelToken cancelToken = CancelToken();
      downloadCancelTokenMap[fileHashCode] = cancelToken;
      Response<dynamic>? downloadResponse;
      try {
        downloadResponse = await dio.download(
          url,
          targetPath,
          cancelToken: cancelToken,
          onReceiveProgress: (process, total) {
            final percent = process / total;
            unawaited(
              _showDownloadNotification(
                id: fileHashCode,
                title: '下载 ${file.name}',
                body: '${(percent * 100).toStringAsFixed(2)}%',
                payload: 'download-doing-$fileHashCode',
              ),
            );
          },
        );
      } on DioException catch (err) {
        if (err.type == DioExceptionType.cancel) {
          await _flutterLocalNotificationsPlugin.cancel(fileHashCode);
          await _showDownloadNotification(
            id: fileHashCode,
            title: '下载 ${file.name}',
            body: '已取消',
            payload: 'download-cancel-$fileHashCode',
          );
        } else {
          await _showDownloadNotification(
            id: fileHashCode,
            title: '下载 ${file.name}',
            body: '下载出错',
            payload: 'download-error-$fileHashCode',
          );
        }
        return;
      }
      if (downloadResponse.statusCode == 200) {
        await _flutterLocalNotificationsPlugin.cancel(fileHashCode);
        await _showDownloadNotification(
          id: fileHashCode,
          title: '下载 ${file.name}',
          body: '至:$_downPath',
          payload: 'download-done-$_downPath',
        );
      } else {
        await _flutterLocalNotificationsPlugin.cancel(fileHashCode);
        await _showDownloadNotification(
          id: fileHashCode,
          title: '下载 ${file.name}',
          body: '下载出错',
          payload: 'download-error-$fileHashCode',
        );
      }
    }
  }

  Future<String?> _ensureDownloadUrl(
    String cacheKey,
    String fileUri, {
    String? contextHint,
  }) async {
    return CloudreveRepository.createDownloadUrl(
      fileUri,
      contextHint: contextHint,
    );
  }

  String _temporaryFilePath(String fileName, {String prefix = ''}) {
    final safeName = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final separator = Platform.pathSeparator;
    final base = _downPath.endsWith(separator)
        ? _downPath.substring(0, _downPath.length - 1)
        : _downPath;
    return '$base$separator$prefix$safeName';
  }

  String? _uriForFile(MFile file) {
    if (file.contentUri.isNotEmpty) {
      return file.contentUri;
    }
    return _uriForId(file.id);
  }

  String? _uriForId(String id) {
    final listing = _currentListing;
    if (listing == null) {
      return null;
    }
    for (final file in listing.files) {
      if (file.id == id) return file.contentUri;
    }
    return listing.fileMap[id]?.path;
  }

  /// 根据文件类型选择应用内预览方式。
  Future<void> _openFileButtonTap(
    BuildContext context,
    MFile file, [
    BuildContext? dialogContext,
  ]) async {
    if (dialogContext != null && dialogContext.mounted) {
      Navigator.pop(dialogContext);
    }
    if (!context.mounted) return;

    try {
      await CloudreveRepository.resolveShortcut(file);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('分享无法打开：$error')));
      }
      return;
    }
    if (!context.mounted) return;

    if (imageRex.hasMatch(file.name)) {
      _imageTap(context, file);
      return;
    }

    if (audioPreviewRegex.hasMatch(file.name)) {
      await _startAudioPlayback(context, file);
      return;
    }

    if (videoRegex.hasMatch(file.name)) {
      await _openVideoPreview(context, file);
      return;
    }

    if (zipPreviewRegex.hasMatch(file.name)) {
      await Navigator.of(context).push(
        cloudrevePageRoute<void>(
          context,
          builder: (_) => _ArchivePreviewPage(
            fileName: file.name,
            entries: _loadZipEntries(file),
          ),
        ),
      );
      return;
    }

    if (browserPreviewRegex.hasMatch(file.name)) {
      await _openBrowserPreview(context, file);
      return;
    }

    await _showUnsupportedPreview(context, file);
  }

  Future<void> _startAudioPlayback(BuildContext context, MFile file) async {
    final listing = _currentListing;
    final belongsToCurrentListing =
        listing?.files.any((item) {
          if (file.id.isNotEmpty && item.id.isNotEmpty) {
            return item.id == file.id;
          }
          return item.path == file.path;
        }) ??
        false;

    final candidates = belongsToCurrentListing
        ? listing!.files
              .where(
                (item) =>
                    item.type == 'file' &&
                    audioPreviewRegex.hasMatch(item.name),
              )
              .toList()
        : <MFile>[file];
    final compare = _compare;
    if (compare != null) candidates.sort(compare);

    final tracks = <CloudreveAudioTrack>[];
    String? initialTrackId;
    for (final candidate in candidates) {
      final rawPath = candidate.contentUri.isNotEmpty
          ? candidate.contentUri
          : listing?.fileMap[candidate.id]?.path ?? '';
      if (rawPath.isEmpty) continue;
      final trackId = candidate.id.isNotEmpty ? candidate.id : rawPath;
      tracks.add(
        CloudreveAudioTrack(
          id: trackId,
          name: candidate.name,
          uri: rawPath,
          contextHint:
              candidate.contentContextHint ??
              (belongsToCurrentListing ? listing?.contextHint : null),
        ),
      );
      final isInitial = file.id.isNotEmpty && candidate.id.isNotEmpty
          ? candidate.id == file.id
          : candidate.path == file.path;
      if (isInitial) initialTrackId = trackId;
    }

    final started = await _audioController.playQueue(
      tracks,
      initialTrackId: initialTrackId ?? file.id,
    );
    if (!started && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_audioController.errorMessage ?? '无法播放这个音频文件')),
      );
    }
  }

  Future<void> _openVideoPreview(BuildContext context, MFile file) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 10),
        content: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text('正在准备 ${file.name}')),
          ],
        ),
      ),
    );

    try {
      final url = await _freshPreviewUrlFor(file);
      // Do not animate a second loading indicator behind the video route.
      messenger.removeCurrentSnackBar();
      if (!context.mounted) return;

      // Avoid mixing an already-playing music track with the video's audio.
      if (_audioController.playing) {
        await _audioController.togglePlayback();
      }
      if (!context.mounted) return;

      await Navigator.of(context).push(
        cloudrevePageRoute<void>(
          context,
          builder: (_) => CloudreveVideoPlayerPage(title: file.name, url: url),
        ),
      );
    } catch (error) {
      messenger.hideCurrentSnackBar();
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('视频加载失败：${_friendlyPreviewError(error)}')),
      );
    }
  }

  String _friendlyPreviewError(Object error) {
    return error.toString().replaceFirst(
      RegExp(r'^(Bad state|StateError):\s*'),
      '',
    );
  }

  Future<String> _freshPreviewUrlFor(MFile file) async {
    await CloudreveRepository.resolveShortcut(file);
    final fileUri = _uriForFile(file);
    if (fileUri == null) throw StateError('找不到文件地址');
    final url = await CloudreveRepository.createDownloadUrl(
      fileUri,
      contextHint: file.contentContextHint ?? _currentListing?.contextHint,
    );
    if (url == null || url.isEmpty) throw StateError('获取预览链接失败');
    return url;
  }

  Future<String> _previewUrlFor(MFile file) async {
    await CloudreveRepository.resolveShortcut(file);
    final fileUri = _uriForFile(file);
    if (fileUri == null) throw StateError('找不到文件地址');
    final url = await _ensureDownloadUrl(
      file.id,
      fileUri,
      contextHint: file.contentContextHint ?? _currentListing?.contextHint,
    );
    if (url == null) throw StateError('获取预览链接失败');
    return url;
  }

  Future<String> _cacheFileForPreview(MFile file) async {
    await _downloadDirectoryReady;
    await CloudreveRepository.resolveShortcut(file);
    final cacheKey =
        '${HttpUtil.dio.options.baseUrl.hashCode}-${file.id}-${file.size}-${file.date.hashCode}';
    final targetPath = _temporaryFilePath(
      file.name,
      prefix: 'preview-$cacheKey-',
    );
    final target = File(targetPath);
    if (await target.exists()) {
      final cachedSize = await target.length();
      if (file.size > 0 && cachedSize == file.size) return targetPath;
    }

    final partial = File('$targetPath.part');
    final client = Dio();
    try {
      final response = await client.download(
        await _previewUrlFor(file),
        partial.path,
      );
      if (response.statusCode != 200 ||
          !await partial.exists() ||
          (file.size > 0 && await partial.length() != file.size)) {
        throw StateError('文件下载不完整，请重试');
      }
      await partial.rename(targetPath);
    } finally {
      client.close();
      if (await partial.exists()) await partial.delete();
    }
    return targetPath;
  }

  Future<List<_ArchiveEntryInfo>> _loadZipEntries(MFile file) async {
    final localPath = await _cacheFileForPreview(file);
    final input = InputFileStream(localPath);
    try {
      final archive = ZipDecoder().decodeStream(input);
      final entries = archive
          .map(
            (entry) => _ArchiveEntryInfo(
              name: _decodeArchiveName(entry.name).replaceAll('\\', '/'),
              size: entry.size,
              isDirectory: entry.isDirectory,
            ),
          )
          .toList();
      entries.sort((a, b) {
        if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      return entries;
    } on ArchiveException {
      throw StateError('压缩包已损坏或使用了不支持的加密方式');
    } finally {
      input.closeSync();
    }
  }

  Future<void> _openBrowserPreview(BuildContext context, MFile file) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        content: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text('正在准备 ${file.name}…')),
          ],
        ),
      ),
    );
    try {
      final launched = await launchUrl(
        Uri.parse(await _previewUrlFor(file)),
        mode: LaunchMode.inAppWebView,
        webViewConfiguration: const WebViewConfiguration(
          enableJavaScript: true,
          enableDomStorage: true,
        ),
      );
      messenger.hideCurrentSnackBar();
      if (!launched && context.mounted) {
        await _showUnsupportedPreview(context, file);
      }
    } catch (_) {
      messenger.hideCurrentSnackBar();
      if (context.mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('预览加载失败，请检查网络后重试')),
        );
      }
    }
  }

  Future<void> _showUnsupportedPreview(BuildContext context, MFile file) async {
    final action = await showDialog<_PreviewFallbackAction>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.file_open_outlined),
        title: const Text('此格式暂不支持内容预览'),
        content: Text('“${file.name}”可以下载保存，或交给手机中已安装的应用打开。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, _PreviewFallbackAction.download),
            child: const Text('下载'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              _PreviewFallbackAction.openExternally,
            ),
            child: const Text('用其他应用打开'),
          ),
        ],
      ),
    );
    if (!context.mounted) return;
    if (action == _PreviewFallbackAction.download) {
      _downloadButtonTap(context, null, file);
    } else if (action == _PreviewFallbackAction.openExternally) {
      await _openWithOtherApp(context, file);
    }
  }

  Future<void> _openWithOtherApp(BuildContext context, MFile file) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(content: Text('正在准备 ${file.name}…')));
    try {
      final result = await OpenFile.open(await _cacheFileForPreview(file));
      messenger.hideCurrentSnackBar();
      if (result.type != ResultType.done && context.mounted) {
        messenger.showSnackBar(const SnackBar(content: Text('没有找到能打开此格式的应用')));
      }
    } catch (_) {
      messenger.hideCurrentSnackBar();
      if (context.mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('文件打开失败，请检查网络后重试')),
        );
      }
    }
  }

  Future<void> _shareButtonTap(BuildContext sheetContext, MFile file) async {
    // Close the action sheet before opening a new route. Dialogs return data,
    // never retain contexts belonging to another route.
    Navigator.pop(sheetContext);
    final link = await showDialog<String>(
      context: context,
      builder: (_) => ShareDialog(file: file),
    );
    if (!mounted || link == null) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('分享成功')));
    if (link.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (_) => ShareResultDialog(link: link),
      );
    }
  }

  void _renameButtonTap(
    BuildContext context,
    BuildContext fatherContext,
    MFile file,
  ) {
    Navigator.pop(fatherContext);
    showDialog(
      context: context,
      builder: (context) {
        return RenameFileDialog(
          file,
          fatherContext,
          () => _refreshCallback(true),
        );
      },
    );
  }

  Future<void> _showDownloadNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    var android = AndroidNotificationDetails(
      '文件下载',
      '文件下载通道',
      playSound: false,
      channelDescription: '文件下载',
      priority: Priority.min,
      importance: Importance.min,
    );
    var iOS = DarwinNotificationDetails();
    var platform = NotificationDetails(android: android, iOS: iOS);
    await _flutterLocalNotificationsPlugin.show(
      id,
      title,
      body,
      platform,
      payload: payload,
    );
  }

  Widget myInkWell({
    required Widget child,
    required MFile file,
    required BuildContext context,
    required BorderRadius borderRadius,
  }) {
    return InkWell(
      enableFeedback: context.watch<SoundEffectProvider?>()?.enabled ?? true,
      borderRadius: borderRadius,
      child: child,
      onTap: () {
        if (file.type == 'file') {
          if (imageRex.hasMatch(file.name)) {
            _imageTap(context, file);
          } else {
            _openFileButtonTap(context, file);
          }
        } else {
          _dirTap(file);
        }
      },
      onDoubleTap: () {},
      onLongPress: () {
        if (file.type == 'file') {
          _fileLongPress(context, file);
        } else {
          _dirLongPress(context, file);
        }
      },
    );
  }
}

enum _PreviewFallbackAction { download, openExternally }

String _decodeArchiveName(String name) {
  final bytes = name.codeUnits;
  final mightBeLegacyEncoded =
      bytes.any((unit) => unit >= 0x80) && bytes.every((unit) => unit <= 0xff);
  if (!mightBeLegacyEncoded) return name;
  try {
    final decoded = gbk.decode(bytes);
    final containsChinese = RegExp(r'[\u3400-\u9fff]').hasMatch(decoded);
    if (containsChinese && !decoded.contains('\uFFFD')) return decoded;
  } catch (_) {
    // Keep the original name when it is not valid GBK.
  }
  return name;
}

class _ArchiveEntryInfo {
  const _ArchiveEntryInfo({
    required this.name,
    required this.size,
    required this.isDirectory,
  });

  final String name;
  final int size;
  final bool isDirectory;

  String get displayName {
    final normalized = name.endsWith('/')
        ? name.substring(0, name.length - 1)
        : name;
    final slash = normalized.lastIndexOf('/');
    return slash < 0 ? normalized : normalized.substring(slash + 1);
  }

  String get parentPath {
    final normalized = name.endsWith('/')
        ? name.substring(0, name.length - 1)
        : name;
    final slash = normalized.lastIndexOf('/');
    return slash < 0 ? '' : normalized.substring(0, slash);
  }
}

class _ArchivePreviewPage extends StatelessWidget {
  const _ArchivePreviewPage({required this.fileName, required this.entries});

  final String fileName;
  final Future<List<_ArchiveEntryInfo>> entries;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(fileName, overflow: TextOverflow.ellipsis)),
      body: FutureBuilder<List<_ArchiveEntryInfo>>(
        future: entries,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _PreviewErrorState(
              message: snapshot.error.toString().replaceFirst(
                RegExp(r'^(Bad state|StateError):\s*'),
                '',
              ),
              onClose: () => Navigator.pop(context),
            );
          }
          if (!snapshot.hasData) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('正在下载并读取压缩包…'),
                ],
              ),
            );
          }

          final files = snapshot.data!;
          if (files.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 52,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 14),
                  const Text('压缩包为空'),
                ],
              ),
            );
          }

          final fileCount = files.where((entry) => !entry.isDirectory).length;
          final directoryCount = files.length - fileCount;
          return Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CloudrevePanel(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.folder_zip_rounded,
                        color: CloudreveColors.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '$fileCount 个文件 · $directoryCount 个文件夹',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '压缩包内容',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: files.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final entry = files[index];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 3,
                        ),
                        leading: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: CloudreveColors.primarySoft,
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: Icon(
                            entry.isDirectory
                                ? Icons.folder_rounded
                                : Icons.insert_drive_file_outlined,
                            color: CloudreveColors.primary,
                          ),
                        ),
                        title: Text(
                          entry.displayName.isEmpty
                              ? entry.name
                              : entry.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          entry.parentPath.isEmpty
                              ? entry.isDirectory
                                    ? '文件夹'
                                    : MFile.getFileSize(entry.size.toDouble())
                              : entry.isDirectory
                              ? entry.parentPath
                              : '${entry.parentPath} · ${MFile.getFileSize(entry.size.toDouble())}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PreviewErrorState extends StatelessWidget {
  const _PreviewErrorState({required this.message, required this.onClose});

  final String message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 54,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: onClose, child: const Text('返回')),
        ],
      ),
    ),
  );
}

class _FileAction extends StatelessWidget {
  const _FileAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    enableFeedback: context.watch<SoundEffectProvider?>()?.enabled ?? true,
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: CloudreveColors.primarySoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: CloudreveColors.primary, size: 21),
          ),
          const SizedBox(height: 7),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    ),
  );
}

class _FileInfoRow extends StatelessWidget {
  const _FileInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 13),
    child: Row(
      children: [
        SizedBox(
          width: 78,
          child: Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

class _FileMoreButton extends StatelessWidget {
  const _FileMoreButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: '更多操作',
      onPressed: onPressed,
      icon: const Icon(Icons.more_horiz_rounded),
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      style: IconButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.surface
            .withValues(alpha: 0.88),
        fixedSize: const Size(40, 40),
      ),
    );
  }
}
