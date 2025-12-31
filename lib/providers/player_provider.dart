import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import '../models/song.dart';
import '../services/navidrome_api.dart';
import '../services/audio_cache_manager.dart';
import '../services/cache_service.dart';
import '../services/color_extraction_service.dart';
import '../services/performance_config.dart';
import '../services/database_helper.dart';
import '../services/notification_service.dart';
import '../providers/network_provider.dart';
import '../services/activity_coordinator.dart';
import '../audio/mpv/mpv_player.dart';
import '../main.dart' as app_main;

class PlayerProvider extends ChangeNotifier {
  final AudioPlayer _audioPlayer;
  final AudioCacheManager _cacheManager = AudioCacheManager();
  final ColorExtractionService _colorExtractionService = ColorExtractionService();
  NavidromeApi? _api;
  CacheService? _cacheService;
  NetworkProvider? _networkProvider;
  ActivityCoordinator? _activityCoordinator;
  Timer? _preloadTimer;
  Timer? _notificationTimer; // For debouncing notifications
  ConcatenatingAudioSource? _playlist;
  StreamSubscription? _mediaItemSubscription;
  StreamSubscription? _playerStateSubscription;
  StreamSubscription? _positionSubscription;
  StreamSubscription? _durationSubscription;
  StreamSubscription? _playbackEventSubscription;
  // MpvPlayer stream subscriptions (Linux/Windows)
  StreamSubscription? _mpvStateSubscription;
  StreamSubscription? _mpvPositionSubscription;
  StreamSubscription? _mpvDurationSubscription;
  DateTime? _lastPreloadCheck;
  DateTime? _lastPositionUpdate; // For throttling position updates
  bool _pendingNotification = false; // For batching notifications

  /// Check if we should use MpvPlayer (Linux/Windows with mpv available)
  bool get _useMpv => (Platform.isLinux || Platform.isWindows) &&
                      app_main.globalMpvPlayer != null &&
                      app_main.globalMpvPlayer!.isInitialized;

  // Connection event handling for playback recovery
  StreamSubscription<ConnectionEvent>? _connectionSubscription;
  int _playbackRetryCount = 0;
  bool _isRecovering = false;
  static const int _maxPlaybackRetries = 3;

  Song? _currentSong;
  String? _currentCoverArtPath; // Local path to cached cover art
  ExtractedColors? _currentColors; // Colors extracted from current album art
  List<Song> _queue = [];
  int _currentIndex = 0;
  bool _isPlaying = false;
  bool _isBuffering = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _volume = 1.0;
  DateTime? _lastPositionSave;
  bool _hasRestoredPosition = false;
  bool _isRestoring = false;
  Set<String> _preloadedSongIds = {};
  bool _useGaplessPlayback = false; // Use performance config setting
  bool _isPlayingOffline = false;
  bool _canPlayCurrentOffline = false;
  String? _lastError; // Last playback error message

  Song? get currentSong => _currentSong;
  String? get lastError => _lastError;
  ExtractedColors? get currentColors => _currentColors;
  List<Song> get queue => _queue;
  int get currentIndex => _currentIndex;
  bool get isPlaying => _isPlaying;
  bool get isBuffering => _isBuffering;
  Duration get position => _position;
  Duration get duration => _duration;
  double get volume => _volume;
  String? get currentStreamUrl => _currentSong != null && _api != null
      ? _api!.getStreamUrl(_currentSong!.id, suffix: _currentSong!.suffix)
      : null;
  bool get isPlayingOffline => _isPlayingOffline;
  bool get canPlayOffline => _currentSong != null && _canPlayCurrentOffline;
  
  // Navigation state getters for UI
  bool get canGoNext => _queue.isNotEmpty && _currentIndex < _queue.length - 1;
  bool get canGoPrevious => _queue.isNotEmpty && (_currentIndex > 0 || _position.inSeconds >= 3);
  
  PlayerProvider() : _audioPlayer = app_main.globalAudioPlayer {
    // Initialize performance configuration
    PerformanceConfig.initialize();

    // Apply performance settings
    _useGaplessPlayback = PerformanceConfig.enableGaplessPlayback;

    // Use the shared audio player instance from main.dart
    _initializePlayer();
    _cacheManager.initialize();
    _loadPersistedState();
  }
  
  void _cancelStreamSubscriptions() {
    _playerStateSubscription?.cancel();
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _playbackEventSubscription?.cancel();
    _mediaItemSubscription?.cancel();
    // Cancel mpv subscriptions
    _mpvStateSubscription?.cancel();
    _mpvPositionSubscription?.cancel();
    _mpvDurationSubscription?.cancel();
    _playerStateSubscription = null;
    _positionSubscription = null;
    _durationSubscription = null;
    _playbackEventSubscription = null;
    _mediaItemSubscription = null;
    _mpvStateSubscription = null;
    _mpvPositionSubscription = null;
    _mpvDurationSubscription = null;
  }

  /// Get cached audio path from database, validating file exists
  Future<String?> _getCachedAudioPath(String songId) async {
    try {
      final cacheInfo = await DatabaseHelper.getSongCacheInfo(songId);
      if (cacheInfo == null) return null;

      final cachedPath = cacheInfo['cached_path'] as String?;
      if (cachedPath == null) return null;

      final file = File(cachedPath);
      if (!await file.exists()) {
        // File missing - clear stale cache entry
        await DatabaseHelper.updateSongCacheStatus(songId, false, cachedPath: null);
        return null;
      }

      final size = await file.length();
      if (size < 1000) {
        // File too small (partial download) - clear
        await file.delete();
        await DatabaseHelper.updateSongCacheStatus(songId, false, cachedPath: null);
        return null;
      }

      return cachedPath;
    } catch (e) {
      if (kDebugMode) print('[PlayerProvider] Error getting cached path: $e');
      return null;
    }
  }
  
