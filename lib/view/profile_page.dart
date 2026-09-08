import 'dart:io';
import 'dart:typed_data';

import 'package:cloudreve/component/rename_nick_dialog.dart';
import 'package:cloudreve/entity/login_result.dart';
import 'package:cloudreve/state/sound_effect_provider.dart';
import 'package:cloudreve/theme/app_theme.dart';
import 'package:cloudreve/utils/cache_util.dart';
import 'package:cloudreve/utils/cloudreve_repository.dart';
import 'package:cloudreve/utils/global_setting.dart';
import 'package:cloudreve/view/app_settings_page.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class Setting extends StatefulWidget {
  const Setting({super.key, required this.userData, required this.refresh});

  final UserData userData;
  final void Function(bool) refresh;

  @override
  State<Setting> createState() => _SettingState();
}

class _SettingState extends State<Setting> {
  UserData get userData => widget.userData;
  void Function(bool) get refresh => widget.refresh;
  late Future<Uint8List> _avatarFuture;

  @override
  void initState() {
    super.initState();
    _avatarFuture = _avatar();
  }

  @override
  void didUpdateWidget(covariant Setting oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userData.id != userData.id ||
        oldWidget.userData.avatar != userData.avatar) {
      _avatarFuture = _avatar();
    }
  }

  Future<Uint8List> _avatar() =>
      CacheUtil.cachedBytes('avatar', userData.id, () async {
        final response = await CloudreveRepository.fetchAvatar(
          userId: userData.id,
        );
        final bytes = response.data;
        if (bytes == null || bytes.isEmpty) throw StateError('头像不可用');
        return bytes;
      });

  Future<void> _showAvatarOptions(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('修改头像', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              _SettingsRow(
                icon: Icons.photo_library_rounded,
                iconColor: CloudreveColors.primary,
                title: '从相册或文件上传',
                onTap: () => _uploadAvatar(context, sheetContext),
              ),
              const SizedBox(height: 10),
              _SettingsRow(
                icon: Icons.fingerprint_rounded,
                iconColor: CloudreveColors.warning,
                title: '使用 Gravatar 头像',
                onTap: () => _useGravatar(context, sheetContext),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _uploadAvatar(
    BuildContext context,
    BuildContext sheetContext,
  ) async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result == null ||
        result.files.isEmpty ||
        result.files.first.path == null) {
      return;
    }
    final bytes = await File(result.files.first.path!).readAsBytes();
    final response = await CloudreveRepository.uploadAvatarBytes(bytes);
    if (sheetContext.mounted) Navigator.pop(sheetContext);
    if (!context.mounted) return;
    final success = response?.code == 0;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(success ? '头像已更新' : response?.msg ?? '上传失败')),
    );
    if (success) {
      await CacheUtil.clear(cacheAvatarPath);
      if (mounted) {
        setState(() {
          _avatarFuture = _avatar();
        });
      }
      refresh(true);
    }
  }

  Future<void> _useGravatar(
    BuildContext context,
    BuildContext sheetContext,
  ) async {
    final response = await CloudreveRepository.setAvatarFromGravatar();
    if (sheetContext.mounted) Navigator.pop(sheetContext);
    if (!context.mounted) return;
    final success = response?.code == 0;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(success ? '头像已更新' : response?.msg ?? '设置失败')),
    );
    if (success) {
      await CacheUtil.clear(cacheAvatarPath);
      if (mounted) {
        setState(() {
          _avatarFuture = _avatar();
        });
      }
      refresh(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final groupName = userData.group?.name.trim();
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        18,
        8,
        18,
        CloudreveTheme.pageBottomInset,
      ),
      children: [
        CloudrevePanel(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => _showAvatarOptions(context),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    FutureBuilder<Uint8List>(
                      future: _avatarFuture,
                      builder: (context, snapshot) => Container(
                        width: 74,
                        height: 74,
                        decoration: BoxDecoration(
                          color: CloudreveColors.primarySoft,
                          shape: BoxShape.circle,
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x1F2478FF),
                              blurRadius: 20,
                              offset: Offset(0, 8),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: snapshot.hasData
                            ? Image.memory(
                                snapshot.data!,
                                fit: BoxFit.cover,
                                alignment: Alignment.center,
                                filterQuality: FilterQuality.medium,
                                errorBuilder: (_, _, _) => const Icon(
                                  Icons.person_rounded,
                                  color: CloudreveColors.primary,
                                  size: 38,
                                ),
                              )
                            : snapshot.hasError
                            ? const Icon(
                                Icons.person_rounded,
                                color: CloudreveColors.primary,
                                size: 38,
                              )
                            : const Center(
                                child: SizedBox.square(
                                  dimension: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                  ),
                                ),
                              ),
                      ),
                    ),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: const BoxDecoration(
                          color: CloudreveColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.edit_rounded,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            userData.nickname,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.verified_rounded,
                          size: 18,
                          color: CloudreveColors.primary,
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      userData.userName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: CloudreveColors.muted),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: CloudreveColors.primarySoft,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        groupName == null || groupName.isEmpty
                            ? 'Cloudreve 用户'
                            : groupName,
                        style: const TextStyle(
                          color: CloudreveColors.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const _SectionTitle(title: '账户信息'),
        const SizedBox(height: 10),
        CloudrevePanel(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            children: [
              _SettingsRow(
                icon: Icons.badge_outlined,
                iconColor: CloudreveColors.primary,
                title: '用户 ID',
                value: userData.id,
                alignWithProfile: true,
              ),
              const _InsetDivider(),
              _SettingsRow(
                icon: Icons.account_circle_outlined,
                iconColor: CloudreveColors.success,
                title: '昵称',
                value: userData.nickname,
                alignWithProfile: true,
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) => RenameNickDialog(
                    nick: userData.nickname,
                    refresh: refresh,
                  ),
                ),
              ),
              const _InsetDivider(),
              _SettingsRow(
                icon: Icons.mail_outline_rounded,
                iconColor: CloudreveColors.warning,
                title: '邮箱',
                value: userData.userName,
                alignWithProfile: true,
              ),
              const _InsetDivider(),
              _SettingsRow(
                icon: Icons.groups_2_outlined,
                iconColor: const Color(0xFF7A5AF8),
                title: '用户组',
                value: groupName == null || groupName.isEmpty
                    ? '默认'
                    : groupName,
                alignWithProfile: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const _SectionTitle(title: '设置'),
        const SizedBox(height: 10),
        CloudrevePanel(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: _SettingsRow(
            icon: Icons.settings_rounded,
            iconColor: CloudreveColors.primary,
            title: '应用设置',
            onTap: () => Navigator.of(context).push(
              cloudrevePageRoute<void>(
                context,
                builder: (_) => AppSettingsPage(userData: userData),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Text(
    title,
    style: Theme.of(context).textTheme.titleMedium
        ?.copyWith(fontWeight: FontWeight.w800),
  );
}

class _InsetDivider extends StatelessWidget {
  const _InsetDivider();

  @override
  Widget build(BuildContext context) => Divider(
    height: 1,
    indent: 104,
    endIndent: 12,
    color: Theme.of(context).dividerColor.withValues(alpha: 0.6),
  );
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.value,
    this.onTap,
    this.alignWithProfile = false,
  }) : assert(!alignWithProfile || value != null);

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? value;
  final VoidCallback? onTap;
  final bool alignWithProfile;

  @override
  Widget build(BuildContext context) {
    final iconBadge = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Icon(icon, color: iconColor, size: 21),
    );
    final titleBlock = Text(
      title,
      style: const TextStyle(fontWeight: FontWeight.w700),
    );

    return InkWell(
      enableFeedback: context.watch<SoundEffectProvider?>()?.enabled ?? true,
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: alignWithProfile ? 12 : 10,
          vertical: 12,
        ),
        child: Row(
          children: [
            if (alignWithProfile)
              SizedBox(
                width: 74,
                child: Align(alignment: Alignment.centerLeft, child: iconBadge),
              )
            else
              iconBadge,
            SizedBox(width: alignWithProfile ? 18 : 12),
            if (alignWithProfile) ...[
              SizedBox(width: 60, child: titleBlock),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  value!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.start,
                  style: const TextStyle(
                    color: CloudreveColors.muted,
                    fontSize: 13,
                  ),
                ),
              ),
              if (onTap != null)
                const SizedBox(
                  width: 26,
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: CloudreveColors.muted,
                    size: 20,
                  ),
                ),
            ] else ...[
              Expanded(child: titleBlock),
              if (value != null)
                Flexible(
                  child: Text(
                    value!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                      color: CloudreveColors.muted,
                      fontSize: 13,
                    ),
                  ),
                ),
              if (onTap != null) ...[
                const SizedBox(width: 6),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: CloudreveColors.muted,
                  size: 20,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
