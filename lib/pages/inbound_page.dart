import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/lcsc/lcsc_service.dart';
import '../data/models.dart';
import '../data/repositories/location_repository.dart';
import '../data/repositories/material_repository.dart';
import '../data/seed_data.dart';
import '../data/stock_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/scan_payload.dart';
import '../widgets/dialogs.dart';
import '../widgets/material_card.dart';
import 'material_detail_page.dart';
import 'material_edit_page.dart';
import 'scan_page.dart';

/// P10 入库流程（F13）：选仓库 → 选物料 → 确认入库（只归档，连续入库）。
class InboundPage extends StatefulWidget {
  const InboundPage({super.key, this.presetLocationId});

  final int? presetLocationId;

  @override
  State<InboundPage> createState() => _InboundPageState();
}

class _InboundPageState extends State<InboundPage> {
  final TextEditingController _qty = TextEditingController();
  final TextEditingController _note = TextEditingController();

  late final Future<List<Location>> _locationsFuture = LocationRepository.all();
  final List<MaterialItem> _targets = [];
  int? _locationId;

  /// 本次清单是否由扫码加入（用于确认后自动回到扫码页，扫下一包）。
  bool _fromScan = false;

  @override
  void initState() {
    super.initState();
    _locationId =
        widget.presetLocationId ?? context.read<AppState>().lastLocationId;
  }

  @override
  void dispose() {
    _qty.dispose();
    _note.dispose();
    super.dispose();
  }

  void _addTarget(MaterialItem item) {
    if (_targets.any((e) => e.id == item.id)) {
      showToast(context, '「${item.title}」已在本次入库清单中');
      return;
    }
    setState(() => _targets.add(item));
  }

  Future<void> _pickLocation() async {
    final locations = await _locationsFuture;
    if (!mounted) return;
    Location? selected;
    for (final location in locations) {
      if (location.id == _locationId) {
        selected = location;
        break;
      }
    }
    final picked = await showPickerSheet<Location>(
      context,
      title: '选择仓库',
      options: locations,
      labelOf: (location) => location.name,
      selected: selected,
    );
    if (picked == null || !mounted) return;
    setState(() => _locationId = picked.id);
    await context.read<AppState>().setLastLocationId(picked.id!);
  }

