import 'dart:async';

import 'package:cloudreve/component/share_dialog.dart';
import 'package:cloudreve/component/share_result_dialog.dart';
import 'package:cloudreve/entity/m_file.dart';
import 'package:cloudreve/utils/cloudreve_repository.dart';
import 'package:cloudreve/utils/http_util.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Controlled JSON transport keeps this test focused on generated
// deserialization and route lifecycle. Protocol tests cover the HTTP adapter.
class _ShareClient extends DioForNative {
  _ShareClient()
    : super(BaseOptions(baseUrl: 'https://cloud.example.test/api/v4/'));

  // setUp runs outside testWidgets' fake-async zone. Lazily create the
  // completer where fetch/complete runs so its callbacks use the test clock.
  late final response = Completer<Map<String, Object?>>();
  int requests = 0;

  @override
  Future<Response<T>> fetch<T>(RequestOptions requestOptions) async {
    requests++;
    return Response<T>(
      requestOptions: requestOptions,
      statusCode: 200,
      data: await response.future as T,
    );
  }
}

void main() {
  const link = 'https://cloud.example.test/s/fixture';
  late Dio previousDio;
  late _ShareClient client;

  setUp(() {
    previousDio = HttpUtil.dio;
    client = _ShareClient();
    HttpUtil.dio = client;
    HttpUtil.clearAuthToken();
  });

  tearDown(() {
    HttpUtil.dio.close(force: true);
    HttpUtil.dio = previousDio;
    HttpUtil.clearAuthToken();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Widget host(Widget dialog, {ValueChanged<String?>? onResult}) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              final result = await showDialog<String>(
                context: context,
                builder: (_) => dialog,
              );
              onResult?.call(result);
            },
            child: const Text('打开'),
          ),
        ),
      ),
    );
  }

  MFile fixture() => MFile.fromJson({
    'id': 'fixture',
    'type': 0,
    'name': 'example.txt',
    'path': 'cloudreve://my/example.txt',
    'size': 5,
  });

  test('generated share response preserves the returned link', () async {
    client.response.complete({'code': 0, 'data': link});
    final response = await CloudreveRepository.createShare(uri: fixture().path);
    expect(response?.code, 0);
    expect(response?.data, link);
  });

  testWidgets('creation returns a link without popping the host page', (
    tester,
  ) async {
    String? result;
    await tester.pumpWidget(
      host(ShareDialog(file: fixture()), onResult: (value) => result = value),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pump();
    client.response.complete({'code': 0, 'data': link});
    await tester.pumpAndSettle();
    expect(client.requests, 1);
    expect(result, link);
    expect(find.text('打开'), findsOneWidget);
    expect(find.byType(ShareDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing a pending creation ignores the late response', (
    tester,
  ) async {
    await tester.pumpWidget(host(ShareDialog(file: fixture())));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pump();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    client.response.complete({'code': 0, 'data': link});
    await tester.pumpAndSettle();
    expect(find.text('打开'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('copy feedback uses a live messenger after closing the dialog', (
    tester,
  ) async {
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        });
    await tester.pumpWidget(host(const ShareResultDialog(link: link)));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('复制'));
    await tester.pumpAndSettle();
    expect(copied, link);
    expect(find.byType(ShareResultDialog), findsNothing);
    expect(find.text('复制成功'), findsOneWidget);
    expect(find.text('打开'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
