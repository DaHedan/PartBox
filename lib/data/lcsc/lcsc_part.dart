import '../models.dart';

/// 立创 C 编号查询结果。
class LcscPart {
  const LcscPart({
    required this.code,
    required this.source,
    this.name,
    this.mpn,
    this.brand,
    this.package,
    this.description,
    this.categoryName,
    this.parentCategoryName,
    this.unit,
    this.unitPrice,
    this.imageUrls = const [],
    this.params = const [],
  });

  final String code;
  final String source;
  final String? name;
  final String? mpn;
  final String? brand;
  final String? package;
  final String? description;

  /// 立创分类（英文原始名，用于映射本地分类）。
  final String? categoryName;
  final String? parentCategoryName;
  final String? unit;
  final double? unitPrice;
  final List<String> imageUrls;
  final List<ParamEntry> params;

  String? get firstImageUrl => imageUrls.isEmpty ? null : imageUrls.first;
}

/// 查询结果（成功 / 失败原因）。
class LcscResult {
  const LcscResult({this.part, this.code, this.error});

  final LcscPart? part;
  final String? code;
  final String? error;

  bool get success => part != null;

  static LcscResult ok(LcscPart part) => LcscResult(part: part);

  static LcscResult fail(String error, {String? code}) =>
      LcscResult(error: error, code: code);
}
