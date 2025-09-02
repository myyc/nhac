import 'package:flutter/foundation.dart';
import '../services/cache_service.dart';
import '../services/aggressive_cache_service.dart';
import '../services/navidrome_api.dart';
import '../providers/network_provider.dart';
import '../models/artist.dart';
import '../models/album.dart';
import '../models/song.dart';

class CacheProvider extends ChangeNotifier {
  CacheService? _cacheService;
  AggressiveCacheService? _aggressiveCacheService;
  
  CacheService? get cacheService => _cacheService;
  AggressiveCacheService? get aggressiveCacheService => _aggressiveCacheService;
  
  void initialize(NavidromeApi api, NetworkProvider networkProvider) {
    _cacheService = CacheService(api: api);
    _aggressiveCacheService = AggressiveCacheService(
      api: api,
      networkProvider: networkProvider,
    );
    
    // Start aggressive caching immediately
    _aggressiveCacheService!.smartSync();
  }
  
  Future<List<Artist>> getArtists({bool forceRefresh = false}) async {
    if (_cacheService == null) return [];
    
    try {
      return await _cacheService!.getArtists(forceRefresh: forceRefresh);
    } catch (e) {
      print('Error getting artists: $e');
      return [];
    }
  }
  
  Future<List<Album>> getAlbums({bool forceRefresh = false}) async {
    if (_cacheService == null) return [];
    
    try {
      return await _cacheService!.getAlbums(forceRefresh: forceRefresh);
    } catch (e) {
      print('Error getting albums: $e');
      return [];
    }
  }
  
  Future<List<Album>> getAlbumsByArtist(String artistId, {bool forceRefresh = false}) async {
    if (_cacheService == null) return [];
    
    try {
      return await _cacheService!.getAlbumsByArtist(artistId, forceRefresh: forceRefresh);
    } catch (e) {
      print('Error getting albums by artist: $e');
      return [];
    }
  }
  
  Future<List<Song>> getSongsByAlbum(String albumId, {bool forceRefresh = false}) async {
    if (_cacheService == null) return [];
    
    try {
      return await _cacheService!.getSongsByAlbum(albumId, forceRefresh: forceRefresh);
    } catch (e) {
      print('Error getting songs by album: $e');
      return [];
    }
  }
  
  Future<List<Album>> getRecentlyAdded({bool forceRefresh = false}) async {
    if (_cacheService == null) return [];
    
    try {
      return await _cacheService!.getRecentlyAdded(forceRefresh: forceRefresh);
    } catch (e) {
      print('Error getting recently added: $e');
      return [];
    }
  }
  
  Future<String?> getCachedCoverArt(String? coverArtId, {int size = 300}) async {
    if (_cacheService == null || coverArtId == null) return null;
    
    try {
      return await _cacheService!.getCachedCoverArt(coverArtId, size: size);
    } catch (e) {
      print('Error getting cached cover art: $e');
      return null;
    }
  }
  
  String getCoverArtUrl(String? coverArtId, {int size = 300}) {
    if (_cacheService == null || coverArtId == null) return '';
    return _cacheService!.getCoverArtUrl(coverArtId, size: size);
  }
  
  Future<void> clearCache() async {
    if (_cacheService == null) return;
    
    try {
      await _cacheService!.clearCache();
      notifyListeners();
    } catch (e) {
      print('Error clearing cache: $e');
    }
  }
  
  Future<void> cleanupCache() async {
    if (_cacheService == null) return;
    
    try {
      await _cacheService!.cleanupCache();
    } catch (e) {
      print('Error cleaning up cache: $e');
    }
  }
  
  @override
  void dispose() {
    _aggressiveCacheService?.dispose();
    super.dispose();
  }
}