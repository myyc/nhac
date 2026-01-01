import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// A wrapper around CachedNetworkImage that handles corrupt cache entries.
/// When an image fails to load with "Invalid image data", it clears the cache
/// entry and retries the fetch.
class SafeCachedImage extends StatefulWidget {
  final String imageUrl;
  final Map<String, String>? httpHeaders;
  final BoxFit? fit;
  final Widget Function(BuildContext, String)? placeholder;
  final Widget Function(BuildContext, String, Object)? errorWidget;
  final double? width;
  final double? height;

  const SafeCachedImage({
    super.key,
    required this.imageUrl,
    this.httpHeaders,
    this.fit,
    this.placeholder,
    this.errorWidget,
    this.width,
    this.height,
  });

  @override
  State<SafeCachedImage> createState() => _SafeCachedImageState();
}

class _SafeCachedImageState extends State<SafeCachedImage> {
  int _retryCount = 0;
  static const int _maxRetries = 1;
  Key _imageKey = UniqueKey();

  Future<void> _clearCacheAndRetry(String url) async {
    if (_retryCount >= _maxRetries) return;

    try {
      // Clear this specific URL from the cache
      await DefaultCacheManager().removeFile(url);

      if (mounted) {
        setState(() {
          _retryCount++;
          _imageKey = UniqueKey(); // Force widget rebuild
        });
      }
    } catch (e) {
      // Ignore cache clearing errors
    }
  }

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      key: _imageKey,
      imageUrl: widget.imageUrl,
      httpHeaders: widget.httpHeaders,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      placeholder: widget.placeholder,
      errorWidget: (context, url, error) {
        // Check if this is a corrupt cache error and we haven't retried yet
        if (error.toString().contains('Invalid image data') &&
            _retryCount < _maxRetries) {
          // Clear cache and retry
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _clearCacheAndRetry(url);
          });
          // Show placeholder while retrying
          return widget.placeholder?.call(context, url) ??
              const Center(child: CircularProgressIndicator());
        }

        // Show error widget for other errors or after retry exhausted
        return widget.errorWidget?.call(context, url, error) ??
            const Center(child: Icon(Icons.broken_image));
      },
    );
  }
}
