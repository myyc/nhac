import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'database_helper.dart';
import 'navidrome_api.dart';
import '../models/artist.dart';
import '../models/album.dart';
import '../models/song.dart';

class CacheService {
  static const Duration _syncInterval = Duration(hours: 1);
  static const Duration _quickSyncInterval = Duration(minutes: 5);
  
  final NavidromeApi api;
  
  CacheService({required this.api});
  
  // Check if data needs sync
  Future<bool> needsFullSync() async {
    return await DatabaseHelper.needsSync('full_library', _syncInterval);
  }
  
  Future<bool> needsQuickSync() async {
    return await DatabaseHelper.needsSync('recently_added', _quickSyncInterval);
  }

  Future<bool> _checkConnectivity() async {
    try {
      // Simple connectivity check - try to reach the API
      await api.ping();
      return true;
    } catch (e) {
      return false;
    }
  }
  
  // Sync all library data
  Future<void> syncFullLibrary() async {
    try {
      // Fetch all artists
      final artists = await api.getArtists();
      await DatabaseHelper.insertArtists(artists);

      // Fetch all albums
      final albums = await api.getAlbumList2(
        type: 'alphabeticalByName',
        size: 500,
      );
      await DatabaseHelper.insertAlbums(albums);

      // Cache songs for ALL albums to ensure offline browsing works
      try {
        if (kDebugMode) print('[CacheService] Caching songs for ${albums.length} albums');

        for (final album in albums) {
          try {
            final result = await api.getAlbum(album.id);
            final songs = result['songs'] as List<Song>?;
            if (songs != null && songs.isNotEmpty) {
              await DatabaseHelper.insertSongs(songs);
            }
            // Small delay to avoid rate limiting
            await Future.delayed(const Duration(milliseconds: 100));
          } catch (e) {
            print('Error caching songs for album ${album.name}: $e');
          }
        }
      } catch (e) {
        print('Error caching album songs: $e');
      }

      // Update sync metadata
      await DatabaseHelper.setSyncMetadata(
        'full_library',
        DateTime.now().toIso8601String(),
      );
    } catch (e) {
      print('Error syncing full library: $e');
      rethrow;
    }
  }
  
  // Quick sync for recently added items
  Future<void> syncRecentlyAdded() async {
    try {
      final albums = await api.getAlbumList2(
        type: 'newest',
        size: 50,
      );
      await DatabaseHelper.insertAlbums(albums);
      
      await DatabaseHelper.setSyncMetadata(
        'recently_added',
        DateTime.now().toIso8601String(),
      );
    } catch (e) {
      print('Error syncing recently added: $e');
      rethrow;
    }
  }
  
  // Get cached data with fallback to API
  Future<List<Artist>> getArtists({bool forceRefresh = false, bool allowNetworkFallback = true}) async {
    try {
      if (forceRefresh || await needsFullSync()) {
        if (allowNetworkFallback) {
          await syncFullLibrary();
        }
      }

      final cached = await DatabaseHelper.getArtists();
      if (cached.isNotEmpty) {
        return cached;
      }
    } catch (e) {
      print('Cache error: $e');
    }

    // Fallback to API if cache is empty or failed and network fallback is allowed
    if (allowNetworkFallback) {
      try {
        final artists = await api.getArtists();
        try {
          await DatabaseHelper.insertArtists(artists);
        } catch (e) {
          print('Could not cache artists: $e');
        }
        return artists;
      } catch (e) {
        print('Network fallback failed for artists: $e');
        // Return empty list instead of throwing when network fails
        return [];
      }
    }

    // Return empty list if no cached data and network fallback not allowed
    return [];
  }
  
  Future<List<Album>> getAlbums({bool forceRefresh = false, bool allowNetworkFallback = true}) async {
    try {
      if (forceRefresh || await needsFullSync()) {
        if (allowNetworkFallback) {
          await syncFullLibrary();
        }
      }

      final cached = await DatabaseHelper.getAlbums();
      if (cached.isNotEmpty) {
        return cached;
      }
    } catch (e) {
      print('Cache error: $e');
    }

    // Fallback to API if cache is empty or failed and network fallback is allowed
    if (allowNetworkFallback) {
      try {
        final albums = await api.getAlbumList2(
          type: 'alphabeticalByName',
          size: 500,
        );
        try {
          await DatabaseHelper.insertAlbums(albums);
        } catch (e) {
          print('Could not cache albums: $e');
        }
        return albums;
      } catch (e) {
        print('Network fallback failed for albums: $e');
        // Return empty list instead of throwing when network fails
        return [];
      }
    }

    // Return empty list if no cached data and network fallback not allowed
    return [];
  }
  
