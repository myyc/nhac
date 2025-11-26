import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'providers/auth_provider.dart';
import 'providers/player_provider.dart';
import 'providers/cache_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/network_provider.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'services/database_helper.dart';
import 'services/audio_handler.dart';
import 'services/navidrome_api.dart';
import 'services/album_download_service.dart';
import 'services/activity_coordinator.dart';
import 'services/audio_cache_manager.dart';
import 'dart:async';

late BaseAudioHandler? audioHandler;
late NhacAudioHandler? actualAudioHandler;
late AudioPlayer globalAudioPlayer;
bool _isCleanedUp = false;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize just_audio with media_kit backend for Linux only
  // macOS uses the native just_audio implementation
  if (Platform.isLinux) {
    JustAudioMediaKit.ensureInitialized();
  }
  
  // Initialize database
  try {
    await DatabaseHelper.database;
  } catch (e) {
    print('Warning: Could not initialize database: $e');
  }
  
  // Create a single AudioPlayer instance to be shared
  globalAudioPlayer = AudioPlayer();
  
  // Initialize audio service for Android and Linux
  if (Platform.isAndroid || Platform.isLinux) {
    // Create a dummy API instance that will be replaced later
    final dummyApi = NavidromeApi(
      baseUrl: 'http://localhost',
      username: '',
      password: '',
    );
    // Create a dummy network provider that will be replaced later
    final dummyNetworkProvider = NetworkProvider();

    // Create the actual handler
    actualAudioHandler = NhacAudioHandler(
      globalAudioPlayer, // Use the shared player instance
      dummyApi, // This will be properly set later in PlayerProvider
      networkProvider: dummyNetworkProvider, // Will be set later
    );
    
    audioHandler = await AudioService.init(
      builder: () => actualAudioHandler!,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'dev.myyc.nhac.channel.audio',
        androidNotificationChannelName: 'Music playback',
        androidNotificationIcon: 'drawable/ic_notification',
        androidNotificationOngoing: false,
        androidStopForegroundOnPause: false, // Keep service alive during pause
      ),
    );
  } else {
    audioHandler = null;
  }
  
  // Window initialization is handled by bitsdojo_window below
  
  runApp(const NhacApp());
  
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    doWhenWindowReady(() {
      const initialSize = Size(1200, 800);
      appWindow.minSize = const Size(600, 400);
      appWindow.size = initialSize;
      appWindow.alignment = Alignment.center;
      appWindow.show();
    });
  }
}

