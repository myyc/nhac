import 'package:flutter/material.dart';
import 'navigation_menu.dart';

// Custom menu dialog for desktop to avoid hover effects
Future<String?> showCustomMenu({
  required BuildContext context,
  required Offset position,
  required List<Widget> items,
  double? buttonWidth,
  bool useRightAlignment = false,
}) async {
  return showDialog<String>(
    context: context,
    barrierColor: Colors.transparent,
    barrierDismissible: true,
    builder: (context) => _MenuDialog(
      position: position,
      items: items,
      buttonWidth: buttonWidth,
      useRightAlignment: useRightAlignment,
    ),
  );
}

class _MenuDialog extends StatefulWidget {
  final Offset position;
  final List<Widget> items;
  final double? buttonWidth;
  final bool useRightAlignment;

  const _MenuDialog({
    required this.position,
      required this.items,
      this.buttonWidth,
      this.useRightAlignment = false,
  });

  @override
  State<_MenuDialog> createState() => _MenuDialogState();
}

class _MenuDialogState extends State<_MenuDialog> {
  final GlobalKey _menuKey = GlobalKey();
  bool _isMenuOpen = true;

  void _closeMenu() {
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  
  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    // Convert position from local to global coordinates if needed
    final RenderBox? overlay = Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?;
    final globalPosition = overlay?.globalToLocal(widget.position) ?? widget.position;

    print('DEBUG: Global position conversion - Input: ${widget.position}, Output: $globalPosition');

    // Estimate menu height (rough calculation)
    final estimatedHeight = widget.items.length * 56.0 + 16.0; // 56 per item + padding

    // Determine if menu should go above or below
    final spaceBelow = screenHeight - widget.position.dy - 40;
    final showAbove = spaceBelow < estimatedHeight && widget.position.dy > estimatedHeight;

    // Calculate menu position
    double topPosition;
    if (showAbove) {
      topPosition = widget.position.dy - estimatedHeight;
    } else {
      topPosition = widget.position.dy + 40;
    }

    // If using right alignment, we don't need complex calculations
    double leftPosition = 0;
    if (!widget.useRightAlignment) {
      // Position menu - align right edge with button
      final menuWidth = 250.0; // Estimated width

      // Position is already the button's right edge, so align menu's right edge there
      leftPosition = widget.position.dx - menuWidth;
      print('DEBUG: Aligning menu right with button position - Position.dx: ${widget.position.dx}, Menu width: $menuWidth, Calculated left: $leftPosition');

      // Ensure menu stays within screen bounds
      if (leftPosition < 16) {
        leftPosition = 16;
      }
      if (leftPosition + menuWidth > screenWidth - 16) {
        leftPosition = screenWidth - menuWidth - 16;
      }
    }

    return Stack(
      children: [
        // Backdrop with custom hit testing
        Listener(
          onPointerDown: (event) {
            // Check if pointer is outside the menu
            final renderBox = _menuKey.currentContext?.findRenderObject() as RenderBox?;
            if (renderBox != null) {
              final menuRect = renderBox.localToGlobal(Offset.zero) & renderBox.size;
              if (!menuRect.contains(event.position)) {
                _closeMenu();
              }
            } else {
              _closeMenu();
            }
          },
          child: Container(color: Colors.transparent),
        ),
        // Menu with proper positioning
        widget.useRightAlignment
            ? Positioned(
                right: 8.0, // Match the button container's padding
                top: topPosition + 8, // Add 8px gap below the menu bar
                child: Material(
                  key: _menuKey,
                  color: Theme.of(context).scaffoldBackgroundColor,
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                      color: Colors.black.withOpacity(0.15),
                      width: 1,
                    ),
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: 200,
                      maxWidth: 300,
                      maxHeight: screenHeight - 32, // Leave some margin
                    ),
                    child: IntrinsicWidth(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: widget.items,
                      ),
                    ),
                  ),
                ),
              )
            : Positioned(
                left: leftPosition,
                top: topPosition + 8, // Add 8px gap below the menu bar
                child: Material(
                  key: _menuKey,
                  color: Theme.of(context).scaffoldBackgroundColor,
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                      color: Colors.black.withOpacity(0.15),
                      width: 1,
                    ),
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: 200,
                      maxWidth: 300,
                      maxHeight: screenHeight - 32, // Leave some margin
                    ),
                    child: IntrinsicWidth(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: widget.items,
                    ),
                  ),
                ),
              ),
              ),
            ],
          );
  }
}