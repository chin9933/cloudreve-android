import 'package:cloudreve/app/loading_home.dart';
import 'package:cloudreve/app/login_home.dart';
import 'package:cloudreve/app/main_home.dart';
import 'package:cloudreve/app/register_home.dart';
import 'package:cloudreve/config/app_config.dart';
import 'package:cloudreve/state/app_state.dart';
import 'package:cloudreve/state/page_transition_provider.dart';
import 'package:cloudreve/state/sound_effect_provider.dart';
import 'package:cloudreve/theme/app_theme.dart';
import 'package:cloudreve/utils/dark_mode_provider.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Resolve local appearance before the first Flutter frame, not afterwards.
  final darkModeProvider = DarkModeProvider();
  await darkModeProvider.initialize();
  MediaKit.ensureInitialized();
  runApp(MyApp(initialDarkModeProvider: darkModeProvider));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, this.initialDarkModeProvider});
  final DarkModeProvider? initialDarkModeProvider;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final DarkModeProvider _darkModeProvider;
  late final PageTransitionProvider _pageTransitionProvider;
  late final SoundEffectProvider _soundEffectProvider;
  late final AppState _appState;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _darkModeProvider = (widget.initialDarkModeProvider ?? DarkModeProvider())
      ..initialize();
    _pageTransitionProvider = PageTransitionProvider()..initialize();
    _soundEffectProvider = SoundEffectProvider()..initialize();
    _appState = AppState();
    _appState.initialize();
    _router = _createRouter();
  }

  GoRouter _createRouter() {
    return GoRouter(
      initialLocation: '/splash',
      refreshListenable: _appState,
      routes: [
        GoRoute(
          path: '/splash',
          pageBuilder: (context, state) =>
              _buildRouterPage(context, state, LoadingHome()),
        ),
        GoRoute(
          path: '/login',
          pageBuilder: (context, state) =>
              _buildRouterPage(context, state, LoginHome()),
        ),
        GoRoute(
          path: '/register',
          pageBuilder: (context, state) =>
              _buildRouterPage(context, state, RegisterHome()),
        ),
        GoRoute(path: '/home', redirect: (context, state) => '/home/files'),
        GoRoute(
          path: '/home/:tab',
          pageBuilder: (context, state) {
            final tabParam = state.pathParameters['tab'] ?? 'files';
            final initialTab = switch (tabParam) {
              'files' => MainTab.files,
              'shares' => MainTab.shares,
              'settings' => MainTab.settings,
              _ => MainTab.overview,
            };
            return _buildRouterPage(
              context,
              state,
              MainHome(initialTab: initialTab),
              pageKey: const ValueKey('main-home-shell'),
            );
          },
        ),
      ],
      redirect: (context, state) {
        final initializing = !_appState.isInitialized;
        final location = state.matchedLocation;
        if (initializing) {
          return location == '/splash' ? null : '/splash';
        }

        final loggedIn = _appState.isLoggedIn;
        final goingToLogin = location == '/login';
        final goingToRegister = location == '/register';
        final goingHome = location.startsWith('/home');

        if (!loggedIn) {
          if (goingToLogin || goingToRegister) {
            return null;
          }
          return '/login';
        }

        if (goingToLogin || goingToRegister || location == '/splash') {
          return '/home/overview';
        }

        if (location == '/home') {
          return '/home/overview';
        }

        if (!goingHome) {
          return '/home/overview';
        }

        return null;
      },
    );
  }

  Page<void> _buildRouterPage(
    BuildContext context,
    GoRouterState state,
    Widget child, {
    LocalKey? pageKey,
  }) {
    final style = context.read<PageTransitionProvider>().style;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : style.duration;
    return CustomTransitionPage<void>(
      key: pageKey ?? state.pageKey,
      opaque: true,
      child: child,
      transitionDuration: duration,
      reverseTransitionDuration: duration,
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

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _darkModeProvider),
        ChangeNotifierProvider.value(value: _pageTransitionProvider),
        ChangeNotifierProvider.value(value: _soundEffectProvider),
        ChangeNotifierProvider.value(value: _appState),
      ],
      child:
          Consumer3<
            DarkModeProvider,
            SoundEffectProvider,
            PageTransitionProvider
          >(
            builder:
                (
                  context,
                  darkModeProvider,
                  soundEffectProvider,
                  pageTransitionProvider,
                  _,
                ) {
                  final darkMode = darkModeProvider.darkMode;
                  final enableFeedback = soundEffectProvider.enabled;
                  final pageTransitionStyle = pageTransitionProvider.style;
                  final lightTheme = CloudreveTheme.light(
                    enableFeedback: enableFeedback,
                    pageTransitionStyle: pageTransitionStyle,
                  );
                  final darkTheme = CloudreveTheme.dark(
                    enableFeedback: enableFeedback,
                    pageTransitionStyle: pageTransitionStyle,
                  );
                  ThemeMode themeMode;
                  switch (darkMode) {
                    case DarkMode.auto:
                      themeMode = ThemeMode.system;
                      break;
                    case DarkMode.open:
                      themeMode = ThemeMode.dark;
                      break;
                    case DarkMode.close:
                      themeMode = ThemeMode.light;
                      break;
                  }
                  return MaterialApp.router(
                    title: AppConfig.appName,
                    debugShowCheckedModeBanner: false,
                    theme: lightTheme,
                    darkTheme: darkTheme,
                    themeMode: themeMode,
                    builder: (context, child) => ColoredBox(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      child: child ?? const SizedBox.shrink(),
                    ),
                    routerConfig: _router,
                  );
                },
          ),
    );
  }
}
