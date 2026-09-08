import 'package:cloudreve/entity/login_result.dart';
import 'package:cloudreve/state/page_transition_provider.dart';
import 'package:cloudreve/state/sound_effect_provider.dart';
import 'package:cloudreve/theme/app_theme.dart';
import 'package:cloudreve/utils/dark_mode_provider.dart';
import 'package:cloudreve/view/app_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PageTransitionProvider pageTransitionProvider;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    pageTransitionProvider = PageTransitionProvider();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Widget buildSettingsPage() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => DarkModeProvider()),
        ChangeNotifierProvider.value(value: pageTransitionProvider),
        ChangeNotifierProvider(create: (_) => SoundEffectProvider()),
      ],
      child: MaterialApp(
        theme: CloudreveTheme.light(),
        home: AppSettingsPage(userData: UserData.empty()),
      ),
    );
  }

  testWidgets('settings expose requested entries without email editing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(buildSettingsPage());

    expect(find.text('设置'), findsOneWidget);
    expect(find.byKey(const Key('app-settings-password')), findsOneWidget);
    expect(find.text('修改密码'), findsOneWidget);
    expect(find.text('界面音效'), findsOneWidget);
    expect(find.text('账户状态'), findsOneWidget);
    expect(find.text('注册时间'), findsOneWidget);
    expect(find.text('安全状态'), findsOneWidget);
    expect(find.byKey(const Key('sound-effects-switch')), findsOneWidget);
    expect(find.byKey(const Key('app-information')), findsOneWidget);
    expect(find.text('应用信息'), findsOneWidget);
    expect(find.text('修改邮箱'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('page transition style can be selected and persisted', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pageTransitionProvider.initialize();

    await tester.pumpWidget(buildSettingsPage());

    expect(find.byKey(const Key('page-transition-settings')), findsOneWidget);
    expect(find.text('页面动画'), findsOneWidget);
    expect(find.text(PageTransitionStyle.slide.label), findsOneWidget);

    await tester.tap(find.byKey(const Key('page-transition-settings')));
    await tester.pumpAndSettle();

    for (final style in PageTransitionStyle.values) {
      expect(
        find.byKey(Key('page-transition-style-${style.name}')),
        findsOneWidget,
      );
      expect(find.text(style.label), findsWidgets);
    }

    await tester.tap(find.byKey(const Key('page-transition-style-fade')));
    await tester.pumpAndSettle();

    final preferences = await SharedPreferences.getInstance();
    expect(pageTransitionProvider.style, PageTransitionStyle.fade);
    expect(
      preferences.getString(PageTransitionProvider.preferenceKey),
      PageTransitionStyle.fade.name,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'password form rejects empty short and mismatched values locally',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildSettingsPage());
      await tester.tap(find.byKey(const Key('app-settings-password')));
      await tester.pumpAndSettle();

      final submit = find.byKey(const Key('submit-password-change'));
      expect(find.byKey(const Key('current-password-field')), findsOneWidget);
      expect(find.byKey(const Key('new-password-field')), findsOneWidget);
      expect(find.byKey(const Key('confirm-password-field')), findsOneWidget);

      await tester.tap(submit);
      await tester.pump();
      expect(find.text('请输入当前密码'), findsOneWidget);
      expect(find.text('请输入新密码'), findsOneWidget);
      expect(find.text('请再次输入新密码'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('current-password-field')),
        'current-password',
      );
      await tester.enterText(
        find.byKey(const Key('new-password-field')),
        '12345',
      );
      await tester.enterText(
        find.byKey(const Key('confirm-password-field')),
        '12345',
      );
      await tester.tap(submit);
      await tester.pump();
      expect(find.text('新密码至少需要 6 个字符'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('new-password-field')),
        '123456',
      );
      await tester.enterText(
        find.byKey(const Key('confirm-password-field')),
        '654321',
      );
      await tester.tap(submit);
      await tester.pump();
      expect(find.text('两次输入的新密码不一致'), findsOneWidget);

      // Every attempted submission above is invalid, so the repository method
      // is never reached and this test performs no network request.
      expect(find.text('保存新密码'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
