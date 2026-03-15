import 'package:cloud_firestore/cloud_firestore.dart';

class IngredientModel {
  final String id;
  final List<String> branchIds;
  final String name;
  final String category;
  final String unit;
  final double costPerUnit;
  final double currentStock;
  final double minStockThreshold;
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
    required this.currentStock,
    required this.minStockThreshold,
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
  bool get isOutOfStock => currentStock <= 0;
  bool get isLowStock => currentStock > 0 && currentStock <= minStockThreshold;
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
      currentStock: (data['currentStock'] as num?)?.toDouble() ?? 0.0,
      minStockThreshold: (data['minStockThreshold'] as num?)?.toDouble() ?? 
                         (data['lowStockThreshold'] as num?)?.toDouble() ?? 0.0,
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
      'currentStock': currentStock,
      'minStockThreshold': minStockThreshold,
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
    double? currentStock,
    double? minStockThreshold,
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
      currentStock: currentStock ?? this.currentStock,
      minStockThreshold: minStockThreshold ?? this.minStockThreshold,
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
