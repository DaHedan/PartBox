import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart' as xls;

import '../../utils/format.dart';
import '../models.dart';

/// BOM 可映射字段（CSV 手动列映射用）。
enum BomField {
  quantity('数量', required: true),
  designator('位号'),
  comment('参数值 Comment'),
  footprint('封装 Footprint'),
  value('值 Value'),
  mpn('制造商编号 MPN'),
  manufacturer('制造商'),
  lcscCode('C 编号 Supplier Part'),
  supplier('供应商'),
  unitPrice('单价');

  const BomField(this.label, {this.required = false});

  final String label;
  final bool required;
}

/// 解析后的一行 BOM（未比对）。
class ParsedBomRow {
  const ParsedBomRow({
    this.quantity = 0,
    this.designator = '',
    this.comment = '',
    this.footprint = '',
    this.value = '',
    this.mpn = '',
    this.manufacturer = '',
    this.lcscCode = '',
    this.supplier = '',
    this.unitPrice,
  });

  final double quantity;
  final String designator;
  final String comment;
  final String footprint;
  final String value;
  final String mpn;
  final String manufacturer;
  final String lcscCode;
  final String supplier;
  final double? unitPrice;

  /// 位号/参数/封装/MPN/C 编号全空视为空行。
  bool get isEmpty =>
      designator.isEmpty &&
      comment.isEmpty &&
      footprint.isEmpty &&
      mpn.isEmpty &&
      lcscCode.isEmpty;

  BomItem toItem(int projectId, int sort) => BomItem(
    bomProjectId: projectId,
    designator: designator,
    comment: comment,
    footprint: footprint,
    value: value,
    mpn: mpn,
    manufacturer: manufacturer,
    lcscCode: lcscCode,
    supplier: supplier,
    unitPrice: unitPrice,
    quantity: quantity,
    sort: sort,
  );
}

/// 一次导入的解析结果。
class ParsedBom {
  const ParsedBom({
    required this.sheetName,
    required this.source,
    required this.rows,
  });

  final String sheetName;

  /// lcsc-xlsx / csv
  final String source;
  final List<ParsedBomRow> rows;
}

/// F10.1 导入与解析（嘉立创 xlsx 自动识别 + CSV 手动列映射）。
class BomParser {
  const BomParser._();

  /// 嘉立创 BOM 的 sheet 名。
  static const String lcscSheetName = 'bom模板';

  /// 表头别名（已归一化：小写、去空格与标点）。
  static const Map<BomField, List<String>> _aliases = {
    BomField.quantity: ['quantity', 'qty', '数量', 'orderqty'],
    BomField.designator: [
      'designator',
      'designators',
      'refdes',
      'reference',
      'references',
      '位号',
      '元件位号',
    ],
    BomField.comment: ['comment', 'commentparam', '参数', '参数值', '规格'],
    BomField.footprint: ['footprint', 'package', '封装', '封装规格'],
    BomField.value: ['value', '值', '数值'],
    BomField.mpn: [
      'manufacturerpart',
      'manufacturerpartnumber',
      'mpn',
      '制造商编号',
      '制造商型号',
      '规格型号',
      '型号',
    ],
    BomField.manufacturer: ['manufacturer', '制造商', '厂家', '品牌'],
    BomField.lcscCode: [
      'supplierpart',
      'supplierpartnumber',
      'lcscpart',
      'lcsc',
      'c编号',
      '立创编号',
      '供应商编号',
    ],
    BomField.supplier: ['supplier', '供应商', '供应商名称'],
    BomField.unitPrice: ['lcscprice', 'price', 'unitprice', '单价', '价格'],
  };

  /// 解析嘉立创导出的 xlsx。识别失败（非嘉立创格式）返回 null。
  static ParsedBom? parseXlsx(Uint8List bytes) {
    final tables = xls.Excel.decodeBytes(bytes).tables;
    if (tables.isEmpty) return null;

    // 优先生命中的 sheet：先「bom模板」，再按顺序找含表头的 sheet。
    final names = [
      if (tables.containsKey(lcscSheetName)) lcscSheetName,
      ...tables.keys.where((n) => n != lcscSheetName),
    ];

    for (final name in names) {
      final table = tables[name]!.rows
          .map((row) => row.map(_cellText).toList())
          .toList();
      final headerIndex = findHeaderRow(table);
      if (headerIndex == null) continue;
      final rows = mapRows(table, headerIndex, guessMapping(table[headerIndex]));
      if (rows.isEmpty) continue;
      return ParsedBom(sheetName: name, source: 'lcsc-xlsx', rows: rows);
    }
    return null;
  }

