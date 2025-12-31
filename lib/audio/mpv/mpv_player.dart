/// High-level audio player using libmpv FFI bindings.
///
/// This is an audio-only player that doesn't set any video properties,
/// making it compatible with audio-only mpv builds.
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'package:ffi/ffi.dart';

import 'bindings.dart';

/// Player state
enum MpvPlayerState {
  idle,
  loading,
  ready,
  playing,
  paused,
  completed,
  error,
}

/// Player error
class MpvPlayerError {
  final int code;
  final String message;

  MpvPlayerError(this.code, this.message);

  @override
  String toString() => 'MpvPlayerError($code): $message';
}

/// High-level mpv audio player
class MpvPlayer {
  LibMpv? _mpv;
  Pointer<MpvHandle>? _ctx;
  Isolate? _eventIsolate;
  ReceivePort? _eventPort;
  SendPort? _commandPort;

  bool _disposed = false;
  bool _initialized = false;

  // Stream controllers
  final _stateController = StreamController<MpvPlayerState>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration?>.broadcast();
  final _bufferingController = StreamController<bool>.broadcast();
  final _errorController = StreamController<MpvPlayerError>.broadcast();
  final _volumeController = StreamController<double>.broadcast();

  // Current state
  MpvPlayerState _state = MpvPlayerState.idle;
  Duration _position = Duration.zero;
  Duration? _duration;
  bool _buffering = false;
  double _volume = 1.0;

  /// Stream of player state changes
  Stream<MpvPlayerState> get stateStream => _stateController.stream;

  /// Stream of position updates
  Stream<Duration> get positionStream => _positionController.stream;

  /// Stream of duration updates
  Stream<Duration?> get durationStream => _durationController.stream;

  /// Stream of buffering state
  Stream<bool> get bufferingStream => _bufferingController.stream;

  /// Stream of errors
  Stream<MpvPlayerError> get errorStream => _errorController.stream;

  /// Stream of volume changes
  Stream<double> get volumeStream => _volumeController.stream;

  /// Current player state
  MpvPlayerState get state => _state;

  /// Current playback position
  Duration get position => _position;

  /// Current media duration (null if unknown)
  Duration? get duration => _duration;

  /// Whether currently buffering
  bool get buffering => _buffering;

  /// Current volume (0.0 - 1.0)
  double get volume => _volume;

  /// Whether the player is playing
  bool get isPlaying => _state == MpvPlayerState.playing;

  /// Whether the player is initialized
  bool get isInitialized => _initialized;

  /// Initialize the player
  Future<bool> initialize([String? libmpvPath]) async {
    if (_initialized) return true;
    if (_disposed) return false;

    // Set C locale for numeric formatting (required by mpv)
    setNumericLocaleToC();

    _mpv = LibMpv.load(libmpvPath);
    if (_mpv == null) {
      _errorController.add(MpvPlayerError(-1, 'Failed to load libmpv'));
      return false;
    }

    _ctx = _mpv!.mpvCreate();
    if (_ctx == null || _ctx == nullptr) {
      _errorController.add(MpvPlayerError(-2, 'Failed to create mpv context'));
      return false;
    }

    // Audio-only configuration - no video properties!
    _setOption('vo', 'null'); // No video output
    _setOption('vid', 'no'); // Disable video track
    _setOption('audio-display', 'no'); // No audio visualization
    _setOption('idle', 'yes'); // Don't exit when idle
    _setOption('keep-open', 'yes'); // Keep player open at end
    _setOption('audio-client-name', 'nhac'); // Audio client name
    _setOption('ytdl', 'no'); // Disable youtube-dl hook - we stream directly

    // HTTP streaming options
    _setOption('user-agent', 'nhac/1.0'); // Set user agent
    _setOption('demuxer-max-bytes', '50MiB'); // Buffer size
    _setOption('demuxer-max-back-bytes', '10MiB'); // Back buffer
    _setOption('cache', 'yes'); // Enable cache
    _setOption('cache-secs', '30'); // Cache 30 seconds ahead

    final result = _mpv!.mpvInitialize(_ctx!);
    if (result < 0) {
      final error = _mpv!.getErrorString(result);
      _errorController.add(MpvPlayerError(result, 'Init failed: $error'));
      _mpv!.mpvTerminateDestroy(_ctx!);
      _ctx = null;
      return false;
    }

    // Enable log messages for errors
    final levelPtr = 'error'.toNativeUtf8();
    _mpv!.mpvRequestLogMessages(_ctx!, levelPtr);
    calloc.free(levelPtr);

    // Observe essential properties
    _observeProperty('time-pos', MpvFormat.double_, 1);
    _observeProperty('duration', MpvFormat.double_, 2);
    _observeProperty('pause', MpvFormat.flag, 3);
    _observeProperty('eof-reached', MpvFormat.flag, 4);
    _observeProperty('volume', MpvFormat.double_, 5);
    _observeProperty('seeking', MpvFormat.flag, 6);
    _observeProperty('core-idle', MpvFormat.flag, 7);

    // Start event loop
    await _startEventLoop();

    _initialized = true;
    _updateState(MpvPlayerState.idle);
    return true;
  }

