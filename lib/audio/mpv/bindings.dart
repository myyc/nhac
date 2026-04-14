/// Minimal FFI bindings for libmpv audio playback.
///
/// This is a hand-written minimal binding that only includes functions
/// needed for audio playback. No video-related properties are used.
library;

import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

// libc setlocale binding for fixing mpv locale issues
typedef _SetlocaleNative = Pointer<Utf8> Function(Int32, Pointer<Utf8>);
typedef _Setlocale = Pointer<Utf8> Function(int, Pointer<Utf8>);

/// Set the C locale for numeric formatting (required by mpv)
void setNumericLocaleToC() {
  try {
    final libc = Platform.isLinux
        ? DynamicLibrary.open('libc.so.6')
        : Platform.isWindows
            ? DynamicLibrary.open('msvcrt.dll')
            : null;

    if (libc == null) return;

    final setlocale = libc
        .lookup<NativeFunction<_SetlocaleNative>>('setlocale')
        .asFunction<_Setlocale>();

    // LC_NUMERIC = 1 on Linux, 4 on Windows
    final lcNumeric = Platform.isLinux ? 1 : 4;
    final cLocale = 'C'.toNativeUtf8();
    setlocale(lcNumeric, cLocale);
    calloc.free(cLocale);
  } catch (e) {
    // Ignore errors - locale setting is best effort
  }
}

// Opaque handle type
final class MpvHandle extends Opaque {}

// Event structure
final class MpvEvent extends Struct {
  @Int32()
  external int eventId;

  @Int32()
  external int error;

  @Uint64()
  external int replyUserdata;

  external Pointer<Void> data;
}

// Property change event data
final class MpvEventProperty extends Struct {
  external Pointer<Utf8> name;

  @Int32()
  external int format;

  external Pointer<Void> data;
}

// Log message event data
final class MpvEventLogMessage extends Struct {
  external Pointer<Utf8> prefix;
  external Pointer<Utf8> level;
  external Pointer<Utf8> text;

  @Int32()
  external int logLevel;
}

// End file event data
final class MpvEventEndFile extends Struct {
  @Int32()
  external int reason;

  @Int32()
  external int error;

  @Int64()
  external int playlistEntryId;

  @Int64()
  external int playlistInsertId;

  @Int32()
  external int playlistInsertNumEntries;
}

/// MPV event IDs
abstract class MpvEventId {
  static const none = 0;
  static const shutdown = 1;
  static const logMessage = 2;
  static const getPropertyReply = 3;
  static const setPropertyReply = 4;
  static const commandReply = 5;
  static const startFile = 6;
  static const endFile = 7;
  static const fileLoaded = 8;
  static const propertyChange = 22;
  static const seek = 20;
  static const playbackRestart = 21;
}

/// MPV end file reasons
abstract class MpvEndFileReason {
  static const eof = 0;
  static const stop = 2;
  static const quit = 3;
  static const error = 4;
}

/// MPV format types
abstract class MpvFormat {
  static const none = 0;
  static const string = 1;
  static const osdString = 2;
  static const flag = 3;
  static const int64 = 4;
  static const double_ = 5;
  static const node = 6;
}

/// MPV error codes
abstract class MpvError {
  static const success = 0;
  static const eventQueueFull = -1;
  static const noMem = -2;
  static const uninitialized = -3;
  static const invalidParameter = -4;
  static const optionNotFound = -5;
  static const optionFormat = -6;
  static const optionError = -7;
  static const propertyNotFound = -8;
  static const propertyFormat = -9;
  static const propertyUnavailable = -10;
  static const propertyError = -11;
  static const command = -12;
  static const loadingFailed = -13;
  static const aoInitFailed = -14;
  static const voInitFailed = -15;
  static const nothingToPlay = -16;
  static const unknownFormat = -17;
  static const unsupported = -18;
  static const notImplemented = -19;
  static const generic = -20;
}

