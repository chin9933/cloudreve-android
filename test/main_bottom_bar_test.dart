import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String source;

  setUpAll(() {
    source = File('lib/app/main_home.dart').readAsStringSync();
  });

  String section(String start, String end) {
    final startIndex = source.indexOf(start);
    final endIndex = source.indexOf(end, startIndex + start.length);
    expect(startIndex, greaterThanOrEqualTo(0), reason: 'missing $start');
    expect(endIndex, greaterThan(startIndex), reason: 'missing $end');
    return source.substring(startIndex, endIndex);
  }

  test('create action is integrated into five equal bottom-bar regions', () {
    final scaffold = section('child: Scaffold(', 'String get _pageTitle');
    final bottomBar = section('Widget _buildBottomBar()', 'void _showSearch()');
    final navButton = section(
      'class _BottomNavButton',
      'class _BottomCreateButton',
    );
    final createButton = section(
      'class _BottomCreateButton',
      'class _CreateActionCard',
    );

    // The upload/create action belongs to the bar itself, rather than a
    // center-docked FAB that floats over and hides page content.
    expect(scaffold, contains('extendBody: false'));
    expect(scaffold, isNot(contains('floatingActionButton:')));
    expect(scaffold, isNot(contains('floatingActionButtonLocation:')));
    expect(bottomBar, contains("key: const Key('main-bottom-bar')"));

    // Four navigation destinations plus the central create action form five
    // direct Row children. Both child types return Expanded with the default
    // flex of 1, so every region receives the same horizontal width.
    expect(RegExp(r'_BottomNavButton\(').allMatches(bottomBar), hasLength(4));
    expect(
      RegExp(r'_BottomCreateButton\(').allMatches(bottomBar),
      hasLength(1),
    );
    expect(navButton, contains('return Expanded('));
    expect(createButton, contains('return Expanded('));
    expect(navButton, isNot(contains('flex:')));
    expect(createButton, isNot(contains('flex:')));

    // Keep the compact dimensions that prevent the bar from obscuring the
    // last row of content while preserving comfortable touch regions.
    expect(bottomBar, contains('return ClipRect('));
    expect(bottomBar, contains("key: const Key('main-bottom-mask')"));
    expect(bottomBar, contains('child: ColoredBox('));
    expect(bottomBar, contains('color: theme.scaffoldBackgroundColor'));
    expect(
      bottomBar,
      contains('minimum: const EdgeInsets.fromLTRB(12, 9, 12, 5)'),
    );
    expect(bottomBar, contains('elevation: 6'));
    expect(
      bottomBar,
      contains('shadowColor: Colors.black.withValues(alpha: 0.12)'),
    );
    expect(bottomBar, contains('borderRadius: BorderRadius.circular(24)'));
    expect(bottomBar, contains('height: 68'));
    expect(navButton, contains('Icon(icon, color: color, size: 23)'));
    expect(navButton, contains('fontSize: 10.5'));
    expect(createButton, contains('dimension: 52'));
    expect(createButton, contains('size: 30'));
    expect(bottomBar, isNot(contains('height: 78')));
    expect(
      bottomBar,
      isNot(contains('minimum: const EdgeInsets.fromLTRB(12, 3, 12, 5)')),
    );
    expect(bottomBar, isNot(contains('elevation: 10')));
    expect(createButton, isNot(contains('dimension: 58')));
  });

  test('central plus remains tappable and opens create choices', () {
    final bottomBar = section('Widget _buildBottomBar()', 'void _showSearch()');
    final createButton = section(
      'class _BottomCreateButton',
      'class _CreateActionCard',
    );
    final createActions = section(
      'void _showCreateActions()',
      'void _newFold()',
    );

    expect(
      bottomBar,
      contains('_BottomCreateButton(onTap: _showCreateActions)'),
    );
    expect(createButton, contains("key: const Key('bottom-create-button')"));
    expect(createButton, contains('onTap: onTap'));
    expect(createButton, contains('Icons.add_rounded'));
    expect(createActions, contains("'上传文件'"));
    expect(createActions, contains("'新建文件夹'"));
  });
}