  void _setOption(String name, String value) {
    if (_ctx == null || _mpv == null) return;
    final namePtr = name.toNativeUtf8();
    final valuePtr = value.toNativeUtf8();
    _mpv!.mpvSetOptionString(_ctx!, namePtr, valuePtr);
    calloc.free(namePtr);
    calloc.free(valuePtr);
  }

  void _observeProperty(String name, int format, int id) {
    if (_ctx == null || _mpv == null) return;
    final namePtr = name.toNativeUtf8();
    _mpv!.mpvObserveProperty(_ctx!, id, namePtr, format);
    calloc.free(namePtr);
  }

  Future<void> _startEventLoop() async {
    _eventPort = ReceivePort();
    final initPort = ReceivePort();

    // Spawn event loop isolate
    _eventIsolate = await Isolate.spawn(
      _eventLoopEntry,
      _EventLoopInit(
        ctxAddress: _ctx!.address,
        sendPort: _eventPort!.sendPort,
        initPort: initPort.sendPort,
      ),
    );

    // Wait for command port
    _commandPort = await initPort.first as SendPort;
    initPort.close();

    // Listen for events
    _eventPort!.listen(_handleEvent);
  }

  void _handleEvent(dynamic message) {
    if (message is _PropertyChangeEvent) {
      switch (message.name) {
        case 'time-pos':
          if (message.value is double) {
            final pos = Duration(
              milliseconds: ((message.value as double) * 1000).round(),
            );
            if (pos != _position) {
              _position = pos;
              _positionController.add(_position);
            }
          }
        case 'duration':
          if (message.value is double) {
            final dur = Duration(
              milliseconds: ((message.value as double) * 1000).round(),
            );
            if (dur != _duration) {
              _duration = dur;
              _durationController.add(_duration);
            }
          }
        case 'pause':
          if (message.value is bool) {
            final paused = message.value as bool;
            if (paused && _state == MpvPlayerState.playing) {
              _updateState(MpvPlayerState.paused);
            } else if (!paused && _state == MpvPlayerState.paused) {
              _updateState(MpvPlayerState.playing);
            }
          }
        case 'eof-reached':
          if (message.value == true) {
            _updateState(MpvPlayerState.completed);
          }
        case 'volume':
          if (message.value is double) {
            final vol = (message.value as double) / 100.0;
            if (vol != _volume) {
              _volume = vol.clamp(0.0, 1.0);
              _volumeController.add(_volume);
            }
          }
        case 'seeking':
          if (message.value is bool) {
            _buffering = message.value as bool;
            _bufferingController.add(_buffering);
          }
        case 'core-idle':
          // Core idle indicates buffering when not paused
          if (message.value is bool && _state == MpvPlayerState.playing) {
            _buffering = message.value as bool;
            _bufferingController.add(_buffering);
          }
      }
    } else if (message is _FileLoadedEvent) {
      _updateState(MpvPlayerState.ready);
    } else if (message is _EndFileEvent) {
      if (message.reason == MpvEndFileReason.eof) {
        _updateState(MpvPlayerState.completed);
      } else if (message.reason == MpvEndFileReason.error) {
        _updateState(MpvPlayerState.error);
        _errorController.add(MpvPlayerError(message.error, 'Playback error'));
      }
    } else if (message is _LogMessageEvent) {
      if (message.level <= MpvLogLevel.error) {
        _errorController.add(
          MpvPlayerError(0, '[${message.prefix}] ${message.text}'),
        );
      }
    }
  }

