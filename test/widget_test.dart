import 'dart:io';

import 'package:excel/excel.dart' as xls;
import 'package:flutter_test/flutter_test.dart';
import 'package:partbox/data/app_database.dart';
import 'package:partbox/data/bom/bom_exporter.dart';
import 'package:partbox/data/bom/bom_matcher.dart';
import 'package:partbox/data/bom/bom_parser.dart';
import 'package:partbox/data/lcsc/lcsc_service.dart';
import 'package:partbox/data/models.dart';
import 'package:partbox/data/repositories/bom_repository.dart';
import 'package:partbox/data/repositories/material_repository.dart';
import 'package:partbox/data/repositories/transaction_repository.dart';
import 'package:partbox/data/stock_service.dart';
import 'package:partbox/utils/format.dart';
import 'package:partbox/utils/scan_payload.dart';
import 'package:partbox/widgets/facet_filter.dart';

void main() {
  test('参数键值对编解码', () {
    const params = [ParamEntry('容值', '10uF'), ParamEntry('额定电压', '25V')];
    final decoded = ParamEntry.decode(ParamEntry.encode(params));
    expect(decoded.length, 2);
    expect(decoded.first.k, '容值');
    expect(decoded.first.v, '10uF');
  });

  test('数量格式化：整数不带小数位', () {
    expect(formatQty(200), '200');
    expect(formatQty(1.5), '1.5');
    expect(formatQtySigned(-3), '-3');
    expect(formatQtySigned(3), '+3');
  });

  test('C 编号提取', () {
    expect(LcscService.normalizeCode('C106248'), 'C106248');
    expect(LcscService.normalizeCode('https://item.szlcsc.com/c106248.html'), 'C106248');
    expect(LcscService.normalizeCode('NO-CODE'), isNull);
  });

  group('立创袋标二维码解析', () {
    test('pc → C 编号、pm → MPN、qty → 数量', () {
      const raw =
          '{on:SO26091528911,pc:C518789,pm:FDN338P,qty:10,mc:,cc:1,pdi:237147158,hp:11}';
      final payload = parseLcscLabel(raw);
      expect(payload, isNotNull);
      expect(payload!.code, 'C518789');
      expect(payload.mpn, 'FDN338P');
      expect(payload.qty, 10);
    });

    test('容错：缺字段 / 空值跳过，非该格式返回 null', () {
      final partial = parseLcscLabel('{pc:C106248,pm:,qty:}');
      expect(partial!.code, 'C106248');
      expect(partial.mpn, isNull);
      expect(partial.qty, isNull);
      // 只有 mpn/qty 也算命中（缺 pc 就不带出 C 编号）
      final noCode = parseLcscLabel('{pm:FDN338P,qty:100}');
      expect(noCode!.code, isNull);
      expect(noCode.mpn, 'FDN338P');
      // 非花括号格式 / 空对象
      expect(parseLcscLabel('C106248'), isNull);
      expect(parseLcscLabel('{}'), isNull);
    });

    test('qty 带单位也能解析，值为空则不预填', () {
      expect(parseLcscLabel('{pc:C106248,qty:100PCS}')!.qty, 100);
      expect(parseLcscLabel('{pc:C106248,qty:0}')!.qty, isNull);
    });

    test('批次追溯码（X+数字）识别', () {
      expect(isBatchTraceCode('X237147158'), isTrue);
      expect(isBatchTraceCode('x123456'), isTrue);
      expect(isBatchTraceCode('C237147158'), isFalse);
      expect(isBatchTraceCode('{pc:C518789}'), isFalse);
    });
  });

  test('筛选参数值排序：数值+单位按数值，其余按字典序', () {
    // 容值跨单位换算：100nF(=1e-7F) 在 1uF(=1e-6F) 前
    expect(compareParamValues('100nF', '1uF'), lessThan(0));
    expect(compareParamValues('1uF', '10uF'), lessThan(0));
    expect(compareParamValues('±1%', '±10%'), lessThan(0));
    expect(compareParamValues('6.3V', '16V'), lessThan(0));
    // 阻值两种写法可比：4.7K < 10kΩ
    expect(compareParamValues('4.7K', '10kΩ'), lessThan(0));
    // 可解析的排在不可解析的（X7R 这类温度系数）之前
    expect(compareParamValues('0603', 'X7R'), lessThan(0));
    // 都不可解析时按字典序
    expect(compareParamValues('C0G', 'X7R'), lessThan(0));
  });

  group('三量联动：余量 = 采购量 − 消耗量', () {
    final dbPath = '${Directory.current.path}/.dart_tool/qty_test.db';
    var materialId = 0;

    setUpAll(() async {
      final file = File(dbPath);
      if (file.existsSync()) file.deleteSync();
      await AppDatabase.instance.init(overridePath: dbPath);
      final now = DateTime.now();
      materialId = await MaterialRepository.insert(
        MaterialItem(
          name: '测试电阻',
          createdAt: now,
          updatedAt: now,
        ),
      );
    });

    tearDownAll(() async {
      await AppDatabase.instance.close();
    });

    test('改采购量 / 消耗量 → 自动算余量', () async {
      await StockService.adjustField(
        materialId: materialId,
        field: StockService.fieldPurchased,
        value: 100,
      );
      var item = await MaterialRepository.byId(materialId);
      expect([item!.qtyPurchased, item.qtyUsed, item.qtyRemaining], [100, 0, 100]);

      await StockService.adjustField(
        materialId: materialId,
        field: StockService.fieldUsed,
        value: 30,
      );
      item = await MaterialRepository.byId(materialId);
      expect([item!.qtyPurchased, item.qtyUsed, item.qtyRemaining], [100, 30, 70]);
    });

    test('改余量 → 反推消耗量（采购量不变）', () async {
      await StockService.adjustField(
        materialId: materialId,
        field: StockService.fieldRemaining,
        value: 50,
      );
      final item = await MaterialRepository.byId(materialId);
      expect([item!.qtyPurchased, item.qtyUsed, item.qtyRemaining], [100, 50, 50]);
    });

    test('每次校正都记一条流水', () async {
      final txs = await TransactionRepository.byMaterial(materialId);
      expect(txs.length, 3);
      expect(txs.first.note, contains('余量'));
      expect(txs.first.remainingAfter, 50);
    });
  });

  group('F10.2 单位归一化', () {
    test('容值统一到 pF：100nF = 0.1µF = 100000pF', () {
      expect(parseCapacitancePf('100nF'), 100000);
      expect(parseCapacitancePf('0.1uF'), 100000);
      expect(parseCapacitancePf('0.1µF'), 100000);
      expect(parseCapacitancePf('100000pF'), 100000);
      expect(parseCapacitancePf('10uF'), 10000000);
      expect(parseCapacitancePf('4.7uF'), 4700000);
      expect(parseCapacitancePf('X7R'), isNull);
    });

    test('阻值统一到 Ω：4.7K = 4k7 = 4700', () {
      expect(parseResistanceOhm('5.1kΩ'), 5100);
      expect(parseResistanceOhm('4.7K'), 4700);
      expect(parseResistanceOhm('4k7'), 4700);
      expect(parseResistanceOhm('10Ω'), 10);
      expect(parseResistanceOhm('0Ω'), 0);
      expect(parseResistanceOhm('1M'), 1000000);
    });

    test('封装去前缀字母：C0603/R0603 → 0603', () {
      expect(normalizePackage('C0603'), '0603');
      expect(normalizePackage('r0402'), '0402');
      expect(normalizePackage('0603'), '0603');
      expect(normalizePackage('SOD-523_L1.2-W0.8'), 'SOD-523_L1.2-W0.8');
    });

    test('从 Comment 里挑出耐压 / 功率', () {
      expect(extractVoltageV('100nF 50V'), 50);
      expect(extractVoltageV('4.7uF/16V'), 16);
      expect(extractVoltageV('100nF'), isNull);
      expect(extractPowerW('10kΩ 0.1W'), 0.1);
      expect(extractPowerW('10kΩ'), isNull);
    });
  });

  group('F10.2 四色比对', () {
    MaterialItem material({
      String? mpn,
      String? code,
      String? brand,
      String? package,
      List<ParamEntry> params = const [],
      double remaining = 100,
    }) => MaterialItem(
      id: 1,
      name: '库中料',
      mpn: mpn,
      lcscCode: code,
      brand: brand,
      package: package,
      params: params,
      qtyRemaining: remaining,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    test('蓝：C 编号一致', () {
      final result = BomMatcher.match(
        const ParsedBomRow(
          designator: 'C12, C24',
          comment: '100nF',
          footprint: 'C0603',
          lcscCode: 'C66501',
          quantity: 2,
        ),
        [material(code: 'C66501')],
      );
      expect(result.status, MatchStatus.blue);
      expect(result.reason, 'C 编号一致');
    });

    test('蓝：MPN + 制造商一致', () {
      final result = BomMatcher.match(
        const ParsedBomRow(
          designator: 'Q2',
          mpn: 'FDN338P',
          manufacturer: 'HUASHUO(华朔)',
          quantity: 1,
        ),
        [material(mpn: 'FDN338P', brand: 'HUASHUO(华朔)')],
      );
      expect(result.status, MatchStatus.blue);
    });

    test('绿：电容容值 + 封装 + 耐压全一致', () {
      final result = BomMatcher.match(
        const ParsedBomRow(
          designator: 'C1',
          comment: '100nF 50V',
          footprint: 'C0603',
          quantity: 12,
        ),
        [
          material(
            code: 'C6119867',
            package: '0603',
            params: const [ParamEntry('容值', '0.1uF'), ParamEntry('耐压', '50V')],
          ),
        ],
      );
      expect(result.status, MatchStatus.green);
    });

    test('黄：仅核心参数（容值 + 封装）一致', () {
      final result = BomMatcher.match(
        const ParsedBomRow(
          designator: 'C1',
          comment: '100nF',
          footprint: 'C0603',
          quantity: 12,
        ),
        [
          material(
            code: 'C6119867',
            package: '0603',
            params: const [ParamEntry('容值', '0.1uF')],
          ),
        ],
      );
      expect(result.status, MatchStatus.yellow);
      expect(MatchStatus.defaultChecked(result.status), isTrue);
    });

    test('红：库中无匹配料', () {
      final result = BomMatcher.match(
        const ParsedBomRow(
          designator: 'R1',
          comment: '5.1kΩ',
          footprint: 'R0402',
          quantity: 2,
        ),
        [
          material(
            package: '0402',
            params: const [ParamEntry('阻值', '10kΩ')],
          ),
        ],
      );
      expect(result.status, MatchStatus.red);
      expect(result.candidates, isEmpty);
      expect(MatchStatus.defaultChecked(result.status), isTrue);
    });

    test('非 RLC 只判蓝 / 红（参数一致也不算绿黄）', () {
      final result = BomMatcher.match(
        const ParsedBomRow(
          designator: 'U1',
          comment: '2.4GHz',
          footprint: 'WIRELM-SMD_ESP32-S3-WROOM-1',
          quantity: 1,
        ),
        [material(package: 'WIRELM-SMD_ESP32-S3-WROOM-1')],
      );
      expect(result.status, MatchStatus.red);
    });

    test('多候选：按余量降序，取第一个', () {
      final result = BomMatcher.match(
        const ParsedBomRow(
          designator: 'C1',
          comment: '100nF',
          footprint: 'C0603',
          quantity: 1,
        ),
        [
          material(code: 'C1', package: '0603', remaining: 10,
              params: const [ParamEntry('容值', '100nF')]),
          material(code: 'C2', package: '0603', remaining: 999,
              params: const [ParamEntry('容值', '100nF')]),
        ],
      );
      expect(result.status, MatchStatus.yellow);
      expect(result.candidates.length, 2);
      expect(result.candidates.first.lcscCode, 'C2');
    });
  });

  group('F10.4 双导出', () {
    test('采购 BOM：仅勾选行，保持嘉立创列结构', () {
      final bytes = BomExporter.buildPurchaseBom(const [
        BomItem(
          bomProjectId: 1,
          designator: 'C1, C3',
          comment: '100nF',
          footprint: 'C0603',
          mpn: 'CGA0603X7R104K500JT',
          manufacturer: 'HRE(芯声)',
          lcscCode: 'C6119867',
          quantity: 12,
          unitPrice: 0.05,
          matchStatus: MatchStatus.yellow,
          checked: true,
        ),
        BomItem(
          bomProjectId: 1,
          designator: 'C2',
          comment: '1uF',
          footprint: 'C0603',
          mpn: 'B',
          lcscCode: 'C106248',
          quantity: 3,
          matchStatus: MatchStatus.blue,
          checked: false,
        ),
      ]);

      final book = xls.Excel.decodeBytes(bytes);
      final sheet = book.tables[BomExporter.sheetName]!;
      final header = sheet.rows.first
          .map((cell) => cell?.value?.toString() ?? '')
          .toList();
      expect(header, BomExporter.headers);

      final parsed = BomParser.parseXlsx(bytes);
      expect(parsed, isNotNull);
      expect(parsed!.rows.length, 1);
      expect(parsed.rows.first.designator, 'C1, C3');
      expect(parsed.rows.first.quantity, 12);
      expect(parsed.rows.first.lcscCode, 'C6119867');
    });

    test('替换 BOM：未勾选的黄行换成库中匹配料并备注替代', () {
      final material = MaterialItem(
        id: 7,
        name: '贴片电容 100nF',
        mpn: 'CL10B104KO8NNNC',
        lcscCode: 'C66501',
        brand: 'SAMSUNG(三星)',
        package: '0603',
        params: const [ParamEntry('容值', '100nF')],
        qtyRemaining: 500,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      final items = [
        const BomItem(
          bomProjectId: 1,
          designator: 'C1',
          comment: '100nF',
          footprint: 'C0603',
          mpn: 'CGA0603X7R104K500JT',
          manufacturer: 'HRE(芯声)',
          lcscCode: 'C6119867',
          quantity: 12,
          matchStatus: MatchStatus.yellow,
          matchedMaterialId: 7,
          checked: false,
        ),
        const BomItem(
          bomProjectId: 1,
          designator: 'R1',
          comment: '5.1kΩ',
          footprint: 'R0402',
          mpn: '0402WGF5101TCE',
          lcscCode: 'C25905',
          quantity: 2,
          matchStatus: MatchStatus.red,
          checked: true,
        ),
      ];

      final bytes = BomExporter.buildReplaceBom(items, {7: material});
      final parsed = BomParser.parseXlsx(bytes)!;
      expect(parsed.rows.length, 2);
      // 未勾选 + 黄 → 换成库中匹配料
      expect(parsed.rows[0].mpn, 'CL10B104KO8NNNC');
      expect(parsed.rows[0].lcscCode, 'C66501');
      expect(parsed.rows[0].manufacturer, 'SAMSUNG(三星)');
      // 勾选行保持原样
      expect(parsed.rows[1].mpn, '0402WGF5101TCE');

      // 备注列留了「替代：原 MPN」
      final sheet = xls.Excel.decodeBytes(bytes).tables[BomExporter.sheetName]!;
      final note = sheet.rows[1].last?.value?.toString() ?? '';
      expect(note, '替代：CGA0603X7R104K500JT');
    });
  });

  group('F10.5 bom_items 数据表', () {
    final dbPath = '${Directory.current.path}/.dart_tool/bom_test.db';
    var projectId = 0;

    setUpAll(() async {
      final file = File(dbPath);
      if (file.existsSync()) file.deleteSync();
      await AppDatabase.instance.init(overridePath: dbPath);
      final now = DateTime.now();
      projectId = await BomRepository.insertProject(
        BomProject(name: '测试工程', fileName: 'a.xlsx', createdAt: now, updatedAt: now),
      );
    });

    tearDownAll(() async {
      await AppDatabase.instance.close();
    });

    test('建表含 match_status / matched_material_id / checked', () async {
      final info = await AppDatabase.instance.db.rawQuery(
        'PRAGMA table_info(bom_items)',
      );
      final columns = info.map((row) => row['name'] as String).toSet();
      expect(
        columns.containsAll(['match_status', 'matched_material_id', 'checked']),
        isTrue,
        reason: 'bom_items 缺少 F10.5 要求的字段：$columns',
      );
    });

    test('比对结果与勾选可持久化', () async {
      await BomRepository.insertItems([
        BomItem(
          bomProjectId: projectId,
          designator: 'C1',
          comment: '100nF',
          quantity: 12,
          matchStatus: MatchStatus.yellow,
          checked: true,
        ),
      ]);
      var items = await BomRepository.items(projectId);
      expect(items.length, 1);
      expect(items.first.matchStatus, MatchStatus.yellow);
      expect(items.first.checked, isTrue);

      await BomRepository.updateItem(
        items.first.id!,
        matchStatus: MatchStatus.green,
        matchedMaterialId: 42,
        checked: false,
      );
      items = await BomRepository.items(projectId);
      expect(items.first.matchStatus, MatchStatus.green);
      expect(items.first.matchedMaterialId, 42);
      expect(items.first.checked, isFalse);

      final projects = await BomRepository.projects();
      expect(projects.single.itemCount, 1);
      expect(projects.single.checkedCount, 0);
    });

    test('删除工程级联删条目', () async {
      await BomRepository.deleteProject(projectId);
      expect(await BomRepository.items(projectId), isEmpty);
      expect(await BomRepository.projects(), isEmpty);
    });
  });
}
