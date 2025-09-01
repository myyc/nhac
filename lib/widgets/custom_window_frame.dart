import 'package:flutter/material.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'dart:io' show Platform;

class CustomWindowFrame extends StatelessWidget {
  final Widget child;
  final Function(BuildContext)? onMenuPressed;

  const CustomWindowFrame({
    super.key,
    required this.child,
    this.onMenuPressed,
  });

  @override
  Widget build(BuildContext context) {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      return child;
    }

    return Stack(
      children: [
        // Main content
        child,
        // Window control buttons positioned at top right
        Positioned(
          top: 0,
          right: 0,
          child: WindowTitleBarBox(
            child: WindowButtons(onMenuPressed: onMenuPressed),
          ),
        ),
        // Invisible draggable area at the top
        Positioned(
          top: 0,
          left: 0,
          right: onMenuPressed != null ? 112 : 56, // Leave space for buttons
          child: WindowTitleBarBox(
            child: Container(
              height: 48, // Same height as the app bar
              color: Colors.transparent,
              child: MoveWindow(),
            ),
          ),
        ),
      ],
    );
  }
}

class WindowButtons extends StatefulWidget {
  final Function(BuildContext)? onMenuPressed;
  
  const WindowButtons({
    super.key,
    this.onMenuPressed,
  });

  @override
  State<WindowButtons> createState() => _WindowButtonsState();
}

class _WindowButtonsState extends State<WindowButtons> {
  final GlobalKey _menuButtonKey = GlobalKey();

  void _handleMenuPress() {
    if (widget.onMenuPressed != null && _menuButtonKey.currentContext != null) {
      widget.onMenuPressed!(_menuButtonKey.currentContext!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Container(
      height: 48,
      color: Colors.transparent,
      padding: const EdgeInsets.only(right: 8),
      child: Row(
        children: [
          if (widget.onMenuPressed != null)
            _WindowButton(
              key: _menuButtonKey,
              icon: Icons.menu,
              onPressed: _handleMenuPress,
              hoverColor: theme.colorScheme.onSurface.withOpacity(0.08),
              iconColor: theme.colorScheme.onSurface,
              iconSize: 24,
            ),
          if (widget.onMenuPressed != null)
            const SizedBox(width: 8),
          _WindowButton(
            icon: Icons.close,
            onPressed: () => appWindow.close(),
            hoverColor: Colors.red.withOpacity(0.1),
            iconColor: theme.colorScheme.onSurface,
            iconSize: 24,
          ),
        ],
      ),
    );
  }
}

class _WindowButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final Color? hoverColor;
  final Color? iconColor;
  final double? iconSize;
  
  const _WindowButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.hoverColor,
    this.iconColor,
    this.iconSize,
  });
  
  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _isHovering = false;
  
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: _isHovering 
                ? (widget.hoverColor ?? theme.colorScheme.onSurface.withOpacity(0.08))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Center(
            child: Icon(
              widget.icon,
              size: widget.iconSize ?? 18,
              color: widget.iconColor ?? theme.colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}