  void _updateState(MpvPlayerState newState) {
    if (_state != newState) {
      _state = newState;
      _stateController.add(_state);
    }
  }

  /// Load and play a URL or file path
  Future<void> load(String uri, {bool autoPlay = true}) async {
    if (!_initialized || _ctx == null) return;

    _updateState(MpvPlayerState.loading);
    _position = Duration.zero;
    _duration = null;
    _positionController.add(_position);
    _durationController.add(null);

    // If not auto-playing, set pause before loading
    if (!autoPlay) {
      await _setProperty('pause', 'yes');
    }

    await _command(['loadfile', uri, 'replace']);

    // If auto-playing, ensure we're not paused
    if (autoPlay) {
      await _setProperty('pause', 'no');
    }
  }

  /// Start or resume playback
  Future<void> play() async {
    if (!_initialized || _ctx == null) return;
    await _setProperty('pause', 'no');
    _updateState(MpvPlayerState.playing);
  }

  /// Pause playback
  Future<void> pause() async {
    if (!_initialized || _ctx == null) return;
    await _setProperty('pause', 'yes');
    _updateState(MpvPlayerState.paused);
  }

  /// Toggle play/pause
  Future<void> togglePlayPause() async {
    if (isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  /// Stop playback
  Future<void> stop() async {
    if (!_initialized || _ctx == null) return;
    await _command(['stop']);
    _position = Duration.zero;
    _duration = null;
    _positionController.add(_position);
    _durationController.add(null);
    _updateState(MpvPlayerState.idle);
  }

  /// Seek to position
  Future<void> seek(Duration position) async {
    if (!_initialized || _ctx == null) return;
    final seconds = position.inMilliseconds / 1000.0;
    await _setProperty('time-pos', seconds.toString());
  }

  /// Seek by offset
  Future<void> seekRelative(Duration offset) async {
    if (!_initialized || _ctx == null) return;
    final seconds = offset.inMilliseconds / 1000.0;
    await _command(['seek', seconds.toString(), 'relative']);
  }

  /// Set volume (0.0 - 1.0)
  Future<void> setVolume(double volume) async {
    if (!_initialized || _ctx == null) return;
    final mpvVolume = (volume.clamp(0.0, 1.0) * 100).round();
    await _setProperty('volume', mpvVolume.toString());
  }

  /// Set playback speed
  Future<void> setSpeed(double speed) async {
    if (!_initialized || _ctx == null) return;
    await _setProperty('speed', speed.toString());
  }

  Future<void> _command(List<String> args) async {
    if (_ctx == null || _mpv == null) return;

    // Allocate array of pointers
    final argsPtr = calloc<Pointer<Utf8>>(args.length + 1);
    for (var i = 0; i < args.length; i++) {
      argsPtr[i] = args[i].toNativeUtf8();
    }
    argsPtr[args.length] = nullptr;

    _mpv!.mpvCommand(_ctx!, argsPtr.cast());

    // Free memory
    for (var i = 0; i < args.length; i++) {
      calloc.free(argsPtr[i]);
    }
    calloc.free(argsPtr);
  }

  Future<void> _setProperty(String name, String value) async {
    if (_ctx == null || _mpv == null) return;
    final namePtr = name.toNativeUtf8();
    final valuePtr = value.toNativeUtf8();
    _mpv!.mpvSetPropertyString(_ctx!, namePtr, valuePtr);
    calloc.free(namePtr);
    calloc.free(valuePtr);
  }

  /// Dispose the player
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    // Stop event loop
    _commandPort?.send('stop');
    _eventIsolate?.kill(priority: Isolate.immediate);
    _eventPort?.close();

    // Destroy mpv
    if (_ctx != null && _mpv != null) {
      _mpv!.mpvTerminateDestroy(_ctx!);
    }

    // Close streams
    await _stateController.close();
    await _positionController.close();
    await _durationController.close();
    await _bufferingController.close();
    await _errorController.close();
    await _volumeController.close();

    _ctx = null;
    _mpv = null;
    _initialized = false;
  }
}

// Event loop isolate communication

class _EventLoopInit {
  final int ctxAddress;
  final SendPort sendPort;
  final SendPort initPort;