  void _initializePlayer() {
    // Cancel any existing subscriptions first
    _cancelStreamSubscriptions();

    // Use MpvPlayer on Linux/Windows if available
    if (_useMpv) {
      _initializeMpvPlayer();
      return;
    }

    // Add error handling for audio playback with recovery
    _playbackEventSubscription = _audioPlayer.playbackEventStream.listen(
      (event) {
        // Reset retry count on successful playback
        if (event.processingState == ProcessingState.ready) {
          _playbackRetryCount = 0;
        }
      },
      onError: (error, stackTrace) {
        if (kDebugMode) {
          print('[PlayerProvider] Playback error: $error');
        }
        _handlePlaybackError(error);
      },
    );

    _positionSubscription = _audioPlayer.positionStream.listen((position) {
      // Don't update position while restoring or buffering
      if (_isRestoring || _isBuffering) return;

      // Only update position if we've restored or if actively playing
      if (_hasRestoredPosition || _isPlaying) {
        _position = position;

        // Check if we need to preload upcoming tracks
        if (_isPlaying) {
          _checkPreloadNeeded();
        }

        // Save position every 5 seconds while playing
        if (_isPlaying) {
          final now = DateTime.now();
          if (_lastPositionSave == null ||
              now.difference(_lastPositionSave!).inSeconds >= 5) {
            _savePlayerState();
            _lastPositionSave = now;
          }
        }

        // Throttle position updates to reduce CPU usage
        final now = DateTime.now();
        if (_lastPositionUpdate == null ||
            now.difference(_lastPositionUpdate!) >= Duration(milliseconds: PerformanceConfig.positionUpdateInterval)) {
          _lastPositionUpdate = now;
          _notifyListenersDebounced();
        }
      }
    });

    _durationSubscription = _audioPlayer.durationStream.listen((duration) {
      if (duration != null) {
        _duration = duration;
        _notifyListenersDebounced();
      }
    });

    _playerStateSubscription = _audioPlayer.playerStateStream.listen((state) {
      // Track playing state separately from buffering
      final wasPlaying = _isPlaying;
      final wasBuffering = _isBuffering;
      _isPlaying = state.playing;

      // Report playing state to ActivityCoordinator for battery optimization
      if (wasPlaying != _isPlaying) {
        _activityCoordinator?.setPlayingState(_isPlaying);
      }

      // Consider both buffering and loading states as "buffering" for UI purposes
      // Also check if we're "playing" but not ready (which means buffering)
      _isBuffering = state.processingState == ProcessingState.buffering ||
                     state.processingState == ProcessingState.loading ||
                     (state.playing && state.processingState != ProcessingState.ready);

      // Detect playback failure: was loading/buffering but went to idle without completing
      if (wasBuffering && state.processingState == ProcessingState.idle && !state.playing) {
        _lastError = 'Failed to play track. Check your connection or try again.';
        if (kDebugMode) print('[PlayerProvider] Playback failed - stream error detected');
      }

      // Clear error when playback starts successfully
      if (state.processingState == ProcessingState.ready && state.playing) {
        _lastError = null;
      }

      // Debug logging to see what states we're getting
      if (kDebugMode) {
        print('[PlayerProvider] PlayerState: playing=${state.playing}, processingState=${state.processingState}, isBuffering=$_isBuffering');
      }

      if (state.processingState == ProcessingState.completed) {
        next();
      }

      _notifyListenersDebounced();
    });
  }

  /// Initialize MpvPlayer streams for Linux/Windows
  void _initializeMpvPlayer() {
    final mpv = app_main.globalMpvPlayer!;
    if (kDebugMode) print('[PlayerProvider] Initializing MpvPlayer streams');

    // Listen to mpv state changes
    _mpvStateSubscription = mpv.stateStream.listen((state) {
      final wasPlaying = _isPlaying;
      final wasBuffering = _isBuffering;

      _isPlaying = state == MpvPlayerState.playing;
      _isBuffering = state == MpvPlayerState.loading;

      // Report playing state to ActivityCoordinator
      if (wasPlaying != _isPlaying) {
        _activityCoordinator?.setPlayingState(_isPlaying);
      }

      // Detect playback failure
      if (wasBuffering && state == MpvPlayerState.error) {
        _lastError = 'Failed to play track. Check your connection or try again.';
        if (kDebugMode) print('[PlayerProvider] MpvPlayer error detected');
      }

      // Clear error when ready
      if (state == MpvPlayerState.ready || state == MpvPlayerState.playing) {
        _lastError = null;
      }

      if (kDebugMode) {
        print('[PlayerProvider] MpvPlayer state: $state, isPlaying=$_isPlaying, isBuffering=$_isBuffering');
      }

      // Handle track completion
      if (state == MpvPlayerState.completed) {
        next();
      }

      _notifyListenersDebounced();
    });

    // Listen to position updates
    _mpvPositionSubscription = mpv.positionStream.listen((position) {
      if (_isRestoring || _isBuffering) return;

      if (_hasRestoredPosition || _isPlaying) {
        _position = position;

        if (_isPlaying) {
          _checkPreloadNeeded();

          final now = DateTime.now();
          if (_lastPositionSave == null ||
              now.difference(_lastPositionSave!).inSeconds >= 5) {
            _savePlayerState();
            _lastPositionSave = now;
          }
        }

        final now = DateTime.now();
        if (_lastPositionUpdate == null ||
            now.difference(_lastPositionUpdate!) >= Duration(milliseconds: PerformanceConfig.positionUpdateInterval)) {
          _lastPositionUpdate = now;
          _notifyListenersDebounced();
        }
      }
    });

    // Listen to duration updates
    _mpvDurationSubscription = mpv.durationStream.listen((duration) {
      if (duration != null) {
        _duration = duration;
        _notifyListenersDebounced();
      }
    });

    // Listen to errors
    mpv.errorStream.listen((error) {
      if (kDebugMode) print('[PlayerProvider] MpvPlayer error: $error');
      _handlePlaybackError(error);
    });
  }

  void _notifyListenersDebounced() {
    // Cancel any existing timer
    _notificationTimer?.cancel();

    // Set a new timer to debounce notifications
    _notificationTimer = Timer(const Duration(milliseconds: 16), () {
      _pendingNotification = false;
      notifyListeners();
      _notificationTimer = null;
    });

    _pendingNotification = true;
  }

  /// Show a native desktop notification for track changes (Linux only, used with MpvPlayer)
  Future<void> _showTrackNotification(Song song) async {
    if (!Platform.isLinux) return;

    try {
      // Get cached cover art path if available
      String? albumArtPath;
      if (song.coverArt != null) {
        albumArtPath = await DatabaseHelper.getAnyCachedCoverArt(song.coverArt!);
      }

      await NotificationService().showTrackNotification(
        title: song.title,
        artist: song.artist ?? 'Unknown Artist',
        album: song.album ?? 'Unknown Album',
        albumArtPath: albumArtPath,
      );
    } catch (e) {
      // Silently ignore notification failures
    }
  }

  /// Set the ActivityCoordinator for reporting playing state
  void setActivityCoordinator(ActivityCoordinator coordinator) {
    _activityCoordinator = coordinator;
  }

  void setApi(NavidromeApi api, {NetworkProvider? networkProvider}) {
    // Check if the API is already set to the same instance
    if (_api == api) {
      if (kDebugMode) print('[PlayerProvider] API already set to same instance, skipping');
      return;
    }

    _api = api;
    _cacheService = CacheService(api: api);

    // Store network provider for connectivity checks
    if (networkProvider != null) {
      _networkProvider = networkProvider;

      // Subscribe to connection events for playback recovery
      _connectionSubscription?.cancel();
      _connectionSubscription = networkProvider.connectionEvents.listen(_handleConnectionEvent);
    }
    
    // Update the audio handler with the proper API if on Android or Linux
    if ((Platform.isAndroid || Platform.isLinux) && app_main.actualAudioHandler != null) {
      app_main.actualAudioHandler!.updateApi(api);
      
      // Cancel any existing subscription before creating a new one
      _mediaItemSubscription?.cancel();
      
      // Set up listener for mediaItem changes (use the proxy for listening)
      if (app_main.audioHandler != null) {
        _mediaItemSubscription = app_main.audioHandler!.mediaItem.listen((mediaItem) async {
          if (mediaItem != null && _queue.isNotEmpty) {
          // Find the song in the queue that matches this media item
          final songIndex = _queue.indexWhere((song) => song.id == mediaItem.id);
          
          if (songIndex != -1) {
            // Check if this is actually a different song
            final isNewSong = _currentSong?.id != mediaItem.id;
            
            if (isNewSong) {
              // Update current song and index
              _currentIndex = songIndex;
              _currentSong = _queue[songIndex];
              
              // Reset position and update visuals for a new song
              _position = Duration.zero; // Reset position for new song
              _hasRestoredPosition = true; // Not restoring
              _isRestoring = false;
              
              // Cache cover art for the new song
              await _cacheCoverArt(_currentSong!);
              
              // Extract colors from album art
              await _extractColorsFromCurrentSong();
              
              // Pre-load next cover art
              _preloadNextCoverArt();
              
              notifyListeners();
              _savePlayerState();
            }
            }
          }
        });
      }
    }
    // Now that we have the API, try to restore the audio if we have persisted state
    _restoreAudioIfNeeded();
  }
  
