import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:io' show Platform;
import '../providers/auth_provider.dart';
import '../providers/cache_provider.dart';
import '../providers/network_provider.dart';
import '../models/album.dart';
import '../widgets/pull_to_search.dart';
import '../widgets/pull_to_refresh.dart';
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

class _LibraryScreenState extends State<LibraryScreen> {
  Map<String, List<Album>>? _albumsByArtist;
  List<String>? _sortedArtists;
  bool _isLoading = true;
  String? _error;
  StreamSubscription<LibraryChangeEvent>? _libraryUpdateSubscription;

  @override
  void initState() {
    super.initState();
    _loadAlbums();
    _listenForLibraryUpdates();
  }

  @override
  void dispose() {
    _libraryUpdateSubscription?.cancel();
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

  Future<void> _handleRefresh() async {
    final cacheProvider = context.read<CacheProvider>();
    final networkProvider = context.read<NetworkProvider>();

    if (!networkProvider.isOffline) {
      // Sync library when refreshing
      await cacheProvider.syncRecentlyAdded();
    }

    // Reload data
    await _loadAlbums(forceRefresh: true);
  }

  Future<void> _loadAlbums({bool forceRefresh = false}) async {
    final cacheProvider = context.read<CacheProvider>();
    final networkProvider = context.read<NetworkProvider>();

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Load all albums from cache or API, with offline awareness
      final albums = await cacheProvider.getAlbumsOffline(forceRefresh: forceRefresh && !networkProvider.isOffline);
      
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
            builder: (context) => AlbumDetailScreen(
              album: album,
              onOpenSearch: widget.onOpenSearch,
            ),
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
    
    // Always wrap with PullToRefresh
    Widget content = PullToRefresh(
      onRefresh: _handleRefresh,
      child: (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
          ? MoveWindow(child: gridView)
          : gridView,
    );

    // Add pull-to-search wrapper on mobile
    if ((Platform.isAndroid || Platform.isIOS) && widget.onOpenSearch != null) {
      content = PullToSearch(
        onSearchTriggered: widget.onOpenSearch!,
        triggerThreshold: 80.0,
        child: content,
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