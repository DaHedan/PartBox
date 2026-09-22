import '../models.dart';
import 'bom_parser.dart';

/// F10.2 四色比对 + 单位归一化。
///
/// 归一化口径：容值统一到 pF、阻值统一到 Ω、电压统一到 V、功率统一到 W、
/// 封装名去前缀字母（C0603/R0603 → 0603）；v2.1 数值严格相等，不做模糊匹配。
class BomMatcher {
  const BomMatcher._();

  /// 单行比对：返回四色状态与同色候选（按余量降序）。
  static BomMatchResult match(ParsedBomRow row, List<MaterialItem> materials) {
    final kind = kindOf(row.designator);
    final blue = <MaterialItem>[];
    final green = <MaterialItem>[];
    final yellow = <MaterialItem>[];

    for (final material in materials) {
      final blueReason = _blueReason(row, material);
      if (blueReason != null) {
        blue.add(material);
        continue;
      }
      if (kind == BomPartKind.other) continue;
      switch (_paramLevel(row, material, kind)) {
        case _Level.green:
          green.add(material);
        case _Level.yellow:
          yellow.add(material);
        case null:
          break;
      }
    }

    final List<MaterialItem> candidates;
    final String status;
    if (blue.isNotEmpty) {
      candidates = blue;
      status = MatchStatus.blue;
    } else if (green.isNotEmpty) {
      candidates = green;
      status = MatchStatus.green;
    } else if (yellow.isNotEmpty) {
      candidates = yellow;
      status = MatchStatus.yellow;
    } else {
      candidates = const [];
      status = MatchStatus.red;
    }

    final sorted = [...candidates]
      ..sort((a, b) => b.qtyRemaining.compareTo(a.qtyRemaining));
    return BomMatchResult(
      status: status,
      candidates: sorted,
      reason: switch (status) {
        MatchStatus.blue => _blueReason(row, sorted.first) ?? '完全一致',
        MatchStatus.green => '重要参数一致',
        MatchStatus.yellow => '核心参数一致',
        _ => '库中无匹配料',
      },
    );
  }

  /// 🔵 蓝：C 编号一致；或 MPN + 制造商一致。
  static String? _blueReason(ParsedBomRow row, MaterialItem material) {
    final code = row.lcscCode.trim().toUpperCase();
    final materialCode = (material.lcscCode ?? '').trim().toUpperCase();
    if (code.isNotEmpty && materialCode == code) return 'C 编号一致';

    final mpn = row.mpn.trim().toUpperCase();
    final materialMpn = (material.mpn ?? '').trim().toUpperCase();
    if (mpn.isEmpty || materialMpn != mpn) return null;

    final manufacturer = row.manufacturer.trim().toUpperCase();
    final materialManufacturer = materialManufacturerOf(material);
    if (manufacturer.isEmpty || materialManufacturer != manufacturer) {
      return null;
    }
    return 'MPN + 制造商一致';
  }

  /// 🟢/🟡：仅电容、电阻参与（PRD 10.2）。
  static _Level? _paramLevel(
    ParsedBomRow row,
    MaterialItem material,
    BomPartKind kind,
  ) {
    final bomPackage = normalizePackage(row.footprint);
    if (bomPackage.isEmpty) return null;
    if (bomPackage != materialPackage(material)) return null;

    if (kind == BomPartKind.capacitor) {
      final bomValue = extractCapacitancePf(row.comment) ??
          extractCapacitancePf(row.value);
      final materialValue = materialCapacitancePf(material);
      if (bomValue == null || materialValue == null) return null;
      if (!_eq(bomValue, materialValue)) return null;

      final bomVoltage =
          extractVoltageV(row.comment) ?? extractVoltageV(row.value);
      final materialVoltage = materialVoltageV(material);
      final voltageMatched = bomVoltage != null &&
          materialVoltage != null &&
          _eq(bomVoltage, materialVoltage);
      return voltageMatched ? _Level.green : _Level.yellow;
    }

    final bomValue =
        extractResistanceOhm(row.comment) ?? extractResistanceOhm(row.value);
    final materialValue = materialResistanceOhm(material);
    if (bomValue == null || materialValue == null) return null;
    if (!_eq(bomValue, materialValue)) return null;

    final bomPower = extractPowerW(row.comment) ?? extractPowerW(row.value);
    final materialPower = materialPowerW(material);
    final powerMatched =
        bomPower != null && materialPower != null && _eq(bomPower, materialPower);
    return powerMatched ? _Level.green : _Level.yellow;
  }

