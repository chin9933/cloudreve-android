import 'package:cloudreve/entity/m_file.dart';
import 'package:cloudreve/state/download_history_controller.dart';
import 'package:cloudreve/state/sound_effect_provider.dart';
import 'package:cloudreve/theme/app_theme.dart';
import 'package:cloudreve/utils/file_download_service.dart';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

void showDownloadHistory(
  BuildContext context, {
  DownloadHistoryController? controller,
}) {
  Navigator.of(context).push(
    cloudrevePageRoute<void>(
      context,
      builder: (_) => DownloadHistoryPage(controller: controller),
    ),
  );
}

class DownloadHistoryPage extends StatefulWidget {
  const DownloadHistoryPage({
    super.key,
    this.controller,
    this.fileService,
    this.shareRecords,
    this.deleteLocalFiles,
    this.isLocalFileAvailable,
  });
  final DownloadHistoryController? controller;
  final FileDownloadService? fileService;
  final Future<void> Function(List<DownloadRecord> records)? shareRecords;
  final Future<int> Function(List<DownloadRecord> records)? deleteLocalFiles;
  final Future<bool> Function(DownloadRecord record)? isLocalFileAvailable;
  @override
  State<DownloadHistoryPage> createState() => _DownloadHistoryPageState();
}

class _DownloadHistoryPageState extends State<DownloadHistoryPage> {
  int _filter = 0;
  final Set<String> _selectedIds = {};
  DownloadHistoryController get _history =>
      widget.controller ?? DownloadHistoryController.instance;
  FileDownloadService get _files =>
      widget.fileService ?? FileDownloadService.instance;

