import 'package:cloudreve/state/app_state.dart';
import 'package:cloudreve/utils/cloudreve_repository.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class RenameNickDialog extends StatefulWidget {
  const RenameNickDialog({
    super.key,
    required this.nick,
    required this.refresh,
  });
  final String nick;
  final void Function(bool) refresh;
  @override
  State<RenameNickDialog> createState() => _RenameNickDialogState();
}

class _RenameNickDialogState extends State<RenameNickDialog> {
  late final _controller = TextEditingController(text: widget.nick);
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
    if (name == widget.nick) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await CloudreveRepository.updateNickname(name);
      if (!mounted) return;
      if (result?.code != 0) {
        throw CloudreveApiException(result?.msg ?? '昵称修改失败');
      }
      await context.read<AppState>().applyNickname(name);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      widget.refresh(true);
      Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(content: Text('昵称已更新')));
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is CloudreveApiException
              ? error.message
              : '修改失败，请检查网络后重试',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('修改昵称'),
    content: Form(
      key: _formKey,
      child: TextFormField(
        controller: _controller,
        autofocus: true,
        maxLength: 255,
        textInputAction: TextInputAction.done,
        onFieldSubmitted: (_) => _save(),
        decoration: InputDecoration(labelText: '昵称', errorText: _error),
        validator: (value) =>
            value?.trim().isNotEmpty == true ? null : '昵称不能为空',
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
