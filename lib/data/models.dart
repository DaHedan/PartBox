import 'dart:convert';

/// 参数键值对，对应 materials.params_json 中的一项。
class ParamEntry {
  const ParamEntry(this.k, this.v);

  final String k;
  final String v;

  Map<String, dynamic> toJson() => {'k': k, 'v': v};

  factory ParamEntry.fromJson(Map<dynamic, dynamic> json) => ParamEntry(
    (json['k'] ?? '').toString(),
    (json['v'] ?? '').toString(),
  );

  static List<ParamEntry> decode(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final data = jsonDecode(raw);
      if (data is! List) return const [];
      return data
          .whereType<Map<dynamic, dynamic>>()
          .map(ParamEntry.fromJson)
          .where((e) => e.k.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static String encode(List<ParamEntry> params) =>
      jsonEncode(params.map((e) => e.toJson()).toList());
}

/// 分类：parentId 为 null 表示大类，否则为子类。
class Category {
  const Category({
    this.id,
    this.parentId,
    required this.name,
    this.icon,
    this.sort = 0,
    this.builtin = false,
    this.materialCount = 0,
  });

  final int? id;
  final int? parentId;
  final String name;
  final String? icon;
  final int sort;
  final bool builtin;

  /// 联表统计字段（该分类下物料种数），不落库。
  final int materialCount;

  bool get isTop => parentId == null;

  Category copyWith({int? id, int? parentId, String? name, String? icon, int? sort}) {
    return Category(
      id: id ?? this.id,
      parentId: parentId ?? this.parentId,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      sort: sort ?? this.sort,
      builtin: builtin,
      materialCount: materialCount,
    );
  }

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'parent_id': parentId,
    'name': name,
    'icon': icon,
    'sort': sort,
    'builtin': builtin ? 1 : 0,
  };

  factory Category.fromMap(Map<String, Object?> map) => Category(
    id: map['id'] as int?,
    parentId: map['parent_id'] as int?,
    name: (map['name'] ?? '') as String,
    icon: map['icon'] as String?,
    sort: (map['sort'] ?? 0) as int,
    builtin: ((map['builtin'] ?? 0) as int) == 1,
    materialCount: (map['material_count'] ?? 0) as int,
  );
}

/// 仓库（储存位置）。扁平结构，parent_id 预留。
class Location {
  const Location({
    this.id,
    this.parentId,
    required this.name,
    this.note,
    this.sort = 0,
    this.materialKinds = 0,
    this.totalRemaining = 0,
  });

  final int? id;
  final int? parentId;
  final String name;
  final String? note;
  final int sort;

  /// 联表统计：物料种数、余量合计。
  final int materialKinds;
  final double totalRemaining;

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'parent_id': parentId,
    'name': name,
    'note': note,
    'sort': sort,
  };

  factory Location.fromMap(Map<String, Object?> map) => Location(
    id: map['id'] as int?,
    parentId: map['parent_id'] as int?,
    name: (map['name'] ?? '') as String,
    note: map['note'] as String?,
    sort: (map['sort'] ?? 0) as int,
    materialKinds: ((map['material_kinds'] ?? 0) as num).toInt(),
    totalRemaining: ((map['total_remaining'] ?? 0) as num).toDouble(),
  );
}

/// 物料。
class MaterialItem {
  const MaterialItem({
    this.id,
    required this.name,
    this.mpn,
    this.lcscCode,
    this.categoryId,
    this.package,
    this.brand,
    this.params = const [],
    this.imagePath,
    this.unit = 'pcs',
    this.locationId,
    this.qtyPurchased = 0,
    this.qtyUsed = 0,
    this.qtyRemaining = 0,
    this.lowStockThreshold,
    this.unitPrice,
    this.note,
    required this.createdAt,
    required this.updatedAt,
    this.lastTransactionAt,
    this.categoryName,
    this.categoryIcon,
    this.locationName,
  });

  final int? id;
  final String name;
  final String? mpn;
  final String? lcscCode;

  /// 落库字段名沿用 subcategory_id：可指向子类，也可指向大类（=该大类下"未分类"）。
  final int? categoryId;
  final String? package;
  final String? brand;
  final List<ParamEntry> params;
  final String? imagePath;
  final String unit;
  final int? locationId;
  final double qtyPurchased;
  final double qtyUsed;
  final double qtyRemaining;
  final double? lowStockThreshold;
  final double? unitPrice;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastTransactionAt;

  /// 联表字段，不落库。
  final String? categoryName;
  final String? categoryIcon;
  final String? locationName;

  String get title => (mpn != null && mpn!.trim().isNotEmpty) ? mpn!.trim() : name;

  /// 参数摘要行：类别 + 关键参数（取前 4 个）。
  String get summary {
    final parts = <String>[];
    if (categoryName != null && categoryName!.isNotEmpty) parts.add(categoryName!);
    for (final p in params.take(4)) {
      if (p.v.trim().isEmpty) continue;
      parts.add(p.v.trim());
    }
    if (parts.isEmpty && package != null && package!.isNotEmpty) parts.add(package!);
    return parts.join(' ');
  }

