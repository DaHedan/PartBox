import 'dart:io';

import 'package:excel/excel.dart' as xls;
import 'package:flutter_test/flutter_test.dart';
import 'package:partbox/data/app_database.dart';
import 'package:partbox/data/bom/bom_enrich.dart';
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

    test('电感值统一到 H，电流统一到 A，频率统一到 Hz', () {
      expect(parseInductanceH('4.7uH'), closeTo(4.7e-6, 1e-12));
      expect(parseInductanceH('120nH'), closeTo(1.2e-7, 1e-12));
      expect(parseInductanceH('10mH'), closeTo(1e-2, 1e-9));
      expect(parseCurrentA('1.5A'), 1.5);
      expect(parseCurrentA('500mA'), 0.5);
      expect(parseCurrentA('100uA'), closeTo(1e-4, 1e-12));
      expect(parseFrequencyHz('16MHz'), 16000000);
      expect(parseFrequencyHz('32.768kHz'), 32768);
      expect(parseFrequencyHz('2.4GHz'), 2400000000);
      // 单位不能串台
      expect(parseInductanceH('100nF'), isNull);
      expect(parseCurrentA('120Ω'), isNull);
      expect(parseFrequencyHz('4.7uH'), isNull);
    });

    test('封装归一化：去前缀字母 + 去尺寸后缀', () {
      expect(normalizePackage('C0603'), '0603');
      expect(normalizePackage('r0402'), '0402');
      expect(normalizePackage('0603'), '0603');
      // 嘉立创 Footprint 带尺寸后缀，只留主封装名
      expect(normalizePackage('SOD-123_L2.7-W1.6-LS3.7-RD'), 'SOD-123');
      expect(normalizePackage('SOD-523_L1.2-W0.8-LS1.6-BI'), 'SOD-523');
      expect(normalizePackage('SOT-23-3_L3.0-W1.7-P0.95-LS2.9-BR'), 'SOT-23-3');
    });

    test('从 Comment 里挑出耐压 / 功率 / 电流 / 频率', () {
      expect(extractVoltageV('100nF 50V'), 50);
      expect(extractVoltageV('4.7uF/16V'), 16);
      expect(extractVoltageV('100nF'), isNull);
      expect(extractPowerW('10kΩ 0.1W'), 0.1);
      expect(extractPowerW('10kΩ'), isNull);
      expect(extractCurrentA('2.2uH 1.5A'), 1.5);
      // 磁珠的阻抗与测试频率不能互相当成电感/电流
      expect(extractImpedanceOhm('120Ω@100MHz'), 120);
      expect(extractInductanceH('120Ω@100MHz'), isNull);
      expect(extractCurrentA('120Ω@100MHz'), isNull);
    });
  });

  group('F10.2 四色比对', () {
    MaterialItem material({
      String? mpn,
      String? code,
      String? brand,
      String? package,
      String? category,
      List<ParamEntry> params = const [],
      double remaining = 100,
    }) => MaterialItem(
      id: 1,
      name: '库中料',
      mpn: mpn,
      lcscCode: code,
      brand: brand,
      package: package,
      categoryName: category,
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

    test('绿：电容容值 + 封装一致且耐压达标', () {
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
      expect(result.reason, '容值 + 封装一致，耐压达标');
    });

    test('绿：库存耐压高于 BOM 需求也算（50V 替 16V）', () {
      final result = BomMatcher.match(
        const ParsedBomRow(
          designator: 'C12, C24',
          comment: '100nF',
          footprint: 'C0603',
          quantity: 2,
        ),
        [
          material(
            package: '0603',
            params: const [
              ParamEntry('容值', '100nF'),
              ParamEntry('额定电压', '50V'),
            ],
          ),
        ],
        bomParams: const [
          ParamEntry('容值', '100nF'),
          ParamEntry('额定电压', '16V'),
        ],
      );
      expect(result.status, MatchStatus.green);
    });

    test('黄：库存耐压低于 BOM 需求', () {
      final result = BomMatcher.match(
        const ParsedBomRow(
          designator: 'C1',
          comment: '100nF',
          footprint: 'C0603',
          quantity: 2,
        ),
        [
          material(
            package: '0603',
            params: const [
              ParamEntry('容值', '100nF'),
              ParamEntry('额定电压', '16V'),
            ],
          ),
        ],
        bomParams: const [
          ParamEntry('容值', '100nF'),
          ParamEntry('额定电压', '50V'),
        ],
      );
      expect(result.status, MatchStatus.yellow);
      expect(result.reason, '核心参数一致 · 库存耐压不足');
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

    test('无模板的类型只判蓝 / 红（IC 即使参数碰巧一致也不给绿黄）', () {
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

    test('二极管：反向耐压 + 封装一致，正向电流达标即绿', () {
      final result = BomMatcher.match(
        const ParsedBomRow(
          designator: 'D4, D5',
          comment: '1N5819HW-7-F',
          footprint: 'SOD-123_L2.7-W1.6-LS3.7-RD',
          quantity: 4,
        ),
        [
          material(
            package: 'SOD-123',
            params: const [
              ParamEntry('反向耐压', '40V'),
              ParamEntry('正向电流(If)', '3A'),
            ],
          ),
        ],
        bomParams: const [
          ParamEntry('反向耐压', '40V'),
          ParamEntry('正向电流', '1A'),
        ],
      );
      expect(result.status, MatchStatus.green);
      expect(result.reason, '反向耐压 + 封装一致，正向电流达标');
    });

    test('二极管：只有核心参数一致 → 黄，并说明缺哪一侧', () {
      final result = BomMatcher.match(
        const ParsedBomRow(
          designator: 'D1',
          comment: 'LESD5D5.0CT1G',
          footprint: 'SOD-523_L1.2-W0.8-LS1.6-BI',
          quantity: 3,
        ),
        [
          material(
            package: 'SOD-523',
            params: const [ParamEntry('反向耐压', '5V')],
          ),
        ],
        bomParams: const [
          ParamEntry('反向耐压', '5V'),
          ParamEntry('正向电流', '1A'),
        ],
      );
      expect(result.status, MatchStatus.yellow);
      expect(result.reason, '核心参数一致 · 库中料未记正向电流');
    });

    test('电感：电感值 + 封装一致，额定电流达标即绿', () {
      final result = BomMatcher.match(
        const ParsedBomRow(
          designator: 'L2',
          comment: 'CBW160808U121T',
          footprint: 'L0603',
          quantity: 1,
        ),
        [
          material(
            package: '0603',
            params: const [
              ParamEntry('电感值', '4.7uH'),
              ParamEntry('额定电流', '2A'),
            ],
          ),
        ],
        bomParams: const [
          ParamEntry('电感值', '4.7uH'),
          ParamEntry('额定电流', '1.5A'),
        ],
      );
      expect(result.status, MatchStatus.green);
    });

    test('磁珠：按阻抗@100MHz 判核心参数，频率不会被当成电感/电流', () {
      final result = BomMatcher.match(
        const ParsedBomRow(
          designator: 'FB1',
          comment: '120Ω@100MHz',
          footprint: '0603',
          quantity: 2,
        ),
        [
          material(
            package: '0603',
            params: const [
              ParamEntry('阻抗@100MHz', '120Ω'),
              ParamEntry('额定电流', '500mA'),
            ],
          ),
        ],
      );
      expect(result.status, MatchStatus.yellow);
      expect(result.reason, '核心参数一致 · BOM 未标额定电流');
    });

    test('模板优先级：库中料按子类名判类型，优先于 BOM 位号', () {
      final result = BomMatcher.match(
        const ParsedBomRow(
          designator: 'C1',
          comment: '4.7uH',
          footprint: 'C0603',
          quantity: 1,
        ),
        [
          material(
            category: '贴片电感',
            package: '0603',
            params: const [
              ParamEntry('电感值', '4.7uH'),
              ParamEntry('额定电流', '2A'),
            ],
          ),
        ],
        bomParams: const [
          ParamEntry('电感值', '4.7uH'),
          ParamEntry('额定电流', '1.5A'),
        ],
      );
      expect(result.status, MatchStatus.green);
    });

    test('模板判定：子类名关键词覆盖 PRD 表里的类型', () {
      expect(BomMatcher.templateFromCategory('贴片电容(MLCC)')?.label, '电容');
      expect(BomMatcher.templateFromCategory('贴片电阻')?.label, '电阻');
      expect(BomMatcher.templateFromCategory('功率电感')?.label, '电感');
      expect(BomMatcher.templateFromCategory('贴片磁珠')?.label, '磁珠');
      expect(BomMatcher.templateFromCategory('肖特基二极管')?.label, '二极管');
      expect(BomMatcher.templateFromCategory('稳压二极管')?.label, '稳压二极管');
      expect(BomMatcher.templateFromCategory('TVS/ESD')?.label, 'TVS/ESD');
      expect(BomMatcher.templateFromCategory('无源晶振')?.label, '晶振');
      expect(BomMatcher.templateFromCategory('自恢复保险丝')?.label, '保险丝');
      // 无模板 → 只判蓝/红
      expect(BomMatcher.templateFromCategory('MCU'), isNull);
      expect(BomMatcher.templateFromCategory('板对板连接器'), isNull);
      expect(BomMatcher.templateFromCategory('未分类'), isNull);
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
      expect(result.candidates.first.material.lcscCode, 'C2');
    });

    test('绿：耐压由 C 编号查回的立创参数补齐', () {
      // BOM Comment 只有 4.7uF（没耐压），靠 C6119856 查回的 25V 才判得出绿
      final result = BomMatcher.match(
        const ParsedBomRow(
          designator: 'C13, C14, C20, C22, C28',
          comment: '4.7uF',
          footprint: 'C0603',
          mpn: 'CGA0603X5R475K250JT',
          manufacturer: 'HRE(芯声)',
          lcscCode: 'C6119856',
          quantity: 5,
        ),
        [
          material(
            code: 'C69335',
            package: '0603',
            params: const [
              ParamEntry('容值', '4.7uF'),
              ParamEntry('额定电压', '25V'),
            ],
          ),
        ],
        bomParams: const [
          ParamEntry('容值', '4.7uF'),
          ParamEntry('精度', '±10%'),
          ParamEntry('额定电压', '25V'),
          ParamEntry('温度系数', 'X5R'),
        ],
      );
      expect(result.status, MatchStatus.green);
      expect(result.reason, '容值 + 封装一致，耐压达标');
    });

    test('绿：电阻功率由立创参数补齐', () {
      final result = BomMatcher.match(
        const ParsedBomRow(
          designator: 'R1, R2',
          comment: '5.1kΩ',
          footprint: 'R0402',
          quantity: 2,
        ),
        [
          material(
            package: '0402',
            params: const [
              ParamEntry('阻值', '5.1kΩ'),
              ParamEntry('功率', '62.5mW'),
            ],
          ),
        ],
        bomParams: const [
          ParamEntry('阻值', '5.1kΩ'),
          ParamEntry('功率', '62.5mW'),
        ],
      );
      expect(result.status, MatchStatus.green);
    });

    test('黄会说明原因：BOM 未标耐压 / 库中料未记耐压', () {
      const row = ParsedBomRow(
        designator: 'C1',
        comment: '100nF',
        footprint: 'C0603',
        quantity: 12,
      );
      final noBomVoltage = BomMatcher.match(row, [
        material(
          package: '0603',
          params: const [ParamEntry('容值', '100nF'), ParamEntry('耐压', '50V')],
        ),
      ]);
      expect(noBomVoltage.status, MatchStatus.yellow);
      expect(noBomVoltage.reason, '核心参数一致 · BOM 未标耐压');

      final noMaterialVoltage = BomMatcher.match(
        row,
        [
          material(
            package: '0603',
            params: const [ParamEntry('容值', '100nF')],
          ),
        ],
        bomParams: const [ParamEntry('额定电压', '50V')],
      );
      expect(noMaterialVoltage.status, MatchStatus.yellow);
      expect(noMaterialVoltage.reason, '核心参数一致 · 库中料未记耐压');
    });
  });

  group('F10.1 C 编号参数补全', () {
    test('只挑电容缺耐压 / 电阻缺功率且带 C 编号的行', () {
      final codes = BomEnricher.codesNeedingParams(const [
        ParsedBomRow(
          designator: 'C1',
          comment: '100nF',
          footprint: 'C0603',
          lcscCode: 'C6119867',
        ),
        // Comment 里已写耐压，不用查
        ParsedBomRow(
          designator: 'C2',
          comment: '100nF 50V',
          footprint: 'C0603',
          lcscCode: 'C111111',
        ),
        ParsedBomRow(
          designator: 'R1',
          comment: '10kΩ',
          footprint: 'R0603',
          lcscCode: 'C2906982',
        ),
        // 已写功率，不用查
        ParsedBomRow(
          designator: 'R2',
          comment: '10kΩ 0.1W',
          footprint: 'R0603',
          lcscCode: 'C222222',
        ),
        // 无模板（IC/连接器…）只判蓝/红，不必查
        ParsedBomRow(
          designator: 'U1',
          comment: 'CH340N',
          footprint: 'SOP-8',
          lcscCode: 'C2977777',
        ),
        // 二极管：Comment 是 MPN，核心/重要参数都取不到 → 要查
        ParsedBomRow(
          designator: 'D4',
          comment: '1N5819HW-7-F',
          footprint: 'SOD-123_L2.7-W1.6-LS3.7-RD',
          lcscCode: 'C82544',
        ),
        // 磁珠：Comment 里已有阻抗，但缺额定电流 → 要查
        ParsedBomRow(
          designator: 'FB1',
          comment: '120Ω@100MHz',
          footprint: '0603',
          lcscCode: 'C333333',
        ),
        // 没 C 编号，查不了
        ParsedBomRow(designator: 'C3', comment: '1uF', footprint: 'C0603'),
      ]);
      expect(codes, {'C6119867', 'C2906982', 'C82544', 'C333333'});
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
        columns.containsAll([
          'match_status',
          'matched_material_id',
          'checked',
          'params_json',
        ]),
        isTrue,
        reason: 'bom_items 缺少 F10.5 要求的字段：$columns',
      );
    });

    test('比对结果、勾选、立创参数可持久化', () async {
      await BomRepository.insertItems([
        BomItem(
          bomProjectId: projectId,
          designator: 'C1',
          comment: '100nF',
          quantity: 12,
          params: const [
            ParamEntry('容值', '100nF'),
            ParamEntry('额定电压', '50V'),
          ],
          matchStatus: MatchStatus.yellow,
          checked: true,
        ),
      ]);
      var items = await BomRepository.items(projectId);
      expect(items.length, 1);
      expect(items.first.matchStatus, MatchStatus.yellow);
      expect(items.first.checked, isTrue);
      expect(items.first.params.length, 2);
      expect(items.first.params.last.v, '50V');

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
      // 参数不因更新比对结果而丢失
      expect(items.first.params.length, 2);

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
