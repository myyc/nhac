import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class CustomTitleBar extends StatefulWidget implements PreferredSizeWidget {
  final Widget? title;
  final List<Widget>? actions;
  final Widget? leading;

  const CustomTitleBar({
    super.key,
    this.title,
    this.actions,
    this.leading,
  });

  @override
  Size get preferredSize => const Size.fromHeight(48);

  @override
  State<CustomTitleBar> createState() => _CustomTitleBarState();
}

class _CustomTitleBarState extends State<CustomTitleBar> {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      windowManager.isMaximized().then((v) {
        if (mounted) setState(() => _isMaximized = v);
      });
    }
  }

  void _toggleMaximize() async {
    if (_isMaximized) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
    if (mounted) {
      setState(() => _isMaximized = !_isMaximized);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isLinux && !Platform.isWindows && !Platform.isMacOS) {
      return AppBar(
        title: widget.title,
        actions: widget.actions,
        leading: widget.leading,
      );
    }

    final theme = Theme.of(context);

    return SizedBox(
      height: 48,
      child: Material(
        color: theme.colorScheme.surface,
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: theme.dividerColor,
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              if (widget.leading != null) widget.leading!,
              if (widget.leading == null) const SizedBox(width: 16),
              if (widget.title != null)
                Expanded(
                  child: GestureDetector(
                    onDoubleTap: _toggleMaximize,
                    onPanStart: (_) => windowManager.startDragging(),
                    child: DefaultTextStyle(
                      style: theme.textTheme.titleLarge!,
                      child: widget.title!,
                    ),
                  ),
                ),
              if (widget.title == null)
                Expanded(
                  child: GestureDetector(
                    onDoubleTap: _toggleMaximize,
                    onPanStart: (_) => windowManager.startDragging(),
                    child: Container(color: Colors.transparent),
                  ),
                ),
              if (widget.actions != null) ...widget.actions!,

              // Window control buttons
              _WindowButton(
                icon: Icons.remove,
                onPressed: () => windowManager.minimize(),
                hoverColor: theme.colorScheme.onSurface.withOpacity(0.08),
              ),
              _WindowButton(
                icon: _isMaximized ? Icons.filter_none : Icons.crop_square,
                onPressed: _toggleMaximize,
                hoverColor: theme.colorScheme.onSurface.withOpacity(0.08),
              ),
              _WindowButton(
                icon: Icons.close,
                onPressed: () => windowManager.close(),
                hoverColor: Colors.red.withOpacity(0.1),
                iconColor: Colors.red,
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _WindowButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final Color? hoverColor;
  final Color? iconColor;

  const _WindowButton({
    required this.icon,
    required this.onPressed,
    this.hoverColor,
    this.iconColor,
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
          width: 46,
          height: 48,
          decoration: BoxDecoration(
            color: _isHovering
                ? (widget.hoverColor ?? theme.colorScheme.onSurface.withOpacity(0.08))
                : Colors.transparent,
          ),
          child: Center(
            child: Icon(
              widget.icon,
              size: 18,
              color: widget.iconColor ?? theme.colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
