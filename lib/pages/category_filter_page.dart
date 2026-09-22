import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../data/repositories/category_repository.dart';
import '../data/repositories/material_repository.dart';
import '../data/seed_data.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/dialogs.dart';
import '../widgets/empty_state.dart';
import '../widgets/facet_filter.dart';
import '../widgets/material_card.dart';
import '../widgets/multi_select.dart';
import 'material_detail_page.dart';
import 'search_page.dart';

/// 排序方式。
enum _SortMode { updated, remainingAsc, remainingDesc, name }

const Map<_SortMode, String> _sortLabels = {
  _SortMode.updated: '更新时间',
  _SortMode.remainingAsc: '余量升序',
  _SortMode.remainingDesc: '余量降序',
  _SortMode.name: '名称',
};

/// 固定列「类别 / 品牌 / 封装规格」的组 id；参数列 id 为 `param:<参数名>`。
const String _kCategoryGroup = 'category';
const String _kBrandGroup = 'brand';
const String _kPackageGroup = 'package';
const String _kParamPrefix = 'param:';
const String _kNoneKey = '__none__';

/// P3 大类筛选页（线框 04）——立创式多列分面筛选。
class CategoryFilterPage extends StatefulWidget {
  const CategoryFilterPage({
    super.key,
    required this.topCategoryId,
    required this.topCategoryName,
  });

  final int topCategoryId;
  final String topCategoryName;

  @override
  State<CategoryFilterPage> createState() => _CategoryFilterPageState();
}

class _FilterData {
  const _FilterData(this.materials, this.subcategories);

  final List<MaterialItem> materials;
  final List<Category> subcategories;
}

