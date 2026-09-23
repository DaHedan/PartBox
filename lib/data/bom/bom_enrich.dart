import '../lcsc/lcsc_service.dart';
import '../models.dart';
import 'bom_matcher.dart';
import 'bom_parser.dart';

/// F10.1 参数补全。
///
/// 嘉立创 BOM 的 Comment 往往只写 `4.7uF` / `10kΩ`，没有耐压、功率，而
/// 「重要参数全一致」要拿 BOM 原料的耐压/功率与库存料比。BOM 里带着原料的
/// C 编号，按它查回立创参数即可补齐，不必因为 Comment 少写就一律降级成黄。
class BomEnricher {
  const BomEnricher._();

  /// 需要补参数的 C 编号：电容缺耐压、电阻缺功率，且 Comment/Value 里没写。
  /// 非 RLC（IC、连接器、二极管…）只判蓝/红，不用查。
  static Set<String> codesNeedingParams(List<ParsedBomRow> rows) {
    final codes = <String>{};
    for (final row in rows) {
      final code = row.lcscCode.trim().toUpperCase();
      if (code.isEmpty) continue;
      switch (BomMatcher.kindOf(row.designator)) {
        case BomPartKind.capacitor:
          if (_missing(row.comment, row.value, extractVoltageV)) codes.add(code);
        case BomPartKind.resistor:
          if (_missing(row.comment, row.value, extractPowerW)) codes.add(code);
        case BomPartKind.other:
          break;
      }
    }
    return codes;
  }

  static bool _missing(
    String comment,
    String value,
    double? Function(String) extract,
  ) =>
      extract(comment) == null && extract(value) == null;

  /// 并发查立创（默认 4 路），返回 code → 参数表。
  /// 单条失败直接跳过：该行退化为只按 Comment 判定，不阻塞导入。
  static Future<Map<String, List<ParamEntry>>> fetchParams(
    Set<String> codes, {
    String apiKey = '',
    int concurrency = 4,
    void Function(int done, int total)? onProgress,
  }) async {
    final result = <String, List<ParamEntry>>{};
    final list = codes.toList(growable: false);
    if (list.isEmpty) return result;

    var cursor = 0;
    var done = 0;

    Future<void> worker() async {
      while (true) {
        final index = cursor++;
        if (index >= list.length) return;
        final code = list[index];
        try {
          final res = await LcscService.query(code, apiKey: apiKey);
          final params = res.part?.params;
          if (params != null && params.isNotEmpty) result[code] = params;
        } catch (_) {
          // 查不到就保留原样。
        }
        done++;
        onProgress?.call(done, list.length);
      }
    }

    await Future.wait([for (var i = 0; i < concurrency; i++) worker()]);
    return result;
  }
}
