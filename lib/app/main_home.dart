import 'dart:async';

import 'package:cloudreve/component/file_search_dialog.dart';
import 'package:cloudreve/component/import_share_dialog.dart';
import 'package:cloudreve/component/m_drawer.dart';
import 'package:cloudreve/entity/m_file.dart';
import 'package:cloudreve/state/app_state.dart';
import 'package:cloudreve/state/page_transition_provider.dart';
import 'package:cloudreve/state/sound_effect_provider.dart';
import 'package:cloudreve/theme/app_theme.dart';
import 'package:cloudreve/utils/cloudreve_repository.dart';
import 'package:cloudreve/view/dashboard_home.dart';
import 'package:cloudreve/view/files_page.dart';
import 'package:cloudreve/view/profile_page.dart';
import 'package:cloudreve/view/shares_page.dart';
import 'package:cloudreve_api_client/cloudreve_api_client.dart'
    as cloudreve_api;
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:open_file/open_file.dart';
import 'package:provider/provider.dart';

Map<int, CancelToken> uploadCancelTokenMap = {};

enum MainTab { overview, files, shares, settings }

class MainHome extends StatefulWidget {
  final MainTab initialTab;

  const MainHome({super.key, this.initialTab = MainTab.files});

  @override
  State<MainHome> createState() => _MainHomeState();
}

