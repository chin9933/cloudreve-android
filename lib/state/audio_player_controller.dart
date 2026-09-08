import 'dart:async';

import 'package:cloudreve/utils/cloudreve_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

@immutable
class CloudreveAudioTrack {
  const CloudreveAudioTrack({
    required this.id,
    required this.name,
    required this.uri,
    this.contextHint,
  });

  final String id;
  final String name;
  final String uri;
  final String? contextHint;
}

/// Owns the in-app music queue and exposes only UI-friendly playback state.
class CloudreveAudioController extends ChangeNotifier {
  CloudreveAudioController()
    : _player = AudioPlayer(
        // Cloudreve returns a self-contained HTTPS signed URL, so no local
        // header proxy is needed. A longer forward buffer smooths over the
        // short network dips that previously interrupted music playback.
        useProxyForRequestHeaders: false,
        audioLoadConfiguration: const AudioLoadConfiguration(
          androidLoadControl: AndroidLoadControl(
            minBufferDuration: Duration(seconds: 60),
            maxBufferDuration: Duration(seconds: 120),
            bufferForPlaybackDuration: Duration(milliseconds: 1500),
            bufferForPlaybackAfterRebufferDuration: Duration(seconds: 5),
            prioritizeTimeOverSizeThresholds: true,
          ),
          darwinLoadControl: DarwinLoadControl(
            preferredForwardBufferDuration: Duration(seconds: 120),
          ),
        ),
      ) {
    _subscriptions.addAll([
      _player.positionStream.listen((position) {
        _position = position;
        _notify();
      }),
      _player.bufferedPositionStream.listen((position) {
        _bufferedPosition = position;
        _notify();
      }),
      _player.durationStream.listen((duration) {
        _duration = duration ?? Duration.zero;
        _notify();
      }),
      _player.playerStateStream.listen((state) {
        _playing = state.playing;
        _processingState = state.processingState;
        _notify();
        if (state.processingState == ProcessingState.completed) {
          unawaited(_advanceAfterCompletion());
        }
      }),
      _player.errorStream.listen((_) {
        if (_disposed || currentTrack == null) return;
        _loading = false;
        _playing = false;
        _errorMessage = '播放失败，请检查网络或音频格式';
        _notify();
      }),
    ]);
  }

  final AudioPlayer _player;
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  List<CloudreveAudioTrack> _queue = const [];
  int _currentIndex = -1;
  Duration _position = Duration.zero;
  Duration _bufferedPosition = Duration.zero;
  Duration _duration = Duration.zero;
  ProcessingState _processingState = ProcessingState.idle;
  String? _errorMessage;
  bool _playing = false;
  bool _loading = false;
  bool _handlingCompletion = false;
  bool _disposed = false;
  int _loadToken = 0;

  List<CloudreveAudioTrack> get queue => List.unmodifiable(_queue);
  int get currentIndex => _currentIndex;
  Duration get position => _position;
  Duration get bufferedPosition => _bufferedPosition;
  Duration get duration => _duration;
  ProcessingState get processingState => _processingState;
  String? get errorMessage => _errorMessage;
  bool get playing => _playing;
  bool get loading => _loading;
  bool get buffering => _processingState == ProcessingState.buffering;
  bool get hasTrack => currentTrack != null;
  bool get canSkip => _queue.length > 1;

  CloudreveAudioTrack? get currentTrack {
    if (_currentIndex < 0 || _currentIndex >= _queue.length) return null;
    return _queue[_currentIndex];
  }

  double get bufferedFraction {
    final total = _duration.inMilliseconds;
    if (total <= 0) return 0;
    return (_bufferedPosition.inMilliseconds / total).clamp(0.0, 1.0);
  }

  Future<bool> playQueue(
    List<CloudreveAudioTrack> tracks, {
    required String initialTrackId,
  }) async {
    final validTracks = tracks.where((track) => track.uri.isNotEmpty).toList();
    if (validTracks.isEmpty) {
      _errorMessage = '找不到可播放的音频地址';
      _notify();
      return false;
    }

    var index = validTracks.indexWhere((track) => track.id == initialTrackId);
    if (index < 0) index = 0;
    _queue = List.unmodifiable(validTracks);
    _currentIndex = index;
    _errorMessage = null;
    _notify();
    return _loadCurrent(autoplay: true);
  }

  Future<void> togglePlayback() async {
    if (!hasTrack || _loading) return;

    if (_errorMessage != null || _processingState == ProcessingState.idle) {
      await _loadCurrent(autoplay: true);
      return;
    }
    if (_processingState == ProcessingState.completed) {
      await _player.seek(Duration.zero);
      _startPlayback(_loadToken);
      return;
    }
    if (_playing) {
      await _player.pause();
    } else {
      _startPlayback(_loadToken);
    }
  }

