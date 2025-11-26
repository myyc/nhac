import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'database_helper.dart';
import 'navidrome_api.dart';
import '../models/artist.dart';
import '../models/album.dart';
import '../models/song.dart';
import '../providers/network_provider.dart';

class AggressiveCacheService {
  static const Duration _quickSyncInterval = Duration(minutes: 2);  // Aggressive on WiFi
  static const Duration _fullSyncInterval = Duration(hours: 24);    // Fallback

  final NavidromeApi api;
  final NetworkProvider networkProvider;

  int _syncProgress = 0;
  int _syncTotal = 0;
  bool _isSyncing = false;
  bool _isSuspended = false;
  Timer? _syncTimer;
  
  final _progressController = StreamController<SyncProgress>.broadcast();
  Stream<SyncProgress> get progressStream => _progressController.stream;
  
  AggressiveCacheService({
    required this.api,
    required this.networkProvider,
  }) {
    // Start periodic sync
    _startPeriodicSync();
    
    // React to network changes
    networkProvider.addListener(_onNetworkChanged);
  }
  
  void _startPeriodicSync() {
    _syncTimer?.cancel();
    
    // More aggressive sync on WiFi
    final interval = networkProvider.isOnWifi 
      ? _quickSyncInterval 
      : const Duration(minutes: 15);
    
    _syncTimer = Timer.periodic(interval, (_) {
      smartSync();
    });
    
    // Initial sync
    smartSync();
  }
  
  void _onNetworkChanged() {
    if (networkProvider.isOnWifi) {
      // Switched to WiFi - sync immediately
      _startPeriodicSync();
      smartSync();
    }
  }
  
  /// Suspend all background sync tasks (for battery optimization)
  void suspend() {
    _isSuspended = true;
    _syncTimer?.cancel();
    _syncTimer = null;
    if (kDebugMode) debugPrint('[AggressiveCache] Suspended - timers stopped');
  }

  /// Resume background sync tasks
  void resume() {
    _isSuspended = false;
    _startPeriodicSync();
    if (kDebugMode) debugPrint('[AggressiveCache] Resumed - timers restarted');
  }

