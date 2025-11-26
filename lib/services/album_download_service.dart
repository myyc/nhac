import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'database_helper.dart';
import 'navidrome_api.dart';
import '../providers/network_provider.dart';
import '../services/activity_coordinator.dart';
import '../models/album.dart';
import '../models/song.dart';

class AlbumDownloadService extends ChangeNotifier {
  NavidromeApi _api;
  NetworkProvider _networkProvider;
  ActivityCoordinator? _activityCoordinator;

  NavidromeApi get api => _api;
  NetworkProvider get networkProvider => _networkProvider;

  final _downloadsController = StreamController<AlbumDownloadProgress>.broadcast();
  Stream<AlbumDownloadProgress> get downloadProgress => _downloadsController.stream;

  final _activeDownloads = <String, AlbumDownloadTask>{};
  final _downloadQueue = <AlbumDownloadTask>[];
  bool _isProcessingQueue = false;

  // Debouncing timers for progress updates
  final _progressTimers = <String, Timer>{};

  // Rate limiting
  static const int _maxConcurrentDownloads = 2;

  AlbumDownloadService({
    required NavidromeApi api,
    required NetworkProvider networkProvider,
  }) : _api = api, _networkProvider = networkProvider;

  /// Update dependencies without losing state (called by ChangeNotifierProxyProvider)
  void updateDependencies({
    required NavidromeApi api,
    required NetworkProvider networkProvider,
  }) {
    _api = api;
    _networkProvider = networkProvider;
  }

  /// Set the ActivityCoordinator for reporting download state
  void setActivityCoordinator(ActivityCoordinator coordinator) {
    _activityCoordinator = coordinator;
  }

  Future<void> downloadAlbum(Album album, List<Song> songs) async {
    // Check if already downloading (check by albumId, not downloadId)
    final existingDownload = _activeDownloads.values
        .where((task) => task.albumId == album.id)
        .firstOrNull;
    if (existingDownload != null) {
      print('[AlbumDownloadService] Album ${album.name} is already downloading');
      // Emit current progress so UI updates
      _downloadsController.add(existingDownload.toProgress());
      return;
    }

    final downloadId = _generateDownloadId();

    // Create download task
    final task = AlbumDownloadTask(
      id: downloadId,
      albumId: album.id,
      album: album,
      songs: songs,
      status: AlbumDownloadStatus.pending,
      progress: 0,
      createdAt: DateTime.now(),
    );

    // Save to database
    await DatabaseHelper.insertAlbumDownload(
      id: downloadId,
      albumId: album.id,
      status: 'pending',
      totalSize: songs.length,
    );

    _activeDownloads[downloadId] = task;
    _downloadsController.add(task.toProgress());

    // Add to queue and start processing if not already running
    _downloadQueue.add(task);
    if (!_isProcessingQueue) {
      _processQueue();
    }
  }

  Future<void> _processQueue() async {
    if (_isProcessingQueue || _downloadQueue.isEmpty) {
      return;
    }

    _isProcessingQueue = true;
    // Report downloading state to ActivityCoordinator
    _activityCoordinator?.setDownloadingState(true);

    try {
      // Keep processing until queue is empty
      while (_downloadQueue.isNotEmpty) {
        // Process up to max concurrent downloads
        final batch = <Future>[];
        while (_downloadQueue.isNotEmpty && batch.length < _maxConcurrentDownloads) {
          final task = _downloadQueue.removeAt(0);
          batch.add(_processDownload(task));
        }
        // Wait for this batch to complete before starting next
        await Future.wait(batch);
      }
    } finally {
      _isProcessingQueue = false;
      // Report download queue empty to ActivityCoordinator
      _activityCoordinator?.setDownloadingState(false);
    }
  }