  _EventLoopInit({
    required this.ctxAddress,
    required this.sendPort,
    required this.initPort,
  });
}

class _PropertyChangeEvent {
  final String name;
  final dynamic value;

  _PropertyChangeEvent(this.name, this.value);
}

class _FileLoadedEvent {}

class _EndFileEvent {
  final int reason;
  final int error;

  _EndFileEvent(this.reason, this.error);
}

class _LogMessageEvent {
  final String prefix;
  final String text;
  final int level;

  _LogMessageEvent(this.prefix, this.text, this.level);
}

/// Event loop that runs in a separate isolate
void _eventLoopEntry(_EventLoopInit init) {
  final mpv = LibMpv.load();
  if (mpv == null) return;

  final ctx = Pointer<MpvHandle>.fromAddress(init.ctxAddress);
  final sendPort = init.sendPort;

  // Set up command port for stopping
  final commandPort = ReceivePort();
  init.initPort.send(commandPort.sendPort);

  var running = true;
  commandPort.listen((message) {
    if (message == 'stop') {
      running = false;
      mpv.mpvWakeup(ctx);
    }
  });

  // Event loop
  while (running) {
    final event = mpv.mpvWaitEvent(ctx, 0.1); // 100ms timeout
    if (event == nullptr) continue;

    final eventId = event.ref.eventId;

    switch (eventId) {
      case MpvEventId.none:
        // Timeout, continue
        break;

      case MpvEventId.shutdown:
        running = false;
        break;

      case MpvEventId.fileLoaded:
        sendPort.send(_FileLoadedEvent());
        break;

      case MpvEventId.endFile:
        final data = event.ref.data.cast<MpvEventEndFile>();
        if (data != nullptr) {
          sendPort.send(_EndFileEvent(data.ref.reason, data.ref.error));
        }
        break;

      case MpvEventId.propertyChange:
        final data = event.ref.data.cast<MpvEventProperty>();
        if (data != nullptr && data.ref.name != nullptr) {
          final name = data.ref.name.toDartString();
          dynamic value;

          switch (data.ref.format) {
            case MpvFormat.double_:
              if (data.ref.data != nullptr) {
                value = data.ref.data.cast<Double>().value;
              }
            case MpvFormat.flag:
              if (data.ref.data != nullptr) {
                value = data.ref.data.cast<Int32>().value != 0;
              }
            case MpvFormat.int64:
              if (data.ref.data != nullptr) {
                value = data.ref.data.cast<Int64>().value;
              }
            case MpvFormat.string:
              if (data.ref.data != nullptr) {
                final strPtr = data.ref.data.cast<Pointer<Utf8>>().value;
                if (strPtr != nullptr) {
                  value = strPtr.toDartString();
                }
              }
          }

          if (value != null) {
            sendPort.send(_PropertyChangeEvent(name, value));
          }
        }
        break;

      case MpvEventId.logMessage:
        final data = event.ref.data.cast<MpvEventLogMessage>();
        if (data != nullptr) {
          final prefix =
              data.ref.prefix != nullptr ? data.ref.prefix.toDartString() : '';
          final text =
              data.ref.text != nullptr ? data.ref.text.toDartString() : '';
          sendPort.send(_LogMessageEvent(prefix, text, data.ref.logLevel));
        }
        break;
    }
  }

  commandPort.close();
}
