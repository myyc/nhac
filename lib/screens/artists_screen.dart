import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/auth_provider.dart';
import '../models/artist.dart';
import 'artist_detail_screen.dart';

class ArtistsScreen extends StatefulWidget {
  const ArtistsScreen({super.key});

  @override
  State<ArtistsScreen> createState() => _ArtistsScreenState();
}

class _ArtistsScreenState extends State<ArtistsScreen> {
  List<Artist>? _artists;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadArtists();
  }

  Future<void> _loadArtists() async {
    final api = context.read<AuthProvider>().api;
    if (api == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final artists = await api.getArtists();
      if (mounted) {
        setState(() {
          _artists = artists;
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
              onPressed: _loadArtists,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_artists == null || _artists!.isEmpty) {
      return const Center(
        child: Text('No artists found'),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadArtists,
      child: ListView.builder(
        itemCount: _artists!.length,
        itemBuilder: (context, index) {
          final artist = _artists![index];
          final api = context.read<AuthProvider>().api;
          
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
              child: artist.coverArt != null && api != null
                  ? ClipOval(
                      child: CachedNetworkImage(
                        imageUrl: api.getCoverArtUrl(artist.coverArt, size: 100),
                        httpHeaders: const {
                          'User-Agent': 'nhac/1.0.0',
                        },
                        fit: BoxFit.cover,
                        width: 40,
                        height: 40,
                        placeholder: (context, url) => const Icon(Icons.person),
                        errorWidget: (context, url, error) => const Icon(Icons.person),
                      ),
                    )
                  : const Icon(Icons.person),
            ),
            title: Text(artist.name),
            subtitle: artist.albumCount != null
                ? Text('${artist.albumCount} album${artist.albumCount != 1 ? 's' : ''}')
                : null,
            trailing: artist.starred != null
                ? const Icon(Icons.star, color: Colors.amber, size: 20)
                : null,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ArtistDetailScreen(artist: artist),
                ),
              );
            },
          );
        },
      ),
    );
  }
}