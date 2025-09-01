import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:io' show Platform;
import '../providers/auth_provider.dart';
import '../providers/cache_provider.dart';
import '../models/album.dart';
import 'album_detail_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  Map<String, List<Album>>? _albumsByArtist;
  List<String>? _sortedArtists;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAlbums();
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
    
    return RefreshIndicator(
      onRefresh: () => _loadAlbums(forceRefresh: true),
      child: GridView.builder(
        padding: EdgeInsets.fromLTRB(16, topPadding, 16, 16),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 200,
          childAspectRatio: 0.8,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemCount: allAlbums.length,
        itemBuilder: (context, index) => _buildAlbumCard(allAlbums[index]),
      ),
    );
  }
}