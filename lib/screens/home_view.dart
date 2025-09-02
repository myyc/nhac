import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:io' show Platform;
import '../providers/auth_provider.dart';
import '../providers/cache_provider.dart';
import '../models/album.dart';
import 'album_detail_screen.dart';

class HomeView extends StatefulWidget {
  final VoidCallback? onOpenSearch;
  
  const HomeView({super.key, this.onOpenSearch});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> with SingleTickerProviderStateMixin {
  List<Album>? _recentlyAdded;
  List<Album>? _mostPlayed;
  List<Album>? _random;
  bool _isLoading = true;
  
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
    _loadData();
  }
  
  @override
  void dispose() {
    _pullController.dispose();
    super.dispose();
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
    
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AlbumDetailScreen(album: album),
            ),
          );
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          width: size,
          margin: const EdgeInsets.only(right: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: Theme.of(context).colorScheme.surfaceVariant,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                          spreadRadius: -2,
                        ),
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                          spreadRadius: -1,
                        ),
                      ],
                    ),
                    child: album.coverArt != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: CachedNetworkImage(
                              key: ValueKey('home_${album.id}_${album.coverArt}'),
                              imageUrl: cacheProvider.getCoverArtUrl(album.coverArt, size: 320),
                              cacheKey: 'cover_${album.id}_${album.coverArt}_320',
                              fit: BoxFit.cover,
                              memCacheWidth: 320,
                              memCacheHeight: 320,
                              placeholder: (context, url) => Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  color: Theme.of(context).colorScheme.surfaceVariant,
                                ),
                                child: Center(
                                  child: Icon(
                                    Icons.album,
                                    size: 40,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.4),
                                  ),
                                ),
                              ),
                              errorWidget: (context, url, error) => Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  color: Theme.of(context).colorScheme.surfaceVariant,
                                ),
                                child: Center(
                                  child: Icon(
                                    Icons.album,
                                    size: 40,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.4),
                                  ),
                                ),
                              ),
                            ),
                          )
                        : Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: Theme.of(context).colorScheme.surfaceVariant,
                            ),
                            child: Center(
                              child: Icon(
                                Icons.album,
                                size: 40,
                                color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.4),
                              ),
                            ),
                          ),
                  ),
                  // Subtle gradient overlay
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(12),
                          bottomRight: Radius.circular(12),
                        ),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withOpacity(0.1),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                album.name,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.1,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              if (album.artist != null)
                Text(
                  album.artist!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.65),
                    letterSpacing: 0,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
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
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              TextButton(
                onPressed: () {
                  // TODO: Navigate to full section view
                },
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'View all',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 220,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: albums.length,
            itemBuilder: (context, index) => _buildAlbumCard(albums[index]),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    Widget listView = ListView(
        children: [
          const SizedBox(height: 16),
          
          // Welcome message
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _getGreeting(),
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'What would you like to listen to today?',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                    letterSpacing: -0.1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          
          _buildSection('Recently Added', _recentlyAdded),
          _buildSection('Most Played', _mostPlayed),
          _buildSection('Discover', _random),
          
          const SizedBox(height: 80), // Space for player bar
        ],
      );
    
    // On mobile, add pull-to-search with elastic animation
    if ((Platform.isAndroid || Platform.isIOS) && widget.onOpenSearch != null) {
      return NotificationListener<ScrollNotification>(
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
              child: listView,
            ),
          ],
        ),
      );
    }
    
    return listView;
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