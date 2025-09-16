import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io' show Platform;

class PullToSearch extends StatefulWidget {
  final Widget child;
  final VoidCallback onSearchTriggered;
  final double triggerThreshold;
  final double maxStretchDistance;
  final double elasticity;

  const PullToSearch({
    super.key,
    required this.child,
    required this.onSearchTriggered,
    this.triggerThreshold = 80.0,
    this.maxStretchDistance = 240.0,
    this.elasticity = 0.6,
  });

  @override
  State<PullToSearch> createState() => _PullToSearchState();
}

class _PullToSearchState extends State<PullToSearch> {
  double _dragOffset = 0.0;
  bool _isSearchTriggered = false;

  @override
  Widget build(BuildContext context) {
    // Only enable on mobile platforms
    if (!(Platform.isAndroid || Platform.isIOS)) {
      return widget.child;
    }

    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: Stack(
        children: [
          // Search indicator
          if (_dragOffset > 0)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Container(
                  height: _dragOffset.clamp(0.0, widget.maxStretchDistance),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.1),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search,
                          size: 28,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _dragOffset > widget.triggerThreshold
                              ? 'Release to search'
                              : 'Pull to search',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w500,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Main content moves directly with finger
          Transform.translate(
            offset: Offset(0, _dragOffset),
            child: widget.child,
          ),
        ],
      ),
    );
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is OverscrollNotification && notification.overscroll < 0) {
      // Use overscroll directly - this gives immediate elastic feedback
      final dragDistance = -notification.overscroll;

      setState(() {
        _dragOffset = (dragDistance * 1.5).clamp(0.0, widget.maxStretchDistance);
      });

      // Check if we should trigger search
      if (_dragOffset > widget.triggerThreshold && !_isSearchTriggered) {
        _isSearchTriggered = true;
        HapticFeedback.mediumImpact();
        widget.onSearchTriggered();
      }
    } else if (notification is ScrollEndNotification || notification is UserScrollNotification) {
      // Reset when scrolling ends or user scrolls in another direction
      if (_dragOffset > 0) {
        setState(() {
          _dragOffset = 0.0;
          _isSearchTriggered = false;
        });
      }
    }

    return false;
  }
}