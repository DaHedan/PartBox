import 'dart:convert';

import '../bom/bom_parser.dart';
import '../models.dart';

/// 解析失败（文件不是嘉立创 iBOM，或结构漂移得太厉害）。
class IbomParseException implements Exception {
  const IbomParseException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// iBOM 物料级数据（对应 `comp_info` 的一条，键 = `C编号,值`）。
class IbomMaterial {
  const IbomMaterial({
    required this.key,
    required this.lcsc,
    required this.value,
    required this.mpn,
    required this.manufacturer,
    required this.footprint,
    required this.description,
    required this.qty,
    required this.params,
  });

  /// `comp_info` 的键，形如 `C6119867,100nF`。
  final String key;

  /// C 编号（`Supplier Part`）。
  final String lcsc;
  final String value;

  /// `Manufacturer Part`。
  final String mpn;
  final String manufacturer;

  /// `Supplier Footprint` / `lc_pkg`。
  final String footprint;

  /// `Description`，形如 `容值:100nF;精度:±10%;额定电压:50V;`。
  final String description;

  /// `q` 字段：该物料的用量。
  final int qty;

  /// 由 Description 拆出的参数（容值/额定电压/功率…），交给 F10 比对用。
  final Map<String, String> params;

  List<ParamEntry> get paramEntries => [
    for (final e in params.entries) ParamEntry(e.key, e.value),
  ];
}

/// iBOM 位号级数据（对应 `designator_info[0].top/bottom` 的一条）。
class IbomDesignator {
  const IbomDesignator({
    required this.designator,
    required this.materialKey,
    required this.layer,
    required this.x,
    required this.y,
    required this.angle,
    required this.bomIndex,
    required this.footprint,
    required this.comment,
  });

  /// 位号，如 `R8`。
  final String designator;

  /// 指向 [IbomMaterial.key]（iBOM 里叫 `lc_code`）。
  final String materialKey;

  /// `top` / `bottom`。
  final String layer;
  final double x;
  final double y;

  /// 角度（度）。
  final double angle;
  final int bomIndex;

  /// `ft_name`。
  final String footprint;

  /// `cm`：值。
  final String comment;

  bool get isBottom => layer == 'bottom';

  /// 转成 F10 的比对输入行。
  ParsedBomRow toBomRow(IbomMaterial? material) => ParsedBomRow(
    quantity: 1,
    designator: designator,
    comment: material?.value.isNotEmpty == true ? material!.value : comment,
    footprint: (material?.footprint.isNotEmpty == true
            ? material!.footprint
            : footprint)
        .toString(),
    value: material?.value ?? comment,
    mpn: material?.mpn ?? '',
    manufacturer: material?.manufacturer ?? '',
    lcscCode: material?.lcsc ?? '',
  );
}

/// 一次 iBOM 解析的完整结果。
class IbomData {
  const IbomData({required this.materials, required this.designators});

  final List<IbomMaterial> materials;
  final List<IbomDesignator> designators;

  int get topCount => designators.where((d) => !d.isBottom).length;
  int get bottomCount => designators.where((d) => d.isBottom).length;

  /// 位号 → 物料（先按 `C编号,值` 全键匹配，再退化到只按 C 编号）。
  IbomMaterial? materialOf(IbomDesignator designator) {
    for (final m in materials) {
      if (m.key == designator.materialKey) return m;
    }
    final code = lcscOf(designator.materialKey);
    if (code.isEmpty) return null;
    for (final m in materials) {
      if (m.lcsc == code) return m;
    }
    return null;
  }

  /// 从 `C6119867,100nF` 里取出 `C6119867`。
  static String lcscOf(String key) {
    final comma = key.indexOf(',');
    final head = comma < 0 ? key : key.substring(0, comma);
    final text = head.trim().toUpperCase();
    final match = RegExp(r'^C\d{3,}$').firstMatch(text);
    return match == null ? '' : text;
  }
}

/// F11.2：嘉立创 EDA 导出的 iBOM 单文件 HTML 解析。
///
/// 元件数据内嵌在 `window.files.bom_merge`，是**三层转义 JSON**：
/// `files.bom_merge`(字符串) → `{sum, data}` → `data`(字符串) →
/// `{file_info, check_info, comp_info, designator_info}`。
class IbomParser {
  const IbomParser._();

  /// 阻焊绿色（iBOM 内部 cfg 值）。绿板最常见，也和 iBOM 面板里显示的默认值一致。
  static const String solderMaskGreen = 'solder_mask_green';

