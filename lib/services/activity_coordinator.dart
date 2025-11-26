import 'package:flutter/foundation.dart';

/// Coordinates app activity state to manage background tasks and battery usage.
///
/// Activity states:
/// - Foreground: App is visible, all background tasks enabled
/// - Playing (background): Music playing, health checks enabled, sync disabled
/// - Downloading (background): Downloads active, sync disabled
/// - Idle (background): No activity, all background tasks suspended (zero battery)
class ActivityCoordinator extends ChangeNotifier {
  bool _isInForeground = true;
  bool _isPlaying = false;
  bool _isDownloading = false;

  /// Whether the app is currently in the foreground
  bool get isInForeground => _isInForeground;

  /// Whether music is currently playing
  bool get isPlaying => _isPlaying;

  /// Whether downloads are active
  bool get isDownloading => _isDownloading;

  /// Whether server health checks should run (foreground or playing)
  bool get shouldRunHealthChecks => _isInForeground || _isPlaying;

  /// Whether sync tasks should run (only in foreground)
  bool get shouldRunSyncTasks => _isInForeground;

  /// Whether the app is truly idle (no activity at all)
  bool get isIdle => !_isInForeground && !_isPlaying && !_isDownloading;

  /// Callbacks for services to register suspend/resume actions
  final List<VoidCallback> _suspendCallbacks = [];
  final List<VoidCallback> _resumeCallbacks = [];

  /// Register a callback to be called when background tasks should suspend
  void registerSuspendCallback(VoidCallback callback) {
    _suspendCallbacks.add(callback);
  }

  /// Register a callback to be called when background tasks should resume
  void registerResumeCallback(VoidCallback callback) {
    _resumeCallbacks.add(callback);
  }

  /// Unregister suspend/resume callbacks
  void unregisterCallbacks(VoidCallback suspendCallback, VoidCallback resumeCallback) {
    _suspendCallbacks.remove(suspendCallback);
    _resumeCallbacks.remove(resumeCallback);
  }

  /// Update foreground state (called from app lifecycle observer)
  void setForegroundState(bool isForeground) {
    if (_isInForeground == isForeground) return;

    final wasIdle = isIdle;
    _isInForeground = isForeground;
    final nowIdle = isIdle;

    if (kDebugMode) {
      debugPrint('[ActivityCoordinator] Foreground: $isForeground, isIdle: $nowIdle');
    }

    _notifyStateChange(wasIdle, nowIdle);
    notifyListeners();
  }

  /// Update playing state (called from PlayerProvider)
  void setPlayingState(bool isPlaying) {
    if (_isPlaying == isPlaying) return;

    final wasIdle = this.isIdle;
    _isPlaying = isPlaying;
    final nowIdle = this.isIdle;

    if (kDebugMode) {
      debugPrint('[ActivityCoordinator] Playing: $isPlaying, isIdle: $nowIdle');
    }

    _notifyStateChange(wasIdle, nowIdle);
    notifyListeners();
  }

  /// Update downloading state (called from AlbumDownloadService)
  void setDownloadingState(bool isDownloading) {
    if (_isDownloading == isDownloading) return;

    final wasIdle = this.isIdle;
    _isDownloading = isDownloading;
    final nowIdle = this.isIdle;

    if (kDebugMode) {
      debugPrint('[ActivityCoordinator] Downloading: $isDownloading, isIdle: $nowIdle');
    }

    _notifyStateChange(wasIdle, nowIdle);
    notifyListeners();
  }

  void _notifyStateChange(bool wasIdle, bool nowIdle) {
    if (!wasIdle && nowIdle) {
      // Transitioning to idle - suspend all background tasks
      if (kDebugMode) {
        debugPrint('[ActivityCoordinator] Suspending background tasks');
      }
      for (final callback in _suspendCallbacks) {
        callback();
      }
    } else if (wasIdle && !nowIdle) {
      // Transitioning from idle - resume background tasks
      if (kDebugMode) {
        debugPrint('[ActivityCoordinator] Resuming background tasks');
      }
      for (final callback in _resumeCallbacks) {
        callback();
      }
    }
  }

  @override
  void dispose() {
    _suspendCallbacks.clear();
    _resumeCallbacks.clear();
    super.dispose();
  }
}
