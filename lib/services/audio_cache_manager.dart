import 'package:just_audio/just_audio.dart';
import 'dart:async';

class AudioCacheEntry {
  final AudioPlayer player;
  final String songId;
  final DateTime cachedAt;
  final Duration? duration;
  
  AudioCacheEntry({
    required this.player,
    required this.songId,
    required this.cachedAt,
    this.duration,
  });
  
  bool get isExpired {
    // TODO: Make this configurable in settings
    const cacheLifetime = Duration(hours: 1);
    return DateTime.now().difference(cachedAt) > cacheLifetime;
  }
  
  void dispose() {
    player.dispose();
  }
}

class AudioCacheManager {
  static final AudioCacheManager _instance = AudioCacheManager._internal();
  factory AudioCacheManager() => _instance;
  AudioCacheManager._internal();
  
  final Map<String, AudioCacheEntry> _cache = {};
  Timer? _cleanupTimer;
  
  bool _isSuspended = false;

  void initialize() {
    // Run cleanup every 5 minutes
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _cleanupExpired();
    });
  }

  /// Suspend cleanup timer (for battery optimization)
  void suspend() {
    _isSuspended = true;
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    print('[AudioCache] Suspended - cleanup timer stopped');
  }

  /// Resume cleanup timer
  void resume() {
    _isSuspended = false;
    initialize();
    print('[AudioCache] Resumed - cleanup timer restarted');
  }
  
  Future<AudioPlayer?> preloadTrack(String songId, String streamUrl) async {
    // Check if already cached and not expired
    final existing = _cache[songId];
    if (existing != null && !existing.isExpired) {
      print('[AudioCache] Track $songId already cached');
      return existing.player;
    }
    
    // Dispose expired entry if exists
    if (existing != null) {
      existing.dispose();
      _cache.remove(songId);
    }
    
    try {
      print('[AudioCache] Preloading track $songId');
      final player = AudioPlayer();
      
      // Set up the audio source without playing
      final duration = await player.setUrl(streamUrl);
      
      // Store in cache
      _cache[songId] = AudioCacheEntry(
        player: player,
        songId: songId,
        cachedAt: DateTime.now(),
        duration: duration,
      );
      
      print('[AudioCache] Track $songId preloaded successfully');
      return player;
    } catch (e) {
      print('[AudioCache] Failed to preload track $songId: $e');
      return null;
    }
  }
  
  AudioPlayer? getCachedPlayer(String songId) {
    final entry = _cache[songId];
    if (entry != null && !entry.isExpired) {
      return entry.player;
    }
    return null;
  }
  
  void removeCachedPlayer(String songId) {
    final entry = _cache[songId];
    if (entry != null) {
      entry.dispose();
      _cache.remove(songId);
    }
  }
  
  void _cleanupExpired() {
    final expiredIds = <String>[];
    
    _cache.forEach((id, entry) {
      if (entry.isExpired) {
        expiredIds.add(id);
      }
    });
    
    for (final id in expiredIds) {
      print('[AudioCache] Removing expired track $id');
      _cache[id]!.dispose();
      _cache.remove(id);
    }
  }
  
  void dispose() {
    _cleanupTimer?.cancel();
    _cache.forEach((_, entry) {
      entry.dispose();
    });
    _cache.clear();
  }
  
  int get cachedCount => _cache.length;
  List<String> get cachedSongIds => _cache.keys.toList();
}