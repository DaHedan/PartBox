import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../data/repositories/location_repository.dart';
import '../data/seed_data.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/app_drawer.dart';
import '../widgets/dialogs.dart';
import '../widgets/empty_state.dart';
import '../widgets/location_row.dart';
import '../widgets/multi_select.dart';
import 'location_detail_page.dart';

/// P5 仓库页（线框 06）。
class LocationPage extends StatefulWidget {
  const LocationPage({super.key});

  @override
  State<LocationPage> createState() => _LocationPageState();
}

class _LocationPageState extends State<LocationPage>
    with MultiSelectMixin<LocationPage> {
  late Future<List<Location>> _future = LocationRepository.all(withStats: true);
  int _revision = -1;

  /// 可批量删除的仓库 id（进入多选/全选时刷新；内置"未分配"不可删）。
  List<int> _selectableIds = const [];

  Future<List<int>> _querySelectableIds() async {
    final locations = await LocationRepository.all();
    return [
      for (final location in locations)
        if (location.id != kUnassignedLocationId) location.id!,
    ];
  }

  Future<void> _startSelection() async {
    final ids = await _querySelectableIds();
    if (!mounted) return;
    if (ids.isEmpty) {
      showToast(context, '内置"未分配"不可删除，没有可批量删除的仓库');
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
      title: '批量删除仓库',
      message: '确定删除选中的 ${ids.length} 个仓库？\n这些仓库下的物料将迁移到「未分配」。',
      confirmText: '删除',
      danger: true,
    );
    if (!ok) return;
    for (final id in ids) {
      await LocationRepository.delete(id);
    }
    if (!mounted) return;
    exitSelection();
    context.read<AppState>().notifyDataChanged();
    showToast(context, '已删除 ${ids.length} 个仓库');
  }

  /// 内置"未分配"不可选。
  void _enterSelectionFor(Location location) {
    if (location.id == kUnassignedLocationId) {
      showToast(context, '内置"未分配"不可删除');
      return;
    }
    enterSelection(location.id);
  }

  Future<void> _add() async {
    final name = await showTextDialog(
      context,
      title: '添加仓库',
      hint: '如：元件柜A / 抽屉3 / 料盒B',
    );
    if (name == null) return;
    await LocationRepository.insert(name);
    if (!mounted) return;
    context.read<AppState>().notifyDataChanged();
    showToast(context, '已添加仓库「$name」');
  }

  Future<void> _rename(Location location) async {
    final name = await showTextDialog(
      context,
      title: '重命名仓库',
      initial: location.name,
    );
    if (name == null) return;
    await LocationRepository.rename(location.id!, name);
    if (!mounted) return;
    context.read<AppState>().notifyDataChanged();
  }

  Future<void> _delete(Location location) async {
    if (location.id == kUnassignedLocationId) {
      showToast(context, '内置"未分配"不可删除');
      return;
    }
    final ok = await showConfirmDialog(
      context,
      title: '删除仓库',
      message: '确定删除「${location.name}」？该仓库下的 ${location.materialKinds} 种物料将迁移到「未分配」。',
      confirmText: '删除',
      danger: true,
    );
    if (!ok) return;
    await LocationRepository.delete(location.id!);
    if (!mounted) return;
    context.read<AppState>().notifyDataChanged();
    showToast(context, '已删除「${location.name}」');
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final revision = context.watch<AppState>().revision;
    if (revision != _revision) {
      _revision = revision;
      _future = LocationRepository.all(withStats: true);
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
              leading: const DrawerMenuButton(),
              title: const Text('仓库'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.checklist),
                  tooltip: '批量删除',
                  onPressed: _startSelection,
                ),
              ],
            ),
      drawer: const AppDrawer(current: RootPage.location),
      body: Column(
        children: [
          Expanded(
            child: FutureBuilder<List<Location>>(
              future: _future,
              builder: (context, snapshot) {
                final locations = snapshot.data ?? const <Location>[];
                if (locations.isEmpty) {
                  return const EmptyState(
                    icon: Icons.warehouse_outlined,
                    message: '还没有仓库，点下方按钮添加',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: locations.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final location = locations[index];
                    final selectable = location.id != kUnassignedLocationId;
                    final checked = selectedIds.contains(location.id);
                    return Card(
                      child: Row(
                        children: [
                          Expanded(
                            child: LocationRow(
                              location: location,
                              onTap: () {
                                if (selecting) {
                                  if (!selectable) {
                                    showToast(context, '内置"未分配"不可删除');
                                    return;
                                  }
                                  toggleSelected(location.id!);
                                  return;
                                }
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => LocationDetailPage(
                                      locationId: location.id!,
                                    ),
                                  ),
                                );
                              },
                              onLongPress:
                                  selecting || useSecondaryTapSelection
                                  ? null
                                  : () => _enterSelectionFor(location),
                              onSecondaryTap:
                                  selecting || !useSecondaryTapSelection
                                  ? null
                                  : () => _enterSelectionFor(location),
                            ),
                          ),
                          if (selecting)
                            Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: selectable
                                  ? SelectCheck(checked: checked)
                                  : Icon(
                                      Icons.lock_outline,
                                      size: 20,
                                      color: palette.textSub,
                                    ),
                            )
                          else
                            PopupMenuButton<String>(
                              icon: Icon(
                                Icons.more_vert,
                                size: 20,
                                color: palette.textSub,
                              ),
                              onSelected: (value) {
                                if (value == 'rename') {
                                  _rename(location);
                                } else {
                                  _delete(location);
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'rename',
                                  child: Text('重命名'),
                                ),
                                if (location.id != kUnassignedLocationId)
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Text('删除'),
                                  ),
                              ],
                            ),
                        ],
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
                label: const Text('添加仓库'),
              ),
            ),
        ],
      ),
    );
  }
}
