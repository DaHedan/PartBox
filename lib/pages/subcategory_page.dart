import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../data/repositories/category_repository.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/dialogs.dart';
import '../widgets/empty_state.dart';
import '../widgets/multi_select.dart';

/// 子类管理（大类下的子类，增 / 删 / 改 / 排序）。
class SubcategoryPage extends StatefulWidget {
  const SubcategoryPage({
    super.key,
    required this.topCategoryId,
    required this.topCategoryName,
  });

  final int topCategoryId;
  final String topCategoryName;

  @override
  State<SubcategoryPage> createState() => _SubcategoryPageState();
}

class _SubcategoryPageState extends State<SubcategoryPage>
    with MultiSelectMixin<SubcategoryPage> {
  late Future<List<Category>> _future = CategoryRepository.subcategoriesWithCount(
    widget.topCategoryId,
  );
  int _revision = -1;

  /// 可批量删除的子类 id（进入多选/全选时刷新；内置子类不可删）。
  List<int> _selectableIds = const [];

  Future<List<int>> _querySelectableIds() async {
    final items = await CategoryRepository.subcategoriesWithCount(
      widget.topCategoryId,
    );
    return [for (final item in items) if (!item.builtin) item.id!];
  }

  Future<void> _startSelection() async {
    final ids = await _querySelectableIds();
    if (!mounted) return;
    if (ids.isEmpty) {
      showToast(context, '内置子类不可删除，没有可批量删除的子类');
      return;
    }
    _selectableIds = ids;
    enterSelection();
  }

  Future<void> _selectAll() async {
    final ids = await _querySelectableIds();
    if (!mounted) return;
    _selectableIds = ids;
    setSelection(selectedIds.length == ids.length ? const <int>[] : ids);
  }

  Future<void> _deleteSelected() async {
    final ids = selectedIds.toList();
    if (ids.isEmpty) return;
    final ok = await showConfirmDialog(
      context,
      title: '批量删除子类',
      message: '确定删除选中的 ${ids.length} 个自定义子类？',
      confirmText: '删除',
      danger: true,
    );
    if (!ok) return;
    var deleted = 0;
    String? blocked;
    for (final id in ids) {
      try {
        await CategoryRepository.delete(id);
        deleted++;
      } on StateError catch (error) {
        blocked = error.message;
        break;
      }
    }
    if (!mounted) return;
    exitSelection();
    context.read<AppState>().notifyDataChanged();
    showToast(
      context,
      blocked == null ? '已删除 $deleted 个子类' : '已删除 $deleted 个；$blocked',
    );
  }

  /// 内置子类不可删。
  void _enterSelectionFor(Category category) {
    if (category.builtin) {
      showToast(context, '内置子类不可删除');
      return;
    }
    enterSelection(category.id);
  }

  Future<void> _add() async {
    final name = await showTextDialog(
      context,
      title: '添加子类',
      hint: '如：贴片电容(MLCC)',
    );
    if (name == null) return;
    await CategoryRepository.insertSub(widget.topCategoryId, name);
    if (!mounted) return;
    context.read<AppState>().notifyDataChanged();
  }

  Future<void> _rename(Category category) async {
    final name = await showTextDialog(
      context,
      title: '重命名子类',
      initial: category.name,
    );
    if (name == null) return;
    await CategoryRepository.update(category.copyWith(name: name));
    if (!mounted) return;
    context.read<AppState>().notifyDataChanged();
  }

  Future<void> _move(Category category, int delta) async {
    await CategoryRepository.moveSort(category.id!, delta);
    if (!mounted) return;
    context.read<AppState>().notifyDataChanged();
  }

  /// 子类行右侧"更多"菜单（内置子类不提供删除项）。
  Widget _menuButton(Category category, bool selectable) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, size: 20, color: context.palette.textSub),
      onSelected: (value) {
        if (value == 'rename') {
          _rename(category);
        } else if (value == 'up') {
          _move(category, -1);
        } else if (value == 'down') {
          _move(category, 1);
        } else {
          _delete(category);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'rename', child: Text('重命名')),
        const PopupMenuItem(value: 'up', child: Text('上移')),
        const PopupMenuItem(value: 'down', child: Text('下移')),
        if (selectable)
          const PopupMenuItem(value: 'delete', child: Text('删除')),
      ],
    );
  }

  Future<void> _delete(Category category) async {
    if (category.builtin) {
      showToast(context, '内置子类不可删除');
      return;
    }
    final count = await CategoryRepository.materialCountUnder(category.id!);
    if (!mounted) return;
    if (count > 0) {
      showToast(context, '「${category.name}」下还有 $count 种物料，请先迁移物料');
      return;
    }
    final ok = await showConfirmDialog(
      context,
      title: '删除子类',
      message: '确定删除「${category.name}」？',
      confirmText: '删除',
      danger: true,
    );
    if (!ok) return;
    await CategoryRepository.delete(category.id!);
    if (!mounted) return;
    context.read<AppState>().notifyDataChanged();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final revision = context.watch<AppState>().revision;
    if (revision != _revision) {
      _revision = revision;
      _future = CategoryRepository.subcategoriesWithCount(widget.topCategoryId);
    }

    return Scaffold(
      appBar: selecting
          ? SelectionAppBar(
              count: selectedIds.length,
              allSelected: _selectableIds.isNotEmpty &&
                  selectedIds.length == _selectableIds.length,
              onSelectAll: _selectAll,
              onDelete: _deleteSelected,
              onExit: exitSelection,
            )
          : AppBar(
              title: Text('${widget.topCategoryName} · 子类'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.checklist),
                  tooltip: '批量删除',
                  onPressed: _startSelection,
                ),
              ],
            ),
      body: Column(
        children: [
          Expanded(
            child: FutureBuilder<List<Category>>(
              future: _future,
              builder: (context, snapshot) {
                final items = snapshot.data ?? const <Category>[];
                if (items.isEmpty) {
                  return const EmptyState(
                    icon: Icons.category_outlined,
                    message: '还没有子类，点下方按钮添加',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final category = items[index];
                    final selectable = !category.builtin;
                    final checked = selectedIds.contains(category.id);
                    return Card(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          if (!selecting) return;
                          if (!selectable) {
                            showToast(context, '内置子类不可删除');
                            return;
                          }
                          toggleSelected(category.id!);
                        },
                        onLongPress: selecting || useSecondaryTapSelection
                            ? null
                            : () => _enterSelectionFor(category),
                        onSecondaryTap: selecting || !useSecondaryTapSelection
                            ? null
                            : () => _enterSelectionFor(category),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  child: Text(
                                    category.name,
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: palette.text,
                                    ),
                                  ),
                                ),
                              ),
                              Text(
                                '${category.materialCount} 种',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: palette.textSub,
                                ),
                              ),
                              if (selecting)
                                Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: selectable
                                      ? SelectCheck(checked: checked)
                                      : Icon(
                                          Icons.lock_outline,
                                          size: 20,
                                          color: palette.textSub,
                                        ),
                                )
                              else
                                _menuButton(category, selectable),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          if (!selecting)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: FilledButton.icon(
                onPressed: _add,
                icon: const Icon(Icons.add),
                label: const Text('添加子类'),
              ),
            ),
        ],
      ),
    );
  }
}
