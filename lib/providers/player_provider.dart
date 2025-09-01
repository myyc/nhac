import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import '../models/song.dart';
import '../services/navidrome_api.dart';
import '../services/audio_cache_manager.dart';
import '../services/mpris_service.dart';

class PlayerProvider extends ChangeNotifier {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final AudioCacheManager _cacheManager = AudioCacheManager();
  NavidromeApi? _api;
  Timer? _preloadTimer;
  ConcatenatingAudioSource? _playlist;
  
  Song? _currentSong;
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
  List<Song> get queue => _queue;
  int get currentIndex => _currentIndex;
  bool get isPlaying => _isPlaying;
  Duration get position => _position;
  Duration get duration => _duration;
  double get volume => _volume;
  String? get currentStreamUrl => _currentSong != null && _api != null 
      ? _api!.getStreamUrl(_currentSong!.id) 
      : null;
  
  PlayerProvider() {
    _initializePlayer();
    _cacheManager.initialize();
    _loadPersistedState();
  }
  
  void _initializePlayer() {
    _audioPlayer.positionStream.listen((position) {
      // Don't update position while restoring
      if (_isRestoring) return;
      
      // Only update position if we've restored or if actively playing
      if (_hasRestoredPosition || _isPlaying) {
        _position = position;
        
        // Update MPRIS position
        if (Platform.isLinux) {
          MprisService.instance.updatePosition(position);
        }
        
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
      
      // Update MPRIS playback status
      if (Platform.isLinux) {
        MprisService.instance.updatePlaybackStatus(isPlaying: state.playing);
      }
      
      if (state.processingState == ProcessingState.completed) {
        next();
      }
      
      notifyListeners();
    });
  }

  void setApi(NavidromeApi api) {
    _api = api;
    // Now that we have the API, try to restore the audio if we have persisted state
    _restoreAudioIfNeeded();
  }
  
  Future<void> _restoreAudioIfNeeded() async {
    if (_currentSong != null && _api != null && !_hasRestoredPosition) {
      _isRestoring = true;
      print('[PlayerProvider] API set, restoring audio for ${_currentSong!.title}');
      final url = _api!.getStreamUrl(_currentSong!.id);
      
      // Store the position we want to restore
      final targetPosition = _position;
      
      try {
        // Load the audio without playing
        await _audioPlayer.setUrl(url);
        
        // Seek to saved position after URL is loaded
        if (targetPosition.inMilliseconds > 0) {
          print('[PlayerProvider] Seeking to saved position: $targetPosition');
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

  Future<void> playSong(Song song) async {
    if (_api == null) return;
    
    _currentSong = song;
    _queue = [song];
    _currentIndex = 0;
    _hasRestoredPosition = true; // New playback, not restoring
    _isRestoring = false; // Not restoring
    _position = Duration.zero; // Reset position for new song
    _playlist = null; // Clear playlist for single song
    
    // Update MPRIS metadata
    if (Platform.isLinux) {
      MprisService.instance.updateMetadata(song);
    }
    
    final url = _api!.getStreamUrl(song.id);
    await _audioPlayer.setUrl(url);
    await _audioPlayer.play();
    
    notifyListeners();
    _savePlayerState();
  }

  Future<void> playQueue(List<Song> songs, {int startIndex = 0}) async {
    if (_api == null || songs.isEmpty) return;
    
    _queue = songs;
    _currentIndex = startIndex;
    _currentSong = songs[startIndex];
    _hasRestoredPosition = true; // New playback, not restoring
    _isRestoring = false; // Not restoring
    _position = Duration.zero; // Reset position for new song
    
    // Update MPRIS metadata
    if (Platform.isLinux) {
      MprisService.instance.updateMetadata(_currentSong);
    }
    
    if (_useGaplessPlayback && songs.length > 1) {
      // Use gapless playback for queues with multiple songs
      await _setupGaplessPlayback(startIndex);
    } else {
      // Single song or gapless disabled
      final url = _api!.getStreamUrl(_currentSong!.id);
      await _audioPlayer.setUrl(url);
    }
    
    await _audioPlayer.play();
    
    notifyListeners();
    _savePlayerState();
  }

  Future<void> addToQueue(Song song) async {
    _queue.add(song);
    
    if (_currentSong == null) {
      await playSong(song);
    }
    
    notifyListeners();
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
      
      // Update MPRIS metadata
      if (Platform.isLinux) {
        MprisService.instance.updateMetadata(_currentSong);
      }
      
      // Try to use preloaded player for minimal gap
      final cachedPlayer = _cacheManager.getCachedPlayer(_currentSong!.id);
      if (cachedPlayer != null) {
        print('[PlayerProvider] Using preloaded audio for ${_currentSong!.title}');
        _cacheManager.removeCachedPlayer(_currentSong!.id);
        _preloadedSongIds.remove(_currentSong!.id);
      }
      
      final url = _api!.getStreamUrl(_currentSong!.id);
      await _audioPlayer.setUrl(url);
      await _audioPlayer.play();
      
      notifyListeners();
      _savePlayerState();
      _checkPreloadNeeded(); // Check if we need to preload more
    }
  }

  Future<void> previous() async {
    if (_queue.isEmpty || _api == null) return;
    
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
      
      // Update MPRIS metadata
      if (Platform.isLinux) {
        MprisService.instance.updateMetadata(_currentSong);
      }
      
      final url = _api!.getStreamUrl(_currentSong!.id);
      await _audioPlayer.setUrl(url);
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
    
    print('[PlayerProvider] Loading persisted state - position: ${positionMillis}ms');
    
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
          coverArt: item['coverArt'],
        )).toList();
        
        _currentIndex = currentIndex;
        _position = Duration(milliseconds: positionMillis);
        _volume = volume;
        
        await _audioPlayer.setVolume(_volume);
        
        // Just restore the state, don't load audio yet (API might not be set)
        print('[PlayerProvider] State restored, waiting for API to load audio');
        
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
        'coverArt': song.coverArt,
      }).toList();
      
      await prefs.setString('player_current_song', json.encode(currentSongMap));
      await prefs.setString('player_queue', json.encode(queueList));
      await prefs.setInt('player_current_index', _currentIndex);
      await prefs.setInt('player_position', _position.inMilliseconds);
      await prefs.setDouble('player_volume', _volume);
      
      print('[PlayerProvider] Saved state - position: ${_position.inMilliseconds}ms');
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
          
          // Update MPRIS metadata
          if (Platform.isLinux) {
            MprisService.instance.updateMetadata(_currentSong);
          }
          
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
      
      // Skip if already preloaded
      if (!_preloadedSongIds.contains(song.id)) {
        final url = _api!.getStreamUrl(song.id);
        final player = await _cacheManager.preloadTrack(song.id, url);
        
        if (player != null) {
          _preloadedSongIds.add(song.id);
          
          // Add the duration of this track to our total
          if (song.duration != null) {
            totalPreloaded += Duration(seconds: song.duration!);
          } else {
            // Assume 3 minutes if duration unknown
            totalPreloaded += const Duration(minutes: 3);
          }
        }
      } else {
        // Track already preloaded, just add its duration
        if (song.duration != null) {
          totalPreloaded += Duration(seconds: song.duration!);
        } else {
          totalPreloaded += const Duration(minutes: 3);
        }
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
      print('[PlayerProvider] Error switching to preloaded player: $e');
    }
  }
  
  @override
  void dispose() {
    _preloadTimer?.cancel();
    _savePlayerState();
    _audioPlayer.dispose();
    _cacheManager.dispose();
    super.dispose();
  }
}