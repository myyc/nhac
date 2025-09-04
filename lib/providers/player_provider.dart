import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import '../models/song.dart';
import '../services/navidrome_api.dart';
import '../services/audio_cache_manager.dart';
import '../services/audio_handler.dart';
import '../services/cache_service.dart';
import '../services/audio_file_cache_service.dart';
import '../services/color_extraction_service.dart';
import '../providers/network_provider.dart';
import '../main.dart' as app_main;

class PlayerProvider extends ChangeNotifier {
  final AudioPlayer _audioPlayer;
  final AudioCacheManager _cacheManager = AudioCacheManager();
  final ColorExtractionService _colorExtractionService = ColorExtractionService();
  NavidromeApi? _api;
  CacheService? _cacheService;
  AudioFileCacheService? _audioFileCacheService;
  NetworkProvider? _networkProvider;
  Timer? _preloadTimer;
  ConcatenatingAudioSource? _playlist;
  StreamSubscription? _mediaItemSubscription;
  DateTime? _lastPreloadCheck;
  
  Song? _currentSong;
  String? _currentCoverArtPath; // Local path to cached cover art
  ExtractedColors? _currentColors; // Colors extracted from current album art
  List<Song> _queue = [];
  int _currentIndex = 0;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _volume = 1.0;
  DateTime? _lastPositionSave;
  bool _hasRestoredPosition = false;
  bool _isRestoring = false;
  Set<String> _preloadedSongIds = {};
  bool _useGaplessPlayback = false; // Disabled: not supported by media_kit backend

  Song? get currentSong => _currentSong;
  ExtractedColors? get currentColors => _currentColors;
  List<Song> get queue => _queue;
  int get currentIndex => _currentIndex;
  bool get isPlaying => _isPlaying;
  Duration get position => _position;
  Duration get duration => _duration;
  double get volume => _volume;
  String? get currentStreamUrl => _currentSong != null && _api != null 
      ? _api!.getStreamUrl(_currentSong!.id) 
      : null;
  
  // Navigation state getters for UI
  bool get canGoNext => _queue.isNotEmpty && _currentIndex < _queue.length - 1;
  bool get canGoPrevious => _queue.isNotEmpty && (_currentIndex > 0 || _position.inSeconds >= 3);
  
  PlayerProvider() : _audioPlayer = app_main.globalAudioPlayer {
    // Use the shared audio player instance from main.dart
    _initializePlayer();
    _cacheManager.initialize();
    _loadPersistedState();
  }
  
  void _initializePlayer() {
    // Add error handling for audio playback
    _audioPlayer.playbackEventStream.listen(
      (event) {
        print('[AudioPlayer] Playback event: processing=${event.processingState}, playing=${_audioPlayer.playing}');
      },
      onError: (error, stackTrace) {
        print('[AudioPlayer] Playback error: $error');
        print('[AudioPlayer] Stack trace: $stackTrace');
      },
    );
    
    _audioPlayer.positionStream.listen((position) {
      // Don't update position while restoring
      if (_isRestoring) return;
      
      // Only update position if we've restored or if actively playing
      if (_hasRestoredPosition || _isPlaying) {
        _position = position;
        
        notifyListeners();
        
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
      }
    });
    
    _audioPlayer.durationStream.listen((duration) {
      if (duration != null) {
        _duration = duration;
        notifyListeners();
      }
    });
    
    _audioPlayer.playerStateStream.listen((state) {
      _isPlaying = state.playing;
      
      if (state.processingState == ProcessingState.completed) {
        next();
      }
      
      notifyListeners();
    });
  }

