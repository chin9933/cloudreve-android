import 'package:cloudreve/state/page_transition_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

abstract final class CloudreveColors {
  static const primary = Color(0xFF2478FF);
  static const primaryDark = Color(0xFF0D5FE8);
  static const primarySoft = Color(0xFFE9F2FF);
  static const cyan = Color(0xFF34C7F4);
  static const background = Color(0xFFF4F7FC);
  static const surface = Color(0xFFFFFFFF);
  static const ink = Color(0xFF101A2E);
  static const muted = Color(0xFF778399);
  static const line = Color(0xFFE7ECF4);
  static const success = Color(0xFF22B968);
  static const warning = Color(0xFFFF9F43);
  static const danger = Color(0xFFEF4B5F);

  static const darkBackground = Color(0xFF0D1422);
  static const darkSurface = Color(0xFF172033);
  static const darkSurfaceRaised = Color(0xFF202B40);
}

abstract final class CloudreveTheme {
  static const cardRadius = 22.0;
  static const controlRadius = 16.0;
  static const pageBottomInset = 24.0;

  static ThemeData light({
    bool enableFeedback = true,
    PageTransitionStyle pageTransitionStyle = PageTransitionStyle.slide,
  }) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: CloudreveColors.primary,
      brightness: Brightness.light,
      primary: CloudreveColors.primary,
      surface: CloudreveColors.surface,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: CloudreveColors.background,
      splashFactory: InkSparkle.splashFactory,
      pageTransitionsTheme: _pageTransitions(pageTransitionStyle),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: CloudreveColors.background,
        foregroundColor: CloudreveColors.ink,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemStatusBarContrastEnforced: false,
        ),
        titleTextStyle: TextStyle(
          color: CloudreveColors.ink,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: CloudreveColors.surface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: const BorderSide(color: CloudreveColors.line),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF0F4FA),
        hintStyle: const TextStyle(color: Color(0xFF9AA5B6)),
        labelStyle: const TextStyle(color: CloudreveColors.muted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 17,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: const BorderSide(
            color: CloudreveColors.primary,
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: const BorderSide(color: CloudreveColors.danger),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          enableFeedback: enableFeedback,
          minimumSize: const Size(0, 54),
          backgroundColor: CloudreveColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          enableFeedback: enableFeedback,
          minimumSize: const Size(0, 52),
          elevation: 0,
          backgroundColor: CloudreveColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(enableFeedback: enableFeedback),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(enableFeedback: enableFeedback),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(enableFeedback: enableFeedback),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        enableFeedback: enableFeedback,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        enableFeedback: enableFeedback,
      ),
      dividerTheme: const DividerThemeData(
        color: CloudreveColors.line,
        thickness: 1,
        space: 1,
      ),
      dialogTheme: DialogThemeData(
        clipBehavior: Clip.antiAlias,
        backgroundColor: CloudreveColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        clipBehavior: Clip.antiAlias,
        backgroundColor: CloudreveColors.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: CloudreveColors.surface,
        indicatorColor: CloudreveColors.primarySoft,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: CloudreveColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shadowColor: const Color(0x240B1730),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
          side: BorderSide(color: CloudreveColors.line),
        ),
        textStyle: const TextStyle(color: CloudreveColors.ink),
        enableFeedback: enableFeedback,
      ),
      listTileTheme: ListTileThemeData(enableFeedback: enableFeedback),
      tooltipTheme: TooltipThemeData(enableFeedback: enableFeedback),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: CloudreveColors.ink,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  static ThemeData dark({
    bool enableFeedback = true,
    PageTransitionStyle pageTransitionStyle = PageTransitionStyle.slide,
  }) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: CloudreveColors.primary,
      brightness: Brightness.dark,
      primary: const Color(0xFF69A5FF),
      surface: CloudreveColors.darkSurface,
      onSurface: const Color(0xFFF3F6FC),
      onSurfaceVariant: const Color(0xFFB4C0D4),
      outline: const Color(0xFF52617A),
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: CloudreveColors.darkBackground,
      splashFactory: InkSparkle.splashFactory,
      pageTransitionsTheme: _pageTransitions(pageTransitionStyle),
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: colorScheme.onSurface,
        displayColor: colorScheme.onSurface,
      ),
      primaryTextTheme: base.primaryTextTheme.apply(
        bodyColor: colorScheme.onSurface,
        displayColor: colorScheme.onSurface,
      ),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: CloudreveColors.darkBackground,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemStatusBarContrastEnforced: false,
        ),
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: CloudreveColors.darkSurface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: const BorderSide(color: Color(0xFF26324A)),
        ),
      ),
      inputDecorationTheme: light(enableFeedback: enableFeedback)
          .inputDecorationTheme
          .copyWith(
            fillColor: CloudreveColors.darkSurfaceRaised,
            hintStyle: const TextStyle(color: Color(0xFF8997AD)),
            labelStyle: const TextStyle(color: Color(0xFFB4C0D4)),
            iconColor: const Color(0xFFB4C0D4),
          ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          enableFeedback: enableFeedback,
          minimumSize: const Size(0, 54),
          backgroundColor: const Color(0xFF397FE8),
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFF29364C),
          disabledForegroundColor: const Color(0xFF8795AA),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          enableFeedback: enableFeedback,
          minimumSize: const Size(0, 52),
          elevation: 0,
          backgroundColor: const Color(0xFF397FE8),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(enableFeedback: enableFeedback),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(enableFeedback: enableFeedback),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(enableFeedback: enableFeedback),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        enableFeedback: enableFeedback,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        enableFeedback: enableFeedback,
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFF2B374D),
        thickness: 1,
        space: 1,
      ),
      dialogTheme: DialogThemeData(
        clipBehavior: Clip.antiAlias,
        backgroundColor: CloudreveColors.darkSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        clipBehavior: Clip.antiAlias,
        backgroundColor: CloudreveColors.darkSurface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: CloudreveColors.darkSurface,
        indicatorColor: CloudreveColors.darkSurfaceRaised,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(color: Color(0xFFF3F6FC)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF2A3850),
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: CloudreveColors.darkSurfaceRaised,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shadowColor: const Color(0x66000000),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
          side: BorderSide(color: Color(0xFF344159)),
        ),
        textStyle: const TextStyle(color: Color(0xFFF3F6FC)),
        enableFeedback: enableFeedback,
      ),
      listTileTheme: ListTileThemeData(
        textColor: const Color(0xFFF3F6FC),
        iconColor: const Color(0xFFB4C0D4),
        enableFeedback: enableFeedback,
      ),
      tooltipTheme: TooltipThemeData(enableFeedback: enableFeedback),
    );
  }

  static PageTransitionsTheme _pageTransitions(PageTransitionStyle style) {
    final builder = CloudrevePageTransitionsBuilder(style);
    return PageTransitionsTheme(
      builders: {
        TargetPlatform.android: builder,
        TargetPlatform.fuchsia: builder,
        TargetPlatform.iOS: builder,
        TargetPlatform.linux: builder,
        TargetPlatform.macOS: builder,
        TargetPlatform.windows: builder,
      },
    );
  }
}

