import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../widgets/cached_cover_image.dart';
import '../services/color_extraction_service.dart';
import '../providers/cache_provider.dart';

class ArtisticBackground extends StatefulWidget {
  final String? coverArtId;
  final String albumId;
  final double height;
  final double width;

  const ArtisticBackground({
    super.key,
    required this.coverArtId,
    required this.albumId,
    this.height = 300,
    this.width = double.infinity,
  });

  @override
  State<ArtisticBackground> createState() => _ArtisticBackgroundState();
}

class _ArtisticBackgroundState extends State<ArtisticBackground> {
  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(ArtisticBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.coverArtId == null) {
      return Container(
        height: widget.height,
        width: widget.width,
        color: Theme.of(context).colorScheme.surfaceVariant,
        child: const Icon(Icons.album, size: 100),
      );
    }

    // Always use blur effect - simple and reliable
    return ClipRect(
      child: SizedBox(
        height: widget.height,
        width: widget.width,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildBlurEffect(),
            // Gradient only at the bottom for text readability
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                height: widget.height * 0.3, // Only bottom 30%
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.3),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlurEffect() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Transform.scale(
          scale: 1.5,
          child: CachedCoverImage(
            coverArtId: widget.coverArtId,
            size: 600,
            fit: BoxFit.cover,
          ),
        ),
        BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            color: Colors.black.withOpacity(0.2),
          ),
        ),
      ],
    );
  }

}