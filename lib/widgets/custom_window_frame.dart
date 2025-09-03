import 'package:flutter/material.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'dart:io' show Platform;

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

  void _showMenu(BuildContext context) {
    showMenu(
      context: context,
      position: const RelativeRect.fromLTRB(0, 48, 0, 0),
      items: [
        const PopupMenuItem(
          value: 'logout',
          child: Text('Logout'),
        ),
      ],
    ).then((value) {
      if (value == 'logout' && mounted) {
        // Import and call logout from auth provider
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      return widget.child;
    }

    return Stack(
      children: [
        // Main content
        widget.child,
        // Hover area for window controls - positioned to match AppBar
        Positioned(
          top: 0,
          right: 0,
          child: MouseRegion(
            onEnter: (_) => setState(() => _isHoveringButtons = true),
            onExit: (_) => setState(() => _isHoveringButtons = false),
            child: AnimatedOpacity(
              opacity: _isHoveringButtons ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                width: widget.showMenuButton ? 112 : 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(8),
                  ),
                ),
                child: WindowTitleBarBox(
                  child: WindowButtons(
                    showMenuButton: widget.showMenuButton,
                    onMenuPressed: widget.showMenuButton ? _showMenu : null,
                  ),
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
          right: widget.showMenuButton ? 112 : 56, // Leave space for window buttons
          child: WindowTitleBarBox(
            child: Container(
              height: 56, // Same height as the app bar
              color: Colors.transparent,
              child: MoveWindow(),
            ),
          ),
        ),
      ],
    );
  }
}

class WindowButtons extends StatelessWidget {
  final bool showMenuButton;
  final Function(BuildContext)? onMenuPressed;
  
  const WindowButtons({
    super.key,
    this.showMenuButton = false,
    this.onMenuPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Container(
      height: 56,
      color: Colors.transparent,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (showMenuButton && onMenuPressed != null)
            IconButton(
              icon: Icon(Icons.menu),
              iconSize: 24,
              onPressed: () => onMenuPressed!(context),
            ),
          IconButton(
            icon: Icon(Icons.close),
            iconSize: 24,
            onPressed: () => appWindow.close(),
            hoverColor: Colors.red.withOpacity(0.1),
          ),
        ],
      ),
    );
  }
}

// Removed _WindowButton class as we now use standard IconButton