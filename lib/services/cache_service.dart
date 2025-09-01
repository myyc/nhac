import 'dart:io';
import 'dart:typed_data';
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
  Future<List<Artist>> getArtists({bool forceRefresh = false}) async {
    try {
      if (forceRefresh || await needsFullSync()) {
        await syncFullLibrary();
      }
      
      final cached = await DatabaseHelper.getArtists();
      if (cached.isNotEmpty) {
        return cached;
      }
    } catch (e) {
      print('Cache error, falling back to API: $e');
    }
    
    // Fallback to API if cache is empty or failed
    final artists = await api.getArtists();
    try {
      await DatabaseHelper.insertArtists(artists);
    } catch (e) {
      print('Could not cache artists: $e');
    }
    return artists;
  }
  
  Future<List<Album>> getAlbums({bool forceRefresh = false}) async {
    try {
      if (forceRefresh || await needsFullSync()) {
        await syncFullLibrary();
      }
      
      final cached = await DatabaseHelper.getAlbums();
      if (cached.isNotEmpty) {
        return cached;
      }
    } catch (e) {
      print('Cache error, falling back to API: $e');
    }
    
    // Fallback to API if cache is empty or failed
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
  }
  
  Future<List<Album>> getAlbumsByArtist(String artistId, {bool forceRefresh = false}) async {
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
    
    // Fallback to API if cache is empty
    final result = await api.getArtist(artistId);
    final albums = result['albums'] as List<Album>? ?? [];
    await DatabaseHelper.insertAlbums(albums);
    return albums;
  }
  
  Future<List<Song>> getSongsByAlbum(String albumId, {bool forceRefresh = false}) async {
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
    
    // Fallback to API if cache is empty
    final result = await api.getAlbum(albumId);
    final songs = result['songs'] as List<Song>? ?? [];
    await DatabaseHelper.insertSongs(songs);
    return songs;
  }
  
  Future<List<Album>> getRecentlyAdded({bool forceRefresh = false}) async {
    if (forceRefresh || await needsQuickSync()) {
      await syncRecentlyAdded();
    }
    
    // For recently added, always fetch from API to ensure freshness
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
      print('[CacheService] Cover art ID is null');
      return null;
    }
    
    print('[CacheService] Getting cached cover art for ID: $coverArtId, size: $size');
    
    // Check if we have a cached local path
    final cachedPath = await DatabaseHelper.getCoverArtLocalPath(coverArtId);
    if (cachedPath != null) {
      final file = File(cachedPath);
      if (await file.exists()) {
        print('[CacheService] Found cached cover art at: $cachedPath');
        return cachedPath;
      } else {
        print('[CacheService] Cached path exists in DB but file not found: $cachedPath');
      }
    }
    
    // Download and cache the cover art
    try {
      final url = api.getCoverArtUrl(coverArtId, size: size);
      print('[CacheService] Downloading cover art from: $url');
      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200) {
        Directory appDir;
        if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
          appDir = await getApplicationSupportDirectory();
        } else {
          appDir = await getApplicationDocumentsDirectory();
        }
        final coverDir = Directory(path.join(appDir.path, 'covers'));
        
        print('[CacheService] Cover directory: ${coverDir.path}');
        
        if (!await coverDir.exists()) {
          print('[CacheService] Creating cover directory...');
          await coverDir.create(recursive: true);
        }
        
        final fileName = '${coverArtId}_$size.jpg';
        final filePath = path.join(coverDir.path, fileName);
        final file = File(filePath);
        
        print('[CacheService] Saving cover art to: $filePath');
        await file.writeAsBytes(response.bodyBytes);
        
        // Verify file was written
        if (await file.exists()) {
          print('[CacheService] Cover art saved successfully, size: ${response.bodyBytes.length} bytes');
        } else {
          print('[CacheService] WARNING: File not found after writing!');
        }
        
        // Store in database
        await DatabaseHelper.setCoverArtCache(
          coverArtId,
          url,
          filePath,
          response.bodyBytes.length,
        );
        
        return filePath;
      } else {
        print('[CacheService] Failed to download cover art, status: ${response.statusCode}');
      }
    } catch (e) {
      print('[CacheService] Error caching cover art: $e');
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