  /// 焊盘喷锡（银色）。
  static const String padSilver = 'silver';

  static IbomData parse(String html) {
    final files = _decodeFiles(html);
    final mergeRaw = files['bom_merge'];
    if (mergeRaw is! String) {
      throw const IbomParseException('文件里没有 bom_merge，不像是嘉立创 iBOM');
    }
    final merge = _asMap(jsonDecode(mergeRaw), 'bom_merge');
    final dataRaw = merge['data'];
    if (dataRaw is! String) {
      throw const IbomParseException('bom_merge 里没有 data');
    }
    final data = _asMap(jsonDecode(dataRaw), 'data');

    return IbomData(
      materials: _parseMaterials(data['comp_info']),
      designators: _parseDesignators(data['designator_info']),
    );
  }

  /// 取 `window.files` 的 JSON 对象。
  static Map<String, dynamic> _decodeFiles(String html) {
    final marker = html.indexOf('window.files');
    if (marker < 0) {
      throw const IbomParseException('文件里没有 window.files，不是嘉立创 iBOM');
    }
    final brace = html.indexOf('{', marker);
    if (brace < 0) {
      throw const IbomParseException('window.files 结构异常');
    }
    final raw = extractJsonObject(html, brace);
    if (raw == null) {
      throw const IbomParseException('window.files 的 JSON 没有闭合');
    }
    return _asMap(jsonDecode(raw), 'window.files');
  }

  /// 从 [start] 处的 `{` 开始做**花括号配对**，跳过字符串内的括号与转义。
  ///
  /// 不能简单取到 `</script>`：`window.files` 之后紧跟 `window.__ENGING_OBJ_PRELOAD__`。
  static String? extractJsonObject(String text, int start) {
    if (start < 0 || start >= text.length || text[start] != '{') return null;
    var depth = 0;
    var inString = false;
    for (var i = start; i < text.length; i++) {
      final c = text[i];
      if (inString) {
        if (c == r'\') {
          i++;
        } else if (c == '"') {
          inString = false;
        }
        continue;
      }
      if (c == '"') {
        inString = true;
      } else if (c == '{') {
        depth++;
      } else if (c == '}') {
        depth--;
        if (depth == 0) return text.substring(start, i + 1);
      }
    }
    return null;
  }

  static Map<String, dynamic> _asMap(Object? value, String what) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.cast<String, dynamic>();
    throw IbomParseException('$what 不是对象');
  }

  static List<IbomMaterial> _parseMaterials(Object? compInfo) {
    if (compInfo is! Map) return const [];
    final result = <IbomMaterial>[];
    compInfo.forEach((key, value) {
      if (value is! Map) return;
      final map = value.cast<String, dynamic>();
      final description = _str(map['Description']);
      result.add(
        IbomMaterial(
          key: key.toString(),
          lcsc: _str(map['Supplier Part']).isNotEmpty
              ? _str(map['Supplier Part'])
              : IbomData.lcscOf(key.toString()),
          value: _firstNonEmpty([map['Value'], map['value'], map['Name']]),
          mpn: _str(map['Manufacturer Part']),
          manufacturer: _str(map['Manufacturer']),
          footprint: _firstNonEmpty([
            map['Supplier Footprint'],
            map['lc_pkg'],
          ]),
          description: description,
          qty: _int(map['q']),
          params: _parseDescription(description, map),
        ),
      );
    });
    return result;
  }

  /// `Description` 形如 `容值:100nF;精度:±10%;额定电压:50V;温度系数:X7R;`，
  /// 拆成键值对后正好能喂给 F10 的参数比对（别名就是立创这套参数名）。
  static Map<String, String> _parseDescription(
    String description,
    Map<String, dynamic> raw,
  ) {
    final params = <String, String>{};
    for (final part in description.split(';')) {
      final text = part.trim();
      if (text.isEmpty) continue;
      final colon = text.indexOf(':');
      if (colon <= 0) continue;
      final name = text.substring(0, colon).trim();
      final value = text.substring(colon + 1).trim();
      if (name.isEmpty || value.isEmpty) continue;
      params[name] = value;
    }
    // 兜底：Description 里没写全时，用独立字段补上。
    for (final entry in {
      '精度': raw['Tolerance'],
      '额定电压': raw['Voltage Rating'],
      '温度系数': raw['Temperature Coefficient'],
    }.entries) {
      final value = _str(entry.value);
      if (value.isNotEmpty && !params.containsKey(entry.key)) {
        params[entry.key] = value;
      }
    }
    return params;
  }