  Future<void> _restoreAudioIfNeeded() async {
    // Check if already restoring to prevent concurrent operations
    if (_isRestoring) {
      if (kDebugMode) print('[PlayerProvider] Already restoring, skipping concurrent restore');
      return;
    }
    
    if (_currentSong != null && _api != null && !_hasRestoredPosition) {
      _isRestoring = true;
      if (kDebugMode) print('[PlayerProvider] API set, restoring audio for ${_currentSong!.title}');
      
      // Store the position we want to restore
      final targetPosition = _position;
      
      try {
        // Cache cover art for the current song
        await _cacheCoverArt(_currentSong!);
        
        // Extract colors from album art
        await _extractColorsFromCurrentSong();
        
        // Use MpvPlayer on Linux/Windows if available
        if (_useMpv) {
          // Check for cached audio file first
          String? audioSource;
          final cachedPath = await _getCachedAudioPath(_currentSong!.id);
          if (cachedPath != null) {
            final cachedFile = File(cachedPath);
            final fileExists = await cachedFile.exists();
            final fileSize = fileExists ? await cachedFile.length() : 0;
            if (fileExists && fileSize > 1000) {
              audioSource = cachedPath;
              _isPlayingOffline = true;
              _canPlayCurrentOffline = true;
            } else {
              _canPlayCurrentOffline = false;
            }
          } else {
            _canPlayCurrentOffline = false;
          }

          // Fall back to streaming if not cached
          if (audioSource == null && !_networkProvider!.isOffline) {
            audioSource = _api!.getStreamUrl(_currentSong!.id, transcode: false, suffix: _currentSong!.suffix);
            _isPlayingOffline = false;
          } else if (audioSource == null && _networkProvider!.isOffline) {
            _isPlayingOffline = false;
            _canPlayCurrentOffline = false;
            if (kDebugMode) print('[PlayerProvider] ✗ Offline and no cached file for ${_currentSong!.title} - CANNOT PLAY');
            return;
          }

          if (audioSource != null) {
            if (kDebugMode) print('[PlayerProvider] MpvPlayer restoring: $audioSource');
            // Load paused (autoPlay: false)
            await app_main.globalMpvPlayer!.load(audioSource, autoPlay: false);

            // Seek to saved position
            if (targetPosition.inMilliseconds > 0) {
              if (kDebugMode) print('[PlayerProvider] Seeking to saved position: $targetPosition');
              await app_main.globalMpvPlayer!.seek(targetPosition);
              _position = targetPosition;
            }
          }
          _hasRestoredPosition = true;
        }
        // On Linux/Windows without MpvPlayer, we can't play - just mark as restored
        else if (Platform.isLinux || Platform.isWindows) {
          if (kDebugMode) print('[PlayerProvider] ✗ MpvPlayer not available on ${Platform.operatingSystem} - cannot restore playback');
          _hasRestoredPosition = true;
          // Don't try to use just_audio on Linux/Windows - it won't work
        }
        // Update audio handler for Android media session with full queue
        else if (Platform.isAndroid && app_main.actualAudioHandler != null) {
          await app_main.actualAudioHandler!.updateQueueFromSongs(
            _queue,  // Use the full queue, not just current song
            startIndex: _currentIndex,
            coverArtPaths: [_currentCoverArtPath],
            networkProvider: _networkProvider,
          );
          // The audio handler will handle playback through the shared player
          // Seek to saved position after URL is loaded
          if (targetPosition.inMilliseconds > 0) {
            if (kDebugMode) print('[PlayerProvider] Seeking to saved position: $targetPosition');
            await _audioPlayer.seek(targetPosition);
            _position = targetPosition;
          }
          await _audioPlayer.pause();
          _hasRestoredPosition = true;
        } else if (!Platform.isLinux && !Platform.isWindows) {
          // Check for cached audio file first - works on all platforms when offline
          String? audioSource;
          final cachedPath = await _getCachedAudioPath(_currentSong!.id);
          if (cachedPath != null) {
            final cachedFile = File(cachedPath);
            final fileExists = await cachedFile.exists();
            final fileSize = fileExists ? await cachedFile.length() : 0;
            if (fileExists && fileSize > 1000) {
              audioSource = cachedPath;
              _isPlayingOffline = true;
              _canPlayCurrentOffline = true;
            } else {
              _canPlayCurrentOffline = false;
            }
          } else {
            _canPlayCurrentOffline = false;
            if (kDebugMode) print('[PlayerProvider] No cached file found for: ${_currentSong!.title}');
          }

          // Fall back to streaming if not cached or if online
          if (audioSource == null && !_networkProvider!.isOffline) {
            final shouldTranscode = _networkProvider != null &&
                                   !_networkProvider!.isOnWifi &&
                                   !(Platform.isLinux || Platform.isWindows || Platform.isMacOS);
            audioSource = _api!.getStreamUrl(_currentSong!.id, transcode: shouldTranscode, suffix: _currentSong!.suffix);
            _isPlayingOffline = false;
          } else if (audioSource == null && _networkProvider!.isOffline) {
            // Offline and no cached file - can't play
            _isPlayingOffline = false;
            _canPlayCurrentOffline = false;
            if (kDebugMode) print('[PlayerProvider] ✗ Offline and no cached file for ${_currentSong!.title} - CANNOT PLAY');
            return;
          }

          // Set the audio source (either local file or stream URL)
          if (audioSource != null) {
            if (audioSource.startsWith('/')) {
              // Local file path
              if (kDebugMode) print('[PlayerProvider] → Setting local file path: $audioSource');
              await _audioPlayer.setFilePath(audioSource);
            } else {
              // Stream URL
              if (kDebugMode) print('[PlayerProvider] → Setting stream URL: $audioSource');
              await _audioPlayer.setUrl(audioSource);
            }
          }

          // Seek to saved position after URL is loaded
          if (targetPosition.inMilliseconds > 0) {
            if (kDebugMode) print('[PlayerProvider] Seeking to saved position: $targetPosition');
            await _audioPlayer.seek(targetPosition);
            _position = targetPosition; // Ensure position is set correctly
          }

          // Make sure it's paused
          await _audioPlayer.pause();
          _hasRestoredPosition = true;
        }
      } finally {
        _isRestoring = false;
      }
      
      notifyListeners();
    }
  }

  Future<void> _cacheCoverArt(Song song) async {
    if (_cacheService != null && song.coverArt != null) {
      try {
        _currentCoverArtPath = await _cacheService!.getCachedCoverArt(
          song.coverArt,
          size: 600, // Higher res for notification
        );
      } catch (e) {
        print('Error caching cover art: $e');
        _currentCoverArtPath = null;
      }
    } else {
      _currentCoverArtPath = null;
    }
  }

  Future<void> _preloadNextCoverArt() async {
    if (_currentIndex >= _queue.length - 1) return;

    final nextCoverArt = _queue[_currentIndex + 1].coverArt;
    if (nextCoverArt == null) return;

    // Check if already cached locally
    final localPath = await DatabaseHelper.getCoverArtLocalPath(nextCoverArt);
    if (localPath != null) {
      // Already cached locally, no action needed
      return;
    }

    // Not cached locally - only fetch from network if online
    if (_networkProvider?.isOffline == true) return;

    if (_cacheService != null) {
      try {
        await _cacheService!.getCachedCoverArt(nextCoverArt, size: 600);
      } catch (e) {
        print('Error pre-caching next cover art: $e');
      }
    }
  }