class CloudrevePageTransitionsBuilder extends PageTransitionsBuilder {
  const CloudrevePageTransitionsBuilder(this.style);

  final PageTransitionStyle style;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return buildCloudrevePageTransition(
      context: context,
      style: style,
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      child: child,
    );
  }
}

Widget buildCloudrevePageTransition({
  required BuildContext context,
  required PageTransitionStyle style,
  required Animation<double> animation,
  required Animation<double> secondaryAnimation,
  required Widget child,
}) {
  if (style == PageTransitionStyle.none ||
      MediaQuery.disableAnimationsOf(context)) {
    return child;
  }

  // CurveTween is listener-free. Allocating CurvedAnimation on every route
  // rebuild leaves status listeners behind and hitches when uncovering a page.
  final curved = animation.drive(CurveTween(curve: Curves.easeInOutCubic));
  final isolated = RepaintBoundary(child: child);
  final faded = FadeTransition(opacity: curved, child: isolated);

  return switch (style) {
    PageTransitionStyle.none => child,
    PageTransitionStyle.fade => faded,
    PageTransitionStyle.slide => ClipRect(
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(curved),
        child: isolated,
      ),
    ),
    PageTransitionStyle.scale => ClipRect(
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.965, end: 1).animate(curved),
        child: faded,
      ),
    ),
  };
}

PageRoute<T> cloudrevePageRoute<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  RouteSettings? settings,
}) {
  final style = context.read<PageTransitionProvider>().style;
  final duration = MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : style.duration;
  return PageRouteBuilder<T>(
    settings: settings,
    opaque: true,
    transitionDuration: duration,
    reverseTransitionDuration: duration,
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
        buildCloudrevePageTransition(
          context: context,
          style: style,
          animation: animation,
          secondaryAnimation: secondaryAnimation,
          child: child,
        ),
  );
}

class CloudrevePanel extends StatelessWidget {
  const CloudrevePanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.margin = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: dark ? CloudreveColors.darkSurface : CloudreveColors.surface,
        borderRadius: BorderRadius.circular(CloudreveTheme.cardRadius),
        border: Border.all(
          color: dark ? const Color(0xFF26324A) : CloudreveColors.line,
        ),
        boxShadow: dark
            ? null
            : const [
                BoxShadow(
                  color: Color(0x0D17335E),
                  blurRadius: 22,
                  offset: Offset(0, 8),
                ),
              ],
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(CloudreveTheme.cardRadius),
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