class _MainHomeState extends State<MainHome> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  DateTime? _lastExitAttempt;
  int _selectedIndex = 0;

  /// 当前路径
  String _path = '/';

  /// 访问后台的文件列表
  late Future<FileListing> _fileResp;
  late Future<FileListing> _dashboardResp;

  /// 列表模式
  Mode _mode = Mode.list;

  /// 文件排序比较函数
  CompareFunction _compare = _compareFunctions[0];

  /// 分享排序方式
  ShareOrderBy _shareOrderBy = shareOrderByOptions.first;

  MFile? _openFile;

  _MainHomeState() {
    _fileResp = _loadListing(_path);
    _dashboardResp = _fileResp;
  }

  Future<FileListing> _loadListing(String path, {bool forceRefresh = false}) {
    final request = CloudreveRepository.listFiles(
      path,
      forceRefresh: forceRefresh,
    );
    // Retained/offstage pages may subscribe a frame later or be disposed while
    // loading. Keep errors available to FutureBuilder without an unhandled gap.
    request.ignore();
    return request;
  }

  FlutterLocalNotificationsPlugin? flutterLocalNotificationsPlugin;

  @override
  void initState() {
    super.initState();
    _selectedIndex = _indexForTab(widget.initialTab);
    flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    var android = AndroidInitializationSettings('ic_stat_cloud');
    var iOS = DarwinInitializationSettings();
    var initSetttings = InitializationSettings(android: android, iOS: iOS);
    flutterLocalNotificationsPlugin?.initialize(
      initSetttings,
      onDidReceiveNotificationResponse: _onSelectNotification,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppState>().refreshSession();
    });
  }

  @override
  void didUpdateWidget(covariant MainHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newIndex = _indexForTab(widget.initialTab);
    if (newIndex != _selectedIndex) {
      _selectedIndex = newIndex;
    }
  }

  int _indexForTab(MainTab tab) {
    return switch (tab) {
      MainTab.overview => 0,
      MainTab.files => 1,
      MainTab.shares => 2,
      MainTab.settings => 3,
    };
  }

  static final _compareFunctions = <CompareFunction>[
    CompareFunction((f1, f2) {
      if (f1.type != f2.type) {
        return f1.type == 'dir' ? -1 : 1;
      }
      return f1.name.compareTo(f2.name);
    }, 'A-Z'),
    CompareFunction((f1, f2) {
      if (f1.type != f2.type) {
        return f1.type == 'dir' ? -1 : 1;
      }
      return f2.name.compareTo(f1.name);
    }, 'Z-A'),
    CompareFunction((f1, f2) {
      if (f1.type != f2.type) {
        return f1.type == 'dir' ? -1 : 1;
      }
      return f1.getFormatDate().compareTo(f2.getFormatDate());
    }, '最早'),
    CompareFunction((f1, f2) {
      if (f1.type != f2.type) {
        return f1.type == 'dir' ? -1 : 1;
      }
      return f2.getFormatDate().compareTo(f1.getFormatDate());
    }, '最新'),
    CompareFunction((f1, f2) {
      if (f1.type != f2.type) {
        return f1.type == 'dir' ? -1 : 1;
      }
      return f2.size.compareTo(f1.size);
    }, '最大'),
    CompareFunction((f1, f2) {
      if (f1.type != f2.type) {
        return f1.type == 'dir' ? -1 : 1;
      }
      return f1.size.compareTo(f2.size);
    }, '最小'),
  ];

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final storage = appState.storage;
    final userData = appState.userData;

    if (storage == null || userData == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        key: _scaffoldKey,
        extendBody: false,
        appBar: AppBar(
          toolbarHeight: 68,
          centerTitle: false,
          leadingWidth: 68,
          leading: Center(
            child: _selectedIndex == 1 && _path != '/'
                ? _TopIconButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    tooltip: '返回上级',
                    onPressed: _goToParentFolder,
                  )
                : Builder(
                    builder: (context) => _TopIconButton(
                      icon: Icons.menu_rounded,
                      tooltip: '菜单',
                      onPressed: () => Scaffold.of(context).openDrawer(),
                    ),
                  ),
          ),
          title: Text(_pageTitle),
          actions: _buildTopActions(),
        ),
        drawer: MDrawer(storage: storage, userData: userData),
        body: _AnimatedMainTabStack(
          index: _selectedIndex,
          style: context.watch<PageTransitionProvider>().style,
          children: <Widget>[
            DashboardHome(
              userData: userData,
              storage: storage,
              fileResp: _dashboardResp,
              onRefresh: _refreshDashboard,
              onOpenFiles: () => _onItemTapped(1),
              onUpload: _uploadFile,
              onOpenShares: _openShares,
            ),
            Home(
              mode: _mode,
              refresh: _refresh,
              path: _path,
              fileResp: _fileResp,
              changePath: _navigateToFolder,
              compare: _compare.fun,
              openFile: _openFile,
              setOpenFile: (file) {
                setState(() => _openFile = file);
              },
            ),
            Share(orderBy: _shareOrderBy),
            Setting(userData: userData, refresh: _refresh),
          ],
        ),
        bottomNavigationBar: _buildBottomBar(),
      ),
    );
  }

  void _handleBack() {
    if (_scaffoldKey.currentState?.isDrawerOpen == true) {
      _scaffoldKey.currentState?.closeDrawer();
      return;
    }
    if (_selectedIndex == 1 && _path != '/') {
      _lastExitAttempt = null;
      _goToParentFolder();
      return;
    }
    final now = DateTime.now();
    final messenger = ScaffoldMessenger.of(context);
    if (_lastExitAttempt != null &&
        now.difference(_lastExitAttempt!) < const Duration(seconds: 2)) {
      messenger.hideCurrentSnackBar();
      SystemNavigator.pop();
      return;
    }
    _lastExitAttempt = now;
    messenger.hideCurrentSnackBar();
    final theme = Theme.of(context);
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        backgroundColor: theme.brightness == Brightness.dark
            ? CloudreveColors.darkSurfaceRaised
            : CloudreveColors.primarySoft,
        content: Row(
          children: [
            Icon(
              Icons.arrow_back_rounded,
              color: theme.colorScheme.primary,
              size: 20,
            ),
            const SizedBox(width: 10),
            Text(
              '再返回一次退出应用',
              style: TextStyle(color: theme.colorScheme.onSurface),
            ),
          ],
        ),
      ),
    );
  }

  String get _pageTitle => switch (_selectedIndex) {
    0 => '首页',
    1 => '我的文件',
    2 => '我的分享',
    3 => '我的',
    _ => 'Cloudreve',
  };

  List<Widget> _buildTopActions() {
    if (_selectedIndex == 0) {
      return [
        _TopIconButton(
          icon: Icons.search_rounded,
          tooltip: '搜索',
          onPressed: _showSearch,
        ),
        _TopIconButton(
          icon: Icons.notifications_none_rounded,
          tooltip: '通知',
          onPressed: () {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('暂无新通知')));
          },
        ),
        const SizedBox(width: 8),
      ];
    }
    if (_selectedIndex == 1) {
      return [
        _TopIconButton(
          icon: Icons.search_rounded,
          tooltip: '搜索',
          onPressed: _showSearch,
        ),
        _TopSortMenuButton<CompareFunction>(
          key: const Key('file-sort-menu'),
          value: _compare,
          items: _compareFunctions,
          labelBuilder: (item) => item.name,
          onSelected: (item) => setState(() => _compare = item),
          tooltip: '更多文件操作',
          mode: _mode,
          onToggleMode: () {
            setState(() {
              _mode = _mode == Mode.list ? Mode.grid : Mode.list;
            });
          },
        ),
        const SizedBox(width: 8),
      ];
    }
    if (_selectedIndex == 2) {
      return [
        _TopIconButton(
          icon: Icons.add_link_rounded,
          tooltip: '导入分享',
          onPressed: _importShare,
        ),
        _TopSortMenuButton<ShareOrderBy>(
          key: const Key('share-sort-menu'),
          value: _shareOrderBy,
          items: shareOrderByOptions,
          labelBuilder: (item) => item.name,
          onSelected: (item) => setState(() => _shareOrderBy = item),
        ),
        const SizedBox(width: 8),
      ];
    }
    return const [];
  }

  Widget _buildBottomBar() {
    final theme = Theme.of(context);
    return ClipRect(
      key: const Key('main-bottom-mask'),
      child: ColoredBox(
        color: theme.scaffoldBackgroundColor,
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(12, 9, 12, 5),
          child: Material(
            key: const Key('main-bottom-bar'),
            elevation: 6,
            color: theme.colorScheme.surface,
            surfaceTintColor: Colors.transparent,
            shadowColor: Colors.black.withValues(alpha: 0.12),
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(
                color: theme.dividerColor.withValues(alpha: 0.45),
              ),
            ),
            child: SizedBox(
              height: 68,
              child: Row(
                children: [
                  _BottomNavButton(
                    icon: Icons.home_rounded,
                    label: '首页',
                    selected: _selectedIndex == 0,
                    onTap: () => _onItemTapped(0),
                  ),
                  _BottomNavButton(
                    icon: Icons.folder_rounded,
                    label: '文件',
                    selected: _selectedIndex == 1,
                    onTap: () => _onItemTapped(1),
                  ),
                  _BottomCreateButton(onTap: _showCreateActions),
                  _BottomNavButton(
                    icon: Icons.share_rounded,
                    label: '分享',
                    selected: _selectedIndex == 2,
                    onTap: () => _onItemTapped(2),
                  ),
                  _BottomNavButton(
                    icon: Icons.person_rounded,
                    label: '我的',
                    selected: _selectedIndex == 3,
                    onTap: () => _onItemTapped(3),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showSearch() async {
    final file = await showDialog<MFile>(
      context: context,
      builder: (_) => const FileSearchDialog(),
    );
    if (!mounted || file == null) return;
    setState(() => _selectedIndex = 1);
    if (file.type == 'dir') {
      _navigateToFolder(file.contentUri);
    } else {
      setState(() => _openFile = file);
    }
  }

  void _navigateToFolder(String path) {
    if (path == 'cloudreve://my' || path == 'cloudreve://my/') path = '/';
    final listing = _loadListing(path);
    setState(() {
      _path = path;
      _fileResp = listing;
      _openFile = null;
      if (path == '/' || path == 'cloudreve://my') _dashboardResp = listing;
    });
  }

  void _goToParentFolder() {
    if (_path.startsWith('cloudreve://')) {
      final uri = Uri.parse(_path);
      final segments = uri.pathSegments
          .where((part) => part.isNotEmpty)
          .toList();
      _navigateToFolder(
        segments.isEmpty
            ? '/'
            : uri
                  .replace(
                    pathSegments: segments.take(segments.length - 1).toList(),
                    query: '',
                    fragment: '',
                  )
                  .toString(),
      );
      return;
    }
    final segments = _path.split('/').where((part) => part.isNotEmpty).toList();
    final parent = segments.length <= 1
        ? '/'
        : '/${segments.sublist(0, segments.length - 1).join('/')}';
    _navigateToFolder(parent);
  }

  Future<void> _refreshDashboard() async {
    await _refresh(true);
  }

  void _openShares() {
    _onItemTapped(2);
  }

  Future<void> _importShare() async {
    final destination = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ImportShareDialog(destination: _path),
    );
    if (!mounted || destination == null) return;
    setState(() => _path = destination);
    _onItemTapped(1);
    await _refresh(true);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('分享已添加到我的文件')));
    }
  }

  void _showCreateActions() {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '新建',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            ListTile(
              leading: const Icon(Icons.add_link_rounded),
              title: const Text('导入分享链接'),
              onTap: () {
                Navigator.pop(sheetContext);
                _importShare();
              },
            ),
            Row(
              children: [
                Expanded(
                  child: _CreateActionCard(
                    icon: Icons.upload_file_rounded,
                    label: '上传文件',
                    color: CloudreveColors.primary,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _uploadFile();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _CreateActionCard(
                    icon: Icons.create_new_folder_rounded,
                    label: '新建文件夹',
                    color: CloudreveColors.success,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _newFold();
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _newFold() {
    final newFoldController = TextEditingController();

    final GlobalKey<FormState> formKey = GlobalKey<FormState>();

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('新建目录'),
          actions: [
            TextButton(
              onPressed: () async {
                if ((formKey.currentState!).validate()) {
                  final res = await CloudreveRepository.createDirectory(
                    _path,
                    newFoldController.text.trim(),
                  );
                  if (!mounted || !dialogContext.mounted) return;
                  if (res != null && res.code == 0) {
                    Navigator.pop(dialogContext);
                    _refresh(true);
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text('新建目录成功')));
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(res?.msg ?? '新建目录失败')),
                    );
                  }
                }
              },
              child: Text('创建'),
            ),
          ],
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: newFoldController,
              decoration: InputDecoration(
                labelText: '文件夹名称',
                icon: Icon(Icons.folder),
              ),
              validator: (v) {
                if (v == null) {
                  return null;
                }
                return v.trim().isNotEmpty ? null : '文件夹名称不得为空';
              },
            ),
          ),
        );
      },
    ).whenComplete(newFoldController.dispose);
  }

  void _onItemTapped(int index) {
    _lastExitAttempt = null;
    if (_selectedIndex == index) {
      return;
    }
    setState(() {
      _selectedIndex = index;
    });
    switch (index) {
      case 0:
        context.go('/home/overview');
        break;
      case 1:
        context.go('/home/files');
        break;
      case 2:
        context.go('/home/shares');
        break;
      case 3:
        context.go('/home/settings');
        break;
    }
  }

  /// 刷新 [immediately]表示是否强制
  Future<void> _refresh(bool immediately) async {
    if (!mounted) return;
    final appState = context.read<AppState>();
    final fileResp = _loadListing(_path, forceRefresh: immediately);
    final dashboardResp = _path == '/' || _path == 'cloudreve://my'
        ? fileResp
        : _loadListing('/', forceRefresh: immediately);
    setState(() {
      _fileResp = fileResp;
      _dashboardResp = dashboardResp;
    });
    // Directory changes never reload profile/capacity. Explicit refresh runs
    // these requests in parallel, instead of blocking file rendering on them.
    await Future.wait([
      appState.refreshSession(forceRefresh: immediately),
      fileResp.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      if (!identical(fileResp, dashboardResp))
        dashboardResp.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    ]);
  }

  void _uploadFile() async {
    try {
      final policies = await CloudreveRepository.fetchUploadPolicies();
      cloudreve_api.StoragePolicy? policy;
      if (policies.length == 1) {
        policy = policies.first;
      } else if (policies.length > 1) {
        policy = await _selectUploadPolicy(policies);
        if (policy == null) {
          return;
        }
      }
      if (!mounted) {
        return;
      }

      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: false,
      );
      if (result == null) {
        return;
      }
      for (final file in result.files) {
        await _uploadSingleFile(file, policy);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('无法开始上传：$error')));
    }
  }

  Future<cloudreve_api.StoragePolicy?> _selectUploadPolicy(
    List<cloudreve_api.StoragePolicy> policies,
  ) {
    return showDialog<cloudreve_api.StoragePolicy>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('选择存储策略'),
        children: policies
            .map(
              (policy) => SimpleDialogOption(
                onPressed: () => Navigator.pop(dialogContext, policy),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.storage),
                  title: Text(policy.name ?? '未命名策略'),
                  subtitle: Text(policy.type?.name ?? '未知类型'),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Future<void> _uploadSingleFile(
    PlatformFile file,
    cloudreve_api.StoragePolicy? policy,
  ) async {
    int fileHashCode = file.hashCode;
    CancelToken cancelToken = CancelToken();
    uploadCancelTokenMap[fileHashCode] = cancelToken;
    try {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('正在上传 ${file.name}')));
      }
      final localPath = file.path;
      if (localPath == null || localPath.isEmpty) {
        throw const CloudreveUploadException('系统没有返回可读取的文件路径');
      }
      await CloudreveRepository.uploadFile(
        localPath: localPath,
        fileName: file.name,
        fileSize: file.size,
        targetFolder: _path,
        policy: policy,
        cancelToken: cancelToken,
        onProgress: (sent, total) {
          final percent = total == 0 ? 1 : sent / total;
          unawaited(
            _showUploadNotification(
              id: fileHashCode,
              title: '上传 ${file.name}',
              body: '${(percent * 100).toStringAsFixed(2)}%',
              payload: 'upload-doing-$fileHashCode',
            ),
          );
        },
      );
      await flutterLocalNotificationsPlugin?.cancel(fileHashCode);
      await _showUploadNotification(
        id: fileHashCode,
        title: '上传 ${file.name}',
        body: '已上传至 $_path',
        payload: 'upload-done',
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('上传完成：${file.name}')));
      }
      await _refresh(true);
    } catch (error) {
      final canceled =
          error is DioException && error.type == DioExceptionType.cancel;
      await flutterLocalNotificationsPlugin?.cancel(fileHashCode);
      await _showUploadNotification(
        id: fileHashCode,
        title: '上传 ${file.name}',
        body: canceled ? '已取消' : '上传失败：$error',
        payload: canceled
            ? 'upload-cancel-$fileHashCode'
            : 'upload-error-$fileHashCode',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              canceled ? '上传已取消' : '上传失败：${_friendlyUploadError(error)}',
            ),
          ),
        );
      }
    } finally {
      uploadCancelTokenMap.remove(fileHashCode);
    }
  }

  String _friendlyUploadError(Object error) {
    if (error is CloudreveUploadException) {
      return error.message;
    }
    if (error is DioException) {
      final responseData = error.response?.data;
      if (responseData is Map) {
        final message = responseData['msg'] ?? responseData['error'];
        if (message != null && message.toString().trim().isNotEmpty) {
          return message.toString();
        }
      }
      final statusCode = error.response?.statusCode;
      if (statusCode != null) {
        return '服务器返回 HTTP $statusCode';
      }
      return error.message ?? '网络连接异常';
    }
    return error.toString();
  }

  void _onSelectNotification(NotificationResponse notificationResponse) {
    String s = notificationResponse.payload!;
    if (s.startsWith('download')) {
      String downloadString = s.substring(9);
      if (downloadString.startsWith('doing')) {
        CancelToken cancelToken =
            downloadCancelTokenMap[int.parse(downloadString.substring(6))]!;
        cancelToken.cancel();
        downloadCancelTokenMap.remove(int.parse(downloadString.substring(6)));
      } else if (downloadString.startsWith('done')) {
        OpenFile.open(downloadString.substring(5));
      }
    } else if (s.startsWith('upload')) {
      String uploadString = s.substring(7);
      if (uploadString.startsWith('doing')) {
        CancelToken cancelToken =
            uploadCancelTokenMap[int.parse(uploadString.substring(6))]!;
        cancelToken.cancel();
        uploadCancelTokenMap.remove(int.parse(uploadString.substring(6)));
      }
    }
  }

  Future<void> _showUploadNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    var android = AndroidNotificationDetails(
      '文件上传',
      '文件上传通道',
      playSound: false,
      channelDescription: '文件上传',
      priority: Priority.min,
      importance: Importance.min,
    );
    var iOS = DarwinNotificationDetails();
    var platform = NotificationDetails(android: android, iOS: iOS);
    await flutterLocalNotificationsPlugin?.show(
      id,
      title,
      body,
      platform,
      payload: payload,
    );
  }
}

