import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/cache_provider.dart';
import '../providers/player_provider.dart';
import '../screens/now_playing_screen.dart';

class NowPlayingBar extends StatelessWidget {
  const NowPlayingBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<PlayerProvider>(
      builder: (context, playerProvider, child) {
        final song = playerProvider.currentSong;
        if (song == null) return const SizedBox.shrink();
        
        final cacheProvider = context.read<CacheProvider>();
        final extractedColors = playerProvider.currentColors;
        final theme = Theme.of(context);
        
        return Material(
          elevation: 0,
          child: Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: theme.colorScheme.outline.withOpacity(0.1),
                  width: 0.5,
                ),
              ),
            ),
            child: Stack(
              children: [
                InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const NowPlayingScreen(),
                      ),
                    );
                  },
                  onLongPress: () {
                    // Show stream URL for external player
                    if (playerProvider.currentStreamUrl != null) {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Stream URL'),
                          content: SelectableText(playerProvider.currentStreamUrl!),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                      );
                    }
                  },
                  child: Container(
                    height: 72,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: theme.colorScheme.surfaceVariant,
                          ),
                          child: song.coverArt != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: CachedNetworkImage(
                                    key: ValueKey('nowplaying_${song.id}_${song.coverArt}'),
                                    imageUrl: cacheProvider.getCoverArtUrl(song.coverArt, size: 112),
                                    fit: BoxFit.cover,
                                    memCacheWidth: 112,
                                    memCacheHeight: 112,
                                    cacheKey: 'cover_${song.id}_${song.coverArt}_112',
                                    placeholder: (context, url) => 
                                        const Center(child: Icon(Icons.music_note, size: 24)),
                                    errorWidget: (context, url, error) => 
                                        const Center(child: Icon(Icons.music_note, size: 24)),
                                  ),
                                )
                              : const Center(child: Icon(Icons.music_note)),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                song.title,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                song.artist ?? 'Unknown Artist',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurface.withOpacity(0.7),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.skip_previous),
                              onPressed: playerProvider.currentIndex > 0
                                  ? playerProvider.previous
                                  : null,
                            ),
                            Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: extractedColors?.primary ?? theme.colorScheme.primary,
                              ),
                              child: IconButton(
                                icon: Icon(
                                  playerProvider.isPlaying 
                                      ? Icons.pause 
                                      : Icons.play_arrow,
                                  color: Colors.white,
                                ),
                                padding: const EdgeInsets.all(8),
                                onPressed: playerProvider.togglePlayPause,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.skip_next),
                              onPressed: playerProvider.currentIndex < playerProvider.queue.length - 1
                                  ? playerProvider.next
                                  : null,
                            ),
                          ],
                        ),
                        ],
                      ),
                    ),
                  ),
                  // Progress bar at the bottom
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      height: 2,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.outline.withOpacity(0.1),
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final progress = playerProvider.duration.inMilliseconds > 0
                              ? playerProvider.position.inMilliseconds / playerProvider.duration.inMilliseconds
                              : 0.0;
                          return Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              width: constraints.maxWidth * progress.clamp(0.0, 1.0),
                              height: 2,
                              decoration: BoxDecoration(
                                color: extractedColors?.primary ?? theme.colorScheme.primary,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
            ),
          ),
        );
      },
    );
  }
}