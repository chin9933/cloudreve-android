import 'package:cloudreve/entity/m_file.dart';
import 'package:cloudreve/utils/cloudreve_repository.dart';
import 'package:flutter/material.dart';

String normalizeSaveFolder(String value) {
  final uri = Uri.tryParse(
    value.startsWith('/') ? 'cloudreve://my$value' : value,
  );
  if (uri == null ||
      uri.scheme != 'cloudreve' ||
      uri.host != 'my' ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      uri.pathSegments.any((part) => part == '.' || part == '..')) {
    return 'cloudreve://my';
  }
  final parts = uri.pathSegments.where((part) => part.isNotEmpty).toList();
  return Uri(scheme: 'cloudreve', host: 'my', pathSegments: parts).toString();
}

String saveFolderLabel(String value) {
  final parts = Uri.parse(normalizeSaveFolder(value)).pathSegments;
  return ['我的文件', ...parts].join(' / ');
}

class SaveFolderDialog extends StatefulWidget {
  const SaveFolderDialog({super.key, required this.initialFolder});
  final String initialFolder;
  @override
  State<SaveFolderDialog> createState() => _SaveFolderDialogState();
}

class _SaveFolderDialogState extends State<SaveFolderDialog> {
  late String _path = normalizeSaveFolder(widget.initialFolder);
  final _folders = <MFile>[];
  int _generation = 0;
  int _page = 0;
  String? _nextToken;
  bool _more = false;
  bool _busy = false;
  bool _loaded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false, bool refresh = false}) async {
    if (more && _busy) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
      if (!more) {
        _loaded = false;
        _folders.clear();
        _page = 0;
        _nextToken = null;
      }
    });
    final page = more ? _page + 1 : 0;
    try {
      final result = await CloudreveRepository.listFiles(
        _path,
        page: page,
        nextPageToken: more ? _nextToken : null,
        forceRefresh: refresh,
      );
      if (!mounted || generation != _generation) return;
      final pagination = result.raw?.data?.pagination;
      setState(() {
        // Share shortcuts are not writable destinations in the user's space.
        _folders.addAll(
          result.files.where(
            (file) =>
                file.type == 'dir' &&
                file.shortcutUri == null &&
                Uri.tryParse(file.path)?.host == 'my',
          ),
        );
        _page = page;
        _nextToken = pagination?.nextToken;
        _more = pagination?.isCursor == true
            ? _nextToken?.isNotEmpty == true
            : pagination?.totalItems != null
            ? (page + 1) * (pagination?.pageSize ?? 100) <
                  pagination!.totalItems!
            : result.files.length >= 100;
        _loaded = true;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(
          () => _error = error is CloudreveApiException
              ? error.message
              : '文件夹加载失败，请重试',
        );
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  void _open(String path) {
    _path = normalizeSaveFolder(path);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final uri = Uri.parse(_path);
    final parts = uri.pathSegments.where((part) => part.isNotEmpty).toList();
    return Dialog(
      key: const Key('save-folder-dialog'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 480,
        height: MediaQuery.sizeOf(context).height * 0.68,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '选择保存位置',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: '刷新文件夹',
                    onPressed: _busy ? null : () => _load(refresh: true),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                  IconButton(
                    tooltip: '关闭位置选择',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  IconButton(
                    tooltip: '返回上一级',
                    onPressed: parts.isEmpty
                        ? null
                        : () => _open(
                            uri
                                .replace(
                                  pathSegments: parts.take(parts.length - 1),
                                )
                                .toString(),
                          ),
                    icon: const Icon(Icons.arrow_upward_rounded),
                  ),
                  Expanded(
                    child: Text(
                      saveFolderLabel(_path),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (parts.isNotEmpty)
                    TextButton(
                      onPressed: () => _open('/'),
                      child: const Text('根目录'),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _busy && !_loaded
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      children: [
                        for (final folder in _folders)
                          ListTile(
                            key: ValueKey('save-folder:${folder.path}'),
                            leading: Icon(
                              Icons.folder_rounded,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            title: Text(
                              folder.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => _open(folder.path),
                          ),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              children: [
                                Text(_error!, textAlign: TextAlign.center),
                                TextButton(
                                  onPressed: () => _load(more: _loaded),
                                  child: const Text('重新加载'),
                                ),
                              ],
                            ),
                          )
                        else if (_folders.isEmpty && !_more)
                          const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              '没有子文件夹，可保存到此处',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        if (_busy)
                          const Center(child: CircularProgressIndicator())
                        else if (_more && _error == null)
                          TextButton(
                            onPressed: () => _load(more: true),
                            child: const Text('加载更多'),
                          ),
                      ],
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    key: const Key('confirm-save-folder'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 48),
                    ),
                    onPressed: !_loaded || _busy || _error != null
                        ? null
                        : () => Navigator.pop(context, _path),
                    child: const Text('保存到此处'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
