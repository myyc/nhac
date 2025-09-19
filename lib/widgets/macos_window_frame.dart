import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'dart:io' show Platform;
import '../providers/auth_provider.dart';
import '../providers/admin_provider.dart';
import '../services/library_scan_service.dart';
import 'navigation_menu.dart';
import 'custom_menu_dialog.dart';

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
  bool _isMenuOpen = false;

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

  void _showMenu(BuildContext context) async {
    setState(() {
      _isMenuOpen = true;
    });

    // Get the window frame's render box
    final RenderBox? windowFrame = context.findRenderObject() as RenderBox?;
    if (windowFrame == null) return;

    // Calculate positions
    final windowFrameSize = windowFrame.size;
    final buttonsWidth = widget.showMenuButton ? 152.0 : 112.0; // Menu + Minimize + Maximize + Close + padding

    // Menu button is positioned from the right:
    // - 24px for the button itself
    // - 8px right padding
    // Total offset from right edge = 32px
    final menuButtonX = windowFrameSize.width - buttonsWidth + 8.0;

    final position = Offset(menuButtonX, 0);
    final buttonWidth = 24.0;

    // Check admin rights before showing menu
    final authProvider = context.read<AuthProvider>();
    final adminProvider = context.read<AdminProvider>();
    if (authProvider.api != null) {
      await adminProvider.checkAdminRights(authProvider.api!);
    }

    // Keep the hamburger menu visible while showing menu
    final result = await showCustomMenu(
      context: context,
      position: position,
      buttonWidth: 24.0, // Menu button width
      items: [
        NavigationMenuDesktop(
          context: context,
          position: position,
          onQuickScan: () async {
            Navigator.of(context).pop('quick-scan');
          },
          onLogout: () async {
            Navigator.of(context).pop('logout');
          },
        ),
      ],
    );

    setState(() {
      _isMenuOpen = false;
    });

    if (result == 'quick-scan' && mounted) {
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
    } else if (result == 'logout' && mounted) {
      await context.read<AuthProvider>().logout();
    }
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