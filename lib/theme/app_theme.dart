import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Modern color palette
  static const Color primaryColor = Color(0xFF6366F1); // Indigo
  static const Color secondaryColor = Color(0xFF8B5CF6); // Purple
  static const Color accentColor = Color(0xFFF59E0B); // Amber
  static const Color successColor = Color(0xFF10B981); // Emerald
  static const Color errorColor = Color(0xFFEF4444); // Red
  
  // Surface colors
  static const Color surfaceLight = Color(0xFFFAFAFA);
  static const Color surfaceDark = Color(0xFF0F0F0F);
  static const Color surfaceVariantLight = Color(0xFFF1F5F9);
  static const Color surfaceVariantDark = Color(0xFF1E293B);

  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: Brightness.light,
      primary: primaryColor,
      secondary: secondaryColor,
      tertiary: accentColor,
      surface: surfaceLight,
      surfaceVariant: surfaceVariantLight,
      error: errorColor,
    );

    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      textTheme: buildTextTheme(colorScheme),
      appBarTheme: buildAppBarTheme(colorScheme),
      cardTheme: buildCardThemeData(colorScheme),
      elevatedButtonTheme: buildElevatedButtonTheme(colorScheme),
      filledButtonTheme: buildFilledButtonTheme(colorScheme),
      iconButtonTheme: buildIconButtonTheme(colorScheme),
      navigationBarTheme: buildNavigationBarTheme(colorScheme),
      inputDecorationTheme: buildInputDecorationTheme(colorScheme),
    );
  }

  static ThemeData get darkTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: Brightness.dark,
      primary: primaryColor,
      secondary: secondaryColor,
      tertiary: accentColor,
      surface: surfaceDark,
      surfaceVariant: surfaceVariantDark,
      error: errorColor,
    );

    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      textTheme: buildTextTheme(colorScheme),
      appBarTheme: buildAppBarTheme(colorScheme),
      cardTheme: buildCardThemeData(colorScheme),
      elevatedButtonTheme: buildElevatedButtonTheme(colorScheme),
      filledButtonTheme: buildFilledButtonTheme(colorScheme),
      iconButtonTheme: buildIconButtonTheme(colorScheme),
      navigationBarTheme: buildNavigationBarTheme(colorScheme),
      inputDecorationTheme: buildInputDecorationTheme(colorScheme),
    );
  }

  static TextTheme buildTextTheme(ColorScheme colorScheme) {
    // macOS font fallback chain
    const fontFallback = ['.SF NS Text', 'Helvetica Neue', 'Helvetica', 'Arial', 'sans-serif'];
    final baseTextTheme = GoogleFonts.interTextTheme();
    
    return baseTextTheme.copyWith(
      displayLarge: GoogleFonts.inter(
        fontSize: 57,
        fontWeight: FontWeight.w400,
        letterSpacing: -0.25,
        color: colorScheme.onSurface,
      ).copyWith(fontFamilyFallback: fontFallback),
      displayMedium: GoogleFonts.inter(
        fontSize: 45,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        color: colorScheme.onSurface,
      ).copyWith(fontFamilyFallback: fontFallback),
      displaySmall: GoogleFonts.inter(
        fontSize: 36,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        color: colorScheme.onSurface,
      ).copyWith(fontFamilyFallback: fontFallback),
      headlineLarge: GoogleFonts.inter(
        fontSize: 32,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        color: colorScheme.onSurface,
      ).copyWith(fontFamilyFallback: fontFallback),
      headlineMedium: GoogleFonts.inter(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        color: colorScheme.onSurface,
      ).copyWith(fontFamilyFallback: fontFallback),
      headlineSmall: GoogleFonts.inter(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        color: colorScheme.onSurface,
      ).copyWith(fontFamilyFallback: fontFallback),
      titleLarge: GoogleFonts.inter(
        fontSize: 22,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
        color: colorScheme.onSurface,
      ).copyWith(fontFamilyFallback: fontFallback),
      titleMedium: GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.15,
        color: colorScheme.onSurface,
      ).copyWith(fontFamilyFallback: fontFallback),
      titleSmall: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.1,
        color: colorScheme.onSurface,
      ).copyWith(fontFamilyFallback: fontFallback),
      bodyLarge: GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.5,
        color: colorScheme.onSurface,
      ).copyWith(fontFamilyFallback: fontFallback),
      bodyMedium: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.25,
        color: colorScheme.onSurface,
      ).copyWith(fontFamilyFallback: fontFallback),
      bodySmall: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.4,
        color: colorScheme.onSurface.withOpacity(0.7),
      ).copyWith(fontFamilyFallback: fontFallback),
      labelLarge: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.1,
        color: colorScheme.onSurface,
      ).copyWith(fontFamilyFallback: fontFallback),
      labelMedium: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
        color: colorScheme.onSurface,
      ).copyWith(fontFamilyFallback: fontFallback),
      labelSmall: GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
        color: colorScheme.onSurface,
      ).copyWith(fontFamilyFallback: fontFallback),
    );
  }

  static AppBarTheme buildAppBarTheme(ColorScheme colorScheme) {
    const fontFallback = ['.SF NS Text', 'Helvetica Neue', 'Helvetica', 'Arial', 'sans-serif'];
    return AppBarTheme(
      backgroundColor: colorScheme.surface,
      foregroundColor: colorScheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
      titleTextStyle: GoogleFonts.inter(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: colorScheme.onSurface,
      ).copyWith(fontFamilyFallback: fontFallback),
    );
  }

  static CardThemeData buildCardThemeData(ColorScheme colorScheme) {
    return CardThemeData(
      color: colorScheme.surface,
      surfaceTintColor: colorScheme.surfaceTint,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  static ElevatedButtonThemeData buildElevatedButtonTheme(ColorScheme colorScheme) {
    const fontFallback = ['.SF NS Text', 'Helvetica Neue', 'Helvetica', 'Arial', 'sans-serif'];
    return ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ).copyWith(fontFamilyFallback: fontFallback),
      ),
    );
  }

  static FilledButtonThemeData buildFilledButtonTheme(ColorScheme colorScheme) {
    const fontFallback = ['.SF NS Text', 'Helvetica Neue', 'Helvetica', 'Arial', 'sans-serif'];
    return FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ).copyWith(fontFamilyFallback: fontFallback),
      ),
    );
  }

  static IconButtonThemeData buildIconButtonTheme(ColorScheme colorScheme) {
    return IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: colorScheme.onSurface,
        padding: const EdgeInsets.all(8),
        minimumSize: const Size(40, 40),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  static NavigationBarThemeData buildNavigationBarTheme(ColorScheme colorScheme) {
    const fontFallback = ['.SF NS Text', 'Helvetica Neue', 'Helvetica', 'Arial', 'sans-serif'];
    return NavigationBarThemeData(
      backgroundColor: colorScheme.surface.withOpacity(0.95),
      indicatorColor: colorScheme.primary.withOpacity(0.12),
      labelTextStyle: MaterialStateProperty.resolveWith((states) {
        if (states.contains(MaterialState.selected)) {
          return GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: colorScheme.primary,
          ).copyWith(fontFamilyFallback: fontFallback);
        }
        return GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: colorScheme.onSurface.withOpacity(0.7),
        ).copyWith(fontFamilyFallback: fontFallback);
      }),
      iconTheme: MaterialStateProperty.resolveWith((states) {
        if (states.contains(MaterialState.selected)) {
          return IconThemeData(color: colorScheme.primary);
        }
        return IconThemeData(color: colorScheme.onSurface.withOpacity(0.7));
      }),
    );
  }

  static InputDecorationTheme buildInputDecorationTheme(ColorScheme colorScheme) {
    const fontFallback = ['.SF NS Text', 'Helvetica Neue', 'Helvetica', 'Arial', 'sans-serif'];
    return InputDecorationTheme(
      filled: true,
      fillColor: colorScheme.surfaceVariant,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colorScheme.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colorScheme.error, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colorScheme.error, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      hintStyle: GoogleFonts.inter(
        color: colorScheme.onSurface.withOpacity(0.6),
      ).copyWith(fontFamilyFallback: fontFallback),
      labelStyle: GoogleFonts.inter(
        color: colorScheme.onSurface.withOpacity(0.7),
      ).copyWith(fontFamilyFallback: fontFallback),
    );
  }
}