  Future<List<Album>> getAlbumsByArtist(String artistId, {bool forceRefresh = false, bool allowNetworkFallback = true}) async {
    if (forceRefresh) {
      // Fetch fresh data from API
      final result = await api.getArtist(artistId);
      final albums = result['albums'] as List<Album>?;
      if (albums != null) {
        await DatabaseHelper.insertAlbums(albums);
      }
    }

    final cached = await DatabaseHelper.getAlbumsByArtist(artistId);
    if (cached.isNotEmpty) {
      return cached;
    }

    // Only fallback to API if allowed and we're not forcing refresh
    if (allowNetworkFallback && !forceRefresh) {
      try {
        final result = await api.getArtist(artistId);
        final albums = result['albums'] as List<Album>? ?? [];
        await DatabaseHelper.insertAlbums(albums);
        return albums;
      } catch (e) {
        print('Network fallback failed for artist albums: $e');
        // Return empty list instead of throwing when network fails
        return [];
      }
    }

    // Return empty list if no cached data and network fallback not allowed
    return [];
  }
  
  Future<List<Song>> getSongsByAlbum(String albumId, {bool forceRefresh = false, bool allowNetworkFallback = true}) async {
    if (forceRefresh) {
      // Fetch fresh data from API
      final result = await api.getAlbum(albumId);
      final songs = result['songs'] as List<Song>?;
      if (songs != null) {
        await DatabaseHelper.insertSongs(songs);
      }
    }

    final cached = await DatabaseHelper.getSongsByAlbum(albumId);
    if (cached.isNotEmpty) {
      return cached;
    }

    // Only fallback to API if allowed and we're not forcing refresh
    if (allowNetworkFallback && !forceRefresh) {
      try {
        final result = await api.getAlbum(albumId);
        final songs = result['songs'] as List<Song>? ?? [];
        await DatabaseHelper.insertSongs(songs);
        return songs;
      } catch (e) {
        print('Network fallback failed for album songs: $e');
        // Return empty list instead of throwing when network fails
        return [];
      }
    }

    // Return empty list if no cached data and network fallback not allowed
    return [];
  }
  
  Future<List<Album>> getRecentlyAdded({bool forceRefresh = false}) async {
    // Check if we're offline
    final hasConnectivity = await _checkConnectivity();

    if (!hasConnectivity && !forceRefresh) {
      // Offline - return cached recently added
      try {
        final cached = await DatabaseHelper.getAlbums();
        // Sort by id descending as a proxy for recently added
        cached.sort((a, b) => b.id.compareTo(a.id));
        return cached.take(50).toList();
      } catch (e) {
        print('Error getting cached recently added: $e');
        return [];
      }
    }

    // Online - proceed with normal sync
    if (forceRefresh || await needsQuickSync()) {
      await syncRecentlyAdded();
    }

    // Fetch from API
    final albums = await api.getAlbumList2(
      type: 'newest',
      size: 50,
    );
    await DatabaseHelper.insertAlbums(albums);
    return albums;
  }
  
  // Cover art caching
  Future<String?> getCachedCoverArt(String? coverArtId, {int size = 300}) async {
    if (coverArtId == null) {
      return null;
    }

    // Use size-specific cache key to support multiple resolutions
    final cacheKey = '${coverArtId}_$size';

    // Check if we have a cached local path for this specific size
    final cachedPath = await DatabaseHelper.getCoverArtLocalPath(cacheKey);
    if (cachedPath != null) {
      final file = File(cachedPath);
      if (await file.exists()) {
        return cachedPath;
      }
    }

    // Download and cache the cover art
    try {
      final url = api.getCoverArtUrl(coverArtId, size: size);
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
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

        // Store in database with size-specific key
        await DatabaseHelper.setCoverArtCache(
          cacheKey,
          url,
          filePath,
          response.bodyBytes.length,
        );

        return filePath;
      }
    } catch (e) {
      // Only log errors, not successful operations
      if (kDebugMode) print('[CacheService] Error caching cover art: $e');
    }

    return null;
  }
  
  // Generate stable cover URL using session-based auth params
  String getCoverArtUrl(String? coverArtId, {int size = 300}) {
    if (coverArtId == null) return '';
    // This returns a stable URL for the session
    return api.getCoverArtUrl(coverArtId, size: size);
  }
  
  // Clear all cache
  Future<void> clearCache() async {
    await DatabaseHelper.clearAllCache();
    
    // Delete cover art files
    try {
      Directory appDir;
      if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
        appDir = await getApplicationSupportDirectory();
      } else {
        appDir = await getApplicationDocumentsDirectory();
      }
      final coverDir = Directory(path.join(appDir.path, 'covers'));
      if (await coverDir.exists()) {
        await coverDir.delete(recursive: true);
      }
    } catch (e) {
      print('Error deleting cover art files: $e');
    }
  }
  
  // Cleanup old cache entries
  Future<void> cleanupCache() async {
    await DatabaseHelper.cleanupOldCache();
  }
}