import 'package:cloudreve/component/save_folder_dialog.dart';
import 'package:cloudreve/entity/share_link.dart';
import 'package:cloudreve/theme/app_theme.dart';
import 'package:cloudreve/utils/cloudreve_repository.dart';
import 'package:cloudreve/utils/http_util.dart';
import 'package:cloudreve/utils/share_clipboard_history.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ImportShareDialog extends StatefulWidget {
  const ImportShareDialog({super.key, this.destination = '/'});
  final String destination;
  @override
  State<ImportShareDialog> createState() => _ImportShareDialogState();
}

class _ImportShareDialogState extends State<ImportShareDialog> {
  final _link = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  late String _destination = normalizeSaveFolder(widget.destination);
  int _pasteGeneration = 0;
  SharedContent? _content;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _paste(onlyNew: true);
  }

  @override
  void dispose() {
    _link.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _paste({bool onlyNew = false}) async {
    if (_busy) return;
    final generation = ++_pasteGeneration;
    try {
      // Read only in this explicitly opened window, never on app startup.
      final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted || generation != _pasteGeneration || _busy) return;
      if (clipboard?.text?.trim().isNotEmpty == true) {
        final link = ShareLink.parse(
          clipboard!.text!,
          server: Uri.parse(HttpUtil.dio.options.baseUrl),
        );
        if (onlyNew && _link.text.isNotEmpty) return;
        final fresh = await ShareClipboardHistory.claim(
          link,
          scope: '${HttpUtil.dio.options.baseUrl}|${HttpUtil.cacheUserId}',
        );
        if (!mounted ||
            generation != _pasteGeneration ||
            _busy ||
            (onlyNew && (!fresh || _link.text.isNotEmpty))) {
          return;
        }
        _link.text = clipboard.text!;
        _password.clear();
        await _inspect();
      }
    } catch (error) {
      // Ordinary clipboard text must not produce an unsolicited error.
      if (mounted && !onlyNew) {
        setState(
          () => _error = error is FormatException
              ? error.message
              : '无法读取剪贴板，请手动粘贴链接',
        );
      }
    }
  }

  Future<void> _inspect() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _content = null;
      _error = null;
    });
    try {
      final link = ShareLink.parse(
        _link.text,
        server: Uri.parse(HttpUtil.dio.options.baseUrl),
        password: _password.text,
      );
      final content = await CloudreveRepository.inspectShareLink(link);
      if (mounted) {
        setState(() {
          _content = content;
          _name.text = content.name;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is FormatException
              ? error.message
              : error is CloudreveApiException
              ? error.message
              : '读取分享失败，请检查网络后重试',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    if (_busy || _content == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await CloudreveRepository.importShare(
        _content!,
        _destination,
        name: _name.text,
      );
      if (mounted) Navigator.pop(context, _destination);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is CloudreveApiException
              ? error.message
              : '转存未完成，请检查目标目录后重试',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseDestination() async {
    FocusScope.of(context).unfocus();
    final selected = await showDialog<String>(
      context: context,
      builder: (_) => SaveFolderDialog(initialFolder: _destination),
    );
    if (mounted && selected != null) setState(() => _destination = selected);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('导入分享链接'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const Key('import-share-link'),
                controller: _link,
                enabled: !_busy,
                maxLines: 3,
                minLines: 1,
                onChanged: (_) => setState(() {
                  _pasteGeneration++;
                  _content = null;
                }),
                decoration: InputDecoration(
                  labelText: '分享链接',
                  hintText: '粘贴复制的分享链接',
                  suffixIcon: IconButton(
                    onPressed: _busy ? null : _paste,
                    tooltip: '从剪贴板粘贴',
                    icon: const Icon(Icons.content_paste_rounded),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                enabled: !_busy,
                onChanged: (_) => setState(() => _content = null),
                decoration: const InputDecoration(labelText: '提取码（可选）'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                key: const Key('choose-share-destination'),
                onPressed: _busy ? null : _chooseDestination,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.folder_open_rounded),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '保存到：${saveFolderLabel(_destination)}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                ),
              ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.all(18),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (_content != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: CloudrevePanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _content!.name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _content!.folder
                              ? '文件夹（包含子文件）'
                              : _content!.files
                                    .map((file) => file.displaySize)
                                    .join('、'),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_content != null) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _name,
                  enabled: !_busy,
                  decoration: const InputDecoration(labelText: '保存名称'),
                ),
                const SizedBox(height: 10),
                Text(
                  '与网页端一致，保存为分享快捷方式；原分享失效后将无法访问。',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
          onPressed: _busy
              ? null
              : _content == null
              ? _inspect
              : _import,
          child: Text(_content == null ? '读取分享' : '导入'),
        ),
      ],
    ),
  );
}
