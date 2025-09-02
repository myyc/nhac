import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/network_provider.dart';

class OfflineIndicator extends StatelessWidget {
  const OfflineIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<NetworkProvider>(
      builder: (context, networkProvider, child) {
        if (!networkProvider.isOffline) {
          return const SizedBox.shrink();
        }
        
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off,
                size: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                'Offline',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class NetworkStatusToast extends StatelessWidget {
  final bool isOnline;
  
  const NetworkStatusToast({
    super.key,
    required this.isOnline,
  });
  
  static void show(BuildContext context, bool isOnline) {
    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;
    
    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 16,
        left: 0,
        right: 0,
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 200),
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.scale(
                    scale: 0.8 + (0.2 * value),
                    child: NetworkStatusToast(isOnline: isOnline),
                  ),
                );
              },
              onEnd: () {
                Future.delayed(const Duration(seconds: 2), () {
                  overlayEntry.remove();
                });
              },
            ),
          ),
        ),
      ),
    );
    
    overlay.insert(overlayEntry);
  }
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isOnline 
          ? Colors.green.shade700
          : Colors.orange.shade700,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isOnline ? Icons.cloud_done : Icons.cloud_off,
            color: Colors.white,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            isOnline ? 'Back online' : 'Offline mode',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}