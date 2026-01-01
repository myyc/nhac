/// Platform-specific audio player abstraction.
///
/// Uses MpvPlayer on Linux/Windows where media_kit has issues,
/// and falls back to just_audio on other platforms.
library;

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' as ja;

import 'mpv/mpv_player.dart';

/// Processing state for audio playback
enum ProcessingState {
  idle,
  loading,
  buffering,
  ready,
  completed,
}

/// Player state combining playing and processing state
class PlayerState {
  final bool playing;
  final ProcessingState processingState;

  PlayerState(this.playing, this.processingState);
}

/// Playback event with position and state info
class PlaybackEvent {
  final Duration position;
  final Duration? duration;
  final ProcessingState processingState;
  final bool playing;
  final int? currentIndex;

  PlaybackEvent({
    required this.position,
    this.duration,
    required this.processingState,
    required this.playing,
    this.currentIndex,
  });
}

/// Abstract audio player interface
abstract class PlatformAudioPlayer {
  /// Create platform-appropriate player
  static PlatformAudioPlayer create() {
    if (!kIsWeb && (Platform.isLinux || Platform.isWindows)) {
      return MpvAudioPlayer();
    }
    return JustAudioPlayer();
  }

  /// Whether to use mpv on this platform
  static bool get usesMpv =>
      !kIsWeb && (Platform.isLinux || Platform.isWindows);

  // Streams
  Stream<Duration> get positionStream;
  Stream<Duration?> get durationStream;
  Stream<PlayerState> get playerStateStream;
  Stream<PlaybackEvent> get playbackEventStream;
  Stream<int?> get currentIndexStream;

  // State getters
  bool get playing;
  ProcessingState get processingState;
  Duration get position;
  Duration? get duration;
  bool get hasNext;
  bool get hasPrevious;

  // Control methods
  Future<void> setUrl(String url, {Map<String, String>? headers});
  Future<void> setFilePath(String path);
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
  Future<void> seekToNext();
  Future<void> seekToPrevious();
  Future<void> dispose();

  // Playlist support (simple version)
  Future<void> setAudioSource(dynamic source, {int initialIndex});
}

/// MpvPlayer-based implementation for Linux/Windows
class MpvAudioPlayer implements PlatformAudioPlayer {
  final MpvPlayer _player = MpvPlayer();
  bool _initialized = false;

  // Stream controllers that bridge MpvPlayer to our interface
  final _playerStateController = StreamController<PlayerState>.broadcast();
  final _playbackEventController = StreamController<PlaybackEvent>.broadcast();
  final _currentIndexController = StreamController<int?>.broadcast();

  // State
  int _currentIndex = 0;
  List<String> _playlist = [];
  String? _currentUrl;

  MpvAudioPlayer() {
    _init();
  }

  Future<void> _init() async {
    _initialized = await _player.initialize();
    if (!_initialized) {
      debugPrint('[MpvAudioPlayer] Failed to initialize mpv');
      return;
    }

    // Bridge state stream
    _player.stateStream.listen((state) {
      final playing = state == MpvPlayerState.playing;
      final processingState = _mapState(state);
      _playerStateController.add(PlayerState(playing, processingState));
      _playbackEventController.add(PlaybackEvent(
        position: _player.position,
        duration: _player.duration,
        processingState: processingState,
        playing: playing,
        currentIndex: _currentIndex,
      ));
    });

    // Position stream triggers playback events
    _player.positionStream.listen((position) {
      _playbackEventController.add(PlaybackEvent(
        position: position,
        duration: _player.duration,
        processingState: _mapState(_player.state),
        playing: _player.isPlaying,
        currentIndex: _currentIndex,
      ));
    });
  }

  ProcessingState _mapState(MpvPlayerState state) {
    switch (state) {
      case MpvPlayerState.idle:
        return ProcessingState.idle;
      case MpvPlayerState.loading:
        return ProcessingState.loading;
      case MpvPlayerState.ready:
      case MpvPlayerState.paused:
      case MpvPlayerState.playing:
        return ProcessingState.ready;
      case MpvPlayerState.completed:
        return ProcessingState.completed;
      case MpvPlayerState.error:
        return ProcessingState.idle;
    }
  }

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  Stream<Duration?> get durationStream => _player.durationStream;

  @override
  Stream<PlayerState> get playerStateStream => _playerStateController.stream;

  @override
  Stream<PlaybackEvent> get playbackEventStream =>
      _playbackEventController.stream;

  @override
  Stream<int?> get currentIndexStream => _currentIndexController.stream;

  @override
  bool get playing => _player.isPlaying;

  @override
  ProcessingState get processingState => _mapState(_player.state);

  @override
  Duration get position => _player.position;

  @override
  Duration? get duration => _player.duration;

  @override
  bool get hasNext => _playlist.isNotEmpty && _currentIndex < _playlist.length - 1;

