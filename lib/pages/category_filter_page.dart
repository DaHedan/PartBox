import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../data/repositories/category_repository.dart';
import '../data/repositories/material_repository.dart';
import '../data/seed_data.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/facet_filter.dart';
import '../widgets/material_card.dart';
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

class _CategoryFilterPageState extends State<CategoryFilterPage> {
  late Future<_FilterData> _future = _load();
  int _revision = -1;

  final Map<String, Set<String>> _selection = {};
  bool _lowStockOnly = false;
  bool _unassignedOnly = false;
  _SortMode _sort = _SortMode.updated;

  Future<_FilterData> _load() async {
    final materials = await MaterialRepository.byTopCategory(
      widget.topCategoryId,
    );
    final subs = await CategoryRepository.subcategoriesWithCount(
      widget.topCategoryId,
    );
    return _FilterData(materials, subs);
  }

  /// 某个物料在某个筛选组里的取值集合。
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

  /// 动态参数列（出现频次最高的若干参数键）。
  List<String> _paramKeys(List<MaterialItem> materials) {
    final freq = <String, int>{};
    for (final item in materials) {
      for (final param in item.params) {
        if (param.v.trim().isEmpty) continue;
        freq[param.k] = (freq[param.k] ?? 0) + 1;
      }
    }
    final keys = freq.entries.where((e) => e.value >= 2).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return keys.take(4).map((e) => e.key).toList();
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

  List<FacetGroup> _buildGroups(_FilterData data, AppState appState) {
    final groups = <FacetGroup>[];

    void addGroup(String id, String title, Map<String, String> labels) {
      final scope = _applyFilters(data.materials, appState, exceptGroup: id);
      final counts = <String, int>{};
      for (final item in scope) {
        for (final value in _valuesOf(item, id)) {
          counts[value] = (counts[value] ?? 0) + 1;
        }
      }
      final values = <FacetValue>[];
      for (final entry in labels.entries) {
        values.add(
          FacetValue(
            key: entry.key,
            label: entry.value,
            count: counts[entry.key] ?? 0,
          ),
        );
      }
      if (values.isEmpty) return;
      groups.add(FacetGroup(id: id, title: title, values: values));
    }

    if (data.subcategories.isNotEmpty) {
      addGroup(_kCategoryGroup, '类别', {
        for (final sub in data.subcategories) sub.id.toString(): sub.name,
        _kNoneKey: '未分类',
      });
    }

    final brandLabels = <String, String>{};
    final packageLabels = <String, String>{};
    for (final item in data.materials) {
      final brand = item.brand?.trim() ?? '';
      if (brand.isNotEmpty) brandLabels[brand] = brand;
      final package = item.package?.trim() ?? '';
      if (package.isNotEmpty) packageLabels[package] = package;
    }
    if (brandLabels.isNotEmpty) {
      addGroup(_kBrandGroup, '品牌', brandLabels);
    }
    if (packageLabels.isNotEmpty) {
      addGroup(_kPackageGroup, '封装/规格', packageLabels);
    }

    for (final key in _paramKeys(data.materials)) {
      final labels = <String, String>{};
      for (final item in data.materials) {
        for (final param in item.params) {
          if (param.k == key && param.v.trim().isNotEmpty) {
            labels[param.v.trim()] = param.v.trim();
          }
        }
      }
      if (labels.isNotEmpty) {
        addGroup('$_kParamPrefix$key', key, labels);
      }
    }

    return groups;
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

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final appState = context.watch<AppState>();
    if (appState.revision != _revision) {
      _revision = appState.revision;
      _future = _load();
    }

    return Scaffold(
      appBar: AppBar(
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
          final groups = _buildGroups(data, appState);
          final filtered = _applyFilters(data.materials, appState);
          _sortItems(filtered);
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
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    MaterialDetailPage(materialId: item.id!),
                              ),
                            ),
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
