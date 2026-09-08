import 'package:cloudreve/entity/site_auth_config.dart';
import 'package:cloudreve/theme/app_theme.dart';
import 'package:cloudreve/utils/cloudreve_repository.dart';
import 'package:cloudreve/utils/http_util.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

class RegisterHome extends StatefulWidget {
  const RegisterHome({super.key});
  @override
  State<RegisterHome> createState() => _RegisterHomeState();
}

class _RegisterHomeState extends State<RegisterHome> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _captchaText = TextEditingController();
  SiteAuthConfig? _config;
  ImageCaptcha? _captcha;
  String? _error;
  bool _loading = true;
  bool _submitting = false;
  bool _agreed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in [_email, _password, _confirm, _captchaText]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _captcha = null;
    });
    _captchaText.clear();
    try {
      final config = await CloudreveRepository.fetchAuthConfig();
      final captcha = config.registerCaptcha && config.captchaType == 'normal'
          ? await CloudreveRepository.fetchCaptcha()
          : null;
      if (!mounted) return;
      setState(() {
        _config = config;
        _captcha = captcha;
      });
    } catch (_) {
      if (mounted) setState(() => _error = '注册验证加载失败，请检查网络后重试');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (_submitting ||
        _loading ||
        _config == null ||
        !_formKey.currentState!.validate()) {
      return;
    }
    if (!_agreed &&
        (_config!.termsUrl != null || _config!.privacyUrl != null)) {
      setState(() => _error = '请先阅读并同意服务条款和隐私政策');
      return;
    }
    if (_config!.registerCaptcha && _captcha == null) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await CloudreveRepository.register(
        email: _email.text,
        password: _password.text,
        captcha: _captcha == null ? null : _captchaText.text,
        ticket: _captcha?.ticket,
      );
      if (!mounted) return;
      if (result.code == 0 || result.code == 203) {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: Text(result.code == 203 ? '请激活邮箱' : '注册成功'),
            content: Text(
              result.code == 203 ? '激活邮件已发送，请在邮箱中完成验证后登录。' : '现在可以使用新账户登录。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('去登录'),
              ),
            ],
          ),
        );
        if (mounted) context.go('/login');
      } else {
        final message = result.msg?.isNotEmpty == true
            ? result.msg!
            : '注册失败，请重试';
        await _load();
        if (mounted) setState(() => _error = message);
      }
    } catch (_) {
      await _load();
      if (mounted) setState(() => _error = '注册请求未完成，请检查网络后重试');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _openUrl(String? value) async {
    final uri = Uri.tryParse(value ?? '');
    if (uri == null || !['https', 'http'].contains(uri.scheme)) return;
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      setState(() => _error = '无法打开链接');
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    final supported =
        config == null ||
        !config.registerCaptcha ||
        config.captchaType == 'normal';
    return Scaffold(
      appBar: AppBar(title: const Text('注册账户')),
      body: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 470),
              child: CloudrevePanel(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: '邮箱',
                          prefixIcon: Icon(Icons.mail_outline_rounded),
                        ),
                        validator: (value) =>
                            RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                .hasMatch(value?.trim() ?? '')
                            ? null
                            : '请输入有效邮箱',
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _password,
                        obscureText: true,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.newPassword],
                        decoration: const InputDecoration(
                          labelText: '密码',
                          prefixIcon: Icon(Icons.lock_outline_rounded),
                        ),
                        validator: (value) =>
                            (value?.length ?? 0) >= 6 &&
                                (value?.length ?? 0) <= 64
                            ? null
                            : '密码长度应为 6–64 位',
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _confirm,
                        obscureText: true,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: '确认密码',
                          prefixIcon: Icon(Icons.lock_outline_rounded),
                        ),
                        validator: (value) =>
                            value == _password.text && value?.isNotEmpty == true
                            ? null
                            : '两次输入的密码不一致',
                      ),
                      const SizedBox(height: 16),
                      if (_loading)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      else if (config?.registerCaptcha == true &&
                          supported &&
                          _captcha != null) ...[
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                key: const Key('register-captcha'),
                                controller: _captchaText,
                                autocorrect: false,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _submit(),
                                decoration: const InputDecoration(
                                  labelText: '图片验证码',
                                ),
                                validator: (value) =>
                                    value?.trim().isNotEmpty == true
                                    ? null
                                    : '请输入验证码',
                              ),
                            ),
                            const SizedBox(width: 12),
                            InkWell(
                              onTap: _submitting ? null : _load,
                              child: Semantics(
                                label: '点击刷新验证码',
                                button: true,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.memory(
                                    _captcha!.bytes,
                                    width: 120,
                                    height: 54,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _submitting ? null : _load,
                            child: const Text('看不清，换一张'),
                          ),
                        ),
                      ],
                      if (config != null && !config.registerEnabled)
                        const Text('站点当前未开放注册'),
                      if (!supported) ...[
                        const Text('此站点使用网页人机验证，请在站点注册后返回 APP 登录。'),
                        TextButton(
                          onPressed: () => _openUrl(
                            Uri.parse(HttpUtil.dio.options.baseUrl)
                                .resolve('/session/signup')
                                .toString(),
                          ),
                          child: const Text('打开站点验证'),
                        ),
                      ],
                      if (config?.termsUrl != null ||
                          config?.privacyUrl != null)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Checkbox(
                              value: _agreed,
                              onChanged: (value) =>
                                  setState(() => _agreed = value ?? false),
                            ),
                            Expanded(
                              child: Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  const Text('我已阅读并同意'),
                                  if (config?.termsUrl != null)
                                    TextButton(
                                      onPressed: () =>
                                          _openUrl(config!.termsUrl),
                                      child: const Text('服务条款'),
                                    ),
                                  if (config?.privacyUrl != null)
                                    TextButton(
                                      onPressed: () =>
                                          _openUrl(config!.privacyUrl),
                                      child: const Text('隐私政策'),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      if (_error != null)
                        TextButton(
                          onPressed: _load,
                          child: const Text('重新加载验证'),
                        ),
                      FilledButton(
                        onPressed:
                            _submitting ||
                                _loading ||
                                config?.registerEnabled != true ||
                                !supported ||
                                (config!.registerCaptcha && _captcha == null)
                            ? null
                            : _submit,
                        child: _submitting
                            ? const SizedBox.square(
                                dimension: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('注册'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
