import 'package:flutter/material.dart';

import '../data/models.dart';
import '../theme/app_theme.dart';
import 'category_icon.dart';
import 'count_circle.dart';

/// 仓库行：图标 + 名称 + 圆形数量（线框 06）。
class LocationRow extends StatelessWidget {
  const LocationRow({
    super.key,
    required this.location,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTap,
  });

  final Location location;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// 桌面端右键（进入多选）。
  final VoidCallback? onSecondaryTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      onSecondaryTap: onSecondaryTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            CategoryIconBox(
              iconKey: 'box',
              tintKey: location.name,
              size: 40,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                location.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: palette.text,
                ),
              ),
            ),
            CountCircle(count: location.materialKinds),
          ],
        ),
      ),
    );
  }
}
