import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../bom/bom_matcher.dart';
import '../models.dart';
import '../repositories/bom_repository.dart';
import '../repositories/material_repository.dart';
import 'ibom_parser.dart';

/// iBOM 导入结果。
class IbomImportOutcome {
  const IbomImportOutcome({
    required this.projectId,
    required this.htmlPath,
    required this.designatorCount,
    required this.matchedCount,
  });

  final int projectId;

  /// 改写后落盘的 iBOM（打开时加载这一份）。
  final String htmlPath;
  final int designatorCount;

  /// 四色里非红（蓝/绿/黄）的位号数。
  final int matchedCount;
}

/// F11.2：导入 iBOM → 建 BOM 工程（复用 F10 的 bom_projects / bom_items）→ 四色比对。
class IbomImportService {
  const IbomImportService._();

  static const String _dirName = 'ibom';

  static Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, _dirName));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// 工程对应 iBOM 文件的落盘路径（[BomProject.fileName] 只是文件名）。
  static Future<String> htmlPathOf(BomProject project) async {
    final dir = await _dir();
    return p.join(dir.path, project.fileName ?? '');
  }

  /// 导入一个 iBOM。
  ///
  /// iBOM 自带完整电气参数（comp_info 的 `Description`），所以比对**完全离线**，
  /// 不需要像嘉立创 BOM 那样联网补齐耐压/功率。
  static Future<IbomImportOutcome> importFile({
    required String sourcePath,
    String? displayName,
  }) async {
    final html = await File(sourcePath).readAsString();
    final data = IbomParser.parse(html);
    if (data.designators.isEmpty) {
      throw const IbomParseException('这个 iBOM 里没有元件清单');
    }

    final now = DateTime.now();
    final fileName = 'ibom_${now.millisecondsSinceEpoch}.html';
    final dir = await _dir();
    final target = File(p.join(dir.path, fileName));
    await target.writeAsString(IbomParser.prepareHtml(html));

    final projectId = await BomRepository.insertProject(
      BomProject(
        name: displayName ?? p.basenameWithoutExtension(sourcePath),
        fileName: fileName,
        source: 'ibom',
        createdAt: now,
        updatedAt: now,
      ),
    );

    final materials = await MaterialRepository.all();
    final built = buildItems(
      projectId: projectId,
      data: data,
      materials: materials,
    );
    await BomRepository.insertItems(built.items);

    return IbomImportOutcome(
      projectId: projectId,
      htmlPath: target.path,
      designatorCount: built.items.length,
      matchedCount: built.matched,
    );
  }

  /// iBOM 的位号 → `bom_items` 一行，并顺手跑 F10 四色比对。
  ///
  /// 一个**位号**一行（不是按物料聚合）：焊接是按位号进行的，四色标记、
  /// 焊接进度都挂在位号上（PRD 11.5 / 11.7）。
  static ({List<BomItem> items, int matched}) buildItems({
    required int projectId,
    required IbomData data,
    required List<MaterialItem> materials,
  }) {
    final designators = [...data.designators]
      ..sort((a, b) => a.bomIndex.compareTo(b.bomIndex));

    final items = <BomItem>[];
    var matched = 0;
    for (var i = 0; i < designators.length; i++) {
      final designator = designators[i];
      final material = data.materialOf(designator);
      // iBOM 自带电气参数（Description），比对不用联网补齐
      final params = material?.paramEntries ?? const <ParamEntry>[];
      final result = BomMatcher.match(
        designator.toBomRow(material),
        materials,
        bomParams: params,
      );
      if (result.status != MatchStatus.red) matched++;
      final best = result.candidates.isEmpty
          ? null
          : result.candidates.first.material;
      items.add(
        BomItem(
          bomProjectId: projectId,
          designator: designator.designator,
          comment: material?.value.isNotEmpty == true
              ? material!.value
              : designator.comment,
          footprint: material?.footprint.isNotEmpty == true
              ? material!.footprint
              : designator.footprint,
          value: material?.value ?? designator.comment,
          mpn: material?.mpn ?? '',
          manufacturer: material?.manufacturer ?? '',
          lcscCode: material?.lcsc.isNotEmpty == true
              ? material!.lcsc
              : IbomData.lcscOf(designator.materialKey),
          supplier: 'LCSC',
          quantity: 1,
          sort: i,
          params: params,
          matchStatus: result.status,
          matchedMaterialId: best?.id,
          checked: MatchStatus.defaultChecked(result.status),
        ),
      );
    }
    return (items: items, matched: matched);
  }
}
