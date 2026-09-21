import 'package:flutter/material.dart';

/// 等宽数字（数量类数字统一使用）。
const List<FontFeature> kTabularFigures = [FontFeature.tabularFigures()];

/// 数量格式化：整数不带小数位。
String formatQty(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}

String formatQtySigned(double value) {
  if (value > 0) return '+${formatQty(value)}';
  return formatQty(value);
}

/// `2026-9-21 14:05`
String formatDateTime(DateTime time) {
  final local = time.toLocal();
  final h = local.hour.toString().padLeft(2, '0');
  final m = local.minute.toString().padLeft(2, '0');
  return '${local.year}-${local.month}-${local.day} $h:$m';
}

/// `2026-9-21`
String formatDate(DateTime time) {
  final local = time.toLocal();
  return '${local.year}-${local.month}-${local.day}';
}

/// 备份文件名用时间戳 `20260921_1405`
String fileStamp(DateTime time) {
  final local = time.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${local.year}${two(local.month)}${two(local.day)}_${two(local.hour)}${two(local.minute)}';
}

void showToast(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 1800),
      ),
    );
}
