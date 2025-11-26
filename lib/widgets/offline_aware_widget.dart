import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/network_provider.dart';

class OfflineAwareWidget extends StatelessWidget {
  final Widget child;
  final bool isAvailableOffline;
  final bool showGreyedOut;
  final VoidCallback? onTap;
  final bool enableWhenOffline;

  const OfflineAwareWidget({
    super.key,
    required this.child,
    this.isAvailableOffline = false,
    this.showGreyedOut = true,
    this.onTap,
    this.enableWhenOffline = false,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<NetworkProvider>(
      builder: (context, networkProvider, _) {
        final isOffline = networkProvider.isOffline;
        final shouldGreyOut = isOffline && showGreyedOut && !isAvailableOffline;
        final isEnabled = !isOffline || enableWhenOffline || isAvailableOffline;

        return Opacity(
          opacity: shouldGreyOut ? 0.5 : 1.0,
          child: AbsorbPointer(
            absorbing: !isEnabled,
            child: InkWell(
              onTap: isEnabled ? onTap : null,
              borderRadius: BorderRadius.circular(8),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

class OfflineAwareListTile extends StatelessWidget {
  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool isAvailableOffline;

  const OfflineAwareListTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.isAvailableOffline = false,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<NetworkProvider>(
      builder: (context, networkProvider, _) {
        final isOffline = networkProvider.isOffline;
        final shouldGreyOut = isOffline && !isAvailableOffline;
        final isEnabled = !isOffline || isAvailableOffline;

        return Opacity(
          opacity: shouldGreyOut ? 0.5 : 1.0,
          child: ListTile(
            title: DefaultTextStyle(
              style: Theme.of(context).textTheme.titleMedium!.copyWith(
                color: shouldGreyOut
                  ? Theme.of(context).colorScheme.onSurface.withOpacity(0.5)
                  : Theme.of(context).colorScheme.onSurface,
              ),
              child: title,
            ),
            subtitle: subtitle != null
              ? DefaultTextStyle(
                  style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                    color: shouldGreyOut
                      ? Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5)
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  child: subtitle!,
                )
              : null,
            leading: leading,
            trailing: trailing,
            onTap: isEnabled ? onTap : null,
          ),
        );
      },
    );
  }
}