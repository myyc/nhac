import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/auth_provider.dart';
import '../providers/player_provider.dart';
import '../providers/cache_provider.dart';
import '../models/album.dart';
import '../models/song.dart';
import '../models/artist.dart';
import '../widgets/custom_title_bar.dart';
import 'app_scaffold.dart';
import 'artist_detail_screen.dart';

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
    final api = context.read<AuthProvider>().api;
    if (api == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await api.getAlbum(widget.album.id);
      if (mounted) {
        setState(() {
          _songs = result['songs'];
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
    final playerProvider = context.read<PlayerProvider>();
    final cacheProvider = context.read<CacheProvider>();
    
    return AppScaffold(
      appBar: CustomTitleBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(widget.album.name),
      ),
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
                                  CachedNetworkImage(
                                    key: ValueKey('album_${widget.album.id}_${widget.album.coverArt}'),
                                    imageUrl: cacheProvider.getCoverArtUrl(widget.album.coverArt, size: 600),
                                    cacheKey: 'cover_${widget.album.id}_${widget.album.coverArt}_600',
                                    fit: BoxFit.cover,
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
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                FilledButton.icon(
                                  onPressed: _songs != null && _songs!.isNotEmpty
                                      ? () {
                                          playerProvider.setApi(api!);
                                          playerProvider.playQueue(_songs!);
                                        }
                                      : null,
                                  icon: const Icon(Icons.play_arrow),
                                  label: const Text('Play'),
                                ),
                                const SizedBox(width: 8),
                                FilledButton.tonalIcon(
                                  onPressed: _songs != null && _songs!.isNotEmpty
                                      ? () {
                                          playerProvider.setApi(api!);
                                          final shuffled = List<Song>.from(_songs!)..shuffle();
                                          playerProvider.playQueue(shuffled);
                                        }
                                      : null,
                                  icon: const Icon(Icons.shuffle),
                                  label: const Text('Shuffle'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      
                      // Song list
                      if (_songs != null)
                        ...(_songs!.map((song) => ListTile(
                          leading: SizedBox(
                            width: 30,
                            child: Text(
                              song.track?.toString() ?? '',
                              style: Theme.of(context).textTheme.bodyMedium,
                              textAlign: TextAlign.center,
                            ),
                          ),
                          title: Text(song.title),
                          subtitle: Text(song.artist ?? 'Unknown Artist'),
                          trailing: Text(song.formattedDuration),
                          onTap: () {
                            playerProvider.setApi(api!);
                            playerProvider.playQueue(_songs!, startIndex: _songs!.indexOf(song));
                          },
                        ))),
                        
                      const SizedBox(height: 80), // Space for player bar
                    ],
                  ),
                ),
    );
  }
}