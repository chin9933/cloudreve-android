import 'dart:async';

import 'package:cloudreve/utils/video_device_controls.dart';
import 'package:flutter/foundation.dart';

enum VideoGestureAxis { pending, vertical, horizontal }

/// Resolve intent once; a sideways swipe must not become a volume gesture
/// because a finger drifts vertically later in the same stroke.
VideoGestureAxis videoGestureAxis(double dx, double dy) {
  if (dx * dx + dy * dy < 18 * 18) return VideoGestureAxis.pending;
  return dy.abs() > dx.abs() * 1.3
      ? VideoGestureAxis.vertical
      : VideoGestureAxis.horizontal;
}

/// Coalesces pointer updates instead of queuing a platform call per frame.
class VideoGestureController extends ChangeNotifier {
  VideoGestureController({
    required this.readLevels,
    required this.setBrightness,
    required this.setVolume,
  });
  final Future<VideoDeviceLevels> Function() readLevels;
  final Future<double> Function(double) setBrightness, setVolume;
  Timer? _writeTimer, _hudTimer;
  int _revision = 0;
  bool _disposed = false, _sending = false, _dragging = false;
  bool? brightness;
  double? level;
  bool failed = false;
  double? _startLevel, _pending;
  double _delta = 0, _distance = 1;

  bool get visible => brightness != null && (level != null || failed);

  void start({required bool brightness, required double height}) {
    cancel();
    final revision = _revision;
    this.brightness = brightness;
    _dragging = true;
    _distance = (height * .65).clamp(80, double.infinity);
    unawaited(_read(revision));
  }

  Future<void> _read(int revision) async {
    try {
      // Refresh for every gesture: hardware keys/headphones may change volume.
      final values = await readLevels();
      if (_disposed || revision != _revision) return;
      _startLevel = brightness! ? values.brightness : values.volume;
      level = _startLevel;
      if (_delta != 0) _updateTarget();
      notifyListeners();
    } catch (_) {
      _fail(revision);
    }
  }

  void update(double deltaY) {
    if (!_dragging || failed) return;
    _delta += deltaY;
    if (_startLevel != null) _updateTarget();
  }

  void _updateTarget() {
    final target = (_startLevel! - _delta / _distance)
        .clamp(brightness! ? .05 : 0, 1.0)
        .toDouble();
    level = target;
    _pending = target;
    notifyListeners();
    if (!_sending && _writeTimer == null) {
      _writeTimer = Timer(const Duration(milliseconds: 40), _flush);
    }
  }

  Future<void> _flush() async {
    _writeTimer?.cancel();
    _writeTimer = null;
    if (_disposed || _sending || _pending == null) return;
    final revision = _revision;
    final target = _pending!;
    final adjustBrightness = brightness!;
    _pending = null;
    _sending = true;
    try {
      final actual = await (adjustBrightness ? setBrightness : setVolume)(
        target,
      );
      if (_disposed || revision != _revision) return;
      if (_pending == null) {
        // Show the actual Android volume step, not an unattainable percentage.
        level = actual;
        notifyListeners();
      }
    } catch (_) {
      _fail(revision);
    } finally {
      _sending = false;
      if (!_disposed && _pending != null && _writeTimer == null) {
        _writeTimer = Timer(const Duration(milliseconds: 40), _flush);
      }
    }
  }

  void end() {
    _dragging = false;
    unawaited(_flush());
    _scheduleHide();
  }

  void _fail(int revision) {
    if (_disposed || revision != _revision) return;
    _pending = null;
    _writeTimer?.cancel();
    _writeTimer = null;
    failed = true;
    notifyListeners();
    _scheduleHide();
  }

  void _scheduleHide() {
    _hudTimer?.cancel();
    _hudTimer = Timer(const Duration(milliseconds: 1000), cancel);
  }

  void cancel() {
    _revision++;
    _writeTimer?.cancel();
    _hudTimer?.cancel();
    _writeTimer = _hudTimer = null;
    _dragging = false;
    _startLevel = _pending = level = null;
    brightness = null;
    _delta = 0;
    failed = false;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    cancel();
    super.dispose();
  }
}
