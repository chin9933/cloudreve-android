import 'package:cloudreve/component/file_visual.dart';
import 'package:cloudreve/entity/login_result.dart';
import 'package:cloudreve/entity/m_file.dart';
import 'package:cloudreve/entity/storage_summary.dart';
import 'package:cloudreve/state/sound_effect_provider.dart';
import 'package:cloudreve/theme/app_theme.dart';
import 'package:cloudreve/utils/cloudreve_repository.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class DashboardHome extends StatelessWidget {
  const DashboardHome({
    super.key,
    required this.userData,
    required this.storage,
    required this.fileResp,
    required this.onRefresh,
    required this.onOpenFiles,
    required this.onUpload,
    required this.onOpenShares,
  });

  final UserData userData;
  final Storage storage;
  final Future<FileListing> fileResp;
  final Future<void> Function() onRefresh;
  final VoidCallback onOpenFiles;
  final VoidCallback onUpload;
  final VoidCallback onOpenShares;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).brightness == Brightness.dark
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : CloudreveColors.muted;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          18,
          4,
          18,
          CloudreveTheme.pageBottomInset,
        ),
        children: [
          Text(
            '你好，${userData.nickname}',
            style: TextStyle(
              color: muted,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          _buildStorageCard(context),
          const SizedBox(height: 16),
          _buildQuickActions(context),
          const SizedBox(height: 24),
          Row(
            children: [
              const Expanded(
                child: Text(
                  '最近文件',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              TextButton.icon(
                onPressed: onOpenFiles,
                iconAlignment: IconAlignment.end,
                icon: const Icon(Icons.arrow_forward_ios_rounded, size: 13),
                label: const Text('查看全部'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FutureBuilder<FileListing>(
            future: fileResp,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const CloudrevePanel(
                  child: SizedBox(
                    height: 150,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                );
              }
              if (snapshot.hasError) {
                return CloudrevePanel(
                  child: _EmptyRecent(
                    icon: Icons.cloud_off_outlined,
                    title: '最近文件加载失败',
                    actionLabel: '重新加载',
                    onAction: onRefresh,
                  ),
                );
              }
              final files = List<MFile>.from(
                snapshot.data?.files ?? const <MFile>[],
              )..sort((a, b) => b.date.compareTo(a.date));
              if (files.isEmpty) {
                return CloudrevePanel(
                  child: _EmptyRecent(
                    icon: Icons.cloud_upload_outlined,
                    title: '还没有文件',
                    actionLabel: '上传第一个文件',
                    onAction: onUpload,
                  ),
                );
              }
              return CloudrevePanel(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  children: files.take(5).map((file) {
                    return InkWell(
                      enableFeedback:
                          context.watch<SoundEffectProvider?>()?.enabled ??
                          true,
                      onTap: onOpenFiles,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                        child: Row(
                          children: [
                            FileIconBadge(file: file, size: 44),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    file.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    file.type == 'dir'
                                        ? '文件夹 · ${file.getFormatDate()}'
                                        : '${file.displaySize} · ${file.getFormatDate()}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.more_horiz_rounded, color: muted),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStorageCard(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final total = storage.total;
    final progress = total <= 0 ? 0.0 : (storage.used / total).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const [Color(0xFF1B2B43), Color(0xFF17243A)]
              : const [Color(0xFFFFFFFF), Color(0xFFEAF3FF)],
        ),
        borderRadius: BorderRadius.circular(CloudreveTheme.cardRadius),
        border: Border.all(
          color: dark ? const Color(0xFF30435F) : const Color(0xFFDDEAFF),
        ),
        boxShadow: dark
            ? null
            : const [
                BoxShadow(
                  color: Color(0x142478FF),
                  blurRadius: 26,
                  offset: Offset(0, 12),
                ),
              ],
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF64B5FF), CloudreveColors.primary],
              ),
              borderRadius: BorderRadius.circular(19),
            ),
            child: const Icon(
              Icons.storage_rounded,
              color: Colors.white,
              size: 34,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '我的空间',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '已使用 ${MFile.getFileSize(storage.used.toDouble())} / ${MFile.getFileSize(storage.total.toDouble())}',
                  style: TextStyle(
                    color: dark
                        ? Theme.of(context).colorScheme.onSurfaceVariant
                        : CloudreveColors.muted,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 7,
                    backgroundColor: dark
                        ? const Color(0xFF32445F)
                        : const Color(0xFFDCE7F6),
                    color: CloudreveColors.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${(progress * 100).toStringAsFixed(0)}%',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return CloudrevePanel(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      child: Row(
        children: [
          _QuickAction(
            icon: Icons.folder_rounded,
            label: '我的文件',
            foreground: CloudreveColors.primary,
            background: CloudreveColors.primarySoft,
            onTap: onOpenFiles,
          ),
          _QuickAction(
            icon: Icons.schedule_rounded,
            label: '最近上传',
            foreground: CloudreveColors.success,
            background: const Color(0xFFE7F8EF),
            onTap: onOpenFiles,
          ),
          _QuickAction(
            icon: Icons.star_rounded,
            label: '收藏夹',
            foreground: CloudreveColors.warning,
            background: const Color(0xFFFFF1E3),
            onTap: () {
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('收藏夹将在后续版本接入')));
            },
          ),
          _QuickAction(
            icon: Icons.link_rounded,
            label: '分享链接',
            foreground: const Color(0xFF8B5CF6),
            background: const Color(0xFFF0E9FF),
            onTap: onOpenShares,
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.foreground,
    required this.background,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color foreground;
  final Color background;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        enableFeedback: context.watch<SoundEffectProvider?>()?.enabled ?? true,
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Column(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? foreground.withValues(alpha: 0.16)
                      : background,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, color: foreground, size: 26),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyRecent extends StatelessWidget {
  const _EmptyRecent({
    required this.icon,
    required this.title,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 22),
      child: Column(
        children: [
          Icon(icon, size: 44, color: CloudreveColors.muted),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          TextButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}
