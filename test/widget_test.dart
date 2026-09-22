import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:partbox/data/app_database.dart';
import 'package:partbox/data/lcsc/lcsc_service.dart';
import 'package:partbox/data/models.dart';
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
}
