import 'package:cloudreve/app/main_home.dart';
import 'package:cloudreve/app/register_home.dart';
import 'package:cloudreve/component/import_share_dialog.dart';
import 'package:cloudreve/entity/login_result.dart';
import 'package:cloudreve/entity/storage_summary.dart';
import 'package:cloudreve/state/app_state.dart';
import 'package:cloudreve/state/page_transition_provider.dart';
import 'package:cloudreve/state/sound_effect_provider.dart';
import 'package:cloudreve/theme/app_theme.dart';
import 'package:cloudreve/utils/cloudreve_repository.dart';
import 'package:cloudreve/utils/http_util.dart';
import 'package:cloudreve/view/dashboard_home.dart';
import 'package:cloudreve/view/web_dav.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cloudreve_protocol_regression_test.dart' show ProtocolAdapter;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    HttpUtil.clearAuthToken();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dexterous.com/flutter/local_notifications'),
          (_) async => true,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dexterous.com/flutter/local_notifications'),
          null,
        );
  });

  testWidgets(
    'registration loads native captcha and validates it before any submission',
    (tester) async {
      final requests = <RequestOptions>[];
      const pixel =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
      HttpUtil.dio =
          Dio(BaseOptions(baseUrl: 'https://cloud.example.com/api/v4/'))
            ..httpClientAdapter = ProtocolAdapter((request) {
              requests.add(request);
              if (request.path.endsWith('captcha')) {
                return {
                  'code': 0,
                  'data': {
                    'ticket': 'ticket-123',
                    'image': 'data:image/png;base64,$pixel',
                  },
                };
              }
              return {
                'code': 0,
                'data': request.path.endsWith('basic')
                    ? {'captcha_type': 'normal'}
                    : {'reg_captcha': true, 'register_enabled': true},
              };
            });
      await tester.pumpWidget(
        MaterialApp(theme: CloudreveTheme.light(), home: const RegisterHome()),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('register-captcha')), findsOneWidget);
      expect(find.text('看不清，换一张'), findsOneWidget);
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'test@example.test',
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'test-password');
      await tester.enterText(find.byType(TextFormField).at(2), 'test-password');
      await tester.ensureVisible(find.widgetWithText(FilledButton, '注册'));
      await tester.tap(find.widgetWithText(FilledButton, '注册'));
      await tester.pumpAndSettle();
      expect(find.text('请输入验证码'), findsOneWidget);
      expect(requests.where((request) => request.method == 'POST'), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'WebDAV failure stops spinner and retry displays returned account',
    (tester) async {
      var failed = true;
      HttpUtil.dio =
          Dio(BaseOptions(baseUrl: 'https://cloud.example.com/api/v4/'))
            ..httpClientAdapter = ProtocolAdapter(
              (_) => failed
                  ? {'code': 403, 'msg': '暂时无法连接'}
                  : {
                      'code': 0,
                      'data': {
                        'accounts': [
                          {
                            'id': 'dav-1',
                            'name': '测试 DAV',
                            'password': 'hidden-test-password',
                          },
                        ],
                      },
                    },
            );
      await tester.pumpWidget(
        MaterialApp(theme: CloudreveTheme.dark(), home: const WebDav()),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('暂时无法连接'), findsOneWidget);
      failed = false;
      await tester.tap(find.widgetWithText(FilledButton, '重新加载'));
      await tester.pumpAndSettle();
      expect(find.text('测试 DAV'), findsOneWidget);
      expect(find.text('hidden-test-password'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'root back exits via platform without popping root route (dark=$dark)',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final calls = <String>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
              calls.add(call.method);
              return null;
            });
        HttpUtil.dio =
            Dio(BaseOptions(baseUrl: 'https://cloud.example.com/api/v4/'))
              ..httpClientAdapter = ProtocolAdapter(
                (_) => {
                  'code': 0,
                  'data': {'files': [], 'shares': []},
                },
              );
        final state = AppState()
          ..updateSession(
            userData: UserData.empty(),
            storage: Storage(1, 100, 99),
          );
        final transitions = PageTransitionProvider();
        await transitions.initialize();
        final sounds = SoundEffectProvider();
        await sounds.initialize();
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: state),
              ChangeNotifierProvider.value(value: transitions),
              ChangeNotifierProvider.value(value: sounds),
            ],
            child: MaterialApp(
              theme: dark ? CloudreveTheme.dark() : CloudreveTheme.light(),
              home: const MainHome(initialTab: MainTab.settings),
            ),
          ),
        );
        // Avatar disk IO is not controlled by FakeAsync. Back navigation must
        // work even while the visible profile is still loading its avatar.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        // The file tab is retained but hidden. It must not intercept this event.
        await tester.binding.handlePopRoute();
        await tester.pump(const Duration(milliseconds: 350));
        expect(find.text('再返回一次退出应用'), findsOneWidget);
        expect(
          tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor,
          dark
              ? CloudreveColors.darkSurfaceRaised
              : CloudreveColors.primarySoft,
        );
        expect(calls.where((call) => call == 'SystemNavigator.pop'), isEmpty);
        await tester.binding.handlePopRoute();
        await tester.pump();
        expect(
          calls.where((call) => call == 'SystemNavigator.pop'),
          hasLength(1),
        );
        expect(find.byType(MainHome), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        state.dispose();
        transitions.dispose();
        sounds.dispose();
      },
    );
  }

  testWidgets('dark storage card has dark fill and contrasting title', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: CloudreveTheme.dark(),
        home: Scaffold(
          body: DashboardHome(
            userData: UserData.empty(),
            storage: Storage(0, 100, 100),
            fileResp: Future.value(FileListing.empty('/')),
            onRefresh: () async {},
            onOpenFiles: () {},
            onUpload: () {},
            onOpenShares: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final title = tester.widget<Text>(find.text('我的空间'));
    expect(title.style!.color!.computeLuminance(), greaterThan(0.5));
    final cards = tester.widgetList<Container>(
      find.ancestor(of: find.text('我的空间'), matching: find.byType(Container)),
    );
    final gradient = cards
        .map((card) => card.decoration)
        .whereType<BoxDecoration>()
        .map((decoration) => decoration.gradient)
        .whereType<LinearGradient>()
        .first;
    expect(
      gradient.colors.every((color) => color.computeLuminance() < 0.08),
      isTrue,
    );
    final caption = tester.widget<Text>(find.textContaining('已使用'));
    for (final background in gradient.colors) {
      final contrast =
          (caption.style!.color!.computeLuminance() + 0.05) /
          (background.computeLuminance() + 0.05);
      expect(contrast, greaterThanOrEqualTo(4.5));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'clipboard import previews real size and writes only after confirmation',
    (tester) async {
      final requests = <RequestOptions>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async => call.method == 'Clipboard.getData'
                ? {'text': 'https://cloud.example.com/s/TestId'}
                : null,
          );
      HttpUtil.dio =
          Dio(BaseOptions(baseUrl: 'https://cloud.example.com/api/v4/'))
            ..httpClientAdapter = ProtocolAdapter((request) {
              requests.add(request);
              if (request.path.startsWith('share/info/')) {
                return {
                  'code': 0,
                  'data': {
                    'unlocked': true,
                    'name': 'song.flac',
                    'source_type': 0,
                    'owner': {'id': 'owner'},
                  },
                };
              }
              if (request.path == 'file') {
                return {
                  'code': 0,
                  'data': {
                    'files': [
                      {
                        'type': 0,
                        'id': 'media',
                        'name': 'song.flac',
                        'path': 'cloudreve://TestId@share/song.flac',
                        'size': 144449051,
                      },
                    ],
                  },
                };
              }
              return {'code': 0};
            });
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: CloudreveTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showDialog<String>(
                    context: context,
                    builder: (_) => const ImportShareDialog(),
                  );
                },
                child: const Text('打开导入'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开导入'));
      await tester.pumpAndSettle();
      expect(find.text('137.8MB'), findsOneWidget);
      expect(requests.where((request) => request.method == 'POST'), isEmpty);
      await tester.tap(find.widgetWithText(FilledButton, '导入'));
      await tester.pumpAndSettle();
      expect(result, 'cloudreve://my');
      final request = requests.singleWhere(
        (request) => request.path == 'file/create',
      );
      expect(
        request.data['metadata']['sys:shared_redirect'],
        'cloudreve://TestId@share/song.flac',
      );
      expect(request.data['err_on_conflict'], isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
