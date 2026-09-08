import 'package:cloudreve/config/app_config.dart';
import 'package:cloudreve/entity/login_result.dart';
import 'package:cloudreve/entity/m_file.dart';
import 'package:cloudreve/state/app_state.dart';
import 'package:cloudreve/state/page_transition_provider.dart';
import 'package:cloudreve/state/sound_effect_provider.dart';
import 'package:cloudreve/theme/app_theme.dart';
import 'package:cloudreve/utils/cloudreve_repository.dart';
import 'package:cloudreve/utils/dark_mode_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

class AppSettingsPage extends StatelessWidget {
  const AppSettingsPage({super.key, required this.userData});

  final UserData userData;

  @override
  Widget build(BuildContext context) {
    final darkMode = context.watch<DarkModeProvider>().darkMode;
    final pageTransitions = context.watch<PageTransitionProvider>();
    final soundEffects = context.watch<SoundEffectProvider>();

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        leadingWidth: 68,
        leading: Center(
          child: _CircleIconButton(
            icon: Icons.arrow_back_ios_new_rounded,
            tooltip: '返回',
            onPressed: () => Navigator.pop(context),
          ),
        ),
        title: const Text('设置'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 36),
        children: [
          const _SectionTitle(title: '账户安全'),
          const SizedBox(height: 10),
          CloudrevePanel(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: _SettingsTile(
              key: const Key('app-settings-password'),
              icon: Icons.lock_reset_rounded,
              iconColor: CloudreveColors.primary,
              title: '修改密码',
              onTap: () => _showPasswordSheet(context),
            ),
          ),
          const SizedBox(height: 24),
          const _SectionTitle(title: '账户状态'),
          const SizedBox(height: 10),
          CloudrevePanel(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Column(
              children: [
                _InformationRow(
                  title: '注册时间',
                  value: getFormatDate(userData.createdAt),
                ),
                const _InsetDivider(),
                const _InformationRow(title: '安全状态', value: '已登录保护'),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const _SectionTitle(title: '应用偏好'),
          const SizedBox(height: 10),
          CloudrevePanel(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Column(
              children: [
                _SettingsTile(
                  icon: Icons.palette_outlined,
                  iconColor: const Color(0xFF7A5AF8),
                  title: '外观',
                  value: _darkModeLabel(darkMode),
                  onTap: () => _showAppearanceSheet(context, darkMode),
                ),
                const _InsetDivider(),
                _SettingsTile(
                  key: const Key('page-transition-settings'),
                  icon: Icons.animation_rounded,
                  iconColor: CloudreveColors.warning,
                  title: '页面动画',
                  value: pageTransitions.style.label,
                  onTap: () =>
                      _showPageTransitionSheet(context, pageTransitions.style),
                ),
                const _InsetDivider(),
                _SettingsTile(
                  icon: Icons.volume_up_outlined,
                  iconColor: CloudreveColors.success,
                  title: '界面音效',
                  trailing: Switch(
                    key: const Key('sound-effects-switch'),
                    value: soundEffects.enabled,
                    onChanged: soundEffects.setEnabled,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const _SectionTitle(title: '关于'),
          const SizedBox(height: 10),
          CloudrevePanel(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: _SettingsTile(
              key: const Key('app-information'),
              icon: Icons.info_outline_rounded,
              iconColor: CloudreveColors.warning,
              title: '应用信息',
              onTap: () {
                Navigator.of(context).push(
                  cloudrevePageRoute<void>(
                    context,
                    builder: (_) => const AppInformationPage(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static String _darkModeLabel(DarkMode mode) => switch (mode) {
    DarkMode.auto => '跟随系统',
    DarkMode.close => '浅色',
    DarkMode.open => '深色',
  };

  Future<void> _showPasswordSheet(BuildContext context) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _ChangePasswordSheet(),
    );
    if (changed == true && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('密码修改成功，请使用新密码重新登录')));
      await context.read<AppState>().logout();
    }
  }

  Future<void> _showAppearanceSheet(
    BuildContext context,
    DarkMode selected,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('外观', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            for (final mode in DarkMode.values)
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                leading: Icon(
                  mode == selected
                      ? Icons.check_circle_rounded
                      : Icons.circle_outlined,
                  color: mode == selected
                      ? CloudreveColors.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                title: Text(_darkModeLabel(mode)),
                onTap: () {
                  context.read<DarkModeProvider>().changeMode(mode);
                  Navigator.pop(sheetContext);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showPageTransitionSheet(
    BuildContext context,
    PageTransitionStyle selected,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('页面动画', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            for (final style in PageTransitionStyle.values)
              ListTile(
                key: Key('page-transition-style-${style.name}'),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                leading: Icon(
                  style == selected
                      ? Icons.check_circle_rounded
                      : Icons.circle_outlined,
                  color: style == selected
                      ? CloudreveColors.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                title: Text(style.label),
                onTap: () {
                  context.read<PageTransitionProvider>().setStyle(style);
                  Navigator.pop(sheetContext);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _ChangePasswordSheet extends StatefulWidget {
  const _ChangePasswordSheet();

  @override
  State<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<_ChangePasswordSheet> {
  final _formKey = GlobalKey<FormState>();
  final _currentPassword = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();

  bool _showCurrentPassword = false;
  bool _showNewPassword = false;
  bool _submitting = false;

  @override
  void dispose() {
    _currentPassword.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('修改密码', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(
                '修改后请使用新密码登录。应用不会保存你输入的密码。',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              TextFormField(
                key: const Key('current-password-field'),
                controller: _currentPassword,
                obscureText: !_showCurrentPassword,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: '原密码',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    tooltip: _showCurrentPassword ? '隐藏密码' : '显示密码',
                    onPressed: () => setState(
                      () => _showCurrentPassword = !_showCurrentPassword,
                    ),
                    icon: Icon(
                      _showCurrentPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) return '请输入当前密码';
                  if (value.length < 4) return '当前密码至少需要 4 个字符';
                  if (value.length > 128) return '当前密码不能超过 128 个字符';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('new-password-field'),
                controller: _newPassword,
                obscureText: !_showNewPassword,
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: '新密码',
                  helperText: '6–128 个字符',
                  prefixIcon: const Icon(Icons.password_rounded),
                  suffixIcon: IconButton(
                    tooltip: _showNewPassword ? '隐藏密码' : '显示密码',
                    onPressed: () =>
                        setState(() => _showNewPassword = !_showNewPassword),
                    icon: Icon(
                      _showNewPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) return '请输入新密码';
                  if (value.length < 6) return '新密码至少需要 6 个字符';
                  if (value.length > 128) return '新密码不能超过 128 个字符';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('confirm-password-field'),
                controller: _confirmPassword,
                obscureText: !_showNewPassword,
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  labelText: '重复新密码',
                  prefixIcon: Icon(Icons.verified_user_outlined),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) return '请再次输入新密码';
                  if (value != _newPassword.text) return '两次输入的新密码不一致';
                  return null;
                },
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('submit-password-change'),
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Text('保存新密码'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (_submitting || !(_formKey.currentState?.validate() ?? false)) return;
    TextInput.finishAutofillContext(shouldSave: false);
    setState(() => _submitting = true);
    try {
      final response = await CloudreveRepository.updatePassword(
        currentPassword: _currentPassword.text,
        newPassword: _newPassword.text,
      );
      if (!mounted) return;
      if (response?.code == 0) {
        Navigator.pop(context, true);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            response?.code == 40069 ? '当前密码不正确' : response?.msg ?? '密码修改失败',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_friendlyError(error))));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _friendlyError(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map) {
        final message = data['msg'] ?? data['error'];
        if (message != null && message.toString().trim().isNotEmpty) {
          return message.toString();
        }
      }
      if (error.response?.statusCode != null) {
        return '服务器返回 HTTP ${error.response!.statusCode}';
      }
      return error.message ?? '网络连接异常';
    }
    return '密码修改失败，请稍后重试';
  }
}

class AppInformationPage extends StatefulWidget {
  const AppInformationPage({super.key});

  @override
  State<AppInformationPage> createState() => _AppInformationPageState();
}

class _AppInformationPageState extends State<AppInformationPage> {
  late final Future<PackageInfo?> _packageInfo = _loadPackageInfo();

  Future<PackageInfo?> _loadPackageInfo() async {
    try {
      return await PackageInfo.fromPlatform();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo?>(
      future: _packageInfo,
      builder: (context, snapshot) {
        final info = snapshot.data;
        final appName = info?.appName.trim().isNotEmpty == true
            ? info!.appName
            : AppConfig.appName;
        final version = info == null
            ? '读取中'
            : '${info.version} (${info.buildNumber})';
        final packageName = info?.packageName ?? AppConfig.applicationId;
        return Scaffold(
          appBar: AppBar(
            toolbarHeight: 68,
            leadingWidth: 68,
            leading: Center(
              child: _CircleIconButton(
                icon: Icons.arrow_back_ios_new_rounded,
                tooltip: '返回',
                onPressed: () => Navigator.pop(context),
              ),
            ),
            title: const Text('应用信息'),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 36),
            children: [
              CloudrevePanel(
                padding: const EdgeInsets.all(22),
                child: Column(
                  children: [
                    Container(
                      width: 86,
                      height: 86,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: CloudreveColors.primarySoft,
                        borderRadius: BorderRadius.circular(26),
                      ),
                      child: Image.asset('assets/logo.png'),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      appName,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      AppConfig.description,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const _SectionTitle(title: '版本信息'),
              const SizedBox(height: 10),
              CloudrevePanel(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Column(
                  children: [
                    _InformationRow(title: '版本', value: version),
                    const _InsetDivider(),
                    _InformationRow(title: '软件包', value: packageName),
                    const _InsetDivider(),
                    const _InformationRow(
                      title: '客户端',
                      value: 'Flutter / Android',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              CloudrevePanel(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: _SettingsTile(
                  icon: Icons.description_outlined,
                  iconColor: CloudreveColors.primary,
                  title: '开源许可证',
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: appName,
                    applicationVersion: version,
                    applicationLegalese: 'Cloudreve 非官方客户端',
                    applicationIcon: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Image.asset('assets/logo.png', width: 60),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
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
    indent: 58,
    color: Theme.of(context).dividerColor.withValues(alpha: 0.6),
  );
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    this.value,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return InkWell(
      enableFeedback: context.watch<SoundEffectProvider?>()?.enabled ?? true,
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: iconColor, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (value != null)
              Text(value!, style: TextStyle(color: muted, fontSize: 13)),
            ?trailing,
            if (onTap != null) ...[
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded, color: muted, size: 20),
            ],
          ],
        ),
      ),
    );
  }
}

class _InformationRow extends StatelessWidget {
  const _InformationRow({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
        ),
      ],
    ),
  );
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    enableFeedback: context.watch<SoundEffectProvider?>()?.enabled ?? true,
    onPressed: onPressed,
    icon: Icon(icon),
    style: IconButton.styleFrom(
      backgroundColor: Theme.of(context).colorScheme.surface,
      foregroundColor: Theme.of(context).colorScheme.onSurface,
      fixedSize: const Size(42, 42),
      padding: EdgeInsets.zero,
      shape: const CircleBorder(),
    ),
  );
}
