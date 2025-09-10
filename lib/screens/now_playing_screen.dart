import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import '../widgets/custom_window_frame.dart';
import 'package:provider/provider.dart';
import '../providers/cache_provider.dart';
import '../providers/player_provider.dart';
import '../providers/auth_provider.dart';
import '../models/artist.dart';
import '../models/album.dart';
import '../services/share_service.dart';
import '../widgets/cached_cover_image.dart';
import 'artist_detail_screen.dart';
import 'album_detail_screen.dart';

class NowPlayingScreen extends StatelessWidget {
  const NowPlayingScreen({super.key});

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

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final cacheProvider = context.read<CacheProvider>();
    final shareService = ShareService();
    
    return Consumer<PlayerProvider>(
      builder: (context, playerProvider, child) {
        final song = playerProvider.currentSong;
        if (song == null) {
          Navigator.pop(context);
          return const SizedBox.shrink();
        }

        final extractedColors = playerProvider.currentColors;
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;

        final scaffold = Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).pop(),
            ),
            actions: [
              if (Platform.isAndroid && song.coverArt != null)
                IconButton(
                  icon: const Icon(Icons.share),
                  onPressed: () {
                    // Capture theme before sharing
                    final capturedTheme = InheritedTheme.capture(from: context, to: context);
                    shareService.shareStoryImage(
                      context: context,
                      song: song,
                      coverArtUrl: cacheProvider.getCoverArtUrl(song.coverArt!, size: 800),
                      styleType: 'solid',
                      capturedTheme: capturedTheme,
                    );
                  },
                ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Expanded(
                  child: (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
                      ? MoveWindow(
                          child: Center(
                            child: Container(
                              constraints: const BoxConstraints(maxWidth: 360, maxHeight: 360),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                color: Theme.of(context).colorScheme.surfaceVariant,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.15),
                                    blurRadius: 30,
                                    offset: const Offset(0, 15),
                                    spreadRadius: -5,
                                  ),
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.08),
                                    blurRadius: 10,
                                    offset: const Offset(0, 5),
                                  ),
                                ],
                              ),
                              child: CachedCoverImage(
                                key: ValueKey('playing_${song.id}_${song.coverArt}'),
                                coverArtId: song.coverArt,
                                size: 800,
                                borderRadius: BorderRadius.circular(20),
                                placeholder: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(20),
                                    color: Theme.of(context).colorScheme.surfaceVariant,
                                  ),
                                  child: Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.music_note,
                                          size: 60,
                                          color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.4),
                                        ),
                                        const SizedBox(height: 16),
                                        SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Theme.of(context).colorScheme.primary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                errorWidget: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(20),
                                    color: Theme.of(context).colorScheme.surfaceVariant,
                                  ),
                                  child: Center(
                                    child: Icon(
                                      Icons.music_note,
                                      size: 80,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.4),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        )
                      : Center(
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 360, maxHeight: 360),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              color: Theme.of(context).colorScheme.surfaceVariant,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.15),
                                  blurRadius: 30,
                                  offset: const Offset(0, 15),
                                  spreadRadius: -5,
                                ),
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.08),
                                  blurRadius: 10,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                            ),
                            child: CachedCoverImage(
                              key: ValueKey('playing_${song.id}_${song.coverArt}'),
                              coverArtId: song.coverArt,
                              size: 800,
                              borderRadius: BorderRadius.circular(20),
                              placeholder: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(20),
                                  color: Theme.of(context).colorScheme.surfaceVariant,
                                ),
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.music_note,
                                        size: 60,
                                        color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.4),
                                      ),
                                      const SizedBox(height: 16),
                                      SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Theme.of(context).colorScheme.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              errorWidget: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(20),
                                  color: Theme.of(context).colorScheme.surfaceVariant,
                                ),
                                child: Center(
                                  child: Icon(
                                    Icons.music_note,
                                    size: 80,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.4),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: 40),
                Column(
                  children: [
                    Text(
                      song.title,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                        height: 1.2,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
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
                            onTap: song.albumId != null ? () async {
                              // Try to get full album from cache first
                              Album album;
                              try {
                                final cacheProvider = context.read<CacheProvider>();
                                final albums = await cacheProvider.getAlbums();
                                album = albums.firstWhere(
                                  (a) => a.id == song.albumId,
                                  orElse: () => Album(
                                    id: song.albumId!,
                                    name: song.album!,
                                    artist: song.artist,
                                    artistId: song.artistId,
                                    coverArt: song.coverArt,
                                  ),
                                );
                              } catch (e) {
                                // If error, create minimal Album object
                                album = Album(
                                  id: song.albumId!,
                                  name: song.album!,
                                  artist: song.artist,
                                  artistId: song.artistId,
                                  coverArt: song.coverArt,
                                );
                              }
                              
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
                    Material(
                      color: Theme.of(context).colorScheme.primary,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: playerProvider.togglePlayPause,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Icon(
                            playerProvider.isPlaying 
                                ? Icons.pause 
                                : Icons.play_arrow,
                            size: 48,
                            color: _getContrastIconColor(Theme.of(context).colorScheme.primary),
                          ),
                        ),
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
                
                // Volume control - only show on desktop
                if (!Platform.isAndroid && !Platform.isIOS)
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
                if (!Platform.isAndroid && !Platform.isIOS)
                  const SizedBox(height: 24),
              ],
            ),
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
      },
    );
  }
}