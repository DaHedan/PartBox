import 'dart:io';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/bom/bom_matcher.dart';
import '../data/bom/bom_parser.dart';
import '../data/models.dart';
import '../data/repositories/bom_repository.dart';
import '../data/repositories/material_repository.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/empty_state.dart';
import '../widgets/dialogs.dart';
import 'bom_compare_page.dart';

/// F10 BOM 工程列表：历史导入可重复打开（入口见首页「BOM 对照」大卡）。
/// 电脑端（Windows/macOS/Linux）支持把 xlsx / csv 直接拖进窗口导入。
class BomProjectListPage extends StatefulWidget {
  const BomProjectListPage({super.key});

  @override
  State<BomProjectListPage> createState() => _BomProjectListPageState();
}

/// 拖拽导入只在电脑端可用（移动端没有系统级文件拖拽）。
bool get _supportsDrop => !Platform.isAndroid && !Platform.isIOS;

class _BomProjectListPageState extends State<BomProjectListPage> {
  late Future<List<BomProject>> _future = BomRepository.projects();
  bool _importing = false;

  /// 拖入文件时高亮整个页面。
  bool _dragging = false;

  /// 比对页在前台时关闭拖拽目标：DropTarget 在不可见时仍会收到事件。
  bool _dropEnabled = true;

  static const List<String> _allowedExtensions = ['xlsx', 'csv'];

