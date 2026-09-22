import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../data/repositories/category_repository.dart';
import '../data/repositories/material_repository.dart';
import '../data/repositories/transaction_repository.dart';
import '../data/stock_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/category_icon.dart';
import '../widgets/dialogs.dart';
import '../widgets/local_image.dart';
import '../widgets/qty_cards.dart';
import '../widgets/stat_card.dart';
import 'material_edit_page.dart';

/// P4 物料详情页（线框 05）。
class MaterialDetailPage extends StatefulWidget {
  const MaterialDetailPage({super.key, required this.materialId});

  final int materialId;

  @override
  State<MaterialDetailPage> createState() => _MaterialDetailPageState();
}

class _DetailData {
  const _DetailData(this.item, this.transactions, this.categoryPath);

  final MaterialItem item;
  final List<StockTransaction> transactions;
  final String categoryPath;
}

class _MaterialDetailPageState extends State<MaterialDetailPage> {
  late Future<_DetailData?> _future = _load();
  int _revision = -1;

  Future<_DetailData?> _load() async {
    final item = await MaterialRepository.byId(widget.materialId);
    if (item == null) return null;
    final transactions = await TransactionRepository.byMaterial(widget.materialId);
    final names = await CategoryRepository.idFullNameMap();
    return _DetailData(
      item,
      transactions,
      names[item.categoryId] ?? item.categoryName ?? '未分类',
    );
  }

  Future<void> _adjust(String field) async {
    final data = await _future;
    final item = data?.item;
    if (item == null || !mounted) return;
    final current = switch (field) {
      StockService.fieldPurchased => item.qtyPurchased,
      StockService.fieldUsed => item.qtyUsed,
      _ => item.qtyRemaining,
    };
    final value = await showNumberDialog(
      context,
      title: '修改${StockService.fieldLabel(field)}',
      initial: current,
      suffix: item.unit,
    );
    if (value == null) return;
    await StockService.adjustField(
      materialId: item.id!,
      field: field,
      value: value,
    );
    if (!mounted) return;
    context.read<AppState>().notifyDataChanged();
    _reload();
    showToast(
      context,
      '${StockService.fieldLabel(field)} 已改为 ${formatQty(value)}',
    );
  }

  Future<void> _consume() async {
    final data = await _future;
    final item = data?.item;
    if (item == null || !mounted) return;
    final value = await showNumberDialog(
      context,
      title: '消耗数量',
      initial: 1,
      suffix: item.unit,
      allowNegative: false,
    );
    if (value == null || value <= 0) return;
    await StockService.consume(materialId: item.id!, qty: value);
    final updated = await MaterialRepository.byId(item.id!);
    if (!mounted) return;
    context.read<AppState>().notifyDataChanged();
    _reload();
    showToast(
      context,
      '余量 −${formatQty(value)}（剩 ${formatQty(updated?.qtyRemaining ?? 0)}）',
    );
  }

