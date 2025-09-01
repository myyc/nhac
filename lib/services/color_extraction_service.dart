import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:cached_network_image/cached_network_image.dart';

class ColorExtractionService {
  static final ColorExtractionService _instance = ColorExtractionService._internal();
  factory ColorExtractionService() => _instance;
  ColorExtractionService._internal();

  // Cache for extracted colors to avoid re-processing
  final Map<String, ExtractedColors> _colorCache = {};

  /// Extracts colors from an album cover image
  Future<ExtractedColors> extractColorsFromImage(String imageUrl, {String? cacheKey}) async {
    final key = cacheKey ?? imageUrl;
    
    // Return cached colors if available
    if (_colorCache.containsKey(key)) {
      return _colorCache[key]!;
    }

    try {
      // Create image provider from cached network image
      final imageProvider = CachedNetworkImageProvider(imageUrl);
      
      // Generate palette from the image
      final paletteGenerator = await PaletteGenerator.fromImageProvider(
        imageProvider,
        size: const Size(200, 200), // Resize for faster processing
        maximumColorCount: 16, // Limit colors for better performance
      );

      // Extract the most suitable colors
      final extractedColors = _processColors(paletteGenerator);
      
      // Cache the results
      _colorCache[key] = extractedColors;
      
      return extractedColors;
    } catch (e) {
      // Return default colors if extraction fails
      return ExtractedColors.defaultColors();
    }
  }

  /// Process the generated palette to extract meaningful colors
  ExtractedColors _processColors(PaletteGenerator palette) {
    // Primary color (most dominant)
    Color primary = palette.dominantColor?.color ?? Colors.blue;
    
    // Accent color (vibrant or muted vibrant)
    Color accent = palette.vibrantColor?.color ?? 
                   palette.mutedColor?.color ?? 
                   primary;
    
    // Background colors
    Color lightBackground = palette.lightMutedColor?.color ?? 
                           _lightenColor(primary, 0.9);
    
    Color darkBackground = palette.darkMutedColor?.color ?? 
                          _darkenColor(primary, 0.9);
    
    // Text colors (ensure good contrast)
    Color onPrimary = _getContrastingTextColor(primary);
    Color onAccent = _getContrastingTextColor(accent);
    
    // Surface colors for cards and overlays
    Color lightSurface = palette.lightVibrantColor?.color ?? 
                        _lightenColor(accent, 0.95);
    
    Color darkSurface = palette.darkVibrantColor?.color ?? 
                       _darkenColor(accent, 0.8);

    return ExtractedColors(
      primary: primary,
      accent: accent,
      lightBackground: lightBackground,
      darkBackground: darkBackground,
      lightSurface: lightSurface,
      darkSurface: darkSurface,
      onPrimary: onPrimary,
      onAccent: onAccent,
    );
  }

  /// Lighten a color by a given amount (0.0 to 1.0)
  Color _lightenColor(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    final lightness = (hsl.lightness + amount).clamp(0.0, 1.0);
    return hsl.withLightness(lightness).toColor();
  }

  /// Darken a color by a given amount (0.0 to 1.0)
  Color _darkenColor(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    final lightness = (hsl.lightness - amount).clamp(0.0, 1.0);
    return hsl.withLightness(lightness).toColor();
  }

  /// Get contrasting text color (white or black) for a background color
  Color _getContrastingTextColor(Color backgroundColor) {
    final luminance = backgroundColor.computeLuminance();
    return luminance > 0.5 ? Colors.black87 : Colors.white;
  }

  /// Create gradient colors from primary and accent
  List<Color> createGradient(ExtractedColors colors, {bool isDark = false}) {
    if (isDark) {
      return [
        colors.darkSurface,
        colors.darkBackground,
        colors.primary.withOpacity(0.1),
      ];
    } else {
      return [
        colors.lightSurface,
        colors.lightBackground,
        colors.accent.withOpacity(0.1),
      ];
    }
  }

  /// Clear the color cache (useful for memory management)
  void clearCache() {
    _colorCache.clear();
  }

  /// Remove a specific entry from cache
  void removeCacheEntry(String key) {
    _colorCache.remove(key);
  }
}

/// Data class to hold extracted colors
class ExtractedColors {
  final Color primary;
  final Color accent;
  final Color lightBackground;
  final Color darkBackground;
  final Color lightSurface;
  final Color darkSurface;
  final Color onPrimary;
  final Color onAccent;

  const ExtractedColors({
    required this.primary,
    required this.accent,
    required this.lightBackground,
    required this.darkBackground,
    required this.lightSurface,
    required this.darkSurface,
    required this.onPrimary,
    required this.onAccent,
  });

  /// Default colors to use when extraction fails
  factory ExtractedColors.defaultColors() {
    return const ExtractedColors(
      primary: Color(0xFF6366F1), // Indigo
      accent: Color(0xFF8B5CF6), // Purple
      lightBackground: Color(0xFFF8FAFC),
      darkBackground: Color(0xFF0F172A),
      lightSurface: Color(0xFFE2E8F0),
      darkSurface: Color(0xFF1E293B),
      onPrimary: Colors.white,
      onAccent: Colors.white,
    );
  }

  /// Create a ColorScheme from extracted colors
  ColorScheme toColorScheme({required Brightness brightness}) {
    return ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: onPrimary,
      secondary: accent,
      onSecondary: onAccent,
      surface: brightness == Brightness.light ? lightSurface : darkSurface,
      onSurface: brightness == Brightness.light ? Colors.black87 : Colors.white,
      background: brightness == Brightness.light ? lightBackground : darkBackground,
      onBackground: brightness == Brightness.light ? Colors.black87 : Colors.white,
      error: const Color(0xFFEF4444),
      onError: Colors.white,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ExtractedColors &&
      other.primary == primary &&
      other.accent == accent &&
      other.lightBackground == lightBackground &&
      other.darkBackground == darkBackground;
  }

  @override
  int get hashCode {
    return primary.hashCode ^
      accent.hashCode ^
      lightBackground.hashCode ^
      darkBackground.hashCode;
  }
}