/// Log levels
abstract class MpvLogLevel {
  static const none = 0;
  static const fatal = 10;
  static const error = 20;
  static const warn = 30;
  static const info = 40;
  static const v = 50;
  static const debug = 60;
  static const trace = 70;
}

// Native function typedefs
typedef _MpvCreateNative = Pointer<MpvHandle> Function();
typedef _MpvCreate = Pointer<MpvHandle> Function();

typedef _MpvInitializeNative = Int32 Function(Pointer<MpvHandle>);
typedef _MpvInitialize = int Function(Pointer<MpvHandle>);

typedef _MpvTerminateDestroyNative = Void Function(Pointer<MpvHandle>);
typedef _MpvTerminateDestroy = void Function(Pointer<MpvHandle>);

typedef _MpvSetOptionStringNative = Int32 Function(
    Pointer<MpvHandle>, Pointer<Utf8>, Pointer<Utf8>);
typedef _MpvSetOptionString = int Function(
    Pointer<MpvHandle>, Pointer<Utf8>, Pointer<Utf8>);

typedef _MpvCommandNative = Int32 Function(
    Pointer<MpvHandle>, Pointer<Pointer<Utf8>>);
typedef _MpvCommand = int Function(
    Pointer<MpvHandle>, Pointer<Pointer<Utf8>>);

typedef _MpvCommandStringNative = Int32 Function(
    Pointer<MpvHandle>, Pointer<Utf8>);
typedef _MpvCommandString = int Function(Pointer<MpvHandle>, Pointer<Utf8>);

typedef _MpvSetPropertyStringNative = Int32 Function(
    Pointer<MpvHandle>, Pointer<Utf8>, Pointer<Utf8>);
typedef _MpvSetPropertyString = int Function(
    Pointer<MpvHandle>, Pointer<Utf8>, Pointer<Utf8>);

typedef _MpvSetPropertyNative = Int32 Function(
    Pointer<MpvHandle>, Pointer<Utf8>, Int32, Pointer<Void>);
typedef _MpvSetProperty = int Function(
    Pointer<MpvHandle>, Pointer<Utf8>, int, Pointer<Void>);

typedef _MpvGetPropertyStringNative = Pointer<Utf8> Function(
    Pointer<MpvHandle>, Pointer<Utf8>);
typedef _MpvGetPropertyString = Pointer<Utf8> Function(
    Pointer<MpvHandle>, Pointer<Utf8>);

typedef _MpvGetPropertyNative = Int32 Function(
    Pointer<MpvHandle>, Pointer<Utf8>, Int32, Pointer<Void>);
typedef _MpvGetProperty = int Function(
    Pointer<MpvHandle>, Pointer<Utf8>, int, Pointer<Void>);

typedef _MpvObservePropertyNative = Int32 Function(
    Pointer<MpvHandle>, Uint64, Pointer<Utf8>, Int32);
typedef _MpvObserveProperty = int Function(
    Pointer<MpvHandle>, int, Pointer<Utf8>, int);

typedef _MpvWaitEventNative = Pointer<MpvEvent> Function(
    Pointer<MpvHandle>, Double);
typedef _MpvWaitEvent = Pointer<MpvEvent> Function(Pointer<MpvHandle>, double);

typedef _MpvWakeupNative = Void Function(Pointer<MpvHandle>);
typedef _MpvWakeup = void Function(Pointer<MpvHandle>);

typedef _MpvFreeNative = Void Function(Pointer<Void>);
typedef _MpvFree = void Function(Pointer<Void>);

typedef _MpvErrorStringNative = Pointer<Utf8> Function(Int32);
typedef _MpvErrorString = Pointer<Utf8> Function(int);

typedef _MpvRequestLogMessagesNative = Int32 Function(
    Pointer<MpvHandle>, Pointer<Utf8>);
typedef _MpvRequestLogMessages = int Function(
    Pointer<MpvHandle>, Pointer<Utf8>);

/// Minimal libmpv bindings for audio playback
class LibMpv {
  final DynamicLibrary _lib;

