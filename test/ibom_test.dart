import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:partbox/data/app_database.dart';
import 'package:partbox/data/models.dart';
import 'package:partbox/data/repositories/bom_repository.dart';
import 'package:partbox/data/repositories/material_repository.dart';
import 'package:partbox/data/repositories/transaction_repository.dart';
import 'package:partbox/data/repositories/weld_repository.dart';
import 'package:partbox/data/weld/ibom_import.dart';
import 'package:partbox/data/weld/ibom_parser.dart';
import 'package:partbox/data/weld/weld_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

const samplePath =
    r'F:\Code\esp32\SmartEYE\Hardware\PCB\V1.2\zhimou_1.2_InteractiveBOM_PCB1_2026-9-13.html';

/// 造一份与嘉立创 iBOM 同构的最小 HTML（三层转义 JSON）。
String buildFakeIbom() {
  final inner = {
    'file_info': {'create_time': 1789265162932},
    'check_info': {'assembler_total_num': 3},
    'comp_info': {
      'C6119867,100nF': {
        'Supplier Part': 'C6119867',
        'Manufacturer Part': 'CGA0603X7R104K500JT',
        'Manufacturer': 'HRE(芯声)',
        'Supplier Footprint': '0603',
        'Value': '100nF',
        'q': 2,
        'Description': '容值:100nF;精度:±10%;额定电压:50V;温度系数:X7R;',
      },
      'C100044,0Ω': {
        'Supplier Part': 'C100044',
        'Manufacturer Part': 'RC0603JR-070RL',
        'Manufacturer': 'YAGEO',
        'lc_pkg': '0603',
        'value': '0Ω',
        'q': 1,
        'Description': '阻值:0Ω;功率:100mW;',
      },
    },
    'designator_info': [
      {
        'name': 'default',
        'top': [
          {
            'des': 'R8',
            'lc_code': 'C100044,0Ω',
            'ft_name': 'R0603',
            'cm': '0Ω',
            'bom_index': 2,
            'ec': {'x': 1.5, 'y': -2.5, 'ang': 90},
          },
          {
            'des': 'C1',
            'lc_code': 'C6119867,100nF',
            'ft_name': 'C0603',
            'cm': '100nF',
            'bom_index': 1,
            'ec': {'x': 3.0, 'y': -4.0, 'ang': 0},
          },
        ],
        'bottom': [
          {
            'des': 'CN2',
            'lc_code': 'C2797209,undefined',
            'ft_name': 'FPC-SMD',
            'cm': 'KH-FG0.5',
            'bom_index': 31,
            'ec': {'x': -0.1, 'y': -55.3, 'ang': 180},
          },
        ],
      },
    ],
  };
  final files = {
    'bom_merge': jsonEncode({'sum': '1231313215456', 'data': jsonEncode(inner)}),
    'language': 'zh-hans',
  };
  return '<html><head><title>SMT-UI App</title>'
      '<meta name="solder-mask-material" content="solder_mask_green">'
      '<!-- <meta name="pad-material" content="gold" /> -->'
      '</head><body><script>window.files = ${jsonEncode(files)};'
      ' window.__ENGING_OBJ_PRELOAD__ = {"a":{"b":1}};</script></body></html>';
}

