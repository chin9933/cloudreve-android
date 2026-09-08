import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Presents a newly created share without retaining the creation route.
class ShareResultDialog extends StatelessWidget {
  const ShareResultDialog({super.key, required this.link});

  final String link;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('分享成功'),
      content: SelectableText(link, autofocus: true),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
        FilledButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: link));
            if (!context.mounted) return;
            final messenger = ScaffoldMessenger.of(context);
            Navigator.pop(context);
            messenger.showSnackBar(const SnackBar(content: Text('复制成功')));
          },
          child: const Text('复制'),
        ),
      ],
    );
  }
}
