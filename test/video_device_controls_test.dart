import 'dart:async';
import 'dart:io';

import 'package:cloudreve/utils/video_device_controls.dart';
import 'package:cloudreve/utils/video_gesture_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(VideoDeviceControls.channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'read' => {'brightness': .6, 'volume': .4},
            'brightness' => call.arguments['value'],
            'volume' => .5, // Android reports the actual quantized media level.
            _ => null,
          };
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(VideoDeviceControls.channel, null),
  );

  test(
    'device bridge shares one session, clamps values and restores on close',
    () async {
      final device = VideoDeviceControls();
      final values = await Future.wait([
        device.readLevels(),
        device.readLevels(),
      ]);
      expect(values.first.brightness, .6);
      expect(values.last.volume, .4);
      expect(calls.where((c) => c.method == 'begin').length, 1);
      expect(await device.setBrightness(-1), .05);
      expect(await device.setVolume(2), .5);
      expect(calls.last.arguments['value'], 1);
      final session = calls.first.arguments['session'];
      await device.end();
      await device.end();
      expect(calls.where((c) => c.method == 'end').length, 1);
      expect(calls.every((c) => c.arguments['session'] == session), isTrue);
      await expectLater(device.setVolume(.7), throwsStateError);
      final second = VideoDeviceControls();
      await second.readLevels();
      expect(calls.last.arguments['session'], isNot(session));
      await second.end();
    },
  );

  test(
    'close during session startup cannot perform a late device adjustment',
    () async {
      final pending = Completer<void>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(VideoDeviceControls.channel, (call) async {
            calls.add(call);
            if (call.method == 'begin') await pending.future;
            return null;
          });
      final device = VideoDeviceControls();
      final adjustment = expectLater(device.setVolume(.8), throwsStateError);
      final closing = device.end();
      pending.complete();
      await Future.wait([adjustment, closing]);
      expect(calls.map((c) => c.method), ['begin', 'end']);
    },
  );

  testWidgets(
    'gestures coalesce writes, clamp limits and display actual native levels',
    (tester) async {
      final writes = <double>[];
      var reads = 0;
      final controller = VideoGestureController(
        readLevels: () async {
          reads++;
          return const VideoDeviceLevels(brightness: .5, volume: .4);
        },
        setBrightness: (v) async {
          writes.add(v);
          return v;
        },
        setVolume: (v) async {
          writes.add(v);
          return .6;
        },
      );
      controller.start(brightness: true, height: 400);
      await tester.pump();
      for (var i = 0; i < 80; i++) {
        controller.update(-10);
      }
      expect(writes, isEmpty);
      await tester.pump(const Duration(milliseconds: 40));
      expect(writes, [1]);
      controller.update(1600);
      controller.end();
      await tester.pump();
      expect(writes.last, .05);
      controller.start(brightness: false, height: 400);
      await tester.pump();
      controller.update(-80);
      controller.end();
      await tester.pump();
      expect(controller.level, .6);
      expect(reads, 2);
      await tester.pump(const Duration(seconds: 2));
      expect(controller.visible, isFalse);
      controller.dispose();
    },
  );

  testWidgets(
    'async writes are serialized and canceled reads never update devices',
    (tester) async {
      final pendingRead = Completer<VideoDeviceLevels>();
      final writes = <double>[];
      final controller = VideoGestureController(
        readLevels: () => pendingRead.future,
        setBrightness: (v) async {
          writes.add(v);
          return v;
        },
        setVolume: (v) async {
          writes.add(v);
          return v;
        },
      );
      controller.start(brightness: true, height: 400);
      controller.update(-100);
      controller.cancel();
      pendingRead.complete(const VideoDeviceLevels(brightness: .5, volume: .4));
      await tester.pump(const Duration(milliseconds: 100));
      expect(writes, isEmpty);
      expect(controller.visible, isFalse);
      controller.dispose();

      final pendingWrite = Completer<double>();
      final serialized = VideoGestureController(
        readLevels: () async =>
            const VideoDeviceLevels(brightness: .5, volume: .4),
        setBrightness: (v) async {
          writes.add(v);
          return writes.length == 1 ? await pendingWrite.future : v;
        },
        setVolume: (v) async => v,
      );
      serialized.start(brightness: true, height: 400);
      await tester.pump();
      serialized.update(-30);
      await tester.pump(const Duration(milliseconds: 40));
      serialized.update(-30);
      serialized.update(-30);
      await tester.pump(const Duration(milliseconds: 100));
      expect(writes.length, 1);
      pendingWrite.complete(writes.first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(writes.length, 2);
      expect(writes.last, greaterThan(writes.first));
      serialized.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unavailable hardware fails gracefully without a second spinner',
    (tester) async {
      final controller = VideoGestureController(
        readLevels: () async => throw PlatformException(code: 'unavailable'),
        setBrightness: (v) async => v,
        setVolume: (v) async => v,
      );
      controller.start(brightness: false, height: 400);
      await tester.pump();
      expect(controller.failed, isTrue);
      expect(controller.visible, isTrue);
      await tester.pump(const Duration(seconds: 2));
      expect(controller.visible, isFalse);
      controller.dispose();
    },
  );

  test(
    'Android bridge scopes brightness to the window and volume to music',
    () {
      final source = File(
        'android/app/src/main/java/com/example/cloudreve/MainActivity.java',
      ).readAsStringSync();
      expect(
        source,
        contains('attributes.screenBrightness = originalBrightness'),
      );
      expect(source, contains('session.equals(videoSession)'));
      expect(
        source,
        contains('audio.setStreamVolume(AudioManager.STREAM_MUSIC'),
      );
      expect(source, isNot(contains('Settings.System.put')));
      expect(
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
        isNot(contains('WRITE_SETTINGS')),
      );
    },
  );
}