  Future<void> playQueue(List<Song> songs, {int startIndex = 0}) async {
    if (_api == null || songs.isEmpty) return;
    
    _queue = songs;
    _currentIndex = startIndex;
    _currentSong = songs[startIndex];
    _hasRestoredPosition = true; // New playback, not restoring
    _isRestoring = false; // Not restoring
    _position = Duration.zero; // Reset position for new song
    
    // Cache cover art for the current song
    await _cacheCoverArt(_currentSong!);
    
    // Extract colors from album art
    await _extractColorsFromCurrentSong();
    
    // Pre-cache cover arts for the queue (async, don't wait)
    if (_cacheService != null) {
      Future.microtask(() async {
        final List<String?> coverArtPaths = [];
        for (final song in songs) {
          if (song.coverArt != null) {
            try {
              final path = await _cacheService!.getCachedCoverArt(
                song.coverArt,
                size: 600,
              );
              coverArtPaths.add(path);
            } catch (e) {
              coverArtPaths.add(null);
            }
          } else {
            coverArtPaths.add(null);
          }
        }
        // Update handler with all cached paths if still playing same queue
        if ((Platform.isAndroid || Platform.isLinux) && app_main.actualAudioHandler != null && _queue == songs) {
          await app_main.actualAudioHandler!.updateCoverArtPaths(coverArtPaths);
        }
      });
    }
    
    // Use MpvPlayer on Linux/Windows if available
    if (_useMpv) {
      // Get audio source for the current song
      String? audioSource;
      final cachedPath = await _getCachedAudioPath(_currentSong!.id);
      if (cachedPath != null) {
        final cachedFile = File(cachedPath);
        final fileExists = await cachedFile.exists();
        final fileSize = fileExists ? await cachedFile.length() : 0;
        if (fileExists && fileSize > 1000) {
          audioSource = cachedPath;
          _isPlayingOffline = true;
          _canPlayCurrentOffline = true;
        } else {
          _canPlayCurrentOffline = false;
        }
      } else {
        _canPlayCurrentOffline = false;
      }

      // Fall back to streaming if not cached
      if (audioSource == null && !_networkProvider!.isOffline) {
        // Desktop never transcodes
        audioSource = _api!.getStreamUrl(_currentSong!.id, transcode: false, suffix: _currentSong!.suffix);
        _isPlayingOffline = false;
      } else if (audioSource == null && _networkProvider!.isOffline) {
        _isPlayingOffline = false;
        _canPlayCurrentOffline = false;
        if (kDebugMode) print('[PlayerProvider] Offline and no cached file for ${_currentSong!.title}');
        return;
      }

      if (audioSource != null) {
        if (kDebugMode) print('[PlayerProvider] MpvPlayer loading: $audioSource');
        await app_main.globalMpvPlayer!.load(audioSource);

        // Show notification for track change on Linux
        if (Platform.isLinux) {
          _showTrackNotification(_currentSong!);
        }
      }
    }
    // On Linux/Windows without MpvPlayer, we can't play
    else if (Platform.isLinux || Platform.isWindows) {
      if (kDebugMode) print('[PlayerProvider] ✗ MpvPlayer not available on ${Platform.operatingSystem} - cannot play');
      return;
    }
    // Update audio handler for Android media session with current cached art
    else if (Platform.isAndroid && app_main.actualAudioHandler != null) {
      await app_main.actualAudioHandler!.updateQueueFromSongs(
        songs,
        startIndex: startIndex,
        coverArtPaths: [_currentCoverArtPath], // Start with just current song's art
        networkProvider: _networkProvider,
      );
      // The audio handler will set up the playlist in the shared player
      await _audioPlayer.play();
    } else if (!Platform.isLinux && !Platform.isWindows) {
      if (_useGaplessPlayback && songs.length > 1) {
        // Use gapless playback for queues with multiple songs
        await _setupGaplessPlayback(startIndex);
      } else {
        // Check for cached audio file first - works on all platforms
        String? audioSource;
        final cachedPath = await _getCachedAudioPath(_currentSong!.id);
        if (cachedPath != null) {
          final cachedFile = File(cachedPath);
          final fileExists = await cachedFile.exists();
          final fileSize = fileExists ? await cachedFile.length() : 0;
          if (fileExists && fileSize > 1000) {
            audioSource = cachedPath;
            _isPlayingOffline = true;
            _canPlayCurrentOffline = true;
          } else {
            _canPlayCurrentOffline = false;
          }
        } else {
          _canPlayCurrentOffline = false;
        }

        // Fall back to streaming if not cached or if online
        if (audioSource == null && !_networkProvider!.isOffline) {
          final shouldTranscode = _networkProvider != null &&
                                 !_networkProvider!.isOnWifi &&
                                 !(Platform.isLinux || Platform.isWindows || Platform.isMacOS);
          audioSource = _api!.getStreamUrl(_currentSong!.id, transcode: shouldTranscode, suffix: _currentSong!.suffix);
          _isPlayingOffline = false;
        } else if (audioSource == null && _networkProvider!.isOffline) {
          // Offline and no cached file - can't play
          _isPlayingOffline = false;
          _canPlayCurrentOffline = false;
          if (kDebugMode) print('[PlayerProvider] Offline and no cached file for ${_currentSong!.title}');
          return;
        }

        // Stop any current playback first
        await _audioPlayer.stop();

        // Set the audio source (either local file or stream URL)
        if (audioSource != null) {
          if (audioSource.startsWith('/')) {
            // Local file path
            await _audioPlayer.setFilePath(audioSource);
          } else {
            // Stream URL
            await _audioPlayer.setUrl(audioSource);
          }
        }
      }
      await _audioPlayer.play();
    }
    
    // Pre-load next cover art
    _preloadNextCoverArt();
    
    notifyListeners();
    _savePlayerState();
  }

  Future<void> addToQueue(Song song) async {
    if (_queue.isEmpty) {
      // If no queue, start playing this song as a new queue
      await playQueue([song], startIndex: 0);
    } else {
      // Add to existing queue
      _queue.add(song);
      notifyListeners();
    }
  }

  Future<void> play() async {
    // Check if we can play offline
    if (_networkProvider?.isOffline == true && !_canPlayCurrentOffline) {
      if (kDebugMode) print('[PlayerProvider] Cannot play offline - no cached file');
      return;
    }

    if (_useMpv) {
      await app_main.globalMpvPlayer!.play();
    } else {
      await _audioPlayer.play();
    }
  }

  Future<void> pause() async {
    if (_useMpv) {
      await app_main.globalMpvPlayer!.pause();
    } else {
      await _audioPlayer.pause();
    }
    _savePlayerState();
  }

  Future<void> togglePlayPause() async {
    if (_isPlaying) {
      await pause();
    } else {
      // Check if we can play offline
      if (_networkProvider?.isOffline == true && !_canPlayCurrentOffline) {
        if (kDebugMode) print('[PlayerProvider] Cannot play offline - no cached file');
        return;
      }

      await play();
    }
  }

