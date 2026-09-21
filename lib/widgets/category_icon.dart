import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/category_icons.dart';

/// 分类图标方块（彩色底色 + 图标），无图物料时作为兜底图标。
class CategoryIconBox extends StatelessWidget {
  const CategoryIconBox({
    super.key,
    required this.iconKey,
    required this.tintKey,
    this.size = 48,
  });

  final String? iconKey;
  final String? tintKey;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final tint = palette.tintFor(tintKey ?? iconKey);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: palette.isDark ? 0.22 : 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Icon(
        iconForKey(iconKey),
        size: size * 0.55,
        color: tint,
      ),
    );
  }
}