class NhacApp extends StatelessWidget {
  const NhacApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => PlayerProvider()),
          ChangeNotifierProvider(create: (_) => CacheProvider()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => NetworkProvider()),
          ChangeNotifierProvider(create: (_) => ActivityCoordinator()),
          ChangeNotifierProxyProvider2<AuthProvider, NetworkProvider, AlbumDownloadService?>(
            create: (_) => null, // Created when auth is ready
            update: (context, auth, network, previous) {
              if (auth.api == null) return previous;

              if (previous == null) {
                // First creation
                return AlbumDownloadService(
                  api: auth.api!,
                  networkProvider: network,
                );
              } else {
                // Update existing instance without losing state
                previous.updateDependencies(
                  api: auth.api!,
                  networkProvider: network,
                );
                return previous;
              }
            },
          ),
        ],
        child: Consumer2<ThemeProvider, PlayerProvider>(
          builder: (context, themeProvider, playerProvider, child) {
            // Connect the providers
            if (themeProvider.currentColors == null) {
              themeProvider.setPlayerProvider(playerProvider);
            }
            
            return CallbackShortcuts(
              bindings: {
                LogicalKeySet(LogicalKeyboardKey.space): () {
                  // Only toggle play/pause if no text field is focused
                  final primaryFocus = FocusManager.instance.primaryFocus;
                  if (primaryFocus != null && 
                      primaryFocus.context != null && 
                      primaryFocus.context!.widget is! EditableText) {
                    playerProvider.togglePlayPause();
                  }
                },
              },
              child: Focus(
                autofocus: true,
                child: MaterialApp(
                  title: 'Nhac',
                  debugShowCheckedModeBanner: false,
                  theme: themeProvider.getDarkTheme(),
                  darkTheme: themeProvider.getDarkTheme(),
                  themeMode: ThemeMode.dark,
                  home: const AuthWrapper(),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> with WidgetsBindingObserver {
  bool _hasInitializedProviders = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeAuth();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cleanupBeforeExit();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (!_hasInitializedProviders) return;

    final activityCoordinator = context.read<ActivityCoordinator>();
    final cacheProvider = context.read<CacheProvider>();
    final networkProvider = context.read<NetworkProvider>();

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        // App going to background - update foreground state
        debugPrint('[Main] App backgrounded');
        activityCoordinator.setForegroundState(false);
        break;
      case AppLifecycleState.resumed:
        // App coming to foreground - update foreground state
        debugPrint('[Main] App resumed');
        activityCoordinator.setForegroundState(true);
        break;
      case AppLifecycleState.detached:
        // App is being terminated - clean up resources
        debugPrint('[Main] App detached - cleaning up');
        _cleanupBeforeExit();
        break;
    }

    // Handle suspend/resume based on activity state
    if (activityCoordinator.isIdle) {
      cacheProvider.suspend();
      networkProvider.suspendHealthChecks();
      AudioCacheManager().suspend();
    } else {
      cacheProvider.resume();
      if (activityCoordinator.shouldRunHealthChecks) {
        networkProvider.resumeHealthChecks();
      }
      AudioCacheManager().resume();
    }
  }

  Future<void> _initializeAuth() async {
    await context.read<AuthProvider>().initialize();
  }

  void _cleanupBeforeExit() {
    // Prevent double cleanup
    if (_isCleanedUp) return;
    _isCleanedUp = true;

    debugPrint('[Main] Cleaning up before exit...');

    // Stop the global audio player immediately to prevent hanging
    try {
      globalAudioPlayer.stop();
    } catch (e) {
      debugPrint('[Main] Error stopping audio: $e');
    }

    // Cancel any background tasks
    if (_hasInitializedProviders) {
      try {
        context.read<CacheProvider>().suspend();
        context.read<NetworkProvider>().suspendHealthChecks();
        AudioCacheManager().suspend();
      } catch (e) {
        debugPrint('[Main] Error during cleanup: $e');
      }
    }

    debugPrint('[Main] Cleanup complete');
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        if (authProvider.isLoading) {
          // Random loading messages for fun
          final loadingMessages = [
            'Loading',
            'Vibing',
            'Crunching',
            'Pondering',
            'Simmering',
            'Shimmering',
            'Grooving',
            'Jamming',
            'Tuning',
            'Spinning',
            'Brewing',
            'Syncing',
            'Harmonizing',
            'Composing',
            'Buffering',
          ];
          final randomMessage = loadingMessages[
            DateTime.now().millisecondsSinceEpoch % loadingMessages.length
          ];
          
          return Scaffold(
            backgroundColor: Theme.of(context).colorScheme.surface,
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.music_note,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    randomMessage,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 32),
                  CircularProgressIndicator(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
            ),
          );
        }

        if (authProvider.isAuthenticated) {
          // Only initialize providers once to prevent multiple setApi calls
          if (!_hasInitializedProviders) {
            _hasInitializedProviders = true;
            final playerProvider = context.read<PlayerProvider>();
            final cacheProvider = context.read<CacheProvider>();
            final networkProvider = context.read<NetworkProvider>();
            final activityCoordinator = context.read<ActivityCoordinator>();
            final albumDownloadService = context.read<AlbumDownloadService?>();

            // Wire up ActivityCoordinator for battery optimization
            playerProvider.setActivityCoordinator(activityCoordinator);
            albumDownloadService?.setActivityCoordinator(activityCoordinator);

            // Register suspend/resume callbacks with coordinator
            activityCoordinator.registerSuspendCallback(() {
              cacheProvider.suspend();
              networkProvider.suspendHealthChecks();
              AudioCacheManager().suspend();
            });
            activityCoordinator.registerResumeCallback(() {
              cacheProvider.resume();
              if (activityCoordinator.shouldRunHealthChecks) {
                networkProvider.resumeHealthChecks();
              }
              AudioCacheManager().resume();
            });

            playerProvider.setApi(authProvider.api!, networkProvider: networkProvider);
            cacheProvider.initialize(authProvider.api!, networkProvider);

            // Enable server health monitoring for connection resilience
            networkProvider.setApi(authProvider.api!);
            // Allow API to report failures to NetworkProvider (circuit breaker)
            authProvider.api!.setNetworkProvider(networkProvider);

            // MPRIS is now handled through audio_service, no separate initialization needed

            // Check if this is first run and initialize cache
            _initializeFirstRunCache(cacheProvider, networkProvider);
          }
          
          return const HomeScreen();
        }

        return const LoginScreen();
      },
    );
  }

  Future<void> _initializeFirstRunCache(
    CacheProvider cacheProvider,
    NetworkProvider networkProvider,
  ) async {
    // Check if this is the first run
    final firstRunKey = 'first_run_completed';
    final isFirstRun = await DatabaseHelper.getSyncMetadata(firstRunKey) == null;

    if (isFirstRun) {
      print('[Main] First run detected, initializing cache...');

      // Don't block the UI, run in background
      unawaited(() async {
        try {
          // Wait a bit for the app to fully initialize
          await Future.delayed(const Duration(seconds: 5));

          // If online, perform initial cache sync
          if (!networkProvider.isOffline) {
            print('[Main] Starting initial library sync...');
            await cacheProvider.syncFullLibrary();
            print('[Main] Initial library sync completed');
          }

          // Mark first run as completed
          await DatabaseHelper.setSyncMetadata(firstRunKey, 'true');
          print('[Main] First run initialization completed');
        } catch (e) {
          print('[Main] Error during first run initialization: $e');
        }
      }());
    }
  }
}