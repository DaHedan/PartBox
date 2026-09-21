import 'package:flutter/material.dart';

import '../data/models.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import 'category_icon.dart';
import 'local_image.dart';

/// 物料卡片（全局通用，详见 UI 规范 6.1）。
class MaterialCard extends StatelessWidget {
  const MaterialCard({
    super.key,
    required this.item,
    required this.lowStock,
    this.iconKey,
    this.onTap,
    this.onLongPress,
    this.trailing,
    this.selected = false,
  });

  final MaterialItem item;
  final bool lowStock;
  final String? iconKey;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// 追加在余量右侧的内容（如多选勾选框）。
  final Widget? trailing;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final fallback = CategoryIconBox(
      iconKey: iconKey,
      tintKey: item.categoryName ?? item.name,
      size: 48,
    );
    final brandLine = [
      if (item.brand != null && item.brand!.isNotEmpty) item.brand!,
      if (item.lcscCode != null && item.lcscCode!.isNotEmpty) item.lcscCode!,
    ].join(' · ');

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? palette.primary : (palette.isDark ? palette.border : const Color(0xFFEDF0F4)),
          width: selected ? 1.6 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LocalImage(
                relativePath: item.imagePath,
                width: 48,
                height: 48,
                fallback: fallback,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: palette.text,
                      ),
                    ),
                    if (item.summary.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.summary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: palette.textSub),
                      ),
                    ],
                    if (brandLine.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        brandLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: palette.textSub),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatQty(item.qtyRemaining),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      fontFeatures: kTabularFigures,
                      color: lowStock ? palette.danger : palette.text,
                    ),
                  ),
                  Text(
                    item.unit,
                    style: TextStyle(fontSize: 12, color: palette.textSub),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(height: 6),
                    trailing!,
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
