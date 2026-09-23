import 'package:sqflite/sqflite.dart';

import '../app_database.dart';

/// F11.7：单个位号的焊接进度。
///
/// iBOM 自己**不持久化**「已焊接」勾选（localStorage / IndexedDB 里都没有），
/// 刷新即丢；所以进度按位号存在 PartBox 侧，重开时回放。
class WeldProgress {
  const WeldProgress({
    required this.designator,
    this.bomItemId,
    this.welded = false,
    this.consumeCount = 0,
    this.lossCount = 0,
    this.updatedAt,
  });

  final String designator;
  final int? bomItemId;

  /// 已焊接。
  final bool welded;

  /// 「焊好了」次数。
  final int consumeCount;

  /// 「掉了」次数。
  final int lossCount;

  final DateTime? updatedAt;

  factory WeldProgress.fromMap(Map<String, Object?> map) => WeldProgress(
    designator: (map['designator'] ?? '') as String,
    bomItemId: (map['bom_item_id'] as num?)?.toInt(),
    welded: ((map['welded'] ?? 0) as num).toInt() == 1,
    consumeCount: ((map['consume_count'] ?? 0) as num).toInt(),
    lossCount: ((map['loss_count'] ?? 0) as num).toInt(),
    updatedAt: map['updated_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            (map['updated_at'] as num).toInt(),
          ),
  );
}

/// `weld_progress` 的数据访问。
class WeldRepository {
  static Database get _db => AppDatabase.instance.db;

  /// 某工程的进度表：位号 → 进度。
  static Future<Map<String, WeldProgress>> byProject(int projectId) async {
    final rows = await _db.query(
      'weld_progress',
      where: 'bom_project_id = ? AND designator IS NOT NULL',
      whereArgs: [projectId],
    );
    return {
      for (final row in rows)
        (row['designator'] as String): WeldProgress.fromMap(row),
    };
  }

  static Future<WeldProgress?> byDesignator(
    int projectId,
    String designator,
  ) async {
    final rows = await _db.query(
      'weld_progress',
      where: 'bom_project_id = ? AND designator = ?',
      whereArgs: [projectId, designator],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return WeldProgress.fromMap(rows.first);
  }

  /// 已焊接的位号（重开 iBOM 时注入回放）。
  static Future<List<String>> weldedDesignators(int projectId) async {
    final rows = await _db.query(
      'weld_progress',
      columns: ['designator'],
      where: 'bom_project_id = ? AND welded = 1 AND designator IS NOT NULL',
      whereArgs: [projectId],
    );
    return [for (final row in rows) row['designator'] as String];
  }

  static Future<int> weldedCount(int projectId) async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS n FROM weld_progress '
      'WHERE bom_project_id = ? AND welded = 1',
      [projectId],
    );
    return ((rows.first['n'] ?? 0) as num).toInt();
  }

  /// 各工程的已焊接数量（列表页一次查完，避免 N 次查询）。
  static Future<Map<int, int>> weldedCounts() async {
    final rows = await _db.rawQuery(
      'SELECT bom_project_id, COUNT(*) AS n FROM weld_progress '
      'WHERE welded = 1 GROUP BY bom_project_id',
    );
    return {
      for (final row in rows)
        ((row['bom_project_id'] ?? 0) as num).toInt(): ((row['n'] ?? 0) as num)
            .toInt(),
    };
  }

  /// 写入进度（按 bom_project_id + designator 唯一，靠 UPSERT 保证不重复）。
  static Future<WeldProgress> upsert({
    required int projectId,
    required String designator,
    int? bomItemId,
    bool? welded,
    bool bumpConsume = false,
    bool bumpLoss = false,
  }) async {
    final current = await byDesignator(projectId, designator);
    final next = WeldProgress(
      designator: designator,
      bomItemId: bomItemId ?? current?.bomItemId,
      welded: welded ?? current?.welded ?? false,
      consumeCount: (current?.consumeCount ?? 0) + (bumpConsume ? 1 : 0),
      lossCount: (current?.lossCount ?? 0) + (bumpLoss ? 1 : 0),
      updatedAt: DateTime.now(),
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.rawInsert(
      '''
      INSERT INTO weld_progress(
        bom_project_id, bom_item_id, designator, welded,
        consume_count, loss_count, action, created_at, updated_at
      ) VALUES(?, ?, ?, ?, ?, ?, NULL, ?, ?)
      ON CONFLICT(bom_project_id, designator) DO UPDATE SET
        bom_item_id = excluded.bom_item_id,
        welded = excluded.welded,
        consume_count = excluded.consume_count,
        loss_count = excluded.loss_count,
        updated_at = excluded.updated_at
      ''',
      [
        projectId,
        next.bomItemId,
        designator,
        next.welded ? 1 : 0,
        next.consumeCount,
        next.lossCount,
        now,
        now,
      ],
    );
    return next;
  }

  /// 清空某工程的「已焊接」勾选。
  ///
  /// 只取消勾选，不动消耗/损耗计数，更不回滚库存流水 ——
  /// 流水是真实出入库动作（PRD 11.7），要退走物料详情页的撤销。
  static Future<void> clearWelded(int projectId) async {
    await _db.update(
      'weld_progress',
      {'welded': 0, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'bom_project_id = ?',
      whereArgs: [projectId],
    );
  }

  static Future<void> deleteByProject(int projectId) async {
    await _db.delete(
      'weld_progress',
      where: 'bom_project_id = ?',
      whereArgs: [projectId],
    );
  }
}