  static List<IbomDesignator> _parseDesignators(Object? designatorInfo) {
    if (designatorInfo is! List) return const [];
    final groups = <Map<String, dynamic>>[];
    for (final item in designatorInfo) {
      if (item is Map) groups.add(item.cast<String, dynamic>());
    }
    final result = <IbomDesignator>[];
    for (final group in groups) {
      for (final layer in const ['top', 'bottom']) {
        final list = group[layer];
        if (list is! List) continue;
        for (final entry in list) {
          if (entry is! Map) continue;
          final map = entry.cast<String, dynamic>();
          final designator = _str(map['des']);
          if (designator.isEmpty) continue;
          final ec = map['ec'];
          final model = map['model'];
          result.add(
            IbomDesignator(
              designator: designator,
              materialKey: _str(map['lc_code']),
              layer: layer,
              x: _double(ec is Map ? ec['x'] : null) ??
                  _double(model is Map ? model['x'] : null) ??
                  0,
              y: _double(ec is Map ? ec['y'] : null) ??
                  _double(model is Map ? model['y'] : null) ??
                  0,
              angle: _double(ec is Map ? ec['ang'] : null) ??
                  _double(model is Map ? model['rz'] : null) ??
                  0,
              bomIndex: _int(map['bom_index']),
              footprint: _str(map['ft_name']),
              comment: _str(map['cm']),
            ),
          );
        }
      }
    }
    return result;
  }

  /// 打开前改写 HTML：
  /// 1. 把 3D 板子初始成「阻焊绿 + 焊盘喷锡（银）」；
  /// 2. 强制视口宽度，让 Android 上也呈现电脑端布局（PRD 11.3）。
  ///
  /// iBOM 的板子材质正是读 `<meta name="solder-mask-material">` 与
  /// `<meta name="pad-material">` 的 content 作为初始值（见其
  /// `solder-mask-material` / `pad-material` 的 querySelector）。
  /// meta 一律插在 `<head>` 之后：文档里 `pad-material` 是被注释掉的，
  /// 而 querySelector 取**第一个**匹配，插最前面才一定生效。
  static String prepareHtml(
    String html, {
    String solderMask = solderMaskGreen,
    String pad = padSilver,
    int viewportWidth = 1280,
  }) {
    var out = html;
    final headPattern = RegExp('<head[^>]*>', caseSensitive: false);
    final head = headPattern.firstMatch(out);
    final metas =
        '<meta name="solder-mask-material" content="$solderMask">'
        '<meta name="pad-material" content="$pad">'
        '<meta name="viewport" '
        'content="width=$viewportWidth, initial-scale=1">';
    out = head == null
        ? '$metas$out'
        : out.replaceRange(head.end, head.end, metas);

    // 再把原有的同类 meta 一并改掉（文件里可能写成别的颜色），
    // 免得又出现「谁是第一个」的歧义。
    out = _rewriteMeta(out, 'solder-mask-material', solderMask);
    out = _rewriteMeta(out, 'pad-material', pad);
    return out;
  }

  /// 改掉**所有生效**的同类 meta（被 `<!-- -->` 注释掉的不动，改了也不生效），
  /// 免得文件里同时留着旧设置、给「谁是第一个」留歧义。
  static String _rewriteMeta(String html, String name, String content) {
    final tagPattern = RegExp(
      '<meta\\b[^>]*\\bname="${RegExp.escape(name)}"[^>]*>',
      caseSensitive: false,
    );
    final matches = tagPattern.allMatches(html).toList();
    if (matches.isEmpty) return html;
    final buffer = StringBuffer();
    var cursor = 0;
    for (final match in matches) {
      if (_insideComment(html, match.start)) continue;
      buffer
        ..write(html.substring(cursor, match.start))
        ..write('<meta name="$name" content="$content">');
      cursor = match.end;
    }
    if (cursor == 0) return html;
    buffer.write(html.substring(cursor));
    return buffer.toString();
  }

  /// [index] 处是否落在 `<!-- -->` 注释里。
  static bool _insideComment(String html, int index) {
    final open = html.lastIndexOf('<!--', index);
    if (open < 0) return false;
    final close = html.lastIndexOf('-->', index);
    return open > close;
  }

  static String _str(Object? value) => value?.toString().trim() ?? '';

  static String _firstNonEmpty(List<Object?> values) {
    for (final value in values) {
      final text = _str(value);
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  static int _int(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse(_str(value)) ?? 0;
  }

  static double? _double(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(_str(value));
  }
}
