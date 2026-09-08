import 'dart:io';

import 'package:cloudreve/app/loading_home.dart';
import 'package:cloudreve/config/app_config.dart';
import 'package:cloudreve/theme/app_theme.dart';
import 'package:cloudreve/utils/dark_mode_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final mode in DarkMode.values) {
    for (final systemDark in [false, true]) {
      testWidgets(
        'startup first frame respects saved ${mode.name}, system dark=$systemDark',
        (tester) async {
          SharedPreferences.setMockInitialValues({
            DarkModeProvider.preferenceKey: mode.name,
          });
          final provider = DarkModeProvider();
          await provider.initialize();
          addTearDown(provider.dispose);
          tester.platformDispatcher.platformBrightnessTestValue = systemDark
              ? Brightness.dark
              : Brightness.light;
          addTearDown(
            tester.platformDispatcher.clearPlatformBrightnessTestValue,
          );
          final themeMode = switch (provider.darkMode) {
            DarkMode.open => ThemeMode.dark,
            DarkMode.close => ThemeMode.light,
            DarkMode.auto => ThemeMode.system,
          };
          final dark =
              mode == DarkMode.open || (mode == DarkMode.auto && systemDark);
          final colors = (dark ? CloudreveTheme.dark() : CloudreveTheme.light())
              .colorScheme;
          await tester.pumpWidget(
            MaterialApp(
              theme: CloudreveTheme.light(),
              darkTheme: CloudreveTheme.dark(),
              themeMode: themeMode,
              home: const LoadingHome(),
            ),
          );
          final backdrop = tester.widget<Container>(
            find.byKey(const Key('startup-background')),
          );
          final gradient =
              (backdrop.decoration as BoxDecoration).gradient!
                  as LinearGradient;
          expect(
            gradient.colors.first,
            dark ? CloudreveColors.darkBackground : const Color(0xFFF8FBFF),
          );
          expect(
            tester.widget<Text>(find.text(AppConfig.appName)).style!.color,
            colors.onSurface,
          );
          expect(
            tester.widget<Text>(find.text(AppConfig.description)).style!.color,
            colors.onSurfaceVariant,
          );
          expect(
            tester
                .widget<CircularProgressIndicator>(
                  find.byType(CircularProgressIndicator),
                )
                .color,
            colors.primary,
          );
          final bars = tester
              .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
                find.byKey(const Key('startup-system-bars')),
              )
              .value;
          expect(
            bars.statusBarIconBrightness,
            dark ? Brightness.light : Brightness.dark,
          );
          expect(
            bars.systemNavigationBarIconBrightness,
            dark ? Brightness.light : Brightness.dark,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  test('corrupt theme preference recovers and can be replaced', () async {
    SharedPreferences.setMockInitialValues({
      DarkModeProvider.preferenceKey: 42,
    });
    final provider = DarkModeProvider();
    await provider.initialize();
    expect(provider.darkMode, DarkMode.auto);
    await provider.changeMode(DarkMode.open);
    expect(provider.darkMode, DarkMode.open);
    final restored = DarkModeProvider();
    await restored.initialize();
    expect(restored.darkMode, DarkMode.open);
    provider.dispose();
    restored.dispose();
  });

  test('theme resolves before runApp and Android launch resources have night colors', () {
    final source = File('lib/main.dart').readAsStringSync();
    expect(
      source.indexOf('await darkModeProvider.initialize()'),
      lessThan(source.indexOf('runApp(MyApp(')),
    );
    expect(source, contains('initialDarkModeProvider: darkModeProvider'));
    for (final folder in ['drawable', 'drawable-v21']) {
      final native = File(
        'android/app/src/main/res/$folder/launch_background.xml',
      ).readAsStringSync();
      expect(native, contains('@color/startup_background'));
      expect(native, isNot(contains('@android:color/white')));
    }
    expect(
      File('android/app/src/main/res/values-night/colors.xml')
          .readAsStringSync(),
      contains('#0D1422'),
    );
    final activity = File(
      'android/app/src/main/java/com/example/cloudreve/MainActivity.java',
    ).readAsStringSync();
    expect(activity, contains('flutter.settings.dark_mode'));
    expect(activity, contains('getWindow().setBackgroundDrawable'));
  });
}
