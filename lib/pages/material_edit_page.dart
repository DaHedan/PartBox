import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../data/image_store.dart';
import '../data/lcsc/lcsc_category_mapper.dart';
import '../data/lcsc/lcsc_part.dart';
import '../data/lcsc/lcsc_service.dart';
import '../data/models.dart';
import '../data/repositories/category_repository.dart';
import '../data/repositories/location_repository.dart';
import '../data/repositories/material_repository.dart';
import '../data/seed_data.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/scan_payload.dart';
import '../widgets/category_icon.dart';
import '../widgets/dialogs.dart';
import '../widgets/local_image.dart';
import 'scan_page.dart';

/// P7 添加 / 编辑物料页（手动 · C 编号查询 · 扫码）。
class MaterialEditPage extends StatefulWidget {
  const MaterialEditPage({
    super.key,
    this.materialId,
    this.initialDraft,
    this.lcscPart,
    this.presetMpn,
    this.presetLocationId,
  });

  /// 编辑模式：物料 id。
  final int? materialId;

  /// 新建模式的预填数据（来自扫码 / 上游页面）。
  final MaterialItem? initialDraft;

  /// 立创查询结果（新建时自动带出名称 / 参数 / 图片 / 分类）。
  final LcscPart? lcscPart;

  /// 扫码标签带出的 MPN（pm 字段），优先于查询结果里的 MPN。
  final String? presetMpn;

  final int? presetLocationId;

  @override
  State<MaterialEditPage> createState() => _MaterialEditPageState();
}

class _ParamRow {
  _ParamRow(String k, String v)
    : keyController = TextEditingController(text: k),
      valueController = TextEditingController(text: v);

  final TextEditingController keyController;
  final TextEditingController valueController;

  void dispose() {
    keyController.dispose();
    valueController.dispose();
  }
}

