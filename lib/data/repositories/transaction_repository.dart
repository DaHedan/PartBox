import 'package:sqflite/sqflite.dart';

import '../app_database.dart';
import '../models.dart';

/// 库存流水数据访问。
class TransactionRepository {
  static Database get _db => AppDatabase.instance.db;

  static Future<List<StockTransaction>> byMaterial(int materialId) async {
    final rows = await _db.query(
      'transactions',
      where: 'material_id = ?',
      whereArgs: [materialId],
      orderBy: 'created_at DESC, id DESC',
    );
    return rows.map(StockTransaction.fromMap).toList();
  }

  static Future<int> insert(StockTransaction tx) =>
      _db.insert('transactions', tx.toMap()..remove('id'));

  static Future<int> count() async {
    final rows = await _db.rawQuery('SELECT COUNT(*) AS c FROM transactions');
    return (rows.first['c'] as num).toInt();
  }
}
