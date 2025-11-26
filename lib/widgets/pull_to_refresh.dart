import 'package:flutter/material.dart';

class PullToRefresh extends StatefulWidget {
  final Widget child;
  final Future<void> Function() onRefresh;
  final bool enabled;

  const PullToRefresh({
    super.key,
    required this.child,
    required this.onRefresh,
    this.enabled = true,
  });

  @override
  State<PullToRefresh> createState() => _PullToRefreshState();
}

class _PullToRefreshState extends State<PullToRefresh> {
  bool _isRefreshing = false;

  Future<void> _handleRefresh() async {
    if (!widget.enabled || _isRefreshing) return;

    setState(() {
      _isRefreshing = true;
    });

    try {
      await widget.onRefresh();
    } catch (e) {
      // Ignore errors during refresh
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _handleRefresh,
      child: widget.child,
    );
  }
}