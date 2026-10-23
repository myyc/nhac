/// High-level audio player using libmpv FFI bindings.
///
/// This is an audio-only player that doesn't set any video properties,
/// making it compatible with audio-only mpv builds.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:ffi';
import 'dart:io';
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

/// High-level mpv audio player.
///
/// The mpv handle is owned entirely by a dedicated isolate: every libmpv
/// call happens there and the UI isolate only exchanges port messages.
/// On Linux the UI isolate is the GTK main thread, so this isolation is
/// what guarantees a wedged mpv core (e.g. a stalled audio backend) can
/// never freeze the app.
class MpvPlayer {
  Isolate? _eventIsolate;
  ReceivePort? _eventPort;
  SendPort? _commandPort;

  // Load watchdog: fires when mpv produces neither fileLoaded nor endFile
  // after load(), which is how a stalled audio backend presents.
  Timer? _loadWatchdog;

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

  // Resolved when mpv emits fileLoaded after a load() call. Used to defer
  // post-load seeks until mpv is actually ready to handle them.
  Completer<void>? _fileLoadedCompleter;

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
  Future<bool> initialize() async {
    if (_initialized) return true;
    if (_disposed) return false;

    _eventPort = ReceivePort();
    final initPort = ReceivePort();

    // Spawn the isolate that owns the mpv handle
    _eventIsolate = await Isolate.spawn(
      _playerIsolateEntry,
      _IsolateInit(
        eventPort: _eventPort!.sendPort,
        initPort: initPort.sendPort,
      ),
    );

    // Wait for the isolate to report init success/failure
    final result = await initPort.first;
    initPort.close();

    if (result is! _IsolateReady) {
      final message = result is _IsolateInitFailed ? result.message : 'unknown';
      _errorController.add(MpvPlayerError(-2, 'Init failed: $message'));
      // ignore: avoid_print
      print('[MpvPlayer] init failed: $message');
      // Minimal cleanup only — don't close the stream controllers here, so
      // subscribers attaching after a failed init don't hit closed streams.
      _eventIsolate?.kill(priority: Isolate.immediate);
      _eventIsolate = null;
      _eventPort?.close();
      _eventPort = null;
      return false;
    }

    _commandPort = result.commandPort;
    _eventPort!.listen(_handleEvent);

    _initialized = true;
    _updateState(MpvPlayerState.idle);
    return true;
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
            // Mirror mpv's pause flag onto our state. Cover transitions from
            // ready/loading too — autoPlay loads land us in `ready` and only
            // a pause=false event marks the actual start of playback.
            if (paused) {
              if (_state == MpvPlayerState.playing ||
                  _state == MpvPlayerState.ready ||
                  _state == MpvPlayerState.loading) {
                _updateState(MpvPlayerState.paused);
              }
            } else {
              if (_state == MpvPlayerState.paused ||
                  _state == MpvPlayerState.ready ||
                  _state == MpvPlayerState.loading) {
                _updateState(MpvPlayerState.playing);
              }
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
      _loadWatchdog?.cancel();
      // Only mark ready if we're still in the loading phase. load() may have
      // already moved us to playing/paused based on the autoPlay intent;
      // don't override that here.
      if (_state == MpvPlayerState.loading) {
        _updateState(MpvPlayerState.ready);
      }
      // Unblock any load() call waiting to seek post-load.
      if (_fileLoadedCompleter != null && !_fileLoadedCompleter!.isCompleted) {
        _fileLoadedCompleter!.complete();
      }
    } else if (message is _EndFileEvent) {
      _loadWatchdog?.cancel();
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

  /// Load and play a URL or file path. If [startPosition] is provided, the
  /// player will seek to that offset once mpv has actually loaded the file
  /// (waiting on the FileLoaded event — sending a seek before then is
  /// unreliable for HTTP-streamed sources).
  Future<void> load(String uri, {bool autoPlay = true, Duration? startPosition}) async {
    if (!_initialized || _commandPort == null) return;

    _updateState(MpvPlayerState.loading);
    _position = startPosition ?? Duration.zero;
    _duration = null;
    _positionController.add(_position);
    _durationController.add(null);

    // Stay paused until the seek has been issued, so playback doesn't briefly
    // start at 0 before jumping. Then unpause for autoPlay.
    final hasStart = startPosition != null && startPosition.inMilliseconds > 0;
    if (hasStart || !autoPlay) {
      await _setProperty('pause', 'yes');
    }

    _fileLoadedCompleter = Completer<void>();
    await _command(['loadfile', uri, 'replace']);

    // If the audio backend is wedged, mpv never emits fileLoaded or endFile.
    // Surface an error instead of hanging in `loading` forever.
    _loadWatchdog?.cancel();
    _loadWatchdog = Timer(const Duration(seconds: 15), () {
      if (_state != MpvPlayerState.loading) return;
      _updateState(MpvPlayerState.error);
      _errorController.add(
        MpvPlayerError(0, 'Playback timed out — audio backend unavailable'),
      );
      if (_fileLoadedCompleter != null && !_fileLoadedCompleter!.isCompleted) {
        _fileLoadedCompleter!.complete();
      }
    });

    if (hasStart) {
      // Wait for mpv to actually load the file before seeking. Bail after
      // a short timeout so we don't hang forever on a bad URL.
      try {
        await _fileLoadedCompleter!.future
            .timeout(const Duration(seconds: 8));
        final secs = startPosition.inMilliseconds / 1000.0;
        await _command(['seek', secs.toString(), 'absolute']);
      } catch (_) {
        // Timed out; carry on without the seek.
      }
    }

    if (autoPlay) {
      // Setting pause=no when it was already no (default) doesn't emit a
      // property-change event, so we'd never leave `ready`. Drive the state
      // optimistically; an endFile(error) event will roll us back if loading
      // fails.
      await _setProperty('pause', 'no');
      _updateState(MpvPlayerState.playing);
    } else {
      _updateState(MpvPlayerState.paused);
    }
  }

  /// Start or resume playback
  Future<void> play() async {
    print('[MpvPlayer] play() called, state=$_state, initialized=$_initialized');
    if (!_initialized) return;
    await _setProperty('pause', 'no');
    _updateState(MpvPlayerState.playing);
  }

  /// Pause playback
  Future<void> pause() async {
    print('[MpvPlayer] pause() called, state=$_state');
    if (!_initialized) return;
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
    if (!_initialized) return;
    await _command(['stop']);
    _position = Duration.zero;
    _duration = null;
    _positionController.add(_position);
    _durationController.add(null);
    _updateState(MpvPlayerState.idle);
  }

  /// Seek to position
  Future<void> seek(Duration position) async {
    print('[MpvPlayer] seek($position) called, state=$_state');
    if (!_initialized) return;
    final seconds = position.inMilliseconds / 1000.0;
    // Use the seek command (absolute) — more reliable than setting time-pos
    // for HTTP-streamed sources where mpv must coordinate cache seeks.
    await _command(['seek', seconds.toString(), 'absolute']);
  }

  /// Seek by offset
  Future<void> seekRelative(Duration offset) async {
    if (!_initialized) return;
    final seconds = offset.inMilliseconds / 1000.0;
    await _command(['seek', seconds.toString(), 'relative']);
  }

  /// Set volume (0.0 - 1.0)
  Future<void> setVolume(double volume) async {
    if (!_initialized) return;
    final mpvVolume = (volume.clamp(0.0, 1.0) * 100).round();
    await _setProperty('volume', mpvVolume.toString());
  }

  /// Set playback speed
  Future<void> setSpeed(double speed) async {
    if (!_initialized) return;
    await _setProperty('speed', speed.toString());
  }

  Future<void> _command(List<String> args) async {
    final port = _commandPort;
    if (port == null) return;
    port.send(_IsolateCommand(args));
  }

  Future<void> _setProperty(String name, String value) async {
    await _command(['set', name, value]);
  }

  /// Dispose the player
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _loadWatchdog?.cancel();

    // Ask the owning isolate to shut mpv down and exit. If the core is
    // wedged that can hang, so fall back to killing the isolate.
    final isolate = _eventIsolate;
    if (isolate != null && _commandPort != null) {
      final exited = ReceivePort();
      isolate.addOnExitListener(exited.sendPort);
      _commandPort!.send(const _IsolateShutdown());
      try {
        await exited.first.timeout(const Duration(seconds: 2));
      } catch (_) {
        isolate.kill(priority: Isolate.immediate);
      }
      exited.close();
    } else {
      isolate?.kill(priority: Isolate.immediate);
    }
    _eventPort?.close();

    // Close streams
    await _stateController.close();
    await _positionController.close();
    await _durationController.close();
    await _bufferingController.close();
    await _errorController.close();
    await _volumeController.close();

    _eventIsolate = null;
    _commandPort = null;
    _initialized = false;
  }
}

// Player isolate communication

class _IsolateInit {
  final SendPort eventPort;
  final SendPort initPort;

