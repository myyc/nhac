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

      // Fetch ALL albums, paginating — a complete list is required both for
      // the song caching below and for the prune to be authoritative.
      final albums = <Album>[];
      const pageSize = 500;
      while (true) {
        final page = await api.getAlbumList2(
          type: 'alphabeticalByName',
          size: pageSize,
          offset: albums.length,
        );
        albums.addAll(page);
        if (page.length < pageSize) break;
      }
      await DatabaseHelper.insertAlbums(albums);

      // A complete fetch is authoritative: prune cached rows the server no
      // longer has. Single server-side deletions never trigger the startup
      // probe's wholesale wipe, so this is where they get cleaned up. An
      // empty page means something odd server-side — skip pruning then.
      if (albums.isNotEmpty) {
        await DatabaseHelper.pruneLibraryNotIn(
          artistIds: artists.map((a) => a.id).toList(),
          albumIds: albums.map((a) => a.id).toList(),
        );
      }

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

    // If cache is empty, always try to fetch from API
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
      return [];
    }
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

    // If cache is empty, always try to fetch from API
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
      return [];
    }
  }
  
  Future<List<Album>> getAlbumsByArtist(String artistId, {bool forceRefresh = false, bool allowNetworkFallback = true}) async {
    if (forceRefresh) {
      try {
        // Fetch fresh data from API
        final result = await api.getArtist(artistId);
        final albums = result['albums'] as List<Album>?;
        if (albums != null) {
          await DatabaseHelper.insertAlbums(albums);
        }
      } catch (e) {
        if (isNotFoundError(e)) {
          final healed = await _healStaleArtist(artistId);
          if (healed.isNotEmpty) return healed;
        } else {
          rethrow;
        }
      }
    }

    final cached = await DatabaseHelper.getAlbumsByArtist(artistId);
    if (cached.isNotEmpty) {
      return cached;
    }

    // If cache is empty, always try to fetch from API
    if (!forceRefresh) {
      try {
        final result = await api.getArtist(artistId);
        final albums = result['albums'] as List<Album>? ?? [];
        await DatabaseHelper.insertAlbums(albums);
        return albums;
      } catch (e) {
        print('Network fallback failed for artist albums: $e');
        // Stale artist ID? Silently replace it with the server's current one.
        return _healStaleArtist(artistId);
      }
    }

    return [];
  }
  
  Future<List<Song>> getSongsByAlbum(String albumId, {bool forceRefresh = false, bool allowNetworkFallback = true}) async {
    if (forceRefresh) {
      try {
        // Fetch fresh data from API
        final result = await api.getAlbum(albumId);
        final songs = result['songs'] as List<Song>?;
        if (songs != null) {
          await DatabaseHelper.insertSongs(songs);
        }
      } catch (e) {
        if (isNotFoundError(e)) {
          final healed = await _healStaleAlbum(albumId);
          if (healed.isNotEmpty) return healed;
        } else {
          rethrow;
        }
      }
    }

    final cached = await DatabaseHelper.getSongsByAlbum(albumId);
    if (cached.isNotEmpty) {
      return cached;
    }

    // If cache is empty, always try to fetch from API
    // (allowNetworkFallback is just a hint for optimization, not a hard block)
    if (!forceRefresh) {
      try {
        final result = await api.getAlbum(albumId);
        final songs = result['songs'] as List<Song>? ?? [];
        await DatabaseHelper.insertSongs(songs);
        return songs;
      } catch (e) {
        print('Network fallback failed for album songs: $e');
        // Stale album ID? Silently replace it with the server's current one.
        return _healStaleAlbum(albumId);
      }
    }

    return [];
  }

  /// Subsonic "data not found" (code 70) — the ID is stale, not the network.
  static bool isNotFoundError(Object e) =>
      e is NavidromeApiException && e.isNotFound;

  /// The server is ground truth; a missing album usually means a stale ID
  /// after a server re-index. Resolve it by name+artist, swap the cache entry
  /// for the server's current album and return its tracks. If the album is
  /// genuinely gone, evict the stale entry.
  Future<List<Song>> _healStaleAlbum(String staleAlbumId) async {
    try {
      final albums = await DatabaseHelper.getAlbums();
      Album? stale;
      for (final a in albums) {
        if (a.id == staleAlbumId) {
          stale = a;
          break;
        }
      }
      if (stale == null) return [];

      String norm(String? s) => (s ?? '').trim().toLowerCase();
      final results = await api.search3(stale.name);
      final candidates = results['albums'] as List<Album>? ?? const <Album>[];
      Album? fresh;
      for (final c in candidates) {
        if (norm(c.name) != norm(stale.name)) continue;
        fresh ??= c;
        if (stale.artist == null || norm(c.artist) == norm(stale.artist)) {
          fresh = c;
          break;
        }
      }

      if (fresh == null) {
        await DatabaseHelper.deleteSongsByAlbum(staleAlbumId);
        await DatabaseHelper.deleteAlbum(staleAlbumId);
        return [];
      }

      final result = await api.getAlbum(fresh.id);
      final songs = result['songs'] as List<Song>? ?? const <Song>[];
      await DatabaseHelper.deleteSongsByAlbum(staleAlbumId);
      await DatabaseHelper.deleteAlbum(staleAlbumId);
      await DatabaseHelper.insertAlbums([fresh]);
      if (songs.isNotEmpty) {
        await DatabaseHelper.insertSongs(songs);
      }
      return songs;
    } catch (e) {
      print('Stale album heal failed: $e');
      return [];
    }
  }

  /// Same idea as [_healStaleAlbum] for artists: resolve by name, swap the
  /// cache entry, return the fresh artist's albums; evict when truly gone.
  Future<List<Album>> _healStaleArtist(String staleArtistId) async {
    try {
      final artists = await DatabaseHelper.getArtists();
      Artist? stale;
      for (final a in artists) {
        if (a.id == staleArtistId) {
          stale = a;
          break;
        }
      }
      if (stale == null) return [];

      String norm(String? s) => (s ?? '').trim().toLowerCase();
      final results = await api.search3(stale.name);
      final candidates = results['artists'] as List<Artist>? ?? const <Artist>[];
      Artist? fresh;
      for (final c in candidates) {
        if (norm(c.name) == norm(stale.name)) {
          fresh = c;
          break;
        }
      }

      if (fresh == null) {
        await DatabaseHelper.deleteArtist(staleArtistId);
        return [];
      }

      final result = await api.getArtist(fresh.id);
      final albums = result['albums'] as List<Album>? ?? const <Album>[];
      await DatabaseHelper.deleteArtist(staleArtistId);
      await DatabaseHelper.insertArtists([fresh]);
      if (albums.isNotEmpty) {
        await DatabaseHelper.insertAlbums(albums);
      }
      return albums;
    } catch (e) {
      print('Stale artist heal failed: $e');
      return [];
    }
  }

  /// Startup probe: validate up to two cached album IDs against the server.
  /// If all probes are gone, the cache is from another server era (e.g. a
  /// re-index re-generated every ID) — wipe it once so everything re-syncs
  /// from the ground truth. Probing two IDs avoids wiping when a single
  /// album was merely deleted server-side.
  Future<void> verifyCacheIntegrity() async {
    try {
      final albums = await DatabaseHelper.getAlbums();
      if (albums.isEmpty) return;

      var probes = 0;
      var missing = 0;
      for (final album in albums.take(2)) {
        probes++;
        try {
          await api.getAlbum(album.id);
        } catch (e) {
          if (isNotFoundError(e)) {
            missing++;
          } else {
            // Network trouble is not a cache problem — stay put.
            return;
          }
        }
      }

      if (probes > 0 && missing == probes) {
        if (kDebugMode) {
          print('[CacheService] Integrity probe failed, wiping stale cache');
        }
        await DatabaseHelper.clearAllCache();
        // Re-mark the startup migration so it doesn't re-wipe fresh data.
        await DatabaseHelper.setSyncMetadata(
            'cache_migration_v3_clear_all', DateTime.now().toIso8601String());
      }
    } catch (e) {
      print('Cache integrity probe failed: $e');
    }
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