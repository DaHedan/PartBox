import 'package:sqflite/sqflite.dart';

import '../app_database.dart';
import '../models.dart';
import '../seed_data.dart';

/// 物料数据访问。
class MaterialRepository {
  static Database get _db => AppDatabase.instance.db;

  static const String _select = '''
    SELECT m.*, c.name AS category_name, c.icon AS category_icon, l.name AS location_name
    FROM materials m
    LEFT JOIN categories c ON c.id = m.subcategory_id
    LEFT JOIN locations l ON l.id = m.location_id
  ''';

  static Future<List<MaterialItem>> _query({
    String? where,
    List<Object?>? args,
  }) async {
    final sql = StringBuffer(_select);
    if (where != null && where.isNotEmpty) sql.write(' WHERE $where');
    sql.write(' ORDER BY m.updated_at DESC, m.id DESC');
    final rows = await _db.rawQuery(sql.toString(), args);
    return rows.map(MaterialItem.fromMap).toList();
  }

  static Future<List<MaterialItem>> all() => _query();

  /// 某大类下全部物料（含子类；"未分类"大类含未归类物料）。
  static Future<List<MaterialItem>> byTopCategory(int topId) {
    if (topId == kUncategorizedCategoryId) {
      return _query(
        where: '(m.subcategory_id = ? OR m.subcategory_id IS NULL)',
        args: [topId],
      );
    }
    return _query(
      where:
          '(m.subcategory_id = ? OR m.subcategory_id IN (SELECT id FROM categories WHERE parent_id = ?))',
      args: [topId, topId],
    );
  }

  static Future<List<MaterialItem>> byLocation(int locationId) {
    if (locationId == kUnassignedLocationId) {
      return _query(
        where: '(m.location_id = ? OR m.location_id IS NULL)',
        args: [locationId],
      );
    }
    return _query(where: 'm.location_id = ?', args: [locationId]);
  }

  static Future<List<MaterialItem>> search(String keyword) {
    final k = '%${keyword.trim()}%';
    return _query(
      where:
          '(m.name LIKE ? OR m.mpn LIKE ? OR m.lcsc_code LIKE ? OR m.package LIKE ? OR m.brand LIKE ? OR m.note LIKE ?)',
      args: [k, k, k, k, k, k],
    );
  }

  static Future<MaterialItem?> byId(int id) async {
    final rows = await _db.rawQuery('$_select WHERE m.id = ?', [id]);
    if (rows.isEmpty) return null;
    return MaterialItem.fromMap(rows.first);
  }

  static Future<MaterialItem?> byLcscCode(String code) async {
    final rows = await _db.rawQuery(
      '$_select WHERE m.lcsc_code = ? LIMIT 1',
      [code.trim().toUpperCase()],
    );
    if (rows.isEmpty) return null;
    return MaterialItem.fromMap(rows.first);
  }

  static Future<int> insert(MaterialItem item) async {
    final map = item.toMap()..remove('id');
    return _db.insert('materials', map);
  }

  static Future<void> update(MaterialItem item) async {
    final map = item.toMap()..remove('id');
    await _db.update(
      'materials',
      map,
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  static Future<void> delete(int id) async {
    await _db.transaction((txn) async {
      await txn.delete(
        'transactions',
        where: 'material_id = ?',
        whereArgs: [id],
      );
      await txn.delete('materials', where: 'id = ?', whereArgs: [id]);
    });
  }

  static Future<int> count() async {
    final rows = await _db.rawQuery('SELECT COUNT(*) AS c FROM materials');
    return (rows.first['c'] as num).toInt();
  }

  static Future<double> totalRemaining() async {
    final rows = await _db.rawQuery(
      'SELECT COALESCE(SUM(qty_remaining), 0) AS s FROM materials',
    );
    return (rows.first['s'] as num).toDouble();
  }

  static Future<int> lowStockCount(double globalThreshold) async {
    final rows = await _db.rawQuery(
      '''
      SELECT COUNT(*) AS c FROM materials
      WHERE qty_remaining <= COALESCE(low_stock_threshold, ?)
      ''',
      [globalThreshold],
    );
    return (rows.first['c'] as num).toInt();
  }
}
