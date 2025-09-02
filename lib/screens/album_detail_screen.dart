import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/player_provider.dart';
import '../providers/cache_provider.dart';
import '../providers/network_provider.dart';
import '../models/album.dart';
import '../models/song.dart';
import '../models/artist.dart';
import '../widgets/cached_cover_image.dart';
import 'artist_detail_screen.dart';
import '../widgets/custom_window_frame.dart';
import '../widgets/now_playing_bar.dart';
import 'dart:io' show Platform;

class AlbumDetailScreen extends StatefulWidget {
  final Album album;

  const AlbumDetailScreen({super.key, required this.album});

  @override
  State<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends State<AlbumDetailScreen> {
  List<Song>? _songs;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAlbumDetails();
  }

  Future<void> _loadAlbumDetails() async {
    final cacheProvider = context.read<CacheProvider>();

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final songs = await cacheProvider.getSongsByAlbum(widget.album.id);
      if (mounted) {
        setState(() {
          _songs = songs;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  String _formatDuration(int? seconds) {
    if (seconds == null) return '';
    final duration = Duration(seconds: seconds);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final secs = duration.inSeconds.remainder(60);
    
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else {
      return '${minutes}m ${secs}s';
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<AuthProvider>().api;
    final cacheProvider = context.read<CacheProvider>();
    
    final scaffold = Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(widget.album.name),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Error: $_error'),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _loadAlbumDetails,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Album cover
                      Container(
                        height: 300,
                        width: double.infinity,
                        child: widget.album.coverArt != null
                            ? Stack(
                                fit: StackFit.expand,
                                children: [
                                  CachedCoverImage(
                                    key: ValueKey('album_${widget.album.id}_${widget.album.coverArt}'),
                                    coverArtId: widget.album.coverArt,
                                    size: 600,
                                  ),
                                  Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Colors.transparent,
                                          Colors.black.withOpacity(0.3),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : Container(
                                color: Theme.of(context).colorScheme.surfaceVariant,
                                child: const Icon(Icons.album, size: 100),
                              ),
                      ),
                      
                      // Album info
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            MouseRegion(
                              cursor: widget.album.artistId != null ? SystemMouseCursors.click : MouseCursor.defer,
                              child: GestureDetector(
                                onTap: widget.album.artistId != null ? () {
                                  final artist = Artist(
                                    id: widget.album.artistId!,
                                    name: widget.album.artist ?? 'Unknown Artist',
                                  );
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => ArtistDetailScreen(artist: artist),
                                    ),
                                  );
                                } : null,
                                child: Text(
                                  widget.album.artist ?? 'Unknown Artist',
                                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    color: widget.album.artistId != null 
                                        ? Theme.of(context).colorScheme.primary 
                                        : null,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                if (widget.album.year != null)
                                  Text(
                                    widget.album.year.toString(),
                                    style: Theme.of(context).textTheme.bodyMedium,
                                  ),
                                if (widget.album.year != null && widget.album.songCount != null)
                                  const Text(' • '),
                                if (widget.album.songCount != null)
                                  Text(
                                    '${widget.album.songCount} songs',
                                    style: Theme.of(context).textTheme.bodyMedium,
                                  ),
                                if (widget.album.duration != null)
                                  Text(
                                    ' • ${_formatDuration(widget.album.duration)}',
                                    style: Theme.of(context).textTheme.bodyMedium,
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      
                      // Song list
                      if (_songs != null)
                        Consumer<PlayerProvider>(
                          builder: (context, playerProvider, child) {
                            // Group songs by disc number
                            final Map<int, List<Song>> songsByDisc = {};
                            int maxDiscNumber = 1;
                            for (final song in _songs!) {
                              final discNumber = song.discNumber ?? 1;
                              if (discNumber > maxDiscNumber) {
                                maxDiscNumber = discNumber;
                              }
                              songsByDisc.putIfAbsent(discNumber, () => []).add(song);
                            }
                            
                            // Sort disc numbers
                            final sortedDiscNumbers = songsByDisc.keys.toList()..sort();
                            // Show disc headers if we have multiple discs OR if any disc number is > 1
                            final hasMultipleDiscs = sortedDiscNumbers.length > 1 || maxDiscNumber > 1;
                            
                            // Build widgets for each disc
                            final List<Widget> widgets = [];
                            
                            for (final discNumber in sortedDiscNumbers) {
                              final discSongs = songsByDisc[discNumber]!;
                              
                              // Sort songs within each disc by track number
                              discSongs.sort((a, b) {
                                final trackA = a.track ?? 0;
                                final trackB = b.track ?? 0;
                                return trackA.compareTo(trackB);
                              });
                              
                              // Add disc header if there are multiple discs
                              if (hasMultipleDiscs) {
                                // Get disc subtitle from first song of this disc
                                final discSubtitle = discSongs.first.discSubtitle;
                                
                                widgets.add(
                                  Container(
                                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                                    child: Row(
                                      children: [
                                        Text(
                                          'Disc $discNumber',
                                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        if (discSubtitle != null && discSubtitle.isNotEmpty) ...[
                                          Text(
                                            ': ',
                                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Expanded(
                                            child: Text(
                                              discSubtitle,
                                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                );
                              }
                              
                              // Add songs for this disc
                              for (final song in discSongs) {
                                final isCurrentSong = playerProvider.currentSong?.id == song.id;
                                final isPlaying = isCurrentSong && playerProvider.isPlaying;
                                
                                widgets.add(
                                  Container(
                                    color: isCurrentSong 
                                        ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3)
                                        : null,
                                    child: ListTile(
                                      leading: SizedBox(
                                        width: 30,
                                        child: isCurrentSong
                                            ? Icon(
                                                isPlaying ? Icons.volume_up : Icons.pause_circle_outline,
                                                size: 20,
                                                color: Theme.of(context).colorScheme.primary,
                                              )
                                            : Text(
                                                song.track?.toString() ?? '',
                                                style: Theme.of(context).textTheme.bodyMedium,
                                                textAlign: TextAlign.center,
                                              ),
                                      ),
                                      title: Text(
                                        song.title,
                                        style: TextStyle(
                                          color: isCurrentSong 
                                              ? Theme.of(context).colorScheme.primary 
                                              : null,
                                          fontWeight: isCurrentSong ? FontWeight.bold : null,
                                        ),
                                      ),
                                      subtitle: Text(
                                        song.artist ?? 'Unknown Artist',
                                        style: TextStyle(
                                          color: isCurrentSong 
                                              ? Theme.of(context).colorScheme.primary.withOpacity(0.8)
                                              : null,
                                        ),
                                      ),
                                      trailing: Text(
                                        song.formattedDuration,
                                        style: TextStyle(
                                          color: isCurrentSong 
                                              ? Theme.of(context).colorScheme.primary 
                                              : null,
                                        ),
                                      ),
                                      onTap: () {
                                        final networkProvider = context.read<NetworkProvider>();
                                        playerProvider.setApi(api!, networkProvider: networkProvider);
                                        playerProvider.playQueue(_songs!, startIndex: _songs!.indexOf(song));
                                      },
                                    ),
                                  ),
                                );
                              }
                            }
                            
                            return Column(children: widgets);
                          },
                        ),
                        
                      const SizedBox(height: 16), // Small padding at bottom
                    ],
                  ),
                ),
          ),
          // Mini player at the bottom
          Consumer<PlayerProvider>(
            builder: (context, playerProvider, _) {
              if (playerProvider.currentSong != null) {
                return const NowPlayingBar();
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
    );
    
    // Add ESC key handling for desktop
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return RawKeyboardListener(
        focusNode: FocusNode(),
        autofocus: true,
        onKey: (event) {
          if (event is RawKeyDownEvent && 
              event.logicalKey == LogicalKeyboardKey.escape) {
            Navigator.of(context).pop();
          }
        },
        child: CustomWindowFrame(
          child: scaffold,
        ),
      );
    }
    
    return scaffold;
  }
}