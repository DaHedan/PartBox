import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart';
import 'lcsc_part.dart';

/// 立创 C 编号查询：三级数据源，逐级降级。
///
/// 1. 立创开放平台商品接口（需在设置页配置密钥，优先）；
/// 2. 公开 JSON 接口（免鉴权）：立创商品详情接口，参数最全；
/// 3. 公开 JSON 接口（免鉴权）：jlcsearch；
/// 全部失败 → 调用方转手动模式，保留已填 C 编号。
class LcscService {
  const LcscService._();

  static const Duration _timeout = Duration(seconds: 15);

  /// 立创开放平台（需密钥）。若接口签名规则调整，仅需改这一处。
  static const String openPlatformEndpoint =
      'https://openapi.szlcsc.com/openapi/product/detail';

  /// 立创商品详情公开 JSON 接口（免鉴权，含参数表与图片）。
  static const String lcscWebEndpoint =
      'https://wmsc.lcsc.com/ftps/wm/product/detail';

  /// jlcsearch 公开 JSON 接口（免鉴权，兜底）。
  static const String jlcSearchEndpoint =
      'https://jlcsearch.tscircuit.com/components/list.json';

  static const Map<String, String> _webHeaders = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
    'Referer': 'https://www.lcsc.com/',
    'Accept': 'application/json, text/plain, */*',
  };

  /// 从任意文本（含扫码原文）中提取首个 C 编号。
  static String? normalizeCode(String text) {
    final match = RegExp(r'C\d{3,}').firstMatch(text.toUpperCase());
    return match?.group(0);
  }

  static Future<LcscResult> query(String input, {String apiKey = ''}) async {
    final code = normalizeCode(input);
    if (code == null) {
      return LcscResult.fail('未识别到 C 编号（形如 C106248）');
    }
    final errors = <String>[];

    if (apiKey.trim().isNotEmpty) {
      try {
        final part = await _fromOpenPlatform(code, apiKey.trim());
        if (part != null) return LcscResult.ok(part);
        errors.add('立创开放平台：未找到 $code');
      } catch (e) {
        errors.add('立创开放平台：${_brief(e)}');
      }
    }

    try {
      final part = await _fromLcscWeb(code);
      if (part != null) return LcscResult.ok(part);
      errors.add('立创商品接口：未找到 $code');
    } catch (e) {
      errors.add('立创商品接口：${_brief(e)}');
    }

    try {
      final part = await _fromJlcSearch(code);
      if (part != null) return LcscResult.ok(part);
      errors.add('公开数据源：未找到 $code');
    } catch (e) {
      errors.add('公开数据源：${_brief(e)}');
    }

    return LcscResult.fail(errors.join('\n'), code: code);
  }

  static String _brief(Object error) {
    final text = error.toString();
    return text.length > 80 ? '${text.substring(0, 80)}…' : text;
  }

  static Map<String, dynamic> _decode(http.Response resp) {
    final body = utf8.decode(resp.bodyBytes, allowMalformed: true);
    final data = jsonDecode(body);
    if (data is! Map<String, dynamic>) {
      throw StateError('返回内容不是 JSON 对象');
    }
    return data;
  }

  /// 数据源 1：立创开放平台（需密钥）。
  static Future<LcscPart?> _fromOpenPlatform(String code, String apiKey) async {
    final uri = Uri.parse('$openPlatformEndpoint?productCode=$code');
    final resp = await http
        .get(uri, headers: {'appKey': apiKey, ..._webHeaders})
        .timeout(_timeout);
    if (resp.statusCode != 200) {
      throw StateError('HTTP ${resp.statusCode}');
    }
    final json = _decode(resp);
    final result = json['result'] ?? json;
    if (result is! Map) return null;
    final map = result.cast<String, dynamic>();
    if (map.isEmpty || map['productCode'] == null) return null;
    return _mapLcscProduct(map, code, '立创开放平台');
  }

  /// 数据源 2：立创商品详情公开接口（免鉴权）。
  static Future<LcscPart?> _fromLcscWeb(String code) async {
    final uri = Uri.parse('$lcscWebEndpoint?productCode=$code');
    final resp = await http.get(uri, headers: _webHeaders).timeout(_timeout);
    if (resp.statusCode != 200) {
      throw StateError('HTTP ${resp.statusCode}');
    }
    final json = _decode(resp);
    final result = json['result'];
    if (result is! Map) return null;
    final map = result.cast<String, dynamic>();
    if (map.isEmpty || map['productCode'] == null) return null;
    return _mapLcscProduct(map, code, '立创商品接口');
  }

  static LcscPart _mapLcscProduct(
    Map<String, dynamic> map,
    String code,
    String source,
  ) {
    final params = <ParamEntry>[];
    final rawParams = map['paramVOList'];
    if (rawParams is List) {
      final entries = rawParams.whereType<Map>();
      final sorted = entries.toList()
        ..sort((a, b) {
          final sa = (a['sort'] as num?)?.toInt() ?? 0;
          final sb = (b['sort'] as num?)?.toInt() ?? 0;
          return sa.compareTo(sb);
        });
      for (final raw in sorted) {
        final key = _firstNonEmpty([
          raw['paramName'],
          raw['paramNameEn'],
        ]);
        final value = _firstNonEmpty([
          raw['paramValue'],
          raw['paramValueEn'],
        ]);
        if (key != null && value != null) {
          params.add(ParamEntry(key, value));
        }
      }
    }

    final images = <String>[];
    final rawImages = map['productImages'];
    if (rawImages is List) {
      for (final item in rawImages) {
        if (item is String && item.trim().isNotEmpty) images.add(item.trim());
      }
    }

    double? unitPrice;
    final priceList = map['productPriceList'];
    if (priceList is List && priceList.isNotEmpty) {
      final first = priceList.first;
      if (first is Map) {
        final raw = first['productPrice'] ?? first['usdPrice'];
        if (raw is num) unitPrice = raw.toDouble();
        if (raw is String) unitPrice = double.tryParse(raw);
      }
    }

    return LcscPart(
      code: (map['productCode'] as String?) ?? code,
      source: source,
      name: _firstNonEmpty([map['productNameEn'], map['productModel']]),
      mpn: _firstNonEmpty([map['productModel'], map['productModelEn']]),
      brand: _firstNonEmpty([
        map['brandNameEn'],
        map['brandName'],
      ]),
      package: _firstNonEmpty([map['encapStandard'], map['encap']]),
      description: _firstNonEmpty([
        map['productDescEn'],
        map['productIntroEn'],
        map['productKeyAttributes'],
      ]),
      categoryName: _firstNonEmpty([map['catalogName'], map['wmCatalogNameEn']]),
      parentCategoryName:
          _firstNonEmpty([map['parentCatalogName'], map['parentCatalogNameEn']]),
      unit: _firstNonEmpty([map['productUnit']]),
      unitPrice: unitPrice,
      imageUrls: images,
      params: params,
    );
  }

  /// 数据源 3：jlcsearch（免鉴权，字段较少，用描述反推参数）。
  static Future<LcscPart?> _fromJlcSearch(String code) async {
    final uri = Uri.parse('$jlcSearchEndpoint?search=$code');
    final resp = await http.get(uri, headers: _webHeaders).timeout(_timeout);
    if (resp.statusCode != 200) {
      throw StateError('HTTP ${resp.statusCode}');
    }
    final json = _decode(resp);
    final list = json['components'];
    if (list is! List || list.isEmpty) return null;

    final target = code.replaceAll(RegExp(r'[^0-9]'), '');
    Map<String, dynamic>? picked;
    for (final item in list) {
      if (item is! Map) continue;
      final map = item.cast<String, dynamic>();
      final lcsc = map['lcsc']?.toString() ?? '';
      if (lcsc == target) {
        picked = map;
        break;
      }
      picked ??= map;
    }
    if (picked == null) return null;

    final description = _firstNonEmpty([picked['description']]);
    return LcscPart(
      code: code,
      source: 'jlcsearch',
      name: _firstNonEmpty([picked['description'], picked['mfr']]),
      mpn: _firstNonEmpty([picked['mfr']]),
      package: _firstNonEmpty([picked['package']]),
      description: description,
      categoryName: _firstNonEmpty([picked['subcategory']]),
      parentCategoryName: _firstNonEmpty([picked['category']]),
      params: _inferParams(description),
    );
  }

  /// 从描述文本中反推关键参数（jlcsearch 无结构化参数表时使用）。
  static List<ParamEntry> _inferParams(String? description) {
    if (description == null || description.isEmpty) return const [];
    final text = description;
    final params = <ParamEntry>[];

    void grab(String label, String pattern) {
      final match = RegExp(pattern).firstMatch(text);
      if (match != null) params.add(ParamEntry(label, match.group(0)!));
    }

    grab('容感值/阻值', r'\d+(\.\d+)?\s*(uF|nF|pF|mF|uH|nH|mH|mΩ|Ω|Ω|KΩ|kΩ|MΩ|R|K|M)\b');
    grab('耐压', r'\d+(\.\d+)?\s*(kV|KV|V)\b');
    grab('精度', r'±\s*\d+(\.\d+)?%');
    grab('温度系数', r'\b(X7R|X5R|C0G|NP0|NPO|Y5V|X7S|X6S)\b');
    grab('功率', r'\d+(\.\d+)?\s*W\b');
    return params;
  }

  static String? _firstNonEmpty(List<Object?> candidates) {
    for (final candidate in candidates) {
      if (candidate is String) {
        final trimmed = candidate.trim();
        if (trimmed.isNotEmpty) return trimmed;
      } else if (candidate is num) {
        return candidate.toString();
      }
    }
    return null;
  }
}
