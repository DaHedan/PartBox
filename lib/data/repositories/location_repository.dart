import 'package:sqflite/sqflite.dart';

import '../app_database.dart';
import '../models.dart';
import '../seed_data.dart';

/// 仓库（储存位置）数据访问。扁平结构，parent_id 仅作未来扩展预留。
class LocationRepository {
  static Database get _db => AppDatabase.instance.db;

  /// 物料归属某仓库的判定（"未分配"同时包含 location_id 为空的物料）。
  static const String _belongsTo =
      'm.location_id = l.id OR (m.location_id IS NULL AND l.id = $kUnassignedLocationId)';

  static Future<List<Location>> all({bool withStats = false}) async {
    if (!withStats) {
      final rows = await _db.query('locations', orderBy: 'sort, id');
      return rows.map(Location.fromMap).toList();
    }
    final rows = await _db.rawQuery('''
      SELECT l.*,
        (SELECT COUNT(*) FROM materials m WHERE $_belongsTo) AS material_kinds,
        (SELECT COALESCE(SUM(m.qty_remaining), 0) FROM materials m WHERE $_belongsTo) AS total_remaining
      FROM locations l
      ORDER BY l.sort, l.id
    ''');
    return rows.map(Location.fromMap).toList();
  }

  static Future<Location?> byId(int id) async {
    final rows = await _db.query(
      'locations',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Location.fromMap(rows.first);
  }

  static Future<Location?> stats(int id) async {
    final rows = await _db.rawQuery(
      '''
      SELECT l.*,
        (SELECT COUNT(*) FROM materials m WHERE $_belongsTo) AS material_kinds,
        (SELECT COALESCE(SUM(m.qty_remaining), 0) FROM materials m WHERE $_belongsTo) AS total_remaining
      FROM locations l WHERE l.id = ?
      ''',
      [id],
    );
    if (rows.isEmpty) return null;
    return Location.fromMap(rows.first);
  }

  static Future<int> insert(String name, {String? note}) async {
    final rows = await _db.rawQuery(
      'SELECT COALESCE(MAX(sort), 0) + 1 AS s FROM locations',
    );
    final sort = (rows.first['s'] as num).toInt();
    return _db.insert('locations', {
      'parent_id': null,
      'name': name,
      'note': note,
      'sort': sort,
    });
  }

  static Future<void> rename(int id, String name) async {
    await _db.update(
      'locations',
      {'name': name},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> updateNote(int id, String? note) async {
    await _db.update(
      'locations',
      {'note': note},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<int> materialCount(int id) async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM materials WHERE location_id = ?',
      [id],
    );
    return (rows.first['c'] as num).toInt();
  }

  static Future<int> kindCount() async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM materials',
    );
    return (rows.first['c'] as num).toInt();
  }

  /// 删除仓库；有物料时先迁移到"未分配"。
  static Future<void> delete(int id) async {
    if (id == kUnassignedLocationId) {
      throw StateError('内置"未分配"不可删除');
    }
    await _db.update(
      'materials',
      {'location_id': kUnassignedLocationId},
      where: 'location_id = ?',
      whereArgs: [id],
    );
    await _db.delete('locations', where: 'id = ?', whereArgs: [id]);
  }
}
