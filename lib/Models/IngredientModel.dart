import 'package:cloud_firestore/cloud_firestore.dart';

class IngredientModel {
  final String id;
  final List<String> branchIds;
  final String name;
  final String category;
  final String unit;
  final double costPerUnit;
  final Map<String, double> branchStocks;
  final Map<String, double> branchMinThresholds;
  final List<String> supplierIds;
  final List<String> allergenTags;
  final bool isPerishable;
  final int? shelfLifeDays;
  final DateTime? expiryDate;
  final String? imageUrl;
  final String? barcode;
  final String? sku;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const IngredientModel({
    required this.id,
    required this.branchIds,
    required this.name,
    required this.category,
    required this.unit,
    required this.costPerUnit,
    required this.branchStocks,
    required this.branchMinThresholds,
    required this.supplierIds,
    required this.allergenTags,
    required this.isPerishable,
    this.shelfLifeDays,
    this.expiryDate,
    this.imageUrl,
    this.barcode,
    this.sku,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  // Stock status helpers
  double getStock(String branchId) => branchStocks[branchId] ?? 0.0;
  double getMinThreshold(String branchId) =>
      branchMinThresholds[branchId] ?? 0.0;

  double getStockForBranches(List<String> branchIds) {
    final effectiveBranchIds = _effectiveBranchIds(branchIds);
    if (effectiveBranchIds.isEmpty) {
      return 0.0;
    }
    return effectiveBranchIds.fold<double>(
      0.0,
      (total, branchId) => total + getStock(branchId),
    );
  }

  double getMinThresholdForBranches(List<String> branchIds) {
    final effectiveBranchIds = _effectiveBranchIds(branchIds);
    if (effectiveBranchIds.isEmpty) {
      return 0.0;
    }
    return effectiveBranchIds.fold<double>(
      0.0,
      (total, branchId) => total + getMinThreshold(branchId),
    );
  }

  bool isOutOfStock(String branchId) => getStock(branchId) <= 0;
  bool isLowStock(String branchId) =>
      getStock(branchId) > 0 && getStock(branchId) <= getMinThreshold(branchId);
  bool isOutOfStockForBranches(List<String> branchIds) =>
      getStockForBranches(branchIds) <= 0;
  bool isLowStockForBranches(List<String> branchIds) {
    final stock = getStockForBranches(branchIds);
    final minThreshold = getMinThresholdForBranches(branchIds);
    return stock > 0 && stock <= minThreshold;
  }

  /// Returns true if ANY of the given branches has this ingredient out of stock.
  /// Used for alert counts so that a per-branch stockout isn't hidden by
  /// aggregation with other branches.
  bool isOutOfStockInAnyBranch(List<String> branchIds) {
    final effective = _effectiveBranchIds(branchIds);
    if (effective.isEmpty) return false;
    
    // Only check branches where this ingredient is actually assigned
    final relevant = effective.where((id) => this.branchIds.contains(id)).toList();
    if (relevant.isEmpty) return false;
    
    return relevant.any((bId) => getStock(bId) <= 0);
  }

  /// Returns true if ANY of the given branches has this ingredient at low stock.
  bool isLowStockInAnyBranch(List<String> branchIds) {
    final effective = _effectiveBranchIds(branchIds);
    if (effective.isEmpty) return false;
    
    // Only check branches where this ingredient is actually assigned
    final relevant = effective.where((id) => this.branchIds.contains(id)).toList();
    if (relevant.isEmpty) return false;

    return relevant.any((bId) {
      final s = getStock(bId);
      final t = getMinThreshold(bId);
      return s > 0 && t > 0 && s <= t;
    });
  }

  /// Returns per-branch stock status map for UI display.
  /// Each entry is branchId → 'out' | 'low' | 'ok'.
  Map<String, String> getPerBranchStockStatus(List<String> branchIds) {
    final effective = _effectiveBranchIds(branchIds);
    final result = <String, String>{};
    for (final bId in effective) {
      final s = getStock(bId);
      final t = getMinThreshold(bId);
      if (s <= 0) {
        result[bId] = 'out';
      } else if (t > 0 && s <= t) {
        result[bId] = 'low';
      } else {
        result[bId] = 'ok';
      }
    }
    return result;
  }

  bool get isExpiringSoon {
    if (expiryDate == null) return false;
    final diff = expiryDate!.difference(DateTime.now()).inDays;
    return diff >= 0 && diff <= 3;
  }

  bool get isExpired {
    if (expiryDate == null) return false;
    return expiryDate!.isBefore(DateTime.now());
  }

  factory IngredientModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;

    // Robust branch parsing
    List<String> bIds = [];
    if (data['branchIds'] is List) {
      bIds = List<String>.from(data['branchIds'] as List);
    } else if (data['branchids'] is List) {
      bIds = List<String>.from(data['branchids'] as List);
    } else if (data['branchId'] is String && (data['branchId'] as String).isNotEmpty) {
      bIds = [data['branchId'] as String];
    }

    return IngredientModel(
      id: doc.id,
      branchIds: bIds,
      name: data['name'] as String? ?? '',
      category: data['category'] as String? ?? 'other',
      unit: data['unit'] as String? ?? 'pieces',
      costPerUnit: (data['costPerUnit'] as num?)?.toDouble() ?? 0.0,
      branchStocks: _parseBranchStocks(data),
      branchMinThresholds: _parseBranchThresholds(data),
      supplierIds: List<String>.from(data['supplierIds'] as List? ?? []),
      allergenTags: List<String>.from(data['allergenTags'] as List? ?? []),
      isPerishable: data['isPerishable'] as bool? ?? false,
      shelfLifeDays: data['shelfLifeDays'] as int?,
      expiryDate: (data['expiryDate'] as Timestamp?)?.toDate(),
      imageUrl: data['imageUrl'] as String?,
      barcode: data['barcode'] as String?,
      sku: data['sku'] as String?,
      isActive: data['isActive'] as bool? ?? true,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'branchIds': branchIds,
      'name': name,
      'category': category,
      'unit': unit,
      'costPerUnit': costPerUnit,
      'branchStocks': branchStocks,
      'branchMinThresholds': branchMinThresholds,
      'supplierIds': supplierIds,
      'allergenTags': allergenTags,
      'isPerishable': isPerishable,
      'shelfLifeDays': shelfLifeDays,
      'expiryDate': expiryDate != null ? Timestamp.fromDate(expiryDate!) : null,
      'imageUrl': imageUrl,
      'barcode': barcode,
      'sku': sku,
      'isActive': isActive,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  IngredientModel copyWith({
    String? id,
    List<String>? branchIds,
    String? name,
    String? category,
    String? unit,
    double? costPerUnit,
    Map<String, double>? branchStocks,
    Map<String, double>? branchMinThresholds,
    List<String>? supplierIds,
    List<String>? allergenTags,
    bool? isPerishable,
    int? shelfLifeDays,
    DateTime? expiryDate,
    String? imageUrl,
    String? barcode,
    String? sku,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return IngredientModel(
      id: id ?? this.id,
      branchIds: branchIds ?? this.branchIds,
      name: name ?? this.name,
      category: category ?? this.category,
      unit: unit ?? this.unit,
      costPerUnit: costPerUnit ?? this.costPerUnit,
      branchStocks: branchStocks ?? Map.from(this.branchStocks),
      branchMinThresholds:
          branchMinThresholds ?? Map.from(this.branchMinThresholds),
      supplierIds: supplierIds ?? this.supplierIds,
      allergenTags: allergenTags ?? this.allergenTags,
      isPerishable: isPerishable ?? this.isPerishable,
      shelfLifeDays: shelfLifeDays ?? this.shelfLifeDays,
      expiryDate: expiryDate ?? this.expiryDate,
      imageUrl: imageUrl ?? this.imageUrl,
      barcode: barcode ?? this.barcode,
      sku: sku ?? this.sku,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static Map<String, double> _parseBranchStocks(Map<String, dynamic> data) {
    if (data['branchStocks'] is Map) {
      final map = data['branchStocks'] as Map;
      return map.map((k, v) => MapEntry(k.toString(), (v as num).toDouble()));
    }
    // Migration logic from old structure
    if (data['currentStock'] != null &&
        data['branchIds'] is List &&
        (data['branchIds'] as List).isNotEmpty) {
      final oldStock = (data['currentStock'] as num).toDouble();
      final String firstBranch = (data['branchIds'] as List).first.toString();
      return {firstBranch: oldStock};
    }
    return {};
  }

  static Map<String, double> _parseBranchThresholds(Map<String, dynamic> data) {
    if (data['branchMinThresholds'] is Map) {
      final map = data['branchMinThresholds'] as Map;
      return map.map((k, v) => MapEntry(k.toString(), (v as num).toDouble()));
    }
    // Migration logic
    if (data['minStockThreshold'] != null &&
        data['branchIds'] is List &&
        (data['branchIds'] as List).isNotEmpty) {
      final oldThreshold = (data['minStockThreshold'] as num).toDouble();
      final String firstBranch = (data['branchIds'] as List).first.toString();
      return {firstBranch: oldThreshold};
    }
    return {};
  }

  List<String> _effectiveBranchIds(List<String> branchIds) {
    // When the caller provides explicit filter branch IDs, use ONLY those.
    // This prevents unioning with the ingredient's own branchIds which
    // would inflate aggregated stock and mask per-branch stockouts.
    final filterIds = branchIds.where((id) => id.trim().isNotEmpty).toSet();
    if (filterIds.isNotEmpty) return filterIds.toList();

    // Fallback: no filter specified — use the ingredient's own branch list.
    final resolved = <String>{}
      ..addAll(this.branchIds.where((id) => id.trim().isNotEmpty));

    if (resolved.isEmpty) {
      resolved.addAll(branchStocks.keys.where((id) => id.trim().isNotEmpty));
    }
    if (resolved.isEmpty) {
      resolved.addAll(
        branchMinThresholds.keys.where((id) => id.trim().isNotEmpty),
      );
    }

    return resolved.toList();
  }

  // --- Static lookup maps ---
  static const List<String> categories = [
    'produce',
    'dairy',
    'meat',
    'spices',
    'dry_goods',
    'beverages',
    'other',
  ];

  static const List<String> units = [
    'kg',
    'g',
    'L',
    'mL',
    'pieces',
    'dozen',
    'bunch',
  ];

  static const List<String> allergens = [
    'gluten',
    'dairy',
    'nuts',
    'shellfish',
    'soy',
    'eggs',
    'sesame',
  ];

  static String categoryLabel(String cat) {
    const labels = {
      'produce': 'Produce',
      'dairy': 'Dairy',
      'meat': 'Meat',
      'spices': 'Spices',
      'dry_goods': 'Dry Goods',
      'beverages': 'Beverages',
      'other': 'Other',
    };
    return labels[cat] ?? cat;
  }

  static String allergenLabel(String a) {
    const labels = {
      'gluten': 'Gluten',
      'dairy': 'Dairy',
      'nuts': 'Nuts',
      'shellfish': 'Shellfish',
      'soy': 'Soy',
      'eggs': 'Eggs',
      'sesame': 'Sesame',
    };
    return labels[a] ?? a;
  }
}
