import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/cache_provider.dart';
import '../providers/player_provider.dart';
import '../screens/now_playing_screen.dart';
import 'cached_cover_image.dart';

class NowPlayingBar extends StatelessWidget {
  const NowPlayingBar({super.key});

  // Calculate appropriate icon color based on HSL values
  Color _getContrastIconColor(Color backgroundColor) {
    final hslColor = HSLColor.fromColor(backgroundColor);
    final lightness = hslColor.lightness;
    final saturation = hslColor.saturation;
    
    // For very light colors with low saturation (near white/gray)
    // Use dark icons
    if (lightness > 0.7 && saturation < 0.3) {
      return Colors.black87;
    }
    
    // For very light colors with some saturation (pastel colors)
    // Also use dark icons
    if (lightness > 0.8) {
      return Colors.black87;
    }
    
    // For all other colors (including bright saturated colors like red)
    // Use white icons
    return Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PlayerProvider>(
      builder: (context, playerProvider, child) {
        final song = playerProvider.currentSong;
        if (song == null) return const SizedBox.shrink();
        
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
                          child: CachedCoverImage(
                            key: ValueKey('nowplaying_${song.id}_${song.coverArt}'),
                            coverArtId: song.coverArt,
                            size: 112,
                            width: 56,
                            height: 56,
                            borderRadius: BorderRadius.circular(8),
                            placeholder: const Center(child: Icon(Icons.music_note, size: 24)),
                            errorWidget: const Center(child: Icon(Icons.music_note, size: 24)),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      song.title,
                                      style: theme.textTheme.bodyLarge?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (playerProvider.isPlayingOffline)
                                    Container(
                                      margin: const EdgeInsets.only(left: 8),
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade700,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.offline_pin,
                                            size: 12,
                                            color: Colors.white,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'CACHED',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
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
                            Material(
                              color: extractedColors?.primary ?? theme.colorScheme.primary,
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: playerProvider.togglePlayPause,
                                child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Icon(
                                    playerProvider.isPlaying
                                        ? (playerProvider.isBuffering ? Icons.hourglass_empty : Icons.pause)
                                        : Icons.play_arrow,
                                    size: 24,
                                    color: _getContrastIconColor(
                                      extractedColors?.primary ?? theme.colorScheme.primary
                                    ),
                                  ),
                                ),
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