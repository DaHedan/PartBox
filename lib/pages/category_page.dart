import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../data/repositories/category_repository.dart';
import '../data/seed_data.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/category_icons.dart';
import '../utils/format.dart';
import '../widgets/app_drawer.dart';
import '../widgets/category_icon.dart';
import '../widgets/dialogs.dart';
import '../widgets/empty_state.dart';
import 'category_filter_page.dart';
import 'search_page.dart';
import 'subcategory_page.dart';

/// P2 分类页（线框 03）。
class CategoryPage extends StatefulWidget {
  const CategoryPage({super.key});

  @override
  State<CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends State<CategoryPage> {
  late Future<List<Category>> _future = CategoryRepository.topCategories();
  int _revision = -1;

  Future<void> _createTop() async {
    final result = await _editDialog(title: '自定义大类');
    if (result == null) return;
    await CategoryRepository.insertTop(result.$1, result.$2);
    if (!mounted) return;
    context.read<AppState>().notifyDataChanged();
    showToast(context, '已添加大类「${result.$1}」');
  }

  Future<void> _editTop(Category category) async {
    final result = await _editDialog(
      title: '编辑大类',
      initialName: category.name,
      initialIcon: category.icon,
    );
    if (result == null) return;
    await CategoryRepository.update(
      category.copyWith(name: result.$1, icon: result.$2),
    );
    if (!mounted) return;
    context.read<AppState>().notifyDataChanged();
  }

  Future<void> _deleteTop(Category category) async {
    if (category.id == kUncategorizedCategoryId) {
      showToast(context, '内置"未分类"不可删除');
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
      title: '删除分类',
      message: '确定删除「${category.name}」及其全部子类？',
      confirmText: '删除',
      danger: true,
    );
    if (!ok) return;
    await CategoryRepository.delete(category.id!);
    if (!mounted) return;
    context.read<AppState>().notifyDataChanged();
  }

  Future<void> _move(Category category, int delta) async {
    await CategoryRepository.moveSort(category.id!, delta);
    if (!mounted) return;
    context.read<AppState>().notifyDataChanged();
  }

  /// 名称 + 图标的编辑对话框。
  Future<(String, String?)?> _editDialog({
    required String title,
    String? initialName,
    String? initialIcon,
  }) {
    return showDialog<(String, String?)>(
      context: context,
      builder: (_) => _CategoryDialog(
        title: title,
        initialName: initialName,
        initialIcon: initialIcon,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final revision = context.watch<AppState>().revision;
    if (revision != _revision) {
      _revision = revision;
      _future = CategoryRepository.topCategories();
    }

    return Scaffold(
      appBar: AppBar(
        leading: const DrawerMenuButton(),
        title: const Text('分类'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: '搜索',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SearchPage()),
            ),
          ),
        ],
      ),
      drawer: const AppDrawer(current: RootPage.category),
      body: Column(
        children: [
          Expanded(
            child: FutureBuilder<List<Category>>(
              future: _future,
              builder: (context, snapshot) {
                final categories = snapshot.data ?? const <Category>[];
                if (categories.isEmpty) {
                  return const EmptyState(
                    icon: Icons.grid_view_outlined,
                    message: '还没有分类',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: categories.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final category = categories[index];
                    return Card(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => CategoryFilterPage(
                              topCategoryId: category.id!,
                              topCategoryName: category.name,
                            ),
                          ),
                        ),
                        onLongPress: () => _editTop(category),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              CategoryIconBox(
                                iconKey: category.icon,
                                tintKey: category.name,
                                size: 40,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  category.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    color: palette.text,
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
                              PopupMenuButton<String>(
                                icon: Icon(
                                  Icons.more_vert,
                                  size: 20,
                                  color: palette.textSub,
                                ),
                                onSelected: (value) {
                                  switch (value) {
                                    case 'edit':
                                      _editTop(category);
                                    case 'sub':
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => SubcategoryPage(
                                            topCategoryId: category.id!,
                                            topCategoryName: category.name,
                                          ),
                                        ),
                                      );
                                    case 'up':
                                      _move(category, -1);
                                    case 'down':
                                      _move(category, 1);
                                    case 'delete':
                                      _deleteTop(category);
                                  }
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Text('编辑'),
                                  ),
                                  const PopupMenuItem(
                                    value: 'sub',
                                    child: Text('管理子类'),
                                  ),
                                  const PopupMenuItem(
                                    value: 'up',
                                    child: Text('上移'),
                                  ),
                                  const PopupMenuItem(
                                    value: 'down',
                                    child: Text('下移'),
                                  ),
                                  if (category.id !=
                                      kUncategorizedCategoryId)
                                    const PopupMenuItem(
                                      value: 'delete',
                                      child: Text('删除'),
                                    ),
                                ],
                              ),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: OutlinedButton.icon(
              onPressed: _createTop,
              icon: const Icon(Icons.add),
              label: const Text('自定义'),
            ),
          ),
        ],
      ),
    );
  }
}

/// 分类名称 + 图标选择对话框。
///
/// 输入框控制器由对话框自身持有（随 State 一起销毁），
/// 避免在退场动画期间被外部提前 dispose 导致构建期异常。
class _CategoryDialog extends StatefulWidget {
  const _CategoryDialog({
    required this.title,
    this.initialName,
    this.initialIcon,
  });

  final String title;
  final String? initialName;
  final String? initialIcon;

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName ?? '',
  );
  late String _icon = widget.initialIcon ?? kSelectableIcons.first;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _close([(String, String?)? result]) {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).pop(result);
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      showToast(context, '请输入分类名称');
      return;
    }
    _close((name, _icon));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(hintText: '分类名称'),
            ),
            const SizedBox(height: 16),
            Text(
              '图标',
              style: TextStyle(fontSize: 13, color: palette.textSub),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 160,
              child: GridView.count(
                crossAxisCount: 6,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                children: [
                  for (final key in kSelectableIcons)
                    InkWell(
                      onTap: () => setState(() => _icon = key),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _icon == key
                                ? palette.primary
                                : palette.border,
                            width: _icon == key ? 1.6 : 1,
                          ),
                        ),
                        child: Icon(
                          iconForKey(key),
                          size: 20,
                          color: _icon == key
                              ? palette.primary
                              : palette.textSub,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => _close(),
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
