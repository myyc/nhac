import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/color_extraction_service.dart';
import '../theme/app_theme.dart';
import 'player_provider.dart';

class ThemeProvider extends ChangeNotifier {
  ExtractedColors? _currentColors;
  PlayerProvider? _playerProvider;
  
  ExtractedColors? get currentColors => _currentColors;
  
  ThemeProvider() {
    _loadPersistedColors();
  }
  
  void setPlayerProvider(PlayerProvider playerProvider) {
    _playerProvider = playerProvider;
    _playerProvider!.addListener(_onPlayerChanged);
    _onPlayerChanged();
  }
  
  void _onPlayerChanged() {
    final colors = _playerProvider?.currentColors;
    if (colors != null && colors != _currentColors) {
      _currentColors = colors;
      _savePersistedColors();
      notifyListeners();
    }
  }
  
  Future<void> _loadPersistedColors() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final colorsJson = prefs.getString('theme_extracted_colors');
      
      if (colorsJson != null) {
        final colorsMap = json.decode(colorsJson);
        _currentColors = ExtractedColors(
          primary: Color(colorsMap['primary']),
          accent: Color(colorsMap['accent']),
          lightBackground: Color(colorsMap['lightBackground']),
          darkBackground: Color(colorsMap['darkBackground']),
          lightSurface: Color(colorsMap['lightSurface']),
          darkSurface: Color(colorsMap['darkSurface']),
          onPrimary: Color(colorsMap['onPrimary']),
          onAccent: Color(colorsMap['onAccent']),
        );
        notifyListeners();
      }
    } catch (e) {
      print('Error loading persisted colors: $e');
    }
  }
  
  Future<void> _savePersistedColors() async {
    if (_currentColors == null) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final colorsMap = {
        'primary': _currentColors!.primary.value,
        'accent': _currentColors!.accent.value,
        'lightBackground': _currentColors!.lightBackground.value,
        'darkBackground': _currentColors!.darkBackground.value,
        'lightSurface': _currentColors!.lightSurface.value,
        'darkSurface': _currentColors!.darkSurface.value,
        'onPrimary': _currentColors!.onPrimary.value,
        'onAccent': _currentColors!.onAccent.value,
      };
      await prefs.setString('theme_extracted_colors', json.encode(colorsMap));
    } catch (e) {
      print('Error saving persisted colors: $e');
    }
  }
  
  ThemeData getLightTheme() {
    if (_currentColors == null) {
      return AppTheme.lightTheme;
    }
    
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _currentColors!.primary,
      brightness: Brightness.light,
      primary: _currentColors!.primary,
      secondary: _currentColors!.accent,
      tertiary: _currentColors!.accent,
      surface: AppTheme.surfaceLight,
      surfaceContainerHighest: AppTheme.surfaceVariantLight,
      error: AppTheme.errorColor,
    );
    
    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      textTheme: AppTheme.buildTextTheme(colorScheme),
      appBarTheme: AppTheme.buildAppBarTheme(colorScheme),
      cardTheme: AppTheme.buildCardThemeData(colorScheme),
      elevatedButtonTheme: AppTheme.buildElevatedButtonTheme(colorScheme),
      filledButtonTheme: AppTheme.buildFilledButtonTheme(colorScheme),
      iconButtonTheme: AppTheme.buildIconButtonTheme(colorScheme),
      navigationBarTheme: AppTheme.buildNavigationBarTheme(colorScheme),
      inputDecorationTheme: AppTheme.buildInputDecorationTheme(colorScheme),
    );
  }
  
  ThemeData getDarkTheme() {
    if (_currentColors == null) {
      return AppTheme.darkTheme;
    }
    
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _currentColors!.primary,
      brightness: Brightness.dark,
      primary: _currentColors!.primary,
      secondary: _currentColors!.accent,
      tertiary: _currentColors!.accent,
      surface: AppTheme.surfaceDark,
      surfaceContainerHighest: AppTheme.surfaceVariantDark,
      error: AppTheme.errorColor,
    );
    
    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      textTheme: AppTheme.buildTextTheme(colorScheme),
      appBarTheme: AppTheme.buildAppBarTheme(colorScheme),
      cardTheme: AppTheme.buildCardThemeData(colorScheme),
      elevatedButtonTheme: AppTheme.buildElevatedButtonTheme(colorScheme),
      filledButtonTheme: AppTheme.buildFilledButtonTheme(colorScheme),
      iconButtonTheme: AppTheme.buildIconButtonTheme(colorScheme),
      navigationBarTheme: AppTheme.buildNavigationBarTheme(colorScheme),
      inputDecorationTheme: AppTheme.buildInputDecorationTheme(colorScheme),
    );
  }
  
  @override
  void dispose() {
    _playerProvider?.removeListener(_onPlayerChanged);
    super.dispose();
  }
}