import 'package:sqflite/sqflite.dart';

import '../app_database.dart';
import '../models.dart';
import '../seed_data.dart';

/// 分类（大类 / 子类）数据访问。
class CategoryRepository {
  static Database get _db => AppDatabase.instance.db;

  /// 大类列表（含内置"未分类"），带该大类下物料种数。
  static Future<List<Category>> topCategories() async {
    final rows = await _db.rawQuery('''
      SELECT c.*,
        (SELECT COUNT(*) FROM materials m
           WHERE m.subcategory_id = c.id
              OR m.subcategory_id IN (SELECT s.id FROM categories s WHERE s.parent_id = c.id)
              OR (m.subcategory_id IS NULL AND c.id = $kUncategorizedCategoryId)
        ) AS material_count
      FROM categories c
      WHERE c.parent_id IS NULL
      ORDER BY c.sort, c.id
    ''');
    return rows.map(Category.fromMap).toList();
  }

  static Future<List<Category>> subcategories(int parentId) async {
    final rows = await _db.query(
      'categories',
      where: 'parent_id = ?',
      whereArgs: [parentId],
      orderBy: 'sort, id',
    );
    return rows.map(Category.fromMap).toList();
  }

  /// 子类列表（带该子类下物料种数）。
  static Future<List<Category>> subcategoriesWithCount(int parentId) async {
    final rows = await _db.rawQuery(
      '''
      SELECT c.*,
        (SELECT COUNT(*) FROM materials m WHERE m.subcategory_id = c.id) AS material_count
      FROM categories c
      WHERE c.parent_id = ?
      ORDER BY c.sort, c.id
      ''',
      [parentId],
    );
    return rows.map(Category.fromMap).toList();
  }

  static Future<List<Category>> allCategories() async {
    final rows = await _db.query('categories', orderBy: 'sort, id');
    return rows.map(Category.fromMap).toList();
  }

  static Future<Category?> byId(int id) async {
    final rows = await _db.query(
      'categories',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Category.fromMap(rows.first);
  }

  /// 返回该分类所属大类 id（子类返回其父；大类返回自身）。
  static Future<int?> topIdOf(int categoryId) async {
    final c = await byId(categoryId);
    if (c == null) return null;
    return c.parentId ?? c.id;
  }

  static Future<int> insertTop(String name, String? icon) async {
    final rows = await _db.rawQuery(
      'SELECT COALESCE(MAX(sort), 0) + 1 AS s FROM categories WHERE parent_id IS NULL',
    );
    final sort = (rows.first['s'] as num).toInt();
    return _db.insert('categories', {
      'parent_id': null,
      'name': name,
      'icon': icon,
      'sort': sort,
      'builtin': 0,
    });
  }

  static Future<int> insertSub(int parentId, String name) async {
    final rows = await _db.rawQuery(
      'SELECT COALESCE(MAX(sort), -1) + 1 AS s FROM categories WHERE parent_id = ?',
      [parentId],
    );
    final sort = (rows.first['s'] as num).toInt();
    return _db.insert('categories', {
      'parent_id': parentId,
      'name': name,
      'icon': null,
      'sort': sort,
      'builtin': 0,
    });
  }

  static Future<void> update(Category category) async {
    await _db.update(
      'categories',
      {'name': category.name, 'icon': category.icon},
      where: 'id = ?',
      whereArgs: [category.id],
    );
  }

  static Future<void> moveSort(int id, int delta) async {
    final rows = await _db.query(
      'categories',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final category = Category.fromMap(rows.first);
    final siblings = category.parentId == null
        ? await topCategories()
        : await subcategories(category.parentId!);
    final index = siblings.indexWhere((e) => e.id == id);
    final target = index + delta;
    if (index < 0 || target < 0 || target >= siblings.length) return;
    final other = siblings[target];
    await _db.update(
      'categories',
      {'sort': other.sort},
      where: 'id = ?',
      whereArgs: [id],
    );
    await _db.update(
      'categories',
      {'sort': category.sort},
      where: 'id = ?',
      whereArgs: [other.id],
    );
  }

  /// 该分类（含子类）下的物料种数，用于删除约束。
  static Future<int> materialCountUnder(int categoryId) async {
    final rows = await _db.rawQuery(
      '''
      SELECT COUNT(*) AS c FROM materials
      WHERE subcategory_id = ?
         OR subcategory_id IN (SELECT id FROM categories WHERE parent_id = ?)
      ''',
      [categoryId, categoryId],
    );
    return (rows.first['c'] as num).toInt();
  }

  /// 删除分类；内置分类（立创预置 23 类及"未分类"）不可删除，
  /// 分类下存在物料时抛出 [StateError]。
  static Future<void> delete(int id) async {
    final category = await byId(id);
    if (category == null) return;
    if (category.builtin) {
      throw StateError('内置分类不可删除');
    }
    final count = await materialCountUnder(id);
    if (count > 0) {
      throw StateError('该分类下还有 $count 种物料，请先迁移物料');
    }
    await _db.delete('categories', where: 'parent_id = ?', whereArgs: [id]);
    await _db.delete('categories', where: 'id = ?', whereArgs: [id]);
  }

  /// 分类 id → 名称。
  static Future<Map<int, String>> idNameMap() async {
    final rows = await _db.query('categories', columns: ['id', 'name']);
    return {
      for (final row in rows) (row['id'] as num).toInt(): row['name'] as String,
    };
  }

  /// 分类 id → 完整路径（`大类 / 子类`）。
  static Future<Map<int, String>> idFullNameMap() async {
    final rows = await _db.query(
      'categories',
      columns: ['id', 'parent_id', 'name'],
    );
    final names = {
      for (final row in rows)
        (row['id'] as num).toInt(): row['name'] as String,
    };
    return {
      for (final row in rows)
        (row['id'] as num).toInt(): row['parent_id'] == null
            ? names[(row['id'] as num).toInt()]!
            : '${names[row['parent_id'] as int] ?? ''} / ${names[(row['id'] as num).toInt()]}',
    };
  }
}