  Future<void> _processDownload(AlbumDownloadTask task) async {
    try {
      // Update status to downloading
      task.status = AlbumDownloadStatus.downloading;
      await DatabaseHelper.updateAlbumDownloadStatus(task.id, 'downloading');
      _downloadsController.add(task.toProgress());

      int completedSongs = 0;
      int totalSize = 0;

      // Calculate total size
      for (final song in task.songs) {
        if (song.duration != null) {
          // Estimate size based on duration and bitrate
          totalSize += (song.duration! * 320); // 320 kbps estimate
        }
      }

      // Calculate already completed songs (for resume functionality)
      completedSongs = task.currentSongIndex;

      // Start from the current song index (for resume functionality)
      for (int i = task.currentSongIndex; i < task.songs.length; i++) {
        // Check if paused or cancelled during processing
        if (task.status == AlbumDownloadStatus.paused ||
            task.status == AlbumDownloadStatus.cancelled) {
          if (kDebugMode) {
            print('[AlbumDownload] Download stopped: ${task.status}');
          }
          task.currentSongIndex = i; // Save position for resume
          return;
        }

        final song = task.songs[i];

        try {
          // Check if already cached using songs table
          final songCacheInfo = await DatabaseHelper.getSongCacheInfo(song.id);
          if (songCacheInfo != null && songCacheInfo['cached_path'] != null) {
            final existingPath = songCacheInfo['cached_path'] as String;
            final existingFile = File(existingPath);
            if (await existingFile.exists() && await existingFile.length() > 1000) {
              if (kDebugMode) {
                print('[AlbumDownload] Song "${song.title}" already cached, skipping');
              }
              completedSongs++;
              task.currentSongIndex = i + 1; // Update position
              task.progress = ((completedSongs / task.songs.length) * 100).round();
              await DatabaseHelper.updateAlbumDownloadProgress(task.id, task.progress, downloadedSongs: completedSongs);
              _debouncedProgressUpdate(task.id, task);
              continue;
            }
          }

          // Start downloading this song
          if (kDebugMode) {
            print('[AlbumDownload] Starting download: "${song.title}" (${song.formattedDuration})');
          }

          // Download the song
          final isDesktop = Platform.isLinux || Platform.isWindows || Platform.isMacOS;
          final shouldTranscode = !isDesktop && !networkProvider.isOnWifi;
          final url = api.getStreamUrl(song.id, transcode: shouldTranscode);

          if (kDebugMode) {
            print('[AlbumDownload] Downloading from: $url');
          }

          // Get cache directory and file path first
          final cacheDir = await _getCacheDirectory();
          String fileExtension;
          if (shouldTranscode) {
            fileExtension = 'mp3';
          } else {
            fileExtension = song.suffix?.toLowerCase() ?? 'flac';
            switch (fileExtension) {
              case 'flac':
              case 'mp3':
              case 'ogg':
              case 'wav':
                break;
              case 'aac':
              case 'm4a':
                fileExtension = 'm4a';
                break;
              default:
                fileExtension = 'flac';
            }
          }
          final fileName = '${song.id}.$fileExtension';
          final filePath = path.join(cacheDir, fileName);

          // Download using HttpClient - stream directly to file to avoid memory issues
          final downloadSuccess = await _downloadFile(url, filePath);
          if (!downloadSuccess) {
            print('[AlbumDownload] Download failed for ${song.title}');
            continue;
          }

          // Verify file was downloaded
          final file = File(filePath);
          if (!await file.exists()) {
            print('[AlbumDownload] File not created for ${song.title}');
            continue;
          }

          final fileSize = await file.length();
          if (fileSize < 1000) {
            // Read and log the content to see what the server returned
            final content = await file.readAsString();
            print('[AlbumDownload] File too small for ${song.title}: $fileSize bytes');
            print('[AlbumDownload] Content: $content');
            await file.delete();
            continue;
          }

          // Mark song as cached in songs table
          await DatabaseHelper.updateSongCacheStatus(song.id, true, cachedPath: filePath);

          if (kDebugMode) {
            print('[AlbumDownload] ✓ Completed: "${song.title}" (${_formatBytes(fileSize)})');
          }

          completedSongs++;
          task.currentSongIndex = i + 1;
          task.progress = ((completedSongs / task.songs.length) * 100).round();
          _debouncedProgressUpdate(task.id, task);

          // Check if paused after completing a song
          if (task.status == AlbumDownloadStatus.paused) {
            task.currentSongIndex = i + 1; // Save position for resume
            return;
          }

        } catch (e) {
          print('Error downloading song ${song.title}: $e');
          // Continue with next song
        }
      }

      // Note: Individual songs are marked as cached immediately after download in onDone

      // Mark album as cached
      await DatabaseHelper.updateAlbumCacheStatus(task.albumId, true, cacheSize: totalSize);

      // Mark download as complete
      task.status = AlbumDownloadStatus.completed;
      task.progress = 100;
      task.currentSongIndex = task.songs.length; // Mark all songs as completed
      await DatabaseHelper.updateAlbumDownloadStatus(task.id, 'completed');

      // Cancel any pending debounced update and emit completion immediately
      _progressTimers[task.id]?.cancel();
      _progressTimers.remove(task.id);
      _downloadsController.add(task.toProgress());

    } catch (e) {
      print('Error downloading album: $e');

      // Mark as failed
      task.status = AlbumDownloadStatus.failed;
      task.error = e.toString();
      await DatabaseHelper.updateAlbumDownloadStatus(task.id, 'failed', error: e.toString());
      _downloadsController.add(task.toProgress());
    } finally {
      if (task.status != AlbumDownloadStatus.paused) {
        _activeDownloads.remove(task.id);
      }
    }
  }

