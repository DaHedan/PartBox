import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

import 'seed_data.dart';

/// 本地 SQLite 数据库（全本地，无后端）。
class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  static const String dbFileName = 'partbox.db';
  static const int schemaVersion = 1;

  Database? _db;

  Database get db {
    final database = _db;
    if (database == null) {
      throw StateError('数据库尚未初始化，请先调用 AppDatabase.instance.init()');
    }
    return database;
  }

  bool get isOpen => _db != null;

  Future<String> databaseFilePath() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, dbFileName);
  }

  Future<void> init({String? overridePath}) async {
    if (_db != null) return;
    if (!Platform.isAndroid && !Platform.isIOS) {
      ffi.sqfliteFfiInit();
      databaseFactory = ffi.databaseFactoryFfi;
    }
    final path = overridePath ?? await databaseFilePath();
    _db = await openDatabase(
      path,
      version: schemaVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _onCreate,
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Future<void> _onCreate(Database db, int version) async {
    final batch = db.batch();

    batch.execute('''
      CREATE TABLE categories(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        parent_id INTEGER,
        name TEXT NOT NULL,
        icon TEXT,
        sort INTEGER NOT NULL DEFAULT 0,
        builtin INTEGER NOT NULL DEFAULT 0
      )
    ''');

    batch.execute('''
      CREATE TABLE locations(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        parent_id INTEGER,
        name TEXT NOT NULL,
        note TEXT,
        sort INTEGER NOT NULL DEFAULT 0
      )
    ''');

    batch.execute('''
      CREATE TABLE materials(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        mpn TEXT,
        lcsc_code TEXT,
        subcategory_id INTEGER,
        package TEXT,
        brand TEXT,
        params_json TEXT,
        image_path TEXT,
        unit TEXT NOT NULL DEFAULT 'pcs',
        location_id INTEGER,
        qty_purchased REAL NOT NULL DEFAULT 0,
        qty_used REAL NOT NULL DEFAULT 0,
        qty_remaining REAL NOT NULL DEFAULT 0,
        low_stock_threshold REAL,
        unit_price REAL,
        note TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        last_transaction_at INTEGER
      )
    ''');

    batch.execute('''
      CREATE TABLE transactions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        material_id INTEGER NOT NULL,
        type TEXT NOT NULL,
        qty REAL NOT NULL,
        remaining_after REAL NOT NULL,
        note TEXT,
        created_at INTEGER NOT NULL
      )
    ''');

    batch.execute('''
      CREATE TABLE category_param_templates(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        subcategory_id INTEGER NOT NULL,
        param_name TEXT NOT NULL,
        sort INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // 预留功能表（F10 BOM 对照 / F11 焊接辅助），V2.0 建库即建好。
    batch.execute('''
      CREATE TABLE bom_projects(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        file_name TEXT,
        source TEXT,
        note TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    batch.execute('''
      CREATE TABLE bom_items(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        bom_project_id INTEGER NOT NULL,
        designator TEXT,
        comment TEXT,
        footprint TEXT,
        lcsc_code TEXT,
        mpn TEXT,
        quantity REAL NOT NULL DEFAULT 0,
        material_id INTEGER,
        pos_x REAL,
        pos_y REAL,
        side TEXT,
        sort INTEGER NOT NULL DEFAULT 0
      )
    ''');

    batch.execute('''
      CREATE TABLE weld_progress(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        bom_project_id INTEGER NOT NULL,
        bom_item_id INTEGER,
        action TEXT,
        created_at INTEGER NOT NULL
      )
    ''');

    batch.execute('''
      CREATE TABLE settings(
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');

    batch.execute('CREATE INDEX idx_materials_category ON materials(subcategory_id)');
    batch.execute('CREATE INDEX idx_materials_location ON materials(location_id)');
    batch.execute('CREATE INDEX idx_tx_material ON transactions(material_id)');

    await batch.commit(noResult: true);

    await _seed(db);
  }

  Future<void> _seed(Database db) async {
    // 内置"未分类"大类（id=1，不可删除）。
    // 必须最先插入：其余大类依赖自增 id，若延迟到最后批量插入，
    // 自增行会先占用 id=1 造成主键冲突。
    await db.insert('categories', {
      'id': kUncategorizedCategoryId,
      'parent_id': null,
      'name': kUncategorizedName,
      'icon': 'help',
      'sort': 0,
      'builtin': 1,
    });

    var sort = 1;
    for (final seed in kSeedCategories) {
      final topId = await db.insert('categories', {
        'parent_id': null,
        'name': seed.name,
        'icon': seed.icon,
        'sort': sort,
        'builtin': 1,
      });
      var subSort = 0;
      for (final sub in seed.subs) {
        await db.insert('categories', {
          'parent_id': topId,
          'name': sub,
          'icon': null,
          'sort': subSort++,
          'builtin': 1,
        });
      }
      sort++;
    }

    // 内置"未分配"仓库（id=1，不可删除）
    await db.insert('locations', {
      'id': kUnassignedLocationId,
      'parent_id': null,
      'name': kUnassignedLocationName,
      'note': null,
      'sort': 0,
    });

    await db.insert('settings', {'key': 'schema_seeded', 'value': '1'});
  }
}