class _CategoryFilterPageState extends State<CategoryFilterPage>
    with MultiSelectMixin<CategoryFilterPage> {
  late Future<_FilterData> _future = _load();
  int _revision = -1;

  final Map<String, Set<String>> _selection = {};
  bool _lowStockOnly = false;
  bool _unassignedOnly = false;
  _SortMode _sort = _SortMode.updated;

  /// 当前结果集里可批量删除的物料 id（进入多选/全选时刷新）。
  List<int> _selectableIds = const [];

  Future<_FilterData> _load() async {
    final materials = await MaterialRepository.byTopCategory(
      widget.topCategoryId,
    );
    final subs = await CategoryRepository.subcategoriesWithCount(
      widget.topCategoryId,
    );
    return _FilterData(materials, subs);
  }

  /// 某个物料在某个筛选列里的取值集合（与物料详情页参数表同源：params_json）。
  List<String> _valuesOf(MaterialItem item, String groupId) {
    if (groupId == _kCategoryGroup) {
      final id = item.categoryId;
      if (id == null || id == widget.topCategoryId) return const [_kNoneKey];
      return [id.toString()];
    }
    if (groupId == _kBrandGroup) {
      final brand = item.brand?.trim() ?? '';
      return brand.isEmpty ? const [] : [brand];
    }
    if (groupId == _kPackageGroup) {
      final value = item.package?.trim() ?? '';
      return value.isEmpty ? const [] : [value];
    }
    if (groupId.startsWith(_kParamPrefix)) {
      final name = groupId.substring(_kParamPrefix.length);
      return [
        for (final param in item.params)
          if (param.k == name && param.v.trim().isNotEmpty) param.v.trim(),
      ];
    }
    return const [];
  }

  List<FacetGroup> _buildGroups(
    _FilterData data,
    AppState appState,
    List<MaterialItem> filtered,
  ) {
    // 固定三列（最左）：类别 | 品牌 | 封装/规格
    final groups = <FacetGroup>[
      _buildCategoryGroup(data, appState),
      _valueGroup(
        id: _kBrandGroup,
        title: '品牌',
        data: data,
        appState: appState,
      ),
      _valueGroup(
        id: _kPackageGroup,
        title: '封装/规格',
        data: data,
        appState: appState,
      ),
    ];

    // 动态参数列：扫描当前筛选范围内所有物料的 params_json，
    // 出现过的参数键（容值/耐压/精度/功率…）每个键一列，键名不写死。
    final frequency = <String, int>{};
    for (final item in filtered) {
      for (final param in item.params) {
        if (param.v.trim().isEmpty) continue;
        frequency[param.k] = (frequency[param.k] ?? 0) + 1;
      }
    }
    final keys = frequency.keys.toList()
      ..sort((a, b) {
        final byCount = frequency[b]!.compareTo(frequency[a]!);
        return byCount != 0 ? byCount : a.compareTo(b);
      });
    for (final key in keys) {
      groups.add(
        _valueGroup(
          id: '$_kParamPrefix$key',
          title: key,
          data: data,
          appState: appState,
        ),
      );
    }
    return groups;
  }

  /// 固定列「类别」：按子类配置顺序排列，未分类排在最后。
  FacetGroup _buildCategoryGroup(_FilterData data, AppState appState) {
    const id = _kCategoryGroup;
    final counts = _scopeCounts(data, appState, id);
    final selected = _selection[id] ?? const <String>{};

    final values = <FacetValue>[];
    for (final sub in data.subcategories) {
      final key = sub.id.toString();
      final count = counts[key] ?? 0;
      if (count == 0 && !selected.contains(key)) continue;
      values.add(FacetValue(key: key, label: sub.name, count: count));
    }
    final noneCount = counts[_kNoneKey] ?? 0;
    if (noneCount > 0 || selected.contains(_kNoneKey)) {
      values.add(FacetValue(key: _kNoneKey, label: '未分类', count: noneCount));
    }
    for (final entry in counts.entries) {
      if (values.any((v) => v.key == entry.key)) continue;
      values.add(
        FacetValue(key: entry.key, label: entry.key, count: entry.value),
      );
    }
    return FacetGroup(id: id, title: '类别', values: values);
  }

  /// 取值列（品牌 / 封装规格 / 动态参数）：
  /// 列内条目 = 当前范围内出现过的值去重 + 数量，并按「数值+单位」智能排序。
  FacetGroup _valueGroup({
    required String id,
    required String title,
    required _FilterData data,
    required AppState appState,
  }) {
    final counts = _scopeCounts(data, appState, id);
    final selected = _selection[id] ?? const <String>{};

    final values = [
      for (final entry in counts.entries)
        FacetValue(key: entry.key, label: entry.key, count: entry.value),
    ];
    // 已选但当前范围内已无数据的值仍保留，避免筛选条件在列内"消失"
    for (final key in selected) {
      if (!values.any((v) => v.key == key)) {
        values.add(FacetValue(key: key, label: key, count: 0));
      }
    }
    values.sort((a, b) => compareParamValues(a.label, b.label));
    return FacetGroup(id: id, title: title, values: values);
  }

  /// 在"除本列外其余筛选条件"作用下的取值计数。
  Map<String, int> _scopeCounts(
    _FilterData data,
    AppState appState,
    String groupId,
  ) {
    final scope = _applyFilters(data.materials, appState, exceptGroup: groupId);
    final counts = <String, int>{};
    for (final item in scope) {
      for (final value in _valuesOf(item, groupId)) {
        counts[value] = (counts[value] ?? 0) + 1;
      }
    }
    return counts;
  }

  List<MaterialItem> _applyFilters(
    List<MaterialItem> materials,
    AppState appState, {
    String? exceptGroup,
  }) {
    return materials.where((item) {
      for (final entry in _selection.entries) {
        if (entry.key == exceptGroup) continue;
        if (entry.value.isEmpty) continue;
        final values = _valuesOf(item, entry.key);
        if (!values.any(entry.value.contains)) return false;
      }
      if (_lowStockOnly && !appState.isLowStock(item)) return false;
      if (_unassignedOnly &&
          item.locationId != null &&
          item.locationId != kUnassignedLocationId) {
        return false;
      }
      return true;
    }).toList();
  }

  void _toggle(String groupId, String key) {
    setState(() {
      final set = _selection.putIfAbsent(groupId, () => <String>{});
      if (set.contains(key)) {
        set.remove(key);
        if (set.isEmpty) _selection.remove(groupId);
      } else {
        set.add(key);
      }
    });
  }

  List<SelectedChip> _chips(List<FacetGroup> groups) {
    final chips = <SelectedChip>[];
    for (final entry in _selection.entries) {
      FacetGroup? group;
      for (final candidate in groups) {
        if (candidate.id == entry.key) {
          group = candidate;
          break;
        }
      }
      for (final key in entry.value) {
        var label = key;
        if (group != null) {
          for (final value in group.values) {
            if (value.key == key) {
              label = value.label;
              break;
            }
          }
        }
        chips.add(SelectedChip(groupId: entry.key, key: key, label: label));
      }
    }
    return chips;
  }

  void _sortItems(List<MaterialItem> items) {
    switch (_sort) {
      case _SortMode.remainingAsc:
        items.sort((a, b) => a.qtyRemaining.compareTo(b.qtyRemaining));
      case _SortMode.remainingDesc:
        items.sort((a, b) => b.qtyRemaining.compareTo(a.qtyRemaining));
      case _SortMode.name:
        items.sort((a, b) => a.title.compareTo(b.title));
      case _SortMode.updated:
        items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    }
  }

  Future<void> _deleteSelected() async {
    final ids = selectedIds.toList();
    if (ids.isEmpty) return;
    final ok = await showConfirmDialog(
      context,
      title: '批量删除物料',
      message: '确定删除选中的 ${ids.length} 种物料？\n每种物料的库存流水将一并删除，且不可恢复。',
      confirmText: '删除',
      danger: true,
    );
    if (!ok) return;
    for (final id in ids) {
      await MaterialRepository.delete(id);
    }
    if (!mounted) return;
    exitSelection();
    context.read<AppState>().notifyDataChanged();
    showToast(context, '已删除 ${ids.length} 种物料');
  }

  /// 当前筛选结果里的物料 id（点击时实时计算，避免用到过期缓存）。
  Future<List<int>> _querySelectableIds() async {
    final appState = context.read<AppState>();
    final data = await _future;
    final filtered = _applyFilters(data.materials, appState);
    return [for (final item in filtered) item.id!];
  }

  Future<void> _startSelection() async {
    final ids = await _querySelectableIds();
    if (!mounted) return;
    if (ids.isEmpty) {
      showToast(context, '当前没有可批量删除的物料');
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

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final appState = context.watch<AppState>();
    if (appState.revision != _revision) {
      _revision = appState.revision;
      _future = _load();
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
              title: Text(widget.topCategoryName),
              actions: [
                PopupMenuButton<_SortMode>(
                  icon: const Icon(Icons.swap_vert),
                  tooltip: '排序',
                  initialValue: _sort,
                  onSelected: (value) => setState(() => _sort = value),
                  itemBuilder: (context) => [
                    for (final entry in _sortLabels.entries)
                      PopupMenuItem(value: entry.key, child: Text(entry.value)),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.checklist),
                  tooltip: '批量删除',
                  onPressed: _startSelection,
                ),
                IconButton(
                  icon: const Icon(Icons.search),
                  tooltip: '搜索',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SearchPage()),
                  ),
                ),
              ],
            ),
      body: FutureBuilder<_FilterData>(
        future: _future,
        builder: (context, snapshot) {
          final data = snapshot.data;
          if (data == null) {
            return const Center(child: CircularProgressIndicator());
          }
          // 先算出最终结果集，筛选列由它反推（列集合随数据变化）
          final filtered = _applyFilters(data.materials, appState);
          _sortItems(filtered);
          final groups = _buildGroups(data, appState, filtered);
          final chips = _chips(groups);

          return Column(
            children: [
              if (groups.isNotEmpty)
                FacetFilterBar(
                  groups: groups,
                  selection: _selection,
                  onToggle: _toggle,
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: palette.border),
                    bottom: BorderSide(color: palette.border),
                  ),
                ),
                child: SelectedChipsBar(
                  chips: chips,
                  onRemove: (chip) => _toggle(chip.groupId, chip.key),
                  onClear: () => setState(() {
                    _selection.clear();
                    _lowStockOnly = false;
                    _unassignedOnly = false;
                  }),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Row(
                  children: [
                    _QuickChip(
                      label: '低库存',
                      selected: _lowStockOnly,
                      onTap: () =>
                          setState(() => _lowStockOnly = !_lowStockOnly),
                    ),
                    const SizedBox(width: 8),
                    _QuickChip(
                      label: '未分配仓库',
                      selected: _unassignedOnly,
                      onTap: () =>
                          setState(() => _unassignedOnly = !_unassignedOnly),
                    ),
                    const Spacer(),
                    Text(
                      '共 ${filtered.length} 种',
                      style: TextStyle(fontSize: 12, color: palette.textSub),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? const EmptyState(
                        icon: Icons.inventory_2_outlined,
                        message: '没有符合条件的物料',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final item = filtered[index];
                          return MaterialCard(
                            item: item,
                            lowStock: appState.isLowStock(item),
                            iconKey: item.categoryIcon,
                            selected: selectedIds.contains(item.id),
                            trailing: selecting
                                ? SelectCheck(
                                    checked: selectedIds.contains(item.id),
                                  )
                                : null,
                            onTap: () {
                              if (selecting) {
                                toggleSelected(item.id!);
                                return;
                              }
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      MaterialDetailPage(materialId: item.id!),
                                ),
                              );
                            },
                            onLongPress:
                                selecting || useSecondaryTapSelection
                                ? null
                                : () => enterSelection(item.id!),
                            onSecondaryTap:
                                selecting || !useSecondaryTapSelection
                                ? null
                                : () => enterSelection(item.id!),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  const _QuickChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? palette.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? palette.primary : palette.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? palette.primary : palette.textSub,
          ),
        ),
      ),
    );
  }
}
