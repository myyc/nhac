import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:io' show Platform;
import '../providers/auth_provider.dart';
import '../providers/player_provider.dart';
import '../providers/cache_provider.dart';
import '../providers/network_provider.dart';
import '../models/artist.dart';
import '../models/album.dart';
import '../models/song.dart';
import '../widgets/custom_window_frame.dart';
import '../widgets/now_playing_bar.dart';
import 'artist_detail_screen.dart';
import 'album_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  final VoidCallback? onNavigateToHome;
  final VoidCallback? onClose;
  final String? initialQuery;
  
  const SearchScreen({
    super.key, 
    this.onNavigateToHome,
    this.onClose,
    this.initialQuery,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  List<Artist>? _artists;
  List<Album>? _albums;
  List<Song>? _songs;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery != null) {
      _searchController.text = widget.initialQuery!;
      // Move cursor to end of text
      _searchController.selection = TextSelection.fromPosition(
        TextPosition(offset: _searchController.text.length),
      );
      // Trigger search after a short delay to let the UI build
      Future.delayed(const Duration(milliseconds: 100), () {
        _search(widget.initialQuery!);
        // Request focus after the initial search
        _searchFocusNode.requestFocus();
      });
    }
    // Request focus on mount
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.isEmpty) {
      setState(() {
        _artists = null;
        _albums = null;
        _songs = null;
      });
      return;
    }

    final api = context.read<AuthProvider>().api;
    final cacheProvider = context.read<CacheProvider>();
    final networkProvider = context.read<NetworkProvider>();

    if (api == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      Map<String, dynamic> results;

      // Use offline search when offline
      if (networkProvider.isOffline) {
        if (kDebugMode) print('[SearchScreen] Searching offline for: $query');
        results = await cacheProvider.searchOffline(query);
      } else {
        // Online search
        results = await api.search3(query);
      }

      if (mounted) {
        setState(() {
          _artists = results['artists'];
          _albums = results['albums'];
          _songs = results['songs'];
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

  Widget _buildSongTile(Song song) {
    final api = context.read<AuthProvider>().api;
    final playerProvider = context.read<PlayerProvider>();
    final cacheProvider = context.read<CacheProvider>();
    
    return ListTile(
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          color: Theme.of(context).colorScheme.surfaceVariant,
        ),
        child: song.coverArt != null && api != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: CachedNetworkImage(
                  key: ValueKey('search_${song.id}_${song.coverArt}'),
                  imageUrl: cacheProvider.getCoverArtUrl(song.coverArt, size: 96),
                  cacheKey: 'cover_${song.id}_${song.coverArt}_96',
                  fit: BoxFit.cover,
                  memCacheWidth: 96,
                  memCacheHeight: 96,
                  placeholder: (context, url) => 
                      const Center(child: Icon(Icons.music_note, size: 20)),
                  errorWidget: (context, url, error) => 
                      const Center(child: Icon(Icons.music_note, size: 20)),
                ),
              )
            : const Center(child: Icon(Icons.music_note, size: 20)),
      ),
      title: Text(song.title),
      subtitle: Text('${song.artist ?? 'Unknown Artist'} • ${song.album ?? ''}'),
      trailing: Text(song.formattedDuration),
      onTap: () async {
        final networkProvider = context.read<NetworkProvider>();
        playerProvider.setApi(api!, networkProvider: networkProvider);
        // If song has an albumId, load and play the full album from this song
        if (song.albumId != null) {
          try {
            final result = await api.getAlbum(song.albumId!);
            final albumSongs = result['songs'] as List<Song>?;
            if (albumSongs != null && albumSongs.isNotEmpty) {
              // Find the index of the current song in the album
              final songIndex = albumSongs.indexWhere((s) => s.id == song.id);
              if (songIndex != -1) {
                playerProvider.playQueue(albumSongs, startIndex: songIndex);
              } else {
                // If song not found in album, just play as single track
                playerProvider.playQueue([song], startIndex: 0);
              }
            } else {
              // Album has no songs, just play as single track
              playerProvider.playQueue([song], startIndex: 0);
            }
          } catch (e) {
            // If loading album fails, just play as single track
            playerProvider.playQueue([song], startIndex: 0);
          }
        } else {
          // No album info, just play as single track
          playerProvider.playQueue([song], startIndex: 0);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<AuthProvider>().api;
    final cacheProvider = context.read<CacheProvider>();
    
    // Check if on mobile and wrap search bar with SafeArea
    final searchBar = Padding(
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        autofocus: true,
        decoration: InputDecoration(
          hintText: 'Search artists, albums, songs...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    _search('');
                  },
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          filled: true,
        ),
        onChanged: (value) {
          _search(value);
        },
      ),
    );
    
    Widget content = Column(
      children: [
        // Search bar - wrap with SafeArea on mobile
        if (Platform.isAndroid || Platform.isIOS)
          SafeArea(
            bottom: false,
            child: searchBar,
          )
        else
          searchBar,
        
        // Results
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Text('Error: $_error'),
                    )
                  : (_artists == null && _albums == null && _songs == null)
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.search,
                                size: 64,
                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Search for music',
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView(
                          children: [
                            // Artists section
                            if (_artists != null && _artists!.isNotEmpty) ...[
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                child: Text(
                                  'Artists',
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              ..._artists!.take(5).map((artist) => ListTile(
                                leading: const CircleAvatar(
                                  child: Icon(Icons.person),
                                ),
                                title: Text(artist.name),
                                subtitle: artist.albumCount != null
                                    ? Text('${artist.albumCount} albums')
                                    : null,
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => ArtistDetailScreen(artist: artist),
                                    ),
                                  );
                                },
                              )),
                            ],
                            
                            // Albums section
                            if (_albums != null && _albums!.isNotEmpty) ...[
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                child: Text(
                                  'Albums',
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              ..._albums!.take(5).map((album) => ListTile(
                                leading: Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(4),
                                    color: Theme.of(context).colorScheme.surfaceVariant,
                                  ),
                                  child: album.coverArt != null && api != null
                                      ? ClipRRect(
                                          borderRadius: BorderRadius.circular(4),
                                          child: CachedNetworkImage(
                                            imageUrl: cacheProvider.getCoverArtUrl(album.coverArt, size: 96),
                                            fit: BoxFit.cover,
                                            placeholder: (context, url) => 
                                                const Center(child: Icon(Icons.album, size: 20)),
                                            errorWidget: (context, url, error) => 
                                                const Center(child: Icon(Icons.album, size: 20)),
                                          ),
                                        )
                                      : const Center(child: Icon(Icons.album, size: 20)),
                                ),
                                title: Text(album.name),
                                subtitle: Text(album.artist ?? 'Unknown Artist'),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => AlbumDetailScreen(album: album),
                                    ),
                                  );
                                },
                              )),
                            ],
                            
                            // Songs section
                            if (_songs != null && _songs!.isNotEmpty) ...[
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                child: Text(
                                  'Songs',
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              ..._songs!.take(10).map((song) => _buildSongTile(song)),
                            ],
                            
                            const SizedBox(height: 80), // Space for player bar
                          ],
                        ),
        ),
      ],
    );
    
    // Wrap in Scaffold with app bar for navigation
    Widget scaffold = Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.of(context).pop();
            widget.onClose?.call();
          },
        ),
        title: const Text('Search'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(child: content),
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
    
    // For desktop, add ESC key handling and CustomWindowFrame
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return RawKeyboardListener(
        focusNode: FocusNode(),
        autofocus: true,
        onKey: (event) {
          if (event is RawKeyDownEvent && 
              event.logicalKey == LogicalKeyboardKey.escape) {
            Navigator.of(context).pop();
            widget.onClose?.call();
          }
        },
        child: CustomWindowFrame(
          child: scaffold,
        ),
      );
    }
    
    return scaffold;
  }
}