  List<DownloadRecord> get _selectedRecords => _history.records
      .where((record) => _selectedIds.contains(record.id))
      .toList();

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _history,
    builder: (context, _) {
      final theme = Theme.of(context);
      final records = _history.records
          .where(
            (record) =>
                _filter == 0 ||
                (_filter == 1
                    ? record.kind == TransferKind.download
                    : record.kind != TransferKind.download),
          )
          .toList();
      return Scaffold(
        appBar: AppBar(
          toolbarHeight: 68,
          leadingWidth: 68,
          centerTitle: false,
          leading: Center(
            child: IconButton.filledTonal(
              tooltip: _selectedRecords.isEmpty ? '返回' : '取消选择',
              onPressed: () {
                if (_selectedRecords.isNotEmpty) {
                  setState(_selectedIds.clear);
                } else {
                  Navigator.pop(context);
                }
              },
              style: IconButton.styleFrom(shape: const CircleBorder()),
              icon: Icon(
                _selectedRecords.isEmpty
                    ? Icons.arrow_back_ios_new_rounded
                    : Icons.close_rounded,
                size: 22,
              ),
            ),
          ),
          title: Text(
            _selectedRecords.isEmpty
                ? '下载记录'
                : '已选 ${_selectedRecords.length} 项',
          ),
          actions: [
            if (_selectedRecords.isEmpty)
              IconButton(
                tooltip: '清除已结束记录',
                onPressed: _history.records.any((record) => !record.active)
                    ? _clear
                    : null,
                icon: const Icon(Icons.delete_sweep_outlined),
              ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Column(
              children: [
                const SizedBox(height: 8),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 0, label: Text('全部')),
                    ButtonSegment(value: 1, label: Text('文件下载')),
                    ButtonSegment(value: 2, label: Text('预览加载')),
                  ],
                  selected: {_filter},
                  showSelectedIcon: false,
                  onSelectionChanged: (value) => setState(() {
                    _filter = value.single;
                    _selectedIds.clear();
                  }),
                ),
                if (_history.storageFailed)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      '本机记录暂时无法保存',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                const SizedBox(height: 16),
                Expanded(
                  child: records.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.download_outlined,
                                size: 48,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(height: 12),
                              const Text('暂无记录'),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.only(bottom: 20),
                          itemCount: records.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) => _recordCard(
                            records[index],
                            selected: _selectedIds.contains(records[index].id),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: _selectionBottomBar(_selectedRecords),
      );
    },
  );

  Widget _recordCard(DownloadRecord record, {required bool selected}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final failed = record.status == TransferStatus.failed;
    return Card(
      key: Key('download-record-${record.id}'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: selected ? scheme.primaryContainer.withValues(alpha: 0.48) : null,
      shape: selected
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: scheme.primary, width: 1.4),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(switch (record.kind) {
                  TransferKind.audio => Icons.music_note_rounded,
                  TransferKind.video => Icons.play_circle_outline_rounded,
                  TransferKind.image => Icons.image_outlined,
                  TransferKind.download => Icons.download_rounded,
                  _ => Icons.insert_drive_file_outlined,
                }, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    record.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  key: Key('download-select-${record.id}'),
                  tooltip: selected ? '取消选择' : '选择',
                  onPressed: () => _toggleSelection(record.id),
                  style: IconButton.styleFrom(
                    foregroundColor: selected
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                    shape: const CircleBorder(),
                  ),
                  icon: Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '${record.kind == TransferKind.download ? '文件下载' : '预览加载'} · ${_status(record)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: failed ? scheme.error : scheme.primary,
              ),
            ),
            if (record.active) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: record.progress,
                  minHeight: 4,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              _details(record),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            Row(
              key: Key('download-record-footer-${record.id}'),
              children: [
                Expanded(
                  child: Text(
                    getFormatDate(record.createdAt.toLocal().toIso8601String()),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (!record.active && record.localPath != null)
                  TextButton.icon(
                    key: Key('download-open-${record.id}'),
                    onPressed: () => _open(record),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('打开文件'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
            if (record.active && _history.canCancel(record.id))
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => _history.cancel(record.id),
                  child: const Text('取消'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _status(DownloadRecord record) => switch (record.status) {
    TransferStatus.loading =>
      record.kind == TransferKind.download ? '下载中' : '加载中',
    TransferStatus.completed =>
      record.kind == TransferKind.download ? '已完成' : '已加载',
    TransferStatus.opened =>
      record.kind == TransferKind.document ? '已交给浏览器' : '已开始播放',
    TransferStatus.failed => '失败',
    TransferStatus.cancelled => '已取消',
    TransferStatus.interrupted => '已中断',
  };

  String _details(DownloadRecord record) {
    if ({TransferKind.audio, TransferKind.video}.contains(record.kind)) {
      return '在线播放，不代表已下载完整文件';
    }
    if (record.kind == TransferKind.document) return '浏览器预览，不代表已保存到本机';
    final received = MFile.getFileSize(record.received.toDouble());
    return record.total > 0
        ? '$received / ${MFile.getFileSize(record.total.toDouble())}'
        : '$received · 大小未知';
  }

  void _toggleSelection(String id) {
    setState(() {
      if (!_selectedIds.add(id)) _selectedIds.remove(id);
    });
  }

  Widget _selectionBottomBar(List<DownloadRecord> records) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      reverseDuration: const Duration(milliseconds: 190),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(animation),
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: records.isEmpty
          ? const SizedBox.shrink(key: Key('download-selection-hidden'))
          : _DownloadSelectionBar(
              key: const Key('download-selection-bar'),
              onShare: () => _shareSelected(records),
              onDelete: () => _deleteSelected(records),
              onDetails: records.length == 1
                  ? () => _showDetails(records.single)
                  : null,
            ),
    );
  }

  Future<void> _shareSelected(List<DownloadRecord> records) async {
    try {
      if (widget.shareRecords != null) {
        await widget.shareRecords!(records);
        return;
      }
      if (records.any((record) => record.localPath == null)) {
        _showMessage('只有已保存到本机的文件可以分享');
        return;
      }
      final available = await Future.wait(records.map(_files.isAvailable));
      if (!mounted) return;
      if (available.any((value) => !value)) {
        _showMessage('部分本地文件已失效，请重新下载后再分享');
        return;
      }
      final box = context.findRenderObject() as RenderBox?;
      final origin = box != null && box.hasSize
          ? box.localToGlobal(Offset.zero) & box.size
          : null;
      await SharePlus.instance.share(
        ShareParams(
          files: records.map((record) => XFile(record.localPath!)).toList(),
          subject: records.length == 1
              ? records.single.name
              : '分享 ${records.length} 个文件',
          sharePositionOrigin: origin,
        ),
      );
    } catch (_) {
      if (mounted) _showMessage('无法打开系统分享面板');
    }
  }

  Future<void> _deleteSelected(List<DownloadRecord> records) async {
    var deleteLocalFiles = false;
    final availability = await Future.wait(
      records.map(
        (record) =>
            widget.isLocalFileAvailable?.call(record) ??
            _files.isAvailable(record),
      ),
    );
    if (!mounted) return;
    final localRecords = <DownloadRecord>[
      for (var index = 0; index < records.length; index++)
        if (availability[index]) records[index],
    ];
    final hasLocalFiles = localRecords.isNotEmpty;
    final choice = await showDialog<_DeleteSelectionChoice>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('删除 ${records.length} 条记录？'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('仅删除下载记录，不会删除网盘中的源文件。'),
              if (hasLocalFiles) ...[
                const SizedBox(height: 12),
                CheckboxListTile(
                  key: const Key('delete-local-files-option'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('同时删除本地文件'),
                  value: deleteLocalFiles,
                  onChanged: (value) =>
                      setDialogState(() => deleteLocalFiles = value ?? false),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              key: const Key('confirm-delete-selected'),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(
                dialogContext,
                _DeleteSelectionChoice(deleteLocalFiles: deleteLocalFiles),
              ),
              child: const Text('删除'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    final revision = _history.revision;
    var localDeleteFailures = 0;
    if (choice.deleteLocalFiles) {
      if (widget.deleteLocalFiles != null) {
        localDeleteFailures = await widget.deleteLocalFiles!(localRecords);
      } else {
        for (final record in localRecords) {
          if (!await _files.deleteLocalFile(record)) localDeleteFailures++;
        }
      }
    }
    if (!mounted || revision != _history.revision) return;
    final ids = records.map((record) => record.id).toSet();
    _history.removeRecords(ids);
    setState(() => _selectedIds.removeAll(ids));
    if (choice.deleteLocalFiles && localDeleteFailures > 0) {
      _showMessage('记录已删除，$localDeleteFailures 个本地文件未能删除');
    } else if (choice.deleteLocalFiles) {
      _showMessage('记录和本地文件已删除');
    } else {
      _showMessage('已删除 ${records.length} 条记录');
    }
  }

  void _showDetails(DownloadRecord record) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('记录详情', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            _DownloadDetailRow(label: '文件名', value: record.name),
            _DownloadDetailRow(
              label: '类型',
              value: record.kind == TransferKind.download ? '文件下载' : '预览加载',
            ),
            _DownloadDetailRow(label: '状态', value: _status(record)),
            _DownloadDetailRow(label: '传输信息', value: _details(record)),
            _DownloadDetailRow(
              label: '记录时间',
              value: getFormatDate(
                record.createdAt.toLocal().toIso8601String(),
              ),
            ),
            _DownloadDetailRow(
              label: '本地文件',
              value: record.localPath ?? '未保存到本机',
            ),
          ],
        ),
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _open(DownloadRecord record) async {
    final revision = _history.revision;
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (!await _files.isAvailable(record)) {
        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(content: Text('本地文件已失效或被清理，请重新下载')),
          );
        }
        return;
      }
      if (!mounted || revision != _history.revision) return;
      final result = await OpenFile.open(record.localPath!);
      if (mounted && result.type != ResultType.done) {
        messenger.showSnackBar(const SnackBar(content: Text('没有找到能打开此文件的应用')));
      }
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(const SnackBar(content: Text('无法打开本地文件，请重新下载')));
      }
    }
  }

  Future<void> _clear() async {
    final revision = _history.revision;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除已结束记录？'),
        content: const Text('不会删除已下载的文件，进行中的任务会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (mounted && confirmed == true && revision == _history.revision) {
      _history.clearFinished();
    }
  }
}

class _DeleteSelectionChoice {
  const _DeleteSelectionChoice({required this.deleteLocalFiles});

  final bool deleteLocalFiles;
}

class _DownloadSelectionBar extends StatelessWidget {
  const _DownloadSelectionBar({
    super.key,
    required this.onShare,
    required this.onDelete,
    required this.onDetails,
  });

  final VoidCallback onShare;
  final VoidCallback onDelete;
  final VoidCallback? onDetails;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRect(
      key: const Key('download-selection-bottom-mask'),
      child: ColoredBox(
        color: theme.scaffoldBackgroundColor,
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(12, 9, 12, 5),
          child: Material(
            key: const Key('download-selection-bottom-surface'),
            elevation: 6,
            color: theme.colorScheme.surface,
            surfaceTintColor: Colors.transparent,
            shadowColor: Colors.black.withValues(alpha: 0.12),
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(
                color: theme.dividerColor.withValues(alpha: 0.45),
              ),
            ),
            child: SizedBox(
              height: 68,
              child: Row(
                children: [
                  _DownloadSelectionAction(
                    controlKey: const Key('download-selection-share'),
                    icon: Icons.share_rounded,
                    label: '分享',
                    onTap: onShare,
                  ),
                  _DownloadSelectionAction(
                    controlKey: const Key('download-selection-delete'),
                    icon: Icons.delete_outline_rounded,
                    label: '删除',
                    color: theme.colorScheme.error,
                    onTap: onDelete,
                  ),
                  _DownloadSelectionAction(
                    controlKey: const Key('download-selection-details'),
                    icon: Icons.info_outline_rounded,
                    label: '详情',
                    onTap: onDetails,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DownloadSelectionAction extends StatelessWidget {
  const _DownloadSelectionAction({
    required this.controlKey,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final Key controlKey;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final foreground = enabled
        ? color ?? Theme.of(context).colorScheme.primary
        : Theme.of(context).disabledColor;
    return Expanded(
      child: SizedBox(
        height: double.infinity,
        child: InkWell(
          key: controlKey,
          enableFeedback:
              context.watch<SoundEffectProvider?>()?.enabled ?? true,
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: foreground, size: 23),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DownloadDetailRow extends StatelessWidget {
  const _DownloadDetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 82,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
