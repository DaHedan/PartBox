import 'package:flutter_test/flutter_test.dart';
import 'package:partbox/data/lcsc/lcsc_service.dart';
import 'package:partbox/data/models.dart';
import 'package:partbox/utils/format.dart';
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
}
