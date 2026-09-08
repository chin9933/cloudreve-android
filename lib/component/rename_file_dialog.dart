import 'package:cloudreve/entity/m_file.dart';
import 'package:cloudreve/utils/cloudreve_repository.dart';
import 'package:flutter/material.dart';

class RenameFileDialog extends StatefulWidget {
  const RenameFileDialog(
    this.file,
    this.fatherContext,
    this.refresh, {
    super.key,
  });
  final MFile file;
  final BuildContext fatherContext;
  final VoidCallback refresh;
  @override
  State<RenameFileDialog> createState() => _RenameFileDialogState();
}

class _RenameFileDialogState extends State<RenameFileDialog> {
  late final _controller = TextEditingController(text: widget.file.name);
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    final name = _controller.text.trim();
    if (name == widget.file.name) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await CloudreveRepository.renameEntry(
        fileUri: widget.file.path,
        newName: name,
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      widget.refresh();
      Navigator.pop(context, true);
      messenger.showSnackBar(const SnackBar(content: Text('重命名成功')));
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is CloudreveApiException
              ? error.message
              : '重命名失败，请检查网络后重试',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('重命名'),
    content: Form(
      key: _formKey,
      child: TextFormField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(labelText: '名称', errorText: _error),
        textInputAction: TextInputAction.done,
        onFieldSubmitted: (_) => _save(),
        validator: (value) {
          final name = value?.trim() ?? '';
          return name.isEmpty ||
                  name == '.' ||
                  name == '..' ||
                  RegExp(r'[/\\\x00]').hasMatch(name)
              ? '请输入有效名称，不能包含斜杠'
              : null;
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(_saving ? '保存中…' : '保存'),
      ),
    ],
  );
}
