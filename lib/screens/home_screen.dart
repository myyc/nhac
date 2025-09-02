import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:io' show Platform;
import '../providers/auth_provider.dart';
import '../widgets/custom_window_frame.dart';
import 'home_view.dart';
import 'search_screen.dart';
import 'library_screen.dart';
import 'app_scaffold.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  bool _isSearchOpen = false;

  void _navigateToHome() {
    setState(() {
      _selectedIndex = 0;
    });
  }

  void _openSearch({String? initialQuery}) {
    if (!_isSearchOpen) {
      setState(() {
        _isSearchOpen = true;
      });
      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => SearchScreen(
            onNavigateToHome: _navigateToHome,
            initialQuery: initialQuery,
            onClose: () {
              setState(() {
                _isSearchOpen = false;
              });
            },
          ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            // Slide up from bottom with fade
            const begin = Offset(0.0, 0.3);
            const end = Offset.zero;
            const curve = Curves.easeOutCubic;

            var tween = Tween(begin: begin, end: end).chain(
              CurveTween(curve: curve),
            );
            var offsetAnimation = animation.drive(tween);
            
            var fadeTween = Tween(begin: 0.0, end: 1.0).chain(
              CurveTween(curve: curve),
            );
            var fadeAnimation = animation.drive(fadeTween);

            return SlideTransition(
              position: offsetAnimation,
              child: FadeTransition(
                opacity: fadeAnimation,
                child: child,
              ),
            );
          },
          transitionDuration: const Duration(milliseconds: 300),
        ),
      ).then((_) {
        setState(() {
          _isSearchOpen = false;
        });
      });
    }
  }

  late final List<Widget> _screens = [
    HomeView(onOpenSearch: _openSearch),
    LibraryScreen(
      onNavigateToHome: _navigateToHome,
      onOpenSearch: _openSearch,
    ),
  ];

  final List<NavigationDestination> _destinations = const [
    NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home),
      label: 'Home',
    ),
    NavigationDestination(
      icon: Icon(Icons.library_music_outlined),
      selectedIcon: Icon(Icons.library_music),
      label: 'Library',
    ),
  ];

  void _showMenu(BuildContext context) async {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay = Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    final result = await showMenu<String>(
      context: context,
      position: position,
      items: [
        const PopupMenuItem<String>(
          value: 'logout',
          child: Text('Logout'),
        ),
      ],
    );

    if (result == 'logout' && mounted) {
      await context.read<AuthProvider>().logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget content = AppScaffold(
      child: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: _destinations,
      ),
    );

    // Mobile content remains unchanged - we'll handle search trigger differently
    // Remove the GestureDetector as it conflicts with scrolling

    // Add keyboard listener for desktop
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      content = RawKeyboardListener(
        focusNode: FocusNode(),
        autofocus: true,
        onKey: (event) {
          if (event is RawKeyDownEvent) {
            final primaryFocus = FocusManager.instance.primaryFocus;
            // Check if no text field is focused
            if (primaryFocus == null || 
                primaryFocus.context == null || 
                primaryFocus.context!.widget is! EditableText) {
              final key = event.logicalKey;
              
              // Handle ESC key - navigate to home if on Library tab
              if (key == LogicalKeyboardKey.escape) {
                if (_selectedIndex == 1) { // Library is at index 1
                  setState(() {
                    _selectedIndex = 0; // Navigate to Home
                  });
                }
                return;
              }
              
              // Handle alphanumeric keys for search
              final label = key.keyLabel;
              // Check if it's an alphanumeric character
              if (label.length == 1 && RegExp(r'[a-zA-Z0-9]').hasMatch(label)) {
                // Convert to lowercase unless shift is pressed
                final shiftPressed = event.isShiftPressed;
                final query = shiftPressed ? label.toUpperCase() : label.toLowerCase();
                _openSearch(initialQuery: query);
              }
            }
          }
        },
        child: CustomWindowFrame(
          showMenuButton: true,
          child: content,
        ),
      );
      return content;
    }
    
    // For mobile platforms, return content without app bar to save screen space
    return content;
  }
}