  Future<void> next() async {
    if (!hasTrack) return;
    if (_queue.length == 1) {
      await _player.seek(Duration.zero);
      return;
    }
    _currentIndex = (_currentIndex + 1) % _queue.length;
    await _loadCurrent(autoplay: true);
  }

  Future<void> previous() async {
    if (!hasTrack) return;
    if (_position > const Duration(seconds: 3) || _queue.length == 1) {
      await _player.seek(Duration.zero);
      return;
    }
    _currentIndex = (_currentIndex - 1 + _queue.length) % _queue.length;
    await _loadCurrent(autoplay: true);
  }

  Future<void> seek(Duration target) async {
    if (!hasTrack || _duration <= Duration.zero) return;
    final bounded = target < Duration.zero
        ? Duration.zero
        : target > _duration
        ? _duration
        : target;
    await _player.seek(bounded);
  }

  Future<void> close() async {
    _loadToken++;
    await _player.stop();
    _queue = const [];
    _currentIndex = -1;
    _position = Duration.zero;
    _bufferedPosition = Duration.zero;
    _duration = Duration.zero;
    _processingState = ProcessingState.idle;
    _errorMessage = null;
    _playing = false;
    _loading = false;
    _notify();
  }

  Future<bool> _loadCurrent({required bool autoplay}) async {
    final track = currentTrack;
    if (track == null) return false;

    final token = ++_loadToken;
    _loading = true;
    _errorMessage = null;
    _position = Duration.zero;
    _bufferedPosition = Duration.zero;
    _duration = Duration.zero;
    _notify();

    try {
      await _player.stop();
      final url = await _resolveDownloadUrl(track);
      if (_disposed || token != _loadToken) return false;
      if (url == null || url.isEmpty) {
        throw StateError('empty audio url');
      }

      Duration? duration;
      try {
        duration = await _player.setUrl(url);
      } catch (error, stackTrace) {
        _debugFailure(
          'audio source rejected, refreshing URL',
          error,
          stackTrace,
        );
        if (_disposed || token != _loadToken) return false;
        final refreshedUrl = await _resolveDownloadUrl(track);
        if (refreshedUrl == null || refreshedUrl.isEmpty) rethrow;
        duration = await _player.setUrl(refreshedUrl);
      }
      if (_disposed || token != _loadToken) return false;
      _duration = duration ?? _player.duration ?? Duration.zero;
      _loading = false;
      _errorMessage = null;
      _notify();
      if (autoplay) _startPlayback(token);
      return true;
    } catch (error, stackTrace) {
      _debugFailure('audio load failed', error, stackTrace);
      if (_disposed || token != _loadToken) return false;
      _loading = false;
      _playing = false;
      _errorMessage = '播放失败，请检查网络或音频格式';
      _notify();
      return false;
    }
  }

  Future<String?> _resolveDownloadUrl(CloudreveAudioTrack track) async {
    final contextHint = track.contextHint?.trim();
    if (contextHint != null && contextHint.isNotEmpty) {
      try {
        final hintedUrl = await CloudreveRepository.createDownloadUrl(
          track.uri,
          contextHint: contextHint,
        );
        if (hintedUrl != null && hintedUrl.isNotEmpty) return hintedUrl;
      } catch (error, stackTrace) {
        _debugFailure('context-hinted URL failed', error, stackTrace);
      }
    }

    // Context hints are short-lived. Personal files remain addressable by URI,
    // so retrying without a stale hint keeps a long-open file page playable.
    return CloudreveRepository.createDownloadUrl(track.uri);
  }

  void _startPlayback(int token) {
    unawaited(
      _player.play().catchError((error, stackTrace) {
        _debugFailure('audio playback failed', error, stackTrace);
        if (_disposed || token != _loadToken) return;
        _loading = false;
        _playing = false;
        _errorMessage = '播放失败，请检查网络或音频格式';
        _notify();
      }),
    );
  }

  Future<void> _advanceAfterCompletion() async {
    if (_handlingCompletion || _disposed || !hasTrack) return;
    _handlingCompletion = true;
    try {
      if (_queue.length > 1) {
        await next();
      } else {
        await _player.pause();
        await _player.seek(Duration.zero);
      }
    } finally {
      _handlingCompletion = false;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _debugFailure(String stage, Object error, StackTrace stackTrace) {
    if (kDebugMode) {
      // Platform errors can contain signed media URLs. Log only their type.
      debugPrint('$stage: ${error.runtimeType}');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _loadToken++;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_player.dispose());
    super.dispose();
  }
}
