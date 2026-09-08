import 'package:cloudreve/entity/m_file.dart';

class ShareLink {
  const ShareLink({required this.id, required this.password});
  final String id;
  final String password;
  String get rootUri =>
      'cloudreve://${Uri.encodeComponent(id)}${password.isEmpty ? '' : ':${Uri.encodeComponent(password)}'}@share';

  factory ShareLink.parse(
    String text, {
    required Uri server,
    String? password,
  }) {
    final match = RegExp(
      r'''https?://[^\s<>"'，。；）)]+''',
      caseSensitive: false,
    ).firstMatch(text);
    final url = Uri.tryParse(match?.group(0) ?? text.trim());
    if (url == null || !['http', 'https'].contains(url.scheme)) {
      throw const FormatException('请粘贴 Cloudreve 分享链接');
    }
    if (url.origin != server.origin || url.userInfo.isNotEmpty) {
      throw const FormatException('请使用当前网盘的分享链接，不能跨站转存');
    }
    String? id;
    String? secret;
    final segments = url.pathSegments;
    if (segments.length >= 2 && segments.first == 's' && segments.length <= 3) {
      id = segments[1];
      secret = segments.length == 3
          ? segments[2]
          : url.queryParameters['password'];
    } else {
      final path = Uri.tryParse(url.queryParameters['path'] ?? '');
      if (path?.scheme == 'cloudreve' &&
          ['share', 'shared_with_me'].contains(path!.host)) {
        final auth = path.userInfo.split(':');
        id = Uri.decodeComponent(auth.first);
        secret = auth.length > 1
            ? Uri.decodeComponent(auth.sublist(1).join(':'))
            : null;
      }
    }
    if (id == null || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id)) {
      throw const FormatException('未找到有效的分享 ID');
    }
    secret = password?.trim().isNotEmpty == true ? password!.trim() : secret;
    secret ??= RegExp(r'(?:提取码|密码)\s*[:：]\s*([A-Za-z0-9]+)')
        .firstMatch(text)
        ?.group(1);
    return ShareLink(id: id, password: secret ?? '');
  }
}

class SharedContent {
  const SharedContent({
    required this.link,
    required this.name,
    required this.folder,
    required this.ownerId,
    required this.files,
  });
  final ShareLink link;
  final String name;
  final bool folder;
  final String ownerId;
  final List<MFile> files;
}
