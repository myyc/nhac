import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/lyrics.dart';
import '../models/song.dart';
import '../providers/auth_provider.dart';
import '../providers/player_provider.dart';
import '../widgets/custom_window_frame.dart';

class LyricsScreen extends StatefulWidget {
  final Song song;

  const LyricsScreen({super.key, required this.song});

  @override
  State<LyricsScreen> createState() => _LyricsScreenState();
}

class _LyricsScreenState extends State<LyricsScreen> {
  Lyrics? _lyrics;
  bool _loading = true;
  String? _error;

  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _lineKeys = {};
  int _activeLineIndex = -1;
  String? _loadedSongId;

  @override
  void initState() {
    super.initState();
    _fetchLyrics(widget.song);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchLyrics(Song song) async {
    _loadedSongId = song.id;
    setState(() {
      _loading = true;
      _error = null;
      _lyrics = null;
      _activeLineIndex = -1;
      _lineKeys.clear();
    });

    final api = context.read<AuthProvider>().api;
    if (api == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Not connected';
      });
      return;
    }

    try {
      final lyrics = await api.getLyricsBySongId(
        song.id,
        artist: song.artist,
        title: song.title,
      );
      if (!mounted || _loadedSongId != song.id) return;
      setState(() {
        _lyrics = lyrics;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || _loadedSongId != song.id) return;
      setState(() {
        _loading = false;
        _error = 'Could not load lyrics';
      });
    }
  }

  int _findActiveLine(Duration position) {
    final lyrics = _lyrics;
    if (lyrics == null || !lyrics.synced) return -1;
    int idx = -1;
    for (var i = 0; i < lyrics.lines.length; i++) {
      final start = lyrics.lines[i].start;
      if (start == null) continue;
      if (start <= position) {
        idx = i;
      } else {
        break;
      }
    }
    return idx;
  }

  void _scrollToActive(int index) {
    if (index < 0) return;
    final key = _lineKeys[index];
    final ctx = key?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      alignment: 0.4,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scaffold = Consumer<PlayerProvider>(
      builder: (context, player, _) {
        final currentSong = player.currentSong;

        // If track changed, reload lyrics for the new song.
        if (currentSong != null && currentSong.id != _loadedSongId) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _fetchLyrics(currentSong);
          });
        }

        final lyrics = _lyrics;
        if (lyrics != null && lyrics.synced) {
          final newIndex = _findActiveLine(player.position);
          if (newIndex != _activeLineIndex) {
            _activeLineIndex = newIndex;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _scrollToActive(newIndex);
            });
          }
        }

        return Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: Text(
              currentSong?.title ?? widget.song.title,
              style: Theme.of(context).textTheme.titleMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          body: SafeArea(child: _buildBody(player)),
        );
      },
    );

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return RawKeyboardListener(
        focusNode: FocusNode(),
        autofocus: true,
        onKey: (event) {
          if (event is RawKeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            Navigator.of(context).pop();
          }
        },
        child: CustomWindowFrame(child: scaffold),
      );
    }
    return scaffold;
  }

  Widget _buildBody(PlayerProvider player) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
    }
    final lyrics = _lyrics;
    if (lyrics == null || lyrics.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lyrics_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
            ),
            const SizedBox(height: 12),
            Text(
              'No lyrics available',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                  ),
            ),
          ],
        ),
      );
    }

    final theme = Theme.of(context);
    final inactiveColor = theme.colorScheme.onSurface.withOpacity(0.65);
    // Active uses full-opacity onSurface (pure white in dark mode) for maximum
    // brightness; size+weight bump keeps the visual emphasis for CJK glyphs.
    final activeColor = theme.colorScheme.onSurface;

    final baseStyle = TextStyle(
      fontSize: 26,
      height: 1.4,
      fontWeight: FontWeight.w600,
      color: inactiveColor,
    );
    final activeStyle = TextStyle(
      fontSize: 32,
      height: 1.4,
      fontWeight: FontWeight.w800,
      color: activeColor,
    );

    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.symmetric(
        horizontal: 24,
        vertical: MediaQuery.of(context).size.height * 0.3,
      ),
      itemCount: lyrics.lines.length,
      itemBuilder: (context, index) {
        final line = lyrics.lines[index];
        final key = _lineKeys.putIfAbsent(index, () => GlobalKey());
        final isActive = lyrics.synced && index == _activeLineIndex;
        final text = line.text.trim();

        Widget content = Padding(
          key: key,
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            style: isActive ? activeStyle : baseStyle,
            child: Text(
              text.isEmpty ? '\u00B7' : text,
              textAlign: TextAlign.center,
            ),
          ),
        );

        if (lyrics.synced && line.start != null) {
          content = InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () async {
              await player.seek(line.start!);
              if (!player.isPlaying) {
                await player.play();
              }
            },
            child: content,
          );
        }
        return content;
      },
    );
  }
}
