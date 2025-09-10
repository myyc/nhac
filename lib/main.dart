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
import 'theme/app_theme.dart';

late BaseAudioHandler? audioHandler;
late NhacAudioHandler? actualAudioHandler;
late AudioPlayer globalAudioPlayer;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize just_audio with media_kit backend for Linux and macOS
  // This provides better codec support including FLAC
  if (Platform.isLinux || Platform.isMacOS) {
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
    // Create the actual handler
    actualAudioHandler = NhacAudioHandler(
      globalAudioPlayer, // Use the shared player instance
      dummyApi, // This will be properly set later in PlayerProvider
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

class _AuthWrapperState extends State<AuthWrapper> {
  bool _hasInitializedProviders = false;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeAuth();
    });
  }

  Future<void> _initializeAuth() async {
    await context.read<AuthProvider>().initialize();
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
            playerProvider.setApi(authProvider.api!, networkProvider: networkProvider);
            cacheProvider.initialize(authProvider.api!, networkProvider);
            
            // MPRIS is now handled through audio_service, no separate initialization needed
          }
          
          return const HomeScreen();
        }

        return const LoginScreen();
      },
    );
  }
}