  MaterialItem copyWith({
    int? id,
    String? name,
    String? mpn,
    String? lcscCode,
    int? categoryId,
    String? package,
    String? brand,
    List<ParamEntry>? params,
    String? imagePath,
    String? unit,
    int? locationId,
    double? qtyPurchased,
    double? qtyUsed,
    double? qtyRemaining,
    double? lowStockThreshold,
    double? unitPrice,
    String? note,
    DateTime? updatedAt,
    DateTime? lastTransactionAt,
    String? categoryName,
    String? categoryIcon,
    String? locationName,
  }) {
    return MaterialItem(
      id: id ?? this.id,
      name: name ?? this.name,
      mpn: mpn ?? this.mpn,
      lcscCode: lcscCode ?? this.lcscCode,
      categoryId: categoryId ?? this.categoryId,
      package: package ?? this.package,
      brand: brand ?? this.brand,
      params: params ?? this.params,
      imagePath: imagePath ?? this.imagePath,
      unit: unit ?? this.unit,
      locationId: locationId ?? this.locationId,
      qtyPurchased: qtyPurchased ?? this.qtyPurchased,
      qtyUsed: qtyUsed ?? this.qtyUsed,
      qtyRemaining: qtyRemaining ?? this.qtyRemaining,
      lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
      unitPrice: unitPrice ?? this.unitPrice,
      note: note ?? this.note,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastTransactionAt: lastTransactionAt ?? this.lastTransactionAt,
      categoryName: categoryName ?? this.categoryName,
      categoryIcon: categoryIcon ?? this.categoryIcon,
      locationName: locationName ?? this.locationName,
    );
  }

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'name': name,
    'mpn': mpn,
    'lcsc_code': lcscCode,
    'subcategory_id': categoryId,
    'package': package,
    'brand': brand,
    'params_json': ParamEntry.encode(params),
    'image_path': imagePath,
    'unit': unit,
    'location_id': locationId,
    'qty_purchased': qtyPurchased,
    'qty_used': qtyUsed,
    'qty_remaining': qtyRemaining,
    'low_stock_threshold': lowStockThreshold,
    'unit_price': unitPrice,
    'note': note,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'last_transaction_at': lastTransactionAt?.millisecondsSinceEpoch,
  };

  factory MaterialItem.fromMap(Map<String, Object?> map) => MaterialItem(
    id: map['id'] as int?,
    name: (map['name'] ?? '') as String,
    mpn: map['mpn'] as String?,
    lcscCode: map['lcsc_code'] as String?,
    categoryId: map['subcategory_id'] as int?,
    package: map['package'] as String?,
    brand: map['brand'] as String?,
    params: ParamEntry.decode(map['params_json'] as String?),
    imagePath: map['image_path'] as String?,
    unit: (map['unit'] ?? 'pcs') as String,
    locationId: map['location_id'] as int?,
    qtyPurchased: ((map['qty_purchased'] ?? 0) as num).toDouble(),
    qtyUsed: ((map['qty_used'] ?? 0) as num).toDouble(),
    qtyRemaining: ((map['qty_remaining'] ?? 0) as num).toDouble(),
    lowStockThreshold: (map['low_stock_threshold'] as num?)?.toDouble(),
    unitPrice: (map['unit_price'] as num?)?.toDouble(),
    note: map['note'] as String?,
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      ((map['created_at'] ?? 0) as num).toInt(),
    ),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(
      ((map['updated_at'] ?? 0) as num).toInt(),
    ),
    lastTransactionAt: map['last_transaction_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            (map['last_transaction_at'] as num).toInt(),
          ),
    categoryName: map['category_name'] as String?,
    categoryIcon: map['category_icon'] as String?,
    locationName: map['location_name'] as String?,
  );
}

/// 流水类型。
class TxType {
  static const inbound = 'in';
  static const outbound = 'out';
  static const adjust = 'adjust';

  static String label(String type) {
    switch (type) {
      case inbound:
        return '入库';
      case outbound:
        return '消耗';
      default:
        return '手动校正';
    }
  }
}

/// 库存流水。
class StockTransaction {
  const StockTransaction({
    this.id,
    required this.materialId,
    required this.type,
    required this.qty,
    required this.remainingAfter,
    this.note,
    required this.createdAt,
  });

  final int? id;
  final int materialId;
  final String type;
  final double qty;
  final double remainingAfter;
  final String? note;
  final DateTime createdAt;

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'material_id': materialId,
    'type': type,
    'qty': qty,
    'remaining_after': remainingAfter,
    'note': note,
    'created_at': createdAt.millisecondsSinceEpoch,
  };

  factory StockTransaction.fromMap(Map<String, Object?> map) => StockTransaction(
    id: map['id'] as int?,
    materialId: (map['material_id'] as num).toInt(),
    type: (map['type'] ?? TxType.adjust) as String,
    qty: ((map['qty'] ?? 0) as num).toDouble(),
    remainingAfter: ((map['remaining_after'] ?? 0) as num).toDouble(),
    note: map['note'] as String?,
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      ((map['created_at'] ?? 0) as num).toInt(),
    ),
  );
}