  Future<void> next() async {
    if (_queue.isEmpty || _api == null) return;

    // Use MpvPlayer on Linux/Windows if available
    if (_useMpv) {
      if (_currentIndex < _queue.length - 1) {
        _currentIndex++;
        _currentSong = _queue[_currentIndex];
        _position = Duration.zero;
        _hasRestoredPosition = true;
        _isRestoring = false;

        await _cacheCoverArt(_currentSong!);
        await _extractColorsFromCurrentSong();

        // Get audio source
        String? audioSource;
        final cachedPath = await _getCachedAudioPath(_currentSong!.id);
        if (cachedPath != null) {
          final cachedFile = File(cachedPath);
          if (await cachedFile.exists() && await cachedFile.length() > 1000) {
            audioSource = cachedPath;
            _isPlayingOffline = true;
            _canPlayCurrentOffline = true;
          } else {
            _canPlayCurrentOffline = false;
          }
        } else {
          _canPlayCurrentOffline = false;
        }

        if (audioSource == null && !_networkProvider!.isOffline) {
          audioSource = _api!.getStreamUrl(_currentSong!.id, transcode: false, suffix: _currentSong!.suffix);
          _isPlayingOffline = false;
        } else if (audioSource == null && _networkProvider!.isOffline) {
          _isPlayingOffline = false;
          _canPlayCurrentOffline = false;
          if (kDebugMode) print('[PlayerProvider] Offline and no cached file for ${_currentSong!.title}');
          return;
        }

        if (audioSource != null) {
          await app_main.globalMpvPlayer!.load(audioSource);
          if (Platform.isLinux) _showTrackNotification(_currentSong!);
        }

        notifyListeners();
        _savePlayerState();
      }
      return;
    }

    // Use the audio handler for navigation on Android
    if (Platform.isAndroid && app_main.audioHandler != null) {
      await app_main.audioHandler!.skipToNext();
      // The handler will update everything via the mediaItem listener
      return;
    }

    if (_playlist != null && _useGaplessPlayback) {
      // Gapless mode - just seek to next in playlist
      if (_audioPlayer.hasNext) {
        await _audioPlayer.seekToNext();
        // Current index update is handled by the stream listener
      }
    } else if (_currentIndex < _queue.length - 1) {
      // Traditional mode
      _currentIndex++;
      _currentSong = _queue[_currentIndex];
      _position = Duration.zero; // Reset position for new song
      _hasRestoredPosition = true; // Not restoring
      _isRestoring = false;
      
      // Cache cover art for the new song
      await _cacheCoverArt(_currentSong!);
      
      // Extract colors from album art
      await _extractColorsFromCurrentSong();
      
      // Try to use preloaded player for minimal gap
      final cachedPlayer = _cacheManager.getCachedPlayer(_currentSong!.id);
      if (cachedPlayer != null) {
        _cacheManager.removeCachedPlayer(_currentSong!.id);
        _preloadedSongIds.remove(_currentSong!.id);
      }
      
      // Check for cached audio file first - works on all platforms
      String? audioSource;
      final cachedPath = await _getCachedAudioPath(_currentSong!.id);
      if (cachedPath != null) {
        // Validate the cached file exists and is readable
        final cachedFile = File(cachedPath);
        if (await cachedFile.exists() && await cachedFile.length() > 1000) {
          audioSource = cachedPath;
          _isPlayingOffline = true;
          _canPlayCurrentOffline = true;
        } else {
          _canPlayCurrentOffline = false;
        }
      } else {
        _canPlayCurrentOffline = false;
      }

      // Fall back to streaming if not cached or if online
      if (audioSource == null && !_networkProvider!.isOffline) {
        final shouldTranscode = _networkProvider != null &&
                               !_networkProvider!.isOnWifi &&
                               !(Platform.isLinux || Platform.isWindows || Platform.isMacOS);
        audioSource = _api!.getStreamUrl(_currentSong!.id, transcode: shouldTranscode, suffix: _currentSong!.suffix);
        _isPlayingOffline = false;
      } else if (audioSource == null && _networkProvider!.isOffline) {
        // Offline and no cached file - can't play
        _isPlayingOffline = false;
        _canPlayCurrentOffline = false;
        if (kDebugMode) print('[PlayerProvider] Offline and no cached file for ${_currentSong!.title}');
        return;
      }

      // Stop current playback before loading new track
      await _audioPlayer.stop();
      
      // Try to load the audio source, fall back to streaming if it fails
      try {
        // Set the audio source (either local file or stream URL)
        if (audioSource != null) {
          if (audioSource.startsWith('/')) {
            // Local file path
            await _audioPlayer.setFilePath(audioSource);
          } else {
            // Stream URL
            await _audioPlayer.setUrl(audioSource);
          }
        }
      } catch (e) {
        // If it was a cached file that failed, try streaming instead
        if (audioSource?.startsWith('/') == true) {
          final shouldTranscode = _networkProvider != null &&
                                 !_networkProvider!.isOnWifi &&
                                 !(Platform.isLinux || Platform.isWindows || Platform.isMacOS);
          audioSource = _api!.getStreamUrl(_currentSong!.id, transcode: shouldTranscode, suffix: _currentSong!.suffix);
          await _audioPlayer.setUrl(audioSource);
        } else {
          rethrow; // If streaming also failed, propagate the error
        }
      }
      
      await _audioPlayer.play();
      
      notifyListeners();
      _savePlayerState();
      _checkPreloadNeeded(); // Check if we need to preload more
    }
  }

