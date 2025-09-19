import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/admin_provider.dart';
import '../services/library_scan_service.dart';
import 'menu_item.dart';

class NavigationMenu extends StatefulWidget {
  final Widget child;
  final VoidCallback? onClose;

  const NavigationMenu({
    super.key,
    required this.child,
    this.onClose,
  });

  @override
  State<NavigationMenu> createState() => _NavigationMenuState();
}

class _NavigationMenuState extends State<NavigationMenu>
    with TickerProviderStateMixin {
  late AnimationController _slideController;
  late AnimationController _backdropController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _backdropAnimation;

  bool _isMenuOpen = false;
  double _dragStartX = 0.0;
  double _currentDragX = 0.0;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _backdropController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(-1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));

    _backdropAnimation = Tween<double>(
      begin: 0.0,
      end: 0.5,
    ).animate(CurvedAnimation(
      parent: _backdropController,
      curve: Curves.easeOutCubic,
    ));
  }

  @override
  void dispose() {
    _slideController.dispose();
    _backdropController.dispose();
    super.dispose();
  }

  
  void _openMenu() {
    setState(() {
      _isMenuOpen = true;
    });
    _slideController.forward();
    _backdropController.forward();

    // Check admin rights when menu opens
    final authProvider = context.read<AuthProvider>();
    final adminProvider = context.read<AdminProvider>();
    if (authProvider.api != null) {
      adminProvider.checkAdminRights(authProvider.api!);
    }
  }

  void _closeMenu() {
    _slideController.reverse();
    _backdropController.reverse().then((_) {
      if (mounted) {
        setState(() {
          _isMenuOpen = false;
        });
        widget.onClose?.call();
      }
    });
  }

  void _handleHorizontalDragStart(DragStartDetails details) {
    // Only start drag for menu if we're swiping from the left edge (first 40px)
    // This prevents interference with normal horizontal scrolling/navigation
    if (!_isMenuOpen && details.localPosition.dx < 40) {
      _isDragging = true;
      _dragStartX = details.localPosition.dx;
      print('DEBUG: Starting menu drag from edge');
    } else if (_isMenuOpen && details.localPosition.dx > MediaQuery.of(context).size.width * 0.7) {
      // Allow closing menu by swiping from the right edge when menu is open
      _isDragging = true;
      _dragStartX = details.localPosition.dx;
      print('DEBUG: Starting menu close drag');
    }
  }

  void _handleHorizontalDragUpdate(DragUpdateDetails details) {
    if (!_isDragging) return;

    final deltaX = details.localPosition.dx - _dragStartX;

    if (!_isMenuOpen && deltaX > 0) {
      // Opening menu - only allow rightward swipe from left edge
      setState(() {
        _currentDragX = deltaX.clamp(0.0, MediaQuery.of(context).size.width * 0.8);
      });
    } else if (_isMenuOpen && deltaX < 0) {
      // Closing menu - allow leftward swipe when menu is open
      setState(() {
        _currentDragX = deltaX.clamp(-MediaQuery.of(context).size.width * 0.8, 0.0);
      });
    } else if (!_isMenuOpen && deltaX < 0) {
      // User is trying to swipe left (normal navigation) - cancel menu drag
      _isDragging = false;
      setState(() {
        _currentDragX = 0.0;
      });
    }
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    if (!_isDragging) return;

    _isDragging = false;

    final threshold = MediaQuery.of(context).size.width * 0.2; // Lower threshold for easier opening

    if (!_isMenuOpen && _currentDragX > threshold) {
      // User dragged far enough to open menu
      _openMenu();
    } else if (_isMenuOpen && _currentDragX < -threshold) {
      // User dragged far enough to close menu
      _closeMenu();
    }

    // Reset drag position
    setState(() {
      _currentDragX = 0.0;
    });
  }

  Future<void> _performQuickScan() async {
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

    // Close menu first
    _closeMenu();

    // Show loading indicator
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Starting library scan...'),
        duration: Duration(seconds: 2),
      ),
    );

    // Perform scan
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

  Future<void> _handleLogout() async {
    _closeMenu();

    // Add a small delay to allow menu to close
    await Future.delayed(const Duration(milliseconds: 300));

    if (mounted) {
      await context.read<AuthProvider>().logout();
    }
  }

  Widget _buildMenuContent() {
    final theme = Theme.of(context);
    final adminProvider = context.watch<AdminProvider>();

    return Container(
      width: MediaQuery.of(context).size.width * 0.8,
      height: MediaQuery.of(context).size.height,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(2, 0),
          ),
        ],
        border: Border(
          right: BorderSide(
            color: Colors.black.withOpacity(0.15),
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Menu',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Manage your library and account',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Menu Items
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  // Quick Scan Option
                  ListTile(
                    title: Text(
                      'Quick Scan Library',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: adminProvider.canScan
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.onSurface.withOpacity(0.4),
                      ),
                    ),
                    subtitle: adminProvider.isLoading
                        ? Text(
                            'Checking permissions...',
                            style: TextStyle(
                              color: theme.colorScheme.onSurface.withOpacity(0.7),
                              fontSize: 12,
                            ),
                          )
                        : !adminProvider.canScan
                            ? Text(
                                'Admin rights required',
                                style: TextStyle(
                                  color: theme.colorScheme.onSurface.withOpacity(0.7),
                                  fontSize: 12,
                                ),
                              )
                            : Text(
                                'Scan your music library',
                                style: TextStyle(
                                  color: theme.colorScheme.onSurface.withOpacity(0.7),
                                  fontSize: 12,
                                ),
                              ),
                    onTap: adminProvider.canScan ? _performQuickScan : null,
                    enabled: adminProvider.canScan,
                  ),

                  const SizedBox(height: 8),

                  // Logout Option
                  ListTile(
                    title: Text(
                      'Log Out',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    subtitle: Text(
                      'Sign out of your account',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withOpacity(0.7),
                        fontSize: 12,
                      ),
                    ),
                    onTap: _handleLogout,
                  ),
                ],
              ),
            ),

            // Footer with version info
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Nhac Music Player',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.4),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Main content
        Stack(
          children: [
            // Left edge swipe area with visual feedback
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 40,
              child: GestureDetector(
                onTap: () {
                  // Quick tap on edge also opens menu
                  if (!_isMenuOpen) {
                    _openMenu();
                  }
                },
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Theme.of(context).colorScheme.primary.withOpacity(0.1),
                        Theme.of(context).colorScheme.primary.withOpacity(0.05),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Main content with gesture detection
            GestureDetector(
              onHorizontalDragStart: _handleHorizontalDragStart,
              onHorizontalDragUpdate: _handleHorizontalDragUpdate,
              onHorizontalDragEnd: _handleHorizontalDragEnd,
              child: widget.child,
            ),
          ],
        ),

        // Backdrop overlay
        if (_isMenuOpen || _currentDragX > 0)
          AnimatedBuilder(
            animation: _backdropAnimation,
            builder: (context, child) {
              return GestureDetector(
                onTapUp: (details) {
                  // Check if tap is outside the menu area
                  final screenWidth = MediaQuery.of(context).size.width;
                  final menuWidth = screenWidth * 0.8;

                  if (details.localPosition.dx > menuWidth) {
                    _closeMenu();
                  }
                },
                child: Container(
                  width: MediaQuery.of(context).size.width,
                  height: MediaQuery.of(context).size.height,
                  color: Colors.black.withOpacity(
                    _isDragging
                        ? (_currentDragX / MediaQuery.of(context).size.width) * 0.5
                        : _backdropAnimation.value,
                  ),
                ),
              );
            },
          ),

        // Sliding menu
        AnimatedBuilder(
          animation: _slideAnimation,
          builder: (context, child) {
            double slidePosition = 0.0;

            if (_isDragging) {
              slidePosition = _currentDragX;
            } else if (_isMenuOpen) {
              slidePosition = MediaQuery.of(context).size.width * 0.8 * _slideAnimation.value.dx;
            }

            return Transform.translate(
              offset: Offset(
                slidePosition - MediaQuery.of(context).size.width * 0.8,
                0,
              ),
              child: _buildMenuContent(),
            );
          },
        ),
      ],
    );
  }
}