  void setApi(NavidromeApi api, {NetworkProvider? networkProvider}) {
    // Check if the API is already set to the same instance
    if (_api == api) {
      if (kDebugMode) print('[PlayerProvider] API already set to same instance, skipping');
      return;
    }
    
    _api = api;
    _cacheService = CacheService(api: api);
    
    // Initialize audio file cache if network provider is available
    if (networkProvider != null) {
      _networkProvider = networkProvider;
      _audioFileCacheService = AudioFileCacheService(
        api: api,
        networkProvider: networkProvider,
      );
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
        
        // Update audio handler for Android/Linux media session with full queue
        if ((Platform.isAndroid || Platform.isLinux) && app_main.actualAudioHandler != null) {
          await app_main.actualAudioHandler!.updateQueueFromSongs(
            _queue,  // Use the full queue, not just current song
            startIndex: _currentIndex,
            coverArtPaths: [_currentCoverArtPath],
          );
          // The audio handler will handle playback through the shared player
        } else {
          // Check for cached audio file first
          String? audioSource;
          if (_audioFileCacheService != null) {
            final cachedPath = await _audioFileCacheService!.getCachedAudioPath(_currentSong!.id);
            if (cachedPath != null) {
              audioSource = cachedPath;
              if (kDebugMode) print('[PlayerProvider] Restoring from cache: ${_currentSong!.title}');
            }
          }
          
          // Fall back to streaming if not cached
          if (audioSource == null) {
            final shouldTranscode = _networkProvider != null && 
                                   !_networkProvider!.isOnWifi && 
                                   !(Platform.isLinux || Platform.isWindows || Platform.isMacOS);
            audioSource = _api!.getStreamUrl(_currentSong!.id, transcode: shouldTranscode);
            
            // Trigger background caching
            _audioFileCacheService?.cacheAudioFile(_currentSong!.id, albumId: _currentSong!.albumId);
          }
          
          // Set the audio source (either local file or stream URL)
          if (audioSource.startsWith('/')) {
            // Local file path
            await _audioPlayer.setFilePath(audioSource);
          } else {
            // Stream URL
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
    if (_cacheService != null && 
        _currentIndex < _queue.length - 1 && 
        _queue[_currentIndex + 1].coverArt != null) {
      try {
        await _cacheService!.getCachedCoverArt(
          _queue[_currentIndex + 1].coverArt,
          size: 600,
        );
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
    
    // Update audio handler for Android/Linux media session with current cached art
    if (kDebugMode) print('[PlayerProvider] Checking handlers - audioHandler: ${app_main.audioHandler != null}, actualAudioHandler: ${app_main.actualAudioHandler != null}');
    if ((Platform.isAndroid || Platform.isLinux) && app_main.actualAudioHandler != null) {
      if (kDebugMode) print('[PlayerProvider] Updating audio handler queue with ${songs.length} songs');
      await app_main.actualAudioHandler!.updateQueueFromSongs(
        songs, 
        startIndex: startIndex,
        coverArtPaths: [_currentCoverArtPath], // Start with just current song's art
      );
      // The audio handler will set up the playlist in the shared player
    } else {
      if (_useGaplessPlayback && songs.length > 1) {
        // Use gapless playback for queues with multiple songs
        await _setupGaplessPlayback(startIndex);
      } else {
        // Check for cached audio file first
        String? audioSource;
        if (_audioFileCacheService != null) {
          final cachedPath = await _audioFileCacheService!.getCachedAudioPath(_currentSong!.id);
          if (cachedPath != null) {
            audioSource = cachedPath;
            if (kDebugMode) print('[PlayerProvider] Playing from cache: ${_currentSong!.title}');
          }
        }
        
        // Fall back to streaming if not cached
        if (audioSource == null) {
          final shouldTranscode = _networkProvider != null && 
                                 !_networkProvider!.isOnWifi && 
                                 !(Platform.isLinux || Platform.isWindows || Platform.isMacOS);
          audioSource = _api!.getStreamUrl(_currentSong!.id, transcode: shouldTranscode);
          
          // Trigger background caching for current and next tracks
          if (_audioFileCacheService != null) {
            _audioFileCacheService!.cacheAudioFile(_currentSong!.id, albumId: _currentSong!.albumId);
            _audioFileCacheService!.preCacheNextTracks(songs, startIndex);
          }
        }
        
        // Set the audio source (either local file or stream URL)
        print('[PlayerProvider] Setting audio source: $audioSource');
        print('[PlayerProvider] Song: ${_currentSong!.title} by ${_currentSong!.artist}');
        
        try {
          if (audioSource.startsWith('/')) {
            // Local file path
            print('[PlayerProvider] Loading local file');
            await _audioPlayer.setFilePath(audioSource);
          } else {
            // Stream URL
            print('[PlayerProvider] Loading stream URL');
            await _audioPlayer.setUrl(audioSource);
          }
          print('[PlayerProvider] Audio source loaded successfully');
        } catch (e, stackTrace) {
          print('[PlayerProvider] Error loading audio source: $e');
          print('[PlayerProvider] Stack trace: $stackTrace');
          rethrow;
        }
      }
    }
    
    // Always use the shared player for playback
    print('[PlayerProvider] Starting playback...');
    try {
      await _audioPlayer.play();
      print('[PlayerProvider] Playback started successfully');
    } catch (e, stackTrace) {
      print('[PlayerProvider] Error starting playback: $e');
      print('[PlayerProvider] Stack trace: $stackTrace');
      rethrow;
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
    await _audioPlayer.play();
  }

  Future<void> pause() async {
    await _audioPlayer.pause();
    _savePlayerState();
  }

  Future<void> togglePlayPause() async {
    if (_isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> next() async {
    if (_queue.isEmpty || _api == null) return;
    
    // Always use the audio handler for navigation on Android/Linux
    if ((Platform.isAndroid || Platform.isLinux) && app_main.audioHandler != null) {
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
        if (kDebugMode) print('[PlayerProvider] Using preloaded audio for ${_currentSong!.title}');
        _cacheManager.removeCachedPlayer(_currentSong!.id);
        _preloadedSongIds.remove(_currentSong!.id);
      }
      
      // Check for cached audio file first
      String? audioSource;
      if (_audioFileCacheService != null) {
        final cachedPath = await _audioFileCacheService!.getCachedAudioPath(_currentSong!.id);
        if (cachedPath != null) {
          audioSource = cachedPath;
          if (kDebugMode) print('[PlayerProvider] Playing from cache: ${_currentSong!.title}');
        }
      }
      
      // Fall back to streaming if not cached
      if (audioSource == null) {
        final shouldTranscode = _networkProvider != null && 
                               !_networkProvider!.isOnWifi && 
                               !(Platform.isLinux || Platform.isWindows || Platform.isMacOS);
        audioSource = _api!.getStreamUrl(_currentSong!.id, transcode: shouldTranscode);
        
        // Trigger background caching
        if (_audioFileCacheService != null) {
          _audioFileCacheService!.cacheAudioFile(_currentSong!.id, albumId: _currentSong!.albumId);
          _audioFileCacheService!.preCacheNextTracks(_queue, _currentIndex);
        }
      }
      
      // Set the audio source (either local file or stream URL)
      if (audioSource.startsWith('/')) {
        // Local file path
        await _audioPlayer.setFilePath(audioSource);
      } else {
        // Stream URL
        await _audioPlayer.setUrl(audioSource);
      }
      await _audioPlayer.play();
      
      notifyListeners();
      _savePlayerState();
      _checkPreloadNeeded(); // Check if we need to preload more
    }
  }

  Future<void> previous() async {
    if (_queue.isEmpty || _api == null) return;
    
    // Always use the audio handler for navigation on Android/Linux
    if ((Platform.isAndroid || Platform.isLinux) && app_main.audioHandler != null) {
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
      
      // Check for cached audio file first
      String? audioSource;
      if (_audioFileCacheService != null) {
        final cachedPath = await _audioFileCacheService!.getCachedAudioPath(_currentSong!.id);
        if (cachedPath != null) {
          audioSource = cachedPath;
          if (kDebugMode) print('[PlayerProvider] Playing from cache: ${_currentSong!.title}');
        }
      }
      
      // Fall back to streaming if not cached
      if (audioSource == null) {
        final shouldTranscode = _networkProvider != null && 
                               !_networkProvider!.isOnWifi && 
                               !(Platform.isLinux || Platform.isWindows || Platform.isMacOS);
        audioSource = _api!.getStreamUrl(_currentSong!.id, transcode: shouldTranscode);
        
        // Trigger background caching
        _audioFileCacheService?.cacheAudioFile(_currentSong!.id, albumId: _currentSong!.albumId);
      }
      
      // Set the audio source (either local file or stream URL)
      if (audioSource.startsWith('/')) {
        // Local file path
        await _audioPlayer.setFilePath(audioSource);
      } else {
        // Stream URL
        await _audioPlayer.setUrl(audioSource);
      }
      await _audioPlayer.play();
      
      notifyListeners();
      _savePlayerState();
    }
  }

  Future<void> seek(Duration position) async {
    await _audioPlayer.seek(position);
    _position = position;
    notifyListeners();
    _savePlayerState();
  }

  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    await _audioPlayer.setVolume(_volume);
    notifyListeners();
    _savePlayerState();
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
      
      // Removed frequent position logging - too verbose for release builds
    } catch (e) {
      print('Error saving player state: $e');
    }
  }
  
  Future<void> clearPersistedState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('player_current_song');
    await prefs.remove('player_queue');
    await prefs.remove('player_current_index');
    await prefs.remove('player_position');
    await prefs.remove('player_volume');
  }

  Future<void> _setupGaplessPlayback(int startIndex) async {
    if (_api == null) return;
    
    // Create audio sources for the queue
    final audioSources = <AudioSource>[];
    
    // Add up to 3 tracks initially (current + next 2)
    final endIndex = (startIndex + 3).clamp(0, _queue.length);
    
    for (int i = startIndex; i < endIndex; i++) {
      final song = _queue[i];
      final url = _api!.getStreamUrl(song.id);
      audioSources.add(AudioSource.uri(Uri.parse(url)));
    }
    
    // Create concatenating audio source for gapless playback
    _playlist = ConcatenatingAudioSource(children: audioSources);
    
    // Set the playlist
    await _audioPlayer.setAudioSource(_playlist!, initialIndex: 0);
    
    // Schedule adding more tracks as we play
    _scheduleTrackAddition(endIndex);
  }
  
  void _scheduleTrackAddition(int nextIndex) {
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
          // Add the next track
          final song = _queue[nextIndex];
          final url = _api!.getStreamUrl(song.id);
          _playlist!.add(AudioSource.uri(Uri.parse(url)));
          _scheduleTrackAddition(nextIndex + 1);
        }
      }
    });
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
    
    var totalPreloaded = Duration.zero;
    var trackIndex = _currentIndex + 1;
    
    while (trackIndex < _queue.length && totalPreloaded < bufferNeeded) {
      final song = _queue[trackIndex];
      
      // Check if already cached in the cache manager (not just our local tracking)
      final cachedPlayer = _cacheManager.getCachedPlayer(song.id);
      if (cachedPlayer == null) {
        // Not cached, so preload it
        final url = _api!.getStreamUrl(song.id);
        final player = await _cacheManager.preloadTrack(song.id, url);
        
        if (player != null) {
          _preloadedSongIds.add(song.id);
        }
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
      await _audioPlayer.setUrl(_api!.getStreamUrl(_currentSong!.id));
      
      if (duration != null) {
        _duration = duration;
      }
    } catch (e) {
      if (kDebugMode) print('[PlayerProvider] Error switching to preloaded player: $e');
    }
  }

  /// Extract colors from the current song's album art
  Future<void> _extractColorsFromCurrentSong() async {
    if (_currentSong?.coverArt == null || _api == null) {
      _currentColors = ExtractedColors.defaultColors();
      notifyListeners();
      return;
    }

    try {
      // Get the cover art URL using the API method
      final imageUrl = _api!.getCoverArtUrl(_currentSong!.coverArt, size: 400);
      
      // Extract colors with caching
      final cacheKey = 'colors_${_currentSong!.coverArt}_400';
      _currentColors = await _colorExtractionService.extractColorsFromImage(
        imageUrl,
        cacheKey: cacheKey,
      );
      
      notifyListeners();
    } catch (e) {
      print('Error extracting colors from album art: $e');
      _currentColors = ExtractedColors.defaultColors();
      notifyListeners();
    }
  }
  
  @override
  void dispose() {
    _preloadTimer?.cancel();
    _mediaItemSubscription?.cancel();
    _savePlayerState();
    _audioPlayer.dispose();
    _cacheManager.dispose();
    super.dispose();
  }
}