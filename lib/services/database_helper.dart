import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
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
  static const int _databaseVersion = 8;
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

      // Check if this is a corruption, schema mismatch, or persistent lock error
      if (errorStr.contains('database is locked') ||
          errorStr.contains('corrupt') ||
          errorStr.contains('malformed') ||
          errorStr.contains('not a database') ||
          errorStr.contains('no such table') ||
          errorStr.contains('no such column') ||
          errorStr.contains('table') && errorStr.contains('already exists')) {

        print('[DatabaseHelper] Database error detected: $e');
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
        
        // WAL mode disabled due to persistence issues
        // Using DELETE mode for better reliability across restarts
        try {
          await db.rawQuery('PRAGMA journal_mode = DELETE');
          print('Journal mode set to: DELETE');
        } catch (e) {
          print('Warning: Could not set journal mode: $e');
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

    if (oldVersion < 5) {
      print('[DatabaseHelper] Upgrading database to version 5 - adding offline cache tracking');
      // Add offline availability tracking for songs only
      try {
        await db.execute('ALTER TABLE songs ADD COLUMN is_cached INTEGER DEFAULT 0');
        print('[DatabaseHelper] Added songs.is_cached column');
      } catch (e) {
        print('[DatabaseHelper] Column songs.is_cached already exists: $e');
      }

      try {
        await db.execute('ALTER TABLE songs ADD COLUMN cached_path TEXT');
        print('[DatabaseHelper] Added songs.cached_path column');
      } catch (e) {
        print('[DatabaseHelper] Column songs.cached_path already exists: $e');
      }

      // Add indexes for offline queries
      try {
        await db.execute('CREATE INDEX idx_songs_cached ON songs(is_cached)');
        print('[DatabaseHelper] Created idx_songs_cached index');
      } catch (e) {
        print('[DatabaseHelper] Index idx_songs_cached already exists: $e');
      }

      // Create download queue table for tracking download progress
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS download_queue (
            id TEXT PRIMARY KEY,
            song_id TEXT NOT NULL,
            status TEXT NOT NULL,
            progress INTEGER DEFAULT 0,
            total_size INTEGER,
            downloaded_size INTEGER,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            error TEXT,
            FOREIGN KEY (song_id) REFERENCES songs(id) ON DELETE CASCADE
          )
        ''');
        print('[DatabaseHelper] Created download_queue table');
      } catch (e) {
        print('[DatabaseHelper] Error creating download_queue table: $e');
      }

      try {
        await db.execute('CREATE INDEX idx_download_queue_status ON download_queue(status)');
        print('[DatabaseHelper] Created idx_download_queue_status index');
      } catch (e) {
        print('[DatabaseHelper] Index idx_download_queue_status already exists: $e');
      }

      try {
        await db.execute('CREATE INDEX idx_download_queue_song ON download_queue(song_id)');
        print('[DatabaseHelper] Created idx_download_queue_song index');
      } catch (e) {
        print('[DatabaseHelper] Index idx_download_queue_song already exists: $e');
      }

      print('[DatabaseHelper] Database upgrade to version 5 completed');
    }

    if (oldVersion < 6) {
      // Create FTS virtual tables for offline search
      await db.execute('''
        CREATE VIRTUAL TABLE IF NOT EXISTS songs_fts
        USING fts5(
          id,
          title,
          album,
          artist,
          albumId,
          artistId,
          content='songs',
          content_rowid='rowid'
        )
      ''');

      await db.execute('''
        CREATE VIRTUAL TABLE IF NOT EXISTS albums_fts
        USING fts5(
          id,
          name,
          artist,
          artistId,
          content='albums',
          content_rowid='rowid'
        )
      ''');

      await db.execute('''
        CREATE VIRTUAL TABLE IF NOT EXISTS artists_fts
        USING fts5(
          id,
          name,
          content='artists',
          content_rowid='rowid'
        )
      ''');

      // Create triggers to keep FTS tables in sync
      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS songs_fts_insert
        AFTER INSERT ON songs BEGIN
          INSERT INTO songs_fts(id, title, album, artist, albumId, artistId)
          VALUES (new.id, new.title, new.album, new.artist, new.albumId, new.artistId);
        END
      ''');

      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS songs_fts_delete
        AFTER DELETE ON songs BEGIN
          DELETE FROM songs_fts WHERE id = old.id;
        END
      ''');

      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS songs_fts_update
        AFTER UPDATE ON songs BEGIN
          DELETE FROM songs_fts WHERE id = old.id;
          INSERT INTO songs_fts(id, title, album, artist, albumId, artistId)
          VALUES (new.id, new.title, new.album, new.artist, new.albumId, new.artistId);
        END
      ''');

      // Similar triggers for albums
      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS albums_fts_insert
        AFTER INSERT ON albums BEGIN
          INSERT INTO albums_fts(id, name, artist, artistId)
          VALUES (new.id, new.name, new.artist, new.artistId);
        END
      ''');

      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS albums_fts_delete
        AFTER DELETE ON albums BEGIN
          DELETE FROM albums_fts WHERE id = old.id;
        END
      ''');

      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS albums_fts_update
        AFTER UPDATE ON albums BEGIN
          DELETE FROM albums_fts WHERE id = old.id;
          INSERT INTO albums_fts(id, name, artist, artistId)
          VALUES (new.id, new.name, new.artist, new.artistId);
        END
      ''');

      // And for artists
      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS artists_fts_insert
        AFTER INSERT ON artists BEGIN
          INSERT INTO artists_fts(id, name)
          VALUES (new.id, new.name);
        END
      ''');

      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS artists_fts_delete
        AFTER DELETE ON artists BEGIN
          DELETE FROM artists_fts WHERE id = old.id;
        END
      ''');

      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS artists_fts_update
        AFTER UPDATE ON artists BEGIN
          DELETE FROM artists_fts WHERE id = old.id;
          INSERT INTO artists_fts(id, name)
          VALUES (new.id, new.name);
        END
      ''');

      // Populate FTS tables with existing data
      await db.execute('INSERT INTO songs_fts(id, title, album, artist, albumId, artistId) SELECT id, title, album, artist, albumId, artistId FROM songs');
      await db.execute('INSERT INTO albums_fts(id, name, artist, artistId) SELECT id, name, artist, artistId FROM albums');
      await db.execute('INSERT INTO artists_fts(id, name) SELECT id, name FROM artists');
    }

    if (oldVersion < 7) {
      print('[DatabaseHelper] Upgrading database to version 7 - creating download_queue table');

      // Create download queue table for tracking download progress
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS download_queue (
            id TEXT PRIMARY KEY,
            song_id TEXT NOT NULL,
            status TEXT NOT NULL,
            progress INTEGER DEFAULT 0,
            total_size INTEGER,
            downloaded_size INTEGER,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            error TEXT,
            FOREIGN KEY (song_id) REFERENCES songs(id) ON DELETE CASCADE
          )
        ''');
        print('[DatabaseHelper] Created download_queue table');
      } catch (e) {
        print('[DatabaseHelper] Error creating download_queue table: $e');
      }

      // Create indexes
      try {
        await db.execute('CREATE INDEX IF NOT EXISTS idx_download_queue_status ON download_queue(status)');
        print('[DatabaseHelper] Created idx_download_queue_status index');
      } catch (e) {
        print('[DatabaseHelper] Index idx_download_queue_status already exists: $e');
      }

      try {
        await db.execute('CREATE INDEX IF NOT EXISTS idx_download_queue_song ON download_queue(song_id)');
        print('[DatabaseHelper] Created idx_download_queue_song index');
      } catch (e) {
        print('[DatabaseHelper] Index idx_download_queue_song already exists: $e');
      }
    }

    if (oldVersion < 8) {
      print('[DatabaseHelper] Upgrading database to version 8 - cleaning up stale audio cache entries');

      // Clean up audio_cache entries that don't have corresponding files
      try {
        final appDir = await getApplicationSupportDirectory();
        final downloadsDir = Directory(join(appDir.path, 'downloads'));

        // Get all audio cache entries
        final cacheEntries = await db.query('audio_cache');
        int cleanedCount = 0;

        for (final entry in cacheEntries) {
          final songId = entry['song_id'] as String;
          final format = entry['format'] as String;
          final oldPath = entry['file_path'] as String;

          // Check if file exists at old location
          final oldFile = File(oldPath);
          if (!await oldFile.exists()) {
            // Try to find file in new downloads directory
            final extension = format == 'mp3' ? 'mp3' : 'audio';
            final newPath = join(downloadsDir.path, '$songId.$extension');
            final newFile = File(newPath);

            if (await newFile.exists()) {
              // Update path in database
              await db.update(
                'audio_cache',
                {'file_path': newPath},
                where: 'song_id = ? AND format = ?',
                whereArgs: [songId, format],
              );
              print('[DatabaseHelper] Updated cache path for $songId');
            } else {
              // Remove entry if file doesn't exist anywhere
              await db.delete(
                'audio_cache',
                where: 'song_id = ? AND format = ?',
                whereArgs: [songId, format],
              );
              cleanedCount++;
            }
          }
        }

        print('[DatabaseHelper] Cleaned up $cleanedCount stale audio cache entries');
      } catch (e) {
        print('[DatabaseHelper] Error cleaning audio cache: $e');
      }
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
        is_cached INTEGER DEFAULT 0,
        cached_path TEXT,
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
    await db.execute('CREATE INDEX idx_songs_cached ON songs(is_cached)');

    // Create download queue table for tracking download progress
    await db.execute('''
      CREATE TABLE download_queue (
        id TEXT PRIMARY KEY,
        song_id TEXT NOT NULL,
        status TEXT NOT NULL,
        progress INTEGER DEFAULT 0,
        total_size INTEGER,
        downloaded_size INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        error TEXT,
        FOREIGN KEY (song_id) REFERENCES songs(id) ON DELETE CASCADE
      )
    ''');

    // Create download queue indexes
    await db.execute('CREATE INDEX idx_download_queue_status ON download_queue(status)');
    await db.execute('CREATE INDEX idx_download_queue_song ON download_queue(song_id)');

    // Create album download table for tracking album-level downloads
    await db.execute('''
      CREATE TABLE album_downloads (
        id TEXT PRIMARY KEY,
        album_id TEXT NOT NULL,
        status TEXT NOT NULL,
        progress INTEGER DEFAULT 0,
        total_songs INTEGER,
        downloaded_songs INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        error TEXT,
        FOREIGN KEY (album_id) REFERENCES albums(id) ON DELETE CASCADE
      )
    ''');

    // Create album download indexes
    await db.execute('CREATE INDEX idx_album_downloads_album_id ON album_downloads(album_id)');
    await db.execute('CREATE INDEX idx_album_downloads_status ON album_downloads(status)');
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

    // First, get existing cache status to preserve it
    final existingSongs = await db.query(
      'songs',
      where: 'id IN (${List.filled(songs.length, '?').join(',')})',
      whereArgs: songs.map((s) => s.id).toList(),
      columns: ['id', 'is_cached', 'cached_path'],
    );

    final cacheStatus = <String, Map<String, dynamic>>{};
    for (final row in existingSongs) {
      cacheStatus[row['id'] as String] = {
        'is_cached': row['is_cached'],
        'cached_path': row['cached_path'],
      };
    }

    for (final song in songs) {
      final cachedInfo = cacheStatus[song.id];

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
          // Preserve cache status
          'is_cached': cachedInfo?['is_cached'] ?? 0,
          'cached_path': cachedInfo?['cached_path'],
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
      isCached: (map['is_cached'] as int?) == 1,
      cachedPath: map['cached_path'] as String?,
    )).toList();
  }

  static Future<Song?> getSongById(String songId) async {
    final db = await database;
    final maps = await db.query(
      'songs',
      where: 'id = ?',
      whereArgs: [songId],
      limit: 1,
    );

    if (maps.isEmpty) return null;

    final map = maps.first;
    return Song(
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
      isCached: (map['is_cached'] as int?) == 1,
      cachedPath: map['cached_path'] as String?,
    );
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

  /// Get any cached cover art for a given coverArtId (finds any size variant)
  static Future<String?> getAnyCachedCoverArt(String coverArtId) async {
    final db = await database;
    // Look for any cache entry starting with the coverArtId (keys are "${coverArtId}_${size}")
    final maps = await db.query(
      'cover_art_cache',
      where: 'id LIKE ?',
      whereArgs: ['${coverArtId}_%'],
      orderBy: 'size DESC', // Prefer larger sizes
      limit: 1,
    );

    if (maps.isEmpty) return null;

    final localPath = maps.first['localPath'] as String?;
    if (localPath != null && await File(localPath).exists()) {
      return localPath;
    }
    return null;
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
    await db.delete('download_queue');
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

    if (kDebugMode) print('[DatabaseHelper] Inserting audio cache for song: $songId, format: $format');

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

    if (kDebugMode) print('[DatabaseHelper] Audio cache inserted successfully');
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
    if (kDebugMode) {
      print('[DatabaseHelper] WARNING: clearAudioCache called - this will delete all audio cache entries!');
      print('[DatabaseHelper] Stack trace: ${StackTrace.current}');
    }
    final db = await database;
    final rowsDeleted = await db.delete('audio_cache');
    if (kDebugMode) print('[DatabaseHelper] Deleted $rowsDeleted audio cache entries');
  }

  static Future<void> clearAllSongCacheStatus() async {
    if (kDebugMode) print('[DatabaseHelper] WARNING: clearAllSongCacheStatus called - this will reset all song cache status!');
    final db = await database;
    final rowsAffected = await db.update(
      'songs',
      {'is_cached': 0},
      where: 'is_cached = ?',
      whereArgs: [1],
    );
    if (kDebugMode) print('[DatabaseHelper] Reset cache status for $rowsAffected songs');
  }

  // Offline cache management methods

  static Future<void> updateSongCacheStatus(String songId, bool isCached, {String? cachedPath}) async {
    print('[DatabaseHelper] Updating song cache status - SongID: $songId, IsCached: $isCached, CachedPath: $cachedPath');
    final db = await database;
    final result = await db.update(
      'songs',
      {
        'is_cached': isCached ? 1 : 0,
        'cached_path': cachedPath,
      },
      where: 'id = ?',
      whereArgs: [songId],
    );
    print('[DatabaseHelper] Song update completed - Rows affected: $result');
  }

  
  static Future<bool> isSongCached(String songId) async {
    final db = await database;
    final result = await db.query(
      'songs',
      columns: ['is_cached'],
      where: 'id = ?',
      whereArgs: [songId],
    );

    if (result.isEmpty) return false;
    return (result.first['is_cached'] as int) == 1;
  }

  static Future<Map<String, dynamic>?> getSongCacheInfo(String songId) async {
    final db = await database;
    final result = await db.query(
      'songs',
      columns: ['is_cached', 'cached_path'],
      where: 'id = ?',
      whereArgs: [songId],
    );

    if (result.isEmpty) return null;
    return result.first;
  }

  
  static Future<List<Map<String, dynamic>>> getCachedSongs({String? albumId}) async {
    final db = await database;

    String where = 'is_cached = 1';
    List<dynamic> whereArgs = [];

    if (albumId != null) {
      where += ' AND albumId = ?';
      whereArgs.add(albumId);
    }

    return await db.query(
      'songs',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'track ASC, discNumber ASC',
    );
  }

  // Download queue tracking methods
  static Future<void> insertDownloadQueueItem({
    required String id,
    required String songId,
    required String status,
    int? totalSize,
    int? downloadedSize,
    String? error,
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.insert(
      'download_queue',
      {
        'id': id,
        'song_id': songId,
        'status': status,
        'total_size': totalSize,
        'downloaded_size': downloadedSize,
        'created_at': now,
        'updated_at': now,
        'error': error,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> updateDownloadQueueProgress(String id, int progress, {int? downloadedSize}) async {
    final db = await database;

    await db.update(
      'download_queue',
      {
        'progress': progress,
        'downloaded_size': downloadedSize,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> updateDownloadQueueStatus(String id, String status, {String? error}) async {
    final db = await database;

    await db.update(
      'download_queue',
      {
        'status': status,
        'error': error,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<List<Map<String, dynamic>>> getActiveDownloads() async {
    final db = await database;

    return await db.query(
      'download_queue',
      where: 'status IN (?, ?)',
      whereArgs: ['pending', 'downloading'],
      orderBy: 'created_at ASC',
    );
  }

  // Album download operations
  static Future<void> insertAlbumDownload({
    required String id,
    required String albumId,
    required String status,
    int? totalSize,
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.insert(
      'album_downloads',
      {
        'id': id,
        'album_id': albumId,
        'status': status,
        'progress': 0,
        'total_songs': totalSize,
        'downloaded_songs': 0,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> updateAlbumDownloadStatus(String id, String status, {String? error}) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.update(
      'album_downloads',
      {
        'status': status,
        'updated_at': now,
        if (error != null) 'error': error,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> updateAlbumDownloadProgress(String id, int progress, {int? downloadedSongs}) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.update(
      'album_downloads',
      {
        'progress': progress,
        'updated_at': now,
        if (downloadedSongs != null) 'downloaded_songs': downloadedSongs,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<Map<String, dynamic>?> getAlbumDownload(String albumId) async {
    final db = await database;
    // Exclude cancelled downloads - they are effectively "no download"
    final result = await db.query(
      'album_downloads',
      where: 'album_id = ? AND status != ?',
      whereArgs: [albumId, 'cancelled'],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    return result.isNotEmpty ? result.first : null;
  }

  static Future<List<Map<String, dynamic>>> getActiveAlbumDownloads() async {
    final db = await database;

    return await db.query(
      'album_downloads',
      where: 'status IN (?, ?)',
      whereArgs: ['pending', 'downloading'],
      orderBy: 'created_at ASC',
    );
  }

  static Future<void> deleteAlbumDownload(String id) async {
    final db = await database;
    await db.delete(
      'album_downloads',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> updateAlbumCacheStatus(String albumId, bool isCached, {int? cacheSize}) async {
    final db = await database;

    // This would require an albums table with cache status
    // For now, we'll track this through album_downloads table
    if (isCached) {
      // Mark any active downloads as completed
      await db.update(
        'album_downloads',
        {
          'status': 'completed',
          'progress': 100,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'album_id = ? AND status IN (?, ?)',
        whereArgs: [albumId, 'pending', 'downloading'],
      );
    } else {
      // Remove completed status if album is no longer cached
      await db.update(
        'album_downloads',
        {
          'status': 'cancelled',
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'album_id = ? AND status = ?',
        whereArgs: [albumId, 'completed'],
      );
    }
  }

  /// Get all album IDs that have been fully downloaded (available offline)
  static Future<Set<String>> getCachedAlbumIds() async {
    final db = await database;
    final results = await db.query(
      'album_downloads',
      columns: ['album_id'],
      where: 'status = ?',
      whereArgs: ['completed'],
    );
    return results.map((row) => row['album_id'] as String).toSet();
  }

  /// Get cached albums sorted by play count (for "Popular Offline" section)
  static Future<List<Album>> getPopularOfflineAlbums({int limit = 18}) async {
    final db = await database;
    // Get completed album downloads, ordered by album name
    final results = await db.rawQuery('''
      SELECT a.* FROM albums a
      INNER JOIN album_downloads ad ON a.id = ad.album_id
      WHERE ad.status = 'completed'
      ORDER BY a.name ASC
      LIMIT ?
    ''', [limit]);
    return results.map((map) => Album(
      id: map['id'] as String,
      name: map['name'] as String,
      artist: map['artist'] as String?,
      artistId: map['artistId'] as String?,
      year: map['year'] as int?,
      coverArt: map['coverArt'] as String?,
      songCount: map['songCount'] as int?,
      duration: map['duration'] as int?,
    )).toList();
  }

  static Future<void> deleteDownloadQueueItem(String id) async {
    final db = await database;
    await db.delete(
      'download_queue',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> clearCompletedDownloads() async {
    final db = await database;
    await db.delete(
      'download_queue',
      where: 'status IN (?, ?)',
      whereArgs: ['completed', 'failed'],
    );
  }

  // FTS search methods for offline functionality
  static Future<List<Map<String, dynamic>>> searchSongsFTS(String query) async {
    final db = await database;

    // Use FTS to search only in cached songs
    final results = await db.rawQuery('''
      SELECT s.* FROM songs_fts sf
      JOIN songs s ON sf.id = s.id
      WHERE s.is_cached = 1 AND songs_fts MATCH ?
      ORDER BY bm25(songs_fts)
    ''', [query]);

    return results;
  }

  static Future<List<Map<String, dynamic>>> searchAlbumsFTS(String query) async {
    final db = await database;

    final results = await db.rawQuery('''
      SELECT a.* FROM albums_fts af
      JOIN albums a ON af.id = a.id
      WHERE albums_fts MATCH ?
      ORDER BY bm25(albums_fts)
    ''', [query]);

    return results;
  }

  static Future<List<Map<String, dynamic>>> searchArtistsFTS(String query) async {
    final db = await database;

    final results = await db.rawQuery('''
      SELECT a.* FROM artists_fts af
      JOIN artists a ON af.id = a.id
      WHERE artists_fts MATCH ?
      ORDER BY bm25(artists_fts)
    ''', [query]);

    return results;
  }

  static Future<Map<String, List<Map<String, dynamic>>>> searchAllFTS(String query) async {
    final db = await database;

    // Search in all FTS tables, but only return cached items for songs/albums
    final songs = await db.rawQuery('''
      SELECT s.* FROM songs_fts sf
      JOIN songs s ON sf.id = s.id
      WHERE s.is_cached = 1 AND songs_fts MATCH ?
      ORDER BY bm25(songs_fts)
      LIMIT 50
    ''', [query]);

    final albums = await db.rawQuery('''
      SELECT a.* FROM albums_fts af
      JOIN albums a ON af.id = a.id
      WHERE albums_fts MATCH ?
      ORDER BY bm25(albums_fts)
      LIMIT 50
    ''', [query]);

    final artists = await db.rawQuery('''
      SELECT a.* FROM artists_fts af
      JOIN artists a ON af.id = a.id
      WHERE artists_fts MATCH ?
      ORDER BY bm25(artists_fts)
      LIMIT 50
    ''', [query]);

    return {
      'songs': songs,
      'albums': albums,
      'artists': artists,
    };
  }

  // Method to rebuild FTS indexes (useful if they get out of sync)
  static Future<void> rebuildFTSIndexes() async {
    final db = await database;

    // Delete and recreate FTS tables
    await db.execute('DROP TABLE IF EXISTS songs_fts');
    await db.execute('DROP TABLE IF EXISTS albums_fts');
    await db.execute('DROP TABLE IF EXISTS artists_fts');

    // Recreate with the same structure
    await db.execute('''
      CREATE VIRTUAL TABLE songs_fts
      USING fts5(
        id,
        title,
        album,
        artist,
        albumId,
        artistId,
        content='songs',
        content_rowid='rowid'
      )
    ''');

    await db.execute('''
      CREATE VIRTUAL TABLE albums_fts
      USING fts5(
        id,
        name,
        artist,
        artistId,
        content='albums',
        content_rowid='rowid'
      )
    ''');

    await db.execute('''
      CREATE VIRTUAL TABLE artists_fts
      USING fts5(
        id,
        name,
        content='artists',
        content_rowid='rowid'
      )
    ''');

    // Repopulate with current data
    await db.execute('INSERT INTO songs_fts(id, title, album, artist, albumId, artistId) SELECT id, title, album, artist, albumId, artistId FROM songs');
    await db.execute('INSERT INTO albums_fts(id, name, artist, artistId) SELECT id, name, artist, artistId FROM albums');
    await db.execute('INSERT INTO artists_fts(id, name) SELECT id, name FROM artists');
  }
}