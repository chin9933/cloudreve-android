import 'package:cloudreve/entity/login_result.dart';
import 'package:cloudreve/entity/m_file.dart';
import 'package:cloudreve/entity/storage_summary.dart';
import 'package:cloudreve/theme/app_theme.dart';
import 'package:cloudreve/utils/cloudreve_repository.dart';
import 'package:cloudreve/view/dashboard_home.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('dark theme keeps default text readable', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: CloudreveTheme.dark(),
        home: const Scaffold(body: Text('夜间可读')),
      ),
    );

    final context = tester.element(find.text('夜间可读'));
    final theme = Theme.of(context);
    expect(theme.brightness, Brightness.dark);
    expect(
      theme.textTheme.bodyMedium!.color!.computeLuminance(),
      greaterThan(0.5),
    );
    expect(theme.scaffoldBackgroundColor.computeLuminance(), lessThan(0.1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('dashboard fits a common phone viewport', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final user = UserData(
      id: '1',
      userName: 'admin@example.com',
      nickname: 'Cloudreve',
      status: 'active',
      avatar: '',
      createdAt: '2026-09-01T10:00:00Z',
      preferredTheme: 'light',
      anonymous: false,
      language: 'zh-CN',
      group: Group(
        id: '1',
        name: '管理员',
        permission: '',
        directLinkBatchSize: 100,
        trashRetention: 30,
      ),
    );
    final listing = FileListing(
      path: '/',
      contextHint: '',
      fileMap: const {},
      files: [
        MFile(
          '2026-09-02T12:00:00Z',
          'folder-1',
          '工作文档',
          'cloudreve://my/工作文档',
          '',
          0,
          'dir',
        ),
        MFile(
          '2026-09-02T11:00:00Z',
          'file-1',
          '产品设计规范.pdf',
          'cloudreve://my/产品设计规范.pdf',
          '',
          2516583,
          'file',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: CloudreveTheme.light(),
        home: Scaffold(
          body: DashboardHome(
            userData: user,
            storage: Storage(
              128 * 1024 * 1024,
              896 * 1024 * 1024,
              1024 * 1024 * 1024,
            ),
            fileResp: Future.value(listing),
            onRefresh: () async {},
            onOpenFiles: () {},
            onUpload: () {},
            onOpenShares: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('我的空间'), findsOneWidget);
    expect(find.text('我的文件'), findsOneWidget);
    expect(find.text('产品设计规范.pdf'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
