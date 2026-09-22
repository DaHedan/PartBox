import 'package:sqflite/sqflite.dart';

import 'app_database.dart';
import 'models.dart';

/// 库存变动（入库 / 消耗 / 手动校正），保证物料数量与流水在同一事务内落库。
class StockService {
  static Database get _db => AppDatabase.instance.db;

  static Future<(double, double, double)> _readQty(
    DatabaseExecutor txn,
    int materialId,
  ) async {
    final rows = await txn.query(
      'materials',
      columns: ['qty_purchased', 'qty_used', 'qty_remaining'],
      where: 'id = ?',
      whereArgs: [materialId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('物料不存在：$materialId');
    final row = rows.first;
    return (
      ((row['qty_purchased'] ?? 0) as num).toDouble(),
      ((row['qty_used'] ?? 0) as num).toDouble(),
      ((row['qty_remaining'] ?? 0) as num).toDouble(),
    );
  }

  /// 入库：把物料归到所选仓库并记一条入库流水。
  ///
  /// [qty] > 0 时同时 采购量 +qty、余量 +qty（等式 余量 = 采购量 − 消耗量 仍成立）；
  /// [qty] 为 0 表示只归档、不改数量。
  static Future<void> inbound({
    required int materialId,
    required int locationId,
    double qty = 0,
    String? note,
  }) async {
    await _db.transaction((txn) async {
      final (purchased, _, remaining) = await _readQty(txn, materialId);
      final newPurchased = purchased + qty;
      final newRemaining = remaining + qty;
      final now = DateTime.now().millisecondsSinceEpoch;
      await txn.update(
        'materials',
        {
          'location_id': locationId,
          if (qty != 0) 'qty_purchased': newPurchased,
          if (qty != 0) 'qty_remaining': newRemaining,
          'updated_at': now,
          'last_transaction_at': now,
        },
        where: 'id = ?',
        whereArgs: [materialId],
      );
      await txn.insert('transactions', {
        'material_id': materialId,
        'type': TxType.inbound,
        'qty': qty,
        'remaining_after': newRemaining,
        'note': note,
        'created_at': now,
      });
    });
  }

  /// 消耗：消耗量 +n、余量 −n（可为负，视为欠料）。
  static Future<void> consume({
    required int materialId,
    required double qty,
    String? note,
  }) async {
    if (qty <= 0) throw StateError('消耗数量需大于 0');
    await _db.transaction((txn) async {
      final (_, used, remaining) = await _readQty(txn, materialId);
      final newUsed = used + qty;
      final newRemaining = remaining - qty;
      final now = DateTime.now().millisecondsSinceEpoch;
      await txn.update(
        'materials',
        {
          'qty_used': newUsed,
          'qty_remaining': newRemaining,
          'updated_at': now,
          'last_transaction_at': now,
        },
        where: 'id = ?',
        whereArgs: [materialId],
      );
      await txn.insert('transactions', {
        'material_id': materialId,
        'type': TxType.outbound,
        'qty': -qty,
        'remaining_after': newRemaining,
        'note': note,
        'created_at': now,
      });
    });
  }

  static const String fieldPurchased = 'purchased';
  static const String fieldUsed = 'used';
  static const String fieldRemaining = 'remaining';

  static String fieldLabel(String field) {
    switch (field) {
      case fieldPurchased:
        return '采购量';
      case fieldUsed:
        return '消耗量';
      default:
        return '余量';
    }
  }

  /// 手动校正数量，保持三量自洽：**余量 = 采购量 − 消耗量**。
  ///
  /// - 改采购量 / 消耗量 → 由另两个字段算出余量；
  /// - 改余量 → 保持采购量不变，反推消耗量（消耗量 = 采购量 − 余量）。
  ///
  /// 写入后生成一条"手动校正"流水，数量为余量的变化量。
  static Future<void> adjustField({
    required int materialId,
    required String field,
    required double value,
    String? note,
  }) async {
    await _db.transaction((txn) async {
      final (oldPurchased, oldUsed, oldRemaining) = await _readQty(
        txn,
        materialId,
      );

      var newPurchased = oldPurchased;
      var newUsed = oldUsed;
      double oldValue;
      switch (field) {
        case fieldPurchased:
          oldValue = oldPurchased;
          newPurchased = value;
        case fieldUsed:
          oldValue = oldUsed;
          newUsed = value;
        default:
          oldValue = oldRemaining;
          newUsed = oldPurchased - value;
      }
      final newRemaining = newPurchased - newUsed;

      final now = DateTime.now().millisecondsSinceEpoch;
      await txn.update(
        'materials',
        {
          'qty_purchased': newPurchased,
          'qty_used': newUsed,
          'qty_remaining': newRemaining,
          'updated_at': now,
          'last_transaction_at': now,
        },
        where: 'id = ?',
        whereArgs: [materialId],
      );
      await txn.insert('transactions', {
        'material_id': materialId,
        'type': TxType.adjust,
        'qty': newRemaining - oldRemaining,
        'remaining_after': newRemaining,
        'note':
            note ??
            '${fieldLabel(field)} ${_trim(oldValue)} → ${_trim(value)}',
        'created_at': now,
      });
    });
  }

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}
