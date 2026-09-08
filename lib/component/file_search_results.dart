import 'dart:async';

import 'package:cloudreve/component/file_visual.dart';
import 'package:cloudreve/entity/m_file.dart';
import 'package:cloudreve/state/page_transition_provider.dart';
import 'package:cloudreve/state/sound_effect_provider.dart';
import 'package:cloudreve/theme/app_theme.dart';
import 'package:cloudreve/utils/cloudreve_repository.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class FileSearchResults extends StatefulWidget {
  const FileSearchResults({
    super.key,
    required this.query,
    required this.onOpen,
    this.submitted = false,
    this.refreshVersion = 0,
  });
  final String query;
  final bool submitted;
  final int refreshVersion;
  final ValueChanged<MFile> onOpen;
  @override
  State<FileSearchResults> createState() => _FileSearchResultsState();
}

class _FileSearchResultsState extends State<FileSearchResults> {
  Timer? _debounce;
  int _generation = 0;
  FileListing? _listing;
  Object? _error;
  String get _query => widget.query.trim();

  @override
  void initState() {
    super.initState();
    _schedule(initial: true);
  }

  @override
  void didUpdateWidget(covariant FileSearchResults oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshVersion != widget.refreshVersion) {
      _schedule(forceRefresh: true);
    } else if (oldWidget.query.trim() != _query) {
      _schedule();
    } else if (widget.submitted &&
        !oldWidget.submitted &&
        _debounce?.isActive == true) {
      _debounce?.cancel();
      _load(_generation, _query);
    }
  }

  void _schedule({bool initial = false, bool forceRefresh = false}) {
    _debounce?.cancel();
    final generation = ++_generation;
    final query = _query;
    _error = null;
    _listing = forceRefresh ? null : CloudreveRepository.peekSearch(query);
    if (!initial) setState(() {});
    if (_listing != null) return;
    if (forceRefresh || widget.submitted || query.isEmpty) {
      _load(generation, query, forceRefresh: forceRefresh);
    } else {
      _debounce = Timer(
        const Duration(milliseconds: 320),
        () => _load(generation, query),
      );
    }
  }

  Future<void> _load(
    int generation,
    String query, {
    bool forceRefresh = false,
  }) async {
    try {
      final listing = await CloudreveRepository.search(
        query,
        forceRefresh: forceRefresh,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _listing = listing;
        _error = null;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    _generation++;
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animate =
        !MediaQuery.disableAnimationsOf(context) &&
        context.watch<PageTransitionProvider?>()?.style !=
            PageTransitionStyle.none;
    final listing = _listing;
    final Widget body;
    if (_error != null) {
      body = _SearchState(
        key: const ValueKey('search-error'),
        icon: Icons.cloud_off_rounded,
        title: '文件加载失败',
        subtitle: '请检查网络连接后重试',
        action: TextButton.icon(
          onPressed: () => _schedule(forceRefresh: true),
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('重新加载'),
        ),
      );
    } else if (listing == null) {
      body = const FileSearchSkeleton(key: ValueKey('search-loading'));
    } else if (listing.files.isEmpty) {
      body = _SearchState(
        key: ValueKey('search-empty:$_query'),
        icon: _query.isEmpty
            ? Icons.folder_open_rounded
            : Icons.search_off_rounded,
        title: _query.isEmpty ? '还没有文件' : '没有找到相关文件',
        subtitle: _query.isEmpty ? '输入名称搜索你的文件' : '试试更短的关键词',
      );
    } else {
      body = _results(listing);
    }
    return ClipRect(
      child: AnimatedSwitcher(
        duration: animate ? const Duration(milliseconds: 200) : Duration.zero,
        reverseDuration: animate
            ? const Duration(milliseconds: 100)
            : Duration.zero,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeOut,
        layoutBuilder: (current, previous) => Stack(
          fit: StackFit.expand,
          children: [
            for (final child in previous) IgnorePointer(child: child),
            ?current,
          ],
        ),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: animation.drive(
              Tween(begin: const Offset(0, 0.018), end: Offset.zero),
            ),
            child: RepaintBoundary(child: child),
          ),
        ),
        child: body,
      ),
    );
  }

  Widget _results(FileListing listing) => RefreshIndicator(
    key: ValueKey('search-ready:$_query'),
    onRefresh: () async {
      _debounce?.cancel();
      await _load(++_generation, _query, forceRefresh: true);
    },
    child: ListView.builder(
      key: PageStorageKey('search-list:$_query'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
      itemCount: listing.files.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _query.isEmpty ? '我的文件' : '搜索结果',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  '${listing.files.length} 项',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );
        }
        final file = listing.files[index - 1];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: CloudrevePanel(
            padding: EdgeInsets.zero,
            child: Material(
              type: MaterialType.transparency,
              borderRadius: BorderRadius.circular(22),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
                enableFeedback:
                    context.watch<SoundEffectProvider?>()?.enabled ?? true,
                leading: FileIconBadge(file: file, size: 44),
                title: Text(
                  file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '${file.type == 'dir' ? '文件夹' : file.displaySize} · ${file.getFormatDate()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                onTap: () => widget.onOpen(file),
              ),
            ),
          ),
        );
      },
    ),
  );
}

class FileSearchSkeleton extends StatefulWidget {
  const FileSearchSkeleton({super.key});
  @override
  State<FileSearchSkeleton> createState() => _FileSearchSkeletonState();
}

class _FileSearchSkeletonState extends State<FileSearchSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final enabled =
        !MediaQuery.disableAnimationsOf(context) &&
        context.watch<PageTransitionProvider?>()?.style !=
            PageTransitionStyle.none;
    if (enabled) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 0.5;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface
        .withValues(alpha: 0.12);
    Widget block(double width, double height, {double radius = 8}) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
    return Semantics(
      label: '正在加载文件',
      liveRegion: true,
      child: ExcludeSemantics(
        child: IgnorePointer(
          child: AnimatedBuilder(
            animation: _pulse,
            builder: (_, child) =>
                Opacity(opacity: 0.55 + _pulse.value * 0.45, child: child),
            child: ListView(
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 24),
              children: [
                Align(alignment: Alignment.centerLeft, child: block(80, 16)),
                const SizedBox(height: 20),
                for (var index = 0; index < 6; index++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: CloudrevePanel(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 16,
                      ),
                      child: Row(
                        children: [
                          block(44, 44, radius: 14),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                FractionallySizedBox(
                                  widthFactor: index.isEven ? 0.78 : 0.6,
                                  child: block(double.infinity, 14),
                                ),
                                const SizedBox(height: 10),
                                FractionallySizedBox(
                                  widthFactor: 0.48,
                                  child: block(double.infinity, 10),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchState extends StatelessWidget {
  const _SearchState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 18),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 12), action!],
        ],
      ),
    ),
  );
}
