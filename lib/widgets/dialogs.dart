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
}) {
  return showDialog<double>(
    context: context,
    builder: (_) => _NumberDialog(
      title: title,
      initial: initial,
      suffix: suffix,
      hint: hint,
      allowNegative: allowNegative,
    ),
  );
}

/// 文本输入对话框（分类名/仓库名/备注）。
Future<String?> showTextDialog(
  BuildContext context, {
  required String title,
  String? initial,
  String? hint,
  int maxLines = 1,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _TextDialog(
      title: title,
      initial: initial,
      hint: hint,
      maxLines: maxLines,
    ),
  );
}

/// 关闭对话框前先收起焦点：带焦点的输入框会借助 keep-alive 阻止自身销毁，
/// 若在退场动画中被祖先 InheritedWidget 带着一起卸载会触发框架断言。
void _closeDialog(BuildContext context, [Object? result]) {
  FocusManager.instance.primaryFocus?.unfocus();
  Navigator.of(context).pop(result);
}

class _NumberDialog extends StatefulWidget {
  const _NumberDialog({
    required this.title,
    this.initial,
    this.suffix,
    this.hint,
    this.allowNegative = true,
  });

  final String title;
  final double? initial;
  final String? suffix;
  final String? hint;
  final bool allowNegative;

  @override
  State<_NumberDialog> createState() => _NumberDialogState();
}

class _NumberDialogState extends State<_NumberDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial == null ? '' : formatQty(widget.initial!),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = double.tryParse(_controller.text.trim());
    if (value == null) {
      showToast(context, '请输入有效数字');
      return;
    }
    _closeDialog(context, value);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.numberWithOptions(
          decimal: true,
          signed: widget.allowNegative,
        ),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9\.\-]')),
        ],
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          hintText: widget.hint ?? '请输入数字',
          suffixText: widget.suffix,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => _closeDialog(context),
          child: Text('取消', style: TextStyle(color: palette.textSub)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(80, 40)),
          onPressed: _submit,
          child: const Text('确定'),
        ),
      ],
    );
  }
}

class _TextDialog extends StatefulWidget {
  const _TextDialog({
    required this.title,
    this.initial,
    this.hint,
    this.maxLines = 1,
  });

  final String title;
  final String? initial;
  final String? hint;
  final int maxLines;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      showToast(context, '内容不能为空');
      return;
    }
    _closeDialog(context, text);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: widget.maxLines,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(hintText: widget.hint),
      ),
      actions: [
        TextButton(
          onPressed: () => _closeDialog(context),
          child: Text('取消', style: TextStyle(color: palette.textSub)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(80, 40)),
          onPressed: _submit,
          child: const Text('确定'),
        ),
      ],
    );
  }
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

/// 入库命中库中已有元件时的选择。
enum DuplicateEntryChoice {
  /// 新建一条独立条目（多包分开记）
  createNew,

  /// 并入已有条目（数量累加）
  merge,
}

/// 入库时命中库中已有 C 编号：新建条目 / 并入已有 / 取消。
Future<DuplicateEntryChoice?> showDuplicateEntryDialog(
  BuildContext context, {
  required String message,
}) {
  final palette = context.palette;
  return showDialog<DuplicateEntryChoice>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('库中已有该元件'),
      content: Text(message, style: const TextStyle(fontSize: 14)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('取消', style: TextStyle(color: palette.textSub)),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(DuplicateEntryChoice.merge),
          child: const Text('并入已有'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(80, 40)),
          onPressed: () =>
              Navigator.of(context).pop(DuplicateEntryChoice.createNew),
          child: const Text('新建条目'),
        ),
      ],
    ),
  );
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
