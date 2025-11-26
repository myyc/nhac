import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/player_provider.dart';
import '../providers/network_provider.dart';
import '../widgets/now_playing_bar.dart';
import '../widgets/offline_indicator.dart';

class AppScaffold extends StatelessWidget {
  final Widget child;
  final PreferredSizeWidget? appBar;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final bool showNowPlayingBar;

  const AppScaffold({
    super.key,
    required this.child,
    this.appBar,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.showNowPlayingBar = true,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: appBar,
      body: Column(
        children: [
          Expanded(child: child),
          const OfflineIndicator(),
          if (showNowPlayingBar)
            Consumer<PlayerProvider>(
              builder: (context, playerProvider, _) {
                if (playerProvider.currentSong != null) {
                  return const NowPlayingBar();
                }
                return const SizedBox.shrink();
              },
            ),
        ],
      ),
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
    );
  }
}