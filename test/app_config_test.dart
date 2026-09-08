import 'package:cloudreve/app/loading_home.dart';
import 'package:cloudreve/app/login_home.dart';
import 'package:cloudreve/config/app_config.dart';
import 'package:cloudreve/theme/app_theme.dart';
import 'package:cloudreve/utils/global_setting.dart';
import 'package:cloudreve/utils/http_util.dart';
import 'package:cloudreve/utils/server_preferences.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    HttpUtil.dio = Dio();
  });

  test('public defaults do not connect to a maintainer deployment', () {
    expect(AppConfig.defaultSiteUrl, isEmpty);
    expect(HttpUtil.defaultApiBaseUrl, isEmpty);
    expect(AppConfig.appName, 'Cloudreve');
    expect(AppConfig.applicationId, 'com.example.cloudreve');
  });

  test(
    'fresh install can have no server or an explicit build default',
    () async {
      final prefs = await SharedPreferences.getInstance();
      expect(ServerPreferences.read(prefs).urls, isEmpty);
      final configured = ServerPreferences.read(
        prefs,
        defaultUrl: 'https://cloud.example.com',
      );
      expect(configured.selectedUrl, 'https://cloud.example.com/api/v4/');
    },
  );

  test('persisted selection wins over changed build defaults; last server can be removed', () async {
    final prefs = await SharedPreferences.getInstance();
    const chosen = 'https://chosen.example/api/v4/';
    await const ServerPreferences([chosen], chosen).save(prefs);
    expect(
      ServerPreferences.read(
        prefs,
        defaultUrl: 'https://new.example',
      ).selectedUrl,
      chosen,
    );
    await const ServerPreferences([], '').save(prefs);
    final empty = ServerPreferences.read(
      prefs,
      defaultUrl: 'https://new.example',
    );
    expect(empty.urls, isEmpty);
    expect(empty.selectedUrl, isEmpty);
  });

  test(
    'legacy custom servers retain selection and invalid entries are filtered',
    () async {
      SharedPreferences.setMockInitialValues({
        urlsKey: [
          'https://one.example',
          'http://insecure.example',
          'https://two.example',
        ],
        selectedIndexKey: 3,
      });
      final prefs = await SharedPreferences.getInstance();
      final migrated = ServerPreferences.read(prefs);
      expect(migrated.urls, [
        'https://one.example/api/v4/',
        'https://two.example/api/v4/',
      ]);
      expect(migrated.selectedUrl, 'https://two.example/api/v4/');
      await prefs.setInt(selectedIndexKey, 0);
      expect(ServerPreferences.read(prefs).selectedUrl, isEmpty);
      expect(
        ServerPreferences.read(
          prefs,
          currentUrl: 'https://session.example',
        ).selectedUrl,
        'https://session.example/api/v4/',
      );
    },
  );

  test('server addresses cannot contain credentials or query tokens', () {
    for (final address in [
      'https://user:password@cloud.example.com',
      'https://cloud.example.com?token=test',
      'https://cloud.example.com/#',
    ]) {
      expect(
        () => HttpUtil.normalizeApiBaseUrl(address),
        throwsFormatException,
      );
    }
  });

  testWidgets('startup name and description use centralized metadata', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: CloudreveTheme.light(), home: const LoadingHome()),
    );
    expect(find.text(AppConfig.appName), findsOneWidget);
    expect(find.text(AppConfig.description), findsOneWidget);
  });

  testWidgets(
    'a server can be added and the final entry removed without a preset',
    (tester) async {
      tester.view.physicalSize = const Size(480, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(theme: CloudreveTheme.light(), home: const LoginHome()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('login-server-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加服务器'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).last,
        'https://cloud.example.com',
      );
      await tester.tap(find.text('添加'));
      await tester.pumpAndSettle();
      expect(HttpUtil.dio.options.baseUrl, 'https://cloud.example.com/api/v4/');
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('login-server-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('删除'));
      await tester.pumpAndSettle();
      expect(find.text('点击添加服务器'), findsOneWidget);
      expect(HttpUtil.dio.options.baseUrl, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(ServerPreferences.read(prefs).urls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unconfigured login opens without errors and blocks authentication until a server is chosen',
    (tester) async {
      tester.view.physicalSize = const Size(480, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var requests = 0;
      HttpUtil.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests++;
            handler.reject(DioException(requestOptions: options));
          },
        ),
      );
      await tester.pumpWidget(
        MaterialApp(theme: CloudreveTheme.light(), home: const LoginHome()),
      );
      await tester.pumpAndSettle();
      expect(find.text('点击添加服务器'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('登录'));
      await tester.pumpAndSettle();
      expect(find.text('请先添加并选择 Cloudreve 服务器'), findsOneWidget);
      expect(requests, 0);
    },
  );
}
