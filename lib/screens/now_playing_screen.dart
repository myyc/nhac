import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/cache_provider.dart';
import '../providers/player_provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/custom_title_bar.dart';
import '../models/artist.dart';
import '../models/album.dart';
import 'app_scaffold.dart';
import 'artist_detail_screen.dart';
import 'album_detail_screen.dart';

class NowPlayingScreen extends StatelessWidget {
  const NowPlayingScreen({super.key});

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final cacheProvider = context.read<CacheProvider>();
    
    return AppScaffold(
      showNowPlayingBar: false,
      appBar: CustomTitleBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Now Playing'),
      ),
      child: Consumer<PlayerProvider>(
        builder: (context, playerProvider, child) {
          final song = playerProvider.currentSong;
          if (song == null) {
            Navigator.pop(context);
            return const SizedBox.shrink();
          }
          
          return Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 400, maxHeight: 400),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: Theme.of(context).colorScheme.surfaceVariant,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: song.coverArt != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: CachedNetworkImage(
                                key: ValueKey('playing_${song.id}_${song.coverArt}'),
                                imageUrl: cacheProvider.getCoverArtUrl(song.coverArt, size: 800),
                                cacheKey: 'cover_${song.id}_${song.coverArt}_800',
                                fit: BoxFit.cover,
                                placeholder: (context, url) => 
                                    const Center(child: CircularProgressIndicator()),
                                errorWidget: (context, url, error) => 
                                    const Center(child: Icon(Icons.music_note, size: 100)),
                              ),
                            )
                          : const Center(child: Icon(Icons.music_note, size: 100)),
                    ),
                  ),
                ),
                const SizedBox(height: 48),
                Column(
                  children: [
                    Text(
                      song.title,
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    MouseRegion(
                      cursor: song.artistId != null ? SystemMouseCursors.click : MouseCursor.defer,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(4),
                          onTap: song.artistId != null ? () {
                            // Create a minimal Artist object for navigation
                            final artist = Artist(
                              id: song.artistId!,
                              name: song.artist ?? 'Unknown Artist',
                            );
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ArtistDetailScreen(artist: artist),
                              ),
                            );
                          } : null,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            child: Text(
                              song.artist ?? 'Unknown Artist',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: song.artistId != null 
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (song.album != null) ...[
                      const SizedBox(height: 4),
                      MouseRegion(
                        cursor: song.albumId != null ? SystemMouseCursors.click : MouseCursor.defer,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(4),
                            onTap: song.albumId != null ? () {
                              // Create a minimal Album object for navigation
                              final album = Album(
                                id: song.albumId!,
                                name: song.album!,
                                artist: song.artist,
                                artistId: song.artistId,
                                coverArt: song.coverArt,
                              );
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => AlbumDetailScreen(album: album),
                                ),
                              );
                            } : null,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              child: Text(
                                song.album!,
                                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  color: song.albumId != null
                                      ? Theme.of(context).colorScheme.primary.withOpacity(0.8)
                                      : Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 32),
                Column(
                  children: [
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 4,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      ),
                      child: Slider(
                        value: playerProvider.duration.inSeconds > 0 
                            ? playerProvider.position.inSeconds.toDouble().clamp(0.0, playerProvider.duration.inSeconds.toDouble())
                            : 0.0,
                        max: playerProvider.duration.inSeconds > 0 
                            ? playerProvider.duration.inSeconds.toDouble() 
                            : 1.0,
                        onChanged: playerProvider.duration.inSeconds > 0 
                            ? (value) {
                                playerProvider.seek(Duration(seconds: value.toInt()));
                              }
                            : null,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatDuration(playerProvider.position),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          Text(
                            _formatDuration(playerProvider.duration),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.skip_previous),
                      iconSize: 48,
                      onPressed: playerProvider.currentIndex > 0
                          ? playerProvider.previous
                          : null,
                    ),
                    const SizedBox(width: 16),
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      child: IconButton(
                        icon: Icon(
                          playerProvider.isPlaying 
                              ? Icons.pause 
                              : Icons.play_arrow,
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                        iconSize: 48,
                        padding: const EdgeInsets.all(16),
                        onPressed: playerProvider.togglePlayPause,
                      ),
                    ),
                    const SizedBox(width: 16),
                    IconButton(
                      icon: const Icon(Icons.skip_next),
                      iconSize: 48,
                      onPressed: playerProvider.currentIndex < playerProvider.queue.length - 1
                          ? playerProvider.next
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                
                // Volume control
                Row(
                  children: [
                    const Icon(Icons.volume_down, size: 20),
                    Expanded(
                      child: Slider(
                        value: playerProvider.volume,
                        onChanged: (value) {
                          playerProvider.setVolume(value);
                        },
                      ),
                    ),
                    const Icon(Icons.volume_up, size: 20),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }
}