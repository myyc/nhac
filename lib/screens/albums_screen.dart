import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/cache_provider.dart';
import '../providers/network_provider.dart';
import '../models/album.dart';
import '../widgets/cached_cover_image.dart';
import '../widgets/pull_to_search.dart';
import 'album_detail_screen.dart';

class AlbumsScreen extends StatefulWidget {
  final VoidCallback? onOpenSearch;

  const AlbumsScreen({super.key, this.onOpenSearch});

  @override
  State<AlbumsScreen> createState() => _AlbumsScreenState();
}

class _AlbumsScreenState extends State<AlbumsScreen> {
  List<Album>? _albums;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAlbums();
  }

  Future<void> _loadAlbums() async {
    final cacheProvider = context.read<CacheProvider>();

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Use offline-aware method when offline
      final albums = await cacheProvider.getAlbumsOffline();
      if (mounted) {
        setState(() {
          _albums = albums;
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

  @override
  Widget build(BuildContext context) {
    final api = context.read<AuthProvider>().api;
    final cacheProvider = context.read<CacheProvider>();
    
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
              onPressed: _loadAlbums,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_albums == null || _albums!.isEmpty) {
      return const Center(
        child: Text('No albums found'),
      );
    }

    return PullToSearch(
      onSearchTriggered: widget.onOpenSearch ?? () {},
      triggerThreshold: 80.0,
      child: RefreshIndicator(
        onRefresh: _loadAlbums,
        child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 200,
          childAspectRatio: 0.85,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemCount: _albums!.length,
        itemBuilder: (context, index) {
          final album = _albums![index];
          
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
                    child: CachedCoverImage(
                      coverArtId: album.coverArt,
                      borderRadius: BorderRadius.circular(8),
                      width: double.infinity,
                      height: double.infinity,
                      placeholder: const Center(child: CircularProgressIndicator()),
                      errorWidget: const Center(child: Icon(Icons.album, size: 48)),
                    ),
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
        },
      ),
      ),
    );
  }
}