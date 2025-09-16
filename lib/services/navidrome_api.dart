import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../models/artist.dart';
import '../models/album.dart';
import '../models/song.dart';
import 'auth_service.dart' show LoginResult;

class NavidromeApi {
  final String baseUrl;
  final String username;
  final String password;
  final String clientName = 'nhac';
  final String apiVersion = '1.16.1';
  
  // Cache auth params for stable URLs
  String? _cachedSalt;
  String? _cachedToken;
  DateTime? _cacheTime;
  static const Duration _cacheExpiry = Duration(minutes: 30);

  NavidromeApi({
    required this.baseUrl,
    required this.username,
    required this.password,
  });

  String _generateSalt() {
    final random = Random.secure();
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(6, (index) => chars[random.nextInt(chars.length)])
        .join();
  }

  String _generateToken(String salt) {
    final bytes = utf8.encode(password + salt);
    return md5.convert(bytes).toString();
  }

  Map<String, String> _getAuthParams({bool forceNew = false}) {
    // Use cached auth params for stable URLs unless forced or expired
    final now = DateTime.now();
    if (!forceNew && 
        _cachedSalt != null && 
        _cachedToken != null && 
        _cacheTime != null &&
        now.difference(_cacheTime!) < _cacheExpiry) {
      return {
        'u': username,
        't': _cachedToken!,
        's': _cachedSalt!,
        'v': apiVersion,
        'c': clientName,
        'f': 'json',
      };
    }
    
    // Generate new auth params and cache them
    _cachedSalt = _generateSalt();
    _cachedToken = _generateToken(_cachedSalt!);
    _cacheTime = now;
    
    return {
      'u': username,
      't': _cachedToken!,
      's': _cachedSalt!,
      'v': apiVersion,
      'c': clientName,
      'f': 'json',
    };
  }

  Uri _buildUri(String endpoint, [Map<String, String>? additionalParams]) {
    final params = _getAuthParams();
    if (additionalParams != null) {
      params.addAll(additionalParams);
    }
    return Uri.parse('$baseUrl/rest/$endpoint').replace(queryParameters: params);
  }

  Future<Map<String, dynamic>> _request(String endpoint, [Map<String, String>? params]) async {
    final uri = _buildUri(endpoint, params);
    final response = await http.get(uri);

    if (response.statusCode != 200) {
      throw Exception('HTTP error: ${response.statusCode}');
    }

    final data = json.decode(response.body);
    final subsonicResponse = data['subsonic-response'];
    
    if (subsonicResponse['status'] != 'ok') {
      final error = subsonicResponse['error'];
      throw Exception('API error: ${error['message']} (code: ${error['code']})');
    }

    return subsonicResponse;
  }

  Future<bool> ping() async {
    try {
      await _request('ping');
      return true;
    } catch (e) {
      return false;
    }
  }
  
  /// Ping with detailed error information for login
  Future<LoginResult> pingWithError() async {
    try {
      await _request('ping');
      return LoginResult(success: true);
    } catch (e) {
      String errorMessage;
      if (e.toString().contains('API error')) {
        // Extract API error message
        errorMessage = e.toString().replaceAll('Exception: API error: ', '');
      } else if (e.toString().contains('HTTP error')) {
        // HTTP errors
        if (e.toString().contains('401')) {
          errorMessage = 'Invalid username or password';
        } else if (e.toString().contains('404')) {
          errorMessage = 'Server not found. Check the URL';
        } else if (e.toString().contains('500')) {
          errorMessage = 'Server error. Please try again later';
        } else {
          errorMessage = 'Connection failed: ${e.toString().replaceAll('Exception: HTTP error: ', '')}';
        }
      } else if (e.toString().contains('SocketException')) {
        errorMessage = 'Cannot connect to server. Check URL and network';
      } else if (e.toString().contains('HandshakeException')) {
        errorMessage = 'SSL certificate error. Try using http:// instead of https://';
      } else {
        errorMessage = 'Connection failed: ${e.toString().replaceAll('Exception: ', '')}';
      }
      return LoginResult(success: false, error: errorMessage);
    }
  }

  Future<List<Artist>> getArtists() async {
    final response = await _request('getArtists');
    final artists = <Artist>[];
    
    final artistsData = response['artists'];
    if (artistsData != null && artistsData['index'] != null) {
      for (final index in artistsData['index']) {
        if (index['artist'] != null) {
          for (final artistJson in index['artist']) {
            artists.add(Artist.fromJson(artistJson));
          }
        }
      }
    }
    
    return artists;
  }

  Future<Map<String, dynamic>> getArtist(String id) async {
    final response = await _request('getArtist', {'id': id});
    final artist = response['artist'];
    
    final albums = <Album>[];
    if (artist['album'] != null) {
      for (final albumJson in artist['album']) {
        albums.add(Album.fromJson(albumJson));
      }
    }
    
    return {
      'artist': Artist.fromJson(artist),
      'albums': albums,
    };
  }

  Future<Map<String, dynamic>> getAlbum(String id) async {
    final response = await _request('getAlbum', {'id': id});
    final albumData = response['album'];
    
    final songs = <Song>[];
    if (albumData['song'] != null) {
      for (final songJson in albumData['song']) {
        songs.add(Song.fromJson(songJson));
      }
    }
    
    return {
      'album': Album.fromJson(albumData),
      'songs': songs,
    };
  }

