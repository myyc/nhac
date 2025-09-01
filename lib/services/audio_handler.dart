import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import '../models/song.dart';
import '../services/navidrome_api.dart';

class NhacteAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player;
  NavidromeApi _api; // Made non-final to allow updates
  List<Song> _queue = [];
  int _currentIndex = 0;
  
  NhacteAudioHandler(this._player, this._api) {
    _notifyAudioHandlerAboutPlaybackEvents();
    _listenForDurationChanges();
    _listenForCurrentSongIndexChanges();
    _listenForSequenceStateChanges();
  }
  
  // Method to update the API after initialization
  void updateApi(NavidromeApi api) {
    _api = api;
  }
  
  void _notifyAudioHandlerAboutPlaybackEvents() {
    _player.playbackEventStream.listen((PlaybackEvent event) {
      final playing = _player.playing;
      playbackState.add(playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.stop,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekBackward,
          MediaAction.seekForward,
        },
        androidCompactActionIndices: const [0, 1, 3],
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
  
  MediaItem _createMediaItem(Song song) {
    String? artUri;
    if (song.coverArt != null) {
      artUri = _api.getCoverArtUrl(song.coverArt!, size: 600);
    }
    
    return MediaItem(
      id: song.id,
      title: song.title,
      artist: song.artist ?? 'Unknown Artist',
      album: song.album,
      duration: song.duration != null 
          ? Duration(seconds: song.duration!) 
          : null,
      artUri: artUri != null ? Uri.parse(artUri) : null,
    );
  }
  
  Future<void> updateQueueFromSongs(List<Song> songs, {int startIndex = 0}) async {
    _queue = songs;
    _currentIndex = startIndex;
    
    // Convert songs to MediaItems
    final mediaItems = songs.map(_createMediaItem).toList();
    
    // Update the queue
    queue.add(mediaItems);
    
    // Create audio sources
    final audioSources = songs.map((song) {
      final url = _api.getStreamUrl(song.id);
      return AudioSource.uri(
        Uri.parse(url),
        tag: _createMediaItem(song),
      );
    }).toList();
    
    // Set the playlist
    final playlist = ConcatenatingAudioSource(children: audioSources);
    await _player.setAudioSource(playlist, initialIndex: startIndex);
    
    // Update the current media item
    if (songs.isNotEmpty) {
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
  Future<void> skipToNext() => _player.seekToNext();
  
  @override
  Future<void> skipToPrevious() => _player.seekToPrevious();
  
  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _currentIndex = index;
    await _player.seek(Duration.zero, index: index);
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