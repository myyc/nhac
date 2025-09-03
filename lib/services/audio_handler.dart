import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import '../models/song.dart';
import '../services/navidrome_api.dart';

class NhacAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player;
  NavidromeApi _api; // Made non-final to allow updates
  List<Song> _queue = [];
  List<String?> _coverArtPaths = []; // Local paths to cached cover art
  int _currentIndex = 0;
  
  NhacAudioHandler(this._player, this._api) {
    _notifyAudioHandlerAboutPlaybackEvents();
    _listenForDurationChanges();
    _listenForCurrentSongIndexChanges();
    _listenForSequenceStateChanges();
    _listenForPositionChanges();
    _listenForCompletion();
  }
  
  // Method to update the API after initialization
  void updateApi(NavidromeApi api) {
    _api = api;
  }
  
  // Method to update cover art paths for the queue
  Future<void> updateCoverArtPaths(List<String?> paths) async {
    _coverArtPaths = paths;
    
    // Update the current media item with cached art if available
    if (_currentIndex < _queue.length) {
      final song = _queue[_currentIndex];
      final coverArtPath = _currentIndex < _coverArtPaths.length ? 
          _coverArtPaths[_currentIndex] : null;
      final mediaItem = _createMediaItem(song, coverArtPath: coverArtPath);
      this.mediaItem.add(mediaItem);
      
      // Also update the queue with the updated media item
      final updatedQueue = queue.value.toList();
      if (_currentIndex < updatedQueue.length) {
        updatedQueue[_currentIndex] = mediaItem;
        queue.add(updatedQueue);
      }
    }
  }
  
  void _notifyAudioHandlerAboutPlaybackEvents() {
    _player.playbackEventStream.listen((PlaybackEvent event) {
      final playing = _player.playing;
      final controls = [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ];
      
      playbackState.add(playbackState.value.copyWith(
        controls: controls,
        systemActions: const {
          MediaAction.seek,
        },
        androidCompactActionIndices: const [0, 1, 2], // prev, play/pause, next in compact view
        processingState: const {
          ProcessingState.idle: AudioProcessingState.idle,
          ProcessingState.loading: AudioProcessingState.loading,
          ProcessingState.buffering: AudioProcessingState.buffering,
          ProcessingState.ready: AudioProcessingState.ready,
          ProcessingState.completed: AudioProcessingState.completed,
        }[_player.processingState]!,
        repeatMode: const {
          LoopMode.off: AudioServiceRepeatMode.none,
          LoopMode.one: AudioServiceRepeatMode.one,
          LoopMode.all: AudioServiceRepeatMode.all,
        }[_player.loopMode]!,
        shuffleMode: (_player.shuffleModeEnabled)
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: event.currentIndex,
      ));
    });
  }
  
  void _listenForDurationChanges() {
    _player.durationStream.listen((duration) {
      var index = _player.currentIndex;
      final newQueue = queue.value;
      if (index == null || newQueue.isEmpty) return;
      if (_player.shuffleModeEnabled) {
        index = _player.shuffleIndices![index];
      }
      final oldMediaItem = newQueue[index];
      final newMediaItem = oldMediaItem.copyWith(duration: duration);
      newQueue[index] = newMediaItem;
      queue.add(newQueue);
      mediaItem.add(newMediaItem);
    });
  }
  
  void _listenForCurrentSongIndexChanges() {
    // Listen to index changes for all platforms now that we use setAudioSources
    _player.currentIndexStream.listen((index) {
      final playlist = queue.value;
      if (index == null || playlist.isEmpty) return;
      
      if (_player.shuffleModeEnabled) {
        index = _player.shuffleIndices![index];
      }
      _currentIndex = index;
      mediaItem.add(playlist[index]);
    });
  }
  
  void _listenForSequenceStateChanges() {
    _player.sequenceStateStream.listen((SequenceState? sequenceState) {
      final sequence = sequenceState?.effectiveSequence;
      if (sequence == null || sequence.isEmpty) return;
      
      // Filter out null tags and safely cast
      final items = sequence
          .where((source) => source.tag != null)
          .map((source) => source.tag as MediaItem)
          .toList();
      
      if (items.isNotEmpty) {
        queue.add(items);
      }
    });
  }
  
  void _listenForPositionChanges() {
    // Update position continuously every 200ms while playing
    _player.positionStream.listen((position) {
      playbackState.add(playbackState.value.copyWith(
        updatePosition: position,
        bufferedPosition: _player.bufferedPosition,
      ));
    });
  }
  
  void _listenForCompletion() {
    // Handle track completion for auto-advance
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        // Auto-advance to next track
        skipToNext();
      }
    });
  }
  
  MediaItem _createMediaItem(Song song, {String? coverArtPath}) {
    Uri? artUri;
    
    // For Android notifications, prefer network URLs over local files
    // as MediaSession may not have access to local files
    if (song.coverArt != null && _api != null) {
      final url = _api.getCoverArtUrl(song.coverArt!, size: 600);
      artUri = Uri.parse(url);
    } else if (coverArtPath != null) {
      // Use local file as fallback
      final file = File(coverArtPath);
      if (file.existsSync()) {
        artUri = Uri.file(coverArtPath);
      }
    }
    
    final mediaItem = MediaItem(
      id: song.id,
      title: song.title,
      artist: song.artist ?? 'Unknown Artist',
      album: song.album,
      duration: song.duration != null 
          ? Duration(seconds: song.duration!) 
          : null,
      artUri: artUri,
    );
    
    
    return mediaItem;
  }
  
  Future<void> updateQueueFromSongs(List<Song> songs, {
    int startIndex = 0,
    List<String?>? coverArtPaths,
  }) async {
    print('[AudioHandler] updateQueueFromSongs() - received ${songs.length} songs, startIndex: $startIndex');
    if (songs.isNotEmpty && startIndex < songs.length) {
      print('[AudioHandler] Starting with song: ${songs[startIndex].title} (track ${songs[startIndex].track})');
    }
    
    // Simple: always replace the queue and set the index
    _queue = songs;
    _currentIndex = startIndex;
    
    print('[AudioHandler] Queue updated - ${_queue.length} songs, currentIndex: $_currentIndex');
    
    // Store cover art paths if provided
    if (coverArtPaths != null) {
      _coverArtPaths = coverArtPaths;
    } else {
      _coverArtPaths = List.filled(songs.length, null);
    }
    
    // Convert songs to MediaItems with cached art paths
    final mediaItems = <MediaItem>[];
    for (int i = 0; i < songs.length; i++) {
      final coverArtPath = i < _coverArtPaths.length ? _coverArtPaths[i] : null;
      mediaItems.add(_createMediaItem(songs[i], coverArtPath: coverArtPath));
    }
    
    // Update the queue
    queue.add(mediaItems);
    
    // Create audio sources for all songs
    final audioSources = <AudioSource>[];
    for (int i = 0; i < songs.length; i++) {
      final url = _api.getStreamUrl(songs[i].id);
      final coverArtPath = i < _coverArtPaths.length ? _coverArtPaths[i] : null;
      audioSources.add(AudioSource.uri(
        Uri.parse(url),
        tag: _createMediaItem(songs[i], coverArtPath: coverArtPath),
      ));
    }
    
    // Use setAudioSources for all platforms
    if (audioSources.isNotEmpty) {
      await _player.setAudioSources(
        audioSources,
        initialIndex: startIndex,
      );
    }
    
    // Update the current media item
    if (songs.isNotEmpty && startIndex < mediaItems.length) {
      mediaItem.add(mediaItems[startIndex]);
    }
  }
  
  @override
  Future<void> updateQueue(List<MediaItem> queue) async {
    // This is the overridden method from BaseAudioHandler
    // We'll just update the queue without changing the playback
    this.queue.add(queue);
  }
  
  Future<void> updateCurrentSong(Song song) async {
    if (_currentIndex < _queue.length) {
      _queue[_currentIndex] = song;
      final newMediaItem = _createMediaItem(song);
      mediaItem.add(newMediaItem);
      
      // Update the queue with the new media item
      final newQueue = queue.value.toList();
      if (_currentIndex < newQueue.length) {
        newQueue[_currentIndex] = newMediaItem;
        queue.add(newQueue);
      }
    }
  }
  
  @override
  Future<void> play() => _player.play();
  
  @override
  Future<void> pause() => _player.pause();
  
  @override
  Future<void> stop() async {
    await _player.stop();
    return super.stop();
  }
  
  @override
  Future<void> seek(Duration position) => _player.seek(position);
  
  @override
  Future<void> skipToNext() async {
    print('[AudioHandler] skipToNext() - queue: ${_queue.length}, index: $_currentIndex');
    if (_queue.isEmpty) return;
    
    // Can only go next if not at the last song
    if (_currentIndex >= _queue.length - 1) {
      print('[AudioHandler] Already at last song, cannot skip next');
      return;
    }
    
    // Remember the playing state
    final wasPlaying = _player.playing;
    
    // Use the player's built-in seekToNext
    await _player.seekToNext();
    
    // Preserve play state (seekToNext maintains play state, but just in case)
    if (wasPlaying && !_player.playing) {
      await _player.play();
    }
  }
  
  @override
  Future<void> skipToPrevious() async {
    print('[AudioHandler] skipToPrevious() - queue: ${_queue.length}, index: $_currentIndex, position: ${_player.position}');
    if (_queue.isEmpty) return;
    
    // Check current position
    const restartThreshold = Duration(seconds: 3);
    final currentPosition = _player.position;
    
    // If more than 3 seconds in, restart current track
    if (currentPosition > restartThreshold) {
      print('[AudioHandler] Restarting current track');
      await _player.seek(Duration.zero);
      return;
    }
    
    // If at first track, always restart
    if (_currentIndex == 0) {
      print('[AudioHandler] At first track, restarting');
      await _player.seek(Duration.zero);
      return;
    }
    
    // Otherwise go to previous track
    final wasPlaying = _player.playing;
    print('[AudioHandler] Moving to previous track');
    
    // Use the player's built-in seekToPrevious
    await _player.seekToPrevious();
    
    // Preserve play state (seekToPrevious maintains play state, but just in case)
    if (wasPlaying && !_player.playing) {
      await _player.play();
    }
  }
  
  @override
  Future<void> rewind() async {
    final newPosition = _player.position - const Duration(seconds: 10);
    await _player.seek(newPosition < Duration.zero ? Duration.zero : newPosition);
  }
  
  @override
  Future<void> fastForward() async {
    final newPosition = _player.position + const Duration(seconds: 10);
    final duration = _player.duration;
    if (duration != null && newPosition > duration) {
      await _player.seek(duration);
    } else {
      await _player.seek(newPosition);
    }
  }
  
  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _currentIndex = index;
    
    // Use seek with index for all platforms
    await _player.seek(Duration.zero, index: index);
    await _player.play();
    
    // Update media item
    final mediaItems = queue.value;
    if (index < mediaItems.length) {
      mediaItem.add(mediaItems[index]);
    }
  }
  
  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    switch (repeatMode) {
      case AudioServiceRepeatMode.none:
        _player.setLoopMode(LoopMode.off);
        break;
      case AudioServiceRepeatMode.one:
        _player.setLoopMode(LoopMode.one);
        break;
      case AudioServiceRepeatMode.group:
      case AudioServiceRepeatMode.all:
        _player.setLoopMode(LoopMode.all);
        break;
    }
  }
  
  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    if (shuffleMode == AudioServiceShuffleMode.none) {
      _player.setShuffleModeEnabled(false);
    } else {
      await _player.shuffle();
      _player.setShuffleModeEnabled(true);
    }
  }
}