  /// 按 C 编号加入清单（可选：标签带出的 MPN 作为预填）。
  ///
  /// 返回是否成功加入清单。
  Future<bool> _addByCode(String rawCode, {String? presetMpn}) async {
    final code = LcscService.normalizeCode(rawCode) ?? rawCode.trim();
    if (code.isEmpty) return false;
    final appState = context.read<AppState>();
    final existing = await MaterialRepository.byLcscCode(code);
    if (!mounted) return false;
    if (existing != null) {
      // 同一元件可能买多包、甚至分放不同仓库 → 默认建议新建一条独立条目
      final sameCode = await MaterialRepository.allByLcscCode(code);
      if (!mounted) return false;
      final total = sameCode.fold<double>(
        0,
        (sum, item) => sum + item.qtyRemaining,
      );
      final choice = await showDuplicateEntryDialog(
        context,
        message:
            '$code 库中已有 ${sameCode.length} 条记录'
            '（余量合计 ${formatQty(total)}）。\n'
            '同一元件买多包、或分放不同仓库时，建议新建一条单独记录。',
      );
      if (!mounted || choice == null) return false;
      if (choice == DuplicateEntryChoice.merge) {
        _addTarget(existing);
        showToast(context, '已并入已有条目「${existing.title}」');
        return true;
      }
      return _createDuplicate(existing, presetMpn: presetMpn);
    }
    showToast(context, '正在查询 $code …');
    final result = await LcscService.query(code, apiKey: appState.lcscApiKey);
    if (!mounted) return false;
    final createdId = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => MaterialEditPage(
          lcscPart: result.part,
          presetMpn: presetMpn,
          presetLocationId: _locationId,
          initialDraft: result.part == null
              ? MaterialItem(
                  name: code,
                  mpn: presetMpn,
                  lcscCode: code,
                  locationId: _locationId,
                  createdAt: DateTime.now(),
                  updatedAt: DateTime.now(),
                )
              : null,
        ),
      ),
    );
    if (createdId == null) return false;
    final created = await MaterialRepository.byId(createdId);
    if (!mounted || created == null) return false;
    _addTarget(created);
    if (result.part == null) {
      showToast(context, '查询失败已转手动录入：${result.error ?? ''}');
    }
    return true;
  }

  /// 复制已有元件的信息，新建一条独立条目（多包分开记），数量从 0 起算，
  /// 本包数量由「入库数量」在确认时加上。
  Future<bool> _createDuplicate(
    MaterialItem source, {
    String? presetMpn,
  }) async {
    final now = DateTime.now();
    final newId = await MaterialRepository.insert(
      MaterialItem(
        name: source.name,
        mpn: (presetMpn != null && presetMpn.isNotEmpty)
            ? presetMpn
            : source.mpn,
        lcscCode: source.lcscCode,
        categoryId: source.categoryId,
        package: source.package,
        brand: source.brand,
        params: source.params,
        imagePath: source.imagePath,
        unit: source.unit,
        locationId: _locationId,
        createdAt: now,
        updatedAt: now,
      ),
    );
    if (!mounted) return false;
    final created = await MaterialRepository.byId(newId);
    if (!mounted || created == null) return false;
    _addTarget(created);
    showToast(context, '已新建条目「${created.title}」，数量按入库数量累加');
    return true;
  }

  /// 扫码：立创袋标二维码会带出 C 编号 / MPN / 数量。
  ///
  /// 采用单次扫描：扫一包立刻带回，数量预填到「入库数量」输入框（可改），
  /// 确认入库后自动回到本页并再次进入扫码（连续入库，全程零输入）。
  Future<void> _scan() async {
    final hits = await Navigator.of(context).push<List<ScanPayload>>(
      MaterialPageRoute(
        builder: (_) => const ScanPage(initialContinuous: false),
      ),
    );
    if (hits == null || hits.isEmpty) return;
    for (final hit in hits) {
      if (!mounted) return;
      final code = hit.code;
      if (code == null) continue;
      final added = await _addByCode(code, presetMpn: hit.mpn);
      if (!mounted) return;
      if (!added) continue;
      _fromScan = true;
      // qty → 预填入库数量（用户可改，确认时以输入框为准）
      final qty = hit.qty;
      if (qty != null) {
        setState(() => _qty.text = formatQty(qty));
      }
    }
  }

  Future<void> _queryByCode() async {
    final input = await showTextDialog(
      context,
      title: 'C 编号',
      hint: '如 C106248',
    );
    if (input == null) return;
    await _addByCode(input);
  }

  Future<void> _createManually() async {
    final createdId = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => MaterialEditPage(presetLocationId: _locationId),
      ),
    );
    if (createdId == null) return;
    final created = await MaterialRepository.byId(createdId);
    if (!mounted || created == null) return;
    _addTarget(created);
  }

  Future<void> _pickExisting() async {
    final ids = await showModalBottomSheet<List<int>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _MaterialPickerSheet(),
    );
    if (ids == null || ids.isEmpty) return;
    for (final id in ids) {
      final item = await MaterialRepository.byId(id);
      if (!mounted) return;
      if (item != null) _addTarget(item);
    }
  }

  Future<void> _submit() async {
    if (_targets.isEmpty) {
      showToast(context, '请先选择要入库的物料');
      return;
    }
    final locationId = _locationId ?? kUnassignedLocationId;
    final note = _note.text.trim();
    final qty = double.tryParse(_qty.text.trim()) ?? 0;
    final fromScan = _fromScan;
    for (final target in _targets) {
      await StockService.inbound(
        materialId: target.id!,
        locationId: locationId,
        qty: qty,
        note: note.isEmpty ? null : note,
      );
    }
    if (!mounted) return;
    final locationName =
        (await LocationRepository.byId(locationId))?.name ?? '未分配';
    if (!mounted) return;
    context.read<AppState>().notifyDataChanged();
    showToast(
      context,
      qty > 0
          ? '已入库 ${_targets.length} 种 × ${formatQty(qty)}（$locationName）'
          : '已入库 ${_targets.length} 种（$locationName）',
    );
    setState(() {
      _targets.clear();
      _note.clear();
      _qty.clear();
      _fromScan = false;
    });
    // 连续入库：扫码进来的，确认后直接回到扫码页，扫下一包
    if (fromScan && _supportsScanner) {
      await _scan();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final canScan = _supportsScanner;

    return Scaffold(
      appBar: AppBar(title: const Text('入库')),
      body: Column(
        children: [
          Expanded(
            child: FutureBuilder<List<Location>>(
              future: _locationsFuture,
              builder: (context, snapshot) {
                final locations = snapshot.data ?? const <Location>[];
                Location? current;
                for (final location in locations) {
                  if (location.id == _locationId) {
                    current = location;
                    break;
                  }
                }
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _SectionTitle(title: '1 选择仓库'),
                    const SizedBox(height: 8),
                    Card(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: _pickLocation,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Icon(
                                Icons.inventory_2_outlined,
                                size: 20,
                                color: palette.textSub,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  current?.name ?? '未分配',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    color: palette.text,
                                  ),
                                ),
                              ),
                              Text(
                                '切换',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: palette.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _SectionTitle(title: '2 选择物料方式'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (canScan) ...[
                          Expanded(
                            child: _MethodButton(
                              icon: Icons.qr_code_scanner,
                              label: '扫码',
                              onTap: _scan,
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: _MethodButton(
                            icon: Icons.tag,
                            label: 'C 编号',
                            onTap: _queryByCode,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _MethodButton(
                            icon: Icons.add_box_outlined,
                            label: '手动新建',
                            onTap: _createManually,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _MethodButton(
                            icon: Icons.checklist,
                            label: '选已有物料',
                            onTap: _pickExisting,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_targets.isEmpty)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Center(
                            child: Text(
                              '本次入库清单为空',
                              style: TextStyle(
                                fontSize: 13,
                                color: palette.textSub,
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                      for (final item in _targets) ...[
                        MaterialCard(
                          item: item,
                          lowStock: context.read<AppState>().isLowStock(item),
                          iconKey: item.categoryIcon,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  MaterialDetailPage(materialId: item.id!),
                            ),
                          ),
                          trailing: IconButton(
                            icon: Icon(
                              Icons.close,
                              size: 18,
                              color: palette.textSub,
                            ),
                            tooltip: '移出清单',
                            onPressed: () => setState(
                              () => _targets.removeWhere(
                                (e) => e.id == item.id,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                    const SizedBox(height: 12),
                    _SectionTitle(title: '3 入库数量'),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _qty,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: '入库数量',
                        hintText: '留空 = 只归档，不改数量',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '扫立创包装二维码会自动带入本包数量（可改）；'
                      '入库时 采购量 +n、余量 +n。',
                      style: TextStyle(fontSize: 12, color: palette.textSub),
                    ),
                    const SizedBox(height: 20),
                    _SectionTitle(title: '4 备注（可选）'),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _note,
                      decoration: const InputDecoration(
                        labelText: '备注',
                        hintText: '如：到货拆包',
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.check),
              label: Text(
                _targets.isEmpty ? '确认入库' : '确认入库（${_targets.length} 种）',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

bool get _supportsScanner => Platform.isAndroid || Platform.isIOS;

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Text(
      title,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: palette.text,
      ),
    );
  }
}

class _MethodButton extends StatelessWidget {
  const _MethodButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    );
  }
}

/// 选已有物料（多选）。
class _MaterialPickerSheet extends StatefulWidget {
  const _MaterialPickerSheet();

  @override
  State<_MaterialPickerSheet> createState() => _MaterialPickerSheetState();
}

class _MaterialPickerSheetState extends State<_MaterialPickerSheet> {
  final TextEditingController _search = TextEditingController();
  final Set<int> _selected = {};
  late Future<List<MaterialItem>> _future = MaterialRepository.all();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.75,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {
                _future = _search.text.trim().isEmpty
                    ? MaterialRepository.all()
                    : MaterialRepository.search(_search.text.trim());
              }),
              decoration: const InputDecoration(
                hintText: '搜索名称 / MPN / C编号',
                prefixIcon: Icon(Icons.search, size: 18),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<MaterialItem>>(
              future: _future,
              builder: (context, snapshot) {
                final items = snapshot.data ?? const <MaterialItem>[];
                if (items.isEmpty) {
                  return Center(
                    child: Text(
                      '没有物料',
                      style: TextStyle(fontSize: 13, color: palette.textSub),
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final checked = _selected.contains(item.id);
                    return CheckboxListTile(
                      value: checked,
                      onChanged: (value) => setState(() {
                        if (value == true) {
                          _selected.add(item.id!);
                        } else {
                          _selected.remove(item.id);
                        }
                      }),
                      title: Text(item.title, maxLines: 1),
                      subtitle: Text(
                        item.summary,
                        maxLines: 1,
                        style: const TextStyle(fontSize: 12),
                      ),
                      secondary: Text(
                        formatQty(item.qtyRemaining),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: palette.text,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(_selected.toList()),
              child: Text('加入清单（${_selected.length}）'),
            ),
          ),
        ],
      ),
    );
  }
}
