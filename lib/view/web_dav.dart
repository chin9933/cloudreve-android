import 'package:cloudreve/theme/app_theme.dart';
import 'package:cloudreve/utils/cloudreve_repository.dart';
import 'package:cloudreve/utils/http_util.dart';
import 'package:cloudreve_api_client/cloudreve_api_client.dart'
    as cloudreve_api;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class WebDav extends StatefulWidget {
  const WebDav({super.key});
  @override
  State<WebDav> createState() => _WebDavState();
}

class _WebDavState extends State<WebDav> {
  late Future<List<cloudreve_api.DavAccount>> _accounts;
  @override
  void initState() {
    super.initState();
    _accounts = CloudreveRepository.fetchWebDavAccounts();
  }

  Future<void> _reload() async {
    setState(() {
      _accounts = CloudreveRepository.fetchWebDavAccounts();
    });
    try {
      await _accounts;
    } catch (_) {
      /* Error is rendered by FutureBuilder. */
    }
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已复制')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('WebDAV'),
      actions: [
        IconButton(
          onPressed: _reload,
          tooltip: '刷新',
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: FutureBuilder<List<cloudreve_api.DavAccount>>(
      future: _accounts,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_rounded, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    snapshot.error is CloudreveApiException
                        ? snapshot.error.toString()
                        : 'WebDAV 加载失败，请检查网络连接',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _reload, child: const Text('重新加载')),
                ],
              ),
            ),
          );
        }
        final list = snapshot.data ?? [];
        return RefreshIndicator(
          onRefresh: _reload,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(18),
            children: [
              CloudrevePanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'WebDAV 地址',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            Uri.parse(HttpUtil.dio.options.baseUrl)
                                .resolve('/dav')
                                .toString(),
                          ),
                        ),
                        IconButton(
                          onPressed: () => _copy(
                            Uri.parse(HttpUtil.dio.options.baseUrl)
                                .resolve('/dav')
                                .toString(),
                          ),
                          tooltip: '复制地址',
                          icon: const Icon(Icons.copy_rounded),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (list.isEmpty)
                const CloudrevePanel(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(child: Text('暂无 WebDAV 账户')),
                  ),
                ),
              for (final account in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: CloudrevePanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          account.name ?? 'WebDAV 账户',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          account.uri ?? '',
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Expanded(child: Text('密码  ••••••••')),
                            TextButton.icon(
                              onPressed: () => _copy(account.password ?? ''),
                              icon: const Icon(Icons.copy_rounded, size: 18),
                              label: const Text('复制密码'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
}
