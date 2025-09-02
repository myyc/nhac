import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'database_helper.dart';
import 'navidrome_api.dart';
import '../providers/network_provider.dart';
import '../models/song.dart';

class AudioFileCacheService {
  final NavidromeApi api;
  final NetworkProvider networkProvider;
  
  // Track ongoing downloads to avoid duplicates
  final Set<String> _downloadingIds = {};
  
  // No size limit on desktop
  static const int _mobileCacheLimit = 10 * 1024 * 1024 * 1024; // 10GB
  
  AudioFileCacheService({
    required this.api,
    required this.networkProvider,
  });
  
  /// Get the cached audio file path if it exists
  Future<String?> getCachedAudioPath(String songId) async {
    try {
      // Desktop: Always look for original format
      if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
        final path = await DatabaseHelper.getAudioCachePath(songId, 'original');
        if (path != null && await File(path).exists()) {
          // Update last played time
          await DatabaseHelper.updateAudioCacheLastPlayed(songId);
          return path;
        }
        return null;
      }
      
      // Mobile: Look for quality matching network type
      final preferredFormat = networkProvider.isOnWifi ? 'original' : 'mp3';
      
      // First try preferred format
      var path = await DatabaseHelper.getAudioCachePath(songId, preferredFormat);
      if (path != null && await File(path).exists()) {
        await DatabaseHelper.updateAudioCacheLastPlayed(songId);
        return path;
      }
      
      // Fall back to any cached format
      path = await DatabaseHelper.getAnyAudioCachePath(songId);
      if (path != null && await File(path).exists()) {
        await DatabaseHelper.updateAudioCacheLastPlayed(songId);
        return path;
      }
      
      return null;
    } catch (e) {
      debugPrint('[AudioFileCache] Error getting cached path: $e');
      return null;
    }
  }
  
  /// Cache an audio file in the background (fire and forget)
  void cacheAudioFile(String songId, {String? albumId}) {
    // Don't wait for this - let it run in background
    _cacheAudioFileAsync(songId, albumId: albumId);
  }
  
  Future<void> _cacheAudioFileAsync(String songId, {String? albumId}) async {
    // Skip if already downloading
    if (_downloadingIds.contains(songId)) return;
    
    // Skip if already cached
    final cached = await getCachedAudioPath(songId);
    if (cached != null) return;
    
    _downloadingIds.add(songId);
    
    try {
      final isDesktop = Platform.isLinux || Platform.isWindows || Platform.isMacOS;
      final shouldTranscode = !isDesktop && !networkProvider.isOnWifi;
      
      // Get the stream URL with appropriate quality
      final url = api.getStreamUrl(songId, transcode: shouldTranscode);
      final format = shouldTranscode ? 'mp3' : 'original';
      
      // Download the file
      final filePath = await _downloadAndSave(songId, url, format);
      
      if (filePath != null) {
        // Get file size
        final file = File(filePath);
        final fileSize = await file.length();
        
        // Save to database
        await DatabaseHelper.insertAudioCache(
          songId: songId,
          format: format,
          filePath: filePath,
          fileSize: fileSize,
          bitrate: shouldTranscode ? 320 : null,
        );
        
        // On desktop, aggressively cache the entire album
        if (isDesktop && albumId != null) {
          _cacheEntireAlbum(albumId);
        }
        
        // On mobile, cleanup if needed
        if (!isDesktop) {
          await _cleanupCacheIfNeeded();
        }
      }
    } catch (e) {
      debugPrint('[AudioFileCache] Error caching $songId: $e');
    } finally {
      _downloadingIds.remove(songId);
    }
  }
  
  /// Download and save a file
  Future<String?> _downloadAndSave(String songId, String url, String format) async {
    try {
      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode != 200) {
        debugPrint('[AudioFileCache] Failed to download $songId: ${response.statusCode}');
        return null;
      }
      
      // Get audio directory
      Directory audioDir;
      if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
        final appDir = await getApplicationSupportDirectory();
        audioDir = Directory(path.join(appDir.path, 'audio_cache'));
      } else {
        final appDir = await getApplicationDocumentsDirectory();
        audioDir = Directory(path.join(appDir.path, 'audio_cache'));
      }
      
      if (!await audioDir.exists()) {
        await audioDir.create(recursive: true);
      }
      
      // Save file with appropriate extension
      final extension = format == 'mp3' ? 'mp3' : 'audio';
      final fileName = '${songId}_$format.$extension';
      final filePath = path.join(audioDir.path, fileName);
      final file = File(filePath);
      
      await file.writeAsBytes(response.bodyBytes);
      
      return filePath;
    } catch (e) {
      debugPrint('[AudioFileCache] Error downloading $songId: $e');
      return null;
    }
  }
  
  /// Cache entire album (desktop only)
  void _cacheEntireAlbum(String albumId) async {
    // Only on desktop with WiFi
    if (!Platform.isLinux && !Platform.isWindows && !Platform.isMacOS) return;
    if (!networkProvider.isOnWifi) return;
    
    try {
      // Get album songs
      final result = await api.getAlbum(albumId);
      final songs = result['songs'] as List<Song>?;
      
      if (songs != null) {
        // Cache each song silently
        for (final song in songs) {
          if (!_downloadingIds.contains(song.id)) {
            // Small delay between downloads to not overwhelm
            await Future.delayed(const Duration(milliseconds: 500));
            cacheAudioFile(song.id);
          }
        }
      }
    } catch (e) {
      debugPrint('[AudioFileCache] Error caching album $albumId: $e');
    }
  }
  
  /// Pre-cache next tracks in queue
  void preCacheNextTracks(List<Song> queue, int currentIndex) {
    // Don't wait for this
    _preCacheNextTracksAsync(queue, currentIndex);
  }
  
  Future<void> _preCacheNextTracksAsync(List<Song> queue, int currentIndex) async {
    final isDesktop = Platform.isLinux || Platform.isWindows || Platform.isMacOS;
    final tracksToCache = isDesktop ? 10 : 3; // More aggressive on desktop
    
    for (int i = 1; i <= tracksToCache && currentIndex + i < queue.length; i++) {
      final song = queue[currentIndex + i];
      
      // Check if already cached
      final cached = await getCachedAudioPath(song.id);
      if (cached == null) {
        // Small delay between downloads
        await Future.delayed(Duration(milliseconds: i * 200));
        cacheAudioFile(song.id, albumId: song.albumId);
      }
    }
  }
  
  /// Cleanup cache on mobile if it exceeds limit
  Future<void> _cleanupCacheIfNeeded() async {
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      return; // No cleanup on desktop
    }
    
    try {
      final totalSize = await DatabaseHelper.getAudioCacheTotalSize();
      
      if (totalSize > _mobileCacheLimit) {
        // Remove least recently played until under limit
        await DatabaseHelper.cleanupAudioCacheLRU(_mobileCacheLimit);
        
        // Also delete the actual files
        final deletedPaths = await DatabaseHelper.getDeletedAudioCachePaths();
        for (final filePath in deletedPaths) {
          try {
            final file = File(filePath);
            if (await file.exists()) {
              await file.delete();
            }
          } catch (e) {
            debugPrint('[AudioFileCache] Error deleting file $filePath: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('[AudioFileCache] Error during cleanup: $e');
    }
  }
  
  /// Clear all audio cache (for settings)
  Future<void> clearAllCache() async {
    try {
      // Get all cached file paths
      final paths = await DatabaseHelper.getAllAudioCachePaths();
      
      // Delete files
      for (final filePath in paths) {
        try {
          final file = File(filePath);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (e) {
          debugPrint('[AudioFileCache] Error deleting $filePath: $e');
        }
      }
      
      // Clear database
      await DatabaseHelper.clearAudioCache();
      
      // Clear downloading set
      _downloadingIds.clear();
    } catch (e) {
      debugPrint('[AudioFileCache] Error clearing cache: $e');
    }
  }
  
  /// Get cache statistics
  Future<Map<String, dynamic>> getCacheStats() async {
    final totalSize = await DatabaseHelper.getAudioCacheTotalSize();
    final fileCount = await DatabaseHelper.getAudioCacheFileCount();
    
    return {
      'totalSize': totalSize,
      'fileCount': fileCount,
      'sizeString': _formatBytes(totalSize),
    };
  }
  
  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}