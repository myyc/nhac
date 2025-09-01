import 'package:flutter/foundation.dart';
import '../models/song.dart';
import '../services/navidrome_api.dart';

class SimplePlayerProvider extends ChangeNotifier {
  NavidromeApi? _api;
  
  Song? _currentSong;
  List<Song> _queue = [];
  int _currentIndex = 0;
  bool _isPlaying = false;
  String? _currentStreamUrl;

  Song? get currentSong => _currentSong;
  List<Song> get queue => _queue;
  int get currentIndex => _currentIndex;
  bool get isPlaying => _isPlaying;
  String? get currentStreamUrl => _currentStreamUrl;
  
  // Simplified duration and position - will be handled by UI
  Duration get position => Duration.zero;
  Duration get duration => Duration.zero;

  void setApi(NavidromeApi api) {
    _api = api;
  }

  Future<void> playSong(Song song) async {
    if (_api == null) return;
    
    _currentSong = song;
    _queue = [song];
    _currentIndex = 0;
    _currentStreamUrl = _api!.getStreamUrl(song.id);
    _isPlaying = true;
    
    notifyListeners();
  }

  Future<void> playQueue(List<Song> songs, {int startIndex = 0}) async {
    if (_api == null || songs.isEmpty) return;
    
    _queue = songs;
    _currentIndex = startIndex;
    _currentSong = songs[startIndex];
    _currentStreamUrl = _api!.getStreamUrl(_currentSong!.id);
    _isPlaying = true;
    
    notifyListeners();
  }

  Future<void> addToQueue(Song song) async {
    _queue.add(song);
    
    if (_currentSong == null) {
      await playSong(song);
    }
    
    notifyListeners();
  }

  Future<void> play() async {
    _isPlaying = true;
    notifyListeners();
  }

  Future<void> pause() async {
    _isPlaying = false;
    notifyListeners();
  }

  Future<void> togglePlayPause() async {
    _isPlaying = !_isPlaying;
    notifyListeners();
  }

  Future<void> next() async {
    if (_queue.isEmpty || _api == null) return;
    
    if (_currentIndex < _queue.length - 1) {
      _currentIndex++;
      _currentSong = _queue[_currentIndex];
      _currentStreamUrl = _api!.getStreamUrl(_currentSong!.id);
      _isPlaying = true;
      
      notifyListeners();
    }
  }

  Future<void> previous() async {
    if (_queue.isEmpty || _api == null) return;
    
    if (_currentIndex > 0) {
      _currentIndex--;
      _currentSong = _queue[_currentIndex];
      _currentStreamUrl = _api!.getStreamUrl(_currentSong!.id);
      _isPlaying = true;
      
      notifyListeners();
    }
  }

  Future<void> seek(Duration position) async {
    // Placeholder - actual seeking would need audio player implementation
  }

  @override
  void dispose() {
    super.dispose();
  }
}