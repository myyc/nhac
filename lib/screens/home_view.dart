import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/auth_provider.dart';
import '../providers/cache_provider.dart';
import '../models/album.dart';
import 'album_detail_screen.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  List<Album>? _recentlyAdded;
  List<Album>? _mostPlayed;
  List<Album>? _random;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final api = context.read<AuthProvider>().api;
    if (api == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final futures = await Future.wait([
        api.getAlbumList2(type: 'newest', size: 10),
        api.getAlbumList2(type: 'frequent', size: 10),
        api.getAlbumList2(type: 'random', size: 10),
      ]);

      if (mounted) {
        setState(() {
          _recentlyAdded = futures[0];
          _mostPlayed = futures[1];
          _random = futures[2];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildAlbumCard(Album album, {double size = 160}) {
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
      child: Container(
        width: size,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: Theme.of(context).colorScheme.surfaceVariant,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: album.coverArt != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        key: ValueKey('home_${album.id}_${album.coverArt}'),
                        imageUrl: cacheProvider.getCoverArtUrl(album.coverArt, size: 320),
                        cacheKey: 'cover_${album.id}_${album.coverArt}_320',
                        fit: BoxFit.cover,
                        memCacheWidth: 320,
                        memCacheHeight: 320,
                        placeholder: (context, url) => 
                            const Center(child: Icon(Icons.album, size: 40)),
                        errorWidget: (context, url, error) => 
                            const Center(child: Icon(Icons.album, size: 40)),
                      ),
                    )
                  : const Center(child: Icon(Icons.album, size: 40)),
            ),
            const SizedBox(height: 8),
            Text(
              album.name,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (album.artist != null)
              Text(
                album.artist!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, List<Album>? albums) {
    if (albums == null || albums.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        SizedBox(
          height: 210,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: albums.length,
            itemBuilder: (context, index) => _buildAlbumCard(albums[index]),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        children: [
          const SizedBox(height: 16),
          
          // Welcome message
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _getGreeting(),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 24),
          
          _buildSection('Recently Added', _recentlyAdded),
          _buildSection('Most Played', _mostPlayed),
          _buildSection('Discover', _random),
          
          const SizedBox(height: 80), // Space for player bar
        ],
      ),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return 'Good morning';
    } else if (hour < 17) {
      return 'Good afternoon';
    } else {
      return 'Good evening';
    }
  }
}