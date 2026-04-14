import 'dart:async';
import 'package:flutter/foundation.dart';
import 'navidrome_api.dart';
import 'database_helper.dart';
import '../models/album.dart';
import '../providers/network_provider.dart';

class LibraryScanService {
  final NavidromeApi api;
  NetworkProvider? _networkProvider;
  Timer? _statusCheckTimer;
  Timer? _periodicScanTimer;
  bool _isScanning = false;
  DateTime? _lastScanTime;
  
  // Configurable scan intervals
  static const Duration _quickScanInterval = Duration(minutes: 5);  // When on WiFi
  static const Duration _normalScanInterval = Duration(minutes: 30); // Default interval
  static const Duration _minScanInterval = Duration(minutes: 2);     // Minimum time between scans
  
  // Stream controller for library change events
  final _libraryChangesController = StreamController<LibraryChangeEvent>.broadcast();
  Stream<LibraryChangeEvent> get libraryChanges => _libraryChangesController.stream;
  
  // Track library state for change detection
  int? _lastAlbumCount;
  String? _lastNewestAlbumId;
  List<String>? _lastAlbumIds;
  
  LibraryScanService({required this.api}) {
    // Start periodic scanning when service is created
    _startPeriodicScanning();
  }

  /// Set the network provider for offline checks
  void setNetworkProvider(NetworkProvider provider) {
    _networkProvider = provider;
  }

  /// Check if we can make network requests
  bool get _canMakeNetworkRequests {
    if (_networkProvider == null) return true;  // No provider, assume online
    return !_networkProvider!.isOffline && _networkProvider!.isServerReachable;
  }
  
  // Start periodic scanning
  void _startPeriodicScanning({Duration? customInterval}) {
    _periodicScanTimer?.cancel();
    
    // Use custom interval or default
    final interval = customInterval ?? _normalScanInterval;
    
    _periodicScanTimer = Timer.periodic(interval, (_) {
      _performPeriodicScan();
    });
  }
  
  // Stop periodic scanning
  void stopPeriodicScanning() {
    _periodicScanTimer?.cancel();
    _periodicScanTimer = null;
    _statusCheckTimer?.cancel();
    _statusCheckTimer = null;
  }

  // Resume periodic scanning (for battery optimization)
  void resumePeriodicScanning() {
    _startPeriodicScanning();
  }
  
  // Adjust scan interval based on network conditions
  void adjustScanInterval({required bool isOnWifi}) {
    if (isOnWifi) {
      // More frequent scans on WiFi
      _startPeriodicScanning(customInterval: _quickScanInterval);
    } else {
      // Less frequent scans on mobile data
      _startPeriodicScanning(customInterval: _normalScanInterval);
    }
  }
  
  // Perform a periodic scan if enough time has passed
  Future<void> _performPeriodicScan() async {
    // Don't scan when offline or server unreachable
    if (!_canMakeNetworkRequests) {
      if (kDebugMode) print('[LibraryScan] Skipping periodic scan - offline or server unreachable');
      return;
    }

    // Check if enough time has passed since last scan
    if (_lastScanTime != null) {
      final timeSinceLastScan = DateTime.now().difference(_lastScanTime!);
      if (timeSinceLastScan < _minScanInterval) {
        if (kDebugMode) {
          print('[LibraryScan] Skipping periodic scan - too soon since last scan');
        }
        return;
      }
    }

    // Don't start a new scan if one is already running
    if (_isScanning) {
      if (kDebugMode) print('[LibraryScan] Skipping periodic scan - scan already in progress');
      return;
    }

    await startBackgroundScan();
  }
  
  // Start a background library scan on app startup
  Future<void> startBackgroundScan() async {
    // Don't scan when offline or server unreachable
    if (!_canMakeNetworkRequests) {
      if (kDebugMode) print('[LibraryScan] Cannot start scan - offline or server unreachable');
      return;
    }

    if (_isScanning) {
      if (kDebugMode) print('[LibraryScan] Scan already in progress');
      return;
    }

    try {
      // Record scan time
      _lastScanTime = DateTime.now();
      
      // Capture current library state before scan
      await _captureLibraryState();
      
      // Start the scan
      await api.startScan();
      
      // Start monitoring scan status
      _isScanning = true;
      _monitorScanStatus();
      
    } catch (e) {
      if (kDebugMode) print('[LibraryScan] Error starting scan: $e');
      _isScanning = false;
    }
  }
  
  // Capture current library state for comparison
  Future<void> _captureLibraryState() async {
    try {
      // Get current album count from database
      final albums = await DatabaseHelper.getAlbums();
      _lastAlbumCount = albums.length;
      
      // Get newest album ID
      final newestAlbumId = await DatabaseHelper.getSyncMetadata('newest_album_id');
      _lastNewestAlbumId = newestAlbumId;
      
      // Store first 100 album IDs for comparison
      if (albums.isNotEmpty) {
        _lastAlbumIds = albums.take(100).map((a) => a.id).toList();
      }
      
    } catch (e) {
      if (kDebugMode) print('[LibraryScan] Error capturing library state: $e');
    }
  }
  
