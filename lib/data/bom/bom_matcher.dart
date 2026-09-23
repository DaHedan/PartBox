import '../models.dart';
import 'bom_parser.dart';

/// F10.2 四色比对 + 单位归一化 + 参数比对模板。
///
/// 归一化口径：容值→pF、阻值/阻抗→Ω、电感→H、电压→V、电流→A、功率→W、频率→Hz，
/// 封装名去前缀字母与尺寸后缀（C0603 → 0603、SOD-123_L2.7-W1.6 → SOD-123）；
/// v2.1 数值严格相等为一致，不做模糊匹配。
class BomMatcher {
  const BomMatcher._();

  /// 单行比对：返回四色状态与同色候选（按余量降序）。
  ///
  /// [bomParams] 是按 BOM 里的 C 编号查回的原料参数：嘉立创 BOM 的 Comment
  /// 常只写 `4.7uF`，没有耐压，靠它补齐才能判断"重要参数一致"。
  static BomMatchResult match(
    ParsedBomRow row,
    List<MaterialItem> materials, {
    List<ParamEntry> bomParams = const [],
  }) {
    final side = _BomSide(row, bomParams);
    final blue = <BomMatchCandidate>[];
    final green = <BomMatchCandidate>[];
    final yellow = <BomMatchCandidate>[];

    for (final material in materials) {
      final blueReason = _blueReason(row, material);
      if (blueReason != null) {
        blue.add(BomMatchCandidate(material, blueReason));
        continue;
      }
      // 模板：库中料按子类名匹配（PRD 10.2），判不出时回落到 BOM 位号前缀。
      // 两边都判不出类型 → 没有模板 → 只判蓝/红。
      final template = templateOf(material, row.designator);
      if (template == null) continue;

      final grade = _grade(side, material, template);
      if (grade == null) continue;
      switch (grade.level) {
        case _Level.green:
          green.add(BomMatchCandidate(material, grade.reason));
        case _Level.yellow:
          yellow.add(BomMatchCandidate(material, grade.reason));
      }
    }

    final List<BomMatchCandidate> best;
    final String status;
    if (blue.isNotEmpty) {
      best = blue;
      status = MatchStatus.blue;
    } else if (green.isNotEmpty) {
      best = green;
      status = MatchStatus.green;
    } else if (yellow.isNotEmpty) {
      best = yellow;
      status = MatchStatus.yellow;
    } else {
      best = const [];
      status = MatchStatus.red;
    }

    final sorted = [...best]
      ..sort((a, b) =>
          b.material.qtyRemaining.compareTo(a.material.qtyRemaining));
    return BomMatchResult(status: status, candidates: sorted);
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

  /// 🟢/🟡：按模板比对；返回 null 表示不匹配（红）。
  static _Grade? _grade(
    _BomSide side,
    MaterialItem material,
    BomTemplate template,
  ) {
    final package = side.package;
    if (package.isEmpty || package != materialPackage(material)) return null;

    // 核心参数：必须两侧都取到且严格相等（黄门槛）。
    final bomCore = side.coreValue(template);
    final materialCore = materialValue(
      material,
      template.coreKeys,
      template.coreParse,
      allowNameFallback: true,
    );
    if (bomCore == null || materialCore == null) return null;
    if (!_eq(bomCore, materialCore)) return null;

    // 重要参数：耐压/电流这类「不小于即可」的参数，库存 ≥ 需求就达标。
    // 这里不回落到物料名：名字里猜出来的耐压容易误判成绿，宁可保守降为黄。
    final bomImportant = side.importantValue(template);
    final materialImportant =
        materialValue(material, template.importantKeys, template.importantParse);
    if (_sufficient(bomImportant, materialImportant)) {
      return _Grade(
        _Level.green,
        '${template.coreLabel} + 封装一致，${template.importantLabel}达标',
      );
    }
    return _Grade(
      _Level.yellow,
      '核心参数一致 · '
      '${_shortReason(template.importantLabel, bomImportant, materialImportant)}',
    );
  }

  /// 耐压、电流、功率这类参数「不小于即可」：库存 ≥ BOM 需求就能替代。
  /// 容值、阻值、电感值、频率不适用（必须严格相等，已在上面卡住）。
  static bool _sufficient(double? bom, double? material) {
    if (bom == null || material == null) return false;
    return material > bom || _eq(bom, material);
  }

  /// 说明为什么没给绿：缺哪一侧，或者库存不够。
  static String _shortReason(String label, double? bom, double? material) {
    if (bom == null) return 'BOM 未标$label';
    if (material == null) return '库中料未记$label';
    return '库存$label不足';
  }

  /// 模板判定：库中料优先按**子类名**匹配（PRD 10.2），
  /// 判不出时回落到 **BOM 位号前缀**（库里没归类时也不会失效）。
  static BomTemplate? templateOf(MaterialItem material, String designator) =>
      templateFromCategory(material.categoryName) ??
      templateFromDesignator(designator);

  /// 按子类名关键词匹配模板。
  /// 顺序即优先级：「稳压」「TVS/ESD」要排在「二极管」前面，否则会被后者抢走。
  static BomTemplate? templateFromCategory(String? categoryName) {
    final name = _normalizeKeyword(categoryName);
    if (name.isEmpty) return null;
    for (final rule in _categoryRules) {
      if (name.contains(rule.$1)) return rule.$2;
    }
    return null;
  }

  /// 按位号前缀匹配模板（C1 → 电容、FB2 → 磁珠、ZD1 → 稳压二极管…）。
  static BomTemplate? templateFromDesignator(String designator) {
    final match = RegExp(r'^[A-Za-z]+').firstMatch(designator.trim());
    if (match == null) return null;
    switch (match.group(0)!.toUpperCase()) {
      case 'C':
        return bomTemplateCapacitor;
      case 'R':
        return bomTemplateResistor;
      case 'L':
        return bomTemplateInductor;
      case 'FB':
      case 'FL':
      case 'BEAD':
        return bomTemplateFerriteBead;
      case 'D':
        return bomTemplateDiode;
      case 'ZD':
      case 'Z':
      case 'DW':
        return bomTemplateZener;
      case 'TVS':
      case 'TV':
      case 'ES':
      case 'ESD':
        return bomTemplateTvs;
      case 'Y':
      case 'X':
      case 'XTAL':
      case 'OSC':
        return bomTemplateCrystal;
      case 'F':
      case 'FU':
      case 'FUSE':
        return bomTemplateFuse;
    }
    return null;
  }

  static String _normalizeKeyword(String? text) => (text ?? '')
      .toLowerCase()
      .replaceAll(RegExp(r'[\s_\-·:：/\\()（）,，]'), '');

  /// 子类名关键词 → 模板（顺序即优先级）。
  static const List<(String, BomTemplate)> _categoryRules = [
    ('磁珠', bomTemplateFerriteBead),
    ('稳压', bomTemplateZener),
    ('tvs', bomTemplateTvs),
    ('esd', bomTemplateTvs),
    ('静电', bomTemplateTvs),
    ('二极管', bomTemplateDiode),
    ('整流', bomTemplateDiode),
    ('肖特基', bomTemplateDiode),
    ('晶振', bomTemplateCrystal),
    ('晶体', bomTemplateCrystal),
    ('谐振', bomTemplateCrystal),
    ('保险', bomTemplateFuse),
    ('电感', bomTemplateInductor),
    ('电容', bomTemplateCapacitor),
    ('电阻', bomTemplateResistor),
  ];
}

enum _Level { green, yellow }

class _Grade {
  const _Grade(this.level, this.reason);

