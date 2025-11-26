import 'package:flutter/foundation.dart';

class PerformanceConfig {
  // Keys for future persistent storage implementation
  // static const String enableGaplessKey = 'enable_gapless_playback';
  // static const String positionUpdateIntervalKey = 'position_update_interval';
  // static const String enableAggressiveCachingKey = 'enable_aggressive_caching';

  // Default values
  static const bool defaultEnableGapless = false; // Disabled to reduce CPU usage
  static const int defaultPositionUpdateInterval = 100; // milliseconds
  static const bool defaultEnableAggressiveCaching = false; // Disabled to reduce CPU usage

  // Current values (can be overridden via environment variables or settings)
  static bool enableGaplessPlayback = defaultEnableGapless;
  static int positionUpdateInterval = defaultPositionUpdateInterval;
  static bool enableAggressiveCaching = defaultEnableAggressiveCaching;

  /// Initialize configuration from environment variables
  static void initialize() {
    if (kDebugMode) {
      print('[PerformanceConfig] Initializing with defaults:');
      print('  - enableGaplessPlayback: $enableGaplessPlayback');
      print('  - positionUpdateInterval: $positionUpdateInterval ms');
      print('  - enableAggressiveCaching: $enableAggressiveCaching');
    }

    // Allow overriding with environment variables (useful for debugging)
    if (const String.fromEnvironment('ENABLE_GAPLESS') == 'true') {
      enableGaplessPlayback = true;
      if (kDebugMode) print('[PerformanceConfig] Gapless playback enabled via environment variable');
    }

    if (const String.fromEnvironment('POSITION_UPDATE_INTERVAL') != '') {
      final interval = int.tryParse(const String.fromEnvironment('POSITION_UPDATE_INTERVAL'));
      if (interval != null && interval > 0 && interval <= 1000) {
        positionUpdateInterval = interval;
        if (kDebugMode) print('[PerformanceConfig] Position update interval set to $positionUpdateInterval ms via environment variable');
      }
    }

    if (const String.fromEnvironment('ENABLE_AGGRESSIVE_CACHING') == 'true') {
      enableAggressiveCaching = true;
      if (kDebugMode) print('[PerformanceConfig] Aggressive caching enabled via environment variable');
    }
  }

  /// Get optimized configuration for low CPU usage
  static void setLowCpuMode() {
    enableGaplessPlayback = false;
    positionUpdateInterval = 200; // Even slower updates
    enableAggressiveCaching = false;

    if (kDebugMode) {
      print('[PerformanceConfig] Switched to low CPU mode:');
      print('  - Gapless playback: disabled');
      print('  - Position updates: $positionUpdateInterval ms');
      print('  - Aggressive caching: disabled');
    }
  }

  /// Get optimized configuration for high quality (higher CPU usage)
  static void setHighQualityMode() {
    enableGaplessPlayback = true;
    positionUpdateInterval = 50; // Faster updates for smoother progress
    enableAggressiveCaching = true;

    if (kDebugMode) {
      print('[PerformanceConfig] Switched to high quality mode:');
      print('  - Gapless playback: enabled');
      print('  - Position updates: $positionUpdateInterval ms');
      print('  - Aggressive caching: enabled');
    }
  }
}