  Future<String> _getCacheDirectory() async {
    Directory cacheDir;

    if (Platform.isLinux) {
      // Use XDG cache directory
      final cacheHome = Platform.environment['XDG_CACHE_HOME'] ??
                       path.join(Platform.environment['HOME'] ?? '', '.cache');
      cacheDir = Directory(path.join(cacheHome, 'nhac', 'audio_cache'));
    } else if (Platform.isMacOS) {
      // Use ~/Library/Caches on macOS
      final home = Platform.environment['HOME'] ?? '';
      cacheDir = Directory(path.join(home, 'Library', 'Caches', 'nhac', 'audio_cache'));
    } else if (Platform.isWindows) {
      // Use %LOCALAPPDATA% on Windows
      final localAppData = Platform.environment['LOCALAPPDATA'] ??
                          path.join(Platform.environment['USERPROFILE'] ?? '', 'AppData', 'Local');
      cacheDir = Directory(path.join(localAppData, 'nhac', 'audio_cache'));
    } else {
      // Mobile platforms - use application documents
      final appDir = await getApplicationDocumentsDirectory();
      cacheDir = Directory(path.join(appDir.path, 'nhac', 'audio_cache'));
    }

    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }

    return cacheDir.path;
  }

  String _generateDownloadId() {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// Download a file using http package with streaming response
  Future<bool> _downloadFile(String url, String filePath) async {
    IOSink? sink;

    try {
      final request = http.Request('GET', Uri.parse(url));
      request.headers['Accept'] = '*/*';
      request.headers['User-Agent'] = 'nhac/1.0';

      final client = http.Client();
      final streamedResponse = await client.send(request);

      if (streamedResponse.statusCode != 200) {
        print('[AlbumDownload] HTTP ${streamedResponse.statusCode}');
        // Try to read error body
        final errorBody = await streamedResponse.stream.bytesToString();
        print('[AlbumDownload] Error response: $errorBody');
        client.close();
        return false;
      }

      final contentLength = streamedResponse.contentLength ?? -1;
      if (kDebugMode) {
        print('[AlbumDownload] Content-Length: $contentLength');
      }

      // Stream to file
      final file = File(filePath);
      sink = file.openWrite();

      await streamedResponse.stream.pipe(sink);
      await sink.flush();

      client.close();
      return true;
    } catch (e) {
      print('[AlbumDownload] Download error: $e');
      // Clean up partial file
      try {
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
      return false;
    } finally {
      await sink?.close();
    }
  }

  Future<void> pauseDownload(String downloadId) async {
    if (kDebugMode) {
      print('[AlbumDownload] pauseDownload called with id: $downloadId');
      print('[AlbumDownload] Active downloads: ${_activeDownloads.keys.toList()}');
    }
    final task = _activeDownloads[downloadId];
    if (task != null && task.status == AlbumDownloadStatus.downloading) {
      task.status = AlbumDownloadStatus.paused;
      await DatabaseHelper.updateAlbumDownloadStatus(downloadId, 'paused');
      _downloadsController.add(task.toProgress());
      if (kDebugMode) {
        print('[AlbumDownload] Download paused');
      }
    } else {
      if (kDebugMode) {
        print('[AlbumDownload] Could not pause - task: ${task != null}, status: ${task?.status}');
      }
    }
  }

  Future<void> resumeDownload(String downloadId) async {
    final task = _activeDownloads[downloadId];
    if (task != null && task.status == AlbumDownloadStatus.paused) {
      task.status = AlbumDownloadStatus.downloading;
      await DatabaseHelper.updateAlbumDownloadStatus(downloadId, 'downloading');
      _downloadsController.add(task.toProgress());
      // Resume processing from where we left off
      _processDownload(task);
    }
  }

  Future<void> cancelDownload(String downloadId) async {
    if (kDebugMode) {
      print('[AlbumDownload] cancelDownload called with id: $downloadId');
      print('[AlbumDownload] Active downloads: ${_activeDownloads.keys.toList()}');
    }
    final task = _activeDownloads[downloadId];
    if (task != null) {
      task.status = AlbumDownloadStatus.cancelled;
      await DatabaseHelper.updateAlbumDownloadStatus(downloadId, 'cancelled');
      _activeDownloads.remove(downloadId);

      // Clean up ALL downloads (remove cached files) BEFORE emitting progress
      await _cleanupDownloads(task, removeAll: true);

      // Now emit progress so UI refreshes with correct state
      _downloadsController.add(task.toProgress());

      if (kDebugMode) {
        print('[AlbumDownload] Download cancelled');
      }
    } else {
      if (kDebugMode) {
        print('[AlbumDownload] Could not cancel - task not found');
      }
    }
  }

  Future<void> _cleanupDownloads(AlbumDownloadTask task, {bool removeAll = true}) async {
    // Clean up all downloaded songs for this album when cancelled
    for (final song in task.songs) {
      try {
        // Check if song has a cached file
        final songCacheInfo = await DatabaseHelper.getSongCacheInfo(song.id);
        if (songCacheInfo != null && songCacheInfo['cached_path'] != null) {
          final cachedPath = songCacheInfo['cached_path'] as String;
          final file = File(cachedPath);

          if (await file.exists()) {
            if (removeAll) {
              // Remove all downloaded files when cancelled
              await file.delete();
              await DatabaseHelper.updateSongCacheStatus(song.id, false, cachedPath: null);
              if (kDebugMode) {
                print('[AlbumDownload] Removed cached file for: ${song.title}');
              }
            } else {
              // Only remove partial downloads (< 1000 bytes)
              final size = await file.length();
              if (size < 1000) {
                await file.delete();
                await DatabaseHelper.updateSongCacheStatus(song.id, false, cachedPath: null);
              }
            }
          } else {
            // File doesn't exist - clear cache entry
            await DatabaseHelper.updateSongCacheStatus(song.id, false, cachedPath: null);
          }
        }
      } catch (e) {
        print('Error cleaning up download for ${song.title}: $e');
      }
    }

    // Also update album cache status
    await DatabaseHelper.updateAlbumCacheStatus(task.albumId, false, cacheSize: 0);
  }

  Future<List<AlbumDownloadProgress>> getActiveDownloads() async {
    final downloads = await DatabaseHelper.getActiveAlbumDownloads();
    return downloads.map((row) => AlbumDownloadProgress.fromMap(row)).toList();
  }

  Future<AlbumDownloadProgress?> getAlbumDownload(String albumId) async {
    // First check active in-memory downloads (more accurate for in-progress)
    final activeDownload = _activeDownloads.values
        .where((task) => task.albumId == albumId)
        .firstOrNull;
    if (activeDownload != null) {
      return activeDownload.toProgress();
    }

    // Fall back to database for completed/paused downloads
    final download = await DatabaseHelper.getAlbumDownload(albumId);
    return download != null ? AlbumDownloadProgress.fromMap(download) : null;
  }

  void _debouncedProgressUpdate(String downloadId, AlbumDownloadTask task) {
    // Cancel any existing timer for this download
    _progressTimers[downloadId]?.cancel();

    // Create a new timer to debounce the update
    _progressTimers[downloadId] = Timer(const Duration(milliseconds: 500), () {
      _downloadsController.add(task.toProgress());
      _progressTimers.remove(downloadId);
    });
  }

  void dispose() {
    // Cancel all timers
    for (final timer in _progressTimers.values) {
      timer.cancel();
    }
    _progressTimers.clear();
    _downloadsController.close();
  }
}

enum AlbumDownloadStatus {
  pending,
  downloading,
  paused,
  completed,
  failed,
  cancelled,
}

class AlbumDownloadTask {
  final String id;
  final String albumId;
  final Album album;
  final List<Song> songs;
  AlbumDownloadStatus status;
  int progress;
  final DateTime createdAt;
  String? error;
  int currentSongIndex = 0;

  AlbumDownloadTask({
    required this.id,
    required this.albumId,
    required this.album,
    required this.songs,
    required this.status,
    required this.progress,
    required this.createdAt,
    this.error,
    this.currentSongIndex = 0,
  });

  AlbumDownloadProgress toProgress() {
    return AlbumDownloadProgress(
      id: id,
      albumId: albumId,
      albumName: album.name,
      status: status,
      progress: progress,
      error: error,
    );
  }
}

class AlbumDownloadProgress {
  final String id;
  final String albumId;
  final String albumName;
  final AlbumDownloadStatus status;
  final int progress;
  final String? error;

  AlbumDownloadProgress({
    required this.id,
    required this.albumId,
    required this.albumName,
    required this.status,
    required this.progress,
    this.error,
  });

  factory AlbumDownloadProgress.fromMap(Map<String, dynamic> map) {
    return AlbumDownloadProgress(
      id: map['id'] as String,
      albumId: map['album_id'] as String,
      albumName: '', // Would need to join with albums table
      status: _parseStatus(map['status'] as String),
      progress: map['progress'] as int,
      error: map['error'] as String?,
    );
  }

  static AlbumDownloadStatus _parseStatus(String status) {
    switch (status) {
      case 'pending':
        return AlbumDownloadStatus.pending;
      case 'downloading':
        return AlbumDownloadStatus.downloading;
      case 'paused':
        return AlbumDownloadStatus.paused;
      case 'completed':
        return AlbumDownloadStatus.completed;
      case 'failed':
        return AlbumDownloadStatus.failed;
      case 'cancelled':
        return AlbumDownloadStatus.cancelled;
      default:
        return AlbumDownloadStatus.pending;
    }
  }
}