  /// CSV 内容 → 二维表（RFC4180：支持引号包裹与转义）。
  static List<List<String>> readCsv(String content) {
    final text = content.startsWith('\uFEFF') ? content.substring(1) : content;
    final rows = <List<String>>[];
    var row = <String>[];
    final cell = StringBuffer();
    var quoted = false;

    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (quoted) {
        if (ch == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            cell.write('"');
            i++;
          } else {
            quoted = false;
          }
        } else {
          cell.write(ch);
        }
        continue;
      }
      switch (ch) {
        case '"':
          quoted = true;
        case ',':
          row.add(cell.toString().trim());
          cell.clear();
        case '\r':
          break;
        case '\n':
          row.add(cell.toString().trim());
          cell.clear();
          rows.add(row);
          row = <String>[];
        default:
          cell.write(ch);
      }
    }
    if (cell.isNotEmpty || row.isNotEmpty) {
      row.add(cell.toString().trim());
      rows.add(row);
    }
    return rows.where((r) => r.any((c) => c.isNotEmpty)).toList();
  }

  /// 表头行 → 列映射（自动猜测）。
  static Map<BomField, int> guessMapping(List<String> header) {
    final mapping = <BomField, int>{};
    for (var i = 0; i < header.length; i++) {
      final field = fieldFor(header[i]);
      if (field != null && !mapping.containsKey(field)) mapping[field] = i;
    }
    return mapping;
  }

  /// 按列映射生成行；数量为空或 ≤ 0 的行跳过（含合计行）。
  static List<ParsedBomRow> mapRows(
    List<List<String>> table,
    int headerIndex,
    Map<BomField, int> mapping,
  ) {
    final rows = <ParsedBomRow>[];
    for (var i = headerIndex + 1; i < table.length; i++) {
      final source = table[i];
      String text(BomField field) {
        final index = mapping[field];
        if (index == null || index >= source.length) return '';
        return source[index];
      }

      final quantity = _toDouble(text(BomField.quantity));
      final row = ParsedBomRow(
        quantity: quantity ?? 0,
        designator: text(BomField.designator),
        comment: text(BomField.comment),
        footprint: text(BomField.footprint),
        value: text(BomField.value),
        mpn: text(BomField.mpn),
        manufacturer: text(BomField.manufacturer),
        lcscCode: _code(text(BomField.lcscCode)),
        supplier: text(BomField.supplier),
        unitPrice: _toDouble(text(BomField.unitPrice)),
      );
      if (quantity == null || quantity <= 0 || row.isEmpty) continue;
      rows.add(row);
    }
    return rows;
  }

  /// 表头文本 → 字段。归一化后精确匹配别名。
  static BomField? fieldFor(String header) {
    final key = normalizeHeader(header);
    if (key.isEmpty) return null;
    for (final entry in _aliases.entries) {
      if (entry.value.contains(key)) return entry.key;
    }
    return null;
  }

  /// 表头归一化：小写、去空白与常见标点。
  static String normalizeHeader(String header) => header
      .toLowerCase()
      .replaceAll(RegExp(r'[\s_\-().:：/\\*]'), '')
      .trim();

  /// 找表头行：前 20 行内，必须含「数量」，且含「位号」或「参数值」其一。
  /// 嘉立创 BOM 表头固定在第 6 行，此处不写死行号以便兼容同类模板。
  static int? findHeaderRow(List<List<String>> table) {
    final limit = table.length < 20 ? table.length : 20;
    for (var i = 0; i < limit; i++) {
      final fields = table[i].map(fieldFor).whereType<BomField>().toSet();
      if (!fields.contains(BomField.quantity)) continue;
      if (fields.contains(BomField.designator) ||
          fields.contains(BomField.comment)) {
        return i;
      }
    }
    return null;
  }

  /// 提取 `C` 编号（容错：`C518789` / `LCSC C518789`）。
  static String _code(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return '';
    final match = RegExp(r'C\d{3,}').firstMatch(text.toUpperCase());
    return match?.group(0) ?? '';
  }

  static double? _toDouble(String raw) {
    final text = raw.trim().replaceAll(',', '');
    if (text.isEmpty) return null;
    return double.tryParse(text);
  }

  static String _cellText(xls.Data? data) {
    switch (data?.value) {
      case null:
        return '';
      case final xls.TextCellValue value:
        return value.value.text?.trim() ?? '';
      case final xls.IntCellValue value:
        return value.value.toString();
      case final xls.DoubleCellValue value:
        return formatQty(value.value);
      case final xls.BoolCellValue value:
        return value.value ? 'TRUE' : 'FALSE';
      case xls.FormulaCellValue():
        // 公式单元格无缓存值（合计行、序号列），按空处理。
        return '';
      case final value:
        return value.toString().trim();
    }
  }
}

/// 文件名 → 工程名：`xxx_BOM.xlsx` → `xxx_BOM`。
String bomProjectNameFromFile(String fileName) {
  final base = fileName.split(RegExp(r'[\\/]')).last;
  final dot = base.lastIndexOf('.');
  return dot > 0 ? base.substring(0, dot) : base;
}

/// UTF-8 解码 CSV 字节（容错）。
String decodeCsvBytes(List<int> bytes) =>
    utf8.decode(bytes, allowMalformed: true);
