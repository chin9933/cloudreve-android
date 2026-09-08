import 'dart:convert';

import 'package:cloudreve/component/file_search_dialog.dart';
import 'package:cloudreve/component/import_share_dialog.dart';
import 'package:cloudreve/component/save_folder_dialog.dart';
import 'package:cloudreve/entity/m_file.dart';
import 'package:cloudreve/entity/share_link.dart';
import 'package:cloudreve/theme/app_theme.dart';
import 'package:cloudreve/utils/http_util.dart';
import 'package:cloudreve/utils/share_clipboard_history.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cloudreve_protocol_regression_test.dart'
    show ProtocolAdapter, mediaFile;

void main() {
  late ProtocolAdapter adapter;
  String? clipboard;
  var revision = 1;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    HttpUtil.clearAuthToken();
    clipboard = null;
    revision = 1;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async =>
              call.method == 'Clipboard.getData' ? {'text': clipboard} : null,
        );
    adapter = ProtocolAdapter((request) {
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
      if (request.path == 'file/create') return {'code': 0};
      return {
        'code': 0,
        'data': {
          'files': [mediaFile(name: 'song-$revision.flac')],
        },
      };
    });
    HttpUtil.dio = Dio(
      BaseOptions(baseUrl: 'https://cloud.example.com/api/v4/'),
    )..httpClientAdapter = adapter;
  });
  tearDown(() {
    HttpUtil.clearAuthToken();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Widget harness(
    Widget dialog, {
    bool dark = false,
    ValueChanged<Object?>? onResult,
  }) => MaterialApp(
    theme: dark ? CloudreveTheme.dark() : CloudreveTheme.light(),
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            final result = await showDialog<Object>(
              context: context,
              builder: (_) => dialog,
            );
            onResult?.call(result);
          },
          child: const Text('打开窗口'),
        ),
      ),
    ),
  );

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('打开窗口'));
    await tester.pumpAndSettle();
  }

  TextEditingController linkController(WidgetTester tester) => tester
      .widget<TextField>(find.byKey(const Key('import-share-link')))
      .controller!;

  testWidgets(
    'new clipboard share is autofilled once; repeat is blank, manual paste remains available',
    (tester) async {
      clipboard = 'https://cloud.example.com/s/TestId';
      await tester.pumpWidget(harness(const ImportShareDialog()));
      await open(tester);
      expect(linkController(tester).text, clipboard);
      final count = adapter.requests.length;
      expect(count, 2);
      expect(adapter.requests.where((r) => r.method == 'POST'), isEmpty);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await open(tester);
      expect(linkController(tester).text, isEmpty);
      expect(adapter.requests.length, count);
      await tester.tap(find.byTooltip('从剪贴板粘贴'));
      await tester.pumpAndSettle();
      expect(linkController(tester).text, clipboard);
      expect(adapter.requests.length, count + 2);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      clipboard = 'https://cloud.example.com/s/AnotherId';
      await open(tester);
      expect(linkController(tester).text, clipboard);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      clipboard = 'https://cloud.example.com/s/TestId';
      await open(tester);
      expect(linkController(tester).text, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'ordinary or foreign clipboard text is not autofilled or fetched',
    (tester) async {
      for (final text in [
        'ordinary copied text',
        'https://foreign.example/s/TestId',
      ]) {
        clipboard = text;
        await tester.pumpWidget(harness(const ImportShareDialog()));
        await open(tester);
        expect(linkController(tester).text, isEmpty);
        expect(adapter.requests, isEmpty);
        expect(find.text('无法读取剪贴板，请手动粘贴链接'), findsNothing);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
      }
    },
  );

  test(
    'clipboard deduplication is serialized, persistent, and stores only hashes',
    () async {
      const link = ShareLink(id: 'PrivateShare', password: 'secret-code');
      expect(
        await Future.wait([
          ShareClipboardHistory.claim(
            link,
            scope: 'https://cloud.example.com|user1',
          ),
          ShareClipboardHistory.claim(
            link,
            scope: 'https://cloud.example.com|user1',
          ),
        ]),
        [true, false],
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      expect(
        await ShareClipboardHistory.claim(
          link,
          scope: 'https://cloud.example.com|user1',
        ),
        isFalse,
      );
      expect(
        await ShareClipboardHistory.claim(
          link,
          scope: 'https://cloud.example.com|user2',
        ),
        isTrue,
      );
      final stored = jsonEncode({
        for (final key in prefs.getKeys()) key: prefs.get(key),
      });
      expect(stored, isNot(contains('PrivateShare')));
      expect(stored, isNot(contains('secret-code')));
      expect(stored, isNot(contains('https://')));
    },
  );

  test('save paths are normalized and restricted to own space', () {
    expect(
      normalizeSaveFolder('/音乐 收藏'),
      'cloudreve://my/%E9%9F%B3%E4%B9%90%20%E6%94%B6%E8%97%8F',
    );
    expect(saveFolderLabel('/音乐 收藏'), '我的文件 / 音乐 收藏');
    expect(normalizeSaveFolder('cloudreve://my/'), 'cloudreve://my');
    for (final path in [
      'cloudreve://id@share/music',
      'cloudreve://id@my/a',
      'https://evil.test/folder',
      'cloudreve://my?name=x',
    ]) {
      expect(normalizeSaveFolder(path), 'cloudreve://my');
    }
  });

  Map<String, dynamic> folder(
    String name,
    String path, {
    bool shortcut = false,
  }) => {
    'id': name,
    'type': 1,
    'name': name,
    'path': path,
    if (shortcut) 'metadata': {'sys:shared_redirect': 'cloudreve://id@share'},
  };

  testWidgets(
    'share import selects a nested destination and returns it after confirmation only',
    (tester) async {
      adapter = ProtocolAdapter((request) {
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
        if (request.path == 'file/create') return {'code': 0};
        final uri = request.queryParameters['uri']?.toString() ?? '';
        return {
          'code': 0,
          'data': {
            'files': uri.contains('@share')
                ? [mediaFile(path: 'cloudreve://TestId@share/song.flac')]
                : uri == 'cloudreve://my'
                ? [
                    folder('音乐', 'cloudreve://my/%E9%9F%B3%E4%B9%90'),
                    folder('共享文件夹', 'cloudreve://my/shortcut', shortcut: true),
                    mediaFile(),
                  ]
                : [],
          },
        };
      });
      HttpUtil.dio.httpClientAdapter = adapter;
      Object? result;
      await tester.pumpWidget(
        harness(const ImportShareDialog(), onResult: (value) => result = value),
      );
      await open(tester);
      await tester.tap(find.byKey(const Key('choose-share-destination')));
      await tester.pumpAndSettle();
      expect(find.text('共享文件夹'), findsNothing);
      await tester.tap(find.text('音乐'));
      await tester.pumpAndSettle();
      expect(find.text('我的文件 / 音乐'), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirm-save-folder')));
      await tester.pumpAndSettle();
      expect(find.text('保存到：我的文件 / 音乐'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('import-share-link')),
        'https://cloud.example.com/s/TestId',
      );
      await tester.tap(find.widgetWithText(FilledButton, '读取分享'));
      await tester.pumpAndSettle();
      expect(adapter.requests.where((r) => r.method == 'POST'), isEmpty);
      await tester.tap(find.widgetWithText(FilledButton, '导入'));
      await tester.pumpAndSettle();
      expect(result, 'cloudreve://my/%E9%9F%B3%E4%B9%90');
      final post = adapter.requests.singleWhere((r) => r.method == 'POST');
      expect(post.data['uri'], 'cloudreve://my/%E9%9F%B3%E4%B9%90/song.flac');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'destination cancel preserves original folder and browsing is cached',
    (tester) async {
      adapter = ProtocolAdapter(
        (request) => {
          'code': 0,
          'data': {
            'files': request.queryParameters['uri'] == 'cloudreve://my'
                ? [folder('Music', 'cloudreve://my/Music')]
                : [],
          },
        },
      );
      HttpUtil.dio.httpClientAdapter = adapter;
      await tester.pumpWidget(
        harness(const ImportShareDialog(destination: '/Music')),
      );
      await open(tester);
      await tester.tap(find.byKey(const Key('choose-share-destination')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('返回上一级'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Music'));
      await tester.pumpAndSettle();
      expect(adapter.requests.length, 2);
      await tester.tap(find.byTooltip('关闭位置选择'));
      await tester.pumpAndSettle();
      expect(find.text('保存到：我的文件 / Music'), findsOneWidget);
      expect(adapter.requests.where((r) => r.method != 'GET'), isEmpty);
    },
  );

  testWidgets('folder picker can reach directories on cursor pages', (
    tester,
  ) async {
    adapter = ProtocolAdapter((request) {
      final next = request.queryParameters['next_page_token'] == 'page-2';
      return {
        'code': 0,
        'data': {
          'files': next
              ? [folder('LastFolder', 'cloudreve://my/last')]
              : [mediaFile()],
          'pagination': {'is_cursor': true, if (!next) 'next_token': 'page-2'},
        },
      };
    });
    HttpUtil.dio.httpClientAdapter = adapter;
    await tester.pumpWidget(
      harness(const SaveFolderDialog(initialFolder: '/')),
    );
    await open(tester);
    await tester.tap(find.text('加载更多'));
    await tester.pumpAndSettle();
    expect(find.text('LastFolder'), findsOneWidget);
    expect(find.text('加载更多'), findsNothing);
    expect(adapter.requests.length, 2);
  });

  for (final dark in [false, true]) {
    testWidgets(
      'search is a clipped modal with refresh, keyboard-safe layout and selection (dark=$dark)',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        Object? selected;
        await tester.pumpWidget(
          harness(
            const FileSearchDialog(),
            dark: dark,
            onResult: (value) => selected = value,
          ),
        );
        await open(tester);
        expect(find.byType(Scaffold), findsOneWidget);
        expect(find.byKey(const Key('file-search-dialog')), findsOneWidget);
        expect(
          tester.widget<Dialog>(find.byType(Dialog)).clipBehavior,
          Clip.antiAlias,
        );
        final bounds = tester.getRect(
          find.byKey(const Key('file-search-surface')),
        );
        expect(bounds.width, lessThan(390));
        expect(bounds.height, lessThan(844));
        await tester.enterText(
          find.byKey(const Key('file-search-input')),
          'song',
        );
        await tester.pump(const Duration(milliseconds: 321));
        await tester.pumpAndSettle();
        final count = adapter.requests.length;
        revision = 2;
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pumpAndSettle();
        expect(adapter.requests.length, count);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('刷新搜索结果'));
        await tester.pumpAndSettle();
        expect(find.text('song-2.flac'), findsOneWidget);
        expect(adapter.requests.length, count + 1);
        await tester.tap(find.text('song-2.flac'));
        await tester.pumpAndSettle();
        expect(selected, isA<MFile>());
        expect(find.byType(FileSearchDialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