  late final _MpvCreate mpvCreate;
  late final _MpvInitialize mpvInitialize;
  late final _MpvTerminateDestroy mpvTerminateDestroy;
  late final _MpvSetOptionString mpvSetOptionString;
  late final _MpvCommand mpvCommand;
  late final _MpvCommandString mpvCommandString;
  late final _MpvSetPropertyString mpvSetPropertyString;
  late final _MpvSetProperty mpvSetProperty;
  late final _MpvGetPropertyString mpvGetPropertyString;
  late final _MpvGetProperty mpvGetProperty;
  late final _MpvObserveProperty mpvObserveProperty;
  late final _MpvWaitEvent mpvWaitEvent;
  late final _MpvWakeup mpvWakeup;
  late final _MpvFree mpvFree;
  late final _MpvErrorString mpvErrorString;
  late final _MpvRequestLogMessages mpvRequestLogMessages;

  LibMpv._(this._lib) {
    mpvCreate = _lib
        .lookup<NativeFunction<_MpvCreateNative>>('mpv_create')
        .asFunction();

    mpvInitialize = _lib
        .lookup<NativeFunction<_MpvInitializeNative>>('mpv_initialize')
        .asFunction();

    mpvTerminateDestroy = _lib
        .lookup<NativeFunction<_MpvTerminateDestroyNative>>(
            'mpv_terminate_destroy')
        .asFunction();

    mpvSetOptionString = _lib
        .lookup<NativeFunction<_MpvSetOptionStringNative>>(
            'mpv_set_option_string')
        .asFunction();

    mpvCommand = _lib
        .lookup<NativeFunction<_MpvCommandNative>>('mpv_command')
        .asFunction();

    mpvCommandString = _lib
        .lookup<NativeFunction<_MpvCommandStringNative>>('mpv_command_string')
        .asFunction();

    mpvSetPropertyString = _lib
        .lookup<NativeFunction<_MpvSetPropertyStringNative>>(
            'mpv_set_property_string')
        .asFunction();

    mpvSetProperty = _lib
        .lookup<NativeFunction<_MpvSetPropertyNative>>('mpv_set_property')
        .asFunction();

    mpvGetPropertyString = _lib
        .lookup<NativeFunction<_MpvGetPropertyStringNative>>(
            'mpv_get_property_string')
        .asFunction();

    mpvGetProperty = _lib
        .lookup<NativeFunction<_MpvGetPropertyNative>>('mpv_get_property')
        .asFunction();

    mpvObserveProperty = _lib
        .lookup<NativeFunction<_MpvObservePropertyNative>>(
            'mpv_observe_property')
        .asFunction();

    mpvWaitEvent = _lib
        .lookup<NativeFunction<_MpvWaitEventNative>>('mpv_wait_event')
        .asFunction();

    mpvWakeup = _lib
        .lookup<NativeFunction<_MpvWakeupNative>>('mpv_wakeup')
        .asFunction();

    mpvFree = _lib
        .lookup<NativeFunction<_MpvFreeNative>>('mpv_free')
        .asFunction();

    mpvErrorString = _lib
        .lookup<NativeFunction<_MpvErrorStringNative>>('mpv_error_string')
        .asFunction();

    mpvRequestLogMessages = _lib
        .lookup<NativeFunction<_MpvRequestLogMessagesNative>>(
            'mpv_request_log_messages')
        .asFunction();
  }

  /// Resolve libmpv symbols from the running process. The host runner is
  /// linked against libmpv at build time, so the dynamic linker has already
  /// loaded libmpv.so.2 by the time Dart code runs.
  static LibMpv? load() {
    try {
      return LibMpv._(DynamicLibrary.process());
    } catch (e) {
      // ignore: avoid_print
      print('[LibMpv] DynamicLibrary.process() failed: $e');
      return null;
    }
  }

  /// Get error message for error code
  String getErrorString(int error) {
    final ptr = mpvErrorString(error);
    if (ptr == nullptr) return 'Unknown error';
    return ptr.toDartString();
  }
}