  Future<void> _delete(MaterialItem item) async {
    final data = await _future;
    final txCount = data?.transactions.length ?? 0;
    if (!mounted) return;
    final ok = await showConfirmDialog(
      context,
      title: '删除物料',
      message: txCount > 0
          ? '确定删除「${item.title}」？\n该物料的 $txCount 条库存流水将一并删除。'
          : '确定删除「${item.title}」？',
      confirmText: '删除',
      danger: true,
    );
    if (!ok) return;
    await MaterialRepository.delete(item.id!);
    if (!mounted) return;
    context.read<AppState>().notifyDataChanged();
    Navigator.of(context).pop();
    showToast(context, '已删除「${item.title}」');
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _future = _load();
    });
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
        title: const Text('物料详情'),
        actions: [
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            tooltip: '消耗',
            onPressed: _consume,
          ),
        ],
      ),
      body: FutureBuilder<_DetailData?>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data;
          if (data == null) {
            return const Center(child: Text('物料不存在'));
          }
          final item = data.item;
          final lowStock = appState.isLowStock(item);

          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _HeaderCard(item: item),
                    const SizedBox(height: 12),
                    QtyCards(
                      item: item,
                      lowStock: lowStock,
                      onTapField: _adjust,
                    ),
                    const SizedBox(height: 20),
                    _SectionTitle(title: '参数'),
                    const SizedBox(height: 8),
                    StatCard(
                      rows: [
                        StatRow(label: '类别', value: data.categoryPath),
                        StatRow(label: '品牌', value: item.brand ?? ''),
                        StatRow(label: '封装/规格', value: item.package ?? ''),
                        StatRow(label: 'C 编号', value: item.lcscCode ?? ''),
                        StatRow(label: '仓库', value: item.locationName ?? '未分配'),
                        StatRow(label: '单位', value: item.unit),
                        StatRow(
                          label: '低库存阈值',
                          value: item.lowStockThreshold == null
                              ? '跟随全局（${appState.lowStockThreshold}）'
                              : formatQty(item.lowStockThreshold!),
                        ),
                        StatRow(
                          label: '单价',
                          value: item.unitPrice == null
                              ? ''
                              : '¥ ${item.unitPrice!.toStringAsFixed(4)}',
                        ),
                        for (final param in item.params)
                          StatRow(label: param.k, value: param.v),
                        if (item.note != null && item.note!.isNotEmpty)
                          StatRow(
                            label: '备注',
                            value: item.note!,
                            secondary: true,
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _SectionTitle(
                      title: '库存流水',
                      trailing: '${data.transactions.length} 条',
                    ),
                    const SizedBox(height: 8),
                    Card(
                      child: data.transactions.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(20),
                              child: Center(
                                child: Text(
                                  '暂无流水',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: palette.textSub,
                                  ),
                                ),
                              ),
                            )
                          : Column(
                              children: [
                                for (var i = 0;
                                    i < data.transactions.length;
                                    i++) ...[
                                  if (i > 0)
                                    Divider(
                                      color: palette.border,
                                      height: 1,
                                      indent: 16,
                                      endIndent: 16,
                                    ),
                                  _TxRow(tx: data.transactions[i]),
                                ],
                              ],
                            ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final changed = await Navigator.of(context).push<bool>(
                            MaterialPageRoute(
                              builder: (_) =>
                                  MaterialEditPage(materialId: item.id),
                            ),
                          );
                          if (changed == true) _reload();
                        },
                        child: const Text('修改'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: palette.danger,
                          side: BorderSide(color: palette.danger),
                        ),
                        onPressed: () => _delete(item),
                        child: const Text('删除'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.item});

  final MaterialItem item;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final fallback = CategoryIconBox(
      iconKey: item.categoryIcon,
      tintKey: item.categoryName ?? item.name,
      size: 56,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            LocalImage(
              relativePath: item.imagePath,
              width: 56,
              height: 56,
              fallback: fallback,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: palette.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${formatDateTime(item.createdAt)} 入库',
                    style: TextStyle(fontSize: 12, color: palette.textSub),
                  ),
                  if (item.name.isNotEmpty && item.name != item.title) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: palette.textSub),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: palette.text,
          ),
        ),
        const Spacer(),
        if (trailing != null)
          Text(
            trailing!,
            style: TextStyle(fontSize: 12, color: palette.textSub),
          ),
      ],
    );
  }
}

class _TxRow extends StatelessWidget {
  const _TxRow({required this.tx});

  final StockTransaction tx;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = switch (tx.type) {
      TxType.inbound => palette.success,
      TxType.outbound => palette.warning,
      _ => palette.textSub,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              TxType.label(tx.type),
              style: TextStyle(fontSize: 11, color: color),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatDateTime(tx.createdAt),
                  style: TextStyle(fontSize: 12, color: palette.textSub),
                ),
                if (tx.note != null && tx.note!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    tx.note!,
                    style: TextStyle(fontSize: 12, color: palette.textSub),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                tx.qty == 0 ? '—' : formatQtySigned(tx.qty),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  fontFeatures: kTabularFigures,
                  color: tx.qty == 0 ? palette.textSub : color,
                ),
              ),
              Text(
                '剩 ${formatQty(tx.remainingAfter)}',
                style: TextStyle(fontSize: 12, color: palette.textSub),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
