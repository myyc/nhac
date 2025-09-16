import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'dart:io' show Platform;
import '../providers/auth_provider.dart';
import '../providers/admin_provider.dart';
import '../services/library_scan_service.dart';
import 'navigation_menu.dart';

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

  void _showMenu(BuildContext context) async {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay = Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final Offset position = button.localToGlobal(Offset.zero, ancestor: overlay);

    // Check admin rights before showing menu
    final authProvider = context.read<AuthProvider>();
    final adminProvider = context.read<AdminProvider>();
    if (authProvider.api != null) {
      await adminProvider.checkAdminRights(authProvider.api!);
    }

    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy + button.size.height,
        position.dx,
        position.dy + button.size.height,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'quick-scan',
          child: NavigationMenuDesktop(
            context: context,
            position: position,
          ),
        ),
        const PopupMenuDivider(height: 1),
        const PopupMenuItem<String>(
          value: 'logout',
          child: Text('Logout'),
        ),
      ],
    );

    if (result == 'quick-scan' && mounted) {
      await _handleQuickScan(context);
    } else if (result == 'logout' && mounted) {
      await context.read<AuthProvider>().logout();
    }
  }

  Future<void> _handleQuickScan(BuildContext context) async {
    final authProvider = context.read<AuthProvider>();
    final adminProvider = context.read<AdminProvider>();

    if (!adminProvider.canScan) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You do not have permission to perform library scans'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    // Show loading indicator
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Starting library scan...'),
        duration: Duration(seconds: 2),
      ),
    );

    try {
      final libraryScanService = LibraryScanService(api: authProvider.api!);
      await libraryScanService.startBackgroundScan();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Library scan started successfully'),
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to start scan: ${e.toString()}'),
          duration: Duration(seconds: 3),
        ),
      );
    }
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
                width: widget.showMenuButton ? 96 : 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(10),
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
          right: widget.showMenuButton ? 96 : 56, // Leave space for window buttons
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
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(10),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
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
          const SizedBox(width: 8), // Add right padding
        ],
      ),
    );
  }
}

// Removed _WindowButton class as we now use standard IconButton