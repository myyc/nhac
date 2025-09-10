import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'dart:io' show Platform;
import '../providers/auth_provider.dart';
import '../providers/cache_provider.dart';
import '../models/album.dart';
import '../widgets/offline_indicator.dart';
import '../widgets/cached_cover_image.dart';
import '../services/library_scan_service.dart';
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
    _loadData();
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
        // Simply refresh the data to show new albums
        _loadData();
      }
    });
  }

  Future<void> _loadData() async {
    final api = context.read<AuthProvider>().api;
    if (api == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final futures = await Future.wait([
        api.getAlbumList2(type: 'newest', size: 18),
        api.getAlbumList2(type: 'frequent', size: 18),
        api.getAlbumList2(type: 'random', size: 18),
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

  Widget _buildSection(String title, List<Album>? albums) {
    if (albums == null || albums.isEmpty) return const SizedBox.shrink();

    // Calculate scroll amount: 3 albums * (170 width + 16 margin)
    const scrollAmount = 3 * (170.0 + 16.0);

    return _AlbumSection(
      title: title,
      albums: albums,
      scrollAmount: scrollAmount,
      onAlbumTap: (album) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AlbumDetailScreen(album: album),
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
                  const OfflineIndicator(),
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
        
        _buildSection('Recently Added', _recentlyAdded),
        _buildSection('Most Played', _mostPlayed),
        _buildSection('Discover', _random),
        
        const SizedBox(height: 80), // Space for player bar
      ],
    );
    
    // Wrap the entire ListView with MoveWindow for desktop
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      listView = MoveWindow(child: listView);
    }
    
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

class _AlbumSection extends StatefulWidget {
  final String title;
  final List<Album> albums;
  final double scrollAmount;
  final Function(Album) onAlbumTap;

  const _AlbumSection({
    required this.title,
    required this.albums,
    required this.scrollAmount,
    required this.onAlbumTap,
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
              itemBuilder: (context, index) => _AlbumCard(
                album: widget.albums[index],
                onTap: () => widget.onAlbumTap(widget.albums[index]),
                isLast: index == widget.albums.length - 1,
              ),
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

  const _AlbumCard({
    required this.album,
    required this.onTap,
    this.size = 160,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
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