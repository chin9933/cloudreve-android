import 'dart:async';
import 'dart:io';

import 'package:cloudreve/component/video_player_controls.dart';
import 'package:cloudreve/theme/app_theme.dart';
import 'package:cloudreve/utils/video_device_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ValueNotifier<VideoPlaybackSnapshot> state;
  var toggles = 0;
  var fullscreens = 0;
  var retries = 0;
  final seeks = <Duration>[];
  final rates = <double>[];
  final brightnesses = <double>[];
  final volumes = <double>[];
  late Future<VideoDeviceLevels> Function() readLevels;

  setUp(() {
    state = ValueNotifier(
      const VideoPlaybackSnapshot(
        opening: false,
        duration: Duration(minutes: 2),
        position: Duration(seconds: 20),
        buffer: Duration(minutes: 1),
      ),
    );
    toggles = fullscreens = retries = 0;
    seeks.clear();
    rates.clear();
    brightnesses.clear();
    volumes.clear();
    readLevels = () async =>
        const VideoDeviceLevels(brightness: .5, volume: .4);
  });
  tearDown(() => state.dispose());

  Widget screen({
    bool dark = false,
    bool fullscreen = false,
    double width = 360,
    double height = 520,
    double scale = 1,
    bool reducedMotion = false,
  }) => MaterialApp(
    theme: dark ? CloudreveTheme.dark() : CloudreveTheme.light(),
    home: MediaQuery(
      data: MediaQueryData(
        textScaler: TextScaler.linear(scale),
        disableAnimations: reducedMotion,
      ),
      child: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            height: height,
            child: ColoredBox(
              color: Colors.black,
              child: VideoPlayerControls(
                state: state,
                fullscreen: fullscreen,
                title: 'video.mp4',
                onToggle: () async => toggles++,
                onFullscreen: () async => fullscreens++,
                onRetry: () async => retries++,
                onReadLevels: () => readLevels(),
                onBrightness: (value) async {
                  brightnesses.add(value);
                  return value;
                },
                onVolume: (value) async {
                  volumes.add(value);
                  return value;
                },
                onSeek: (value) async => seeks.add(value),
                onRate: (value) async {
                  rates.add(value);
                  state.value = state.value.copyWith(rate: value);
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );

  for (final dark in [false, true]) {
    for (final fullscreen in [false, true]) {
      testWidgets(
        'only one themed indicator while opening/buffering (dark=$dark, fullscreen=$fullscreen)',
        (tester) async {
          state.value = const VideoPlaybackSnapshot(
            opening: true,
            buffering: true,
          );
          await tester.pumpWidget(screen(dark: dark, fullscreen: fullscreen));
          await tester.pump(const Duration(milliseconds: 250));
          expect(find.byType(CircularProgressIndicator), findsOneWidget);
          expect(
            find.byKey(const Key('video-loading-indicator')),
            findsOneWidget,
          );
          expect(find.text('正在载入视频…'), findsOneWidget);
          final play = tester.widget<IconButton>(
            find.byKey(const Key('video-play-toggle')),
          );
          expect(play.onPressed, isNull);
          final panel = tester.widget<Material>(
            find.byKey(const Key('video-controls-panel')),
          );
          expect(panel.clipBehavior, Clip.antiAlias);
          expect(
            panel.color,
            (dark ? CloudreveTheme.dark() : CloudreveTheme.light())
                .colorScheme
                .surface,
          );
          await tester.tap(find.byTooltip(fullscreen ? '退出全屏' : '全屏'));
          expect(fullscreens, 1);
          state.value = const VideoPlaybackSnapshot(
            opening: false,
            buffering: true,
          );
          await tester.pump();
          expect(find.text('正在缓冲视频…'), findsOneWidget);
          expect(find.byType(CircularProgressIndicator), findsOneWidget);
          state.value = const VideoPlaybackSnapshot(opening: false);
          await tester.pumpAndSettle();
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'speed selection invokes decoder callback and keeps current speed across rebuild/fullscreen',
    (tester) async {
      await tester.pumpWidget(screen());
      for (final rate in videoPlaybackRates) {
        await tester.tap(find.byKey(const Key('video-speed-button')));
        await tester.pumpAndSettle();
        final item = find.byKey(ValueKey('video-speed-$rate'));
        final surfaces = tester.widgetList<Material>(
          find.ancestor(of: item, matching: find.byType(Material)),
        );
        expect(surfaces.any((s) => s.clipBehavior == Clip.antiAlias), isTrue);
        await tester.tap(item);
        await tester.pumpAndSettle();
        expect(rates.last, rate);
        expect(find.text(videoRateLabel(rate)), findsOneWidget);
      }
      await tester.pumpWidget(screen(fullscreen: true, dark: true));
      await tester.pumpAndSettle();
      expect(find.text('2.0×'), findsOneWidget);
      expect(find.text('video.mp4'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'seeking clamps at media start and end, and slider reports target',
    (tester) async {
      state.value = const VideoPlaybackSnapshot(
        opening: false,
        duration: Duration(seconds: 20),
        position: Duration(seconds: 5),
      );
      await tester.pumpWidget(screen());
      await tester.tap(find.byTooltip('后退 10 秒'));
      expect(seeks.last, Duration.zero);
      state.value = state.value.copyWith(position: const Duration(seconds: 18));
      await tester.pump();
      await tester.tap(find.byTooltip('前进 10 秒'));
      expect(seeks.last, const Duration(seconds: 20));
      final slider = tester.widget<Slider>(
        find.byKey(const Key('video-progress')),
      );
      slider.onChangeStart!(12000);
      slider.onChanged!(12000);
      await tester.pump();
      expect(find.text('00:12'), findsOneWidget);
      slider.onChangeEnd!(12000);
      await tester.pumpAndSettle();
      expect(seeks.last, const Duration(seconds: 12));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'completion offers replay and errors replace rather than stack loaders',
    (tester) async {
      state.value = state.value.copyWith(completed: true);
      await tester.pumpWidget(screen());
      await tester.tap(find.byTooltip('重新播放'));
      expect(toggles, 1);
      state.value = state.value.copyWith(
        opening: true,
        buffering: true,
        error: '无法播放此视频',
      );
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.tap(find.byKey(const Key('video-player-retry')));
      expect(retries, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'playing controls hide once, tap restores them, pause keeps them visible',
    (tester) async {
      state.value = state.value.copyWith(playing: true);
      await tester.pumpWidget(screen());
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 200));
      AnimatedOpacity opacity() =>
          tester.widget(find.byKey(const Key('video-controls-visibility')));
      expect(opacity().opacity, 0);
      await tester.tapAt(
        tester.getCenter(find.byKey(const Key('video-gesture-surface'))),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(opacity().opacity, 1);
      state.value = state.value.copyWith(playing: false);
      await tester.pump(const Duration(seconds: 6));
      expect(opacity().opacity, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('speed menu is not auto-hidden while selecting', (tester) async {
    state.value = state.value.copyWith(playing: true);
    await tester.pumpWidget(screen());
    await tester.tap(find.byKey(const Key('video-speed-button')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 6));
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(const Key('video-controls-visibility')),
          )
          .opacity,
      1,
    );
    await tester.tap(find.byKey(const ValueKey('video-speed-1.5')));
    await tester.pumpAndSettle();
    expect(rates, [1.5]);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(288, 520), const Size(640, 260)]) {
    testWidgets(
      'small/landscape layouts and larger text remain within player ($size)',
      (tester) async {
        await tester.pumpWidget(
          screen(
            width: size.width,
            height: size.height,
            scale: 1.3,
            fullscreen: size.width > size.height,
            reducedMotion: true,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          tester
              .widget<AnimatedOpacity>(
                find.byKey(const Key('video-controls-visibility')),
              )
              .duration,
          Duration.zero,
        );
        await tester.tap(find.byKey(const Key('video-speed-button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('video-speed-1.75')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final dark in [false, true]) {
    testWidgets(
      'fullscreen lock and device HUD use the app theme (dark=$dark)',
      (tester) async {
        await tester.pumpWidget(screen(fullscreen: true, dark: dark));
        final surface = find.byKey(const Key('video-gesture-surface'));
        final origin = tester.getTopLeft(surface);
        await tester.dragFrom(
          origin + const Offset(60, 220),
          const Offset(0, -90),
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(brightnesses.last, greaterThan(.5));
        expect(volumes, isEmpty);
        expect(find.byKey(const Key('video-brightness-value')), findsOneWidget);
        final hud = tester.widget<CloudrevePanel>(
          find.byKey(const Key('video-device-hud')),
        );
        final material = tester.widget<Material>(
          find
              .descendant(
                of: find.byWidget(hud),
                matching: find.byType(Material),
              )
              .first,
        );
        final hudContainer = tester.widget<Container>(
          find
              .descendant(
                of: find.byWidget(hud),
                matching: find.byType(Container),
              )
              .first,
        );
        expect(
          (hudContainer.decoration as BoxDecoration).color,
          (dark ? CloudreveTheme.dark() : CloudreveTheme.light())
              .colorScheme
              .surface,
        );
        expect(material.clipBehavior, Clip.antiAlias);
        await tester.dragFrom(
          origin + const Offset(60, 140),
          const Offset(0, 100),
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(brightnesses.last, lessThan(.5));
        await tester.dragFrom(
          origin + const Offset(300, 220),
          const Offset(0, -90),
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(volumes.last, greaterThan(.4));
        expect(find.byKey(const Key('video-volume-value')), findsOneWidget);
        await tester.dragFrom(
          origin + const Offset(300, 140),
          const Offset(0, 100),
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(volumes.last, lessThan(.4));
        final oldVolumeCalls = volumes.length;
        final oldBrightnessCalls = brightnesses.length;
        await tester.tapAt(origin + const Offset(120, 100));
        await tester.pump(const Duration(milliseconds: 350));
        await tester.tap(find.byTooltip('锁定屏幕'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('解除锁定'), findsOneWidget);
        expect(find.byKey(const Key('video-device-hud')), findsNothing);
        expect(
          tester
              .widget<AnimatedOpacity>(
                find.byKey(const Key('video-controls-visibility')),
              )
              .opacity,
          0,
        );
        await tester.dragFrom(
          origin + const Offset(300, 220),
          const Offset(0, -90),
        );
        await tester.tapAt(
          tester.getCenter(find.byKey(const Key('video-play-toggle'))),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump(const Duration(milliseconds: 500));
        expect(volumes.length, oldVolumeCalls);
        expect(brightnesses.length, oldBrightnessCalls);
        expect(toggles, 0);
        expect(seeks, isEmpty);
        state.value = state.value.copyWith(buffering: true, playing: true);
        await tester.pump();
        expect(
          tester
              .widget<AnimatedOpacity>(
                find.byKey(const Key('video-controls-visibility')),
              )
              .opacity,
          0,
        );
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        state.value = state.value.copyWith(buffering: false);
        await tester.pump();
        await tester.tap(find.byTooltip('解除锁定'));
        await tester.pump(const Duration(milliseconds: 200));
        await tester.tap(find.byKey(const Key('video-play-toggle')));
        expect(toggles, 1);
        await tester.pumpWidget(screen(fullscreen: false));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('video-screen-lock')), findsNothing);
        await tester.dragFrom(
          tester.getTopLeft(surface) + const Offset(300, 220),
          const Offset(0, -90),
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(volumes.length, oldVolumeCalls);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'leaving fullscreen cancels pending device reads and clears lock',
    (tester) async {
      final pending = Completer<VideoDeviceLevels>();
      readLevels = () => pending.future;
      await tester.pumpWidget(screen(fullscreen: true));
      await tester.dragFrom(
        tester.getTopLeft(find.byKey(const Key('video-gesture-surface'))) +
            const Offset(60, 220),
        const Offset(0, -100),
      );
      await tester.tapAt(
        tester.getTopLeft(find.byKey(const Key('video-gesture-surface'))) +
            const Offset(120, 100),
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.byTooltip('锁定屏幕'));
      pending.complete(const VideoDeviceLevels(brightness: .5, volume: .4));
      await tester.pump(const Duration(milliseconds: 200));
      expect(brightnesses, isEmpty);
      await tester.pumpWidget(screen(fullscreen: false));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.byKey(const Key('video-controls-visibility')),
            )
            .opacity,
        1,
      );
      expect(find.byKey(const Key('video-device-hud')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'right-center lock appears only on tap and hides even when locked or paused (dark=$dark)',
      (tester) async {
        await tester.pumpWidget(
          screen(fullscreen: true, dark: dark, width: 640, height: 360),
        );
        final surface = find.byKey(const Key('video-gesture-surface'));
        final rect = tester.getRect(surface);
        final point = rect.topLeft + const Offset(160, 100);
        double opacity() => tester
            .widget<AnimatedOpacity>(
              find.byKey(const Key('video-lock-visibility')),
            )
            .opacity;
        expect(opacity(), 0);
        final lockRect = tester.getRect(
          find.byKey(const Key('video-screen-lock')),
        );
        expect(lockRect.center.dy, closeTo(rect.center.dy, .1));
        expect(rect.right - lockRect.right, closeTo(8, .1));
        expect(
          tester.getSize(find.byKey(const Key('video-controls-panel'))).height,
          lessThanOrEqualTo(94),
        );
        await tester.tapAt(point);
        await tester.pump(const Duration(milliseconds: 350));
        expect(opacity(), 1);
        await tester.pump(const Duration(seconds: 2));
        await tester.tapAt(point);
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pump(const Duration(seconds: 2));
        expect(opacity(), 1); // A further tap renews the idle timeout.
        await tester.pump(const Duration(seconds: 1));
        expect(opacity(), 0); // Pause must not pin the lock on screen.
        await tester.tapAt(point);
        await tester.pump(const Duration(milliseconds: 350));
        await tester.tap(find.byTooltip('锁定屏幕'));
        await tester.pump(const Duration(seconds: 3));
        await tester.pump(const Duration(milliseconds: 200));
        expect(opacity(), 0);
        expect(
          tester
              .widget<IconButton>(find.byKey(const Key('video-screen-lock')))
              .isSelected,
          isTrue,
        );
        state.value = state.value.copyWith(buffering: true);
        await tester.pump();
        expect(opacity(), 0); // Decoder status changes cannot reveal the lock.
        state.value = state.value.copyWith(buffering: false);
        await tester.pump();
        await tester.tapAt(lockRect.center); // Hidden button is not clickable.
        await tester.pump(const Duration(milliseconds: 200));
        expect(opacity(), 1);
        expect(
          tester
              .widget<IconButton>(find.byKey(const Key('video-screen-lock')))
              .isSelected,
          isTrue,
        );
        expect(toggles, 0);
        await tester.tap(find.byTooltip('解除锁定'));
        await tester.pump(const Duration(milliseconds: 200));
        expect(
          tester
              .widget<IconButton>(find.byKey(const Key('video-screen-lock')))
              .isSelected,
          isFalse,
        );
        await tester.pumpWidget(screen());
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('video-screen-lock')), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'sideways and shallow diagonal swipes never adjust devices; vertical swipes still work',
    (tester) async {
      await tester.pumpWidget(screen(fullscreen: true));
      final origin = tester.getTopLeft(
        find.byKey(const Key('video-gesture-surface')),
      );
      for (final right in [false, true]) {
        final start = origin + Offset(right ? 300 : 60, 180);
        for (final dy in [0.0, -40.0, 40.0, -90.0]) {
          await tester.dragFrom(start, Offset(right ? -120 : 120, dy));
          await tester.pump(const Duration(milliseconds: 100));
          expect(brightnesses, isEmpty);
          expect(volumes, isEmpty);
          expect(find.byKey(const Key('video-device-hud')), findsNothing);
        }
        final gesture = await tester.startGesture(start);
        await gesture.moveBy(Offset(right ? -70 : 70, 3));
        await tester.pump();
        await gesture.moveBy(const Offset(2, -90));
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 100));
        expect(brightnesses, isEmpty);
        expect(volumes, isEmpty);
      }
      await tester.dragFrom(
        origin + const Offset(60, 220),
        const Offset(8, -90),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(brightnesses.last, greaterThan(.5));
      await tester.dragFrom(
        origin + const Offset(300, 220),
        const Offset(-8, -90),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(volumes.last, greaterThan(.4));
      final brightnessCount = brightnesses.length;
      final volumeCount = volumes.length;
      await tester.drag(
        find.byKey(const Key('video-progress')),
        const Offset(60, 0),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(seeks, isNotEmpty);
      expect(brightnesses.length, brightnessCount);
      expect(volumes.length, volumeCount);
      expect(tester.takeException(), isNull);
    },
  );

  test('time/rate labels support hours and fractional speeds', () {
    expect(
      videoTimeLabel(const Duration(hours: 1, minutes: 2, seconds: 3)),
      '1:02:03',
    );
    expect(videoTimeLabel(const Duration(seconds: -1)), '00:00');
    expect(videoRateLabel(1.25), '1.25×');
    expect(videoPlaybackRates, containsAll([0.5, 1, 1.5, 2]));
  });

  test('native output uses custom controls; engine and fullscreen behavior are retained', () {
    final source = File('lib/component/cloudreve_video_player.dart')
        .readAsStringSync();
    expect(source, contains('VideoPlayerControls('));
    expect(source, isNot(contains('controls: MaterialVideoControls')));
    expect(source, isNot(contains('CircularProgressIndicator(')));
    expect(source, contains('_player.setRate(rate)'));
    expect(source, contains('toggleFullscreen(videoContext)'));
    expect(source, contains('static final _CloudreveVideoEngine instance'));
    expect(source, isNot(contains('_player.dispose()')));
  });
}
