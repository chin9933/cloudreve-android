import 'package:cloudreve/entity/m_file.dart';
import 'package:cloudreve/entity/share_data.dart';
import 'package:cloudreve/theme/app_theme.dart';
import 'package:cloudreve/utils/cloudreve_repository.dart';
import 'package:cloudreve/utils/http_util.dart';
import 'package:cloudreve/view/files_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class Share extends StatefulWidget {
  const Share({super.key, required this.orderBy});

  final ShareOrderBy orderBy;

  @override
  State<Share> createState() => _ShareState();
}

class _ShareState extends State<Share> {
  late Future<ShareData> _shareFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant Share oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.orderBy != widget.orderBy) {
      _reload();
    }
  }

  void _reload() {
    _shareFuture = _getShare();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        setState(_reload);
        await _shareFuture;
      },
      child: FutureBuilder<ShareData>(
        future: _shareFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ShareStateView(
              icon: Icons.cloud_off_rounded,
              title: '分享加载失败',
              description: '下拉或点击按钮重新尝试',
              buttonText: '重新加载',
              onTap: () => setState(_reload),
            );
          }
          final items = snapshot.data?.items ?? const <ShareItems>[];
          if (items.isEmpty) {
            return _ShareStateView(
              icon: Icons.link_off_rounded,
              title: '还没有分享链接',
              description: '在文件的更多操作中即可创建分享',
              buttonText: '刷新',
              onTap: () => setState(_reload),
            );
          }
          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              18,
              8,
              18,
              CloudreveTheme.pageBottomInset,
            ),
            itemCount: items.length + 1,
            separatorBuilder: (_, index) =>
                SizedBox(height: index == 0 ? 10 : 12),
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(2, 2, 2, 4),
                  child: Row(
                    children: [
                      Text(
                        '${items.length} 个分享',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const Spacer(),
                      Text(
                        widget.orderBy.name,
                        style: const TextStyle(
                          color: CloudreveColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                );
              }
              return _ShareCard(
                item: items[index - 1],
                onOpen: () => _open(items[index - 1]),
                onCopy: () => _copyLink(items[index - 1]),
                onPassword: items[index - 1].password.isEmpty
                    ? null
                    : () => _showPassword(items[index - 1]),
                onDelete: () => _delete(items[index - 1]),
              );
            },
          );
        },
      ),
    );
  }

  Future<ShareData> _getShare() async {
    final result = await CloudreveRepository.fetchMyShares(
      pageSize: 50,
      orderBy: widget.orderBy.orderBy,
      orderDirection: widget.orderBy.order,
    );
    return ShareData.fromApi(result.shares, pagination: result.pagination);
  }

  String _shareUrl(ShareItems item) {
    final baseUrl = HttpUtil.dio.options.baseUrl;
    final trimmed = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return item.url ?? '$trimmed/s/${item.key}';
  }

  Future<void> _open(ShareItems item) async {
    final launched = await launchUrl(
      Uri.parse(_shareUrl(item)),
      mode: LaunchMode.externalApplication,
    );
    if (!launched && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('无法打开分享链接')));
    }
  }

  void _copyLink(ShareItems item) {
    Clipboard.setData(ClipboardData(text: _shareUrl(item)));
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('分享链接已复制')));
  }

  Future<void> _showPassword(ShareItems item) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('访问密码'),
        content: SelectableText(
          item.password,
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(letterSpacing: 3, fontWeight: FontWeight.w800),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('关闭'),
          ),
          FilledButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: item.password));
              Navigator.pop(dialogContext);
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('密码已复制')));
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('复制'),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(ShareItems item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('取消分享？'),
        content: Text('“${item.source.name}”的公开链接将立即失效。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('保留'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: CloudreveColors.danger,
            ),
            child: const Text('取消分享'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final success = await CloudreveRepository.deleteShare(item.key);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(success ? '分享已取消' : '操作失败，请重试')));
    if (success) {
      setState(_reload);
    }
  }
}

class _ShareCard extends StatelessWidget {
  const _ShareCard({
    required this.item,
    required this.onOpen,
    required this.onCopy,
    required this.onDelete,
    this.onPassword,
  });

  final ShareItems item;
  final VoidCallback onOpen;
  final VoidCallback onCopy;
  final VoidCallback? onPassword;
  final VoidCallback onDelete;