  @override
  bool get hasPrevious => _playlist.isNotEmpty && _currentIndex > 0;

  @override
  Future<void> setUrl(String url, {Map<String, String>? headers}) async {
    if (!_initialized) await _init();
    _currentUrl = url;
    _playlist = [url];
    _currentIndex = 0;
    await _player.load(url);
  }

  @override
  Future<void> setFilePath(String path) async {
    if (!_initialized) await _init();
    _currentUrl = path;
    _playlist = [path];
    _currentIndex = 0;
    await _player.load(path);
  }

  @override
  Future<void> play() async {
    if (!_initialized) return;
    await _player.play();
  }

  @override
  Future<void> pause() async {
    if (!_initialized) return;
    await _player.pause();
  }

  @override
  Future<void> stop() async {
    if (!_initialized) return;
    await _player.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    if (!_initialized) return;
    await _player.seek(position);
  }

  @override
  Future<void> setVolume(double volume) async {
    if (!_initialized) return;
    await _player.setVolume(volume);
  }

  @override
  Future<void> seekToNext() async {
    if (!hasNext) return;
    _currentIndex++;
    _currentIndexController.add(_currentIndex);
    if (_playlist.isNotEmpty) {
      await _player.load(_playlist[_currentIndex]);
    }
  }

  @override
  Future<void> seekToPrevious() async {
    if (!hasPrevious) return;
    _currentIndex--;
    _currentIndexController.add(_currentIndex);
    if (_playlist.isNotEmpty) {
      await _player.load(_playlist[_currentIndex]);
    }
  }

  @override
  Future<void> setAudioSource(dynamic source, {int initialIndex = 0}) async {
    // Basic playlist support - extract URLs from ConcatenatingAudioSource
    // For now, just handle single sources
    _currentIndex = initialIndex;
    _currentIndexController.add(_currentIndex);
  }

  @override
  Future<void> dispose() async {
    await _player.dispose();
    await _playerStateController.close();
    await _playbackEventController.close();
    await _currentIndexController.close();
  }
}

/// just_audio wrapper for other platforms
class JustAudioPlayer implements PlatformAudioPlayer {
  final ja.AudioPlayer _player = ja.AudioPlayer();

  JustAudioPlayer();

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  Stream<Duration?> get durationStream => _player.durationStream;

  @override
  Stream<PlayerState> get playerStateStream =>
      _player.playerStateStream.map((state) => PlayerState(
            state.playing,
            _mapProcessingState(state.processingState),
          ));

  @override
  Stream<PlaybackEvent> get playbackEventStream =>
      _player.playbackEventStream.map((event) => PlaybackEvent(
            position: event.updatePosition,
            duration: event.duration,
            processingState: _mapProcessingState(event.processingState),
            playing: _player.playing,
            currentIndex: event.currentIndex,
          ));

  @override
  Stream<int?> get currentIndexStream => _player.currentIndexStream;

  ProcessingState _mapProcessingState(ja.ProcessingState state) {
    switch (state) {
      case ja.ProcessingState.idle:
        return ProcessingState.idle;
      case ja.ProcessingState.loading:
        return ProcessingState.loading;
      case ja.ProcessingState.buffering:
        return ProcessingState.buffering;
      case ja.ProcessingState.ready:
        return ProcessingState.ready;
      case ja.ProcessingState.completed:
        return ProcessingState.completed;
    }
  }

  @override
  bool get playing => _player.playing;

  @override
  ProcessingState get processingState =>
      _mapProcessingState(_player.processingState);

  @override
  Duration get position => _player.position;

  @override
  Duration? get duration => _player.duration;

  @override
  bool get hasNext => _player.hasNext;

  @override
  bool get hasPrevious => _player.hasPrevious;

  @override
  Future<void> setUrl(String url, {Map<String, String>? headers}) async {
    await _player.setUrl(url, headers: headers);
  }

  @override
  Future<void> setFilePath(String path) async {
    await _player.setFilePath(path);
  }

  @override
  Future<void> play() async {
    await _player.play();
  }

  @override
  Future<void> pause() async {
    await _player.pause();
  }

  @override
  Future<void> stop() async {
    await _player.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  @override
  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume);
  }

  @override
  Future<void> seekToNext() async {
    await _player.seekToNext();
  }

  @override
  Future<void> seekToPrevious() async {
    await _player.seekToPrevious();
  }

  @override
  Future<void> setAudioSource(dynamic source, {int initialIndex = 0}) async {
    if (source is ja.AudioSource) {
      await _player.setAudioSource(source, initialIndex: initialIndex);
    }
  }

  @override
  Future<void> dispose() async {
    await _player.dispose();
  }

  /// Access the underlying just_audio player for advanced features
  ja.AudioPlayer get innerPlayer => _player;
}
