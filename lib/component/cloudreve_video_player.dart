import 'dart:async';

import 'package:cloudreve/component/video_player_controls.dart';
import 'package:cloudreve/config/app_config.dart';
import 'package:cloudreve/theme/app_theme.dart';
import 'package:cloudreve/utils/video_device_controls.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Native decoder with app-owned controls and one shared loading presentation.
class CloudreveVideoPlayerPage extends StatefulWidget {
  const CloudreveVideoPlayerPage({
    super.key,
    required this.title,
    required this.url,
  });
  final String title;
  final String url;
  @override
  State<CloudreveVideoPlayerPage> createState() =>
      _CloudreveVideoPlayerPageState();
}

class _CloudreveVideoPlayerPageState extends State<CloudreveVideoPlayerPage> {
  late final _engine = _CloudreveVideoEngine.instance;
  Player get _player => _engine.player;
  final _status = ValueNotifier(const VideoPlaybackSnapshot());
  final _deviceControls = VideoDeviceControls();
  final _subscriptions = <StreamSubscription<dynamic>>[];
  int _loadRevision = 0;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _subscriptions.addAll([
      _player.stream.buffering.listen(
        (value) => _update((s) => s.copyWith(buffering: value)),
      ),
      _player.stream.playing.listen(
        (value) => _update((s) => s.copyWith(playing: value)),
      ),
      _player.stream.completed.listen(
        (value) => _update((s) => s.copyWith(completed: value)),
      ),
      _player.stream.position.listen(
        (value) => _update((s) => s.copyWith(position: value)),
      ),
      _player.stream.duration.listen(
        (value) => _update((s) => s.copyWith(duration: value)),
      ),
      _player.stream.buffer.listen(
        (value) => _update((s) => s.copyWith(buffer: value)),
      ),
      _player.stream.rate.listen(
        (value) => _update((s) => s.copyWith(rate: value)),
      ),
      _player.stream.error.listen((_) => _showPlaybackError()),
    ]);
    unawaited(_openVideo());
  }

  void _update(VideoPlaybackSnapshot Function(VideoPlaybackSnapshot) change) {
    if (mounted && !_closing) _status.value = change(_status.value);
  }

  Future<void> _openVideo() async {
    final revision = ++_loadRevision;
    _update((_) => VideoPlaybackSnapshot(rate: _engine.preferredRate));
    try {
      await _player.open(
        Media(widget.url, extras: {'title': widget.title}),
        play: true,
      );
      if (!mounted || _closing || revision != _loadRevision) return;
      await _player.setRate(_engine.preferredRate);
      await _engine.videoController.waitUntilFirstFrameRendered.timeout(
        const Duration(seconds: 30),
      );
      if (!mounted || _closing || revision != _loadRevision) return;
      _update((s) => s.copyWith(opening: false));
    } catch (error) {
      // Native errors can contain signed media URLs: do not log their contents.
      debugPrint('Cloudreve video open failed: ${error.runtimeType}');
      if (mounted && !_closing && revision == _loadRevision) {
        _showPlaybackError();
      }
    }
  }

  void _showPlaybackError() => _update(
    (s) => s.copyWith(
      opening: false,
      buffering: false,
      error: '视频加载失败，请检查网络后重试；若仍无法播放，文件编码可能不受设备支持。',
    ),
  );

  Future<void> _retry() async {
    _loadRevision++;
    await _player.stop();
    if (mounted && !_closing) await _openVideo();
  }

  Future<void> _togglePlayback() async {
    if (_status.value.completed) {
      await _player.seek(Duration.zero);
      await _player.play();
    } else {
      await _player.playOrPause();
    }
  }

  Future<void> _setRate(double rate) async {
    if (!videoPlaybackRates.contains(rate)) return;
    await _player.setRate(rate);
    _engine.preferredRate = rate;
    _update((s) => s.copyWith(rate: rate));
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    _loadRevision++;
    try {
      await _player.stop();
    } finally {
      if (mounted) Navigator.of(context).maybePop();
    }
  }

  @override
  void dispose() {
    _closing = true;
    _loadRevision++;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    // Keep the native engine: disposing media-kit 1.2.6 after video playback
    // can abort Android release builds (upstream #1443).
    unawaited(_player.stop());
    unawaited(_deviceControls.end());
    _status.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leadingWidth: 72,
        leading: Center(
          child: IconButton(
            key: const ValueKey('video-player-close'),
            tooltip: '关闭视频',
            onPressed: _close,
            style: IconButton.styleFrom(
              backgroundColor: theme.colorScheme.surface,
              foregroundColor: theme.colorScheme.onSurface,
              fixedSize: const Size(42, 42),
              shape: const CircleBorder(),
            ),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          ),
        ),
        titleSpacing: 8,
        title: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Material(
            key: const Key('video-preview-frame'),
            color: Colors.black,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(CloudreveTheme.cardRadius),
            ),
            child: Video(
              key: const ValueKey('cloudreve-video-output'),
              controller: _engine.videoController,
              // No MaterialVideoControls here: its buffering spinner must never
              // be layered underneath our app loading indicator.
              controls: (_) => Builder(
                builder: (videoContext) => VideoPlayerControls(
                  state: _status,
                  title: widget.title,
                  fullscreen: isFullscreen(videoContext),
                  onToggle: _togglePlayback,
                  onSeek: _player.seek,
                  onRate: _setRate,
                  onRetry: _retry,
                  onReadLevels: _deviceControls.readLevels,
                  onBrightness: _deviceControls.setBrightness,
                  onVolume: _deviceControls.setVolume,
                  onFullscreen: () => toggleFullscreen(videoContext),
                ),
              ),
              fit: BoxFit.contain,
              fill: Colors.black,
              wakelock: true,
              pauseUponEnteringBackgroundMode: true,
            ),
          ),
        ),
      ),
    );
  }
}

/// Retaining one native engine avoids media-kit issue #1443 in release builds.
class _CloudreveVideoEngine {
  _CloudreveVideoEngine._() {
    MediaKit.ensureInitialized();
    player = Player(
      configuration: const PlayerConfiguration(
        title: AppConfig.appName,
        bufferSize: 64 * 1024 * 1024,
      ),
    );
    videoController = VideoController(
      player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true,
      ),
    );
  }
  static final _CloudreveVideoEngine instance = _CloudreveVideoEngine._();
  late final Player player;
  late final VideoController videoController;
  double preferredRate = 1;
}
