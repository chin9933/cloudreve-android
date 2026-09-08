import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _source(String relativePath) => File(relativePath).readAsStringSync();

String _section(String source, String start, String end) {
  final startIndex = source.indexOf(start);
  final endIndex = source.indexOf(end, startIndex + start.length);
  expect(startIndex, greaterThanOrEqualTo(0), reason: 'missing $start');
  expect(endIndex, greaterThan(startIndex), reason: 'missing $end');
  return source.substring(startIndex, endIndex);
}

void main() {
  test('file page no longer renders the redundant root breadcrumb', () {
    final home = _source('lib/view/files_page.dart');

    expect(home, isNot(contains("'当前位置'")));
    expect(home, isNot(contains("'全部文件'")));
  });

  test('file title is left aligned and search only lives in the top bar', () {
    final mainHome = _source('lib/app/main_home.dart');
    final home = _source('lib/view/files_page.dart');
    final scaffold = _section(
      mainHome,
      'child: Scaffold(',
      'String get _pageTitle',
    );
    final topActions = _section(
      mainHome,
      'List<Widget> _buildTopActions()',
      'Widget _buildBottomBar()',
    );
    final fileActions = _section(
      topActions,
      'if (_selectedIndex == 1)',
      'if (_selectedIndex == 2)',
    );
    final homeConstruction = _section(scaffold, 'Home(', 'Share(orderBy:');

    // Explicit false keeps Android and iOS aligned and prevents the file tab
    // from being the only centered title.
    expect(scaffold, contains('centerTitle: false'));
    expect(scaffold, isNot(contains('centerTitle: _selectedIndex == 1')));

    expect(fileActions, contains('icon: Icons.search_rounded'));
    expect(fileActions, contains("tooltip: '搜索'"));
    expect(fileActions, contains('onPressed: _showSearch'));
    expect(RegExp(r'_TopIconButton\(').allMatches(fileActions), hasLength(1));
    expect(fileActions, isNot(contains("tooltip: '切换显示模式'")));

    // Home must not keep a second, permanently visible search affordance.
    expect(home, isNot(contains('VoidCallback? onSearch')));
    expect(home, isNot(contains('this.onSearch')));
    expect(home, isNot(contains('widget.onSearch')));
    expect(home, isNot(contains("'搜索文件'")));
    expect(homeConstruction, isNot(contains('onSearch:')));
  });

  test('profile app-settings entry has no explanatory subtitle', () {
    final setting = _source('lib/view/profile_page.dart');
    final titleIndex = setting.indexOf("title: '应用设置'");
    final tapIndex = setting.indexOf('onTap:', titleIndex);

    expect(titleIndex, greaterThanOrEqualTo(0));
    expect(tapIndex, greaterThan(titleIndex));
    expect(
      setting.substring(titleIndex, tapIndex),
      isNot(contains('subtitle:')),
    );
  });

  test('all main tabs share one root bottom mask', () {
    final mainHome = _source('lib/app/main_home.dart');
    final scaffold = _section(
      mainHome,
      'child: Scaffold(',
      'String get _pageTitle',
    );
    final bottomBar = _section(
      mainHome,
      'Widget _buildBottomBar()',
      'void _showSearch()',
    );

    // A single root Scaffold reserves the same bottom region for every child
    // in the IndexedStack. Individual tabs must not grow their own navigation
    // bar or rely on a floating control that obscures scrollable content.
    expect(scaffold, contains('body: _AnimatedMainTabStack('));
    expect(scaffold, contains('DashboardHome('));
    expect(scaffold, contains('Home('));
    expect(scaffold, contains('Share(orderBy:'));
    expect(scaffold, contains('Setting(userData:'));
    expect(scaffold, contains('bottomNavigationBar: _buildBottomBar()'));
    expect(RegExp(r'bottomNavigationBar:').allMatches(mainHome), hasLength(1));
    expect(scaffold, contains('extendBody: false'));
    expect(scaffold, isNot(contains('extendBody: true')));
    expect(scaffold, isNot(contains('floatingActionButton:')));

    expect(bottomBar, contains('return ClipRect('));
    expect(bottomBar, contains("key: const Key('main-bottom-mask')"));
    expect(bottomBar, contains('child: ColoredBox('));
    expect(bottomBar, contains('color: theme.scaffoldBackgroundColor'));
    expect(bottomBar, contains('child: SafeArea('));
    expect(bottomBar, contains('top: false'));
    expect(
      bottomBar,
      contains('minimum: const EdgeInsets.fromLTRB(12, 9, 12, 5)'),
    );
    expect(bottomBar, contains("key: const Key('main-bottom-bar')"));
    expect(bottomBar, contains('height: 68'));

    final theme = _source('lib/theme/app_theme.dart');
    expect(theme, contains('static const pageBottomInset = 24.0'));

    final pageUses = <String, int>{
      'lib/view/dashboard_home.dart': 1,
      'lib/view/files_page.dart': 3,
      'lib/view/shares_page.dart': 4,
      'lib/view/profile_page.dart': 1,
    };
    for (final entry in pageUses.entries) {
      final source = _source(entry.key);
      expect(
        source,
        isNot(contains('bottomNavigationBar:')),
        reason: entry.key,
      );
      expect(
        source,
        isNot(contains('floatingActionButton:')),
        reason: entry.key,
      );
      expect(
        RegExp(r'CloudreveTheme\.pageBottomInset').allMatches(source),
        hasLength(entry.value),
        reason: entry.key,
      );
    }
  });

  test('settings rows do not render explanatory subtitles', () {
    final settings = _source('lib/view/app_settings_page.dart');
    final mainSettings = _section(
      settings,
      'class AppSettingsPage extends StatelessWidget',
      'class _ChangePasswordSheet',
    );

    expect(mainSettings, isNot(contains('subtitle:')));
    for (final obsoleteCopy in <String>[
      '需要验证当前密码',
      '跟随系统、浅色或深色模式',
      '操作反馈音，不影响音乐和视频播放',
      '版本、软件标识与开源许可',
    ]) {
      expect(mainSettings, isNot(contains(obsoleteCopy)));
    }
  });

  test('selected transition style drives both main tabs and routed pages', () {
    final mainHome = _source('lib/app/main_home.dart');
    final app = _source('lib/main.dart');
    final theme = _source('lib/theme/app_theme.dart');
    final scaffold = _section(
      mainHome,
      'child: Scaffold(',
      'String get _pageTitle',
    );
    final animatedStack = _section(
      mainHome,
      'class _AnimatedMainTabStack',
      'class CompareFunction',
    );

    expect(
      scaffold,
      contains('style: context.watch<PageTransitionProvider>().style'),
    );
    expect(
      animatedStack,
      contains('class _AnimatedMainTabStack extends StatefulWidget'),
    );
    expect(
      animatedStack,
      contains(
        'class _AnimatedMainTabStackState '
        'extends State<_AnimatedMainTabStack>',
      ),
    );
    expect(
      animatedStack,
      contains('late final AnimationController _controller'),
    );
    expect(animatedStack, contains('final PageTransitionStyle style'));
    expect(
      animatedStack,
      contains('_disableAnimations ? Duration.zero : widget.style.duration'),
    );
    expect(animatedStack, contains('child: Opacity('));
    expect(animatedStack, contains('child: FractionalTranslation('));
    expect(animatedStack, contains('child: Transform.scale('));
    expect(animatedStack, contains('children: List<Widget>.generate('));
    expect(animatedStack, contains("ValueKey('main-tab-layer-\$childIndex')"));
    expect(animatedStack, contains('child: widget.children[childIndex]'));
    expect(
      animatedStack,
      contains('widget.style == PageTransitionStyle.slide'),
    );
    expect(
      animatedStack,
      contains('selected && widget.style == PageTransitionStyle.scale'),
    );
    expect(animatedStack, contains('TickerMode('));
    expect(animatedStack, contains('IgnorePointer('));

    expect(app, contains('PageTransitionProvider()..initialize()'));
    expect(
      app,
      contains('ChangeNotifierProvider.value(value: _pageTransitionProvider)'),
    );
    expect(app, contains('final pageTransitionStyle ='));
    expect(
      RegExp(r'pageTransitionStyle: pageTransitionStyle').allMatches(app),
      hasLength(2),
    );

    expect(
      RegExp(r'pageTransitionsTheme: _pageTransitions\(pageTransitionStyle\)')
          .allMatches(theme),
      hasLength(2),
    );
    expect(theme, contains('CloudrevePageTransitionsBuilder(style)'));
    expect(theme, contains('PageTransitionStyle.none => child'));
    expect(theme, contains('PageTransitionStyle.fade => faded'));
    expect(theme, contains('PageTransitionStyle.slide => ClipRect('));
    expect(theme, contains('PageTransitionStyle.scale => ClipRect('));
    expect(RegExp(r'child: faded').allMatches(theme), hasLength(1));
    expect(theme, contains('begin: const Offset(1, 0)'));
    expect(theme, isNot(contains('final curved = CurvedAnimation(')));
    expect(RegExp(r'child: child').allMatches(theme), isNotEmpty);
    expect(RegExp(r'opaque: true').allMatches(app), hasLength(1));
    expect(theme, contains('opaque: true'));
    expect(app, contains('color: Theme.of(context).scaffoldBackgroundColor'));
  });

  test('settled main-tab animation paints only the current retained page', () {
    final mainHome = _source('lib/app/main_home.dart');
    final app = _source('lib/main.dart');
    final animatedStack = _section(
      mainHome,
      'class _AnimatedMainTabStack',
      'class CompareFunction',
    );
    final layer = _section(
      mainHome,
      'Widget _buildLayer(int childIndex)',
      'class CompareFunction',
    );

    // The previous index remains available only to calculate slide direction.
    // It must never keep the outgoing file page in the paint pass.
    expect(animatedStack, contains('int? _previousIndex'));
    expect(
      animatedStack,
      contains(
        'if (status != AnimationStatus.completed || '
        '_previousIndex == null)',
      ),
    );
    expect(animatedStack, contains('setState(() => _previousIndex = null)'));
    expect(
      layer,
      isNot(
        contains('childIndex == _previousIndex && _controller.isAnimating'),
      ),
    );

    // Offstage is outside the opacity and transform widgets. Once `selected`
    // is false Flutter retains the child Element/State but does not visit its
    // Opacity or Transform subtree during paint, preventing stale GPU layers.
    expect(layer, contains("key: ValueKey('main-tab-offstage-\$childIndex')"));
    expect(layer, contains('offstage: !selected'));
    expect(
      layer.indexOf('child: Offstage('),
      lessThan(layer.indexOf('child: Opacity(')),
    );
    expect(
      layer.indexOf('child: Opacity('),
      lessThan(layer.indexOf('child: FractionalTranslation(')),
    );
    expect(
      layer.indexOf('child: FractionalTranslation('),
      lessThan(layer.indexOf('child: Transform.scale(')),
    );

    // Every keyed page remains in the fixed stack and keeps its existing
    // subtree/state while the root shell key prevents a second route-level
    // transition from replacing MainHome during bottom-tab navigation.
    expect(
      animatedStack,
      contains("key: ValueKey('main-tab-layer-\$childIndex')"),
    );
    expect(animatedStack, contains('widget.children[childIndex]'));
    expect(app, contains("pageKey: const ValueKey('main-home-shell')"));
  });

  test('file and share sorting reuse one top-bar menu component', () {
    final mainHome = _source('lib/app/main_home.dart');
    final topActions = _section(
      mainHome,
      'List<Widget> _buildTopActions()',
      'Widget _buildBottomBar()',
    );
    final sortComponent = _section(
      mainHome,
      'class _TopSortMenuButton<T>',
      'class _BottomNavButton',
    );
    final sortItems = _section(
      sortComponent,
      '...items.map((item)',
      'onSelected: onSelected',
    );

    expect(RegExp(r'_TopSortMenuButton<').allMatches(topActions), hasLength(2));
    expect(topActions, contains("key: const Key('file-sort-menu')"));
    expect(topActions, contains("key: const Key('share-sort-menu')"));
    expect(topActions, contains('mode: _mode'));
    expect(topActions, contains('onToggleMode: ()'));

    // Feature branches only configure the reusable menu; the sole raw popup
    // implementation is kept inside that shared component.
    expect(topActions, isNot(contains('PopupMenuButton<')));
    expect(RegExp(r'PopupMenuButton<').allMatches(mainHome), hasLength(1));
    expect(sortComponent, contains('return PopupMenuButton<T>('));
    expect(sortComponent, contains("this.tooltip = '排序方式'"));
    expect(sortComponent, contains('tooltip: tooltip'));
    expect(sortComponent, contains('Icons.more_horiz_rounded'));
    expect(sortComponent, contains('onSelected: onSelected'));
    expect(sortComponent, contains('dimension: 48'));
    expect(sortComponent, contains('dimension: 42'));

    // Do not let PopupMenuButton paint its built-in grey selected row. The
    // shared component owns a quieter selected treatment and keeps every row
    // text-only, without leading sort/check glyphs.
    expect(sortComponent, isNot(contains('initialValue:')));
    expect(sortItems, isNot(contains('Icon(')));
    expect(sortItems, isNot(contains('Icons.check_rounded')));
    expect(sortItems, isNot(contains('Icons.swap_vert_rounded')));
    expect(sortItems, contains('colors.primary.withValues(alpha: 0.1)'));
    expect(sortItems, contains('colors.primary.withValues(alpha: 0.2)'));
    expect(
      sortItems,
      contains('color: selected ? colors.primary : colors.onSurface'),
    );

    // Layout switching is an action inside the file overflow menu, rather
    // than another permanent AppBar button.
    expect(sortComponent, contains("key: const Key('file-view-mode-action')"));
    expect(sortComponent, contains("'切换为网格视图'"));
    expect(sortComponent, contains("'切换为列表视图'"));
    expect(sortComponent, contains('onTap: onToggleMode'));
  });

  test('profile account rows share the profile text start line', () {
    final setting = _source('lib/view/profile_page.dart');
    final divider = _section(
      setting,
      'class _InsetDivider',
      'class _SettingsRow',
    );
    final settingsRow = setting.substring(
      setting.indexOf('class _SettingsRow'),
    );

    expect(RegExp(r'alignWithProfile: true').allMatches(setting), hasLength(4));
    expect(settingsRow, contains('width: 74'));
    expect(
      settingsRow,
      contains('SizedBox(width: alignWithProfile ? 18 : 12)'),
    );
    expect(settingsRow, contains('SizedBox(width: 60, child: titleBlock)'));
    expect(settingsRow, contains('const SizedBox(width: 8)'));
    expect(settingsRow, contains('width: 26'));
    expect(settingsRow, contains('textAlign: TextAlign.start'));
    expect(divider, contains('indent: 104'));
  });
}
