import 'package:sqflite/sqflite.dart';

import '../app_database.dart';
import '../models.dart';

/// F10 BOM 工程与条目的数据访问。
class BomRepository {
  static Database get _db => AppDatabase.instance.db;

  static Future<List<BomProject>> projects() async {
    final rows = await _db.rawQuery('''
      SELECT p.*,
        (SELECT COUNT(*) FROM bom_items i WHERE i.bom_project_id = p.id) AS item_count,
        (SELECT COUNT(*) FROM bom_items i WHERE i.bom_project_id = p.id AND i.checked = 1) AS checked_count
      FROM bom_projects p
      ORDER BY p.updated_at DESC, p.id DESC
    ''');
    return rows.map(BomProject.fromMap).toList();
  }

  static Future<BomProject?> byId(int id) async {
    final rows = await _db.rawQuery('''
      SELECT p.*,
        (SELECT COUNT(*) FROM bom_items i WHERE i.bom_project_id = p.id) AS item_count,
        (SELECT COUNT(*) FROM bom_items i WHERE i.bom_project_id = p.id AND i.checked = 1) AS checked_count
      FROM bom_projects p WHERE p.id = ?
    ''', [id]);
    if (rows.isEmpty) return null;
    return BomProject.fromMap(rows.first);
  }

  static Future<int> insertProject(BomProject project) =>
      _db.insert('bom_projects', project.toMap()..remove('id'));

  static Future<void> deleteProject(int id) async {
    await _db.transaction((txn) async {
      await txn.delete('bom_items', where: 'bom_project_id = ?', whereArgs: [id]);
      await txn.delete('bom_projects', where: 'id = ?', whereArgs: [id]);
    });
  }

  static Future<void> touchProject(int id) async {
    await _db.update(
      'bom_projects',
      {'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<List<BomItem>> items(int projectId) async {
    final rows = await _db.query(
      'bom_items',
      where: 'bom_project_id = ?',
      whereArgs: [projectId],
      orderBy: 'sort ASC, id ASC',
    );
    return rows.map(BomItem.fromMap).toList();
  }

  /// 批量写入条目（导入时一次落库），返回带 id 的条目。
  static Future<List<BomItem>> insertItems(List<BomItem> items) async {
    final result = <BomItem>[];
    await _db.transaction((txn) async {
      for (final item in items) {
        final id = await txn.insert(
          'bom_items',
          item.toMap()..remove('id'),
        );
        result.add(item.copyWith(id: id));
      }
    });
    return result;
  }

  /// 更新比对结果与勾选状态。
  static Future<void> updateItem(
    int itemId, {
    String? matchStatus,
    int? matchedMaterialId,
    bool clearMatched = false,
    bool? checked,
  }) async {
    final values = <String, Object?>{};
    if (matchStatus != null) values['match_status'] = matchStatus;
    if (clearMatched) {
      values['matched_material_id'] = null;
    } else if (matchedMaterialId != null) {
      values['matched_material_id'] = matchedMaterialId;
    }
    if (checked != null) values['checked'] = checked ? 1 : 0;
    if (values.isEmpty) return;
    await _db.update('bom_items', values, where: 'id = ?', whereArgs: [itemId]);
  }

  /// 一次写回多行的比对结果（打开工程重新比对后同步）。
  static Future<void> updateMatches(List<BomItem> items) async {
    final batch = _db.batch();
    for (final item in items) {
      final id = item.id;
      if (id == null) continue;
      batch.update(
        'bom_items',
        {
          'match_status': item.matchStatus,
          'matched_material_id': item.matchedMaterialId,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    await batch.commit(noResult: true);
  }
}
