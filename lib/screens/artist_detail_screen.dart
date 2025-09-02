import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/auth_provider.dart';
import '../providers/cache_provider.dart';
import '../models/artist.dart';
import '../models/album.dart';
import 'album_detail_screen.dart';
import 'app_scaffold.dart';
import '../widgets/custom_window_frame.dart';
import 'dart:io' show Platform;

class ArtistDetailScreen extends StatefulWidget {
  final Artist artist;

  const ArtistDetailScreen({super.key, required this.artist});

  @override
  State<ArtistDetailScreen> createState() => _ArtistDetailScreenState();
}

class _ArtistDetailScreenState extends State<ArtistDetailScreen> {
  List<Album>? _albums;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadArtistDetails();
  }

  Future<void> _loadArtistDetails() async {
    final cacheProvider = context.read<CacheProvider>();

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final albums = await cacheProvider.getAlbumsByArtist(widget.artist.id);
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
    
    final scaffold = AppScaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(widget.artist.name),
      ),
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
                        onPressed: _loadArtistDetails,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _albums == null || _albums!.isEmpty
                  ? const Center(child: Text('No albums found'))
                  : GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 200,
                        childAspectRatio: 0.8,
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
                                  child: album.coverArt != null && api != null
                                      ? ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: CachedNetworkImage(
                                            key: ValueKey('artist_${album.id}_${album.coverArt}'),
                                            imageUrl: cacheProvider.getCoverArtUrl(album.coverArt),
                                            cacheKey: 'cover_${album.id}_${album.coverArt}_300',
                                            fit: BoxFit.cover,
                                            width: double.infinity,
                                            height: double.infinity,
                                            placeholder: (context, url) => 
                                                const Center(child: CircularProgressIndicator()),
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
                              if (album.year != null)
                                Text(
                                  album.year.toString(),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                            ],
                          ),
                        );
                      },
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
}