  // Monitor scan status and detect changes when complete
  void _monitorScanStatus() {
    _statusCheckTimer?.cancel();
    
    _statusCheckTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      try {
        final status = await api.getScanStatus();
        final isScanning = status['scanning'] as bool? ?? false;
        
        if (!isScanning && _isScanning) {
          // Scan just completed
          _isScanning = false;
          _statusCheckTimer?.cancel();
          
          // Wait a moment for the server to fully update
          await Future.delayed(const Duration(seconds: 2));
          
          // Check for changes
          await _detectAndNotifyChanges();
        }
        
        _isScanning = isScanning;
      } catch (e) {
        if (kDebugMode) print('[LibraryScan] Error checking scan status: $e');
        // Stop monitoring on error
        _statusCheckTimer?.cancel();
        _isScanning = false;
      }
    });
  }
  
  // Detect library changes and notify listeners
  Future<void> _detectAndNotifyChanges() async {
    try {
      // Fetch latest albums to check for changes
      final newestAlbums = await api.getAlbumList2(type: 'newest', size: 50);
      
      if (newestAlbums.isEmpty) {
        if (kDebugMode) print('[LibraryScan] No albums found after scan');
        return;
      }
      
      // Count new albums by walking the list until we hit the previously-known
      // newest. If we don't find it (album removed/reordered, or no prior state),
      // we can't infer "N new albums" — bail out instead of falsely reporting all 50.
      final currentNewestId = newestAlbums.first.id;
      int newAlbumCount = 0;
      bool hasNewAlbums = false;
      if (_lastNewestAlbumId != null && _lastNewestAlbumId != currentNewestId) {
        for (final album in newestAlbums) {
          if (album.id == _lastNewestAlbumId) {
            hasNewAlbums = true;
            break;
          }
          newAlbumCount++;
        }
        if (!hasNewAlbums) {
          // Stale reference — don't treat the entire window as new.
          newAlbumCount = 0;
        }
      }

      // Check total album count change. getAlbumList2 caps at 500 per page, so
      // a library larger than 500 will produce a misleading negative diff. Only
      // trust the diff when both sides were below the cap.
      final allAlbums = await api.getAlbumList2(
        type: 'alphabeticalByName',
        size: 500,
      );
      final currentAlbumCount = allAlbums.length;
      final bothBelowCap = currentAlbumCount < 500 &&
          _lastAlbumCount != null &&
          _lastAlbumCount! < 500;
      final albumCountDiff = bothBelowCap
          ? currentAlbumCount - _lastAlbumCount!
          : 0;

      // Update cached albums in database
      if (hasNewAlbums || albumCountDiff > 0) {
        // Update database with new albums
        await DatabaseHelper.insertAlbums(newestAlbums);
        if (allAlbums.isNotEmpty) {
          await DatabaseHelper.insertAlbums(allAlbums);
        }
        
        // Update metadata
        await DatabaseHelper.setSyncMetadata(
          'newest_album_id',
          currentNewestId,
        );
        await DatabaseHelper.setSyncMetadata(
          'last_scan',
          DateTime.now().toIso8601String(),
        );
        
        // Notify listeners about changes
        _libraryChangesController.add(LibraryChangeEvent(
          hasNewAlbums: hasNewAlbums,
          newAlbumCount: newAlbumCount,
          totalAlbumCountChange: albumCountDiff,
          newestAlbums: newestAlbums.take(10).toList(),
        ));
        
      }
      
      // Update state for next comparison
      _lastAlbumCount = currentAlbumCount;
      _lastNewestAlbumId = currentNewestId;
      _lastAlbumIds = allAlbums.take(100).map((a) => a.id).toList();
      
    } catch (e) {
      if (kDebugMode) print('[LibraryScan] Error detecting changes: $e');
    }
  }
  
  // Manual refresh check (can be called by user)
  Future<void> checkForUpdates() async {
    if (_isScanning) {
      if (kDebugMode) print('[LibraryScan] Scan already in progress');
      return;
    }
    
    await startBackgroundScan();
  }
  
  void dispose() {
    _statusCheckTimer?.cancel();
    _periodicScanTimer?.cancel();
    _libraryChangesController.close();
  }
}

// Event class for library changes
class LibraryChangeEvent {
  final bool hasNewAlbums;
  final int newAlbumCount;
  final int totalAlbumCountChange;
  final List<Album> newestAlbums;
  
  LibraryChangeEvent({
    required this.hasNewAlbums,
    required this.newAlbumCount,
    required this.totalAlbumCountChange,
    required this.newestAlbums,
  });
  
  bool get hasChanges => hasNewAlbums || totalAlbumCountChange != 0;
}