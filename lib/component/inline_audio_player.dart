import 'package:cloudreve/state/audio_player_controller.dart';
import 'package:cloudreve/state/sound_effect_provider.dart';
import 'package:cloudreve/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

class InlineAudioPlayer extends StatefulWidget {
  const InlineAudioPlayer({super.key, required this.controller});

  final CloudreveAudioController controller;

  @override
  State<InlineAudioPlayer> createState() => _InlineAudioPlayerState();
}

class _InlineAudioPlayerState extends State<InlineAudioPlayer> {
  double? _dragMilliseconds;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        return AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: controller.hasTrack
              ? Padding(
                  key: const ValueKey('inline-audio-player-visible'),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _buildPlayer(context, controller),
                )
              : const SizedBox(key: ValueKey('inline-audio-player-hidden')),
        );
      },
    );
  }

  Widget _buildPlayer(
    BuildContext context,
    CloudreveAudioController controller,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final track = controller.currentTrack!;
    final durationMs = controller.duration.inMilliseconds;
    final maxMs = durationMs <= 0 ? 1.0 : durationMs.toDouble();
    final livePositionMs = controller.position.inMilliseconds.toDouble().clamp(
      0.0,
      maxMs,
    );
    final shownPositionMs = (_dragMilliseconds ?? livePositionMs).clamp(
      0.0,
      maxMs,
    );
    final status = _statusText(controller);

    return Semantics(
      container: true,
      label: controller.errorMessage != null
          ? '音乐播放器，${track.name} 播放失败'
          : controller.loading || controller.buffering
          ? '音乐播放器，正在缓冲 ${track.name}'
          : controller.playing
          ? '音乐播放器，正在播放 ${track.name}'
          : '音乐播放器，已暂停 ${track.name}',
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 9),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: scheme.primary.withValues(alpha: 0.20)),
          boxShadow: theme.brightness == Brightness.dark
              ? null
              : const [
                  BoxShadow(
                    color: Color(0x0D2478FF),
                    blurRadius: 18,
                    offset: Offset(0, 7),
                  ),
                ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    Icons.graphic_eq_rounded,
                    color: scheme.primary,
                    size: 23,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (controller.loading || controller.buffering) ...[
                            SizedBox(
                              width: 11,
                              height: 11,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.8,
                                color: scheme.primary,
                              ),
                            ),
                            const SizedBox(width: 5),
                          ],
                          Expanded(
                            child: Text(
                              status,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: controller.errorMessage == null
                                    ? scheme.onSurfaceVariant
                                    : CloudreveColors.danger,
                                fontSize: 11.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: const ValueKey('audio-player-close'),
                  tooltip: '关闭播放器',
                  onPressed: controller.close,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.close_rounded,
                    color: scheme.onSurfaceVariant,
                    size: 20,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Row(
              children: [
                _PlayerControl(
                  key: const ValueKey('audio-player-previous'),
                  icon: Icons.skip_previous_rounded,
                  tooltip: '上一首',
                  onPressed: controller.previous,
                ),
                const SizedBox(width: 2),
                Material(
                  color: scheme.primary,
                  shape: const CircleBorder(),
                  child: InkWell(
                    enableFeedback:
                        context.watch<SoundEffectProvider?>()?.enabled ?? true,
                    key: const ValueKey('audio-player-toggle'),
                    customBorder: const CircleBorder(),
                    onTap: controller.loading
                        ? null
                        : controller.togglePlayback,
                    child: SizedBox(
                      width: 38,
                      height: 38,
                      child: Icon(
                        _playbackIcon(controller),
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                _PlayerControl(
                  key: const ValueKey('audio-player-next'),
                  icon: Icons.skip_next_rounded,
                  tooltip: '下一首',
                  onPressed: controller.canSkip ? controller.next : null,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: SizedBox(
                    height: 30,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              minHeight: 3,
                              value: controller.bufferedFraction,
                              backgroundColor: scheme.onSurface.withValues(
                                alpha: 0.10,
                              ),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                scheme.primary.withValues(alpha: 0.26),
                              ),
                            ),
                          ),
                        ),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3,
                            activeTrackColor: scheme.primary,
                            inactiveTrackColor: Colors.transparent,
                            thumbColor: scheme.primary,
                            overlayColor: scheme.primary.withValues(
                              alpha: 0.12,
                            ),
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 5,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 13,
                            ),
                          ),
                          child: Slider(
                            key: const ValueKey('audio-player-progress'),
                            min: 0,
                            max: maxMs,
                            value: shownPositionMs,
                            onChangeStart: (value) {
                              setState(() => _dragMilliseconds = value);
                            },
                            onChanged: durationMs <= 0
                                ? null
                                : (value) {
                                    setState(() => _dragMilliseconds = value);
                                  },
                            onChangeEnd: durationMs <= 0
                                ? null
                                : (value) {
                                    setState(() => _dragMilliseconds = null);
                                    controller.seek(
                                      Duration(milliseconds: value.round()),
                                    );
                                  },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: 68,
                  child: Text(
                    '${_formatDuration(Duration(milliseconds: shownPositionMs.round()))} / ${_formatDuration(controller.duration)}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontSize: 10.5,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _statusText(CloudreveAudioController controller) {
    if (controller.errorMessage != null) return controller.errorMessage!;
    if (controller.loading) return '正在载入音频…';
    if (controller.buffering) return '网络波动，正在缓冲…';
    final queuePosition = controller.currentIndex + 1;
    final queueTotal = controller.queue.length;
    if (controller.playing) return '$queuePosition / $queueTotal · 正在播放';
    return '$queuePosition / $queueTotal · 已暂停';
  }

  IconData _playbackIcon(CloudreveAudioController controller) {
    if (controller.processingState == ProcessingState.completed) {
      return Icons.replay_rounded;
    }
    return controller.playing ? Icons.pause_rounded : Icons.play_arrow_rounded;
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

class _PlayerControl extends StatelessWidget {
  const _PlayerControl({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final Future<void> Function()? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      constraints: const BoxConstraints.tightFor(width: 34, height: 34),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, size: 23),
    );
  }
}
