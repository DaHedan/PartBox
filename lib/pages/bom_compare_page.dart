import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/bom/bom_exporter.dart';
import '../data/bom/bom_matcher.dart';
import '../data/bom/bom_parser.dart';
import '../data/models.dart';
import '../data/repositories/bom_repository.dart';
import '../data/repositories/material_repository.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/empty_state.dart';

/// F10 比对结果页：四色标记 + 勾选（默认黄/红）+ 候选更换 + 双导出。
class BomComparePage extends StatefulWidget {
  const BomComparePage({super.key, required this.projectId});

  final int projectId;

  @override
  State<BomComparePage> createState() => _BomComparePageState();
}

class _BomComparePageState extends State<BomComparePage> {
  BomProject? _project;
  List<BomItem> _items = const [];
  Map<int, MaterialItem> _materials = const {};
  Map<int, List<MaterialItem>> _candidates = const {};
  final Set<int> _expanded = {};
  bool _loading = true;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final project = await BomRepository.byId(widget.projectId);
    final items = await BomRepository.items(widget.projectId);
    final materials = await MaterialRepository.all();
    final byId = <int, MaterialItem>{
      for (final material in materials)
        if (material.id != null) material.id!: material,
    };

    // 打开即重算（库变了也能纠正），但保留用户已选定的匹配对象。
    final candidates = <int, List<MaterialItem>>{};
    final refreshed = <BomItem>[];
    final changed = <BomItem>[];
    for (final item in items) {
      final result = BomMatcher.match(_rowOf(item), materials);
      var chosen = result.candidates.isEmpty ? null : result.candidates.first;
      final persistedId = item.matchedMaterialId;
      if (persistedId != null) {
        for (final candidate in result.candidates) {
          if (candidate.id == persistedId) {
            chosen = candidate;
            break;
          }
        }
      }
      final updated = item.copyWith(
        matchStatus: result.status,
        matchedMaterialId: chosen?.id,
        clearMatched: chosen == null,
      );
      if (item.id != null) candidates[item.id!] = result.candidates;
      refreshed.add(updated);
      if (updated.matchStatus != item.matchStatus ||
          updated.matchedMaterialId != item.matchedMaterialId) {
        changed.add(updated);
      }
    }
    if (changed.isNotEmpty) await BomRepository.updateMatches(changed);