  void _reload() {
    // 注意：回调里不能直接返回 Future，否则 setState 断言失败、界面不刷新。
    setState(() {
      _future = BomRepository.projects();
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      appBar: AppBar(title: const Text('BOM 对照')),
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
                  child: FutureBuilder<List<BomProject>>(
                    future: _future,
                    builder: (context, snapshot) {
                      final projects = snapshot.data ?? const <BomProject>[];
                      if (snapshot.connectionState != ConnectionState.done &&
                          !snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (projects.isEmpty) {
                        return const EmptyState(
                          icon: Icons.assignment_outlined,
                          message:
                              '还没有 BOM 工程\n导入嘉立创导出的 BOM（xlsx / csv）开始比对',
                        );
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: projects.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) =>
                            _projectCard(context, projects[index]),
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
                    label: Text(_importing ? '正在解析…' : '导入 BOM'),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _supportsDrop
                        ? '支持嘉立创 EDA 导出的 xlsx（sheet「bom模板」）与 CSV（可手动映射列）\n也可以把文件直接拖进窗口'
                        : '支持嘉立创 EDA 导出的 xlsx（sheet「bom模板」）与 CSV（可手动映射列）',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, height: 1.5, color: palette.textSub),
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
                            '松手即可导入 BOM',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: palette.text,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '支持 .xlsx / .csv，可一次拖入多个',
                            style: TextStyle(fontSize: 12, color: palette.textSub),
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

  Widget _projectCard(BuildContext context, BomProject project) {
    final palette = context.palette;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openProject(project.id!),
        onSecondaryTap: () => _delete(project),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
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
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: palette.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${project.itemCount} 行 · 已勾选 ${project.checkedCount} · ${formatDateTime(project.updatedAt)}',
                      style: TextStyle(fontSize: 12, color: palette.textSub),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, size: 20, color: palette.textSub),
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

  Future<void> _delete(BomProject project) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除 BOM 工程',
      message: '确定删除「${project.name}」及其 ${project.itemCount} 行比对结果？',
      confirmText: '删除',
      danger: true,
    );
    if (!ok) return;
    await BomRepository.deleteProject(project.id!);
    if (!mounted) return;
    _reload();
    showToast(context, '已删除「${project.name}」');
  }

  Future<void> _import() async {
    final file = await FilePicker.pickFile(
      dialogTitle: '选择 BOM 文件',
      type: FileType.custom,
      allowedExtensions: _allowedExtensions,
    );
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;

    setState(() => _importing = true);
    int? projectId;
    try {
      projectId = await _importBytes(bytes, file.name, file.extension);
    } catch (e) {
      if (mounted) showToast(context, '导入失败：$e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
    if (!mounted) return;
    _reload();
    if (projectId != null) await _openProject(projectId);
  }

  /// 电脑端拖入文件：支持一次拖多个，一个文件生成一个工程。
  Future<void> _onDrop(DropDoneDetails details) async {
    setState(() => _dragging = false);
    if (_importing) return;

    final files = details.files
        .where((file) => _isBomFile(file.name))
        .toList(growable: false);
    if (files.isEmpty) {
      showToast(context, '只支持 .xlsx / .csv 文件');
      return;
    }

    setState(() => _importing = true);
    final imported = <int>[];
    try {
      for (final file in files) {
        final bytes = await file.readAsBytes();
        if (!mounted) return;
        final id = await _importBytes(
          bytes,
          file.name,
          _extensionOf(file.name),
        );
        if (id != null) imported.add(id);
      }
    } catch (e) {
      if (mounted) showToast(context, '导入失败：$e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
    if (!mounted) return;

    _reload();
    if (imported.length == 1) {
      await _openProject(imported.single);
    } else if (imported.isNotEmpty) {
      showToast(context, '已导入 ${imported.length} 个 BOM 工程');
    }
  }

  /// 解析 + 建工程。返回工程 id，失败（格式不识别 / 未完成映射）返回 null。
  Future<int?> _importBytes(
    Uint8List bytes,
    String fileName,
    String? extension,
  ) async {
    final isCsv = (extension ?? '').toLowerCase() == 'csv';
    final ParsedBom? parsed = isCsv
        ? await _parseCsv(bytes)
        : BomParser.parseXlsx(bytes);
    if (!mounted) return null;
    if (parsed == null) {
      showToast(
        context,
        isCsv ? 'CSV 未完成列映射' : '不是嘉立创 BOM 格式，可另存为 CSV 后手动映射列',
      );
      return null;
    }
    if (parsed.rows.isEmpty) {
      showToast(context, '文件里没有可导入的 BOM 行');
      return null;
    }
    return _createProject(parsed, fileName);
  }

  /// 打开比对页。期间关掉拖拽目标：DropTarget 被遮住时仍会收到拖拽事件。
  Future<void> _openProject(int projectId) async {
    setState(() => _dropEnabled = false);
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => BomComparePage(projectId: projectId)),
    );
    if (!mounted) return;
    setState(() => _dropEnabled = true);
    _reload();
  }

  bool _isBomFile(String fileName) =>
      _allowedExtensions.contains(_extensionOf(fileName));

  String? _extensionOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    return dot < 0 ? null : fileName.substring(dot + 1).toLowerCase();
  }

  /// CSV：自动识别表头即可直接用；识别不出「数量」列时弹手动列映射。
  Future<ParsedBom?> _parseCsv(List<int> bytes) async {
    final table = BomParser.readCsv(decodeCsvBytes(bytes));
    if (table.isEmpty) return null;
    final headerIndex = BomParser.findHeaderRow(table) ?? 0;
    if (headerIndex >= table.length) return null;

    var mapping = BomParser.guessMapping(table[headerIndex]);
    if (!mapping.containsKey(BomField.quantity)) {
      final chosen = await showBomColumnMappingDialog(
        context,
        header: table[headerIndex],
        initial: mapping,
      );
      if (chosen == null) return null;
      mapping = chosen;
    }
    return ParsedBom(
      sheetName: 'csv',
      source: 'csv',
      rows: BomParser.mapRows(table, headerIndex, mapping),
    );
  }

  /// 建工程 → 逐行四色比对 → 落库（比对结果持久化，默认勾选黄 + 红）。
  Future<int> _createProject(ParsedBom parsed, String fileName) async {
    final materials = await MaterialRepository.all();
    final now = DateTime.now();
    final projectId = await BomRepository.insertProject(
      BomProject(
        name: bomProjectNameFromFile(fileName),
        fileName: fileName,
        source: parsed.source,
        createdAt: now,
        updatedAt: now,
      ),
    );

    final items = <BomItem>[];
    for (var i = 0; i < parsed.rows.length; i++) {
      final row = parsed.rows[i];
      final result = BomMatcher.match(row, materials);
      final matched = result.candidates.isEmpty
          ? null
          : result.candidates.first;
      items.add(
        row.toItem(projectId, i).copyWith(
          matchStatus: result.status,
          matchedMaterialId: matched?.id,
          clearMatched: matched == null,
          checked: MatchStatus.defaultChecked(result.status),
        ),
      );
    }
    await BomRepository.insertItems(items);
    return projectId;
  }
}

/// CSV 手动列映射对话框（保底）。
Future<Map<BomField, int>?> showBomColumnMappingDialog(
  BuildContext context, {
  required List<String> header,
  required Map<BomField, int> initial,
}) {
  return showDialog<Map<BomField, int>>(
    context: context,
    builder: (_) => _ColumnMappingDialog(header: header, initial: initial),
  );
}

class _ColumnMappingDialog extends StatefulWidget {
  const _ColumnMappingDialog({required this.header, required this.initial});

  final List<String> header;
  final Map<BomField, int> initial;

  @override
  State<_ColumnMappingDialog> createState() => _ColumnMappingDialogState();
}

class _ColumnMappingDialogState extends State<_ColumnMappingDialog> {
  late final Map<BomField, int?> _mapping = {
    for (final field in BomField.values) field: widget.initial[field],
  };

  void _submit() {
    if (_mapping[BomField.quantity] == null) {
      showToast(context, '请先指定「数量」所在的列');
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).pop({
      for (final entry in _mapping.entries)
        if (entry.value != null) entry.key: entry.value!,
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AlertDialog(
      title: const Text('映射 BOM 列'),
      content: SizedBox(
        width: 420,
        height: 420,
        child: ListView(
          shrinkWrap: true,
          children: [
            Text(
              '自动识别失败，请指定各字段对应的列。数量为必填。',
              style: TextStyle(fontSize: 12, color: palette.textSub),
            ),
            const SizedBox(height: 12),
            for (final field in BomField.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        field.required ? '${field.label} *' : field.label,
                        style: TextStyle(fontSize: 13, color: palette.text),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 190,
                      child: DropdownButtonFormField<int?>(
                        initialValue: _mapping[field],
                        isDense: true,
                        hint: const Text('不导入'),
                        decoration: const InputDecoration(),
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text('不导入'),
                          ),
                          for (var i = 0; i < widget.header.length; i++)
                            DropdownMenuItem<int?>(
                              value: i,
                              child: Text(
                                widget.header[i].isEmpty
                                    ? '第 ${i + 1} 列'
                                    : widget.header[i],
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) =>
                            setState(() => _mapping[field] = value),
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
          onPressed: () => Navigator.of(context).pop(),
          child: Text('取消', style: TextStyle(color: palette.textSub)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(80, 40)),
          onPressed: _submit,
          child: const Text('导入'),
        ),
      ],
    );
  }
}
