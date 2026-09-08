import 'package:cloudreve/component/add_server_dialog.dart';
import 'package:cloudreve/config/app_config.dart';
import 'package:cloudreve/entity/login_result.dart';
import 'package:cloudreve/entity/storage_summary.dart';
import 'package:cloudreve/state/app_state.dart';
import 'package:cloudreve/state/sound_effect_provider.dart';
import 'package:cloudreve/theme/app_theme.dart';
import 'package:cloudreve/utils/cloudreve_repository.dart';
import 'package:cloudreve/utils/global_setting.dart';
import 'package:cloudreve/utils/http_util.dart';
import 'package:cloudreve/utils/secure_session_store.dart';
import 'package:cloudreve/utils/server_preferences.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginHome extends StatefulWidget {
  const LoginHome({super.key});

  @override
  State<LoginHome> createState() => _LoginHomeState();
}

class _LoginHomeState extends State<LoginHome> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  final List<String> _urls = <String>[];
  int _selectedUrlIndex = -1;
  bool _loadingServers = true;
  bool _rememberSelected = true;
  bool _obscurePassword = true;
  bool _submitting = false;

  String get _selectedUrl =>
      _selectedUrlIndex >= 0 && _selectedUrlIndex < _urls.length
      ? _urls[_selectedUrlIndex]
      : '';

  @override
  void initState() {
    super.initState();
    _initUrls();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _initUrls() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = ServerPreferences.read(
      prefs,
      currentUrl: HttpUtil.dio.options.baseUrl,
      defaultUrl: AppConfig.defaultSiteUrl,
    );
    if (!mounted) return;
    setState(() {
      _urls.addAll(saved.urls);
      _selectedUrlIndex = _urls.indexOf(saved.selectedUrl);
      _loadingServers = false;
    });
    if (_selectedUrl.isEmpty) {
      HttpUtil.clearServer();
    } else {
      HttpUtil.switchServer(_selectedUrl);
    }
    await saved.save(prefs);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: dark
                ? const [Color(0xFF14223A), CloudreveColors.darkBackground]
                : const [Color(0xFFEAF3FF), CloudreveColors.background],
            stops: const [0, 0.55],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 24, 22, 28),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 52,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 470),
                      child: Column(
                        children: [
                          _buildCloudHero(),
                          const SizedBox(height: 24),
                          Text(
                            '欢迎回来',
                            style: TextStyle(
                              color: dark ? Colors.white : CloudreveColors.ink,
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            '登录 ${AppConfig.appName}，继续管理你的文件',
                            style: TextStyle(
                              color: CloudreveColors.muted,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 24),
                          CloudrevePanel(
                            padding: const EdgeInsets.all(20),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _buildServerSelector(),
                                  const SizedBox(height: 14),
                                  TextFormField(
                                    controller: _emailController,
                                    keyboardType: TextInputType.emailAddress,
                                    textInputAction: TextInputAction.next,
                                    autofillHints: const [
                                      AutofillHints.username,
                                    ],
                                    decoration: const InputDecoration(
                                      labelText: '电子邮箱',
                                      hintText: 'name@example.com',
                                      prefixIcon: Icon(
                                        Icons.mail_outline_rounded,
                                      ),
                                    ),
                                    validator: (value) {
                                      if (value == null ||
                                          value.trim().isEmpty) {
                                        return '请输入电子邮箱';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 14),
                                  TextFormField(
                                    controller: _passwordController,
                                    obscureText: _obscurePassword,
                                    textInputAction: TextInputAction.done,
                                    autofillHints: const [
                                      AutofillHints.password,
                                    ],
                                    onFieldSubmitted: (_) => _submitLogin(),
                                    decoration: InputDecoration(
                                      labelText: '密码',
                                      hintText: '请输入登录密码',
                                      prefixIcon: const Icon(
                                        Icons.lock_outline_rounded,
                                      ),
                                      suffixIcon: IconButton(
                                        onPressed: () {
                                          setState(() {
                                            _obscurePassword =
                                                !_obscurePassword;
                                          });
                                        },
                                        icon: Icon(
                                          _obscurePassword
                                              ? Icons.visibility_outlined
                                              : Icons.visibility_off_outlined,
                                        ),
                                      ),
                                    ),
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return '请输入密码';
                                      }
                                      if (value.length < 6) {
                                        return '密码长度不能少于 6 位';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Checkbox.adaptive(
                                        value: _rememberSelected,
                                        onChanged: (value) {
                                          setState(() {
                                            _rememberSelected = value ?? false;
                                          });
                                        },
                                      ),
                                      const Text('保持登录状态'),
                                      const Spacer(),
                                      TextButton(
                                        onPressed: _loadingServers
                                            ? null
                                            : () {
                                                if (_selectedUrl.isEmpty) {
                                                  _showLoginError(
                                                    '请先添加并选择 Cloudreve 服务器',
                                                  );
                                                } else {
                                                  context.push('/register');
                                                }
                                              },
                                        child: const Text('注册账户'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  FilledButton(
                                    onPressed: _submitting || _loadingServers
                                        ? null
                                        : _submitLogin,
                                    child: AnimatedSwitcher(
                                      duration: const Duration(
                                        milliseconds: 180,
                                      ),
                                      child: _submitting
                                          ? const SizedBox(
                                              key: ValueKey('loading'),
                                              width: 22,
                                              height: 22,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2.4,
                                                color: Colors.white,
                                              ),
                                            )
                                          : const Text(
                                              '登录',
                                              key: ValueKey('label'),
                                            ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            AppConfig.description,
                            style: TextStyle(
                              color: CloudreveColors.muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCloudHero() {
    return SizedBox(
      width: 220,
      height: 150,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            bottom: 2,
            child: Container(
              width: 166,
              height: 34,
              decoration: BoxDecoration(
                color: const Color(0x332478FF),
                borderRadius: BorderRadius.circular(999),
                boxShadow: const [
                  BoxShadow(color: Color(0x332478FF), blurRadius: 24),
                ],
              ),
            ),
          ),
          const Positioned(
            top: 4,
            child: Icon(
              Icons.cloud_rounded,
              size: 174,
              color: Colors.white,
              shadows: [Shadow(color: Color(0x332478FF), blurRadius: 28)],
            ),
          ),
          Positioned(
            top: 46,
            child: Container(
              width: 76,
              height: 76,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFD5E7FF), width: 2),
              ),
              child: ClipOval(
                child: Image.asset('assets/logo.png', fit: BoxFit.cover),
              ),
            ),
          ),
          const Positioned(
            right: 14,
            top: 34,
            child: _HeroDot(size: 14, color: Color(0xFF9CC7FF)),
          ),
          const Positioned(
            left: 16,
            top: 48,
            child: _HeroDot(size: 8, color: Color(0xFF64DBF6)),
          ),
        ],
      ),
    );
  }

  Widget _buildServerSelector() {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(CloudreveTheme.controlRadius),
      child: InkWell(
        key: const Key('login-server-selector'),
        enableFeedback: context.watch<SoundEffectProvider?>()?.enabled ?? true,
        borderRadius: BorderRadius.circular(CloudreveTheme.controlRadius),
        onTap: _loadingServers ? null : _showServerPicker,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              const Icon(Icons.dns_outlined, color: CloudreveColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Cloudreve 服务器',
                      style: TextStyle(
                        color: CloudreveColors.muted,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _selectedUrl.isEmpty ? '点击添加服务器' : _selectedUrl,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.expand_more_rounded,
                color: CloudreveColors.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showServerPicker() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 2, 18, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '选择服务器',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              ...List.generate(_urls.length, (index) {
                final selected = index == _selectedUrlIndex;
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  leading: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: selected
                          ? CloudreveColors.primarySoft
                          : const Color(0xFFF0F4FA),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      Icons.cloud_outlined,
                      color: selected
                          ? CloudreveColors.primary
                          : CloudreveColors.muted,
                    ),
                  ),
                  title: Text(
                    _urls[index],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (selected)
                        const Icon(
                          Icons.check_circle,
                          color: CloudreveColors.primary,
                        ),
                      IconButton(
                        tooltip: '删除',
                        onPressed: () async {
                          Navigator.pop(sheetContext);
                          await _removeUrl(index);
                        },
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                    ],
                  ),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await _selectUrl(index);
                  },
                );
              }),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(sheetContext);
                    await _addUrl();
                  },
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('添加服务器'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _selectUrl(int index) async {
    HttpUtil.switchServer(_urls[index]);
    if (!mounted) return;
    setState(() {
      _selectedUrlIndex = index;
    });
    await _persistUrls();
  }

  Future<void> _addUrl() async {
    final url = await _showAddUrl();
    if (url == null || !mounted) return;
    if (_urls.contains(url)) {
      await _selectUrl(_urls.indexOf(url));
      return;
    }
    setState(() {
      _urls.add(url);
      _selectedUrlIndex = _urls.length - 1;
    });
    HttpUtil.switchServer(url);
    await _persistUrls();
  }

  Future<void> _removeUrl(int index) async {
    if (index < 0 || index >= _urls.length) return;
    setState(() {
      _urls.removeAt(index);
      if (_selectedUrlIndex >= _urls.length) {
        _selectedUrlIndex = _urls.length - 1;
      } else if (_selectedUrlIndex > index) {
        _selectedUrlIndex--;
      } else if (_selectedUrlIndex == index) {
        _selectedUrlIndex = 0;
      }
    });
    if (_selectedUrl.isEmpty) {
      HttpUtil.clearServer();
    } else {
      HttpUtil.switchServer(_selectedUrl);
    }
    await _persistUrls();
  }

  Future<void> _persistUrls() async {
    final prefs = await SharedPreferences.getInstance();
    await ServerPreferences(_urls, _selectedUrl).save(prefs);
  }

  Future<String?> _showAddUrl() {
    return showDialog<String>(
      context: context,
      builder: (_) => const AddServerDialog(),
    );
  }

  Future<void> _submitLogin() async {
    if (_loadingServers || _submitting) return;
    if (_selectedUrl.isEmpty) {
      await _showLoginError('请先添加并选择 Cloudreve 服务器');
      return;
    }
    if (_submitting || !_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      final loginResult = await CloudreveRepository.signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      if (!mounted) return;
      if (!loginResult.isSuccess || loginResult.data == null) {
        _passwordController.clear();
        await _showLoginError(loginResult.msg ?? '登录失败，请检查账号与密码');
        return;
      }

      final storage =
          await CloudreveRepository.fetchStorage() ?? Storage(0, 0, 0);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(isRememberKey, _rememberSelected);
      await prefs.setBool(isLoginKey, _rememberSelected);
      await prefs.remove(usernameKey);
      await prefs.remove(passwordKey);
      if (_rememberSelected) {
        await SecureSessionStore.save(
          apiBaseUrl: HttpUtil.dio.options.baseUrl,
          token: loginResult.data!.token,
          user: loginResult.data!.user,
        );
      } else {
        await SecureSessionStore.clear();
      }
      if (!mounted) return;
      _onLoginSuccess(loginResult.data!.user, storage);
    } catch (error) {
      if (mounted) {
        await _showLoginError('登录失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _showLoginError(String message) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('无法登录'),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  void _onLoginSuccess(UserData userData, Storage storage) {
    context.read<AppState>().updateSession(
      userData: userData,
      storage: storage,
    );
    context.go('/home/overview');
  }
}

class _HeroDot extends StatelessWidget {
  const _HeroDot({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 8),
        ],
      ),
    );
  }
}
