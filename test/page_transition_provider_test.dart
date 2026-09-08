import 'package:cloudreve/state/page_transition_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'page transitions expose all selectable styles and default to slide',
    () async {
      expect(PageTransitionStyle.values, <PageTransitionStyle>[
        PageTransitionStyle.none,
        PageTransitionStyle.fade,
        PageTransitionStyle.slide,
        PageTransitionStyle.scale,
      ]);
      expect(PageTransitionStyle.values.map((style) => style.label), <String>[
        '关闭',
        '淡入淡出',
        '平滑滑动',
        '轻柔缩放',
      ]);

      final provider = PageTransitionProvider();
      await provider.initialize();

      expect(provider.style, PageTransitionStyle.slide);
      expect(PageTransitionStyle.none.duration, Duration.zero);
      for (final style in PageTransitionStyle.values.skip(1)) {
        expect(style.duration, greaterThan(Duration.zero));
      }
    },
  );

  test('page transition style is restored from preferences', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      PageTransitionProvider.preferenceKey: PageTransitionStyle.scale.name,
    });
    final provider = PageTransitionProvider();

    await provider.initialize();

    expect(provider.style, PageTransitionStyle.scale);
  });

  test('unknown persisted style safely falls back to slide', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      PageTransitionProvider.preferenceKey: 'future-unknown-style',
    });
    final provider = PageTransitionProvider();

    await provider.initialize();

    expect(provider.style, PageTransitionStyle.slide);
  });

  test(
    'setStyle persists changes and avoids duplicate notifications',
    () async {
      final provider = PageTransitionProvider();
      await provider.initialize();
      var notificationCount = 0;
      provider.addListener(() => notificationCount++);

      await provider.setStyle(PageTransitionStyle.fade);
      await provider.setStyle(PageTransitionStyle.fade);

      final preferences = await SharedPreferences.getInstance();
      expect(provider.style, PageTransitionStyle.fade);
      expect(
        preferences.getString(PageTransitionProvider.preferenceKey),
        PageTransitionStyle.fade.name,
      );
      expect(notificationCount, 1);
    },
  );

  test('setStyle waits for a stored preference before replacing it', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      PageTransitionProvider.preferenceKey: PageTransitionStyle.none.name,
    });
    final provider = PageTransitionProvider();

    await provider.setStyle(PageTransitionStyle.scale);

    final preferences = await SharedPreferences.getInstance();
    expect(provider.style, PageTransitionStyle.scale);
    expect(
      preferences.getString(PageTransitionProvider.preferenceKey),
      PageTransitionStyle.scale.name,
    );
  });
}
