import 'dart:async';
import 'package:flutter/foundation.dart';
import 'navidrome_api.dart';
import 'database_helper.dart';
import '../models/album.dart';

class LibraryScanService {
  final NavidromeApi api;
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
  
  // Start periodic scanning
  void _startPeriodicScanning({Duration? customInterval}) {
    _periodicScanTimer?.cancel();
    
    // Use custom interval or default
    final interval = customInterval ?? _normalScanInterval;
    
    if (kDebugMode) {
      print('[LibraryScan] Starting periodic scanning every ${interval.inMinutes} minutes');
    }
    
    _periodicScanTimer = Timer.periodic(interval, (_) {
      _performPeriodicScan();
    });
  }
  
  // Stop periodic scanning
  void stopPeriodicScanning() {
    _periodicScanTimer?.cancel();
    _periodicScanTimer = null;
    if (kDebugMode) print('[LibraryScan] Stopped periodic scanning');
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
    
    if (kDebugMode) print('[LibraryScan] Starting periodic scan');
    await startBackgroundScan();
  }
  
  // Start a background library scan on app startup
  Future<void> startBackgroundScan() async {
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
      if (kDebugMode) print('[LibraryScan] Starting library scan...');
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
      
      if (kDebugMode) {
        print('[LibraryScan] Captured state: $_lastAlbumCount albums, newest: $_lastNewestAlbumId');
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
        
        if (kDebugMode) {
          print('[LibraryScan] Status: scanning=$isScanning, count=${status['count']}');
        }
        
        if (!isScanning && _isScanning) {
          // Scan just completed
          if (kDebugMode) print('[LibraryScan] Scan completed, checking for changes...');
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
      
      // Check if the newest album has changed
      final currentNewestId = newestAlbums.first.id;
      bool hasNewAlbums = _lastNewestAlbumId != null && _lastNewestAlbumId != currentNewestId;
      
      // Count new albums since last check
      int newAlbumCount = 0;
      if (hasNewAlbums && _lastNewestAlbumId != null) {
        for (final album in newestAlbums) {
          if (album.id == _lastNewestAlbumId) break;
          newAlbumCount++;
        }
      }
      
      // Check total album count change
      final allAlbums = await api.getAlbumList2(
        type: 'alphabeticalByName', 
        size: 500
      );
      final currentAlbumCount = allAlbums.length;
      final albumCountDiff = (_lastAlbumCount != null) 
        ? currentAlbumCount - _lastAlbumCount! 
        : 0;
      
      if (kDebugMode) {
        print('[LibraryScan] Changes detected:');
        print('  - New albums: $newAlbumCount');
        print('  - Total album count change: $albumCountDiff');
        print('  - Newest album changed: $hasNewAlbums');
      }
      
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
        
        if (kDebugMode) {
          print('[LibraryScan] Library changes notified to listeners');
        }
      } else {
        if (kDebugMode) print('[LibraryScan] No changes detected in library');
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