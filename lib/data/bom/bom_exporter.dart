import 'dart:typed_data';

import 'package:excel/excel.dart' as xls;

import '../models.dart';

/// F10.4 双导出：采购 BOM（仅勾选行）/ 替换 BOM（全量 + 替代信息）。
class BomExporter {
  const BomExporter._();

  /// 导出的 sheet 名沿用嘉立创模板名。
  static const String sheetName = 'bom模板';

  /// 嘉立创 BOM 列结构（可直接回传下单）。
  static const List<String> headers = [
    'No.',
    'Quantity',
    'Comment',
    'Designator',
    'Footprint',
    'Value',
    'Manufacturer Part',
    'Manufacturer',
    'Supplier Part',
    'Supplier',
    'LCSC Price',
    'Total',
  ];

  static const String noteHeader = '备注';

  /// 采购 BOM：仅含勾选行（含义 = 采购新料）。
  static Uint8List buildPurchaseBom(List<BomItem> items) {
    final selected = items.where((item) => item.checked).toList();
    final rows = <List<xls.CellValue?>>[];
    for (var i = 0; i < selected.length; i++) {
      rows.add(_row(selected[i], i + 1));
    }
    return _write([...headers], rows);
  }

  /// 替换 BOM：全量；未勾选的绿/黄行把 MPN/制造商/C 编号换成库中匹配料，并备注"替代：原 MPN"。
  static Uint8List buildReplaceBom(
    List<BomItem> items,
    Map<int, MaterialItem> materials,
  ) {
    final rows = <List<xls.CellValue?>>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final substitute = _substituteOf(item, materials);
      final row = _row(
        item,
        i + 1,
        override: substitute,
      );
      rows.add([...row, _text(substitute == null ? '' : '替代：${item.mpn}')]);
    }
    return _write([...headers, noteHeader], rows);
  }

  /// 哪些行需要替换：未勾选，且匹配到库中料（绿/黄）。
  static MaterialItem? _substituteOf(
    BomItem item,
    Map<int, MaterialItem> materials,
  ) {
    if (item.checked) return null;
    final status = item.matchStatus;
    if (status != MatchStatus.green && status != MatchStatus.yellow) {
      return null;
    }
    final matchedId = item.matchedMaterialId;
    if (matchedId == null) return null;
    return materials[matchedId];
  }

  static List<xls.CellValue?> _row(
    BomItem item,
    int index, {
    MaterialItem? override,
  }) {
    final quantity = item.quantity;
    final unitPrice = override?.unitPrice ?? item.unitPrice;
    return [
      _num(index.toDouble()),
      _num(quantity),
      _text(item.comment),
      _text(item.designator),
      _text(item.footprint),
      _text(item.value),
      _text(override == null
          ? item.mpn
          : (override.mpn ?? override.name)),
      _text(override == null ? item.manufacturer : (override.brand ?? '')),
      _text(override == null ? item.lcscCode : (override.lcscCode ?? '')),
      _text(override == null ? item.supplier : 'LCSC'),
      _num(unitPrice),
      _num(unitPrice == null ? null : unitPrice * quantity),
    ];
  }

  static Uint8List _write(
    List<String> headerRow,
    List<List<xls.CellValue?>> rows,
  ) {
    final book = xls.Excel.createExcel();
    final sheet = book[sheetName];
    for (final name in book.tables.keys.toList()) {
      if (name != sheetName) book.delete(name);
    }
    sheet.appendRow(
      headerRow.map<xls.CellValue?>((h) => xls.TextCellValue(h)).toList(),
    );
    for (final row in rows) {
      sheet.appendRow(row);
    }
    return Uint8List.fromList(book.encode() ?? const <int>[]);
  }

  static xls.CellValue? _text(String value) =>
      value.trim().isEmpty ? null : xls.TextCellValue(value.trim());

  static xls.CellValue? _num(double? value) {
    if (value == null) return null;
    if (value == value.roundToDouble()) return xls.IntCellValue(value.toInt());
    return xls.DoubleCellValue(value);
  }

  /// 文件名：`{项目名}_采购BOM_{日期}.xlsx`。
  static String purchaseFileName(String projectName, DateTime now) =>
      '${_safeName(projectName)}_采购BOM_${_dateStamp(now)}.xlsx';

  /// 文件名：`{项目名}_替换BOM_{日期}.xlsx`。
  static String replaceFileName(String projectName, DateTime now) =>
      '${_safeName(projectName)}_替换BOM_${_dateStamp(now)}.xlsx';

  static String _dateStamp(DateTime time) {
    final local = time.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}${two(local.month)}${two(local.day)}';
  }

  static String _safeName(String name) =>
      name.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
}
