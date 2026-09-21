import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 圆形数量（仓库行右侧 / 统计用）。
class CountCircle extends StatelessWidget {
  const CountCircle({super.key, required this.count, this.size = 32});

  final int count;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: palette.primary.withValues(alpha: palette.isDark ? 0.22 : 0.12),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: size * 0.4,
          fontWeight: FontWeight.w600,
          color: palette.primary,
        ),
      ),
    );
  }
}