class _AnimatedMainTabStack extends StatefulWidget {
  const _AnimatedMainTabStack({
    required this.index,
    required this.style,
    required this.children,
  });

  final int index;
  final PageTransitionStyle style;
  final List<Widget> children;

  @override
  State<_AnimatedMainTabStack> createState() => _AnimatedMainTabStackState();
}

class _AnimatedMainTabStackState extends State<_AnimatedMainTabStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late int _currentIndex;
  int? _previousIndex;
  bool _disableAnimations = false;

  Duration get _duration =>
      _disableAnimations ? Duration.zero : widget.style.duration;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.index;
    _controller = AnimationController(
      vsync: this,
      value: 1,
      duration: widget.style.duration,
    )..addStatusListener(_handleAnimationStatus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _disableAnimations = MediaQuery.disableAnimationsOf(context);
    _controller.duration = _duration;
    if (_duration == Duration.zero && _previousIndex != null) {
      _previousIndex = null;
      _controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant _AnimatedMainTabStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.duration = _duration;

    if (widget.index == _currentIndex) return;
    final outgoingIndex = _currentIndex;
    _currentIndex = widget.index;

    if (_duration == Duration.zero) {
      _previousIndex = null;
      _controller.value = 1;
      return;
    }

    _previousIndex = outgoingIndex;
    _controller.forward(from: 0);
  }

  void _handleAnimationStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || _previousIndex == null) return;
    setState(() => _previousIndex = null);
  }

  @override
  void dispose() {
    _controller
      ..removeStatusListener(_handleAnimationStatus)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.hardEdge,
          children: List<Widget>.generate(widget.children.length, _buildLayer),
        ),
      ),
    );
  }

  Widget _buildLayer(int childIndex) {
    final selected = childIndex == _currentIndex;
    final progress = _controller.isAnimating
        ? Curves.easeOutCubic.transform(_controller.value)
        : 1.0;
    final opacity = selected && widget.style == PageTransitionStyle.fade
        ? progress
        : selected
        ? 1.0
        : 0.0;

    var translation = Offset.zero;
    if (selected &&
        widget.style == PageTransitionStyle.slide &&
        _previousIndex != null) {
      final direction = _currentIndex > _previousIndex! ? 1.0 : -1.0;
      translation = Offset(direction * 0.045 * (1 - progress), 0);
    }

    var scale = 1.0;
    if (selected && widget.style == PageTransitionStyle.scale) {
      scale = 0.975 + (0.025 * progress);
    }

    return Positioned.fill(
      key: ValueKey('main-tab-layer-$childIndex'),
      child: Offstage(
        key: ValueKey('main-tab-offstage-$childIndex'),
        // Only the incoming page paints. Keeping a fading outgoing file list
        // here leaves its cards visible as a rectangular after-image through
        // transparent areas of the next page on the last transition frame.
        offstage: !selected,
        child: Opacity(
          key: ValueKey('main-tab-transition-$childIndex'),
          opacity: opacity.clamp(0.0, 1.0).toDouble(),
          child: FractionalTranslation(
            translation: translation,
            transformHitTests: false,
            child: Transform.scale(
              scale: scale,
              child: ExcludeSemantics(
                excluding: !selected,
                child: ExcludeFocus(
                  excluding: !selected,
                  child: TickerMode(
                    enabled: selected,
                    child: IgnorePointer(
                      ignoring: !selected,
                      child: widget.children[childIndex],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CompareFunction {
  int Function(MFile, MFile) fun;
  String name;
  CompareFunction(this.fun, this.name);
}

class _TopIconButton extends StatelessWidget {
  const _TopIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
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
}

class _TopSortMenuButton<T> extends StatelessWidget {
  const _TopSortMenuButton({
    super.key,
    required this.value,
    required this.items,
    required this.labelBuilder,
    required this.onSelected,
    this.tooltip = '排序方式',
    this.mode,
    this.onToggleMode,
  }) : assert((mode == null) == (onToggleMode == null));

  final T value;
  final List<T> items;
  final String Function(T item) labelBuilder;
  final ValueChanged<T> onSelected;
  final String tooltip;
  final Mode? mode;
  final VoidCallback? onToggleMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return PopupMenuButton<T>(
      clipBehavior: Clip.antiAlias,
      tooltip: tooltip,
      position: PopupMenuPosition.under,
      offset: const Offset(0, 8),
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(21),
      style: const ButtonStyle(tapTargetSize: MaterialTapTargetSize.padded),
      enableFeedback: context.watch<SoundEffectProvider?>()?.enabled ?? true,
      constraints: const BoxConstraints(minWidth: 188, maxWidth: 220),
      itemBuilder: (context) => [
        if (mode != null && onToggleMode != null) ...[
          PopupMenuItem<T>(
            key: const Key('file-view-mode-action'),
            height: 54,
            onTap: onToggleMode,
            child: Row(
              children: [
                Icon(
                  mode == Mode.list
                      ? Icons.grid_view_rounded
                      : Icons.view_list_rounded,
                  color: colors.onSurfaceVariant,
                  size: 21,
                ),
                const SizedBox(width: 12),
                Text(
                  mode == Mode.list ? '切换为网格视图' : '切换为列表视图',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const PopupMenuDivider(height: 1),
          PopupMenuItem<T>(
            enabled: false,
            height: 36,
            child: Text(
              '排序方式',
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
        ...items.map((item) {
          final selected = item == value;
          return PopupMenuItem<T>(
            value: item,
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: selected
                    ? colors.primary.withValues(alpha: 0.1)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: selected
                    ? Border.all(color: colors.primary.withValues(alpha: 0.2))
                    : null,
              ),
              child: Text(
                labelBuilder(item),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: selected ? colors.primary : colors.onSurface,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          );
        }),
      ],
      onSelected: onSelected,
      child: SizedBox.square(
        // Keep PopupMenuButton's 48 dp touch target while matching the
        // visible 42 dp surface used by every other top-bar action.
        dimension: 48,
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surface,
              shape: BoxShape.circle,
            ),
            child: const SizedBox.square(
              dimension: 42,
              child: Icon(Icons.more_horiz_rounded),
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomNavButton extends StatelessWidget {
  const _BottomNavButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? CloudreveColors.primary : CloudreveColors.muted;
    return Expanded(
      child: SizedBox(
        height: double.infinity,
        child: InkWell(
          enableFeedback:
              context.watch<SoundEffectProvider?>()?.enabled ?? true,
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: color, size: 23),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 10.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomCreateButton extends StatelessWidget {
  const _BottomCreateButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Tooltip(
          message: '新建或上传',
          child: Semantics(
            button: true,
            label: '新建或上传',
            child: Material(
              color: CloudreveColors.primary,
              elevation: 6,
              shadowColor: CloudreveColors.primary.withValues(alpha: 0.42),
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: const Key('bottom-create-button'),
                enableFeedback:
                    context.watch<SoundEffectProvider?>()?.enabled ?? true,
                customBorder: const CircleBorder(),
                onTap: onTap,
                child: const SizedBox.square(
                  dimension: 52,
                  child: Icon(Icons.add_rounded, color: Colors.white, size: 30),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CreateActionCard extends StatelessWidget {
  const _CreateActionCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        enableFeedback: context.watch<SoundEffectProvider?>()?.enabled ?? true,
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 22),
          child: Column(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Icon(icon, color: Colors.white, size: 29),
              ),
              const SizedBox(height: 12),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}
