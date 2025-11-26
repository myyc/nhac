import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/cache_service.dart';
import '../services/aggressive_cache_service.dart';
import '../services/library_scan_service.dart';
import '../services/navidrome_api.dart';
import '../services/database_helper.dart';
import '../providers/network_provider.dart';
import '../models/artist.dart';
import '../models/album.dart';
import '../models/song.dart';

class CacheProvider extends ChangeNotifier {
  CacheService? _cacheService;
  AggressiveCacheService? _aggressiveCacheService;
  LibraryScanService? _libraryScanService;
  StreamSubscription<LibraryChangeEvent>? _scanSubscription;
  NetworkProvider? _networkProvider;

  CacheService? get cacheService => _cacheService;
  AggressiveCacheService? get aggressiveCacheService => _aggressiveCacheService;
  LibraryScanService? get libraryScanService => _libraryScanService;

  // Stream for library changes
  final _libraryUpdatesController = StreamController<LibraryChangeEvent>.broadcast();
  Stream<LibraryChangeEvent> get libraryUpdates => _libraryUpdatesController.stream;

  // Periodic sync timer
  Timer? _syncTimer;

  // Background task suspension state
  bool _isSuspended = false;

  // Offline functionality
  bool get isOffline => _networkProvider?.isOffline ?? false;
  
  void initialize(NavidromeApi api, NetworkProvider networkProvider) {
    _cacheService = CacheService(api: api);
    _aggressiveCacheService = AggressiveCacheService(
      api: api,
      networkProvider: networkProvider,
    );
    _libraryScanService = LibraryScanService(api: api);
    
    // Listen to library scan changes
    _scanSubscription = _libraryScanService!.libraryChanges.listen((event) {
      if (kDebugMode) {
        print('[CacheProvider] Library changes detected: ${event.newAlbumCount} new albums');
      }
      
      // Forward the event to our listeners
      _libraryUpdatesController.add(event);
      
      // Notify UI to refresh
      notifyListeners();
    });
    
    // Adjust scan interval based on network conditions
    networkProvider.addListener(() {
      _libraryScanService?.adjustScanInterval(isOnWifi: networkProvider.isOnWifi);
    });
    
    // Set initial scan interval based on current network
    _libraryScanService!.adjustScanInterval(isOnWifi: networkProvider.isOnWifi);
    
    // Start aggressive caching immediately
    _aggressiveCacheService!.smartSync();

    // Start background library scan
    _startBackgroundScan();

    // Start periodic sync timer (every 5 minutes)
    _startPeriodicSync();
  }
  
  // Start background scan with a small delay to let the app initialize
  Future<void> _startBackgroundScan() async {
    await Future.delayed(const Duration(seconds: 3));

    if (_libraryScanService != null) {
      if (kDebugMode) print('[CacheProvider] Initiating background library scan');
      _libraryScanService!.startBackgroundScan();
    }
  }