  final _Level level;
  final String reason;
}

/// BOM 侧取值：Comment/Value 文本优先，回落按 C 编号查回的立创参数。
class _BomSide {
  const _BomSide(this.row, this.params);

  final ParsedBomRow row;
  final List<ParamEntry> params;

  static const List<String> _packageKeys = ['封装', 'package', 'footprint'];

  double? coreValue(BomTemplate template) =>
      _value(template.coreKeys, template.coreParse);

  double? importantValue(BomTemplate template) =>
      _value(template.importantKeys, template.importantParse);

  double? _value(List<String> keys, double? Function(String?) parse) {
    for (final text in [row.comment, row.value, paramValue(params, keys)]) {
      final value = parse(text);
      if (value != null) return value;
    }
    return null;
  }

  String get package {
    final fromFootprint = normalizePackage(row.footprint);
    if (fromFootprint.isNotEmpty) return fromFootprint;
    return normalizePackage(paramValue(params, _packageKeys));
  }
}

/// 一行比对结果。
class BomMatchResult {
  const BomMatchResult({required this.status, required this.candidates});

  final String status;

  /// 同色候选，按余量降序；空表示无匹配（红）。
  final List<BomMatchCandidate> candidates;

  /// 首个候选的判定说明（用于列表直接展示）。
  String get reason =>
      candidates.isEmpty ? '库中无匹配料' : candidates.first.reason;
}

/// 一个候选匹配料 + 它为什么是这个颜色。
class BomMatchCandidate {
  const BomMatchCandidate(this.material, this.reason);

