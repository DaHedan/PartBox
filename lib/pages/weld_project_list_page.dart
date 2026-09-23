import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repositories/bom_repository.dart';
import '../data/repositories/weld_repository.dart';
import '../data/weld/ibom_import.dart';
import '../data/weld/ibom_parser.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/dialogs.dart';
import '../widgets/empty_state.dart';
import '../widgets/multi_select.dart';
import 'weld_page.dart';

/// F11 焊接辅助的工程列表：导入嘉立创导出的 iBOM（单文件 HTML），
/// 之后可反复打开继续焊（进度存在 PartBox 侧）。
class WeldProjectListPage extends StatefulWidget {
  const WeldProjectListPage({super.key});

  @override
  State<WeldProjectListPage> createState() => _WeldProjectListPageState();
}

/// 拖拽导入只在电脑端可用（移动端没有系统级文件拖拽）。
bool get _supportsDrop => !Platform.isAndroid && !Platform.isIOS;

class _WeldProjectListPageState extends State<WeldProjectListPage>
    with MultiSelectMixin<WeldProjectListPage> {
  late Future<List<_ProjectRow>> _future = _loadProjects();
  bool _importing = false;

  static const List<String> _allowedExtensions = ['html', 'htm'];

  /// 拖入文件时高亮整个页面。
  bool _dragging = false;

  /// 焊接页在前台时关闭拖拽目标：DropTarget 在不可见时仍会收到事件。
  bool _dropEnabled = true;

  /// 可批量删除的条目（iBOM 工程）。
  List<int> _selectableIds = const [];

  bool _isIbomFile(String name) {
    final lower = name.toLowerCase();
    return _allowedExtensions.any(lower.endsWith);
  }

  /// 只列 iBOM 工程（source = ibom），BOM 对照的工程不混进来。
  Future<List<_ProjectRow>> _loadProjects() async {
    final all = await BomRepository.projects();
    final welded = await WeldRepository.weldedCounts();
    return [
      for (final project in all)
        if (project.source == 'ibom')
          _ProjectRow(project, welded[project.id] ?? 0),
    ];
  }

  void _reload() {
    setState(() {
      _future = _loadProjects();
    });
  }

  Future<void> _import() async {
    final picked = await FilePicker.pickFile(
      dialogTitle: '选择 iBOM 文件',
      type: FileType.custom,
      allowedExtensions: _allowedExtensions,
    );
    final path = picked?.path;
    if (path == null || !mounted) return;
    await _importPaths([path]);
  }

  /// 导入若干 iBOM（选文件与拖入共用一条链路）。
  Future<void> _importPaths(List<String> paths) async {
    setState(() => _importing = true);
    final imported = <(int, String)>[];
    try {
      for (final path in paths) {
        final name = _baseName(path);
        final outcome = await IbomImportService.importFile(
          sourcePath: path,
          displayName: name,
        );
        imported.add((outcome.projectId, name));
      }
    } on IbomParseException catch (error) {
      if (mounted) showToast(context, error.message);
    } catch (error) {
      if (mounted) showToast(context, '导入失败：$error');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
    if (!mounted || imported.isEmpty) return;
    _reload();
    if (imported.length == 1) {
      await _openProject(imported.single.$1, imported.single.$2);
    } else {
      showToast(context, '已导入 ${imported.length} 个焊接工程');
    }
  }

  /// 电脑端把 iBOM 拖进窗口即可导入。
  Future<void> _onDrop(DropDoneDetails details) async {
    setState(() => _dragging = false);
    if (_importing) return;
    final paths = details.files
        .where((file) => _isIbomFile(file.name))
        .map((file) => file.path)
        .toList(growable: false);
    if (paths.isEmpty) {
      showToast(context, '只支持 .html / .htm 文件');
      return;
    }
    await _importPaths(paths);
  }

  /// 去掉路径与扩展名，作为工程名。
  String _baseName(String path) {
    final name = path.split(RegExp(r'[\\/]')).last;
    return name.replaceAll(RegExp(r'\.html?$', caseSensitive: false), '');
  }

  Future<void> _openProject(int projectId, String title) async {
    // 焊接页在前台时 DropTarget 仍会收到拖拽事件，先关掉
    setState(() => _dropEnabled = false);
    try {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => WeldPage(projectId: projectId, title: title),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _dropEnabled = true);
        _reload();
      }
    }
  }

  Future<void> _open(BomProject project) async {
    await _openProject(project.id!, project.name);
  }

  Future<void> _delete(BomProject project) async {
    final sure = await showConfirmDialog(
      context,
      title: '删除焊接工程',
      message: '将删除「${project.name}」的元件清单与焊接进度（不影响库存流水）。',
      confirmText: '删除',
      danger: true,
    );
    if (sure != true) return;
    final projectId = project.id;
    if (projectId == null) return;
    await _deleteProjectAndFile(projectId);
    if (mounted) _reload();
  }

  /// 删工程记录 + 落盘的 iBOM 文件。
  Future<void> _deleteProjectAndFile(int projectId) async {
    try {
      final project = await BomRepository.byId(projectId);
      if (project != null) {
        final path = await IbomImportService.htmlPathOf(project);
        final file = File(path);
        if (file.existsSync()) file.deleteSync();
      }
    } catch (_) {
      // 文件删不掉不影响记录清理
    }
    await BomRepository.deleteProject(projectId);
  }

  // ---------- 批量删除 ----------

  Future<List<int>> _querySelectableIds() async {
    final rows = await _loadProjects();
    return [
      for (final row in rows)
        if (row.project.id != null) row.project.id!,
    ];
  }

  Future<void> _startSelection() async {
    final ids = await _querySelectableIds();
    if (!mounted) return;
    if (ids.isEmpty) {
      showToast(context, '还没有可删除的焊接工程');
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
      title: '批量删除焊接工程',
      message: '将删除选中的 ${ids.length} 个焊接工程'
          '（含元件清单与焊接进度，不影响库存流水）。',
      confirmText: '删除',
      danger: true,
    );
    if (!ok) return;
    for (final id in ids) {
      await _deleteProjectAndFile(id);
    }
    if (!mounted) return;
    exitSelection();
    _reload();
    showToast(context, '已删除 ${ids.length} 个焊接工程');
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      appBar: selecting
          ? SelectionAppBar(
              count: selectedIds.length,
              allSelected:
                  _selectableIds.isNotEmpty &&
                  selectedIds.length == _selectableIds.length,
              onSelectAll: _selectAll,
              onDelete: _deleteSelected,
              onExit: exitSelection,
            )
          : AppBar(
              title: const Text('焊接辅助'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.checklist),
                  tooltip: '批量删除',
                  onPressed: _startSelection,
                ),
              ],
            ),
      body: DropTarget(
        enable: _supportsDrop && _dropEnabled,
        onDragEntered: (_) => setState(() => _dragging = true),
        onDragExited: (_) => setState(() => _dragging = false),
        onDragDone: _onDrop,
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: FutureBuilder<List<_ProjectRow>>(
                    future: _future,
                    builder: (context, snapshot) {
                      final rows = snapshot.data ?? const <_ProjectRow>[];
                      if (snapshot.connectionState != ConnectionState.done &&
                          !snapshot.hasData) {
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      }
                      if (rows.isEmpty) {
                        return const EmptyState(
                          icon: Icons.precision_manufacturing_outlined,
                          message:
                              '还没有焊接工程\n导入嘉立创 EDA 导出的「交互式 BOM」单文件 HTML',
                        );
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: rows.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) =>
                            _projectCard(context, palette, rows[index]),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: FilledButton.icon(
                    onPressed: _importing ? null : _import,
                    icon: _importing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.file_upload_outlined),
                    label: Text(_importing ? '正在解析…' : '导入 iBOM'),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    '支持嘉立创 EDA 专业版导出的「交互式 BOM（SMT 焊接工具）」单文件 HTML\n'
                    '打开后自动配置为：位号不聚合、隐藏已焊接、阻焊蓝、喷锡银'
                    '${_supportsDrop ? '\n也可以把 .html 直接拖进窗口' : ''}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.5,
                      color: palette.textSub,
                    ),
                  ),
                ),
              ],
            ),
            if (_dragging)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    margin: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: palette.card.withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: palette.primary, width: 2),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.file_download_outlined,
                            size: 48,
                            color: palette.primary,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '松手即可导入 iBOM',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: palette.text,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '支持 .html / .htm，可一次拖入多个',
                            style: TextStyle(
                              fontSize: 12,
                              color: palette.textSub,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _projectCard(BuildContext context, AppPalette palette, _ProjectRow row) {
    final project = row.project;
    final projectId = project.id!;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: selecting
            ? () => toggleSelected(projectId)
            : () => _open(project),
        onLongPress: selecting ? null : () => enterSelection(projectId),
        onSecondaryTap: selecting || !useSecondaryTapSelection
            ? null
            : () => enterSelection(projectId),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      project.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${project.itemCount} 个位号 · 已焊 ${row.welded} / ${project.itemCount}',
                      style: TextStyle(fontSize: 12, color: palette.textSub),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '待采购 ${project.checkedCount} · '
                      '${formatDateTime(project.updatedAt)}',
                      style: TextStyle(fontSize: 11, color: palette.textSub),
                    ),
                  ],
                ),
              ),
              if (selecting)
                SelectCheck(checked: selectedIds.contains(projectId))
              else
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert,
                    size: 20,
                    color: palette.textSub,
                  ),
                  tooltip: '更多',
                  onSelected: (value) {
                    if (value == 'delete') _delete(project);
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'delete', child: Text('删除')),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 列表行：工程 + 已焊接数量。
class _ProjectRow {
  const _ProjectRow(this.project, this.welded);

  final BomProject project;
  final int welded;
}
