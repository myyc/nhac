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
    this.triggerThreshold = 60.0,
    this.maxStretchDistance = 240.0,
    this.elasticity = 1.5,
  });

  @override
  State<PullToSearch> createState() => _PullToSearchState();
}

class _PullToSearchState extends State<PullToSearch>
    with SingleTickerProviderStateMixin {
  double _dragOffset = 0.0;
  double _accumulatedDrag = 0.0;
  bool _isSearchTriggered = false;
  late AnimationController _resetController;
  double _animationStartOffset = 0.0;

  @override
  void initState() {
    super.initState();
    _resetController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _resetController.addListener(_onAnimationTick);
  }

  @override
  void dispose() {
    _resetController.dispose();
    super.dispose();
  }

  void _onAnimationTick() {
    setState(() {
      // Animate from start offset to 0 using easeOutCubic curve
      final progress = Curves.easeOutCubic.transform(_resetController.value);
      _dragOffset = _animationStartOffset * (1.0 - progress);
    });
  }

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
      // Stop any running reset animation when user drags again
      if (_resetController.isAnimating) {
        _resetController.stop();
      }

      // ACCUMULATE the drag distance instead of just using the last value
      _accumulatedDrag += -notification.overscroll;
      _dragOffset =
          (_accumulatedDrag * widget.elasticity).clamp(0.0, widget.maxStretchDistance);
      setState(() {});

      // Check if we should trigger search
      if (_dragOffset > widget.triggerThreshold && !_isSearchTriggered) {
        _isSearchTriggered = true;
        HapticFeedback.mediumImpact();
        widget.onSearchTriggered();
      }
    } else if (notification is ScrollUpdateNotification &&
        notification.scrollDelta != null &&
        notification.scrollDelta! > 0) {
      // User is scrolling down (away from overscroll), reset accumulated drag
      if (_accumulatedDrag > 0) {
        _accumulatedDrag = 0.0;
        if (_dragOffset > 0 && !_resetController.isAnimating) {
          _animationStartOffset = _dragOffset;
          _resetController.forward(from: 0.0);
        }
      }
    } else if (notification is ScrollEndNotification ||
        notification is UserScrollNotification) {
      // Animate reset when scrolling ends
      if (_dragOffset > 0 && !_resetController.isAnimating) {
        _animationStartOffset = _dragOffset;
        _isSearchTriggered = false;
        _accumulatedDrag = 0.0;
        _resetController.forward(from: 0.0);
      }
    }

    return false;
  }
}