import 'package:cloudreve/component/file_search_results.dart';
import 'package:cloudreve/entity/m_file.dart';
import 'package:flutter/material.dart';

/// A bounded modal keeps the current page in place while searching.
class FileSearchDialog extends StatefulWidget {
  const FileSearchDialog({super.key});

  @override
  State<FileSearchDialog> createState() => _FileSearchDialogState();
}

class _FileSearchDialogState extends State<FileSearchDialog> {
  final _controller = TextEditingController();
  bool _submitted = false;
  int _refreshVersion = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    key: const Key('file-search-dialog'),
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    clipBehavior: Clip.antiAlias,
    child: SizedBox(
      key: const Key('file-search-surface'),
      width: 560,
      height: MediaQuery.sizeOf(context).height * 0.76,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '搜索文件',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: '刷新搜索结果',
                  onPressed: () => setState(() => _refreshVersion++),
                  icon: const Icon(Icons.refresh_rounded),
                ),
                IconButton(
                  tooltip: '关闭搜索',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            child: TextField(
              key: const Key('file-search-input'),
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: (_) => setState(() => _submitted = false),
              onSubmitted: (_) {
                FocusScope.of(context).unfocus();
                setState(() => _submitted = true);
              },
              decoration: InputDecoration(
                hintText: '输入文件名称',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清除搜索',
                        onPressed: () => setState(() {
                          _controller.clear();
                          _submitted = false;
                        }),
                        icon: const Icon(Icons.close_rounded, size: 20),
                      ),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: FileSearchResults(
              query: _controller.text,
              submitted: _submitted,
              refreshVersion: _refreshVersion,
              onOpen: (MFile file) => Navigator.pop(context, file),
            ),
          ),
        ],
      ),
    ),
  );
}
