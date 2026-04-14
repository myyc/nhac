import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:provider/provider.dart';
import 'dart:io' show Platform;
import '../providers/auth_provider.dart';

class CustomWindowFrame extends StatefulWidget {
  final Widget child;
  final bool showMenuButton;

  const CustomWindowFrame({
    super.key,
    required this.child,
    this.showMenuButton = false,
  });

  @override
  State<CustomWindowFrame> createState() => _CustomWindowFrameState();
}

class _CustomWindowFrameState extends State<CustomWindowFrame> {
  bool _isHoveringButtons = false;
  bool _isMenuOpen = false;

  void _showMenu(BuildContext context, GlobalKey buttonKey) {
    final RenderBox button = buttonKey.currentContext!.findRenderObject() as RenderBox;
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final buttonPosition = button.localToGlobal(Offset.zero, ancestor: overlay);

    // Position menu below the button, aligned to the right edge
    final position = RelativeRect.fromLTRB(
      buttonPosition.dx,
      buttonPosition.dy + button.size.height,
      overlay.size.width - buttonPosition.dx - button.size.width,
      0,
    );

    setState(() => _isMenuOpen = true);

    showMenu(
      context: context,
      position: position,
      items: [
        const PopupMenuItem(
          value: 'logout',
          child: Text('Logout'),
        ),
      ],
    ).then((value) {
      if (mounted) {
        setState(() => _isMenuOpen = false);
      }
      if (value == 'logout' && mounted) {
        // Logout via AuthProvider - AuthWrapper will show login screen
        context.read<AuthProvider>().logout();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Only apply custom window frame for Windows and Linux
    // macOS has its own implementation in MacosWindowFrame
    if (!Platform.isWindows && !Platform.isLinux) {
      return widget.child;
    }

    return Stack(
      children: [
        // Main content
        widget.child,
        // Resize handles around the window edges. TitleBarStyle.hidden tells
        // GTK to drop its decorations, including the resize border, so we
        // recreate them ourselves with windowManager.startResizing.
        ..._resizeHandles(),
        // Hover area for window controls - positioned to match AppBar
        Positioned(
          top: 0,
          right: 0,
          child: MouseRegion(
            onEnter: (_) => setState(() => _isHoveringButtons = true),
            onExit: (_) => setState(() => _isHoveringButtons = false),
            child: AnimatedOpacity(
              opacity: (_isHoveringButtons || _isMenuOpen) ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                width: widget.showMenuButton ? 96 : 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(10),
                  ),
                ),
                child: WindowButtons(
                  showMenuButton: widget.showMenuButton,
                  onMenuPressed: widget.showMenuButton ? _showMenu : null,
                ),
              ),
            ),
          ),
        ),
        // Invisible draggable area at the top
        // Start at left: 56 to avoid overlapping with back button
        Positioned(
          top: 0,
          left: 56, // Leave space for back button
          right: widget.showMenuButton ? 96 : 56, // Leave space for window buttons
          child: GestureDetector(
            onPanStart: (_) => windowManager.startDragging(),
            child: Container(
              height: 56, // Same height as the app bar
              color: Colors.transparent,
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _resizeHandles() {
    const thickness = 6.0;
    const cornerSize = 12.0;

    Widget edge({
      required ResizeEdge edge,
      double? top,
      double? left,
      double? right,
      double? bottom,
      double? width,
      double? height,
      MouseCursor? cursor,
    }) {
      return Positioned(
        top: top,
        left: left,
        right: right,
        bottom: bottom,
        width: width,
        height: height,
        child: MouseRegion(
          cursor: cursor ?? MouseCursor.defer,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: (_) => windowManager.startResizing(edge),
          ),
        ),
      );
    }

    return [
      // Edges
      edge(edge: ResizeEdge.top, top: 0, left: cornerSize, right: cornerSize, height: thickness, cursor: SystemMouseCursors.resizeUpDown),
      edge(edge: ResizeEdge.bottom, bottom: 0, left: cornerSize, right: cornerSize, height: thickness, cursor: SystemMouseCursors.resizeUpDown),
      edge(edge: ResizeEdge.left, left: 0, top: cornerSize, bottom: cornerSize, width: thickness, cursor: SystemMouseCursors.resizeLeftRight),
      edge(edge: ResizeEdge.right, right: 0, top: cornerSize, bottom: cornerSize, width: thickness, cursor: SystemMouseCursors.resizeLeftRight),
      // Corners
      edge(edge: ResizeEdge.topLeft, top: 0, left: 0, width: cornerSize, height: cornerSize, cursor: SystemMouseCursors.resizeUpLeftDownRight),
      edge(edge: ResizeEdge.topRight, top: 0, right: 0, width: cornerSize, height: cornerSize, cursor: SystemMouseCursors.resizeUpRightDownLeft),
      edge(edge: ResizeEdge.bottomLeft, bottom: 0, left: 0, width: cornerSize, height: cornerSize, cursor: SystemMouseCursors.resizeUpRightDownLeft),
      edge(edge: ResizeEdge.bottomRight, bottom: 0, right: 0, width: cornerSize, height: cornerSize, cursor: SystemMouseCursors.resizeUpLeftDownRight),
    ];
  }
}

class WindowButtons extends StatefulWidget {
  final bool showMenuButton;
  final Function(BuildContext, GlobalKey)? onMenuPressed;

  const WindowButtons({
    super.key,
    this.showMenuButton = false,
    this.onMenuPressed,
  });

  @override
  State<WindowButtons> createState() => _WindowButtonsState();
}

class _WindowButtonsState extends State<WindowButtons> {
  final GlobalKey _menuButtonKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(10),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (widget.showMenuButton && widget.onMenuPressed != null)
            IconButton(
              key: _menuButtonKey,
              icon: Icon(Icons.menu),
              iconSize: 24,
              onPressed: () => widget.onMenuPressed!(context, _menuButtonKey),
            ),
          IconButton(
            icon: Icon(Icons.close),
            iconSize: 24,
            onPressed: () => windowManager.close(),
            hoverColor: Colors.red.withOpacity(0.1),
          ),
          const SizedBox(width: 8), // Add right padding
        ],
      ),
    );
  }
}
