import '../models.dart';
import '../repositories/material_repository.dart';
import '../repositories/weld_repository.dart';
import '../stock_service.dart';

/// 一次焊接动作的结果（用来决定 toast 文案）。
class WeldOutcome {
  const WeldOutcome({
    required this.materialMoved,
    this.materialTitle,
    this.remainingAfter,
    this.consumeCount = 0,
    this.lossCount = 0,
  });

  /// 是否真的动了库存。
  final bool materialMoved;

  /// 扣减的物料名（未匹配库存时为空）。
  final String? materialTitle;

  /// 扣减后的余量。
  final double? remainingAfter;

  final int consumeCount;
  final int lossCount;

  bool get matched => materialMoved;
}

/// F11.6：双按钮与库存联动。
///
/// - 「丢失」= 库存 −1 + 记「焊接丢失」流水；
/// - 「完成」= 库存 −1 + 记「焊接完成」流水 + 勾选已焊接；
/// - 库中没匹配到物料：只记进度，不动库存（PRD 11.6）。
class WeldService {
  const WeldService._();

  /// 找到该位号要扣减的库中物料：优先 F10 比对已匹配的，其次按 C 编号精确命中。
  ///
  /// 同一 C 编号存在多条（同一元件买多包分开记）时取余量最多的那条。
  static Future<MaterialItem?> resolveMaterial(BomItem item) async {
    final matchedId = item.matchedMaterialId;
    if (matchedId != null) {
      final material = await MaterialRepository.byId(matchedId);
      if (material != null) return material;
    }
    final code = item.lcscCode.trim().toUpperCase();
    if (code.isEmpty) return null;
    final list = await MaterialRepository.allByLcscCode(code);
    if (list.isEmpty) return null;
    final sorted = [...list]
      ..sort((a, b) => b.qtyRemaining.compareTo(a.qtyRemaining));
    return sorted.first;
  }

  /// 记一次焊接动作，返回是否动了库存。
  static Future<WeldOutcome> record({
    required int bomProjectId,
    required String designator,
    int? bomItemId,
    int? materialId,
    required bool loss,
  }) async {
    String? title;
    double? remaining;
    if (materialId != null) {
      await StockService.consume(
        materialId: materialId,
        qty: 1,
        note: '${TxType.label(loss ? TxType.weldLoss : TxType.weldConsume)} '
            '$designator',
        type: loss ? TxType.weldLoss : TxType.weldConsume,
      );
      final material = await MaterialRepository.byId(materialId);
      title = material?.title;
      remaining = material?.qtyRemaining;
    }

    // 未匹配库存也照样记进度（PRD 11.6）。
    // 「掉了」不改已焊接状态，只累加损耗计数。
    final progress = await WeldRepository.upsert(
      projectId: bomProjectId,
      designator: designator,
      bomItemId: bomItemId,
      welded: loss ? null : true,
      bumpConsume: !loss,
      bumpLoss: loss,
    );

    return WeldOutcome(
      materialMoved: materialId != null,
      materialTitle: title,
      remainingAfter: remaining,
      consumeCount: progress.consumeCount,
      lossCount: progress.lossCount,
    );
  }
}
