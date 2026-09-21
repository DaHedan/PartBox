import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/stock_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

/// 三量卡：采购 / 消耗 / 余量（UI 规范 6.3）。
class QtyCards extends StatelessWidget {
  const QtyCards({
    super.key,
    required this.item,
    required this.lowStock,
    this.onTapField,
  });

  final MaterialItem item;
  final bool lowStock;
  final void Function(String field)? onTapField;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: [
        Expanded(
          child: _QtyCard(
            label: '采购',
            value: item.qtyPurchased,
            color: palette.success,
            onTap: onTapField == null
                ? null
                : () => onTapField!(StockService.fieldPurchased),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _QtyCard(
            label: '消耗',
            value: item.qtyUsed,
            color: palette.warning,
            onTap: onTapField == null
                ? null
                : () => onTapField!(StockService.fieldUsed),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _QtyCard(
            label: '余量',
            value: item.qtyRemaining,
            color: lowStock ? palette.danger : palette.primary,
            onTap: onTapField == null
                ? null
                : () => onTapField!(StockService.fieldRemaining),
          ),
        ),
      ],
    );
  }
}

class _QtyCard extends StatelessWidget {
  const _QtyCard({
    required this.label,
    required this.value,
    required this.color,
    this.onTap,
  });

  final String label;
  final double value;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          height: 88,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 12, color: palette.textSub),
              ),
              const SizedBox(height: 6),
              Text(
                formatQty(value),
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  fontFeatures: kTabularFigures,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
