import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 桌面端（Windows/macOS/Linux）用**右键**进入多选，触屏端用**长按**。
bool get useSecondaryTapSelection => !Platform.isAndroid && !Platform.isIOS;

/// 列表多选（批量删除）状态：进入/退出、单选切换、全选、清空。
mixin MultiSelectMixin<T extends StatefulWidget> on State<T> {
  bool selecting = false;
  final Set<int> selectedIds = {};

  /// 进入多选模式；传入 [id] 表示同时选中该项（长按进入时用）。
  void enterSelection([int? id]) {
    setState(() {
      selecting = true;
      if (id != null) selectedIds.add(id);
    });
  }

  void exitSelection() {
    setState(() {
      selecting = false;
      selectedIds.clear();
    });
  }

  void toggleSelected(int id) {
    setState(() {
      if (!selectedIds.remove(id)) selectedIds.add(id);
    });
  }

  void setSelection(Iterable<int> ids) {
    setState(() {
      selectedIds
        ..clear()
        ..addAll(ids);
    });
  }
}

/// 多选模式下的 AppBar：左上退出、标题"已选 N"、右侧全选 / 删除。
class SelectionAppBar extends StatelessWidget implements PreferredSizeWidget {
  const SelectionAppBar({
    super.key,
    required this.count,
    required this.allSelected,
    required this.onSelectAll,
    required this.onDelete,
    required this.onExit,
  });

  final int count;
  final bool allSelected;
  final VoidCallback onSelectAll;
  final VoidCallback onDelete;
  final VoidCallback onExit;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        tooltip: '退出多选',
        onPressed: onExit,
      ),
      title: Text('已选 $count'),
      actions: [
        TextButton(
          onPressed: onSelectAll,
          child: Text(
            allSelected ? '取消全选' : '全选',
            style: TextStyle(fontSize: 14, color: palette.primary),
          ),
        ),
        IconButton(
          icon: Icon(Icons.delete_outline, color: palette.danger),
          tooltip: '删除所选',
          onPressed: count == 0 ? null : onDelete,
        ),
      ],
    );
  }
}

/// 多选模式下的卡片右上角选中指示（无勾选框布局改动，点卡片即切换）。
class SelectCheck extends StatelessWidget {
  const SelectCheck({super.key, required this.checked, this.size = 22});

  final bool checked;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Icon(
      checked ? Icons.check_circle : Icons.radio_button_unchecked,
      size: size,
      color: checked ? palette.primary : palette.textSub,
    );
  }
}