  (IconData, Color) _visual() {
    if (item.isDir) return (Icons.folder_rounded, const Color(0xFF2E8CFF));
    final name = item.source.name;
    if (imageRex.hasMatch(name)) {
      return (Icons.image_rounded, const Color(0xFF8D63E9));
    }
    if (pdfRex.hasMatch(name)) {
      return (Icons.picture_as_pdf_rounded, const Color(0xFFEF4444));
    }
    if (zipRegex.hasMatch(name)) {
      return (Icons.archive_rounded, const Color(0xFFFFA21A));
    }
    if (wordRegex.hasMatch(name)) {
      return (Icons.description_rounded, const Color(0xFF2478FF));
    }
    if (apkRegex.hasMatch(name)) {
      return (Icons.android_rounded, const Color(0xFF22B573));
    }
    return (Icons.insert_drive_file_rounded, CloudreveColors.muted);
  }

  @override
  Widget build(BuildContext context) {
    final visual = _visual();
    return CloudrevePanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: visual.$2.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(visual.$1, color: visual.$2, size: 28),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.source.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Text(
                          getFormatDate(item.createDate),
                          style: const TextStyle(
                            color: CloudreveColors.muted,
                            fontSize: 12,
                          ),
                        ),
                        if (item.expired) ...[
                          const SizedBox(width: 8),
                          const _StatusBadge(text: '已失效', danger: true),
                        ] else ...[
                          const SizedBox(width: 8),
                          const _StatusBadge(text: '有效'),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _Metric(icon: Icons.visibility_outlined, value: '${item.views}'),
              const SizedBox(width: 16),
              _Metric(
                icon: Icons.download_outlined,
                value: '${item.downloads}',
              ),
              const Spacer(),
              _SmallAction(icon: Icons.open_in_new_rounded, onTap: onOpen),
              _SmallAction(icon: Icons.link_rounded, onTap: onCopy),
              if (onPassword != null)
                _SmallAction(icon: Icons.key_rounded, onTap: onPassword!),
              _SmallAction(
                icon: Icons.delete_outline_rounded,
                color: CloudreveColors.danger,
                onTap: onDelete,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.text, this.danger = false});

  final String text;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? CloudreveColors.danger : CloudreveColors.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, color: CloudreveColors.muted, size: 16),
      const SizedBox(width: 4),
      Text(
        value,
        style: const TextStyle(color: CloudreveColors.muted, fontSize: 12),
      ),
    ],
  );
}

class _SmallAction extends StatelessWidget {
  const _SmallAction({required this.icon, required this.onTap, this.color});

  final IconData icon;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onTap,
    icon: Icon(icon, size: 20),
    color: color ?? CloudreveColors.primary,
    visualDensity: VisualDensity.compact,
    style: IconButton.styleFrom(
      backgroundColor: (color ?? CloudreveColors.primary).withValues(
        alpha: 0.08,
      ),
    ),
  );
}

class _ShareStateView extends StatelessWidget {
  const _ShareStateView({
    required this.icon,
    required this.title,
    required this.description,
    required this.buttonText,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final String buttonText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        30,
        0,
        30,
        CloudreveTheme.pageBottomInset,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: constraints.maxHeight > CloudreveTheme.pageBottomInset
              ? constraints.maxHeight - CloudreveTheme.pageBottomInset
              : 0,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 70,
                color: CloudreveColors.primary.withValues(alpha: 0.6),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                description,
                textAlign: TextAlign.center,
                style: const TextStyle(color: CloudreveColors.muted),
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: onTap,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(buttonText),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class ShareOrderBy {
  const ShareOrderBy(this.order, this.orderBy, this.name);

  final String order;
  final String orderBy;
  final String name;
}

const List<ShareOrderBy> shareOrderByOptions = <ShareOrderBy>[
  ShareOrderBy('desc', 'id', '最近创建'),
  ShareOrderBy('asc', 'id', '最早创建'),
  ShareOrderBy('desc', 'downloads', '下载最多'),
  ShareOrderBy('asc', 'downloads', '下载最少'),
  ShareOrderBy('desc', 'views', '浏览最多'),
  ShareOrderBy('asc', 'views', '浏览最少'),
];
