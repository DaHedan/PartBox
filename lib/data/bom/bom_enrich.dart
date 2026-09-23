import '../lcsc/lcsc_service.dart';
import '../models.dart';
import 'bom_matcher.dart';
import 'bom_parser.dart';

/// F10.1 参数补全。
///
/// 嘉立创 BOM 的 Comment 往往只写 `4.7uF` / `10kΩ` / 直接是 MPN，缺耐压、电流
/// 这类"重要参数"，而绿门槛要拿它跟库存料比。BOM 里带着原料的 C 编号，按它查回
/// 立创参数即可补齐，不必因为 Comment 少写就一律降级。
class BomEnricher {
  const BomEnricher._();

  /// 需要补参数的 C 编号：有比对模板，但 Comment/Value 里取不到
  /// 核心参数或重要参数的行。
  static Set<String> codesNeedingParams(List<ParsedBomRow> rows) {
    final codes = <String>{};
    for (final row in rows) {
      final code = row.lcscCode.trim().toUpperCase();
      if (code.isEmpty) continue;
      // BOM 侧只有位号能判类型；无模板（IC、连接器、开关…）只判蓝/红，不必查。
      final template = BomMatcher.templateFromDesignator(row.designator);
      if (template == null) continue;

      final hasCore = _found(row, template.coreParse);
      final hasImportant = _found(row, template.importantParse);
      if (!hasCore || !hasImportant) codes.add(code);
    }
    return codes;
  }

  static bool _found(ParsedBomRow row, double? Function(String?) parse) =>
      parse(row.comment) != null || parse(row.value) != null;

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