  _IsolateInit({
    required this.eventPort,
    required this.initPort,
  });
}

class _IsolateReady {
  final SendPort commandPort;

  _IsolateReady(this.commandPort);
}

class _IsolateInitFailed {
  final String message;

  _IsolateInitFailed(this.message);
}

class _IsolateCommand {
  final List<String> args;

  const _IsolateCommand(this.args);
}

class _IsolateShutdown {
  const _IsolateShutdown();
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

void _isolateSetOption(LibMpv mpv, Pointer<MpvHandle> ctx, String name, String value) {
  final namePtr = name.toNativeUtf8();
  final valuePtr = value.toNativeUtf8();
  mpv.mpvSetOptionString(ctx, namePtr, valuePtr);
  calloc.free(namePtr);
  calloc.free(valuePtr);
}

void _isolateObserveProperty(LibMpv mpv, Pointer<MpvHandle> ctx, String name, int format, int id) {
  final namePtr = name.toNativeUtf8();
  mpv.mpvObserveProperty(ctx, id, namePtr, format);
  calloc.free(namePtr);
}

void _isolateRunCommand(LibMpv mpv, Pointer<MpvHandle> ctx, List<String> args) {
  final argsPtr = calloc<Pointer<Utf8>>(args.length + 1);
  for (var i = 0; i < args.length; i++) {
    argsPtr[i] = args[i].toNativeUtf8();
  }
  argsPtr[args.length] = nullptr;

  mpv.mpvCommand(ctx, argsPtr.cast());

  for (var i = 0; i < args.length; i++) {
    calloc.free(argsPtr[i]);
  }
  calloc.free(argsPtr);
}

/// Isolate that owns the mpv handle: performs every libmpv call (creation,
/// options, commands, event loop, destruction) so the UI isolate never
/// blocks on the playback core.
Future<void> _playerIsolateEntry(_IsolateInit init) async {
  final sendPort = init.eventPort;

  // Set C locale for numeric formatting (required by mpv)
  setNumericLocaleToC();

  final mpv = LibMpv.load();
  if (mpv == null) {
    init.initPort.send(_IsolateInitFailed('Failed to resolve libmpv symbols'));
    return;
  }

  final ctx = mpv.mpvCreate();
  if (ctx == nullptr) {
    init.initPort.send(_IsolateInitFailed('mpv_create() returned null'));
    return;
  }

  // Audio-only configuration - no video properties!
  _isolateSetOption(mpv, ctx, 'vo', 'null'); // No video output
  _isolateSetOption(mpv, ctx, 'vid', 'no'); // Disable video track
  _isolateSetOption(mpv, ctx, 'audio-display', 'no'); // No audio visualization
  _isolateSetOption(mpv, ctx, 'idle', 'yes'); // Don't exit when idle
  _isolateSetOption(mpv, ctx, 'keep-open', 'yes'); // Keep player open at end
  _isolateSetOption(mpv, ctx, 'audio-client-name', 'nhac'); // Audio client name
  _isolateSetOption(mpv, ctx, 'ytdl', 'no'); // Disable youtube-dl hook

  // HTTP streaming options
  _isolateSetOption(mpv, ctx, 'user-agent', 'nhac/1.0');
  _isolateSetOption(mpv, ctx, 'demuxer-max-bytes', '50MiB');
  _isolateSetOption(mpv, ctx, 'demuxer-max-back-bytes', '10MiB');
  _isolateSetOption(mpv, ctx, 'cache', 'yes');
  _isolateSetOption(mpv, ctx, 'cache-secs', '30');

  if (Platform.isLinux) {
    // Prefer the PulseAudio socket: a PipeWire server that restricts
    // sandboxed clients never completes the native handshake, which
    // wedges AO init entirely.
    _isolateSetOption(mpv, ctx, 'ao', 'pulse,pipewire,alsa');
    // The pulse latency hacks leave streams corked against
    // pipewire-pulse >= 1.6.5 (playback never starts).
    _isolateSetOption(mpv, ctx, 'pulse-latency-hacks', 'no');
  }

  final result = mpv.mpvInitialize(ctx);
  if (result < 0) {
    final error = mpv.getErrorString(result);
    mpv.mpvTerminateDestroy(ctx);
    init.initPort.send(_IsolateInitFailed('mpv_initialize() failed: $error (code $result)'));
    return;
  }

  // Enable log messages for errors
  final levelPtr = 'error'.toNativeUtf8();
  mpv.mpvRequestLogMessages(ctx, levelPtr);
  calloc.free(levelPtr);

  // Observe essential properties
  _isolateObserveProperty(mpv, ctx, 'time-pos', MpvFormat.double_, 1);
  _isolateObserveProperty(mpv, ctx, 'duration', MpvFormat.double_, 2);
  _isolateObserveProperty(mpv, ctx, 'pause', MpvFormat.flag, 3);
  _isolateObserveProperty(mpv, ctx, 'eof-reached', MpvFormat.flag, 4);
  _isolateObserveProperty(mpv, ctx, 'volume', MpvFormat.double_, 5);
  _isolateObserveProperty(mpv, ctx, 'seeking', MpvFormat.flag, 6);
  _isolateObserveProperty(mpv, ctx, 'core-idle', MpvFormat.flag, 7);

  // Command channel from the UI isolate. Incoming messages are queued here
  // by the event loop and drained between mpv_wait_event() calls below.
  final commandQueue = Queue<Object>();
  final commandPort = ReceivePort();
  commandPort.listen((m) => commandQueue.add(m));
  init.initPort.send(_IsolateReady(commandPort.sendPort));

  var running = true;
  while (running) {
    // Let the event loop deliver queued commands.
    await Future(() {});

    while (commandQueue.isNotEmpty) {
      final message = commandQueue.removeFirst();
      if (message is _IsolateShutdown) {
        running = false;
      } else if (message is _IsolateCommand) {
        _isolateRunCommand(mpv, ctx, message.args);
      }
    }
    if (!running) break;

    final event = mpv.mpvWaitEvent(ctx, 0.02); // 20ms timeout
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

  mpv.mpvTerminateDestroy(ctx);
  commandPort.close();
}