  /// 元件类型：仅识别 C（电容）与 R（电阻），其余按非 RLC 处理（只判蓝/红）。
  static BomPartKind kindOf(String designator) {
    final text = designator.trim();
    if (text.isEmpty) return BomPartKind.other;
    final match = RegExp(r'^[A-Za-z]+').firstMatch(text);
    if (match == null) return BomPartKind.other;
    switch (match.group(0)!.toUpperCase()) {
      case 'C':
        return BomPartKind.capacitor;
      case 'R':
        return BomPartKind.resistor;
      default:
        return BomPartKind.other;
    }
  }
}

enum BomPartKind { capacitor, resistor, other }

enum _Level { green, yellow }

/// 一行比对结果。
class BomMatchResult {
  const BomMatchResult({
    required this.status,
    required this.candidates,
    required this.reason,
  });

  final String status;
  final List<MaterialItem> candidates;
  final String reason;
}

/// 库中料的制造商：优先参数表，回落 brand 字段。
String materialManufacturerOf(MaterialItem material) {
  final raw = paramOf(material, ['制造商', '厂家', 'manufacturer', 'mfr']) ??
      material.brand;
  return (raw ?? '').trim().toUpperCase();
}

/// 按参数名取库中料参数值（键名不区分大小写）。
String? paramOf(MaterialItem material, List<String> keys) {
  for (final param in material.params) {
    final key = param.k.trim().toLowerCase();
    if (!keys.any((k) => k.toLowerCase() == key)) continue;
    final value = param.v.trim();
    if (value.isNotEmpty) return value;
  }
  return null;
}

/// 库中料容值（pF）：参数表优先，回落物料名。
double? materialCapacitancePf(MaterialItem material) =>
    extractCapacitancePf(
      paramOf(material, ['容值', '电容值', 'capacitance', 'cap']),
    ) ??
    extractCapacitancePf(material.name);

/// 库中料阻值（Ω）：参数表优先，回落物料名。
double? materialResistanceOhm(MaterialItem material) =>
    extractResistanceOhm(paramOf(material, ['阻值', '电阻值', 'resistance', 'res'])) ??
    extractResistanceOhm(material.name);

/// 库中料耐压（V）。
double? materialVoltageV(MaterialItem material) {
  final raw = paramOf(material, ['耐压', '额定电压', '电压', 'voltage', 'vrating']);
  return parseVoltageV(raw) ?? extractVoltageV(raw);
}

/// 库中料功率（W）。
double? materialPowerW(MaterialItem material) {
  final raw = paramOf(material, ['功率', 'power', 'wattage']);
  return parsePowerW(raw) ?? extractPowerW(raw);
}

/// 库中料封装（归一化）。
String materialPackage(MaterialItem material) => normalizePackage(
  paramOf(material, ['封装', 'package', 'footprint']) ?? material.package,
);

/// 容值 → pF：`100nF`=100000、`0.1uF`=100000、`4.7uF`=4700000、`100000pF`=100000。
double? parseCapacitancePf(String? text) {
  final parsed = _numeric(text);
  if (parsed == null) return null;
  switch (parsed.suffix.toLowerCase().replaceAll('μ', 'u').replaceAll('µ', 'u')) {
    case '':
    case 'f':
      return parsed.value * 1e12;
    case 'pf':
      return parsed.value;
    case 'nf':
      return parsed.value * 1e3;
    case 'uf':
      return parsed.value * 1e6;
    case 'mf':
      return parsed.value * 1e9;
  }
  return null;
}

/// 阻值 → Ω：`10kΩ`=10000、`4.7k`=4700、`10Ω`=10、`4R7`=4.7、`1M`=1e6。
double? parseResistanceOhm(String? text) {
  final parsed = _numeric(text);
  if (parsed == null) return null;
  final suffix = parsed.suffix
      .replaceAll(RegExp('ohm', caseSensitive: false), '')
      .replaceAll('Ω', '')
      .replaceAll(RegExp(r'^[Rr]$'), '');
  switch (suffix) {
    case '':
      return parsed.value;
    case 'm':
      return parsed.value * 1e-3;
    case 'k':
    case 'K':
      return parsed.value * 1e3;
    case 'M':
      return parsed.value * 1e6;
    case 'G':
      return parsed.value * 1e9;
  }
  return null;
}