  Future<void> previous() async {
    if (_queue.isEmpty || _api == null) return;

    // Use MpvPlayer on Linux/Windows if available
    if (_useMpv) {
      // If more than 3 seconds in, restart current track
      if (_position.inSeconds >= 3) {
        await app_main.globalMpvPlayer!.seek(Duration.zero);
        _position = Duration.zero;
        notifyListeners();
        return;
      }

      if (_currentIndex > 0) {
        _currentIndex--;
        _currentSong = _queue[_currentIndex];
        _position = Duration.zero;
        _hasRestoredPosition = true;
        _isRestoring = false;

        await _cacheCoverArt(_currentSong!);
        await _extractColorsFromCurrentSong();

        // Get audio source
        String? audioSource;
        final cachedPath = await _getCachedAudioPath(_currentSong!.id);
        if (cachedPath != null) {
          final cachedFile = File(cachedPath);
          if (await cachedFile.exists() && await cachedFile.length() > 1000) {
            audioSource = cachedPath;
            _isPlayingOffline = true;
            _canPlayCurrentOffline = true;
          } else {
            _canPlayCurrentOffline = false;
          }
        } else {
          _canPlayCurrentOffline = false;
        }

        if (audioSource == null && !_networkProvider!.isOffline) {
          audioSource = _api!.getStreamUrl(_currentSong!.id, transcode: false, suffix: _currentSong!.suffix);
          _isPlayingOffline = false;
        } else if (audioSource == null && _networkProvider!.isOffline) {
          _isPlayingOffline = false;
          _canPlayCurrentOffline = false;
          if (kDebugMode) print('[PlayerProvider] Offline and no cached file for ${_currentSong!.title}');
          return;
        }

        if (audioSource != null) {
          await app_main.globalMpvPlayer!.load(audioSource);
          if (Platform.isLinux) _showTrackNotification(_currentSong!);
        }

        notifyListeners();
        _savePlayerState();
      } else {
        // At first track, restart
        await app_main.globalMpvPlayer!.seek(Duration.zero);
        _position = Duration.zero;
        notifyListeners();
      }
      return;
    }

    // Use the audio handler for navigation on Android
    if (Platform.isAndroid && app_main.audioHandler != null) {
      await app_main.audioHandler!.skipToPrevious();
      // The handler will update everything via the mediaItem listener
      return;
    }

    if (_playlist != null && _useGaplessPlayback) {
      // Gapless mode - seek to previous in playlist
      if (_audioPlayer.hasPrevious) {
        await _audioPlayer.seekToPrevious();
        // Current index update is handled by the stream listener
      }
    } else if (_currentIndex > 0) {
      // Traditional mode
      _currentIndex--;
      _currentSong = _queue[_currentIndex];
      _position = Duration.zero; // Reset position for new song
      _hasRestoredPosition = true; // Not restoring
      _isRestoring = false;
      
      // Cache cover art for the new song
      await _cacheCoverArt(_currentSong!);
      
      // Extract colors from album art
      await _extractColorsFromCurrentSong();
      
      // Check for cached audio file first - works on all platforms
      String? audioSource;
      final cachedPath = await _getCachedAudioPath(_currentSong!.id);
      if (cachedPath != null) {
        final cachedFile = File(cachedPath);
        if (await cachedFile.exists() && await cachedFile.length() > 1000) {
          audioSource = cachedPath;
          _isPlayingOffline = true;
          _canPlayCurrentOffline = true;
        } else {
          _canPlayCurrentOffline = false;
        }
      } else {
        _canPlayCurrentOffline = false;
      }

      // Fall back to streaming if not cached or if online
      if (audioSource == null && !_networkProvider!.isOffline) {
        final shouldTranscode = _networkProvider != null &&
                               !_networkProvider!.isOnWifi &&
                               !(Platform.isLinux || Platform.isWindows || Platform.isMacOS);
        audioSource = _api!.getStreamUrl(_currentSong!.id, transcode: shouldTranscode, suffix: _currentSong!.suffix);
        _isPlayingOffline = false;
      } else if (audioSource == null && _networkProvider!.isOffline) {
        // Offline and no cached file - can't play
        _isPlayingOffline = false;
        _canPlayCurrentOffline = false;
        if (kDebugMode) print('[PlayerProvider] Offline and no cached file for ${_currentSong!.title}');
        return;
      }

      // Set the audio source (either local file or stream URL)
      if (audioSource != null) {
        if (audioSource.startsWith('/')) {
          // Local file path
          await _audioPlayer.setFilePath(audioSource);
        } else {
          // Stream URL
          await _audioPlayer.setUrl(audioSource);
        }
      }
      await _audioPlayer.play();
      
      notifyListeners();
      _savePlayerState();
    }
  }

