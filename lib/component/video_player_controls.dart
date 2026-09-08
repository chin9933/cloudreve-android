import 'dart:async';

import 'package:cloudreve/theme/app_theme.dart';
import 'package:cloudreve/utils/video_device_controls.dart';
import 'package:cloudreve/utils/video_gesture_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const videoPlaybackRates = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

String videoRateLabel(double rate) =>
    '${rate == rate.roundToDouble() ? rate.toStringAsFixed(1) : rate.toString()}×';

String videoTimeLabel(Duration duration) {
  final seconds = duration.inSeconds.clamp(0, 1 << 40);
  final minutes = (seconds ~/ 60) % 60;
  final tail =
      '${minutes.toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  return seconds >= 3600 ? '${seconds ~/ 3600}:$tail' : tail;
}

/// Presentation state shared by embedded and fullscreen controls.
@immutable
class VideoPlaybackSnapshot {
  const VideoPlaybackSnapshot({
    this.opening = true,
    this.buffering = false,
    this.playing = false,
    this.completed = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.buffer = Duration.zero,
    this.rate = 1,
    this.error,
  });
  final bool opening, buffering, playing, completed;
  final Duration position, duration, buffer;
  final double rate;
  final String? error;
  bool get loading => error == null && (opening || buffering);
  bool get canSeek => !opening && error == null && duration > Duration.zero;

  VideoPlaybackSnapshot copyWith({
    bool? opening,
    bool? buffering,
    bool? playing,
    bool? completed,
    Duration? position,
    Duration? duration,
    Duration? buffer,
    double? rate,
    String? error,
  }) => VideoPlaybackSnapshot(
    opening: opening ?? this.opening,
    buffering: buffering ?? this.buffering,
    playing: playing ?? this.playing,
    completed: completed ?? this.completed,
    position: position ?? this.position,
    duration: duration ?? this.duration,
    buffer: buffer ?? this.buffer,
    rate: rate ?? this.rate,
    error: error ?? this.error,
  );
}

/// App-owned controls: the decoder's default controls/spinner are not mounted.
class VideoPlayerControls extends StatefulWidget {
  const VideoPlayerControls({
    super.key,
    required this.state,
    required this.onToggle,
    required this.onSeek,
    required this.onRate,
    required this.onFullscreen,
    required this.onRetry,
    this.onReadLevels,
    this.onBrightness,
    this.onVolume,
    this.fullscreen = false,
    this.title = '',
  });
  final ValueListenable<VideoPlaybackSnapshot> state;
  final Future<void> Function() onToggle, onFullscreen, onRetry;
  final Future<void> Function(Duration) onSeek;
  final Future<void> Function(double) onRate;
  final Future<VideoDeviceLevels> Function()? onReadLevels;
  final Future<double> Function(double)? onBrightness, onVolume;
  final bool fullscreen;
  final String title;
  @override
  State<VideoPlayerControls> createState() => _VideoPlayerControlsState();
}

