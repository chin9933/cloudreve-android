import 'package:cloudreve/utils/http_util.dart';
import 'package:flutter/material.dart';

/// Owns its controller until the dialog's exit animation has finished.
class AddServerDialog extends StatefulWidget {
  const AddServerDialog({super.key});

  @override
  State<AddServerDialog> createState() => _AddServerDialogState();
}

class _AddServerDialogState extends State<AddServerDialog> {
  final _controller = TextEditingController(text: 'https://');
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('新增服务器'),
    content: Form(
      key: _formKey,
      child: TextFormField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.url,
        decoration: const InputDecoration(
          labelText: '服务器地址',
          hintText: 'https://cloud.example.com',
          prefixIcon: Icon(Icons.language_rounded),
        ),
        validator: (value) {
          if (value == null || value.trim().isEmpty) return '请输入服务器地址';
          try {
            HttpUtil.normalizeApiBaseUrl(value);
            return null;
          } on FormatException catch (error) {
            return error.message;
          }
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          if (_formKey.currentState!.validate()) {
            Navigator.pop(
              context,
              HttpUtil.normalizeApiBaseUrl(_controller.text),
            );
          }
        },
        child: const Text('添加'),
      ),
    ],
  );
}