class _MaterialEditPageState extends State<MaterialEditPage> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _mpn;
  late final TextEditingController _lcsc;
  late final TextEditingController _package;
  late final TextEditingController _brand;
  late final TextEditingController _unit;
  late final TextEditingController _note;
  late final TextEditingController _unitPrice;
  late final TextEditingController _qtyPurchased;
  late final TextEditingController _qtyUsed;
  late final TextEditingController _qtyRemaining;
  late final TextEditingController _threshold;

  final List<_ParamRow> _params = [];
  int? _categoryId;
  int? _locationId;
  String? _imagePath;
  MaterialItem? _existing;
  bool _loading = true;

  List<Category> _tops = const [];
  Map<int, List<Category>> _subsByTop = const {};
  List<Location> _locations = const [];

  @override
  void initState() {
    super.initState();
    final draft = widget.initialDraft;
    _name = TextEditingController(text: draft?.name ?? '');
    _mpn = TextEditingController(text: draft?.mpn ?? '');
    _lcsc = TextEditingController(text: draft?.lcscCode ?? '');
    _package = TextEditingController(text: draft?.package ?? '');
    _brand = TextEditingController(text: draft?.brand ?? '');
    _unit = TextEditingController(text: draft?.unit ?? 'pcs');
    _note = TextEditingController(text: draft?.note ?? '');
    _unitPrice = TextEditingController();
    _qtyPurchased = TextEditingController(text: '0');
    _qtyUsed = TextEditingController(text: '0');
    _qtyRemaining = TextEditingController(text: '0');
    _threshold = TextEditingController();
    _categoryId = draft?.categoryId;
    _locationId = draft?.locationId ?? widget.presetLocationId;
    _imagePath = draft?.imagePath;
    for (final param in draft?.params ?? const <ParamEntry>[]) {
      _params.add(_ParamRow(param.k, param.v));
    }
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _mpn.dispose();
    _lcsc.dispose();
    _package.dispose();
    _brand.dispose();
    _unit.dispose();
    _note.dispose();
    _unitPrice.dispose();
    _qtyPurchased.dispose();
    _qtyUsed.dispose();
    _qtyRemaining.dispose();
    _threshold.dispose();
    for (final row in _params) {
      row.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final all = await CategoryRepository.allCategories();
    final tops = all.where((c) => c.parentId == null).toList();
    final subs = <int, List<Category>>{};
    for (final category in all) {
      if (category.parentId != null) {
        subs.putIfAbsent(category.parentId!, () => []).add(category);
      }
    }
    final locations = await LocationRepository.all();

    MaterialItem? existing;
    if (widget.materialId != null) {
      existing = await MaterialRepository.byId(widget.materialId!);
    }

    if (!mounted) return;
    setState(() {
      _tops = tops;
      _subsByTop = subs;
      _locations = locations;
      _existing = existing;
      _loading = false;
      if (existing != null) {
        _name.text = existing.name;
        _mpn.text = existing.mpn ?? '';
        _lcsc.text = existing.lcscCode ?? '';
        _package.text = existing.package ?? '';
        _brand.text = existing.brand ?? '';
        _unit.text = existing.unit;
        _note.text = existing.note ?? '';
        _unitPrice.text = existing.unitPrice == null
            ? ''
            : formatQty(existing.unitPrice!);
        _qtyPurchased.text = formatQty(existing.qtyPurchased);
        _qtyUsed.text = formatQty(existing.qtyUsed);
        _qtyRemaining.text = formatQty(existing.qtyRemaining);
        _threshold.text = existing.lowStockThreshold == null
            ? ''
            : formatQty(existing.lowStockThreshold!);
        _categoryId = existing.categoryId;
        _locationId = existing.locationId ?? kUnassignedLocationId;
        _imagePath = existing.imagePath;
        _replaceParams(existing.params);
      }
    });

    final part = widget.lcscPart;
    if (part != null) {
      await _applyPart(part);
    }
    // 扫码标签带出的 MPN（pm）优先于查询结果
    final presetMpn = widget.presetMpn;
    if (presetMpn != null && presetMpn.isNotEmpty) {
      _mpn.text = presetMpn;
    }
  }

  int? get _topId {
    if (_categoryId == null) return null;
    final category = _categoryIn(_categoryId!);
    if (category == null) return null;
    return category.parentId ?? category.id;
  }

  Category? _categoryIn(int id) {
    for (final top in _tops) {
      if (top.id == id) return top;
      for (final sub in _subsByTop[top.id] ?? const <Category>[]) {
        if (sub.id == id) return sub;
      }
    }
    return null;
  }

  Future<void> _queryLcsc({String? presetCode}) async {
    var code = presetCode ?? _lcsc.text.trim();
    if (presetCode == null) {
      final input = await showTextDialog(
        context,
        title: 'C 编号查询',
        initial: code.isEmpty ? null : code,
        hint: '如 C106248',
      );
      if (input == null) return;
      code = input;
    }
    if (!mounted) return;
    final normalized = LcscService.normalizeCode(code);
    if (normalized == null) {
      showToast(context, '未识别到 C 编号（形如 C106248）');
      return;
    }
    final appState = context.read<AppState>();
    showToast(context, '正在查询 $normalized …');
    final result = await LcscService.query(
      normalized,
      apiKey: appState.lcscApiKey,
    );
    if (!mounted) return;
    final part = result.part;
    if (part == null) {
      _lcsc.text = normalized;
      showToast(context, '查询失败，已转手动模式：${result.error ?? ''}');
      return;
    }
    await _applyPart(part);
    if (!mounted) return;
    showToast(context, '已带出「${part.mpn ?? part.name ?? ''}」（${part.source}）');
  }

  Future<void> _applyPart(LcscPart part) async {
    _lcsc.text = part.code;
    if (part.name != null && part.name!.isNotEmpty) _name.text = part.name!;
    if (part.mpn != null) _mpn.text = part.mpn!;
    if (part.brand != null) _brand.text = part.brand!;
    if (part.package != null) _package.text = part.package!;
    if (part.unitPrice != null) {
      _unitPrice.text = part.unitPrice!.toStringAsFixed(4);
    }

    final topName = LcscCategoryMapper.topCategoryOf(
      part.parentCategoryName,
      part.categoryName,
    );
    final subName = LcscCategoryMapper.subCategoryOf(part.categoryName);
    Category? top;
    for (final candidate in _tops) {
      if (candidate.name == topName) {
        top = candidate;
        break;
      }
    }
    Category? sub;
    if (top != null && subName != null) {
      for (final candidate in _subsByTop[top.id] ?? const <Category>[]) {
        if (candidate.name == subName) {
          sub = candidate;
          break;
        }
      }
    }

    setState(() {
      _categoryId = sub?.id ?? top?.id;
      if (part.params.isNotEmpty) {
        _replaceParams(part.params);
      }
    });

    final imageUrl = part.firstImageUrl;
    if (imageUrl != null) {
      final saved = await ImageStore.saveFromUrl(imageUrl, 'lcsc_${part.code}');
      if (saved != null && mounted) {
        setState(() => _imagePath = saved);
      }
    }
  }

  Future<void> _scan() async {
    final hits = await Navigator.of(context).push<List<ScanPayload>>(
      MaterialPageRoute(builder: (_) => const ScanPage()),
    );
    if (hits == null || hits.isEmpty) return;
    final hit = hits.first;
    final code = hit.code;
    if (code == null) return;
    await _queryLcsc(presetCode: code);
    if (!mounted) return;
    // 标签带出的 MPN 覆盖查询结果
    final mpn = hit.mpn;
    if (mpn != null && mpn.isNotEmpty) {
      setState(() => _mpn.text = mpn);
    }
  }

  Future<void> _pickImage() async {
    final isMobile = Platform.isAndroid || Platform.isIOS;
    if (isMobile) {
      final action = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('拍照'),
                onTap: () => Navigator.of(context).pop('camera'),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('从相册选择'),
                onTap: () => Navigator.of(context).pop('gallery'),
              ),
              if (_imagePath != null)
                ListTile(
                  leading: Icon(
                    Icons.delete_outline,
                    color: context.palette.danger,
                  ),
                  title: Text(
                    '移除图片',
                    style: TextStyle(color: context.palette.danger),
                  ),
                  onTap: () => Navigator.of(context).pop('remove'),
                ),
            ],
          ),
        ),
      );
      if (action == null) return;
      if (action == 'remove') {
        final old = _imagePath;
        setState(() => _imagePath = null);
        await ImageStore.delete(old);
        return;
      }
      final picked = await ImagePicker().pickImage(
        source: action == 'camera' ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 1400,
        imageQuality: 85,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final saved = await ImageStore.saveBytes(
        bytes,
        'mat_${DateTime.now().millisecondsSinceEpoch}',
      );
      if (saved != null && mounted) setState(() => _imagePath = saved);
      return;
    }

    final file = await FilePicker.pickFile(
      dialogTitle: '选择物料图片',
      type: FileType.image,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return;
    final saved = await ImageStore.saveBytes(
      bytes,
      'mat_${DateTime.now().millisecondsSinceEpoch}',
    );
    if (saved != null && mounted) setState(() => _imagePath = saved);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final now = DateTime.now();
    final params = <ParamEntry>[];
    for (final row in _params) {
      final key = row.keyController.text.trim();
      final value = row.valueController.text.trim();
      if (key.isEmpty || value.isEmpty) continue;
      params.add(ParamEntry(key, value));
    }
    final item = MaterialItem(
      id: _existing?.id,
      name: _name.text.trim(),
      mpn: _emptyToNull(_mpn.text),
      lcscCode: _emptyToNull(_lcsc.text)?.toUpperCase(),
      categoryId: _categoryId,
      package: _emptyToNull(_package.text),
      brand: _emptyToNull(_brand.text),
      params: params,
      imagePath: _imagePath,
      unit: _unit.text.trim().isEmpty ? 'pcs' : _unit.text.trim(),
      locationId: _locationId,
      qtyPurchased: double.tryParse(_qtyPurchased.text.trim()) ?? 0,
      qtyUsed: double.tryParse(_qtyUsed.text.trim()) ?? 0,
      qtyRemaining: double.tryParse(_qtyRemaining.text.trim()) ?? 0,
      lowStockThreshold: double.tryParse(_threshold.text.trim()),
      unitPrice: double.tryParse(_unitPrice.text.trim()),
      note: _emptyToNull(_note.text),
      createdAt: _existing?.createdAt ?? now,
      updatedAt: now,
      lastTransactionAt: _existing?.lastTransactionAt,
    );

    final int id;
    if (_existing == null) {
      id = await MaterialRepository.insert(item);
    } else {
      await MaterialRepository.update(item);
      id = _existing!.id!;
    }
    if (!mounted) return;
    final appState = context.read<AppState>();
    appState.notifyDataChanged();
    if (_locationId != null) {
      await appState.setLastLocationId(_locationId!);
    }
    if (!mounted) return;
    showToast(context, _existing == null ? '已添加物料' : '已保存修改');
    Navigator.of(context).pop(id);
  }

  static String? _emptyToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static double _num(TextEditingController controller) =>
      double.tryParse(controller.text.trim()) ?? 0;

  /// 采购量 / 消耗量变动 → 余量 = 采购量 − 消耗量。
  void _syncRemaining() {
    _qtyRemaining.text = formatQty(_num(_qtyPurchased) - _num(_qtyUsed));
  }

  /// 余量变动 → 消耗量 = 采购量 − 余量（采购量保持不变）。
  void _syncUsed() {
    _qtyUsed.text = formatQty(_num(_qtyPurchased) - _num(_qtyRemaining));
  }

  /// 替换参数行：旧行的控制器等其输入框卸载（下一帧）后再释放，
  /// 避免输入框仍挂载时被 dispose 导致构建期异常。
  void _replaceParams(Iterable<ParamEntry> params) {
    final old = List<_ParamRow>.from(_params);
    _params
      ..clear()
      ..addAll(params.map((p) => _ParamRow(p.k, p.v)));
    if (old.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final row in old) {
        row.dispose();
      }
    });
  }

  /// 删除单行参数（同样延后释放控制器）。
  void _removeParamAt(int index) {
    final row = _params[index];
    setState(() => _params.removeAt(index));
    WidgetsBinding.instance.addPostFrameCallback((_) => row.dispose());
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final canScan = Platform.isAndroid || Platform.isIOS;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.materialId == null ? '添加物料' : '编辑物料'),
        actions: [
          TextButton(
            onPressed: _loading ? null : _save,
            child: const Text('保存'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _queryLcsc(),
                          icon: const Icon(Icons.cloud_download_outlined),
                          label: const Text('C 编号查询'),
                        ),
                      ),
                      if (canScan) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _scan,
                            icon: const Icon(Icons.qr_code_scanner),
                            label: const Text('扫码导入'),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  _imagePicker(),
                  const SizedBox(height: 16),
                  _field(_name, '名称 *', hint: '如：贴片电容 1uF 16V', required: true),
                  _field(_mpn, 'MPN 原厂型号', hint: '如 CC0603KRX7R7BB105'),
                  _field(_lcsc, 'C 编号', hint: '如 C106248'),
                  _categoryField(),
                  _field(_package, '封装/规格', hint: '如 0603'),
                  _field(_brand, '品牌', hint: '如 YAGO'),
                  _field(_unit, '单位', hint: '默认 pcs'),
                  _locationField(),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _numberField(
                          _qtyPurchased,
                          '采购量',
                          onChanged: (_) => _syncRemaining(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _numberField(
                          _qtyUsed,
                          '消耗量',
                          onChanged: (_) => _syncRemaining(),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: _numberField(
                          _qtyRemaining,
                          '余量',
                          onChanged: (_) => _syncUsed(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _numberField(
                          _threshold,
                          '低库存阈值',
                          hint: '留空=全局',
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      '三量联动：余量 = 采购量 − 消耗量，改动任意一项自动推算其余。',
                      style: TextStyle(fontSize: 12, color: palette.textSub),
                    ),
                  ),
                  _numberField(_unitPrice, '单价', decimal: true),
                  _field(_note, '备注', maxLines: 2),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(
                        '参数',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: palette.text,
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () => setState(() {
                          _params.add(_ParamRow('', ''));
                        }),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('添加参数'),
                      ),
                    ],
                  ),
                  for (var i = 0; i < _params.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: _params[i].keyController,
                              decoration: const InputDecoration(
                                hintText: '参数名',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 4,
                            child: TextField(
                              controller: _params[i].valueController,
                              decoration: const InputDecoration(
                                hintText: '参数值',
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.close,
                              size: 18,
                              color: palette.textSub,
                            ),
                            onPressed: () => _removeParamAt(i),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _imagePicker() {
    return Row(
      children: [
        LocalImage(
          relativePath: _imagePath,
          width: 72,
          height: 72,
          fallback: CategoryIconBox(
            iconKey: _topId == null ? null : _categoryIn(_topId!)?.icon,
            tintKey: _name.text.isEmpty ? '元件' : _name.text,
            size: 72,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _pickImage,
            icon: const Icon(Icons.image_outlined),
            label: Text(_imagePath == null ? '添加图片' : '更换图片'),
          ),
        ),
      ],
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    bool required = false,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(labelText: label, hintText: hint),
        validator: required
            ? (value) =>
                  (value == null || value.trim().isEmpty) ? '请输入$label' : null
            : null,
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _numberField(
    TextEditingController controller,
    String label, {
    String? hint,
    bool decimal = false,
    void Function(String value)? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.numberWithOptions(
          decimal: decimal,
          signed: false,
        ),
        inputFormatters: [
          FilteringTextInputFormatter.allow(
            decimal ? RegExp(r'[0-9\.]') : RegExp(r'[0-9\.\-]'),
          ),
        ],
        decoration: InputDecoration(labelText: label, hintText: hint),
        onChanged: onChanged,
      ),
    );
  }

  Widget _categoryField() {
    final topId = _topId;
    final subs = _subsByTop[topId] ?? const <Category>[];
    final items = <DropdownMenuItem<int>>[
      if (topId != null)
        const DropdownMenuItem(value: null, child: Text('未分类')),
      for (final sub in subs)
        DropdownMenuItem(value: sub.id, child: Text(sub.name)),
    ];
    final subValue = (topId != null && _categoryId == topId)
        ? null
        : (subs.any((s) => s.id == _categoryId) ? _categoryId : null);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DropdownButtonFormField<int>(
            initialValue: topId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '大类'),
            hint: const Text('请选择大类'),
            items: [
              for (final top in _tops)
                DropdownMenuItem(value: top.id, child: Text(top.name)),
            ],
            onChanged: (value) => setState(() => _categoryId = value),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DropdownButtonFormField<int>(
            key: ValueKey('sub-${topId ?? -1}'),
            initialValue: subValue,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '子类'),
            hint: Text(subs.isEmpty ? '该大类未设子类' : '未分类'),
            items: items,
            onChanged: (value) => setState(() {
              _categoryId = value ?? topId;
            }),
          ),
        ),
      ],
    );
  }

  Widget _locationField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<int>(
        initialValue: _locationId,
        isExpanded: true,
        decoration: const InputDecoration(labelText: '仓库'),
        hint: const Text('未分配'),
        items: [
          for (final location in _locations)
            DropdownMenuItem(value: location.id, child: Text(location.name)),
        ],
        onChanged: (value) => setState(() => _locationId = value),
      ),
    );
  }
}