class _VideoPlayerControlsState extends State<VideoPlayerControls> {
  Timer? _hideTimer;
  Timer? _lockHideTimer;
  bool _lockVisible = false;
  Offset _panDelta = Offset.zero;
  Offset _panOrigin = Offset.zero;
  VideoGestureAxis _panAxis = VideoGestureAxis.pending;
  bool _visible = true;
  bool _menuOpen = false;
  bool _locked = false;
  late final VideoGestureController _deviceGesture;
  double? _drag;
  late VideoPlaybackSnapshot _last = widget.state.value;
  double _doubleTapX = 0;

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_onState);
    _deviceGesture = VideoGestureController(
      readLevels: () => widget.onReadLevels!(),
      setBrightness: (value) => widget.onBrightness!(value),
      setVolume: (value) => widget.onVolume!(value),
    )..addListener(_onDeviceGesture);
  }

  @override
  void didUpdateWidget(covariant VideoPlayerControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fullscreen && !widget.fullscreen) {
      _locked = false;
      _lockVisible = false;
      _lockHideTimer?.cancel();
      _visible = true;
      _deviceGesture.cancel();
    }
    if (oldWidget.state != widget.state) {
      oldWidget.state.removeListener(_onState);
      widget.state.addListener(_onState);
      _last = widget.state.value;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _armHide();
  }

  void _onState() {
    final next = widget.state.value;
    if (!mounted) return;
    if (_locked) {
      _hideTimer?.cancel();
    } else if (next.loading ||
        !next.playing ||
        next.completed ||
        next.error != null) {
      _hideTimer?.cancel();
      if (!_visible) setState(() => _visible = true);
    } else if (next.playing != _last.playing || next.loading != _last.loading) {
      _armHide();
    }
    _last = next;
  }

  void _armHide() {
    _hideTimer?.cancel();
    final data = widget.state.value;
    if (_locked ||
        _menuOpen ||
        _drag != null ||
        !data.playing ||
        data.loading ||
        data.error != null ||
        MediaQuery.maybeOf(context)?.accessibleNavigation == true) {
      return;
    }
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  void _show() {
    if (_locked) return;
    setState(() => _visible = true);
    _armHide();
    if (_lockVisible) _armLockHide();
  }

  void _armLockHide() {
    _lockHideTimer?.cancel();
    _lockHideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _lockVisible = false);
    });
  }

  void _tapSurface() {
    setState(() {
      if (!_locked) _visible = !_visible;
      if (widget.fullscreen) _lockVisible = true;
    });
    if (widget.fullscreen) _armLockHide();
    _armHide();
  }

  void _startPan(DragStartDetails details) {
    _panOrigin = details.localPosition;
    _panDelta = Offset.zero;
    _panAxis = VideoGestureAxis.pending;
  }

  void _updatePan(DragUpdateDetails details, BoxConstraints constraints) {
    _panDelta += details.delta;
    if (_panAxis == VideoGestureAxis.horizontal) return;
    if (_panAxis == VideoGestureAxis.pending) {
      _panAxis = videoGestureAxis(_panDelta.dx, _panDelta.dy);
      if (_panAxis != VideoGestureAxis.vertical) return;
      _hideTimer?.cancel();
      _deviceGesture.start(
        brightness: _panOrigin.dx < constraints.maxWidth / 2,
        height: constraints.maxHeight,
      );
      _deviceGesture.update(_panDelta.dy);
    } else {
      _deviceGesture.update(details.delta.dy);
    }
  }

  void _endPan() {
    if (_panAxis == VideoGestureAxis.vertical) {
      _deviceGesture.end();
      _armHide();
    }
    _panAxis = VideoGestureAxis.pending;
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(const SnackBar(content: Text('播放操作未完成，请重试')));
      }
    }
  }

  void _seekBy(int seconds) {
    if (_locked) return;
    final data = widget.state.value;
    if (!data.canSeek) return;
    final target = (data.position.inMilliseconds + seconds * 1000).clamp(
      0,
      data.duration.inMilliseconds,
    );
    _show();
    _run(() => widget.onSeek(Duration(milliseconds: target)));
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _lockHideTimer?.cancel();
    _deviceGesture.removeListener(_onDeviceGesture);
    _deviceGesture.dispose();
    widget.state.removeListener(_onState);
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<VideoPlaybackSnapshot>(
    valueListenable: widget.state,
    builder: (context, data, _) {
      final colors = Theme.of(context).colorScheme;
      final shown =
          !_locked &&
          (_visible || data.loading || !data.playing || data.error != null);
      final gesturesEnabled =
          widget.fullscreen &&
          !_locked &&
          widget.onReadLevels != null &&
          widget.onBrightness != null &&
          widget.onVolume != null;
      return Focus(
        autofocus: true,
        onKeyEvent: (_, event) {
          if (_locked || event is! KeyDownEvent) {
            return KeyEventResult.ignored;
          }
          if (event.logicalKey == LogicalKeyboardKey.space &&
              !data.opening &&
              data.error == null) {
            _show();
            _run(widget.onToggle);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _seekBy(-10);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            _seekBy(10);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: ClipRect(
          child: LayoutBuilder(
            builder: (context, constraints) => Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  key: const Key('video-gesture-surface'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _tapSurface,
                  onDoubleTapDown: _locked
                      ? null
                      : (details) => _doubleTapX = details.localPosition.dx,
                  onDoubleTap: _locked
                      ? null
                      : () => _seekBy(
                          _doubleTapX < constraints.maxWidth / 2 ? -10 : 10,
                        ),
                  dragStartBehavior: DragStartBehavior.down,
                  onPanStart: gesturesEnabled ? _startPan : null,
                  onPanUpdate: gesturesEnabled
                      ? (details) => _updatePan(details, constraints)
                      : null,
                  onPanEnd: gesturesEnabled ? (_) => _endPan() : null,
                  onPanCancel: gesturesEnabled ? _deviceGesture.cancel : null,
                ),
                if (data.loading || data.error != null)
                  Positioned.fill(
                    bottom: _locked
                        ? 0
                        : constraints.maxWidth < 335 ||
                              MediaQuery.textScalerOf(context).scale(14) > 17
                        ? 210
                        : 154,
                    child: IgnorePointer(
                      ignoring: _locked,
                      child: VideoPlaybackStatus(
                        data: data,
                        onRetry: () => _run(widget.onRetry),
                      ),
                    ),
                  ),
                if (widget.fullscreen && shown)
                  Positioned(
                    left: 16,
                    top: 12,
                    right: 76,
                    child: SafeArea(
                      bottom: false,
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          shadows: [Shadow(blurRadius: 6, color: Colors.black)],
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: SafeArea(
                    top: false,
                    child: IgnorePointer(
                      ignoring: !shown,
                      child: ExcludeFocus(
                        excluding: !shown,
                        child: AnimatedOpacity(
                          key: const Key('video-controls-visibility'),
                          opacity: shown ? 1 : 0,
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 160),
                          child: Listener(
                            onPointerDown: (_) => _show(),
                            child: Material(
                              key: const Key('video-controls-panel'),
                              color: colors.surface,
                              elevation: 2,
                              shadowColor: Colors.black26,
                              surfaceTintColor: Colors.transparent,
                              clipBehavior: Clip.antiAlias,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(22),
                                side: BorderSide(
                                  color: colors.primary.withValues(alpha: .18),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  10,
                                  8,
                                  10,
                                  6,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                      ),
                                      child: Row(
                                        children: [
                                          Text(
                                            videoTimeLabel(
                                              Duration(
                                                milliseconds:
                                                    (_drag ??
                                                            data
                                                                .position
                                                                .inMilliseconds
                                                                .toDouble())
                                                        .round(),
                                              ),
                                            ),
                                            style: TextStyle(
                                              color: colors.onSurface,
                                              fontSize: 12,
                                              fontFeatures: const [
                                                FontFeature.tabularFigures(),
                                              ],
                                            ),
                                          ),
                                          const Spacer(),
                                          Text(
                                            videoTimeLabel(data.duration),
                                            style: TextStyle(
                                              color: colors.onSurfaceVariant,
                                              fontSize: 12,
                                              fontFeatures: const [
                                                FontFeature.tabularFigures(),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(
                                      height: 22,
                                      child: SliderTheme(
                                        data: SliderTheme.of(context).copyWith(
                                          trackHeight: 3,
                                          activeTrackColor: colors.primary,
                                          secondaryActiveTrackColor: colors
                                              .primary
                                              .withValues(alpha: .25),
                                          inactiveTrackColor: colors.onSurface
                                              .withValues(alpha: .1),
                                          thumbColor: colors.primary,
                                          overlayColor: colors.primary
                                              .withValues(alpha: .12),
                                          thumbShape:
                                              const RoundSliderThumbShape(
                                                enabledThumbRadius: 5,
                                              ),
                                          overlayShape:
                                              const RoundSliderOverlayShape(
                                                overlayRadius: 13,
                                              ),
                                        ),
                                        child: Slider(
                                          key: const Key('video-progress'),
                                          max: data.duration.inMilliseconds > 0
                                              ? data.duration.inMilliseconds
                                                    .toDouble()
                                              : 1,
                                          value:
                                              (_drag ??
                                                      data
                                                          .position
                                                          .inMilliseconds
                                                          .toDouble())
                                                  .clamp(
                                                    0,
                                                    data
                                                                .duration
                                                                .inMilliseconds >
                                                            0
                                                        ? data
                                                              .duration
                                                              .inMilliseconds
                                                              .toDouble()
                                                        : 1,
                                                  ),
                                          secondaryTrackValue: data
                                              .buffer
                                              .inMilliseconds
                                              .toDouble()
                                              .clamp(
                                                0,
                                                data.duration.inMilliseconds > 0
                                                    ? data
                                                          .duration
                                                          .inMilliseconds
                                                          .toDouble()
                                                    : 1,
                                              ),
                                          onChangeStart: data.canSeek
                                              ? (value) {
                                                  _hideTimer?.cancel();
                                                  setState(() => _drag = value);
                                                }
                                              : null,
                                          onChanged: data.canSeek
                                              ? (value) => setState(
                                                  () => _drag = value,
                                                )
                                              : null,
                                          onChangeEnd: data.canSeek
                                              ? (value) {
                                                  setState(() => _drag = null);
                                                  _run(
                                                    () => widget.onSeek(
                                                      Duration(
                                                        milliseconds: value
                                                            .round(),
                                                      ),
                                                    ),
                                                  );
                                                  _armHide();
                                                }
                                              : null,
                                        ),
                                      ),
                                    ),
                                    _buildTransport(data),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (widget.fullscreen && _deviceGesture.visible)
                  Positioned.fill(child: IgnorePointer(child: _deviceHud())),
                if (widget.fullscreen)
                  Positioned(
                    top: 0,
                    bottom: 0,
                    right: 8,
                    child: SafeArea(
                      left: false,
                      child: Center(child: _lockVisibility()),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );

  void _onDeviceGesture() {
    if (mounted) setState(() {});
  }

  Widget _lockVisibility() => IgnorePointer(
    ignoring: !_lockVisible,
    child: ExcludeFocus(
      excluding: !_lockVisible,
      child: ExcludeSemantics(
        excluding: !_lockVisible,
        child: AnimatedOpacity(
          key: const Key('video-lock-visibility'),
          opacity: _lockVisible ? 1 : 0,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 160),
          child: _lockButton(),
        ),
      ),
    ),
  );

  Widget _lockButton() {
    final colors = Theme.of(context).colorScheme;
    return IconButton.filled(
      key: const Key('video-screen-lock'),
      tooltip: _locked ? '解除锁定' : '锁定屏幕',
      isSelected: _locked,
      style: IconButton.styleFrom(
        backgroundColor: _locked ? colors.primary : colors.surface,
        foregroundColor: _locked ? colors.onPrimary : colors.onSurface,
        fixedSize: const Size(44, 44),
        shape: const CircleBorder(),
      ),
      onPressed: () {
        _deviceGesture.cancel();
        _hideTimer?.cancel();
        setState(() {
          _locked = !_locked;
          _visible = !_locked;
        });
        _armLockHide();
        if (!_locked) _armHide();
      },
      icon: Icon(
        _locked ? Icons.lock_rounded : Icons.lock_open_rounded,
        size: 22,
      ),
    );
  }

  Widget _deviceHud() {
    final colors = Theme.of(context).colorScheme;
    final brightness = _deviceGesture.brightness!;
    final value = _deviceGesture.level ?? 0;
    final label = brightness ? '亮度' : '音量';
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: CloudrevePanel(
          key: const Key('video-device-hud'),
          padding: const EdgeInsets.all(16),
          child: Semantics(
            label: label,
            value: _deviceGesture.failed
                ? '调节不可用'
                : '${(value * 100).round()}%',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      brightness
                          ? Icons.brightness_6_rounded
                          : value == 0
                          ? Icons.volume_off_rounded
                          : Icons.volume_up_rounded,
                      color: colors.primary,
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        label,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (!_deviceGesture.failed)
                      Text(
                        '${(value * 100).round()}%',
                        key: Key(
                          brightness
                              ? 'video-brightness-value'
                              : 'video-volume-value',
                        ),
                        style: TextStyle(
                          color: colors.primary,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_deviceGesture.failed)
                  Text(
                    '$label调节暂不可用',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  )
                else
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: value,
                      minHeight: 5,
                      color: colors.primary,
                      backgroundColor: colors.primary.withValues(alpha: .12),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTransport(VideoPlaybackSnapshot data) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton.filled(
                key: const Key('video-play-toggle'),
                tooltip: data.completed
                    ? '重新播放'
                    : data.playing
                    ? '暂停'
                    : '播放',
                style: IconButton.styleFrom(
                  backgroundColor: colors.primary,
                  foregroundColor: colors.onPrimary,
                  shape: const CircleBorder(),
                  fixedSize: const Size(40, 40),
                  minimumSize: const Size(40, 40),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: data.opening || data.error != null
                    ? null
                    : () => _run(widget.onToggle),
                icon: Icon(
                  data.completed
                      ? Icons.replay_rounded
                      : data.playing
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                ),
              ),
              _action(
                Icons.replay_10_rounded,
                '后退 10 秒',
                data.canSeek ? () => _seekBy(-10) : null,
              ),
              _action(
                Icons.forward_10_rounded,
                '前进 10 秒',
                data.canSeek ? () => _seekBy(10) : null,
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _speedMenu(data),
              _action(
                widget.fullscreen
                    ? Icons.fullscreen_exit_rounded
                    : Icons.fullscreen_rounded,
                widget.fullscreen ? '退出全屏' : '全屏',
                () => _run(widget.onFullscreen),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _speedMenu(VideoPlaybackSnapshot data) {
    final colors = Theme.of(context).colorScheme;
    return PopupMenuButton<double>(
      key: const Key('video-speed-button'),
      tooltip: '播放速度',
      clipBehavior: Clip.antiAlias,
      position: PopupMenuPosition.over,
      enabled: !data.opening && data.error == null,
      onOpened: () {
        _menuOpen = true;
        _hideTimer?.cancel();
      },
      onCanceled: () {
        _menuOpen = false;
        _armHide();
      },
      onSelected: (rate) {
        _menuOpen = false;
        _run(() => widget.onRate(rate));
        _armHide();
      },
      itemBuilder: (_) => [
        for (final rate in videoPlaybackRates)
          PopupMenuItem<double>(
            value: rate,
            key: ValueKey('video-speed-$rate'),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    videoRateLabel(rate),
                    style: TextStyle(
                      color: rate == data.rate
                          ? colors.primary
                          : colors.onSurface,
                      fontWeight: rate == data.rate
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ),
                if (rate == data.rate)
                  Icon(Icons.check_rounded, size: 20, color: colors.primary),
              ],
            ),
          ),
      ],
      child: Container(
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: colors.primary.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              videoRateLabel(data.rate),
              style: TextStyle(
                color: colors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            Icon(Icons.expand_more_rounded, size: 18, color: colors.primary),
          ],
        ),
      ),
    );
  }

  Widget _action(IconData icon, String tooltip, VoidCallback? onPressed) =>
      IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          minimumSize: const Size(40, 40),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: const CircleBorder(),
        ),
        icon: Icon(icon, size: 24),
      );
}

/// The sole loading indicator, also used in fullscreen. It never blocks controls.
class VideoPlaybackStatus extends StatelessWidget {
  const VideoPlaybackStatus({
    super.key,
    required this.data,
    required this.onRetry,
  });
  final VideoPlaybackSnapshot data;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final label = data.error ?? (data.opening ? '正在载入视频…' : '正在缓冲视频…');
    final content = Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: CloudrevePanel(
            padding: const EdgeInsets.all(16),
            child: Semantics(
              liveRegion: true,
              child: data.error != null
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          color: colors.error,
                          size: 30,
                        ),
                        const SizedBox(height: 12),
                        Text(label, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          key: const Key('video-player-retry'),
                          onPressed: onRetry,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('重新加载'),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(
                            key: const Key('video-loading-indicator'),
                            strokeWidth: 2.5,
                            color: colors.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            label,
                            style: TextStyle(
                              color: colors.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
    return data.error == null ? IgnorePointer(child: content) : content;
  }
}
