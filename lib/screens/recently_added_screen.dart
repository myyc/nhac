import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/auth_provider.dart';
import '../models/album.dart';
import 'album_detail_screen.dart';

class RecentlyAddedScreen extends StatefulWidget {
  const RecentlyAddedScreen({super.key});

  @override
  State<RecentlyAddedScreen> createState() => _RecentlyAddedScreenState();
}

class _RecentlyAddedScreenState extends State<RecentlyAddedScreen> {
  List<Album>? _albums;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRecentlyAdded();
  }

  Future<void> _loadRecentlyAdded() async {
    final api = context.read<AuthProvider>().api;
    if (api == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final albums = await api.getRecentlyAdded(size: 100);
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

  String _getTimeAgo(DateTime? date) {
    if (date == null) return '';
    
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays > 365) {
      final years = (difference.inDays / 365).floor();
      return '$years year${years != 1 ? 's' : ''} ago';
    } else if (difference.inDays > 30) {
      final months = (difference.inDays / 30).floor();
      return '$months month${months != 1 ? 's' : ''} ago';
    } else if (difference.inDays > 7) {
      final weeks = (difference.inDays / 7).floor();
      return '$weeks week${weeks != 1 ? 's' : ''} ago';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays != 1 ? 's' : ''} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours != 1 ? 's' : ''} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute${difference.inMinutes != 1 ? 's' : ''} ago';
    } else {
      return 'Just now';
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<AuthProvider>().api;
    
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
              onPressed: _loadRecentlyAdded,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_albums == null || _albums!.isEmpty) {
      return const Center(
        child: Text('No recently added albums'),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadRecentlyAdded,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _albums!.length,
        itemBuilder: (context, index) {
          final album = _albums![index];
          
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AlbumDetailScreen(album: album),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: Theme.of(context).colorScheme.surfaceVariant,
                      ),
                      child: album.coverArt != null && api != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: CachedNetworkImage(
                                imageUrl: api.getCoverArtUrl(album.coverArt, size: 160),
                                httpHeaders: const {
                                  'User-Agent': 'nhac/1.0.0',
                                },
                                fit: BoxFit.cover,
                                placeholder: (context, url) => 
                                    const Center(child: CircularProgressIndicator()),
                                errorWidget: (context, url, error) => 
                                    const Center(child: Icon(Icons.album)),
                              ),
                            )
                          : const Center(child: Icon(Icons.album)),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            album.name,
                            style: Theme.of(context).textTheme.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            album.artist ?? 'Unknown Artist',
                            style: Theme.of(context).textTheme.bodyMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              if (album.year != null)
                                Text(
                                  album.year.toString(),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              if (album.year != null && album.created != null)
                                Text(
                                  ' • ',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              if (album.created != null)
                                Text(
                                  _getTimeAgo(album.created),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (album.starred != null)
                      const Icon(Icons.star, color: Colors.amber, size: 20),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}