import 'package:flutter_test/flutter_test.dart';
import 'package:partbox/data/lcsc/lcsc_service.dart';
import 'package:partbox/data/models.dart';
import 'package:partbox/utils/format.dart';

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
}
