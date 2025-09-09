import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/song.dart';
import '../services/color_extraction_service.dart';

class ShareService {
  static final ShareService _instance = ShareService._internal();
  factory ShareService() => _instance;
  ShareService._internal();

  final ScreenshotController _screenshotController = ScreenshotController();
  final ColorExtractionService _colorService = ColorExtractionService();

  Future<void> shareStoryImage({
    required BuildContext context,
    required Song song,
    required String coverArtUrl,
    String? styleType,
    CapturedThemes? capturedTheme,
  }) async {
    try {
      debugPrint('ShareService: Starting share for song: ${song.title}');
      debugPrint('ShareService: Cover art URL: $coverArtUrl');
      
      // Check if coverArtUrl is valid
      if (coverArtUrl.isEmpty) {
        throw Exception('Invalid cover art URL');
      }
      
      final extractedColors = await _colorService.extractColorsFromImage(
        coverArtUrl,
        cacheKey: 'share_${song.id}',
      );
      debugPrint('ShareService: Colors extracted successfully');

      final widget = _buildStoryWidget(
        context: context,
        song: song,
        coverArtUrl: coverArtUrl,
        colors: extractedColors,
        style: styleType ?? 'solid',
      );
      debugPrint('ShareService: Widget built successfully');

      // Use captured theme if available, otherwise create a simple wrapper
      final wrappedWidget = capturedTheme != null
          ? capturedTheme.wrap(
              MediaQuery(
                data: const MediaQueryData(),
                child: Material(
                  color: Colors.transparent,
                  child: widget,
                ),
              ),
            )
          : MediaQuery(
              data: const MediaQueryData(),
              child: Material(
                color: Colors.transparent,
                child: widget,
              ),
            );

      final image = await _screenshotController.captureFromWidget(
        wrappedWidget,
        pixelRatio: 3.0,
        targetSize: const Size(1080, 1920),
      );
      debugPrint('ShareService: Screenshot captured successfully');

      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/nhac_story_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(image);
      debugPrint('ShareService: File saved to: ${file.path}');

      await Share.shareXFiles(
        [XFile(file.path)],
        text: '${song.title} by ${song.artist ?? "Unknown Artist"} 🎵',
      );

      await Future.delayed(const Duration(seconds: 5));
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e, stackTrace) {
      debugPrint('Error sharing story image: $e');
      debugPrint('Stack trace: $stackTrace');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to share story')),
        );
      }
    }
  }

  Widget _buildStoryWidget({
    required BuildContext context,
    required Song song,
    required String coverArtUrl,
    required ExtractedColors colors,
    required String style,
  }) {
    final backgroundColor = colors.getSocialShareBackground();
    final frameColor = colors.darkSurface;
    final textColor = colors.darkSurface.computeLuminance() > 0.5 
        ? Colors.black87 
        : Colors.white;

    return Container(
      width: 1080,
      height: 1920,
      color: backgroundColor,
      child: Center(
        child: Container(
          width: 700,
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: frameColor,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 50,
                offset: const Offset(0, 20),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 600,
                height: 600,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  image: DecorationImage(
                    image: CachedNetworkImageProvider(coverArtUrl),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 40),
              Text(
                song.title,
                style: GoogleFonts.inter(
                  fontSize: 42,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                  height: 1.2,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              Text(
                song.artist ?? 'Unknown Artist',
                style: GoogleFonts.inter(
                  fontSize: 32,
                  fontWeight: FontWeight.w500,
                  color: textColor.withOpacity(0.8),
                ),
                textAlign: TextAlign.center,
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