// Desktop version of the menu (shows as popup)
class NavigationMenuDesktop extends StatelessWidget {
  final BuildContext context;
  final Offset position;
  final VoidCallback? onQuickScan;
  final VoidCallback? onLogout;

  const NavigationMenuDesktop({
    super.key,
    required this.context,
    required this.position,
    this.onQuickScan,
    this.onLogout,
  });

  // Custom popup menu item with hover effects
  Widget _buildMenuItem({
    required String value,
    required Widget child,
    bool enabled = true,
    VoidCallback? onTap,
  }) {
    return MenuItem(
      onTap: onTap,
      enabled: enabled,
      child: child,
    );
  }

  Future<void> _performQuickScan() async {
    final authProvider = context.read<AuthProvider>();
    final adminProvider = context.read<AdminProvider>();

    Navigator.of(context).pop(); // Close menu

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

  Future<void> _handleLogout() async {
    Navigator.of(context).pop();
    await Future.delayed(const Duration(milliseconds: 100));
    if (context.mounted) {
      await context.read<AuthProvider>().logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final adminProvider = context.watch<AdminProvider>();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Quick Scan Option
        _buildMenuItem(
          value: 'quick-scan',
          enabled: adminProvider.canScan,
          onTap: adminProvider.canScan ? onQuickScan : null,
          child: Row(
            children: [
              if (!adminProvider.canScan && !adminProvider.isLoading)
                Icon(
                  Icons.lock,
                  size: 16,
                  color: theme.colorScheme.onSurface.withOpacity(0.4),
                ),
              Expanded(
                child: Text(
                  'Quick Scan Library',
                  style: TextStyle(
                    color: adminProvider.canScan
                        ? null
                        : theme.colorScheme.onSurface.withOpacity(0.4),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Divider
        Container(
          height: 1,
          color: theme.colorScheme.onSurface.withOpacity(0.1),
        ),

        // Logout Option
        _buildMenuItem(
          value: 'logout',
          onTap: onLogout,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Log Out',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}