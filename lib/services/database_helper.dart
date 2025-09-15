import 'dart:async';
import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import '../models/artist.dart';
import '../models/album.dart';
import '../models/song.dart';

class DatabaseHelper {
  static Database? _database;
  static const String _databaseName = 'nhac_cache.db';
  static const int _databaseVersion = 4;
  static bool _isInitializing = false;
  static final _initCompleter = <String, Completer<Database>>{};

  static Future<Database> get database async {
    // If database is already open, return it
    if (_database != null && _database!.isOpen) {
      return _database!;
    }
    
    // If already initializing, wait for the existing initialization
    if (_isInitializing) {
      final completer = _initCompleter['main'] ??= Completer<Database>();
      return await completer.future;
    }
    
    // Start initialization
    _isInitializing = true;
    _initCompleter['main'] = Completer<Database>();
    
    try {
      // Initialize sqflite_ffi for desktop platforms
      if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
      }
      
      _database = await _initDatabase();
      _initCompleter['main']!.complete(_database!);
      return _database!;
    } catch (e) {
      final errorStr = e.toString().toLowerCase();
      
      // Check if this is a corruption or persistent lock error
      if (errorStr.contains('database is locked') ||
          errorStr.contains('corrupt') ||
          errorStr.contains('malformed') ||
          errorStr.contains('not a database')) {
        
        print('[DatabaseHelper] Database corruption detected: $e');
        print('[DatabaseHelper] Attempting automatic recovery...');
        
        // Reset the database
        await resetDatabase();
        
        // Try once more with a fresh database
        try {
          _database = await _initDatabase();
          _initCompleter['main']!.complete(_database!);
          print('[DatabaseHelper] Database recovery successful!');
          return _database!;
        } catch (retryError) {
          _initCompleter['main']!.completeError(retryError);
          rethrow;
        }
      } else {
        _initCompleter['main']!.completeError(e);
        rethrow;
      }
    } finally {
      _isInitializing = false;
      _initCompleter.remove('main');
    }
  }
  
  static Future<void> closeDatabase() async {
    if (_database != null && _database!.isOpen) {
      await _database!.close();
      _database = null;
    }
  }
  
  // Reset database - deletes and recreates the database
  static Future<void> resetDatabase() async {
    print('[DatabaseHelper] Resetting database due to corruption or persistent errors');
    
    // Close existing connection
    await closeDatabase();
    
    // Clear initialization state
    _isInitializing = false;
    _initCompleter.clear();
    
    // Get database path
    String dbPath;
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      final appDir = await getApplicationSupportDirectory();
      dbPath = join(appDir.path, _databaseName);
    } else {
      final documentsDirectory = await getApplicationDocumentsDirectory();
      dbPath = join(documentsDirectory.path, _databaseName);
    }
    
    // Delete all database files
    final filesToDelete = [
      dbPath,
      '$dbPath-journal',
      '$dbPath-wal',
      '$dbPath-shm',
    ];
    
    for (final filePath in filesToDelete) {
      try {
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
          print('[DatabaseHelper] Deleted: $filePath');
        }
      } catch (e) {
        print('[DatabaseHelper] Could not delete $filePath: $e');
      }
    }
    
    print('[DatabaseHelper] Database reset complete. Will recreate on next access.');
    print('[DatabaseHelper] Note: Cover art images preserved in covers/ directory');
  }
  
  // Retry logic for database operations with auto-reset on persistent failures
  static Future<T> _retryOperation<T>(
    Future<T> Function() operation, {
    int maxRetries = 3,
    Duration initialDelay = const Duration(milliseconds: 100),
    bool allowReset = true,
  }) async {
    int retryCount = 0;
    Duration delay = initialDelay;
    String? lastError;
    
    while (retryCount < maxRetries) {
      try {
        return await operation();
      } catch (e) {
        lastError = e.toString();
        final errorStr = lastError.toLowerCase();
        
        if ((errorStr.contains('database is locked') || 
             errorStr.contains('corrupt') ||
             errorStr.contains('malformed')) && 
            retryCount < maxRetries - 1) {
          retryCount++;
          print('[DatabaseHelper] Database error, retrying in ${delay.inMilliseconds}ms (attempt $retryCount/$maxRetries): $e');
          await Future.delayed(delay);
          delay *= 2; // Exponential backoff
        } else {
          // If this is the last retry and we're allowed to reset
          if (retryCount == maxRetries - 1 && allowReset && 
              (errorStr.contains('database is locked') || 
               errorStr.contains('corrupt') ||
               errorStr.contains('malformed'))) {
            print('[DatabaseHelper] Persistent database error after $maxRetries retries');
            print('[DatabaseHelper] Triggering database reset...');
            
            // Reset the database
            await resetDatabase();
            
            // For read operations, try to return empty data
            // The app will re-sync from server
            try {
              // Try casting empty list to T
              return [] as T;
            } catch (_) {
              // If it's not a list type, throw the error
              throw Exception('Database was reset due to persistent errors. Please retry.');
            }
          }
          rethrow;
        }
      }
    }
    
    print('[DatabaseHelper] Database operation failed after $maxRetries retries: $lastError');
    
    // If we still have persistent errors, reset the database
    if (allowReset) {
      print('[DatabaseHelper] Triggering final database reset...');
      await resetDatabase();
      
      // For read operations, try to return empty data
      try {
        // Try casting empty list to T
        return [] as T;
      } catch (_) {
        // If it's not a list type, throw the error
        throw Exception('Database operation failed after $maxRetries retries');
      }
    }
    
    throw Exception('Database operation failed after $maxRetries retries');
  }

  static Future<Database> _initDatabase() async {
    String path;
    
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      // For desktop platforms, use a local directory
      final appDir = await getApplicationSupportDirectory();
      await appDir.create(recursive: true);
      path = join(appDir.path, _databaseName);
    } else {
      // For mobile platforms, use documents directory
      final documentsDirectory = await getApplicationDocumentsDirectory();
      path = join(documentsDirectory.path, _databaseName);
    }
    
    // Clean up any stale journal files before opening
    final journalPath = '$path-journal';
    
    try {
      final journalFile = File(journalPath);
      if (await journalFile.exists()) {
        print('Cleaning up stale journal file...');
        await journalFile.delete();
      }
    } catch (e) {
      print('Warning: Could not clean up journal file: $e');
    }
    
    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      singleInstance: true,
      onOpen: (db) async {
        // Enable foreign keys
        await db.rawQuery('PRAGMA foreign_keys = ON');
        
        // Enable WAL mode for better concurrency
        // Note: This must be done in onOpen, not onConfigure
        try {
          final result = await db.rawQuery('PRAGMA journal_mode = WAL');
          print('Journal mode set to: $result');
        } catch (e) {
          print('Warning: Could not set WAL mode: $e');
        }
        
        // Set busy timeout to 10 seconds
        await db.rawQuery('PRAGMA busy_timeout = 10000');
        
        // Set synchronous to NORMAL for better performance
        await db.rawQuery('PRAGMA synchronous = NORMAL');
        
        // Optimize database
        await db.rawQuery('PRAGMA optimize');
      },
    );
  }

  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add audio_cache table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS audio_cache (
          id TEXT PRIMARY KEY,
          song_id TEXT NOT NULL,
          format TEXT NOT NULL,
          bitrate INTEGER,
          file_path TEXT NOT NULL,
          file_size INTEGER NOT NULL,
          last_played INTEGER,
          created_at INTEGER NOT NULL,
          FOREIGN KEY (song_id) REFERENCES songs(id) ON DELETE CASCADE
        )
      ''');
      
      // Add index for faster lookups
      await db.execute('CREATE INDEX idx_audio_cache_song_id ON audio_cache(song_id)');
      await db.execute('CREATE INDEX idx_audio_cache_last_played ON audio_cache(last_played)');
    }
    
    if (oldVersion < 3) {
      // Add disc fields to songs table
      await db.execute('ALTER TABLE songs ADD COLUMN discNumber INTEGER');
      await db.execute('ALTER TABLE songs ADD COLUMN discSubtitle TEXT');
    }
    
    if (oldVersion < 4) {
      // Add audio format and bitrate fields to songs table
      await db.execute('ALTER TABLE songs ADD COLUMN suffix TEXT');
      await db.execute('ALTER TABLE songs ADD COLUMN bitRate INTEGER');
    }
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE artists (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        albumCount INTEGER,
        lastSync INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE albums (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        artist TEXT,
        artistId TEXT,
        year INTEGER,
        coverArt TEXT,
        songCount INTEGER,
        duration INTEGER,
        lastSync INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE songs (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        album TEXT,
        albumId TEXT,
        artist TEXT,
        artistId TEXT,
        duration INTEGER,
        track INTEGER,
        discNumber INTEGER,
        discSubtitle TEXT,
        coverArt TEXT,
        suffix TEXT,
        bitRate INTEGER,
        lastSync INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE cover_art_cache (
        id TEXT PRIMARY KEY,
        url TEXT NOT NULL,
        localPath TEXT,
        size INTEGER,
        lastAccessed INTEGER NOT NULL
      )
    ''');
    
    await db.execute('''
      CREATE TABLE sync_metadata (
        key TEXT PRIMARY KEY,
        value TEXT,
        lastUpdated INTEGER NOT NULL
      )
    ''');
    
    // Audio cache table for storing downloaded audio files
    await db.execute('''
      CREATE TABLE audio_cache (
        id TEXT PRIMARY KEY,
        song_id TEXT NOT NULL,
        format TEXT NOT NULL,
        bitrate INTEGER,
        file_path TEXT NOT NULL,
        file_size INTEGER NOT NULL,
        last_played INTEGER,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (song_id) REFERENCES songs(id) ON DELETE CASCADE
      )
    ''');
    
    // Add indexes for performance
    await db.execute('CREATE INDEX idx_audio_cache_song_id ON audio_cache(song_id)');
    await db.execute('CREATE INDEX idx_audio_cache_last_played ON audio_cache(last_played)');
  }

  // Artist operations
  static Future<void> insertArtists(List<Artist> artists) async {
    final db = await database;
    final batch = db.batch();
    final now = DateTime.now().millisecondsSinceEpoch;
    
    for (final artist in artists) {
      batch.insert(
        'artists',
        {
          'id': artist.id,
          'name': artist.name,
          'albumCount': artist.albumCount,
          'lastSync': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    
    await batch.commit(noResult: true);
  }

  static Future<List<Artist>> getArtists() async {
    return _retryOperation(() async {
      final db = await database;
      final maps = await db.query('artists', orderBy: 'name');
      
      return maps.map((map) => Artist(
        id: map['id'] as String,
        name: map['name'] as String,
        albumCount: map['albumCount'] as int?,
      )).toList();
    });
  }

  // Album operations
  static Future<void> insertAlbums(List<Album> albums) async {
    final db = await database;
    final batch = db.batch();
    final now = DateTime.now().millisecondsSinceEpoch;
    
    for (final album in albums) {
      batch.insert(
        'albums',
        {
          'id': album.id,
          'name': album.name,
          'artist': album.artist,
          'artistId': album.artistId,
          'year': album.year,
          'coverArt': album.coverArt,
          'songCount': album.songCount,
          'duration': album.duration,
          'lastSync': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    
    await batch.commit(noResult: true);
  }

  static Future<int> getAlbumCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM albums');
    return Sqflite.firstIntValue(result) ?? 0;
  }
  
  static Future<List<Album>> getAlbums() async {
    return _retryOperation(() async {
      final db = await database;
      final maps = await db.query('albums', orderBy: 'artist, name');
      
      return maps.map((map) => Album(
        id: map['id'] as String,
        name: map['name'] as String,
        artist: map['artist'] as String?,
        artistId: map['artistId'] as String?,
        year: map['year'] as int?,
        coverArt: map['coverArt'] as String?,
        songCount: map['songCount'] as int?,
        duration: map['duration'] as int?,
      )).toList();
    });
  }

  static Future<List<Album>> getAlbumsByArtist(String artistId) async {
    return _retryOperation(() async {
      final db = await database;
      final maps = await db.query(
        'albums',
        where: 'artistId = ?',
        whereArgs: [artistId],
        orderBy: 'year DESC, name',
      );
      
      return maps.map((map) => Album(
        id: map['id'] as String,
        name: map['name'] as String,
        artist: map['artist'] as String?,
        artistId: map['artistId'] as String?,
        year: map['year'] as int?,
        coverArt: map['coverArt'] as String?,
        songCount: map['songCount'] as int?,
        duration: map['duration'] as int?,
      )).toList();
    });
  }

  // Song operations
  static Future<void> insertSongs(List<Song> songs) async {
    final db = await database;
    final batch = db.batch();
    final now = DateTime.now().millisecondsSinceEpoch;
    
    for (final song in songs) {
      batch.insert(
        'songs',
        {
          'id': song.id,
          'title': song.title,
          'album': song.album,
          'albumId': song.albumId,
          'artist': song.artist,
          'artistId': song.artistId,
          'duration': song.duration,
          'track': song.track,
          'discNumber': song.discNumber,
          'discSubtitle': song.discSubtitle,
          'coverArt': song.coverArt,
          'suffix': song.suffix,
          'bitRate': song.bitRate,
          'lastSync': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    
    await batch.commit(noResult: true);
  }

  static Future<List<Song>> getSongsByAlbum(String albumId) async {
    final db = await database;
    final maps = await db.query(
      'songs',
      where: 'albumId = ?',
      whereArgs: [albumId],
      orderBy: 'discNumber, track, title',
    );
    
    return maps.map((map) => Song(
      id: map['id'] as String,
      title: map['title'] as String,
      album: map['album'] as String?,
      albumId: map['albumId'] as String?,
      artist: map['artist'] as String?,
      artistId: map['artistId'] as String?,
      duration: map['duration'] as int?,
      track: map['track'] as int?,
      discNumber: map['discNumber'] as int?,
      discSubtitle: map['discSubtitle'] as String?,
      coverArt: map['coverArt'] as String?,
      suffix: map['suffix'] as String?,
      bitRate: map['bitRate'] as int?,
    )).toList();
  }

  // Sync metadata operations
  static Future<void> setSyncMetadata(String key, String value) async {
    final db = await database;
    await db.insert(
      'sync_metadata',
      {
        'key': key,
        'value': value,
        'lastUpdated': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<String?> getSyncMetadata(String key) async {
    final db = await database;
    final maps = await db.query(
      'sync_metadata',
      where: 'key = ?',
      whereArgs: [key],
    );
    
    if (maps.isEmpty) return null;
    return maps.first['value'] as String?;
  }

  static Future<bool> needsSync(String key, Duration maxAge) async {
    final db = await database;
    final maps = await db.query(
      'sync_metadata',
      where: 'key = ?',
      whereArgs: [key],
    );
    
    if (maps.isEmpty) return true;
    
    final lastUpdated = maps.first['lastUpdated'] as int;
    final lastUpdateTime = DateTime.fromMillisecondsSinceEpoch(lastUpdated);
    return DateTime.now().difference(lastUpdateTime) > maxAge;
  }

  // Cover art cache operations
  static Future<void> setCoverArtCache(String id, String url, String localPath, int size) async {
    final db = await database;
    await db.insert(
      'cover_art_cache',
      {
        'id': id,
        'url': url,
        'localPath': localPath,
        'size': size,
        'lastAccessed': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<String?> getCoverArtLocalPath(String id) async {
    final db = await database;
    final maps = await db.query(
      'cover_art_cache',
      where: 'id = ?',
      whereArgs: [id],
    );
    
    if (maps.isEmpty) return null;
    
    // Update last accessed time
    await db.update(
      'cover_art_cache',
      {'lastAccessed': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
    
    return maps.first['localPath'] as String?;
  }

  // Clean up old cache entries
  static Future<void> cleanupOldCache({int maxCacheSizeMB = 500}) async {
    final db = await database;
    
    // Get total cache size
    final result = await db.rawQuery('SELECT SUM(size) as total FROM cover_art_cache');
    final totalSize = (result.first['total'] as int?) ?? 0;
    final maxSizeBytes = maxCacheSizeMB * 1024 * 1024;
    
    if (totalSize > maxSizeBytes) {
      // Delete least recently accessed items
      final toDelete = await db.query(
        'cover_art_cache',
        orderBy: 'lastAccessed ASC',
        limit: 100,
      );
      
      for (final item in toDelete) {
        final localPath = item['localPath'] as String;
        final file = File(localPath);
        if (await file.exists()) {
          await file.delete();
        }
        
        await db.delete(
          'cover_art_cache',
          where: 'id = ?',
          whereArgs: [item['id']],
        );
      }
    }
  }

  static Future<void> clearAllCache() async {
    final db = await database;
    await db.delete('artists');
    await db.delete('albums');
    await db.delete('songs');
    await db.delete('cover_art_cache');
    await db.delete('sync_metadata');
    await db.delete('audio_cache');
  }
  
  // Audio cache operations
  static Future<void> insertAudioCache({
    required String songId,
    required String format,
    required String filePath,
    required int fileSize,
    int? bitrate,
  }) async {
    final db = await database;
    final id = '${songId}_$format';
    
    await db.insert(
      'audio_cache',
      {
        'id': id,
        'song_id': songId,
        'format': format,
        'bitrate': bitrate,
        'file_path': filePath,
        'file_size': fileSize,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
  
  static Future<String?> getAudioCachePath(String songId, String format) async {
    final db = await database;
    final id = '${songId}_$format';
    
    final result = await db.query(
      'audio_cache',
      columns: ['file_path'],
      where: 'id = ?',
      whereArgs: [id],
    );
    
    if (result.isNotEmpty) {
      return result.first['file_path'] as String;
    }
    return null;
  }
  
  static Future<String?> getAnyAudioCachePath(String songId) async {
    final db = await database;
    
    final result = await db.query(
      'audio_cache',
      columns: ['file_path'],
      where: 'song_id = ?',
      whereArgs: [songId],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    
    if (result.isNotEmpty) {
      return result.first['file_path'] as String;
    }
    return null;
  }
  
  static Future<void> updateAudioCacheLastPlayed(String songId) async {
    final db = await database;
    
    await db.update(
      'audio_cache',
      {'last_played': DateTime.now().millisecondsSinceEpoch},
      where: 'song_id = ?',
      whereArgs: [songId],
    );
  }
  
  static Future<int> getAudioCacheTotalSize() async {
    final db = await database;
    
    final result = await db.rawQuery(
      'SELECT SUM(file_size) as total FROM audio_cache'
    );
    
    if (result.isNotEmpty && result.first['total'] != null) {
      return result.first['total'] as int;
    }
    return 0;
  }
  
  static Future<int> getAudioCacheFileCount() async {
    final db = await database;
    
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM audio_cache'
    );
    
    return Sqflite.firstIntValue(result) ?? 0;
  }
  
  static Future<List<String>> getAllAudioCachePaths() async {
    final db = await database;
    
    final result = await db.query(
      'audio_cache',
      columns: ['file_path'],
    );
    
    return result.map((row) => row['file_path'] as String).toList();
  }
  
  static Future<void> cleanupAudioCacheLRU(int maxSizeBytes) async {
    final db = await database;
    
    // Get files ordered by last played (oldest first)
    final files = await db.query(
      'audio_cache',
      orderBy: 'last_played ASC NULLS FIRST, created_at ASC',
    );
    
    int totalSize = 0;
    final toDelete = <String>[];
    
    // Calculate what to keep
    for (int i = files.length - 1; i >= 0; i--) {
      final fileSize = files[i]['file_size'] as int;
      if (totalSize + fileSize <= maxSizeBytes) {
        totalSize += fileSize;
      } else {
        toDelete.add(files[i]['id'] as String);
      }
    }
    
    // Delete oldest files
    if (toDelete.isNotEmpty) {
      await db.delete(
        'audio_cache',
        where: 'id IN (${toDelete.map((_) => '?').join(',')})',
        whereArgs: toDelete,
      );
    }
  }
  
  static Future<List<String>> getDeletedAudioCachePaths() async {
    // This would track deleted entries, but for simplicity
    // we'll handle this differently in the service
    return [];
  }
  
  static Future<void> clearAudioCache() async {
    final db = await database;
    await db.delete('audio_cache');
  }
}