import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloudreve/component/file_search_results.dart';
import 'package:cloudreve/entity/m_file.dart';
import 'package:cloudreve/theme/app_theme.dart';
import 'package:cloudreve/utils/cloudreve_repository.dart';
import 'package:cloudreve/utils/http_util.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cloudreve_protocol_regression_test.dart' show mediaFile;

class _SearchAdapter implements HttpClientAdapter {
  _SearchAdapter(this.respond);
  final FutureOr<Object> Function(RequestOptions) respond;
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions request,
    Stream<Uint8List>? body,
    Future<void>? cancelFuture,
  ) async {
    requests.add(request);
    return ResponseBody.fromString(
      jsonEncode(await respond(request)),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Object _files(String name) => {
  'code': 0,
  'data': {
    'files': [mediaFile(name: name)],
  },
};

void main() {
  late _SearchAdapter adapter;
  void mock(FutureOr<Object> Function(RequestOptions) respond) {
    adapter = _SearchAdapter(respond);
    HttpUtil.dio = Dio(
      BaseOptions(baseUrl: 'https://cloud.example.com/api/v4/'),
    )..httpClientAdapter = adapter;
    HttpUtil.clearAuthToken();
  }

  tearDown(HttpUtil.clearAuthToken);

  Widget screen(
    String query, {
    bool submit = false,
    bool dark = false,
    bool reduceMotion = false,
    ValueChanged<MFile>? onOpen,
  }) => MaterialApp(
    theme: dark ? CloudreveTheme.dark() : CloudreveTheme.light(),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Scaffold(
        body: FileSearchResults(
          query: query,
          submitted: submit,
          onOpen: onOpen ?? (_) {},
        ),
      ),
    ),
  );

  testWidgets('typing is debounced and ordinary rebuilds never resubmit', (
    tester,
  ) async {
    mock((_) => _files('music.flac'));
    for (final text in ['m', 'mu', 'mus', 'musi', 'music']) {
      await tester.pumpWidget(screen(text));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(adapter.requests, isEmpty);
    await tester.pump(const Duration(milliseconds: 321));
    await tester.pumpAndSettle();
    expect(adapter.requests.length, 1);
    expect(find.text('music.flac'), findsOneWidget);
    for (var i = 0; i < 20; i++) {
      await tester.pumpWidget(screen('music', dark: i.isEven));
      await tester.pump();
    }
    expect(adapter.requests.length, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'keyboard submit starts pending query immediately and only once',
    (tester) async {
      mock((_) => _files('song.flac'));
      await tester.pumpWidget(screen('song'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(adapter.requests, isEmpty);
      await tester.pumpWidget(screen('song', submit: true));
      await tester.pumpAndSettle();
      expect(adapter.requests.length, 1);
    },
  );

  testWidgets('slow old response cannot overwrite newer search results', (
    tester,
  ) async {
    final old = Completer<Object>();
    mock(
      (request) =>
          request.queryParameters['uri'].toString().contains('name=old')
          ? old.future
          : _files('new.flac'),
    );
    await tester.pumpWidget(screen('old', submit: true));
    await tester.pump();
    await tester.pumpWidget(screen('new', submit: true));
    await tester.pumpAndSettle();
    expect(find.text('new.flac'), findsOneWidget);
    old.complete(_files('old.flac'));
    await tester.pumpAndSettle();
    expect(find.text('old.flac'), findsNothing);
    expect(find.text('new.flac'), findsOneWidget);
  });

  testWidgets(
    'opening cached root renders files immediately with no request or skeleton',
    (tester) async {
      mock((_) => _files('cached.flac'));
      await tester.runAsync(() => CloudreveRepository.listFiles('/'));
      await tester.pumpWidget(screen(''));
      expect(find.text('cached.flac'), findsOneWidget);
      expect(find.byType(FileSearchSkeleton), findsNothing);
      expect(adapter.requests.length, 1);
    },
  );

  testWidgets('closing before debounce cancels pending search', (tester) async {
    mock((_) => _files('song.flac'));
    await tester.pumpWidget(screen('song'));
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump(const Duration(seconds: 1));
    expect(adapter.requests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('network error ends skeleton and retry recovers', (tester) async {
    var attempt = 0;
    mock(
      (_) => ++attempt == 1
          ? {'code': 500, 'msg': 'offline'}
          : _files('recovered.flac'),
    );
    await tester.pumpWidget(screen('song', submit: true));
    await tester.pumpAndSettle();
    expect(find.text('文件加载失败'), findsOneWidget);
    expect(find.byType(FileSearchSkeleton), findsNothing);
    await tester.tap(find.text('重新加载'));
    await tester.pumpAndSettle();
    expect(find.text('recovered.flac'), findsOneWidget);
    expect(adapter.requests.length, 2);
  });

  for (final dark in [false, true]) {
    testWidgets('skeleton adapts to theme and reduced motion (dark=$dark)', (
      tester,
    ) async {
      final pending = Completer<Object>();
      mock((_) => pending.future);
      await tester.pumpWidget(screen('', dark: dark, reduceMotion: true));
      await tester.pump();
      expect(find.byType(FileSearchSkeleton), findsOneWidget);
      expect(
        tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher)).duration,
        Duration.zero,
      );
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.hasScheduledFrame, isFalse);
      pending.complete(_files('loaded.flac'));
      await tester.pumpAndSettle();
      expect(find.byType(FileSearchSkeleton), findsNothing);
      expect(find.text('loaded.flac'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('loaded row opens the selected actual file', (tester) async {
    mock((_) => _files('selected.flac'));
    MFile? selected;
    await tester.pumpWidget(
      screen('selected', submit: true, onOpen: (file) => selected = file),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('selected.flac'));
    expect(selected?.contentUri, 'cloudreve://my/selected.flac');
  });
}
