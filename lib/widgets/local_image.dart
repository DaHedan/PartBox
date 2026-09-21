import 'dart:io';

import 'package:flutter/material.dart';

import '../data/image_store.dart';

/// 本地图片（相对路径存库），加载失败或不存在时回退到 [fallback]。
class LocalImage extends StatefulWidget {
  const LocalImage({
    super.key,
    required this.relativePath,
    required this.width,
    required this.height,
    required this.fallback,
    this.borderRadius = 8,
  });

  final String? relativePath;
  final double width;
  final double height;
  final Widget fallback;
  final double borderRadius;

  @override
  State<LocalImage> createState() => _LocalImageState();
}

class _LocalImageState extends State<LocalImage> {
  Future<File?>? _future;

  @override
  void initState() {
    super.initState();
    _future = ImageStore.resolve(widget.relativePath);
  }

  @override
  void didUpdateWidget(covariant LocalImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.relativePath != widget.relativePath) {
      _future = ImageStore.resolve(widget.relativePath);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.relativePath == null || widget.relativePath!.isEmpty) {
      return widget.fallback;
    }
    return FutureBuilder<File?>(
      future: _future,
      builder: (context, snapshot) {
        final file = snapshot.data;
        if (file == null) return widget.fallback;
        return ClipRRect(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: Image.file(
            file,
            width: widget.width,
            height: widget.height,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => widget.fallback,
          ),
        );
      },
    );
  }
}