  // Start periodic sync timer
  void _startPeriodicSync() {
    // Sync every 5 minutes
    _syncTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      if (!isOffline && !_isSuspended) {
        autoSync();
      }
    });

    // Also trigger an initial sync after a short delay
    Future.delayed(const Duration(seconds: 10), () {
      if (!isOffline && !_isSuspended) {
        autoSync();
      }
    });
  }

  /// Suspend all background sync tasks (for battery optimization)
  void suspend() {
    if (_isSuspended) return;
    _isSuspended = true;

    // Stop our own timer
    _syncTimer?.cancel();
    _syncTimer = null;

    // Suspend child services
    _libraryScanService?.stopPeriodicScanning();
    _aggressiveCacheService?.suspend();

    if (kDebugMode) print('[CacheProvider] Suspended all background tasks');
  }

  /// Resume all background sync tasks
  void resume() {
    if (!_isSuspended) return;
    _isSuspended = false;

    // Restart our own timer
    _startPeriodicSync();

    // Resume child services
    _libraryScanService?.resumePeriodicScanning();
    _aggressiveCacheService?.resume();

    if (kDebugMode) print('[CacheProvider] Resumed all background tasks');
  }
  
  // Manual library scan (can be triggered by user)
  Future<void> checkForLibraryUpdates() async {
    if (_libraryScanService != null) {
      await _libraryScanService!.checkForUpdates();
    }
  }
  
  Future<List<Artist>> getArtists({bool forceRefresh = false}) async {
    if (_cacheService == null) return [];

    try {
      // Disable network fallback when offline to prevent API calls
      final allowNetworkFallback = !isOffline;
      return await _cacheService!.getArtists(
        forceRefresh: forceRefresh,
        allowNetworkFallback: allowNetworkFallback,
      );
    } catch (e) {
      print('Error getting artists: $e');
      return [];
    }
  }

  Future<List<Artist>> getArtistsOffline({bool forceRefresh = false}) async {
    // If offline and not forcing refresh, return cached artists
    if (isOffline && !forceRefresh) {
      return await getCachedArtists();
    }

    // Otherwise use regular method
    return getArtists(forceRefresh: forceRefresh);
  }

  Future<List<Artist>> getCachedArtists() async {
    try {
      return await DatabaseHelper.getArtists();
    } catch (e) {
      print('Error getting cached artists: $e');
      return [];
    }
  }
  
  Future<List<Album>> getAlbums({bool forceRefresh = false}) async {
    if (_cacheService == null) return [];

    try {
      // Disable network fallback when offline to prevent API calls
      final allowNetworkFallback = !isOffline;
      return await _cacheService!.getAlbums(
        forceRefresh: forceRefresh,
        allowNetworkFallback: allowNetworkFallback,
      );
    } catch (e) {
      print('Error getting albums: $e');
      return [];
    }
  }
  
  Future<List<Album>> getAlbumsByArtist(String artistId, {bool forceRefresh = false}) async {
    if (_cacheService == null) return [];

    try {
      // Disable network fallback when offline to prevent API calls
      final allowNetworkFallback = !isOffline;
      return await _cacheService!.getAlbumsByArtist(
        artistId,
        forceRefresh: forceRefresh,
        allowNetworkFallback: allowNetworkFallback,
      );
    } catch (e) {
      print('Error getting albums by artist: $e');
      return [];
    }
  }
  
  Future<List<Song>> getSongsByAlbum(String albumId, {bool forceRefresh = false}) async {
    if (_cacheService == null) return [];

    try {
      // Disable network fallback when offline to prevent API calls
      final allowNetworkFallback = !isOffline;
      return await _cacheService!.getSongsByAlbum(
        albumId,
        forceRefresh: forceRefresh,
        allowNetworkFallback: allowNetworkFallback,
      );
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

  // Offline functionality methods

  Future<bool> isSongCached(String songId) async {
    return await DatabaseHelper.isSongCached(songId);
  }


  Future<List<Song>> getCachedSongs({String? albumId}) async {
    try {
      final cachedData = await DatabaseHelper.getCachedSongs(albumId: albumId);
      return cachedData.map((row) => Song.fromJson(row)).toList();
    } catch (e) {
      print('Error getting cached songs: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> searchOffline(String query) async {
    if (!isOffline) return {'songs': <Song>[], 'albums': <Album>[], 'artists': <Artist>[]};

    try {
      final results = await DatabaseHelper.searchAllFTS(query);

      return {
        'songs': results['songs']?.map<Song>((row) => Song.fromJson(row)).toList() ?? <Song>[],
        'albums': results['albums']?.map<Album>((row) => Album.fromJson(row)).toList() ?? <Album>[],
        'artists': results['artists']?.map<Artist>((row) => Artist.fromJson(row)).toList() ?? <Artist>[],
      };
    } catch (e) {
      print('Error searching offline: $e');
      return {'songs': <Song>[], 'albums': <Album>[], 'artists': <Artist>[]};
    }
  }


  Future<void> updateSongCacheStatus(String songId, bool isCached, {String? cachedPath, bool notify = true}) async {
    try {
      if (kDebugMode) {
        print('[CacheProvider] Updating song cache status - ID: $songId, Cached: $isCached, Path: $cachedPath');
      }
      await DatabaseHelper.updateSongCacheStatus(songId, isCached, cachedPath: cachedPath);
      if (notify) {
        notifyListeners();
      }
      if (kDebugMode) {
        print('[CacheProvider] Song cache status updated successfully');
      }
    } catch (e) {
      print('[CacheProvider] Error updating song cache status: $e');
    }
  }

  /// Batch update multiple song cache statuses
  Future<void> updateSongsCacheStatus(List<String> songIds, bool isCached, {bool notify = true}) async {
    try {
      if (kDebugMode) {
        print('[CacheProvider] Batch updating ${songIds.length} songs cache status to: $isCached');
      }

      for (final songId in songIds) {
        await DatabaseHelper.updateSongCacheStatus(songId, isCached, cachedPath: null);
      }

      if (notify) {
        notifyListeners();
      }

      if (kDebugMode) {
        print('[CacheProvider] Batch update completed successfully');
      }
    } catch (e) {
      print('[CacheProvider] Error in batch update: $e');
    }
  }


  // Enhanced methods to work offline
  Future<List<Album>> getAlbumsOffline({bool forceRefresh = false}) async {
    // If offline and not forcing refresh, return all albums (no album caching)
    if (isOffline && !forceRefresh) {
      return getAlbums();
    }

    // Otherwise use regular method
    return getAlbums(forceRefresh: forceRefresh);
  }

  // Library sync methods
  Future<void> syncFullLibrary() async {
    if (_cacheService == null) return;

    try {
      if (kDebugMode) print('[CacheProvider] Starting full library sync');
      await _cacheService!.syncFullLibrary();

      // Notify listeners that library has been updated
      _libraryUpdatesController.add(LibraryChangeEvent(
        hasNewAlbums: false,
        newAlbumCount: 0,
        totalAlbumCountChange: 0,
        newestAlbums: [],
      ));

      if (kDebugMode) print('[CacheProvider] Full library sync completed');
    } catch (e) {
      print('Error syncing full library: $e');
      rethrow;
    }
  }

  Future<void> syncRecentlyAdded() async {
    if (_cacheService == null) return;

    try {
      if (kDebugMode) print('[CacheProvider] Starting recently added sync');
      await _cacheService!.syncRecentlyAdded();

      // Notify listeners that library has been updated
      _libraryUpdatesController.add(LibraryChangeEvent(
        hasNewAlbums: false,
        newAlbumCount: 0,
        totalAlbumCountChange: 0,
        newestAlbums: [],
      ));

      if (kDebugMode) print('[CacheProvider] Recently added sync completed');
    } catch (e) {
      print('Error syncing recently added: $e');
      rethrow;
    }
  }

  Future<bool> needsFullSync() async {
    if (_cacheService == null) return false;
    return await _cacheService!.needsFullSync();
  }

  Future<bool> needsQuickSync() async {
    if (_cacheService == null) return false;
    return await _cacheService!.needsQuickSync();
  }

  // Auto-sync method that checks if sync is needed
  Future<void> autoSync() async {
    if (isOffline) return;

    try {
      // Check if we need quick sync (recently added)
      if (await needsQuickSync()) {
        await syncRecentlyAdded();
      }

      // Check if we need full sync (not done in last hour)
      if (await needsFullSync()) {
        await syncFullLibrary();
      }
    } catch (e) {
      print('Error during auto sync: $e');
    }
  }

  Future<List<Song>> getSongsByAlbumOffline(String albumId, {bool forceRefresh = false}) async {
    // If offline and not forcing refresh, return cached songs
    if (isOffline && !forceRefresh) {
      return await getCachedSongs(albumId: albumId);
    }

    // Otherwise use regular method
    return getSongsByAlbum(albumId, forceRefresh: forceRefresh);
  }

  Future<List<Album>> getRecentlyAddedOffline({bool forceRefresh = false}) async {
    // If offline and not forcing refresh, return recently added (no album caching)
    if (isOffline && !forceRefresh) {
      return getRecentlyAdded();
    }

    // Otherwise use regular method
    return getRecentlyAdded(forceRefresh: forceRefresh);
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _syncTimer?.cancel();
    _libraryScanService?.dispose();
    _aggressiveCacheService?.dispose();
    _libraryUpdatesController.close();
    super.dispose();
  }
}