  Future<void> smartSync() async {
    if (_isSyncing || _isSuspended) return;
    if (networkProvider.isOffline) return;
    
    _isSyncing = true;
    
    try {
      if (!networkProvider.isOnWifi) {
        // On mobile: only sync recent items
        await _syncRecentlyAdded(size: 30);
      } else {
        // On WiFi: check if we need full sync
        final needsFull = await _checkIfFullSyncNeeded();
        
        if (needsFull) {
          await _syncEverything();
          await _downloadAllCoverArt();
        } else {
          await _syncRecentlyAdded(size: 100);
          await _downloadMissingCoverArt();
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[AggressiveCache] Sync error: $e');
    } finally {
      _isSyncing = false;
    }
  }
  
  Future<bool> _checkIfFullSyncNeeded() async {
    try {
      // Check if cache is empty
      final cachedAlbums = await DatabaseHelper.getAlbums();
      if (cachedAlbums.isEmpty) {
        return true;
      }
      
      // Check if last full sync was too long ago
      final needsSync = await DatabaseHelper.needsSync('full_library', _fullSyncInterval);
      if (needsSync) {
        return true;
      }
      
      // Check for significant changes by comparing newest album
      final newestApi = await api.getAlbumList2(type: 'newest', size: 10);
      final newestCached = await DatabaseHelper.getSyncMetadata('newest_album_id');
      
      if (newestApi.isNotEmpty && newestCached != newestApi.first.id) {
        // Count how many new albums
        int newCount = 0;
        for (final album in newestApi) {
          if (album.id == newestCached) break;
          newCount++;
        }
        
        if (newCount > 5) {
          return true;
        }
      }
      
      return false;
    } catch (e) {
      return true; // When in doubt, sync
    }
  }
  
  Future<void> _syncEverything() async {
    _syncProgress = 0;
    _syncTotal = 0;
    
    try {
      // First, get all artists
      final artists = await api.getArtists();
      await DatabaseHelper.insertArtists(artists);
      
      // Get ALL albums - no limit!
      final allAlbums = <Album>[];
      int offset = 0;
      const batchSize = 100;
      
      while (true) {
        final albums = await api.getAlbumList2(
          type: 'alphabeticalByName',
          size: batchSize,
          offset: offset,
        );
        
        if (albums.isEmpty) break;
        
        allAlbums.addAll(albums);
        await DatabaseHelper.insertAlbums(albums);
        
        
        offset += batchSize;
        
        // Prevent infinite loop
        if (offset > 10000) {
          break;
        }
      }
      
      _syncTotal = allAlbums.length;
      
      // Now fetch all songs for each album
      for (int i = 0; i < allAlbums.length; i++) {
        final album = allAlbums[i];
        
        try {
          final result = await api.getAlbum(album.id);
          final songs = result['songs'] as List<Song>?;
          
          if (songs != null && songs.isNotEmpty) {
            await DatabaseHelper.insertSongs(songs);
          }
          
          _syncProgress = i + 1;
          _progressController.add(SyncProgress(
            current: _syncProgress,
            total: _syncTotal,
            message: 'Syncing songs: ${album.name}',
          ));
          
          // Small delay to prevent overwhelming the server
          if (i % 10 == 0) {
            await Future.delayed(const Duration(milliseconds: 100));
          }
        } catch (e) {
          if (kDebugMode) debugPrint('[AggressiveCache] Error fetching album ${album.id}: $e');
        }
      }
      
      // Save sync metadata
      await DatabaseHelper.setSyncMetadata(
        'full_library',
        DateTime.now().toIso8601String(),
      );
      
      if (allAlbums.isNotEmpty) {
        await DatabaseHelper.setSyncMetadata(
          'newest_album_id',
          allAlbums.first.id,
        );
      }
      
      
    } catch (e) {
      rethrow;
    }
  }
  
  Future<void> _syncRecentlyAdded({required int size}) async {
    try {
      final albums = await api.getAlbumList2(
        type: 'newest',
        size: size,
      );
      
      if (albums.isNotEmpty) {
        await DatabaseHelper.insertAlbums(albums);
        
        // Also fetch songs for these albums
        for (final album in albums) {
          try {
            final result = await api.getAlbum(album.id);
            final songs = result['songs'] as List<Song>?;
            if (songs != null) {
              await DatabaseHelper.insertSongs(songs);
            }
          } catch (e) {
            if (kDebugMode) debugPrint('[AggressiveCache] Error fetching songs for ${album.id}: $e');
          }
        }
        
        await DatabaseHelper.setSyncMetadata(
          'newest_album_id',
          albums.first.id,
        );
      }
      
      await DatabaseHelper.setSyncMetadata(
        'recently_added',
        DateTime.now().toIso8601String(),
      );
      
    } catch (e) {
    }
  }
  
  Future<void> _downloadAllCoverArt() async {
    if (!networkProvider.isOnWifi) return;
    
    
    try {
      final albums = await DatabaseHelper.getAlbums();
      if (albums.isEmpty) return;
      
      final sizes = [112, 300, 800]; // List, grid, and full size
      int completed = 0;
      final total = albums.length * sizes.length;
      
      _progressController.add(SyncProgress(
        current: 0,
        total: total,
        message: 'Downloading cover art...',
      ));
      
      // Process in batches to avoid overwhelming the system
      const batchSize = 10;
      
      for (int i = 0; i < albums.length; i += batchSize) {
        if (!networkProvider.isOnWifi) {
          break;
        }
        
        final batch = albums.skip(i).take(batchSize).toList();
        
        // Download covers in parallel for this batch
        final futures = <Future>[];
        
        for (final album in batch) {
          if (album.coverArt == null) continue;
          
          for (final size in sizes) {
            futures.add(
              _downloadCoverArt(album.coverArt!, size).then((_) {
                completed++;
                if (completed % 10 == 0) {
                  _progressController.add(SyncProgress(
                    current: completed,
                    total: total,
                    message: 'Cover art: $completed/$total',
                  ));
                }
              })
            );
          }
        }
        
        await Future.wait(futures, eagerError: false);
        
        // Small delay between batches
        await Future.delayed(const Duration(milliseconds: 200));
      }
      
      
    } catch (e) {
      if (kDebugMode) debugPrint('[AggressiveCache] Error downloading cover art: $e');
    }
  }
  
  Future<void> _downloadMissingCoverArt() async {
    if (!networkProvider.isOnWifi) return;
    
    try {
      // Get recently viewed albums that might be missing covers
      final albums = await DatabaseHelper.getAlbums();
      final sizes = [300]; // Just the main size for missing covers
      
      int downloaded = 0;
      for (final album in albums.take(50)) { // Check first 50 albums
        if (album.coverArt == null) continue;
        
        for (final size in sizes) {
          final cached = await DatabaseHelper.getCoverArtLocalPath(album.coverArt!);
          if (cached == null) {
            await _downloadCoverArt(album.coverArt!, size);
            downloaded++;
          }
        }
        
        if (downloaded > 20) break; // Limit per sync cycle
      }
      
      if (downloaded > 0) {
      }
      
    } catch (e) {
    }
  }
  
  Future<void> _downloadCoverArt(String coverArtId, int size) async {
    try {
      // Check if already cached
      final cachedPath = await DatabaseHelper.getCoverArtLocalPath(coverArtId);
      if (cachedPath != null) {
        final file = File(cachedPath);
        if (await file.exists()) {
          return; // Already cached
        }
      }
      
      // Download the cover
      final url = api.getCoverArtUrl(coverArtId, size: size);
      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200) {
        // Save to disk
        Directory appDir;
        if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
          appDir = await getApplicationSupportDirectory();
        } else {
          appDir = await getApplicationDocumentsDirectory();
        }
        
        final coverDir = Directory(path.join(appDir.path, 'covers'));
        if (!await coverDir.exists()) {
          await coverDir.create(recursive: true);
        }
        
        final fileName = '${coverArtId}_$size.jpg';
        final filePath = path.join(coverDir.path, fileName);
        final file = File(filePath);
        
        await file.writeAsBytes(response.bodyBytes);
        
        // Store in database
        await DatabaseHelper.setCoverArtCache(
          coverArtId,
          url,
          filePath,
          response.bodyBytes.length,
        );
      }
    } catch (e) {
      // Silently fail for individual covers
    }
  }
  
  void dispose() {
    _syncTimer?.cancel();
    _progressController.close();
    networkProvider.removeListener(_onNetworkChanged);
  }
}

class SyncProgress {
  final int current;
  final int total;
  final String message;
  
  SyncProgress({
    required this.current,
    required this.total,
    required this.message,
  });
  
  double get percentage => total > 0 ? current / total : 0;
}