import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:io' show Platform;
import '../providers/auth_provider.dart';
import '../providers/cache_provider.dart';
import '../models/album.dart';
import '../services/library_scan_service.dart';
import 'album_detail_screen.dart';

class LibraryScreen extends StatefulWidget {
  final VoidCallback? onNavigateToHome;
  final VoidCallback? onOpenSearch;
  
  const LibraryScreen({
    super.key, 
    this.onNavigateToHome,
    this.onOpenSearch,
  });

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> with SingleTickerProviderStateMixin {
  Map<String, List<Album>>? _albumsByArtist;
  List<String>? _sortedArtists;
  bool _isLoading = true;
  String? _error;
  StreamSubscription<LibraryChangeEvent>? _libraryUpdateSubscription;
  
  // Pull to search animation
  late AnimationController _pullController;
  double _dragOffset = 0.0;
  bool _isSearchTriggered = false;

  @override
  void initState() {
    super.initState();
    _pullController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _loadAlbums();
    _listenForLibraryUpdates();
  }
  
  @override
  void dispose() {
    _libraryUpdateSubscription?.cancel();
    _pullController.dispose();
    super.dispose();
  }
  
  void _listenForLibraryUpdates() {
    final cacheProvider = context.read<CacheProvider>();
    _libraryUpdateSubscription = cacheProvider.libraryUpdates.listen((event) {
      if (event.hasChanges && mounted) {
        // Simply reload albums when library changes are detected
        _loadAlbums(forceRefresh: false);
      }
    });
  }

  Future<void> _loadAlbums({bool forceRefresh = false}) async {
    final cacheProvider = context.read<CacheProvider>();
    
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Load all albums from cache or API
      final albums = await cacheProvider.getAlbums(forceRefresh: forceRefresh);
      
      // Group albums by artist
      final albumsByArtist = <String, List<Album>>{};
      for (final album in albums) {
        final artist = album.artist ?? 'Unknown Artist';
        albumsByArtist.putIfAbsent(artist, () => []).add(album);
      }
      
      // Sort albums within each artist by name
      for (final albumList in albumsByArtist.values) {
        albumList.sort((a, b) => a.name.compareTo(b.name));
      }
      
      // Sort artist names
      final sortedArtists = albumsByArtist.keys.toList()..sort();
      
      if (mounted) {
        setState(() {
          _albumsByArtist = albumsByArtist;
          _sortedArtists = sortedArtists;
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

  Widget _buildAlbumCard(Album album) {
    final cacheProvider = context.read<CacheProvider>();
    
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AlbumDetailScreen(album: album),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: Theme.of(context).colorScheme.surfaceVariant,
              ),
              child: album.coverArt != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        key: ValueKey('library_${album.id}_${album.coverArt}'),
                        imageUrl: cacheProvider.getCoverArtUrl(album.coverArt),
                        cacheKey: 'cover_${album.id}_${album.coverArt}_300',
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        placeholder: (context, url) => 
                            const Center(child: Icon(Icons.album, size: 48)),
                        errorWidget: (context, url, error) => 
                            const Center(child: Icon(Icons.album, size: 48)),
                      ),
                    )
                  : const Center(child: Icon(Icons.album, size: 48)),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            album.name,
            style: Theme.of(context).textTheme.bodyMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            album.artist ?? 'Unknown Artist',
            style: Theme.of(context).textTheme.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Error: $_error'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => _loadAlbums(forceRefresh: true),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_albumsByArtist == null || _albumsByArtist!.isEmpty) {
      return const Center(
        child: Text('No albums found'),
      );
    }

    // Flatten albums list but keep sorted by artist -> album
    final allAlbums = <Album>[];
    for (final artist in _sortedArtists!) {
      allAlbums.addAll(_albumsByArtist![artist]!);
    }

    // Add safe top margin on mobile
    final topPadding = (Platform.isAndroid || Platform.isIOS) 
        ? MediaQuery.of(context).padding.top + 16 
        : 16.0;
    
    Widget gridView = GridView.builder(
      padding: EdgeInsets.fromLTRB(16, topPadding, 16, 16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        childAspectRatio: 0.8,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: allAlbums.length,
      itemBuilder: (context, index) => _buildAlbumCard(allAlbums[index]),
    );
    
    Widget content = (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
        ? MoveWindow(child: gridView)
        : gridView;
    
    // On mobile, add pull-to-search with elastic animation
    if ((Platform.isAndroid || Platform.isIOS) && widget.onOpenSearch != null) {
      content = NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is OverscrollNotification) {
            if (notification.overscroll < 0) {
              setState(() {
                _dragOffset = (_dragOffset - notification.overscroll).clamp(0.0, 150.0);
              });
              
              // Trigger search at threshold
              if (_dragOffset > 100 && !_isSearchTriggered) {
                _isSearchTriggered = true;
                // Haptic feedback
                HapticFeedback.mediumImpact();
                widget.onOpenSearch!();
              }
            }
          } else if (notification is ScrollEndNotification) {
            // Animate spring back on scroll end
            if (_dragOffset > 0) {
              _pullController.animateTo(0.0).then((_) {
                if (mounted) {
                  setState(() {
                    _dragOffset = 0.0;
                    _isSearchTriggered = false;
                  });
                }
              });
            }
          }
          return false;
        },
        child: Stack(
          children: [
            // Search indicator that appears when pulling
            if (_dragOffset > 0)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: _dragOffset,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                  ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedRotation(
                          duration: const Duration(milliseconds: 200),
                          turns: _dragOffset / 100 * 0.5,
                          child: Icon(
                            Icons.search,
                            size: 32,
                            color: _dragOffset > 100 
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _dragOffset > 100 ? 'Release to search' : 'Pull to search',
                          style: TextStyle(
                            color: _dragOffset > 100 
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            // Main content with transform
            AnimatedBuilder(
              animation: _pullController,
              builder: (context, child) {
                final animatedOffset = _dragOffset * (1 - _pullController.value);
                return Transform.translate(
                  offset: Offset(0, animatedOffset * 0.8),
                  child: child,
                );
              },
              child: content,
            ),
          ],
        ),
      );
    }
    
    // For Android, wrap with WillPopScope to intercept back gesture
    if (Platform.isAndroid && widget.onNavigateToHome != null) {
      return WillPopScope(
        onWillPop: () async {
          // Navigate to home instead of popping
          widget.onNavigateToHome!();
          return false; // Prevent default back behavior
        },
        child: content,
      );
    }
    
    return content;
  }
}