import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'dart:io' show Platform;
import '../providers/auth_provider.dart';
import '../providers/cache_provider.dart';
import '../providers/network_provider.dart';
import '../models/album.dart';
import '../widgets/offline_indicator.dart';
import '../widgets/cached_cover_image.dart';
import '../widgets/pull_to_search.dart';
import '../widgets/pull_to_refresh.dart';
import '../services/library_scan_service.dart';
import '../services/database_helper.dart';
import 'album_detail_screen.dart';

class HomeView extends StatefulWidget {
  final VoidCallback? onOpenSearch;
  
  const HomeView({super.key, this.onOpenSearch});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  List<Album>? _recentlyAdded;
  List<Album>? _mostPlayed;
  List<Album>? _random;
  List<Album>? _popularOffline;
  Set<String> _cachedAlbumIds = {};
  bool _isLoading = true;
  StreamSubscription<LibraryChangeEvent>? _libraryUpdateSubscription;
  NetworkProvider? _networkProvider;

  @override
  void initState() {
    super.initState();
    _loadData();
    _listenForLibraryUpdates();
    // Listen for network state changes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _networkProvider = context.read<NetworkProvider>();
      _networkProvider?.addListener(_onNetworkStateChanged);
    });
  }

  void _onNetworkStateChanged() {
    if (mounted) {
      // Reload data without showing loading spinner
      _loadData(showLoading: false);
    }
  }

  Future<void> _handleRefresh() async {
    final cacheProvider = context.read<CacheProvider>();
    final networkProvider = context.read<NetworkProvider>();

    if (!networkProvider.isOffline) {
      // Sync library when refreshing
      await cacheProvider.syncRecentlyAdded();
    }

    // Reload data
    await _loadData(forceRefresh: true, showLoading: false);
  }

  @override
  void dispose() {
    _libraryUpdateSubscription?.cancel();
    _networkProvider?.removeListener(_onNetworkStateChanged);
    super.dispose();
  }

  void _listenForLibraryUpdates() {
    final cacheProvider = context.read<CacheProvider>();
    _libraryUpdateSubscription = cacheProvider.libraryUpdates.listen((event) {
      if (event.hasChanges && mounted) {
        // Simply refresh the data to show new albums
        _loadData(showLoading: false);
      }
    });
  }

  Future<void> _loadData({bool forceRefresh = false, bool showLoading = true}) async {
    final api = context.read<AuthProvider>().api;
    final cacheProvider = context.read<CacheProvider>();
    final networkProvider = context.read<NetworkProvider>();

    debugPrint('[HomeView] _loadData called - api: ${api != null}, forceRefresh: $forceRefresh, showLoading: $showLoading');

    // Only show loading spinner on first load (when no data exists)
    if (showLoading && _recentlyAdded == null) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      List<Album> recentlyAdded = [];
      List<Album> mostPlayed = [];
      List<Album> random = [];
      List<Album> popularOffline = [];

      // Always load cached album IDs for opacity
      final cachedAlbumIds = await DatabaseHelper.getCachedAlbumIds();
      debugPrint('[HomeView] Cached album IDs: ${cachedAlbumIds.length}');

      // Always load popular offline albums (for when we switch to offline mode)
      popularOffline = await DatabaseHelper.getPopularOfflineAlbums();
      debugPrint('[HomeView] Popular offline albums: ${popularOffline.length}');

      // ALWAYS try cache first - this ensures we show something immediately
      try {
        recentlyAdded = await cacheProvider.getRecentlyAdded(forceRefresh: false);
        debugPrint('[HomeView] Recently added from cache: ${recentlyAdded.length}');
      } catch (e) {
        debugPrint('[HomeView] Error loading recently added: $e');
      }

      // If cache is empty, try getting all albums
      if (recentlyAdded.isEmpty) {
        debugPrint('[HomeView] Cache empty, trying all albums...');
        try {
          final allAlbums = await cacheProvider.getAlbums(forceRefresh: false);
          debugPrint('[HomeView] All albums from cache: ${allAlbums.length}');
          allAlbums.sort((a, b) => b.id.compareTo(a.id));
          recentlyAdded = allAlbums.take(18).toList();
        } catch (e) {
          debugPrint('[HomeView] Error loading all albums: $e');
        }
      }

      // Update UI with cached data immediately
      debugPrint('[HomeView] Setting state with ${recentlyAdded.length} albums, mounted: $mounted');
      if (mounted && recentlyAdded.isNotEmpty) {
        setState(() {
          _recentlyAdded = recentlyAdded;
          _popularOffline = popularOffline;
          _cachedAlbumIds = cachedAlbumIds;
          _isLoading = false;
        });
      }

      // Then try to refresh from network if online and not forced offline
      if (!networkProvider.isOffline && api != null) {
        try {
          final freshRecent = await cacheProvider.getRecentlyAdded(forceRefresh: forceRefresh);
          if (freshRecent.isNotEmpty) recentlyAdded = freshRecent;
        } catch (e) {
          // Keep cached data on error
        }

        try {
          mostPlayed = await api.getAlbumList2(type: 'frequent', size: 18);
        } catch (e) {
          mostPlayed = _mostPlayed ?? [];
        }

        try {
          random = await api.getAlbumList2(type: 'random', size: 18);
        } catch (e) {
          random = _random ?? [];
        }
      }

      if (mounted) {
        setState(() {
          _recentlyAdded = recentlyAdded;
          _mostPlayed = mostPlayed;
          _random = random;
          _popularOffline = popularOffline;
          _cachedAlbumIds = cachedAlbumIds;
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

  Widget _buildSection(String title, List<Album>? albums, {required bool isOffline}) {
    if (albums == null || albums.isEmpty) return const SizedBox.shrink();

    // Calculate scroll amount: 3 albums * (170 width + 16 margin)
    const scrollAmount = 3 * (170.0 + 16.0);

    return _AlbumSection(
      title: title,
      albums: albums,
      scrollAmount: scrollAmount,
      isOffline: isOffline,
      cachedAlbumIds: _cachedAlbumIds,
      onAlbumTap: (album) {
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
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Consumer<NetworkProvider>(
      builder: (context, networkProvider, _) {
        final isOffline = networkProvider.isOffline;

        Widget listView = ListView(
          children: [
            const SizedBox(height: 16),

            // Welcome message with offline indicator
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          _getGreeting(),
                          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.8,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ],
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

            _buildSection('Recently Added', _recentlyAdded, isOffline: isOffline),
            _buildSection('Most Played', _mostPlayed, isOffline: isOffline),
            // Show "Popular Offline" instead of "Discover" when offline
            if (isOffline)
              _buildSection('Popular Offline', _popularOffline, isOffline: isOffline)
            else
              _buildSection('Discover', _random, isOffline: isOffline),

            const SizedBox(height: 80), // Space for player bar
          ],
        );

        // Wrap the entire ListView with MoveWindow for desktop
        if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
          listView = MoveWindow(child: listView);
        }

        // On mobile, use PullToSearch only (no refresh - search replaces it)
        if ((Platform.isAndroid || Platform.isIOS) && widget.onOpenSearch != null) {
          return PullToSearch(
            onSearchTriggered: widget.onOpenSearch!,
            child: listView,
          );
        }

        // On desktop, use PullToRefresh
        return PullToRefresh(
          onRefresh: _handleRefresh,
          child: listView,
        );
      },
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

class _AlbumSection extends StatefulWidget {
  final String title;
  final List<Album> albums;
  final double scrollAmount;
  final Function(Album) onAlbumTap;
  final bool isOffline;
  final Set<String> cachedAlbumIds;

  const _AlbumSection({
    required this.title,
    required this.albums,
    required this.scrollAmount,
    required this.onAlbumTap,
    required this.isOffline,
    required this.cachedAlbumIds,
  });

  @override
  State<_AlbumSection> createState() => _AlbumSectionState();
}

class _AlbumSectionState extends State<_AlbumSection> {
  final ScrollController _scrollController = ScrollController();
  bool _canScrollLeft = false;
  bool _canScrollRight = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateScrollButtons);
    // Check initial scroll position after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateScrollButtons();
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateScrollButtons);
    _scrollController.dispose();
    super.dispose();
  }

  void _updateScrollButtons() {
    if (!mounted) return;
    
    final bool newCanScrollLeft = _scrollController.hasClients && 
        _scrollController.position.pixels > 5; // Small threshold to handle floating point
    final bool newCanScrollRight = _scrollController.hasClients && 
        _scrollController.position.pixels < (_scrollController.position.maxScrollExtent - 5);
    
    if (newCanScrollLeft != _canScrollLeft || newCanScrollRight != _canScrollRight) {
      setState(() {
        _canScrollLeft = newCanScrollLeft;
        _canScrollRight = newCanScrollRight;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              GestureDetector(
                onDoubleTap: () {
                  // Prevent double-tap from bubbling to window
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ArrowButton(
                      icon: Icons.chevron_left,
                      isEnabled: _canScrollLeft,
                      onTap: () {
                        if (_canScrollLeft) {
                          _scrollController.animateTo(
                            _scrollController.offset - widget.scrollAmount,
                            duration: const Duration(milliseconds: 150),
                            curve: Curves.easeOutCubic,
                          );
                        }
                      },
                    ),
                    const SizedBox(width: 2),
                    _ArrowButton(
                      icon: Icons.chevron_right,
                      isEnabled: _canScrollRight,
                      onTap: () {
                        if (_canScrollRight) {
                          _scrollController.animateTo(
                            _scrollController.offset + widget.scrollAmount,
                            duration: const Duration(milliseconds: 150),
                            curve: Curves.easeOutCubic,
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 220,
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              // Enable drag scrolling with mouse
              dragDevices: {
                PointerDeviceKind.mouse,
                PointerDeviceKind.touch,
                PointerDeviceKind.trackpad,
              },
            ),
            child: ListView.builder(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(left: 20, right: 20),
              itemCount: widget.albums.length,
              itemBuilder: (context, index) {
                final album = widget.albums[index];
                final isCached = widget.cachedAlbumIds.contains(album.id);
                return _AlbumCard(
                  album: album,
                  onTap: () => widget.onAlbumTap(album),
                  isLast: index == widget.albums.length - 1,
                  isOffline: widget.isOffline,
                  isCached: isCached,
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}

class _AlbumCard extends StatelessWidget {
  final Album album;
  final VoidCallback onTap;
  final double size;
  final bool isLast;
  final bool isOffline;
  final bool isCached;

  const _AlbumCard({
    required this.album,
    required this.onTap,
    this.size = 160,
    this.isLast = false,
    required this.isOffline,
    required this.isCached,
  });

  @override
  Widget build(BuildContext context) {
    // When offline, non-cached albums appear faded
    final opacity = (isOffline && !isCached) ? 0.4 : 1.0;

    return Opacity(
      opacity: opacity,
      child: MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          width: size,
          margin: EdgeInsets.only(right: isLast ? 0 : 16),
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
                    child: CachedCoverImage(
                      key: ValueKey('home_${album.id}_${album.coverArt}'),
                      coverArtId: album.coverArt,
                      size: 320,
                      borderRadius: BorderRadius.circular(12),
                      placeholder: Container(
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
                      errorWidget: Container(
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
      ),
    );
  }
}

class _ArrowButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isEnabled;

  const _ArrowButton({
    required this.icon,
    required this.onTap,
    this.isEnabled = true,
  });

  @override
  State<_ArrowButton> createState() => _ArrowButtonState();
}

class _ArrowButtonState extends State<_ArrowButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.isEnabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: widget.isEnabled ? (_) => setState(() => _isHovered = true) : null,
      onExit: widget.isEnabled ? (_) => setState(() => _isHovered = false) : null,
      child: Listener(
        onPointerDown: widget.isEnabled ? (_) => widget.onTap() : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
          child: Icon(
            widget.icon,
            size: 20,
            color: widget.isEnabled
                ? (_isHovered
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(context).colorScheme.onSurface.withOpacity(0.5))
                : Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
          ),
        ),
      ),
    );
  }
}