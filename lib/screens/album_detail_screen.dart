import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/player_provider.dart';
import '../providers/cache_provider.dart';
import '../providers/network_provider.dart';
import '../services/album_download_service.dart';
import '../services/database_helper.dart';
import '../models/album.dart';
import '../models/song.dart';
import '../models/artist.dart';
import '../widgets/cached_cover_image.dart';
import '../widgets/artistic_background.dart';
import '../widgets/pull_to_search.dart';
import 'artist_detail_screen.dart';
import '../widgets/custom_window_frame.dart';
import '../widgets/now_playing_bar.dart';
import '../theme/app_theme.dart';
import 'dart:io' show Platform;

class AlbumDetailScreen extends StatefulWidget {
  final Album album;
  final VoidCallback? onOpenSearch;

  const AlbumDetailScreen({super.key, required this.album, this.onOpenSearch});

  @override
  State<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends State<AlbumDetailScreen> {
  List<Song>? _songs;
  bool _isLoading = true;
  String? _error;
  AlbumDownloadProgress? _albumDownloadProgress;
  int _downloadedCount = 0;
  StreamSubscription<AlbumDownloadProgress>? _albumDownloadSubscription;

  @override
  void initState() {
    super.initState();
    // Defer context-dependent initialization
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAlbumDetails();
      _subscribeToDownloadProgress();
    });
  }

  void _subscribeToDownloadProgress() {
    if (!mounted) return;
    final albumDownloadService = context.read<AlbumDownloadService?>();
    if (albumDownloadService == null) return;

    // Subscribe to download progress stream
    _albumDownloadSubscription?.cancel();
    _albumDownloadSubscription = albumDownloadService.downloadProgress.listen((progress) {
      if (mounted && progress.albumId == widget.album.id) {
        setState(() {
          _albumDownloadProgress = progress;
        });

        // Refresh song list on each progress update to show cached status
        // This will update the green indicators as each song downloads
        _refreshSongsFromDatabase();
      }
    });
  }

  /// Refresh just the songs from database without full reload
  Future<void> _refreshSongsFromDatabase() async {
    if (!mounted) return;
    final songs = await DatabaseHelper.getSongsByAlbum(widget.album.id);
    if (mounted && songs.isNotEmpty) {
      setState(() {
        _songs = songs;
      });
    }
  }

  Future<void> _loadAlbumDetails() async {
    if (kDebugMode) {
      print('[AlbumDetailScreen] Loading album details for: ${widget.album.name}');
    }
    final cacheProvider = context.read<CacheProvider>();
    final networkProvider = context.read<NetworkProvider>();
    final albumDownloadService = context.read<AlbumDownloadService?>();

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Always try cache first, never force refresh by default
      final forceRefresh = false;
      if (kDebugMode) {
        print('[AlbumDetailScreen] Fetching songs from cache... (forceRefresh: $forceRefresh)');
      }
      final songs = await cacheProvider.getSongsByAlbum(
        widget.album.id,
        forceRefresh: forceRefresh,
      );
      if (kDebugMode) {
        print('[AlbumDetailScreen] Found ${songs.length} songs');
      }

      // Check for existing album download progress
      final albumDownloadProgress = albumDownloadService != null
          ? await albumDownloadService.getAlbumDownload(widget.album.id)
          : null;

      if (kDebugMode) {
        if (albumDownloadProgress != null) {
          print('[AlbumDetailScreen] Found existing download progress: ${albumDownloadProgress.status} (${albumDownloadProgress.progress}%)');
        }
      }

      if (mounted) {
        setState(() {
          _songs = songs;
          _isLoading = false;
          _albumDownloadProgress = albumDownloadProgress;
        });
        if (kDebugMode) {
          print('[AlbumDetailScreen] UI updated successfully');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('[AlbumDetailScreen] Error loading album details: $e');
      }
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

  // Calculate if primary color has enough contrast with primaryContainer
  Color _getPlayingTrackColor(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final primaryContainer = theme.colorScheme.primaryContainer;
    
    // Calculate luminance difference
    final primaryLuminance = primary.computeLuminance();
    final containerLuminance = primaryContainer.computeLuminance();
    final luminanceDiff = (primaryLuminance - containerLuminance).abs();
    
    // If colors are too similar (low contrast), use onSurface instead
    if (luminanceDiff < 0.2) {
      return theme.colorScheme.onSurface;
    }
    
    // Otherwise use primary for colorful highlight
    return primary;
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
              : PullToSearch(
                  onSearchTriggered: widget.onOpenSearch ?? () {},
                  triggerThreshold: 80.0,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                      // Album cover with artistic background
                      (Platform.isWindows || Platform.isLinux || Platform.isMacOS) 
                          ? SizedBox(
                              height: 300,
                              width: double.infinity,
                              child: MoveWindow(
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    // Artistic background effect
                                    ArtisticBackground(
                                      coverArtId: widget.album.coverArt,
                                      albumId: widget.album.id,
                                      height: 300,
                                    ),
                                    // Album cover overlay
                                    Container(
                                      height: 300,
                                      width: double.infinity,
                                      alignment: Alignment.center,
                                      child: Container(
                                        width: 200,
                                        height: 200,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(8),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(0.3),
                                              blurRadius: 20,
                                              offset: const Offset(0, 10),
                                            ),
                                          ],
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: widget.album.coverArt != null
                                              ? CachedCoverImage(
                                                  key: ValueKey('album_${widget.album.id}_${widget.album.coverArt}'),
                                                  coverArtId: widget.album.coverArt,
                                                  size: 600, // Higher res for HiDPI displays
                                                )
                                              : Container(
                                                  color: Theme.of(context).colorScheme.surfaceVariant,
                                                  child: const Icon(Icons.album, size: 80),
                                                ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : Stack(
                              children: [
                                // Artistic background effect
                                ArtisticBackground(
                                  coverArtId: widget.album.coverArt,
                                  albumId: widget.album.id,
                                  height: 300,
                                ),
                                // Album cover overlay
                                Container(
                                  height: 300,
                                  width: double.infinity,
                                  alignment: Alignment.center,
                                  child: Container(
                                    width: 200,
                                    height: 200,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.3),
                                          blurRadius: 20,
                                          offset: const Offset(0, 10),
                                        ),
                                      ],
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: widget.album.coverArt != null
                                          ? CachedCoverImage(
                                              key: ValueKey('album_${widget.album.id}_${widget.album.coverArt}'),
                                              coverArtId: widget.album.coverArt,
                                              size: 600, // Higher res for HiDPI displays
                                            )
                                          : Container(
                                              color: Theme.of(context).colorScheme.surfaceVariant,
                                              child: const Icon(Icons.album, size: 80),
                                            ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                      
                      // Album info
                      Container(
                        width: double.infinity,
                        color: Theme.of(context).colorScheme.surface,
                        child: Padding(
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
                                      builder: (context) => ArtistDetailScreen(
                                        artist: artist,
                                        onOpenSearch: widget.onOpenSearch,
                                      ),
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
                                const Spacer(),
                                Consumer<NetworkProvider>(
                                  builder: (context, networkProvider, _) {
                                    return Consumer<AlbumDownloadService?>(
                                      builder: (context, albumDownloadService, _) {
                                        if (albumDownloadService == null) {
                                          return const SizedBox.shrink();
                                        }
                                        // Determine button state
                                        final isDownloading = _albumDownloadProgress?.status == AlbumDownloadStatus.downloading;
                                        final isPaused = _albumDownloadProgress?.status == AlbumDownloadStatus.paused;
                                        final isCompleted = _albumDownloadProgress?.status == AlbumDownloadStatus.completed;
                                        final progress = _albumDownloadProgress?.progress ?? 0;

                                        // For now, consider album fully downloaded only if download completed
                                        // User can trigger delete by pressing the delete button when download completes
                                        final isFullyDownloaded = isCompleted;

                                        Icon icon;
                                        Color iconColor;
                                        String tooltip;

                                        if (isFullyDownloaded) {
                                          icon = Icon(Icons.delete, color: Theme.of(context).colorScheme.primary, size: 20);
                                          iconColor = Theme.of(context).colorScheme.primary;
                                          tooltip = 'Remove from cache';
                                        } else if (isDownloading) {
                                          icon = Icon(Icons.pause, color: Theme.of(context).colorScheme.primary, size: 20);
                                          iconColor = Theme.of(context).colorScheme.primary;
                                          tooltip = 'Pause downloading (${progress}%)';
                                        } else if (isPaused) {
                                          icon = Icon(Icons.play_arrow, color: Theme.of(context).colorScheme.primary, size: 20);
                                          iconColor = Theme.of(context).colorScheme.primary;
                                          tooltip = 'Resume downloading (${progress}%)';
                                        } else {
                                          icon = Icon(Icons.download, color: Theme.of(context).colorScheme.onSurface, size: 20);
                                          iconColor = Theme.of(context).colorScheme.onSurface;
                                          tooltip = 'Download for offline';
                                        }

                                        return GestureDetector(
                                          onTap: networkProvider.isOffline ? null : () => _handleDownloadButtonPress(false),
                                          onLongPress: networkProvider.isOffline ? null : () => _handleDownloadButtonPress(true),
                                          child: Stack(
                                            alignment: Alignment.center,
                                            children: [
                                              // Progress indicator ring
                                              if (isDownloading || isPaused)
                                                SizedBox(
                                                  width: 36,
                                                  height: 36,
                                                  child: CircularProgressIndicator(
                                                    value: progress / 100,
                                                    strokeWidth: 2.5,
                                                    backgroundColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
                                                    valueColor: AlwaysStoppedAnimation<Color>(
                                                      Theme.of(context).colorScheme.primary,
                                                    ),
                                                  ),
                                                ),
                                              IconButton(
                                                icon: icon,
                                                onPressed: networkProvider.isOffline ? null : () => _handleDownloadButtonPress(false),
                                                tooltip: tooltip,
                                                style: IconButton.styleFrom(
                                                  padding: const EdgeInsets.all(6),
                                                  minimumSize: const Size(32, 32),
                                                  shape: const CircleBorder(),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    );
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
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
                                final playingTrackColor = isCurrentSong ? _getPlayingTrackColor(context) : null;

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
                                                color: playingTrackColor,
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
                                          color: playingTrackColor,
                                          fontWeight: isCurrentSong ? FontWeight.bold : null,
                                        ),
                                      ),
                                      subtitle: Row(
                                        children: [
                                          if (song.isCached) ...[
                                            Icon(
                                              Icons.check_circle,
                                              size: 14,
                                              color: Theme.of(context).colorScheme.primary,
                                            ),
                                            const SizedBox(width: 4),
                                          ],
                                          Expanded(
                                            child: Text(
                                              song.artist ?? 'Unknown Artist',
                                              style: TextStyle(
                                                color: playingTrackColor?.withOpacity(0.8),
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (song.suffix != null || song.bitRate != null)
                                            Container(
                                              width: 60,
                                              margin: const EdgeInsets.only(right: 20),
                                              child: Column(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                crossAxisAlignment: CrossAxisAlignment.center,
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  if (song.suffix != null)
                                                    Text(
                                                      song.suffix!.toUpperCase(),
                                                      style: TextStyle(
                                                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.w500,
                                                      ),
                                                    ),
                                                  if (song.suffix != null && song.bitRate != null && song.bitRate! > 0)
                                                    Builder(
                                                      builder: (context) {
                                                        final format = song.suffix?.toLowerCase();
                                                        final isLossless = format == 'flac' || format == 'alac' || 
                                                                           format == 'wav' || format == 'aiff';
                                                        
                                                        String text;
                                                        if (isLossless) {
                                                          // For lossless, show bit depth/sample rate
                                                          // TODO: We need to get actual bit depth and sample rate from API
                                                          // For now, estimate based on bitrate
                                                          if (song.bitRate! > 4000) {
                                                            text = '24/96';
                                                          } else if (song.bitRate! > 2000) {
                                                            text = '24/48';
                                                          } else {
                                                            text = '16/44.1';
                                                          }
                                                        } else {
                                                          // For lossy, show just the bitrate number
                                                          text = '${song.bitRate}';
                                                        }
                                                        
                                                        return Text(
                                                          text,
                                                          style: TextStyle(
                                                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                                                            fontSize: 10,
                                                            fontWeight: FontWeight.w500,
                                                          ),
                                                        );
                                                      },
                                                    ),
                                                ],
                                              ),
                                            ),
                                          Text(
                                            song.formattedDuration,
                                            style: TextStyle(
                                              color: playingTrackColor ?? 
                                                     Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
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

  Future<void> _handleDownloadButtonPress(bool isLongPress) async {
    final albumDownloadService = context.read<AlbumDownloadService?>();
    if (albumDownloadService == null) return;
    final isDownloading = _albumDownloadProgress?.status == AlbumDownloadStatus.downloading;
    final isPaused = _albumDownloadProgress?.status == AlbumDownloadStatus.paused;
    final isCompleted = _albumDownloadProgress?.status == AlbumDownloadStatus.completed;
    final isFullyDownloaded = isCompleted;

    if (isFullyDownloaded) {
      // Always show confirmation modal for delete
      if (isLongPress || true) { // For downloaded albums, any press should show confirmation
        await _showDeleteConfirmation();
      }
    } else if (isDownloading) {
      if (isLongPress) {
        // Long press while downloading = cancel
        await _showCancelConfirmation();
      } else {
        // Short press while downloading = pause
        await albumDownloadService.pauseDownload(_albumDownloadProgress!.id);
      }
    } else if (isPaused) {
      if (isLongPress) {
        // Long press while paused = cancel
        await _showCancelConfirmation();
      } else {
        // Short press while paused = resume
        await albumDownloadService.resumeDownload(_albumDownloadProgress!.id);
      }
    } else {
      // Not downloaded yet - start download
      await _startAlbumDownload();
    }
  }

  Future<void> _startAlbumDownload() async {
    if (_songs == null || _songs!.isEmpty) {
      if (kDebugMode) {
        print('[AlbumDetailScreen] Error: No songs found for album');
      }
      return;
    }

    if (kDebugMode) {
      print('[AlbumDetailScreen] Starting download for album: ${widget.album.name}');
    }

    final albumDownloadService = context.read<AlbumDownloadService?>();
    if (albumDownloadService == null) return;

    // Start the download - subscription is already set up in initState
    await albumDownloadService.downloadAlbum(widget.album, _songs!);
    if (kDebugMode) {
      print('[AlbumDetailScreen] Started download for album: ${widget.album.name}');
    }
  }

  Future<void> _showDeleteConfirmation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove from cache'),
        content: Text('Are you sure you want to remove "${widget.album.name}" from offline storage?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deleteAlbumFromCache();
    }
  }

  Future<void> _showCancelConfirmation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel download'),
        content: Text('Are you sure you want to cancel the download for "${widget.album.name}"? This will delete any partially downloaded files.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep downloading'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cancel download'),
          ),
        ],
      ),
    );

    if (confirmed == true && _albumDownloadProgress != null) {
      final albumDownloadService = context.read<AlbumDownloadService?>();
      await albumDownloadService?.cancelDownload(_albumDownloadProgress!.id);
      setState(() {
        _albumDownloadProgress = null;
      });
    }
  }

  Future<void> _deleteAlbumFromCache() async {
    if (kDebugMode) {
      print('[AlbumDetailScreen] Removing album ${widget.album.name} from cache');
    }

    // Get all song IDs for this album
    final songIds = _songs?.map((song) => song.id).toList() ?? [];

    // Remove from audio cache and update song cache status
    for (final songId in songIds) {
      try {
        // Get cached path and delete file
        final cachedPath = await DatabaseHelper.getAnyAudioCachePath(songId);
        if (cachedPath != null) {
          final file = File(cachedPath);
          if (await file.exists()) {
            await file.delete();
          }
        }

        // Remove from audio cache database
        final db = await DatabaseHelper.database;
        await db.delete('audio_cache', where: 'song_id = ?', whereArgs: [songId]);

        // Update song cache status
        await DatabaseHelper.updateSongCacheStatus(songId, false);
      } catch (e) {
        print('Error removing song $songId from cache: $e');
      }
    }

    // Remove album download record entirely
    if (_albumDownloadProgress != null) {
      final downloadId = _albumDownloadProgress!.id;
      final albumDownloadService = context.read<AlbumDownloadService?>();
      await albumDownloadService?.cancelDownload(downloadId);
      // Also delete the record from database to ensure clean state
      await DatabaseHelper.deleteAlbumDownload(downloadId);
    }

    setState(() {
      _albumDownloadProgress = null;
    });

    // Reload songs to update isCached status
    await _loadAlbumDetails();

    if (kDebugMode) {
      print('[AlbumDetailScreen] Album removed from cache successfully');
    }
  }

  @override
  void dispose() {
    _albumDownloadSubscription?.cancel();
    super.dispose();
  }
}