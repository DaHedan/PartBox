/// 立创包装袋标签二维码内容，形如：
/// `{on:SO26091528911,pc:C518789,pm:FDN338P,qty:10,mc:,cc:1,pdi:237147158,hp:11}`
class ScanPayload {
  const ScanPayload({this.code, this.mpn, this.qty, this.raw = ''});

  /// `pc`：C 编号（立创商品编号）
  final String? code;

  /// `pm`：原厂型号 MPN
  final String? mpn;

  /// `qty`：本包数量
  final double? qty;

  /// 原始扫码文本
  final String raw;
}

/// 解析立创袋标二维码：去掉首尾花括号 → 按逗号 split → 每段按**第一个**冒号分键值。
///
/// 容错：非 `{...}` 形式返回 null；缺字段、值为空的键（如 `mc:`）一律跳过。
ScanPayload? parseLcscLabel(String raw) {
  final text = raw.trim();
  final start = text.indexOf('{');
  final end = text.lastIndexOf('}');
  if (start < 0 || end <= start) return null;

  String? code;
  String? mpn;
  double? qty;

  for (final segment in text.substring(start + 1, end).split(',')) {
    final piece = segment.trim();
    final sep = piece.indexOf(':');
    if (sep <= 0) continue;
    final key = piece.substring(0, sep).trim().toLowerCase();
    final value = piece.substring(sep + 1).trim();
    if (value.isEmpty) continue;
    switch (key) {
      // pc → C 编号（从值里提取 C+数字，兼容带前缀的写法）
      case 'pc':
        code = RegExp(
          r'C\d{3,}',
          caseSensitive: false,
        ).firstMatch(value)?.group(0)?.toUpperCase();
      // pm → MPN
      case 'pm':
        mpn = value;
      // qty → 本包数量
      case 'qty':
        qty = _parseQty(value);
    }
  }
  if (code == null && mpn == null && qty == null) return null;
  return ScanPayload(code: code, mpn: mpn, qty: qty, raw: text);
}

/// 批次追溯码（如 `X237147158`）：用户扫错了码，应改扫标签上的二维码。
bool isBatchTraceCode(String raw) =>
    RegExp(r'^[Xx]\d{3,}$').hasMatch(raw.trim());

double? _parseQty(String value) {
  final match = RegExp(r'\d+(?:\.\d+)?').firstMatch(value);
  if (match == null) return null;
  final parsed = double.tryParse(match.group(0)!);
  if (parsed == null || parsed <= 0) return null;
  return parsed;
}
