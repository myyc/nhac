import 'package:flutter/material.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'dart:io' show Platform;

class MacosWindowFrame extends StatefulWidget {
  final Widget child;
  final bool showMenuButton;

  const MacosWindowFrame({
    super.key,
    required this.child,
    this.showMenuButton = false,
  });

  @override
  State<MacosWindowFrame> createState() => _MacosWindowFrameState();
}

class _MacosWindowFrameState extends State<MacosWindowFrame> {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isMacOS) {
      _isMaximized = appWindow.isMaximized;
    }
  }

  void _toggleMaximize() {
    setState(() {
      if (_isMaximized) {
        appWindow.restore();
        _isMaximized = false;
      } else {
        appWindow.maximize();
        _isMaximized = true;
      }
    });
  }

  void _showMenu(BuildContext context) {
    showMenu(
      context: context,
      position: const RelativeRect.fromLTRB(60, 56, 0, 0),
      items: [
        const PopupMenuItem(
          value: 'logout',
          child: Text('Logout'),
        ),
      ],
    ).then((value) {
      if (value == 'logout' && mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Only apply for macOS
    if (!Platform.isMacOS) {
      return widget.child;
    }

    final theme = Theme.of(context);

    return Column(
      children: [
        // Permanent title bar for macOS
        WindowTitleBarBox(
          child: Container(
            height: 56,
            color: theme.colorScheme.surface,
            child: Stack(
              children: [
                // Draggable area
                Positioned.fill(
                  child: GestureDetector(
                    onDoubleTap: _toggleMaximize,
                    child: MoveWindow(),
                  ),
                ),
                // Controls on the right
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
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
                        if (widget.showMenuButton)
                          IconButton(
                            icon: const Icon(Icons.menu),
                            iconSize: 24,
                            onPressed: () => _showMenu(context),
                          ),
                        // Minimize button
                        IconButton(
                          icon: const Icon(Icons.remove),
                          iconSize: 24,
                          onPressed: () => appWindow.minimize(),
                          hoverColor: theme.colorScheme.onSurface.withOpacity(0.08),
                        ),
                        // Maximize/Restore button
                        IconButton(
                          icon: Icon(_isMaximized ? Icons.filter_none : Icons.crop_square),
                          iconSize: 24,
                          onPressed: _toggleMaximize,
                          hoverColor: theme.colorScheme.onSurface.withOpacity(0.08),
                        ),
                        // Close button
                        IconButton(
                          icon: const Icon(Icons.close),
                          iconSize: 24,
                          onPressed: () => appWindow.close(),
                          hoverColor: Colors.red.withOpacity(0.1),
                        ),
                        const SizedBox(width: 8), // Right padding
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Main content
        Expanded(
          child: widget.child,
        ),
      ],
    );
  }
}