  final MaterialItem material;
  final String reason;
}

/// PRD 10.2 参数比对模板：核心参数（黄门槛）+ 重要参数（绿门槛）。
class BomTemplate {
  const BomTemplate({
    required this.label,
    required this.coreLabel,
    required this.coreKeys,
    required this.coreParse,
    required this.importantLabel,
    required this.importantKeys,
    required this.importantParse,
  });

  /// 类型名，如「电容」。
  final String label;

  /// 核心参数名，如「容值」。
  final String coreLabel;
  final List<String> coreKeys;
  final double? Function(String?) coreParse;

  /// 重要参数名，如「耐压」。
  final String importantLabel;
  final List<String> importantKeys;
  final double? Function(String?) importantParse;
}

/// 电容：容值 + 封装 → 绿门槛加耐压。
const BomTemplate bomTemplateCapacitor = BomTemplate(
  label: '电容',
  coreLabel: '容值',
  coreKeys: ['容值', '电容值', 'capacitance', 'cap'],
  coreParse: extractCapacitancePf,
  importantLabel: '耐压',
  importantKeys: ['耐压', '额定电压', '电压', 'voltage', 'vrating'],
  importantParse: extractVoltageV,
);

/// 电阻：阻值 + 封装 → 绿门槛加功率。
const BomTemplate bomTemplateResistor = BomTemplate(
  label: '电阻',
  coreLabel: '阻值',
  coreKeys: ['阻值', '电阻值', 'resistance', 'res'],
  coreParse: extractResistanceOhm,
  importantLabel: '功率',
  importantKeys: ['功率', '额定功率', 'power', 'wattage'],
  importantParse: extractPowerW,
);

/// 电感：电感值 + 封装 → 绿门槛加额定电流。
const BomTemplate bomTemplateInductor = BomTemplate(
  label: '电感',
  coreLabel: '电感值',
  coreKeys: ['电感值', '感值', '电感', 'inductance'],
  coreParse: extractInductanceH,
  importantLabel: '额定电流',
  importantKeys: ['额定电流', '额定电流(ir)', '电流', 'current', 'ir'],
  importantParse: extractCurrentA,
);

/// 磁珠：阻抗@100MHz + 封装 → 绿门槛加额定电流。
/// 立创的参数名是「阻抗@频率」，值为 `120Ω@100MHz`。
const BomTemplate bomTemplateFerriteBead = BomTemplate(
  label: '磁珠',
  coreLabel: '阻抗@100MHz',
  coreKeys: ['阻抗@频率', '阻抗', '阻抗@100MHz', '阻抗(100MHz)', 'impedance'],
  coreParse: extractImpedanceOhm,
  importantLabel: '额定电流',
  importantKeys: ['额定电流', '电流', 'current', 'ir'],
  importantParse: extractCurrentA,
);

/// 二极管（整流 / 肖特基 / 开关）：反向耐压 + 封装 → 绿门槛加正向电流。
const BomTemplate bomTemplateDiode = BomTemplate(
  label: '二极管',
  coreLabel: '反向耐压',
  coreKeys: [
    '反向耐压',
    '直流反向耐压',
    '反向电压',
    '最大反向电压',
    '耐压',
    'voltage',
  ],
  coreParse: extractVoltageV,
  importantLabel: '正向电流',
  importantKeys: [
    '正向电流',
    '平均整流电流',
    '正向平均电流',
    '整流电流',
    '电流',
    'current',
  ],
  importantParse: extractCurrentA,
);

/// 稳压二极管：稳压值 + 封装 → 绿门槛加功率。
const BomTemplate bomTemplateZener = BomTemplate(
  label: '稳压二极管',
  coreLabel: '稳压值',
  coreKeys: ['稳压值', '齐纳电压', '稳定电压', 'zener'],
  coreParse: extractVoltageV,
  importantLabel: '功率',
  importantKeys: ['功率', '耗散功率', '额定功率', 'power'],
  importantParse: extractPowerW,
);

/// TVS / ESD：击穿电压 VBR + 封装 → 绿门槛加峰值脉冲功率。
const BomTemplate bomTemplateTvs = BomTemplate(
  label: 'TVS/ESD',
  coreLabel: '击穿电压',
  coreKeys: ['击穿电压', '反向击穿电压', 'vbr', '反向电压'],
  coreParse: extractVoltageV,
  importantLabel: '峰值脉冲功率',
  importantKeys: ['峰值脉冲功率', '脉冲功率', '峰值功率', 'power'],
  importantParse: extractPowerW,
);

/// 晶振：频率 + 封装 → 绿门槛加负载电容。
const BomTemplate bomTemplateCrystal = BomTemplate(
  label: '晶振',
  coreLabel: '频率',
  coreKeys: ['频率', '标称频率', 'frequency'],
  coreParse: extractFrequencyHz,
  importantLabel: '负载电容',
  importantKeys: ['负载电容', '负载', 'loadcapacitance', 'cl'],
  importantParse: extractCapacitancePf,
);

/// 保险丝：额定电流 + 封装 → 绿门槛加额定电压。
const BomTemplate bomTemplateFuse = BomTemplate(
  label: '保险丝',
  coreLabel: '额定电流',
  coreKeys: ['额定电流', '电流', 'current'],
  coreParse: extractCurrentA,
  importantLabel: '额定电压',
  importantKeys: ['额定电压', '电压', 'voltage'],
  importantParse: extractVoltageV,
);

/// 库中料的制造商：优先参数表，回落 brand 字段。
String materialManufacturerOf(MaterialItem material) {
  final raw =
      paramValue(material.params, ['制造商', '厂家', 'manufacturer', 'mfr']) ??
          material.brand;
  return (raw ?? '').trim().toUpperCase();
}

/// 按参数名取参数值（键名不区分大小写，忽略括号里的英文缩写）。
String? paramValue(List<ParamEntry> params, List<String> keys) {
  for (final param in params) {
    final key = normalizeParamKey(param.k);
    if (key.isEmpty) continue;
    if (!keys.any((k) => normalizeParamKey(k) == key)) continue;
    final value = param.v.trim();
    if (value.isNotEmpty) return value;
  }
  return null;
}

/// 参数名归一化：去掉括号里的英文缩写（`击穿电压(Vbr)` → `击穿电压`）、
/// 空格与标点，便于和参数别名对齐。
String normalizeParamKey(String key) => key
    .replaceAll(RegExp(r'[（(][^）)]*[）)]'), '')
    .replaceAll(RegExp(r'[\s_\-·:：/\\]'), '')
    .toLowerCase();

/// 库中料某项参数值：参数表优先。
/// [allowNameFallback] 为真时再回落物料名（`CAP CER 100nF 50V 0603`）。
double? materialValue(
  MaterialItem material,
  List<String> keys,
  double? Function(String?) parse, {
  bool allowNameFallback = false,
}) {
  final fromParams = parse(paramValue(material.params, keys));
  if (fromParams != null) return fromParams;
  return allowNameFallback ? parse(material.name) : null;
}

/// 库中料封装（归一化）。
String materialPackage(MaterialItem material) => normalizePackage(
  paramValue(material.params, ['封装', 'package', 'footprint']) ??
      material.package,
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

/// 电感值 → H：`4.7uH`=4.7e-6、`120nH`=1.2e-7、`10mH`=1e-2。
double? parseInductanceH(String? text) {
  final parsed = _numeric(text);
  if (parsed == null) return null;
  switch (parsed.suffix.toLowerCase().replaceAll('μ', 'u').replaceAll('µ', 'u')) {
    case '':
    case 'h':
      return parsed.value;
    case 'nh':
      return parsed.value * 1e-9;
    case 'uh':
      return parsed.value * 1e-6;
    case 'mh':
      return parsed.value * 1e-3;
  }
  return null;
}

/// 阻值/阻抗 → Ω：`10kΩ`=10000、`4.7k`=4700、`10Ω`=10、`4R7`=4.7、`1M`=1e6。
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

/// 电流 → A：`1A`=1、`500mA`=0.5、`100uA`=1e-4。
double? parseCurrentA(String? text) {
  final parsed = _numeric(text);
  if (parsed == null) return null;
  switch (parsed.suffix.toLowerCase().replaceAll('μ', 'u').replaceAll('µ', 'u')) {
    case '':
    case 'a':
      return parsed.value;
    case 'ua':
      return parsed.value * 1e-6;
    case 'ma':
      return parsed.value * 1e-3;
    case 'ka':
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

/// 频率 → Hz：`16MHz`=1.6e7、`32.768kHz`、`2.4GHz`。
double? parseFrequencyHz(String? text) {
  final parsed = _numeric(text);
  if (parsed == null) return null;
  switch (parsed.suffix.toLowerCase()) {
    case '':
    case 'hz':
      return parsed.value;
    case 'khz':
      return parsed.value * 1e3;
    case 'mhz':
      return parsed.value * 1e6;
    case 'ghz':
      return parsed.value * 1e9;
  }
  return null;
}

/// 从 `100nF 50V`、`4.7uF/16V` 这类文本里挑出容值（只认带单位的写法）。
double? extractCapacitancePf(String? text) =>
    _findByParser(text, parseCapacitancePf);

/// 从 `4.7uH`、`4.7uH 1.5A` 这类文本里挑出电感值。
double? extractInductanceH(String? text) =>
    _findByParser(text, parseInductanceH);

/// 从 `5.1kΩ 1%`、`120Ω@100MHz` 这类文本里挑出阻值/阻抗。
double? extractResistanceOhm(String? text) =>
    _findByParser(text, parseResistanceOhm);

/// 磁珠阻抗：`120Ω@100MHz` → 120。
double? extractImpedanceOhm(String? text) =>
    _findByParser(text, parseResistanceOhm);

/// 从 `100nF 50V`、`4.7uF/16V` 这类文本里挑出电压数值。
double? extractVoltageV(String? text) => _findUnit(
  text,
  parseVoltageV,
  const {'v', 'mv', 'kv'},
);

/// 从 `1.5A`、`500mA` 这类文本里挑出电流数值。
double? extractCurrentA(String? text) => _findUnit(
  text,
  parseCurrentA,
  const {'a', 'ma', 'ua', 'μa', 'µa', 'ka'},
);

/// 从 `10kΩ 0.1W` 这类文本里挑出功率数值。
double? extractPowerW(String? text) =>
    _findUnit(text, parsePowerW, const {'w', 'mw', 'kw'});

/// 从 `16MHz`、`32.768kHz` 这类文本里挑出频率数值。
double? extractFrequencyHz(String? text) => _findUnit(
  text,
  parseFrequencyHz,
  const {'hz', 'khz', 'mhz', 'ghz'},
);

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

/// 封装名归一化：
/// - 去掉尺寸后缀，只留主封装名（`SOD-123_L2.7-W1.6-LS3.7-RD` → `SOD-123`）；
/// - 去掉前缀字母（`C0603`/`R0603`/`L0603` → `0603`）。
String normalizePackage(String? text) {
  final upper = (text ?? '').trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
  if (upper.isEmpty) return '';
  final main = upper.split('_').first;
  final match = RegExp(r'^[A-Z]{1,2}(\d{3,5})$').firstMatch(main);
  return match?.group(1) ?? main;
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
