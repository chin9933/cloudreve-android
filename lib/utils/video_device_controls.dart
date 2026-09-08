import 'package:flutter/services.dart';

class VideoDeviceLevels {
  const VideoDeviceLevels({required this.brightness, required this.volume});
  final double brightness, volume;
}

/// A playback-scoped Android bridge, without global brightness permissions.
class VideoDeviceControls {
  static const channel = MethodChannel('cloudreve/video_device');
  static int _nextSession = 0;
  final String _session =
      '${DateTime.now().microsecondsSinceEpoch}-${++_nextSession}';
  Future<void>? _begin;
  bool _ended = false;

  Future<void> _ensureStarted() async {
    if (_ended) throw StateError('Video session has ended');
    await (_begin ??= channel.invokeMethod<void>('begin', {
      'session': _session,
    }));
    if (_ended) throw StateError('Video session has ended');
  }

  Future<VideoDeviceLevels> readLevels() async {
    await _ensureStarted();
    final values = await channel.invokeMapMethod<String, dynamic>('read', {
      'session': _session,
    });
    return VideoDeviceLevels(
      brightness: (values!['brightness'] as num).toDouble().clamp(.05, 1),
      volume: (values['volume'] as num).toDouble().clamp(0, 1),
    );
  }

  Future<double> _set(String method, double value, double minimum) async {
    await _ensureStarted();
    final actual = await channel.invokeMethod<num>(method, {
      'session': _session,
      'value': value.clamp(minimum, 1),
    });
    return actual!.toDouble().clamp(minimum, 1);
  }

  Future<double> setBrightness(double value) => _set('brightness', value, .05);
  Future<double> setVolume(double value) => _set('volume', value, 0);

  Future<void> end() async {
    if (_ended) return;
    _ended = true;
    if (_begin == null) return;
    try {
      await _begin;
      await channel.invokeMethod<void>('end', {'session': _session});
    } catch (_) {
      // Closing a route must not fail when the native activity is already gone.
    }
  }
}
