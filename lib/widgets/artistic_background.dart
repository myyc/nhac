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
  late String _effectType;
  ExtractedColors? _extractedColors;
  final ColorExtractionService _colorService = ColorExtractionService();

  @override
  void initState() {
    super.initState();
    _selectRandomEffect();
    _loadColors();
  }

  @override
  void didUpdateWidget(ArtisticBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.albumId != widget.albumId || oldWidget.coverArtId != widget.coverArtId) {
      _selectRandomEffect();
      _loadColors();
    }
  }

  void _selectRandomEffect() {
    final dateString = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final seed = '${widget.albumId}_$dateString'.hashCode;
    final random = Random(seed);
    final randomValue = random.nextDouble();

    if (randomValue < 0.35) {
      _effectType = 'blur';
    } else if (randomValue < 0.65) {
      _effectType = 'gradient';
    } else if (randomValue < 0.85) {
      _effectType = 'grain';
    } else {
      _effectType = 'oil';
    }
    
    // Debug: Log which effect was selected
    print('ArtisticBackground: Selected effect "$_effectType" for album ${widget.albumId} (random value: ${randomValue.toStringAsFixed(3)})');
  }

  Future<void> _loadColors() async {
    if (widget.coverArtId == null) return;
    
    try {
      final cacheProvider = context.read<CacheProvider>();
      final coverUrl = cacheProvider.getCoverArtUrl(widget.coverArtId!, size: 300);
      final colors = await _colorService.extractColorsFromImage(
        coverUrl,
        cacheKey: 'album_${widget.albumId}',
      );
      if (mounted) {
        setState(() {
          _extractedColors = colors;
        });
      }
    } catch (e) {
      // Use default colors on error
    }
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

    Widget background;
    switch (_effectType) {
      case 'blur':
        background = _buildBlurEffect();
        break;
      case 'gradient':
        background = _buildGradientEffect();
        break;
      case 'grain':
        background = _buildGrainEffect();
        break;
      case 'oil':
        background = _buildOilPaintingEffect();
        break;
      default:
        background = _buildBlurEffect();
    }

    // Wrap in ClipRect to contain all effects within this widget's bounds
    return ClipRect(
      child: SizedBox(
        height: widget.height,
        width: widget.width,
        child: Stack(
          fit: StackFit.expand,
          children: [
            background,
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

  Widget _buildGradientEffect() {
    final colors = _extractedColors ?? ExtractedColors.defaultColors();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
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
        Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.center,
              radius: 1.5,
              colors: [
                colors.primary.withOpacity(0.4),
                colors.accent.withOpacity(0.6),
                isDark ? colors.darkBackground.withOpacity(0.8) : colors.lightBackground.withOpacity(0.8),
              ],
            ),
          ),
        ),
        BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            color: Colors.transparent,
          ),
        ),
      ],
    );
  }

  Widget _buildGrainEffect() {
    final colors = _extractedColors ?? ExtractedColors.defaultColors();
    
    return Stack(
      fit: StackFit.expand,
      children: [
        Transform.scale(
          scale: 1.5,
          child: ColorFiltered(
            colorFilter: const ColorFilter.matrix([
              0.9, 0, 0, 0, 0,
              0, 0.9, 0, 0, 0,
              0, 0, 0.9, 0, 0,
              0, 0, 0, 1, 0,
            ]),
            child: CachedCoverImage(
              coverArtId: widget.coverArtId,
              size: 600,
              fit: BoxFit.cover,
            ),
          ),
        ),
        Container(
          color: Colors.black.withOpacity(0.15),
        ),
        CustomPaint(
          painter: GrainPainter(
            primaryColor: colors.primary,
            accentColor: colors.accent,
          ),
          child: Container(),
        ),
      ],
    );
  }

  Widget _buildOilPaintingEffect() {
    final colors = _extractedColors ?? ExtractedColors.defaultColors();
    
    return Stack(
      fit: StackFit.expand,
      children: [
        Transform.scale(
          scale: 1.5,
          child: ColorFiltered(
            colorFilter: ColorFilter.mode(
              colors.primary.withOpacity(0.6),
              BlendMode.overlay,
            ),
            child: ColorFiltered(
              colorFilter: ColorFilter.mode(
                colors.accent.withOpacity(0.3),
                BlendMode.hardLight,
              ),
              child: ColorFiltered(
                colorFilter: const ColorFilter.matrix([
                  // Much stronger contrast and saturation for intense oil painting look
                  2.2, 0, 0, 0, -50,
                  0, 2.2, 0, 0, -50,
                  0, 0, 2.2, 0, -50,
                  0, 0, 0, 1, 0,
                ]),
                child: CachedCoverImage(
                  coverArtId: widget.coverArtId,
                  size: 120, // Lower resolution for chunkier brush strokes
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
        ),
        // Add stronger texture overlay with more blur
        BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 3.5, sigmaY: 3.5),
          child: Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.5,
                colors: [
                  colors.primary.withOpacity(0.1),
                  Colors.transparent,
                  colors.accent.withOpacity(0.1),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

}

class GrainPainter extends CustomPainter {
  final Color primaryColor;
  final Color accentColor;
  
  GrainPainter({
    required this.primaryColor,
    required this.accentColor,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    final random = Random(42);
    final paint = Paint()
      ..style = PaintingStyle.fill;
    
    // Convert colors to HSL for manipulation
    final primaryHSL = HSLColor.fromColor(primaryColor);
    final accentHSL = HSLColor.fromColor(accentColor);

    // Much denser and more visible grain effect
    for (int i = 0; i < 15000; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      final opacity = 0.15 + random.nextDouble() * 0.25; // Slightly reduced opacity
      final isLight = random.nextBool();
      final useAccent = random.nextDouble() > 0.6; // 40% chance to use accent color
      
      // Use rectangles for more film-like grain
      final grainSize = 1.0 + random.nextDouble() * 2.0; // Larger grain
      
      // Create grain colors based on image colors
      Color grainColor;
      if (isLight) {
        // Lighter grain - increase lightness
        final baseHSL = useAccent ? accentHSL : primaryHSL;
        final lightness = (baseHSL.lightness + 0.3).clamp(0.0, 1.0);
        grainColor = baseHSL.withLightness(lightness).toColor().withOpacity(opacity);
      } else {
        // Darker grain - decrease lightness
        final baseHSL = useAccent ? accentHSL : primaryHSL;
        final lightness = (baseHSL.lightness - 0.3).clamp(0.0, 1.0);
        grainColor = baseHSL.withLightness(lightness).toColor().withOpacity(opacity * 0.8);
      }
      
      paint.color = grainColor;
      
      // Draw rectangles instead of circles for sharper grain
      canvas.drawRect(
        Rect.fromLTWH(x, y, grainSize, grainSize),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}