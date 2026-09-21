import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 统计卡的单行键值。
class StatRow {
  const StatRow({
    required this.label,
    required this.value,
    this.onTap,
    this.secondary = false,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;

  /// 值用辅助色小字（如备注）。
  final bool secondary;
}

/// 统计卡（UI 规范 6.6）：标签左、值右。
class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.rows});

  final List<StatRow> rows;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) Divider(color: palette.border, height: 1),
              InkWell(
                onTap: rows[i].onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rows[i].label,
                        style: TextStyle(fontSize: 14, color: palette.textSub),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          rows[i].value.isEmpty ? '—' : rows[i].value,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: rows[i].secondary ? 12 : 14,
                            fontWeight: rows[i].secondary
                                ? FontWeight.w400
                                : FontWeight.w600,
                            color: rows[i].secondary
                                ? palette.textSub
                                : palette.text,
                          ),
                        ),
                      ),
                      if (rows[i].onTap != null) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.edit_outlined,
                          size: 16,
                          color: palette.textSub,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
