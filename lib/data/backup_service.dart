import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'app_database.dart';
import 'repositories/category_repository.dart';
import 'repositories/material_repository.dart';

/// 备份与恢复（JSON 全量 / CSV 物料清单）。
class BackupService {
  const BackupService._();

  static const String appTag = 'PartBox';
  static const int formatVersion = 1;

  /// 恢复时按此顺序清空，避免外键顺序问题。
  static const List<String> _tables = [
    'transactions',
    'bom_items',
    'weld_progress',
    'bom_projects',
    'materials',
    'categories',
    'locations',
    'category_param_templates',
    'settings',
  ];

  /// 导出时的排序列。settings 的主键是 `key`、没有 `id` 列，
  /// 按 `id` 排序会直接抛 `no such column: id` 让整个导出失败。
  static const Map<String, String> _orderBy = {'settings': 'key'};

  static Future<String> exportJson() async {
    final db = AppDatabase.instance.db;
    final data = <String, dynamic>{
      'app': appTag,
      'formatVersion': formatVersion,
      'exportedAt': DateTime.now().toIso8601String(),
    };
    for (final table in _tables) {
      data[table] = await db.query(table, orderBy: _orderBy[table] ?? 'id');
    }
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  /// 导入恢复：覆盖当前全部数据。返回各表导入条数汇总。
  static Future<BackupSummary> importJson(String content) async {
    final Object? decoded = jsonDecode(content);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('备份文件格式不正确（不是 JSON 对象）');
    }
    if (decoded['formatVersion'] == null) {
      throw const FormatException('缺少 formatVersion 字段，可能不是 PartBox 备份文件');
    }

    final counts = <String, int>{};
    await AppDatabase.instance.db.transaction((txn) async {
      for (final table in _tables.reversed) {
        await txn.delete(table);
      }
      for (final table in _tables) {
        final rows = decoded[table];
        if (rows is! List) continue;
        var inserted = 0;
        for (final row in rows) {
          if (row is! Map) continue;
          await txn.insert(
            table,
            row.map((k, v) => MapEntry(k.toString(), v)),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          inserted++;
        }
        counts[table] = inserted;
      }
    });
    return BackupSummary(counts);
  }

  /// 物料清单 CSV（UTF-8 BOM，Excel 可直接打开）。
  static Future<String> exportCsv() async {
    final materials = await MaterialRepository.all();
    final categoryNames = await CategoryRepository.idFullNameMap();

    final buffer = StringBuffer('\uFEFF');
    buffer.writeln(
      [
        '名称',
        'MPN',
        'C编号',
        '类别',
        '封装',
        '品牌',
        '参数',
        '单位',
        '仓库',
        '采购量',
        '消耗量',
        '余量',
        '低库存阈值',
        '单价',
        '备注',
        '创建时间',
        '更新时间',
      ].map(_csvCell).join(','),
    );

    for (final item in materials) {
      final params = item.params.map((e) => '${e.k}:${e.v}').join(' ');
      buffer.writeln(
        [
          item.name,
          item.mpn ?? '',
          item.lcscCode ?? '',
          categoryNames[item.categoryId] ?? '',
          item.package ?? '',
          item.brand ?? '',
          params,
          item.unit,
          item.locationName ?? '',
          _num(item.qtyPurchased),
          _num(item.qtyUsed),
          _num(item.qtyRemaining),
          item.lowStockThreshold == null ? '' : _num(item.lowStockThreshold!),
          item.unitPrice == null ? '' : _num(item.unitPrice!),
          item.note ?? '',
          item.createdAt.toLocal().toString(),
          item.updatedAt.toLocal().toString(),
        ].map(_csvCell).join(','),
      );
    }
    return buffer.toString();
  }

  static String _num(double value) =>
      value == value.roundToDouble() ? value.toInt().toString() : value.toString();

  static String _csvCell(Object? value) {
    final text = value?.toString() ?? '';
    if (text.contains(',') || text.contains('"') || text.contains('\n')) {
      return '"${text.replaceAll('"', '""')}"';
    }
    return text;
  }
}

class BackupSummary {
  const BackupSummary(this.counts);

  final Map<String, int> counts;

  int get materialCount => counts['materials'] ?? 0;

  int get categoryCount => counts['categories'] ?? 0;

  int get locationCount => counts['locations'] ?? 0;
}
