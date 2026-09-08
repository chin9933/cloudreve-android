import 'dart:typed_data';

import 'package:cloudreve/config/app_config.dart';
import 'package:cloudreve/entity/login_result.dart';
import 'package:cloudreve/entity/m_file.dart';
import 'package:cloudreve/entity/storage_summary.dart';
import 'package:cloudreve/state/app_state.dart';
import 'package:cloudreve/theme/app_theme.dart';
import 'package:cloudreve/utils/cache_util.dart';
import 'package:cloudreve/utils/cloudreve_repository.dart';
import 'package:cloudreve/view/web_dav.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

class MDrawer extends StatelessWidget {
  const MDrawer({super.key, required this.userData, required this.storage});

  final UserData userData;
  final Storage storage;

  Future<Uint8List> _avatar() =>
      CacheUtil.cachedBytes('avatar', userData.id, () async {
        final response = await CloudreveRepository.fetchAvatar(
          userId: userData.id,
        );
        final bytes = response.data;
        if (bytes == null || bytes.isEmpty) throw StateError('头像不可用');
        return bytes;
      });

  @override
  Widget build(BuildContext context) {
    final total = storage.total.toDouble();
    final progress = total <= 0
        ? 0.0
        : (storage.used.toDouble() / total).clamp(0.0, 1.0);
    return Drawer(
      width: MediaQuery.sizeOf(context).width * 0.84,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(30)),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 24),
          children: [
            Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: CloudreveColors.primarySoft,
                    shape: BoxShape.circle,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: FutureBuilder<Uint8List>(
                    future: _avatar(),
                    builder: (_, snapshot) => snapshot.hasData
                        ? Image.memory(
                            snapshot.data!,
                            fit: BoxFit.cover,
                            alignment: Alignment.center,
                            filterQuality: FilterQuality.medium,
                            errorBuilder: (_, _, _) => const Icon(
                              Icons.person_rounded,
                              color: CloudreveColors.primary,
                              size: 30,
                            ),
                          )
                        : snapshot.hasError
                        ? const Icon(
                            Icons.person_rounded,
                            color: CloudreveColors.primary,
                            size: 30,
                          )
                        : const Center(
                            child: SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        userData.nickname,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        userData.userName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: CloudreveColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2478FF), Color(0xFF6BA7FF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(22),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x332478FF),
                    blurRadius: 22,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.cloud_rounded, color: Colors.white),
                      SizedBox(width: 9),
                      Text(
                        '我的空间',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 15),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 7,
                      backgroundColor: Colors.white24,
                      valueColor: const AlwaysStoppedAnimation(Colors.white),
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    '已用 ${MFile.getFileSize(storage.used.toDouble())} / ${MFile.getFileSize(storage.total.toDouble())}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            _DrawerItem(
              icon: Icons.share_outlined,
              title: '我的分享',
              onTap: () {
                Navigator.pop(context);
                context.go('/home/shares');
              },
            ),
            _DrawerItem(
              icon: Icons.devices_other_rounded,
              title: 'WebDAV',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  cloudrevePageRoute<void>(context, builder: (_) => WebDav()),
                );
              },
            ),
            _DrawerItem(
              icon: Icons.cleaning_services_outlined,
              title: '清除缓存',
              onTap: () async {
                await CacheUtil.clear();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('缓存已清理')));
              },
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Divider(),
            ),
            _DrawerItem(
              icon: Icons.logout_rounded,
              iconColor: CloudreveColors.danger,
              title: '退出登录',
              titleColor: CloudreveColors.danger,
              onTap: () async {
                final appState = context.read<AppState>();
                Navigator.of(context).pop();
                await appState.logout();
              },
            ),
            const SizedBox(height: 12),
            const Center(
              child: Text(
                AppConfig.appName,
                style: TextStyle(color: CloudreveColors.muted, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.icon,
    required this.title,
    required this.onTap,
    this.iconColor = CloudreveColors.primary,
    this.titleColor,
  });

  final IconData icon;
  final String title;
  final Color iconColor;
  final Color? titleColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(icon, color: iconColor, size: 21),
      ),
      title: Text(
        title,
        style: TextStyle(color: titleColor, fontWeight: FontWeight.w700),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: CloudreveColors.muted,
      ),
    ),
  );
}
