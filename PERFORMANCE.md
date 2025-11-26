# Performance Configuration

This document explains how to configure the app for optimal performance, especially for reducing CPU usage during FLAC playback on Linux.

## Default Settings

By default, the app is configured for balanced performance:

- **Gapless playback**: Disabled (reduces CPU usage)
- **Position update interval**: 100ms (updates UI 10 times per second)
- **Aggressive caching**: Disabled (reduces background CPU usage)

## Environment Variables

You can override performance settings using environment variables at compile time:

```bash
# Enable gapless playback (higher CPU usage)
flutter run --dart-define=ENABLE_GAPLESS=true

# Set custom position update interval in milliseconds (50-1000)
flutter run --dart-define=POSITION_UPDATE_INTERVAL=50

# Enable aggressive background caching (higher CPU/disk usage)
flutter run --dart-define=ENABLE_AGGRESSIVE_CACHING=true
```

## Performance Modes

### Low CPU Mode (Default)
- Best for battery life and reducing CPU usage
- Gapless playback: Disabled
- Position updates: 100ms
- Aggressive caching: Disabled

### High Quality Mode
- Best for smooth experience with continuous playback
- Gapless playback: Enabled
- Position updates: 50ms (smoother progress bar)
- Aggressive caching: Enabled

To enable high quality mode programmatically:

```dart
import 'services/performance_config.dart';

// Enable high quality mode
PerformanceConfig.setHighQualityMode();

// Or enable low CPU mode
PerformanceConfig.setLowCpuMode();
```

## CPU Usage Optimization

The following optimizations have been implemented to reduce CPU usage:

1. **Throttled Position Updates**: Position stream updates are throttled to reduce UI rebuilds
2. **Debounced Notifications**: Multiple state changes are batched to minimize UI updates
3. **Buffered File Writes**: Downloads use 64KB buffers for efficient disk I/O
4. **Rate Limited Concurrent Operations**: Limited concurrent downloads and cache operations
5. **Reduced Background Caching**: Less aggressive pre-caching when disabled

## FLAC Playback on Linux

The app uses `just_audio_media_kit` with MPV backend on Linux. MPV can be CPU intensive with FLAC files due to:

1. High-quality audio decoding
2. Real-time audio processing
3. Gapless playback preparation

If you experience high CPU usage during FLAC playback:

1. Use the default low CPU mode
2. Consider transcoding FLAC to a more efficient format on the server
3. Close other CPU-intensive applications
4. Ensure your system's audio drivers are up to date

## Troubleshooting

If you still experience high CPU usage:

1. Check if gapless playback is enabled (disabling it helps significantly)
2. Monitor background caching activity in debug logs
3. Consider using lower quality audio formats
4. Update to the latest version of the app and dependencies