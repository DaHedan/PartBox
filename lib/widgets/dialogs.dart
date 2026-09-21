import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../utils/format.dart';

/// 数字输入对话框（数量/阈值）。
Future<double?> showNumberDialog(
  BuildContext context, {
  required String title,
  double? initial,
  String? suffix,
  String? hint,
  bool allowNegative = true,
}) async {
  final controller = TextEditingController(
    text: initial == null ? '' : formatQty(initial),
  );
  final result = await showDialog<double>(
    context: context,
    builder: (context) {
      final palette = context.palette;
      return AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.numberWithOptions(
            decimal: true,
            signed: allowNegative,
          ),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9\.\-]')),
          ],
          decoration: InputDecoration(hintText: hint ?? '请输入数字', suffixText: suffix),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('取消', style: TextStyle(color: palette.textSub)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(80, 40)),
            onPressed: () {
              final value = double.tryParse(controller.text.trim());
              if (value == null) {
                showToast(context, '请输入有效数字');
                return;
              }
              Navigator.of(context).pop(value);
            },
            child: const Text('确定'),
          ),
        ],
      );
    },
  );
  controller.dispose();
  return result;
}

/// 文本输入对话框（分类名/仓库名/备注）。
Future<String?> showTextDialog(
  BuildContext context, {
  required String title,
  String? initial,
  String? hint,
  int maxLines = 1,
}) async {
  final controller = TextEditingController(text: initial ?? '');
  final result = await showDialog<String>(
    context: context,
    builder: (context) {
      final palette = context.palette;
      return AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: maxLines,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('取消', style: TextStyle(color: palette.textSub)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(80, 40)),
            onPressed: () {
              final text = controller.text.trim();
              if (text.isEmpty) {
                showToast(context, '内容不能为空');
                return;
              }
              Navigator.of(context).pop(text);
            },
            child: const Text('确定'),
          ),
        ],
      );
    },
  );
  controller.dispose();
  return result;
}

/// 二次确认对话框。
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmText = '确定',
  bool danger = false,
}) async {
  final palette = context.palette;
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message, style: const TextStyle(fontSize: 14)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('取消', style: TextStyle(color: palette.textSub)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: danger ? palette.danger : palette.primary,
            minimumSize: const Size(80, 40),
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmText),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// 底部单选列表。
Future<T?> showPickerSheet<T>(
  BuildContext context, {
  required String title,
  required List<T> options,
  required String Function(T option) labelOf,
  T? selected,
  String? emptyHint,
}) {
  final palette = context.palette;
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: palette.text,
              ),
            ),
          ),
          if (options.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                emptyHint ?? '暂无可选项',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: palette.textSub),
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options[index];
                  final isSelected = option == selected;
                  return ListTile(
                    title: Text(labelOf(option)),
                    trailing: isSelected
                        ? Icon(Icons.check, color: palette.primary)
                        : null,
                    onTap: () => Navigator.of(context).pop(option),
                  );
                },
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
