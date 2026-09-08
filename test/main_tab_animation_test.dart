import 'package:cloudreve/app/main_home.dart';
import 'package:cloudreve/entity/login_result.dart';
import 'package:cloudreve/entity/storage_summary.dart';
import 'package:cloudreve/state/app_state.dart';
import 'package:cloudreve/state/page_transition_provider.dart';
import 'package:cloudreve/state/sound_effect_provider.dart';
import 'package:cloudreve/theme/app_theme.dart';
import 'package:cloudreve/utils/http_util.dart';
import 'package:cloudreve/view/dashboard_home.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _notificationsChannel = MethodChannel(
  'dexterous.com/flutter/local_notifications',
);

class _EmptyCloudreveAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      '{"code":-1,"data":null}',
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_notificationsChannel, (_) async => true);
    HttpUtil.dio = Dio(
      BaseOptions(baseUrl: 'https://cloud.example.com/api/v4/'),
    )..httpClientAdapter = _EmptyCloudreveAdapter();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_notificationsChannel, null);
  });

  testWidgets(
    'settled tab transition offstages old paint layers and retains state',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final appState = AppState()
        ..updateSession(
          userData: UserData.empty(),
          storage: Storage(0, 1024, 1024),
        );
      final transitions = PageTransitionProvider();
      await transitions.initialize();
      await transitions.setStyle(PageTransitionStyle.fade);
      final soundEffects = SoundEffectProvider();
      await soundEffects.initialize();

      late final GoRouter router;
      router = GoRouter(
        initialLocation: '/home/overview',
        routes: <RouteBase>[
          GoRoute(
            path: '/home/:tab',
            pageBuilder: (context, state) {
              final tab = switch (state.pathParameters['tab']) {
                'files' => MainTab.files,
                'shares' => MainTab.shares,
                'settings' => MainTab.settings,
                _ => MainTab.overview,
              };
              return NoTransitionPage<void>(
                key: const ValueKey('main-home-shell'),
                child: MainHome(initialTab: tab),
              );
            },
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AppState>.value(value: appState),
            ChangeNotifierProvider<PageTransitionProvider>.value(
              value: transitions,
            ),
            ChangeNotifierProvider<SoundEffectProvider>.value(
              value: soundEffects,
            ),
          ],
          child: MaterialApp.router(
            theme: CloudreveTheme.light(pageTransitionStyle: transitions.style),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      Finder offstage(int index) =>
          find.byKey(ValueKey('main-tab-offstage-$index'), skipOffstage: false);
      Finder transition(int index) => find.byKey(
        ValueKey('main-tab-transition-$index'),
        skipOffstage: false,
      );

      expect(tester.widget<Offstage>(offstage(0)).offstage, isFalse);
      for (var index = 1; index < 4; index++) {
        expect(tester.widget<Offstage>(offstage(index)).offstage, isTrue);
      }

      final shellState = tester.state<State<MainHome>>(find.byType(MainHome));
      final overviewElement = tester.element(
        find.byType(DashboardHome, skipOffstage: false),
      );

      router.go('/home/files');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));

      // The outgoing file/dashboard page is removed from paint immediately.
      // Its State remains retained, while only the incoming page is onstage.
      expect(tester.widget<Offstage>(offstage(0)).offstage, isTrue);
      expect(tester.widget<Offstage>(offstage(1)).offstage, isFalse);
      expect(tester.widget<Offstage>(offstage(2)).offstage, isTrue);
      expect(tester.widget<Offstage>(offstage(3)).offstage, isTrue);

      await tester.pumpAndSettle();

      expect(tester.widget<Offstage>(offstage(0)).offstage, isTrue);
      expect(tester.widget<Offstage>(offstage(1)).offstage, isFalse);
      expect(tester.widget<Offstage>(offstage(2)).offstage, isTrue);
      expect(tester.widget<Offstage>(offstage(3)).offstage, isTrue);

      // The old opacity layer may still own a detached debug object, but it must
      // no longer be attached to the composited scene after Offstage settles.
      final oldOpacityRenderObject = tester.renderObject(transition(0));
      expect(oldOpacityRenderObject.debugLayer?.attached ?? false, isFalse);
      final oldTransforms = find.descendant(
        of: offstage(0),
        matching: find.byType(Transform, skipOffstage: false),
      );
      for (final transform in oldTransforms.evaluate()) {
        expect(transform.renderObject?.debugLayer?.attached ?? false, isFalse);
      }

      router.go('/home/overview');
      await tester.pumpAndSettle();

      expect(
        tester.state<State<MainHome>>(find.byType(MainHome)),
        same(shellState),
      );
      expect(
        tester.element(find.byType(DashboardHome, skipOffstage: false)),
        same(overviewElement),
      );
      expect(tester.takeException(), isNull);

      // Both file/share overflow menus must clip ink at their outer corners.
      for (final tab in ['files', 'shares']) {
        router.go('/home/$tab');
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(
            Key(tab == 'files' ? 'file-sort-menu' : 'share-sort-menu'),
          ),
        );
        await tester.pumpAndSettle();
        final item = find
            .byWidgetPredicate((widget) => widget is PopupMenuItem)
            .first;
        final surfaces = tester.widgetList<Material>(
          find.ancestor(of: item, matching: find.byType(Material)),
        );
        expect(
          surfaces.any(
            (surface) =>
                surface.shape is RoundedRectangleBorder &&
                surface.clipBehavior == Clip.antiAlias,
          ),
          isTrue,
        );
        final gesture = await tester.startGesture(
          tester.getTopLeft(item) + const Offset(2, 2),
        );
        await tester.pump(const Duration(milliseconds: 150));
        expect(tester.takeException(), isNull);
        await gesture.up();
        await tester.pumpAndSettle();
      }
    },
  );
}
