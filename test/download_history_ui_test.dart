import 'package:cloudreve/state/download_history_controller.dart';
import 'package:cloudreve/state/page_transition_provider.dart';
import 'package:cloudreve/theme/app_theme.dart';
import 'package:cloudreve/view/download_history_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/download_history_test_store.dart';

void main() {
  late DownloadHistoryController history;
  Future<void> initializeHistory() async {
    history = DownloadHistoryController(store: MemoryDownloadHistoryStore());
    await history.setAccount('https://cloud.example.com/api/v4/', 'test-user');
  }

  tearDown(() {
    history.dispose();
  });

  Widget app(Widget child, {bool dark = false}) => ChangeNotifierProvider(
    create: (_) => PageTransitionProvider(),
    child: MaterialApp(
      theme: dark ? CloudreveTheme.dark() : CloudreveTheme.light(),
      home: child,
    ),
  );

  for (final dark in [false, true]) {
    testWidgets(
      'filters, stream labels and rounded controls render in ${dark ? 'dark' : 'light'} mode',
      (tester) async {
        await initializeHistory();
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final download = await history.begin(
          name: 'document.pdf',
          kind: TransferKind.download,
        );
        download.complete(bytes: 4, localPath: '/local/document.pdf');
        (await history.begin(
          name: 'music.mp3',
          kind: TransferKind.audio,
        )).opened();
        await tester.pumpWidget(
          app(DownloadHistoryPage(controller: history), dark: dark),
        );
        await tester.pumpAndSettle();
        expect(find.text('在线播放，不代表已下载完整文件'), findsOneWidget);
        await tester.tap(find.text('文件下载').first);
        await tester.pumpAndSettle();
        expect(find.text('document.pdf'), findsOneWidget);
        expect(find.text('music.mp3'), findsNothing);
        expect(
          find.descendant(
            of: find.byKey(Key('download-record-footer-${download.id}')),
            matching: find.byKey(Key('download-open-${download.id}')),
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('预览加载').first);
        await tester.pumpAndSettle();
        expect(find.text('music.mp3'), findsOneWidget);
        expect(find.text('document.pdf'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'selection bar shares multiple records and disables multi-file details',
    (tester) async {
      await initializeHistory();
      final first = await history.begin(
        name: 'first.pdf',
        kind: TransferKind.download,
      );
      first.complete(bytes: 4, localPath: '/local/first.pdf');
      final second = await history.begin(
        name: 'second.zip',
        kind: TransferKind.download,
      );
      second.complete(bytes: 8, localPath: '/local/second.zip');
      var shared = <DownloadRecord>[];

      await tester.pumpWidget(
        app(
          DownloadHistoryPage(
            controller: history,
            shareRecords: (records) async => shared = records,
          ),
        ),
      );
      expect(find.byKey(const Key('download-selection-bar')), findsNothing);

      await tester.tap(find.byKey(Key('download-select-${first.id}')));
      await tester.pumpAndSettle();
      expect(find.text('已选 1 项'), findsOneWidget);
      expect(find.byKey(const Key('download-selection-bar')), findsOneWidget);
      expect(find.text('分享'), findsOneWidget);
      expect(find.text('删除'), findsOneWidget);
      expect(find.text('详情'), findsOneWidget);
      final singleDetails = tester.widget<InkWell>(
        find.byKey(const Key('download-selection-details')),
      );
      expect(singleDetails.onTap, isNotNull);

      await tester.tap(find.byKey(const Key('download-selection-details')));
      await tester.pumpAndSettle();
      expect(find.text('记录详情'), findsOneWidget);
      expect(find.text('first.pdf'), findsWidgets);
      Navigator.of(tester.element(find.text('记录详情'))).pop();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(Key('download-select-${second.id}')));
      await tester.pumpAndSettle();
      expect(find.text('已选 2 项'), findsOneWidget);
      final detailsFinder = find.byKey(const Key('download-selection-details'));
      expect(tester.widget<InkWell>(detailsFinder).onTap, isNull);
      final detailsIcon = tester.widget<Icon>(
        find.descendant(
          of: detailsFinder,
          matching: find.byIcon(Icons.info_outline_rounded),
        ),
      );
      expect(
        detailsIcon.color,
        Theme.of(tester.element(detailsFinder)).disabledColor,
      );

      await tester.tap(find.byKey(const Key('download-selection-share')));
      await tester.pump();
      expect(shared.map((record) => record.id).toSet(), {first.id, second.id});
    },
  );

  testWidgets('delete confirmation can remove both record and local file', (
    tester,
  ) async {
    await initializeHistory();
    final download = await history.begin(
      name: 'document.pdf',
      kind: TransferKind.download,
    );
    download.complete(bytes: 4, localPath: '/local/document.pdf');
    var localDeleteCalls = 0;

    await tester.pumpWidget(
      app(
        DownloadHistoryPage(
          controller: history,
          isLocalFileAvailable: (_) async => true,
          deleteLocalFiles: (records) async {
            localDeleteCalls++;
            expect(records.single.id, download.id);
            return 0;
          },
        ),
      ),
    );
    await tester.tap(find.byKey(Key('download-select-${download.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('download-selection-delete')));
    await tester.pumpAndSettle();
    expect(find.text('删除 1 条记录？'), findsOneWidget);
    expect(find.text('同时删除本地文件'), findsOneWidget);
    await tester.tap(find.byKey(const Key('delete-local-files-option')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('confirm-delete-selected')));
    await tester.pumpAndSettle();

    expect(history.records, isEmpty);
    expect(localDeleteCalls, 1);
    expect(find.text('记录和本地文件已删除'), findsOneWidget);
  });

  testWidgets(
    'can cancel an active download and clear its record without deleting files',
    (tester) async {
      await initializeHistory();
      var cancelled = false;
      final task = await history.begin(
        name: 'active.bin',
        kind: TransferKind.download,
      );
      task.onCancel(() => cancelled = true);
      await tester.pumpWidget(app(DownloadHistoryPage(controller: history)));
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(cancelled, isTrue);
      expect(find.text('文件下载 · 已取消'), findsOneWidget);

      await tester.tap(find.byKey(Key('download-select-${task.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('download-selection-delete')));
      await tester.pumpAndSettle();
      expect(find.text('删除 1 条记录？'), findsOneWidget);
      expect(find.text('同时删除本地文件'), findsNothing);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('download-select-${task.id}')));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('清除已结束记录'));
      await tester.pumpAndSettle();
      expect(find.text('不会删除已下载的文件，进行中的任务会保留。'), findsOneWidget);
      await tester.tap(find.text('清除'));
      await tester.pumpAndSettle();
      expect(find.text('暂无记录'), findsOneWidget);
    },
  );

  testWidgets('logout hides history even while the page is open', (
    tester,
  ) async {
    await initializeHistory();
    (await history.begin(
      name: 'private.pdf',
      kind: TransferKind.image,
    )).complete(bytes: 4);
    await tester.pumpWidget(app(DownloadHistoryPage(controller: history)));
    expect(find.text('private.pdf'), findsOneWidget);
    await history.setAccount(null, null);
    await tester.pumpAndSettle();
    expect(find.text('private.pdf'), findsNothing);
    expect(find.text('暂无记录'), findsOneWidget);
  });
}