    if (!mounted) return;
    setState(() {
      _project = project;
      _items = refreshed;
      _materials = byId;
      _candidates = candidates;
      _loading = false;
    });
  }

  ParsedBomRow _rowOf(BomItem item) => ParsedBomRow(
    quantity: item.quantity,
    designator: item.designator,
    comment: item.comment,
    footprint: item.footprint,
    value: item.value,
    mpn: item.mpn,
    manufacturer: item.manufacturer,
    lcscCode: item.lcscCode,
    supplier: item.supplier,
    unitPrice: item.unitPrice,
  );

  void _replace(BomItem updated) {
    setState(() {
      _items = [
        for (final item in _items) if (item.id == updated.id) updated else item,
      ];
    });
  }

  Future<void> _setChecked(BomItem item, bool checked) async {
    _replace(item.copyWith(checked: checked));
    await BomRepository.updateItem(item.id!, checked: checked);
  }

  Future<void> _choose(BomItem item, MaterialItem candidate) async {
    final updated = item.copyWith(matchedMaterialId: candidate.id);
    _replace(updated);
    setState(() => _expanded.remove(item.id));
    await BomRepository.updateItem(
      item.id!,
      matchStatus: updated.matchStatus,
      matchedMaterialId: candidate.id,
    );
  }

  Future<void> _export({required bool purchase}) async {
    final project = _project;
    if (project == null) return;
    if (purchase && !_items.any((item) => item.checked)) {
      showToast(context, '没有勾选行，采购 BOM 为空');
      return;
    }
    setState(() => _exporting = true);
    try {
      final now = DateTime.now();
      final bytes = purchase
          ? BomExporter.buildPurchaseBom(_items)
          : BomExporter.buildReplaceBom(_items, _materials);
      final fileName = purchase
          ? BomExporter.purchaseFileName(project.name, now)
          : BomExporter.replaceFileName(project.name, now);
      final uri = await FilePicker.saveFile(
        dialogTitle: purchase ? '导出采购 BOM' : '导出替换 BOM',
        fileName: fileName,
        bytes: bytes,
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      if (uri == null || !mounted) return;
      await BomRepository.touchProject(project.id!);
      if (!mounted) return;
      showToast(context, '已导出 $fileName');
    } catch (e) {
      if (mounted) showToast(context, '导出失败：$e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      appBar: AppBar(
        title: Text(_project?.name ?? 'BOM 比对'),
        actions: [
          if (_loading)
            const SizedBox.shrink()
          else
            PopupMenuButton<String>(
              enabled: !_exporting,
              icon: _exporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.ios_share),
              tooltip: '导出',
              onSelected: (value) =>
                  _export(purchase: value == 'purchase'),
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'purchase', child: Text('导出采购 BOM（勾选行）')),
                PopupMenuItem(
                  value: 'replace',
                  child: Text('导出替换 BOM（全量 + 替代说明）'),
                ),
              ],
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const EmptyState(
                  icon: Icons.assignment_outlined,
                  message: '这个 BOM 工程没有条目',
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  itemCount: _items.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) return _summary(palette);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _itemCard(_items[index - 1], palette),
                    );
                  },
                ),
    );
  }

  Widget _summary(AppPalette palette) {
    final counts = <String, int>{for (final s in MatchStatus.all) s: 0};
    var checked = 0;
    for (final item in _items) {
      final status = item.matchStatus;
      if (status != null && counts.containsKey(status)) {
        counts[status] = counts[status]! + 1;
      }
      if (item.checked) checked++;
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 14,
              runSpacing: 8,
              children: [
                for (final status in MatchStatus.all)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _dot(_statusColor(status, palette)),
                      const SizedBox(width: 6),
                      Text(
                        '${MatchStatus.label(status)} ${counts[status]}',
                        style: TextStyle(fontSize: 12, color: palette.text),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '已勾选 $checked / ${_items.length} 行（勾选 = 采购新料，默认勾选黄 + 红）',
              style: TextStyle(fontSize: 12, color: palette.textSub),
            ),
          ],
        ),
      ),
    );
  }

  Widget _itemCard(BomItem item, AppPalette palette) {
    final status = item.matchStatus ?? MatchStatus.red;
    final color = _statusColor(status, palette);
    final matched = item.matchedMaterialId == null
        ? null
        : _materials[item.matchedMaterialId!];
    final candidates = _candidates[item.id] ?? const <MaterialItem>[];
    final expanded = _expanded.contains(item.id);

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: candidates.isEmpty
                ? null
                : () => setState(() {
                    final id = item.id;
                    if (id == null) return;
                    if (expanded) {
                      _expanded.remove(id);
                    } else {
                      _expanded.add(id);
                    }
                  }),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: 4, color: color),
                  Checkbox(
                    value: item.checked,
                    onChanged: (value) => _setChecked(item, value ?? false),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item.designator.isEmpty
                                      ? '（无位号）'
                                      : item.designator,
                                  maxLines: expanded ? 6 : 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: palette.text,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '×${formatQty(item.quantity)}',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: palette.text,
                                  fontFeatures: kTabularFigures,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            [
                              if (item.comment.isNotEmpty) item.comment,
                              if (item.footprint.isNotEmpty) item.footprint,
                            ].join(' · '),
                            style: TextStyle(fontSize: 12, color: palette.textSub),
                          ),
                          if (item.mpn.isNotEmpty || item.lcscCode.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              [
                                if (item.mpn.isNotEmpty) item.mpn,
                                if (item.lcscCode.isNotEmpty) item.lcscCode,
                              ].join(' · '),
                              style: TextStyle(
                                fontSize: 12,
                                color: palette.textSub,
                              ),
                            ),
                          ],
                          if (matched != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              '匹配：${matched.title} · ${matched.locationName ?? "未分配"} · 余量 ${formatQty(matched.qtyRemaining)}',
                              style: TextStyle(fontSize: 12, color: color),
                            ),
                          ],
                          if (status == MatchStatus.blue && matched != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              '库余 ${formatQty(matched.qtyRemaining)} / 需 ${formatQty(item.quantity)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: palette.textSub,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 4, right: 10),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: color.withValues(alpha: 0.5),
                            ),
                          ),
                          child: Text(
                            MatchStatus.label(status),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: color,
                            ),
                          ),
                        ),
                        if (candidates.isNotEmpty)
                          Icon(
                            expanded ? Icons.expand_less : Icons.expand_more,
                            size: 18,
                            color: palette.textSub,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (expanded) _candidateList(item, candidates, palette),
        ],
      ),
    );
  }

  Widget _candidateList(
    BomItem item,
    List<MaterialItem> candidates,
    AppPalette palette,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1, color: palette.border),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
          child: Text(
            '候选匹配料（${candidates.length}），点选可更换',
            style: TextStyle(fontSize: 12, color: palette.textSub),
          ),
        ),
        for (final candidate in candidates)
          InkWell(
            onTap: () => _choose(item, candidate),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    candidate.id == item.matchedMaterialId
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 18,
                    color: candidate.id == item.matchedMaterialId
                        ? palette.primary
                        : palette.textSub,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          candidate.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: palette.text),
                        ),
                        Text(
                          '${candidate.lcscCode ?? "—"} · ${candidate.locationName ?? "未分配"} · 余量 ${formatQty(candidate.qtyRemaining)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: palette.textSub,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 6),
      ],
    );
  }

  Widget _dot(Color color) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );

  Color _statusColor(String status, AppPalette palette) {
    switch (status) {
      case MatchStatus.blue:
        return palette.primary;
      case MatchStatus.green:
        return palette.success;
      case MatchStatus.yellow:
        return const Color(0xFFEAB308);
      default:
        return palette.danger;
    }
  }
}