/// 电压 → V：`50V`=50、`100mV`=0.1、`6.3V`=6.3。
double? parseVoltageV(String? text) {
  final parsed = _numeric(text);
  if (parsed == null) return null;
  switch (parsed.suffix.toLowerCase()) {
    case '':
    case 'v':
      return parsed.value;
    case 'mv':
      return parsed.value * 1e-3;
    case 'kv':
      return parsed.value * 1e3;
  }
  return null;
}

/// 功率 → W：`0.1W`=0.1、`100mW`=0.1。
double? parsePowerW(String? text) {
  final parsed = _numeric(text);
  if (parsed == null) return null;
  switch (parsed.suffix.toLowerCase()) {
    case '':
    case 'w':
      return parsed.value;
    case 'mw':
      return parsed.value * 1e-3;
    case 'kw':
      return parsed.value * 1e3;
  }
  return null;
}

/// 从 `100nF 50V`、`4.7uF/16V` 这类文本里挑出容值（只认带单位的写法）。
double? extractCapacitancePf(String? text) =>
    _findByParser(text, parseCapacitancePf);

/// 从 `5.1kΩ 1%`、`10kΩ 0.1W` 这类文本里挑出阻值（只认带单位的写法）。
double? extractResistanceOhm(String? text) =>
    _findByParser(text, parseResistanceOhm);

/// 从 `100nF 50V`、`4.7uF/16V` 这类文本里挑出电压数值。
double? extractVoltageV(String? text) => _findUnit(
  text,
  parseVoltageV,
  const {'v', 'mv', 'kv'},
);

/// 从 `10kΩ 0.1W` 这类文本里挑出功率数值。
double? extractPowerW(String? text) =>
    _findUnit(text, parsePowerW, const {'w', 'mw', 'kw'});

/// 逐 token 试解析：要求 token 带单位后缀，避免把「100」这类裸数字当数值。
double? _findByParser(String? text, double? Function(String) parse) {
  for (final token in _tokens(text)) {
    final parsed = _numeric(token);
    if (parsed == null || parsed.suffix.isEmpty) continue;
    final value = parse(token);
    if (value != null) return value;
  }
  return null;
}

/// 在文本里找「带指定单位后缀」的 token 并解析成数值。
double? _findUnit(
  String? text,
  double? Function(String) parse,
  Set<String> suffixes,
) {
  for (final token in _tokens(text)) {
    final parsed = _numeric(token);
    if (parsed == null || parsed.suffix.isEmpty) continue;
    if (!suffixes.contains(parsed.suffix.toLowerCase())) continue;
    final value = parse(token);
    if (value != null) return value;
  }
  return null;
}

/// 按分隔符切 token（保留单位符号与小数点）。
List<String> _tokens(String? text) {
  final raw = (text ?? '').trim();
  if (raw.isEmpty) return const [];
  return raw
      .split(RegExp(r'[^A-Za-z0-9.µμΩ]+'))
      .where((token) => token.isNotEmpty)
      .toList();
}

/// 封装名归一化：去前缀字母（C0603/R0603/L0603 → 0603）。
String normalizePackage(String? text) {
  final upper = (text ?? '').trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
  if (upper.isEmpty) return '';
  final match = RegExp(r'^[A-Z]{1,2}(\d{3,5})$').firstMatch(upper);
  return match?.group(1) ?? upper;
}

/// `数值 + 单位后缀`。
class _Num {
  const _Num(this.value, this.suffix);

  final double value;
  final String suffix;
}

/// 解析 `4.7k`、`4k7`、`100nF`、`0.1u`、`10` 这类写法。
_Num? _numeric(String? text) {
  final raw = (text ?? '').trim();
  if (raw.isEmpty) return null;
  // 4k7 / 4R7 / 1n5：数字 + 单位 + 数字
  final mid = RegExp(r'^([0-9]+)([A-Za-zµμΩ])([0-9]+)$').firstMatch(raw);
  if (mid != null) {
    return _Num(
      double.parse('${mid.group(1)}.${mid.group(3)}'),
      mid.group(2)!,
    );
  }
  final match =
      RegExp(r'^([0-9]+(?:\.[0-9]+)?|\.[0-9]+)\s*([A-Za-zµμΩ]*)$').firstMatch(raw);
  if (match == null) return null;
  return _Num(double.parse(match.group(1)!), match.group(2)!);
}

/// 数值严格相等（容忍浮点换算误差）。
bool _eq(double a, double b) {
  final diff = (a - b).abs();
  final scale = a.abs() > b.abs() ? a.abs() : b.abs();
  return diff <= scale * 1e-9 + 1e-9;
}
