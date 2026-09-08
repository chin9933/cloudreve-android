import 'package:cloudreve/state/page_transition_provider.dart';
import 'package:cloudreve/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all themed dialogs and action sheets clip feedback to their shape', () {
    for (final theme in [CloudreveTheme.light(), CloudreveTheme.dark()]) {
      expect(theme.dialogTheme.clipBehavior, Clip.antiAlias);
      expect(theme.bottomSheetTheme.clipBehavior, Clip.antiAlias);
    }
  });

  testWidgets(
    'rounded cards own a clipped ink surface with padding inside it',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: CloudreveTheme.light(),
          home: Scaffold(
            body: CloudrevePanel(
              child: ListTile(title: const Text('设置'), onTap: () {}),
            ),
          ),
        ),
      );
      final material = tester.widget<Material>(
        find.descendant(
          of: find.byType(CloudrevePanel),
          matching: find.byType(Material),
        ),
      );
      expect(material.clipBehavior, Clip.antiAlias);
      expect(material.child, isA<Padding>());
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'light app bar uses an opaque page background and dark status icons',
    () {
      final appBarTheme = CloudreveTheme.light().appBarTheme;

      expect(appBarTheme.backgroundColor, CloudreveColors.background);
      expect(appBarTheme.backgroundColor, isNot(Colors.transparent));
      expect(
        appBarTheme.systemOverlayStyle?.statusBarIconBrightness,
        Brightness.dark,
      );
      expect(
        appBarTheme.systemOverlayStyle?.statusBarBrightness,
        Brightness.light,
      );
    },
  );

  test(
    'dark app bar uses an opaque page background and light status icons',
    () {
      final appBarTheme = CloudreveTheme.dark().appBarTheme;

      expect(appBarTheme.backgroundColor, CloudreveColors.darkBackground);
      expect(appBarTheme.backgroundColor, isNot(Colors.transparent));
      expect(
        appBarTheme.systemOverlayStyle?.statusBarIconBrightness,
        Brightness.light,
      );
      expect(
        appBarTheme.systemOverlayStyle?.statusBarBrightness,
        Brightness.dark,
      );
    },
  );

  test('light and dark themes apply the selected page transition style', () {
    for (final style in PageTransitionStyle.values) {
      for (final theme in <ThemeData>[
        CloudreveTheme.light(pageTransitionStyle: style),
        CloudreveTheme.dark(pageTransitionStyle: style),
      ]) {
        for (final platform in TargetPlatform.values) {
          final builder = theme.pageTransitionsTheme.builders[platform];
          expect(builder, isA<CloudrevePageTransitionsBuilder>());
          expect(
            (builder! as CloudrevePageTransitionsBuilder).style,
            style,
            reason: '${theme.brightness} $platform',
          );
        }
      }
    }
  });
}
