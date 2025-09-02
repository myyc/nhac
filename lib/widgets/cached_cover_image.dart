import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/cache_provider.dart';

class CachedCoverImage extends StatefulWidget {
  final String? coverArtId;
  final int size;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  const CachedCoverImage({
    super.key,
    required this.coverArtId,
    this.size = 300,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
    this.width,
    this.height,
    this.borderRadius,
  });

  @override
  State<CachedCoverImage> createState() => _CachedCoverImageState();
}

class _CachedCoverImageState extends State<CachedCoverImage> {
  String? _localPath;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadCoverArt();
  }

  @override
  void didUpdateWidget(CachedCoverImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coverArtId != widget.coverArtId || 
        oldWidget.size != widget.size) {
      _loadCoverArt();
    }
  }

  Future<void> _loadCoverArt() async {
    if (widget.coverArtId == null) {
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final cacheProvider = context.read<CacheProvider>();
      final localPath = await cacheProvider.getCachedCoverArt(
        widget.coverArtId,
        size: widget.size,
      );

      if (mounted) {
        if (localPath != null) {
          setState(() {
            _localPath = localPath;
            _isLoading = false;
            _hasError = false;
          });
        } else {
          setState(() {
            _isLoading = false;
            _hasError = true;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget content;

    if (_isLoading) {
      content = widget.placeholder ?? 
        const Center(child: CircularProgressIndicator());
    } else if (_hasError || _localPath == null) {
      content = widget.errorWidget ?? 
        const Center(child: Icon(Icons.music_note, size: 48));
    } else {
      final file = File(_localPath!);
      content = Image.file(
        file,
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        errorBuilder: (context, error, stackTrace) {
          return widget.errorWidget ?? 
            const Center(child: Icon(Icons.music_note, size: 48));
        },
      );
    }

    if (widget.borderRadius != null) {
      return ClipRRect(
        borderRadius: widget.borderRadius!,
        child: SizedBox(
          width: widget.width,
          height: widget.height,
          child: content,
        ),
      );
    }

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: content,
    );
  }
}