  Future<List<Album>> getAlbumList2({
    required String type,
    int size = 50,
    int offset = 0,
  }) async {
    final response = await _request('getAlbumList2', {
      'type': type,
      'size': size.toString(),
      'offset': offset.toString(),
    });
    
    final albums = <Album>[];
    final albumList = response['albumList2'];
    if (albumList != null && albumList['album'] != null) {
      for (final albumJson in albumList['album']) {
        albums.add(Album.fromJson(albumJson));
      }
    }
    
    return albums;
  }

  Future<List<Album>> getRecentlyAdded({int size = 50}) async {
    return getAlbumList2(type: 'newest', size: size);
  }

  Future<Map<String, dynamic>> search3(String query) async {
    final response = await _request('search3', {
      'query': query,
      'artistCount': '20',
      'albumCount': '20',
      'songCount': '50',
    });
    
    final searchResult = response['searchResult3'] ?? {};
    
    final artists = <Artist>[];
    if (searchResult['artist'] != null) {
      for (final artistJson in searchResult['artist']) {
        artists.add(Artist.fromJson(artistJson));
      }
    }
    
    final albums = <Album>[];
    if (searchResult['album'] != null) {
      for (final albumJson in searchResult['album']) {
        albums.add(Album.fromJson(albumJson));
      }
    }
    
    final songs = <Song>[];
    if (searchResult['song'] != null) {
      for (final songJson in searchResult['song']) {
        songs.add(Song.fromJson(songJson));
      }
    }
    
    return {
      'artists': artists,
      'albums': albums,
      'songs': songs,
    };
  }

  String getStreamUrl(String id, {bool transcode = false}) {
    final params = _getAuthParams();
    params['id'] = id;
    
    // Add transcoding parameters for mobile
    if (transcode) {
      params['format'] = 'mp3';
      params['maxBitRate'] = '320';
    }
    
    final queryString = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    return '$baseUrl/rest/stream?$queryString';
  }

  String getCoverArtUrl(String? id, {int size = 300}) {
    if (id == null) return '';
    final params = _getAuthParams();
    params['id'] = id;
    params['size'] = size.toString();
    final queryString = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    return '$baseUrl/rest/getCoverArt?$queryString';
  }

  Future<void> scrobble(String id, {bool submission = false}) async {
    await _request('scrobble', {
      'id': id,
      'submission': submission.toString(),
    });
  }

  Future<void> star(String id) async {
    await _request('star', {'id': id});
  }

  Future<void> unstar(String id) async {
    await _request('unstar', {'id': id});
  }

  // Library scanning methods (Subsonic API v1.15.0+)
  Future<void> startScan() async {
    try {
      await _request('startScan');
    } catch (e) {
      // Some servers might not support this endpoint
      print('Warning: startScan not supported or failed: $e');
    }
  }

  // Get user information including admin rights
  Future<Map<String, dynamic>> getUser(String username) async {
    try {
      final response = await _request('getUser', {'username': username});
      final user = response['user'] ?? {};

      return {
        'username': user['username'],
        'email': user['email'],
        'adminRole': user['adminRole'] ?? false,
        'settingsRole': user['settingsRole'] ?? false,
        'downloadRole': user['downloadRole'] ?? false,
        'uploadRole': user['uploadRole'] ?? false,
        'playlistRole': user['playlistRole'] ?? false,
        'coverArtRole': user['coverArtRole'] ?? false,
        'commentRole': user['commentRole'] ?? false,
        'podcastRole': user['podcastRole'] ?? false,
        'streamRole': user['streamRole'] ?? true,
        'jukeboxRole': user['jukeboxRole'] ?? false,
        'shareRole': user['shareRole'] ?? false,
        'lastLogin': user['lastLogin'],
      };
    } catch (e) {
      print('Warning: getUser not supported or failed: $e');
      return {
        'username': username,
        'adminRole': false,
        'settingsRole': false,
        'downloadRole': false,
        'uploadRole': false,
        'playlistRole': false,
        'coverArtRole': false,
        'commentRole': false,
        'podcastRole': false,
        'streamRole': true,
        'jukeboxRole': false,
        'shareRole': false,
        'lastLogin': null,
      };
    }
  }

  // Check if current user has admin rights
  Future<bool> hasAdminRights() async {
    try {
      final user = await getUser(username);
      return user['adminRole'] ?? false;
    } catch (e) {
      print('Warning: Could not check admin rights: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>> getScanStatus() async {
    try {
      final response = await _request('getScanStatus');
      final scanStatus = response['scanStatus'] ?? {};

      return {
        'scanning': scanStatus['scanning'] ?? false,
        'count': scanStatus['count'] ?? 0,
        'folderCount': scanStatus['folderCount'] ?? 0,
        'lastScan': scanStatus['lastScan'],
      };
    } catch (e) {
      // Some servers might not support this endpoint
      print('Warning: getScanStatus not supported or failed: $e');
      return {
        'scanning': false,
        'count': 0,
        'folderCount': 0,
        'lastScan': null,
      };
    }
  }
}