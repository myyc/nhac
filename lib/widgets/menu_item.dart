import 'package:flutter/material.dart';

class MenuItem extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final bool enabled;

  const MenuItem({
    super.key,
    required this.child,
    this.onTap,
    this.enabled = true,
  });

  @override
  State<MenuItem> createState() => _MenuItemState();
}

class _MenuItemState extends State<MenuItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: widget.enabled && _isHovered
                ? theme.colorScheme.primary
                : Colors.transparent,
          ),
          child: DefaultTextStyle(
            style: theme.textTheme.bodyMedium!.copyWith(
              color: widget.enabled && _isHovered
                  ? theme.scaffoldBackgroundColor
                  : widget.enabled
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurface.withOpacity(0.4),
              fontWeight: widget.enabled && _isHovered ? FontWeight.w700 : FontWeight.w500,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}