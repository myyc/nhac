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
  static const int _databaseVersion = 1;

  static Future<Database> get database async {
    if (_database != null) return _database!;
    
    // Initialize sqflite_ffi for desktop platforms
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    
    _database = await _initDatabase();
    return _database!;
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
    
    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
    );
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
        coverArt TEXT,
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
    final db = await database;
    final maps = await db.query('artists', orderBy: 'name');
    
    return maps.map((map) => Artist(
      id: map['id'] as String,
      name: map['name'] as String,
      albumCount: map['albumCount'] as int?,
    )).toList();
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

  static Future<List<Album>> getAlbums() async {
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
  }

  static Future<List<Album>> getAlbumsByArtist(String artistId) async {
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
          'coverArt': song.coverArt,
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
      orderBy: 'track, title',
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
      coverArt: map['coverArt'] as String?,
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
  }
}