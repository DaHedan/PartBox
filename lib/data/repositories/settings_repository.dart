import 'package:sqflite/sqflite.dart';

import '../app_database.dart';

/// 应用设置（settings 表：主题、阈值、密钥、上次使用仓库等）。
class SettingsRepository {
  static Database get _db => AppDatabase.instance.db;

  static const String keyThemeMode = 'theme_mode';
  static const String keyLowStockThreshold = 'low_stock_threshold';
  static const String keyLcscApiKey = 'lcsc_api_key';
  static const String keyLastLocationId = 'last_location_id';

  static Future<String?> get(String key) async {
    final rows = await _db.query(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  static Future<void> set(String key, String? value) async {
    await _db.insert('settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<Map<String, String>> all() async {
    final rows = await _db.query('settings');
    return {
      for (final row in rows)
        (row['key'] as String): (row['value'] ?? '') as String,
    };
  }

  static Future<void> replaceAll(Map<String, String> values) async {
    await _db.transaction((txn) async {
      await txn.delete('settings');
      for (final entry in values.entries) {
        await txn.insert('settings', {
          'key': entry.key,
          'value': entry.value,
        });
      }
    });
  }
}