  Future<void> seek(Duration position) async {
    if (_useMpv) {
      await app_main.globalMpvPlayer!.seek(position);
    } else {
      await _audioPlayer.seek(position);
    }
    _position = position;
    notifyListeners();
    _savePlayerState();
  }

  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    if (_useMpv) {
      await app_main.globalMpvPlayer!.setVolume(_volume);
    } else {
      await _audioPlayer.setVolume(_volume);
    }
    notifyListeners();
    _savePlayerState();
  }

  /// Clear any playback error message
  void clearError() {
    _lastError = null;
    notifyListeners();
  }

  Future<void> _loadPersistedState() async {
    final prefs = await SharedPreferences.getInstance();
    
    final currentSongJson = prefs.getString('player_current_song');
    final queueJson = prefs.getString('player_queue');
    final currentIndex = prefs.getInt('player_current_index') ?? 0;
    final positionMillis = prefs.getInt('player_position') ?? 0;
    final volume = prefs.getDouble('player_volume') ?? 1.0;
    
    if (kDebugMode) print('[PlayerProvider] Loading persisted state - position: ${positionMillis}ms');
    
    if (currentSongJson != null && queueJson != null) {
      try {
        final songMap = json.decode(currentSongJson);
        _currentSong = Song(
          id: songMap['id'],
          title: songMap['title'],
          album: songMap['album'],
          albumId: songMap['albumId'],
          artist: songMap['artist'],
          artistId: songMap['artistId'],
          duration: songMap['duration'],
          track: songMap['track'],
          discNumber: songMap['discNumber'],
          discSubtitle: songMap['discSubtitle'],
          coverArt: songMap['coverArt'],
        );
        
        final queueList = json.decode(queueJson) as List;
        _queue = queueList.map((item) => Song(
          id: item['id'],
          title: item['title'],
          album: item['album'],
          albumId: item['albumId'],
          artist: item['artist'],
          artistId: item['artistId'],
          duration: item['duration'],
          track: item['track'],
          discNumber: item['discNumber'],
          discSubtitle: item['discSubtitle'],
          coverArt: item['coverArt'],
        )).toList();
        
        _currentIndex = currentIndex;
        _position = Duration(milliseconds: positionMillis);
        _volume = volume;
        
        await _audioPlayer.setVolume(_volume);
        
        // Just restore the state, don't load audio yet (API might not be set)
        if (kDebugMode) print('[PlayerProvider] State restored, waiting for API to load audio');
        
        notifyListeners();
        
        // Try to restore audio if API is already available
        if (_api != null) {
          await _restoreAudioIfNeeded();
        }
      } catch (e) {
        print('Error loading persisted player state: $e');
      }
    }
  }
  
  Future<void> _savePlayerState() async {
    if (_currentSong == null || _queue.isEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();

      final currentSongMap = {
        'id': _currentSong!.id,
        'title': _currentSong!.title,
        'album': _currentSong!.album,
        'albumId': _currentSong!.albumId,
        'artist': _currentSong!.artist,
        'artistId': _currentSong!.artistId,
        'duration': _currentSong!.duration,
        'track': _currentSong!.track,
        'discNumber': _currentSong!.discNumber,
        'discSubtitle': _currentSong!.discSubtitle,
        'coverArt': _currentSong!.coverArt,
      };

      final queueList = _queue.map((song) => {
        'id': song.id,
        'title': song.title,
        'album': song.album,
        'albumId': song.albumId,
        'artist': song.artist,
        'artistId': song.artistId,
        'duration': song.duration,
        'track': song.track,
        'discNumber': song.discNumber,
        'discSubtitle': song.discSubtitle,
        'coverArt': song.coverArt,
      }).toList();

      await prefs.setString('player_current_song', json.encode(currentSongMap));
      await prefs.setString('player_queue', json.encode(queueList));
      await prefs.setInt('player_current_index', _currentIndex);
      await prefs.setInt('player_position', _position.inMilliseconds);
      await prefs.setDouble('player_volume', _volume);

      // Save play history for intelligent pre-caching
      await _updatePlayHistory();
    } catch (e) {
      print('Error saving player state: $e');
    }
  }

  /// Update play history for intelligent pre-caching
  Future<void> _updatePlayHistory() async {
    if (_currentSong == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getStringList('play_history') ?? [];

      // Add current song to history
      historyJson.add(json.encode({
        'id': _currentSong!.id,
        'title': _currentSong!.title,
        'albumId': _currentSong!.albumId,
        'artistId': _currentSong!.artistId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      }));

      // Keep only last 50 played songs
      if (historyJson.length > 50) {
        historyJson.removeRange(0, historyJson.length - 50);
      }

      await prefs.setStringList('play_history', historyJson);
    } catch (e) {
      print('Error updating play history: $e');
    }
  }
  
  Future<void> clearPersistedState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('player_current_song');
    await prefs.remove('player_queue');
    await prefs.remove('player_current_index');
    await prefs.remove('player_position');
    await prefs.remove('player_volume');
    await prefs.remove('play_history');
  }

  Future<void> _setupGaplessPlayback(int startIndex) async {
    if (_api == null) return;

    // Create audio sources for the queue
    final audioSources = <AudioSource>[];

    // Add up to 3 tracks initially (current + next 2)
    final endIndex = (startIndex + 3).clamp(0, _queue.length);

    for (int i = startIndex; i < endIndex; i++) {
      final song = _queue[i];

      // Check for cached audio file first
      String? audioSource;
      final cachedPath = await _getCachedAudioPath(song.id);
      if (cachedPath != null) {
        final cachedFile = File(cachedPath);
        if (await cachedFile.exists() && await cachedFile.length() > 1000) {
          audioSource = cachedPath;
          if (i == startIndex) {
            // Only set offline flag for the current song
            _isPlayingOffline = true;
            _canPlayCurrentOffline = true;
          }
        }
      }

      // Fall back to streaming if not cached
      if (audioSource == null) {
        final shouldTranscode = _networkProvider != null &&
                               !_networkProvider!.isOnWifi &&
                               !(Platform.isLinux || Platform.isWindows || Platform.isMacOS);
        audioSource = _api!.getStreamUrl(song.id, transcode: shouldTranscode, suffix: song.suffix);
        if (i == startIndex) {
          _isPlayingOffline = false;
          // Check if we can play this song offline
          _canPlayCurrentOffline = await _checkCanPlayOffline(song);
        }
      }

      // Create the appropriate audio source
      if (audioSource.startsWith('/')) {
        // Local file path
        audioSources.add(AudioSource.uri(Uri.file(audioSource)));
      } else {
        // Stream URL
        audioSources.add(AudioSource.uri(Uri.parse(audioSource)));
      }
    }
    
    // Create concatenating audio source for gapless playback
    _playlist = ConcatenatingAudioSource(children: audioSources);
    
    // Set the playlist
    await _audioPlayer.setAudioSource(_playlist!, initialIndex: 0);
    
    // Schedule adding more tracks as we play
    _scheduleTrackAddition(endIndex);
  }

  Future<bool> _checkCanPlayOffline(Song song) async {
    // Check songs table for cached path and status
    final cachedPath = await _getCachedAudioPath(song.id);
    if (cachedPath != null) {
      final cachedFile = File(cachedPath);
      if (await cachedFile.exists() && await cachedFile.length() > 1000) {
        return true;
      } else {
      }
    }

    if (kDebugMode) print('[PlayerProvider] ✗ No cached file found for: ${song.title}');
    return false;
  }
  
  Future<void> _scheduleTrackAddition(int nextIndex) async {
    if (_api == null || _playlist == null) return;
    
    // Add more tracks to the playlist as we approach the end
    _audioPlayer.currentIndexStream.listen((index) {
      if (index != null && _playlist != null) {
        // Update current song based on playlist index
        final actualIndex = _currentIndex + index;
        if (actualIndex < _queue.length) {
          _currentSong = _queue[actualIndex];
          _currentIndex = actualIndex;
          
          // Extract colors from album art for the new track
          _extractColorsFromCurrentSong();
          
          notifyListeners();
          _savePlayerState();
        }
        
        // Add more tracks when we're 2 tracks from the end
        final tracksInPlaylist = _playlist!.length;
        if (index >= tracksInPlaylist - 2 && nextIndex < _queue.length) {
          // Add the next track asynchronously
          _addNextTrackToPlaylist(nextIndex);
        }
      }
    });
  }

  Future<void> _addNextTrackToPlaylist(int trackIndex) async {
    if (_api == null || _playlist == null || trackIndex >= _queue.length) return;

    final song = _queue[trackIndex];

    // Check for cached audio file first
    String? audioSource;
    final cachedPath = await _getCachedAudioPath(song.id);
    if (cachedPath != null) {
      final cachedFile = File(cachedPath);
      if (await cachedFile.exists() && await cachedFile.length() > 1000) {
        audioSource = cachedPath;
      }
    }

    // Fall back to streaming if not cached
    if (audioSource == null) {
      final shouldTranscode = _networkProvider != null &&
                             !_networkProvider!.isOnWifi &&
                             !(Platform.isLinux || Platform.isWindows || Platform.isMacOS);
      audioSource = _api!.getStreamUrl(song.id, transcode: shouldTranscode, suffix: song.suffix);
    }

    // Create the appropriate audio source
    if (audioSource.startsWith('/')) {
      // Local file path
      _playlist!.add(AudioSource.uri(Uri.file(audioSource)));
    } else {
      // Stream URL
      _playlist!.add(AudioSource.uri(Uri.parse(audioSource)));
    }

    // Schedule the next track
    _scheduleTrackAddition(trackIndex + 1);
  }
  
  void _checkPreloadNeeded() {
    // Throttle preload checks to once per second
    final now = DateTime.now();
    if (_lastPreloadCheck != null && 
        now.difference(_lastPreloadCheck!).inMilliseconds < 1000) {
      return;
    }
    _lastPreloadCheck = now;
    
    // With gapless playback, tracks are added to the playlist dynamically
    // This method is now primarily for fallback/single track mode
    if (!_useGaplessPlayback && _api != null && _queue.isNotEmpty) {
      // Calculate remaining time in current track
      final remainingTime = _duration - _position;
      
      // We want to ensure the next 30 seconds are preloaded
      const preloadBuffer = Duration(seconds: 30);
      
      if (remainingTime <= preloadBuffer) {
        // Start preloading next tracks to fill the 30-second buffer
        _preloadUpcomingTracks(preloadBuffer - remainingTime);
      }
    }
  }
  
  Future<void> _preloadUpcomingTracks(Duration bufferNeeded) async {
    if (_api == null) return;

    final isOffline = _networkProvider?.isOffline == true;
    var totalPreloaded = Duration.zero;
    var trackIndex = _currentIndex + 1;

    while (trackIndex < _queue.length && totalPreloaded < bufferNeeded) {
      final song = _queue[trackIndex];

      // Check if already cached in the cache manager (not just our local tracking)
      final cachedPlayer = _cacheManager.getCachedPlayer(song.id);
      if (cachedPlayer == null) {
        // Check if we have this song cached locally on disk
        final cachedPath = await _getCachedAudioPath(song.id);

        if (cachedPath != null) {
          // Cached locally - preload from file
          final player = await _cacheManager.preloadTrack(song.id, cachedPath);
          if (player != null) {
            _preloadedSongIds.add(song.id);
          }
        } else if (!isOffline) {
          // Not cached and online - preload from network
          final url = _api!.getStreamUrl(song.id, suffix: song.suffix);
          final player = await _cacheManager.preloadTrack(song.id, url);
          if (player != null) {
            _preloadedSongIds.add(song.id);
          }
        }
        // If offline and not cached locally, skip this track
      }
      
      // Add the duration of this track to our total
      if (song.duration != null) {
        totalPreloaded += Duration(seconds: song.duration!);
      } else {
        // Assume 3 minutes if duration unknown
        totalPreloaded += const Duration(minutes: 3);
      }
      
      trackIndex++;
    }
  }
  
  Future<void> _switchToPreloadedPlayer(AudioPlayer preloadedPlayer) async {
    // This is a simplified approach - just_audio doesn't support true gapless
    // but we can minimize the gap by having the next track ready
    try {
      // Get the current state from preloaded player
      final duration = preloadedPlayer.duration;
      
      // Stop current player
      await _audioPlayer.stop();
      
      // Use the preloaded URL directly
      // Note: In a more sophisticated implementation, we'd swap the AudioPlayer instances
      // but just_audio has limitations here
      await _audioPlayer.setUrl(_api!.getStreamUrl(_currentSong!.id, suffix: _currentSong!.suffix));
      
      if (duration != null) {
        _duration = duration;
      }
    } catch (e) {
      if (kDebugMode) print('[PlayerProvider] Error switching to preloaded player: $e');
    }
  }

  /// Extract colors from the current song's album art
  Future<void> _extractColorsFromCurrentSong() async {
    if (_currentSong?.coverArt == null) {
      _currentColors = ExtractedColors.defaultColors();
      notifyListeners();
      return;
    }

    try {
      final cacheKey = 'colors_${_currentSong!.coverArt}_400';

      // First try to use locally cached cover art
      final localPath = await DatabaseHelper.getCoverArtLocalPath(_currentSong!.coverArt!);
      if (localPath != null) {
        final file = File(localPath);
        if (await file.exists()) {
          _currentColors = await _colorExtractionService.extractColorsFromLocalFile(
            localPath,
            cacheKey: cacheKey,
          );
          notifyListeners();
          return;
        }
      }

      // Fall back to network URL only if online and API available
      final isOffline = _networkProvider?.isOffline ?? false;
      if (_api != null && !isOffline) {
        final imageUrl = _api!.getCoverArtUrl(_currentSong!.coverArt, size: 400);
        _currentColors = await _colorExtractionService.extractColorsFromImage(
          imageUrl,
          cacheKey: cacheKey,
        );
        notifyListeners();
        return;
      }

      // Offline and no cached cover art - use defaults
      _currentColors = ExtractedColors.defaultColors();
      notifyListeners();
    } catch (e) {
      print('Error extracting colors from album art: $e');
      _currentColors = ExtractedColors.defaultColors();
      notifyListeners();
    }
  }

  /// Handle connection events from NetworkProvider
  void _handleConnectionEvent(ConnectionEvent event) {
    if (event == ConnectionEvent.reconnected ||
        event == ConnectionEvent.serverRestored) {
      _onNetworkReconnected();
    }
  }

  /// Called when network reconnects - attempt to recover playback if needed
  Future<void> _onNetworkReconnected() async {
    if (kDebugMode) {
      print('[PlayerProvider] Network reconnected, checking if recovery needed');
    }

    // If we're buffering and have a current song, try to recover
    if (_isBuffering && _currentSong != null && !_isRecovering) {
      if (kDebugMode) {
        print('[PlayerProvider] Was buffering, attempting recovery');
      }
      await _recoverPlayback();
    }
  }

  /// Handle playback errors with automatic retry
  Future<void> _handlePlaybackError(dynamic error) async {
    if (_isRecovering || _currentSong == null) return;

    _playbackRetryCount++;

    if (_playbackRetryCount > _maxPlaybackRetries) {
      if (kDebugMode) {
        print('[PlayerProvider] Max retries exceeded, giving up');
      }
      _playbackRetryCount = 0;
      return;
    }

    _isRecovering = true;

    try {
      // Exponential backoff
      final delay = Duration(milliseconds: 500 * _playbackRetryCount);
      if (kDebugMode) {
        print(
            '[PlayerProvider] Retry attempt $_playbackRetryCount in ${delay.inMilliseconds}ms');
      }

      await Future.delayed(delay);
      await _recoverPlayback();
    } finally {
      _isRecovering = false;
    }
  }

  /// Attempt to recover playback after network interruption
  Future<void> _recoverPlayback() async {
    if (_currentSong == null || _api == null) return;

    final savedPosition = _position;
    final wasPlaying = _isPlaying;

    if (kDebugMode) {
      print(
          '[PlayerProvider] Recovering playback for ${_currentSong!.title} at $savedPosition');
    }

    // Use MpvPlayer on Linux/Windows
    if (_useMpv) {
      // Try cached file first
      String? audioSource;
      final cachedPath = await _getCachedAudioPath(_currentSong!.id);
      if (cachedPath != null) {
        final cachedFile = File(cachedPath);
        if (await cachedFile.exists() && await cachedFile.length() > 1000) {
          audioSource = cachedPath;
          _isPlayingOffline = true;
          _canPlayCurrentOffline = true;
        }
      }

      // Try streaming if online and no cached file
      if (audioSource == null && !(_networkProvider?.isOffline ?? true)) {
        audioSource = _api!.getStreamUrl(_currentSong!.id, transcode: false, suffix: _currentSong!.suffix);
        _isPlayingOffline = false;
      }

      if (audioSource != null) {
        try {
          await app_main.globalMpvPlayer!.load(audioSource, autoPlay: wasPlaying);
          if (savedPosition.inMilliseconds > 0) {
            await app_main.globalMpvPlayer!.seek(savedPosition);
          }
          if (kDebugMode) {
            print('[PlayerProvider] Recovery: Using MpvPlayer');
          }
          notifyListeners();
          return;
        } catch (e) {
          if (kDebugMode) {
            print('[PlayerProvider] MpvPlayer recovery failed: $e');
          }
        }
      }

      if (kDebugMode) {
        print('[PlayerProvider] Recovery failed, no options left');
      }
      return;
    }

    // On Linux/Windows without MpvPlayer, we can't recover
    if (Platform.isLinux || Platform.isWindows) {
      if (kDebugMode) {
        print('[PlayerProvider] Recovery failed - MpvPlayer not available');
      }
      return;
    }

    // Try cached file first (for other platforms using just_audio)
    final cachedPath = await _getCachedAudioPath(_currentSong!.id);
    if (cachedPath != null) {
      final cachedFile = File(cachedPath);
      if (await cachedFile.exists() && await cachedFile.length() > 1000) {
        try {
          await _audioPlayer.setFilePath(cachedPath);
          await _audioPlayer.seek(savedPosition);
          if (wasPlaying) await _audioPlayer.play();
          _isPlayingOffline = true;
          _canPlayCurrentOffline = true;
          if (kDebugMode) {
            print('[PlayerProvider] Recovery: Using cached file');
          }
          notifyListeners();
          return;
        } catch (e) {
          if (kDebugMode) {
            print('[PlayerProvider] Cache recovery failed: $e');
          }
        }
      }
    }

    // Try streaming if online
    if (!(_networkProvider?.isOffline ?? true)) {
      try {
        final shouldTranscode = _networkProvider != null &&
            !_networkProvider!.isOnWifi &&
            !(Platform.isLinux || Platform.isWindows || Platform.isMacOS);
        final streamUrl =
            _api!.getStreamUrl(_currentSong!.id, transcode: shouldTranscode, suffix: _currentSong!.suffix);
        await _audioPlayer.setUrl(streamUrl);
        await _audioPlayer.seek(savedPosition);
        if (wasPlaying) await _audioPlayer.play();
        _isPlayingOffline = false;
        if (kDebugMode) {
          print('[PlayerProvider] Recovery: Using stream');
        }
        notifyListeners();
        return;
      } catch (e) {
        if (kDebugMode) {
          print('[PlayerProvider] Stream recovery failed: $e');
        }
      }
    }

    if (kDebugMode) {
      print('[PlayerProvider] Recovery failed, no options left');
    }
  }

  @override
  void dispose() {
    _preloadTimer?.cancel();
    _connectionSubscription?.cancel();
    _cancelStreamSubscriptions();
    _savePlayerState();
    _audioPlayer.dispose();
    _cacheManager.dispose();
    super.dispose();
  }
}