void main() {
  group('F11 iBOM 解析', () {
    test('花括号配对能跳过字符串里的括号与转义', () {
      const text =
          'window.files = {"a":"}{\\"x","b":{"c":1}}; window.__NEXT__ = {"z":2};';
      final start = text.indexOf('{');
      final json = IbomParser.extractJsonObject(text, start);
      expect(json, '{"a":"}{\\"x","b":{"c":1}}');
      expect(jsonDecode(json!), {'a': '}{"x', 'b': {'c': 1}});
    });

    test('解析三层转义 JSON 得到物料与位号', () {
      final data = IbomParser.parse(buildFakeIbom());

      expect(data.materials, hasLength(2));
      final c = data.materials.firstWhere((m) => m.lcsc == 'C6119867');
      expect(c.value, '100nF');
      expect(c.mpn, 'CGA0603X7R104K500JT');
      expect(c.manufacturer, 'HRE(芯声)');
      expect(c.footprint, '0603');
      expect(c.qty, 2);
      // Description 拆成参数，正好是 F10 比对照抄的立创参数名
      expect(c.params['容值'], '100nF');
      expect(c.params['额定电压'], '50V');
      expect(c.params['温度系数'], 'X7R');
      expect(c.paramEntries.map((p) => p.k), contains('容值'));

      // lc_pkg / value 这两种兜底字段
      final r = data.materials.firstWhere((m) => m.lcsc == 'C100044');
      expect(r.value, '0Ω');
      expect(r.footprint, '0603');
      expect(r.params['阻值'], '0Ω');
      expect(r.params['功率'], '100mW');

      expect(data.designators, hasLength(3));
      expect(data.topCount, 2);
      expect(data.bottomCount, 1);

      final cn2 = data.designators.firstWhere((d) => d.designator == 'CN2');
      expect(cn2.isBottom, isTrue);
      expect(cn2.x, -0.1);
      expect(cn2.angle, 180);
      // 物料 key 里带 undefined，按 C 编号退化匹配
      expect(data.materialOf(cn2), isNull);

      final c1 = data.designators.firstWhere((d) => d.designator == 'C1');
      expect(data.materialOf(c1)?.lcsc, 'C6119867');
    });

    test('位号转成 F10 比对行时带上物料信息', () {
      final data = IbomParser.parse(buildFakeIbom());
      final c1 = data.designators.firstWhere((d) => d.designator == 'C1');
      final row = c1.toBomRow(data.materialOf(c1));
      expect(row.designator, 'C1');
      expect(row.lcscCode, 'C6119867');
      expect(row.mpn, 'CGA0603X7R104K500JT');
      expect(row.footprint, '0603');
      expect(row.comment, '100nF');
      expect(row.quantity, 1);
    });

    test('parse 对非 iBOM 文件给出明确错误', () {
      expect(
        () => IbomParser.parse('<html><body>hello</body></html>'),
        throwsA(isA<IbomParseException>()),
      );
    });
  });

  group('F11 打开前改写（阻焊蓝 / 焊盘喷锡）', () {
    test('meta 插在 head 之后，抢在原有设置前面生效', () {
      final out = IbomParser.prepareHtml(buildFakeIbom());
      final blue = out.indexOf('name="solder-mask-material" content="solder_mask_blue"');
      expect(blue, greaterThan(0));
      expect(
        RegExp(r'<meta[^>]*content="solder_mask_green"').hasMatch(out),
        isFalse,
        reason: '原绿色 meta 应当被改掉',
      );
      // 第一个 solder-mask-material 必须是蓝色
      final first = out.indexOf(RegExp('name="solder-mask-material"'));
      expect(out.indexOf('solder_mask_blue', first), greaterThan(0));
      // 生效的 pad-material 存在且为 silver
      expect(out.contains('<meta name="pad-material" content="silver">'), isTrue);
      // 被注释掉的那条不用改（改了也不生效），保持原样
      expect(out.contains('<!-- <meta name="pad-material" content="gold" /> -->'), isTrue);
    });

    test('重复改写不会把顺序搞乱', () {
      final once = IbomParser.prepareHtml(buildFakeIbom());
      final twice = IbomParser.prepareHtml(once);
      final first = twice.indexOf('name="solder-mask-material"');
      expect(twice.indexOf('solder_mask_blue', first), greaterThan(0));
      expect(twice.contains('solder_mask_green'), isFalse);
    });
  });

  final hasSample = File(samplePath).existsSync();

  group('F11 真实 iBOM 文件', () {
    test('解析智眸 V1.2 的 iBOM', () {
      final html = File(samplePath).readAsStringSync();
      final data = IbomParser.parse(html);

      expect(data.materials, hasLength(30));
      expect(data.designators, hasLength(73));
      expect(data.topCount, 72);
      expect(data.bottomCount, 1);

      // C1 = 100nF/50V，参数来自 Description
      final c1 = data.designators.firstWhere((d) => d.designator == 'C1');
      final material = data.materialOf(c1);
      expect(material, isNotNull);
      expect(material!.lcsc, 'C6119867');
      expect(material.params['容值'], '100nF');
      expect(material.params['额定电压'], '50V');

      // 电阻带功率
      final r8 = data.designators.firstWhere((d) => d.designator == 'R8');
      final r8Material = data.materialOf(r8);
      expect(r8Material?.mpn, isNotEmpty);
      expect(r8Material?.params['阻值'], '10kΩ');
      expect(r8Material?.params['功率'], isNotEmpty);

      // 带 undefined 值的物料也要能按 C 编号退化匹配
      final sw1 = data.designators.firstWhere((d) => d.designator == 'SW1');
      expect(sw1.materialKey, contains('undefined'));
      expect(IbomData.lcscOf(sw1.materialKey), 'C2874433');
    });

    test('改写后 3D 板子初始为阻焊蓝 + 喷锡银', () {
      final html = File(samplePath).readAsStringSync();
      final out = IbomParser.prepareHtml(html);
      expect(out.length, greaterThan(html.length));

      final first = out.indexOf('name="solder-mask-material"');
      expect(first, greaterThan(0));
      final tag = out.substring(first, first + 80);
      expect(tag, contains('solder_mask_blue'));
      // 注意：solder_mask_green 还会出现在 JS 的图层默认色里（registType(...)），
      // 那与 meta 无关，这里只要求不存在「绿色的 meta」。
      expect(
        RegExp(r'<meta[^>]*content="solder_mask_green"').hasMatch(out),
        isFalse,
      );
      expect(out.contains('<meta name="pad-material" content="silver">'), isTrue);
      // 只改 meta，不动 window.files
      expect(out.contains('window.files = '), isTrue);
      expect(IbomParser.parse(out).designators, hasLength(73));
    });
  }, skip: hasSample ? false : '本机没有示例 iBOM 文件，跳过');

  group('F11 位号 → bom_items 与四色比对', () {
    late IbomData data;
    late MaterialItem material;

    setUpAll(() {
      data = IbomParser.parse(buildFakeIbom());
      final now = DateTime.now();
      material = MaterialItem(
        id: 7,
        name: '贴片电容 100nF 0603',
        lcscCode: 'C6119867',
        mpn: 'CGA0603X7R104K500JT',
        brand: 'HRE(芯声)',
        package: '0603',
        qtyRemaining: 50,
        createdAt: now,
        updatedAt: now,
      );
    });

    test('一个位号一行，按 bom_index 排序', () {
      final built = IbomImportService.buildItems(
        projectId: 1,
        data: data,
        materials: [material],
      );
      expect(built.items, hasLength(3));
      expect(
        built.items.map((i) => i.designator).toList(),
        ['C1', 'R8', 'CN2'],
      );
      expect(built.items[0].sort, 0);
      expect(built.items[0].quantity, 1, reason: '一个位号算一份');
      expect(built.items[0].lcscCode, 'C6119867');
      // iBOM 的 Description 参数带进了条目，供四色比对用
      expect(built.items[0].params.map((p) => p.k), contains('额定电压'));
    });

    test('按 C 编号命中库存 → 蓝；库里没有 → 红', () {
      final built = IbomImportService.buildItems(
        projectId: 1,
        data: data,
        materials: [material],
      );
      final c1 = built.items.firstWhere((i) => i.designator == 'C1');
      expect(c1.matchStatus, MatchStatus.blue);
      expect(c1.matchedMaterialId, 7);
      expect(built.matched, 1);

      final r8 = built.items.firstWhere((i) => i.designator == 'R8');
      expect(r8.matchStatus, MatchStatus.red);
      expect(r8.matchedMaterialId, isNull);
    });
  });

  group('F11 焊接进度与库存联动', () {
    final dbPath = '${Directory.current.path}/.dart_tool/weld_test.db';
    var projectId = 0;
    var materialId = 0;
    late List<BomItem> items;

    setUpAll(() async {
      final file = File(dbPath);
      if (file.existsSync()) file.deleteSync();
      await AppDatabase.instance.init(overridePath: dbPath);
      final now = DateTime.now();
      materialId = await MaterialRepository.insert(
        MaterialItem(
          name: '贴片电阻 10kΩ 0603',
          lcscCode: 'C2906982',
          mpn: 'FRC0603F1002TS',
          package: '0603',
          qtyPurchased: 10,
          qtyRemaining: 10,
          createdAt: now,
          updatedAt: now,
        ),
      );
      projectId = await BomRepository.insertProject(
        BomProject(name: '测试板', source: 'ibom', createdAt: now, updatedAt: now),
      );
      items = await BomRepository.insertItems([
        BomItem(
          bomProjectId: projectId,
          designator: 'R8',
          lcscCode: 'C2906982',
          matchedMaterialId: materialId,
        ),
        BomItem(
          bomProjectId: projectId,
          designator: 'U9',
          lcscCode: 'C9999999',
        ),
      ]);
    });

    tearDownAll(() async {
      await AppDatabase.instance.close();
    });

    test('丢失：库存 −1 + 焊接丢失流水，不勾选已焊接', () async {
      final outcome = await WeldService.record(
        bomProjectId: projectId,
        designator: 'R8',
        bomItemId: items[0].id,
        materialId: materialId,
        loss: true,
      );
      expect(outcome.materialMoved, isTrue);
      expect(outcome.remainingAfter, 9);

      final material = await MaterialRepository.byId(materialId);
      expect([material!.qtyUsed, material.qtyRemaining], [1, 9]);

      final txs = await TransactionRepository.byMaterial(materialId);
      expect(txs.first.type, TxType.weldLoss);
      expect(TxType.label(txs.first.type), '焊接丢失');
      expect(txs.first.qty, -1);

      final progress = await WeldRepository.byDesignator(projectId, 'R8');
      expect(progress!.welded, isFalse);
      expect(progress.lossCount, 1);
      expect(progress.consumeCount, 0);
    });

    test('完成：库存 −1 + 焊接完成流水 + 勾选已焊接', () async {
      final outcome = await WeldService.record(
        bomProjectId: projectId,
        designator: 'R8',
        bomItemId: items[0].id,
        materialId: materialId,
        loss: false,
      );
      expect(outcome.materialMoved, isTrue);

      final material = await MaterialRepository.byId(materialId);
      expect([material!.qtyUsed, material.qtyRemaining], [2, 8]);

      final txs = await TransactionRepository.byMaterial(materialId);
      expect(txs.first.type, TxType.weldConsume);
      expect(TxType.label(txs.first.type), '焊接完成');

      final progress = await WeldRepository.byDesignator(projectId, 'R8');
      expect(progress!.welded, isTrue);
      expect(progress.consumeCount, 1);
      expect(progress.lossCount, 1, reason: '上一次「掉了」的计数要留着');
      expect(await WeldRepository.weldedDesignators(projectId), ['R8']);
      expect(await WeldRepository.weldedCounts(), {projectId: 1});
    });

    test('未匹配库存：只记进度，不动库存', () async {
      final before = await MaterialRepository.byId(materialId);
      final outcome = await WeldService.record(
        bomProjectId: projectId,
        designator: 'U9',
        bomItemId: items[1].id,
        materialId: null,
        loss: false,
      );
      expect(outcome.materialMoved, isFalse);
      final after = await MaterialRepository.byId(materialId);
      expect(after!.qtyRemaining, before!.qtyRemaining);
      expect(after.qtyUsed, before.qtyUsed);

      final progress = await WeldRepository.byDesignator(projectId, 'U9');
      expect(progress!.welded, isTrue, reason: '未匹配也要记进度');
      expect(progress.consumeCount, 1);
    });

    test('同一位号只有一行进度（唯一约束 + UPSERT）', () async {
      await WeldRepository.upsert(
        projectId: projectId,
        designator: 'R8',
        bumpConsume: true,
      );
      await WeldRepository.upsert(
        projectId: projectId,
        designator: 'R8',
        bumpConsume: true,
      );
      final progress = await WeldRepository.byProject(projectId);
      expect(progress.keys.toSet(), {'R8', 'U9'});
      expect(progress['R8']!.consumeCount, 3);
    });

    test('位号匹配物料：优先 F10 已匹配的，其次按 C 编号', () async {
      expect(await WeldService.resolveMaterial(items[0]), isNotNull);
      final byCode = await WeldService.resolveMaterial(items[1]);
      expect(byCode, isNull, reason: '库中确实没有 C9999999');
    });

    test('删除工程级联清掉焊接进度', () async {
      final now = DateTime.now();
      final extra = await BomRepository.insertProject(
        BomProject(name: '临时', source: 'ibom', createdAt: now, updatedAt: now),
      );
      await WeldRepository.upsert(
        projectId: extra,
        designator: 'X1',
        welded: true,
      );
      expect(await WeldRepository.weldedCount(extra), 1);
      await BomRepository.deleteProject(extra);
      expect(await WeldRepository.weldedCount(extra), 0);
      expect(await WeldRepository.byProject(extra), isEmpty);
    });
  });

  group('F11 schema v3 → v4 升级', () {
    final dbPath = '${Directory.current.path}/.dart_tool/upgrade_v4.db';

    test('旧的 weld_progress 占位表补上按位号所需的列', () async {
      final file = File(dbPath);
      if (file.existsSync()) file.deleteSync();

      // 先造一个 v3 的库：weld_progress 还是老结构（V2.0 的占位表）
      ffi.sqfliteFfiInit();
      final old = await ffi.databaseFactoryFfi.openDatabase(dbPath);
      await old.execute('''
        CREATE TABLE weld_progress(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          bom_project_id INTEGER NOT NULL,
          bom_item_id INTEGER,
          action TEXT,
          created_at INTEGER NOT NULL
        )
      ''');
      await old.execute('PRAGMA user_version = 3');
      await old.close();

      // 打开即触发 onUpgrade
      await AppDatabase.instance.init(overridePath: dbPath);
      final info = await AppDatabase.instance.db.rawQuery(
        'PRAGMA table_info(weld_progress)',
      );
      final columns = info.map((row) => row['name']).toSet();
      expect(
        columns.containsAll({
          'designator',
          'welded',
          'consume_count',
          'loss_count',
          'updated_at',
        }),
        isTrue,
        reason: '实际列：$columns',
      );
      final index = await AppDatabase.instance.db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' "
        "AND name='idx_weld_progress_designator'",
      );
      expect(index, isNotEmpty, reason: '唯一索引要一起建上');

      // 升级后能正常写进度
      await WeldRepository.upsert(
        projectId: 1,
        designator: 'R1',
        welded: true,
      );
      expect(await WeldRepository.weldedCount(1), 1);

      await AppDatabase.instance.close();
    });

    test('重复升级不会报错（幂等）', () async {
      await AppDatabase.instance.init(overridePath: dbPath);
      final info = await AppDatabase.instance.db.rawQuery(
        'PRAGMA table_info(weld_progress)',
      );
      expect(info, isNotEmpty);
      await AppDatabase.instance.close();
    });
  });
}
