import 'package:cloudreve/state/sound_effect_provider.dart';
import 'package:cloudreve/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('sound effects default to enabled', () async {
    final provider = SoundEffectProvider();

    await provider.initialize();

    expect(provider.enabled, isTrue);
  });

  test('sound effects load the persisted preference', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      SoundEffectProvider.preferenceKey: false,
    });
    final provider = SoundEffectProvider();

    await provider.initialize();

    expect(provider.enabled, isFalse);
  });

  test(
    'setEnabled persists changes and avoids duplicate notifications',
    () async {
      final provider = SoundEffectProvider();
      await provider.initialize();
      var notificationCount = 0;
      provider.addListener(() => notificationCount++);

      await provider.setEnabled(false);
      await provider.setEnabled(false);

      final preferences = await SharedPreferences.getInstance();
      expect(provider.enabled, isFalse);
      expect(preferences.getBool(SoundEffectProvider.preferenceKey), isFalse);
      expect(notificationCount, 1);
    },
  );

  test('setEnabled waits for a stored preference before changing it', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      SoundEffectProvider.preferenceKey: false,
    });
    final provider = SoundEffectProvider();

    await provider.setEnabled(true);

    final preferences = await SharedPreferences.getInstance();
    expect(provider.enabled, isTrue);
    expect(preferences.getBool(SoundEffectProvider.preferenceKey), isTrue);
  });

  test('light and dark themes apply the feedback preference', () {
    for (final theme in <ThemeData>[
      CloudreveTheme.light(enableFeedback: false),
      CloudreveTheme.dark(enableFeedback: false),
    ]) {
      expect(theme.filledButtonTheme.style?.enableFeedback, isFalse);
      expect(theme.elevatedButtonTheme.style?.enableFeedback, isFalse);
      expect(theme.textButtonTheme.style?.enableFeedback, isFalse);
      expect(theme.outlinedButtonTheme.style?.enableFeedback, isFalse);
      expect(theme.iconButtonTheme.style?.enableFeedback, isFalse);
      expect(theme.floatingActionButtonTheme.enableFeedback, isFalse);
      expect(theme.bottomNavigationBarTheme.enableFeedback, isFalse);
      expect(theme.popupMenuTheme.enableFeedback, isFalse);
      expect(theme.listTileTheme.enableFeedback, isFalse);
      expect(theme.tooltipTheme.enableFeedback, isFalse);
    }
  });
}
