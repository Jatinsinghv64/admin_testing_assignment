import 'package:cloud_firestore/cloud_firestore.dart';

class ComboModel {
  final String comboId;
  final String name;
  final String? nameAr;
  final String description;
  final String? descriptionAr;
  final String? imageUrl;
  final List<String> itemIds; // References to menu_items collection
  final double originalTotalPrice;
  final double comboPrice;
  final bool isActive;
  final bool isLimitedTime;
  final DateTime? startDate;
  final DateTime? endDate;
  final List<int>? availableDays; // 1=Mon, 7=Sun
  final int? availableStartHour;
  final int? availableEndHour;
  final int maxQuantityPerOrder;
  final int sortOrder;
  final int orderCount;
  final List<String> branchIds;

  ComboModel({
    required this.comboId,
    required this.name,
    this.nameAr,
    required this.description,
    this.descriptionAr,
    this.imageUrl,
    required this.itemIds,
    required this.originalTotalPrice,
    required this.comboPrice,
    required this.isActive,
    required this.isLimitedTime,
    this.startDate,
    this.endDate,
    this.availableDays,
    this.availableStartHour,
    this.availableEndHour,
    this.maxQuantityPerOrder = 5,
    required this.sortOrder,
    this.orderCount = 0,
    required this.branchIds,
  });

  factory ComboModel.fromMap(Map<String, dynamic> map, String id) {
    // Robust branch parsing
    List<String> bIds = [];
    if (map['branchIds'] is List) {
      bIds = List<String>.from(map['branchIds'] as List);
    } else if (map['branchids'] is List) {
      bIds = List<String>.from(map['branchids'] as List);
    } else if (map['branchId'] is String && (map['branchId'] as String).isNotEmpty) {
      bIds = [map['branchId'] as String];
    }

    return ComboModel(
      comboId: id,
      name: map['name'] ?? '',
      nameAr: map['nameAr'] as String?,
      description: map['description'] ?? '',
      descriptionAr: map['descriptionAr'] as String?,
      imageUrl: map['imageUrl'],
      itemIds: List<String>.from(map['itemIds'] ?? []),
      originalTotalPrice:
          (map['originalTotalPrice'] as num?)?.toDouble() ?? 0.0,
      comboPrice: (map['comboPrice'] as num?)?.toDouble() ?? 0.0,
      isActive: map['isActive'] ?? false,
      isLimitedTime: map['isLimitedTime'] ?? false,
      startDate: (map['startDate'] as Timestamp?)?.toDate(),
      endDate: (map['endDate'] as Timestamp?)?.toDate(),
      availableDays: map['availableDays'] != null
          ? List<int>.from(map['availableDays'])
          : null,
      availableStartHour: map['availableStartHour'] as int?,
      availableEndHour: map['availableEndHour'] as int?,
      maxQuantityPerOrder: map['maxQuantityPerOrder'] ?? 5,
      sortOrder: map['sortOrder'] ?? 0,
      orderCount: map['orderCount'] ?? 0,
      branchIds: bIds,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'comboId': comboId,
      'name': name,
      if (nameAr != null && nameAr!.isNotEmpty) 'nameAr': nameAr,
      'description': description,
      if (descriptionAr != null && descriptionAr!.isNotEmpty)
        'descriptionAr': descriptionAr,
      'imageUrl': imageUrl,
      'itemIds': itemIds,
      'originalTotalPrice': originalTotalPrice,
      'comboPrice': comboPrice,
      'isActive': isActive,
      'isLimitedTime': isLimitedTime,
      'startDate': startDate != null ? Timestamp.fromDate(startDate!) : null,
      'endDate': endDate != null ? Timestamp.fromDate(endDate!) : null,
      'availableDays': availableDays,
      'availableStartHour': availableStartHour,
      'availableEndHour': availableEndHour,
      'maxQuantityPerOrder': maxQuantityPerOrder,
      'sortOrder': sortOrder,
      'orderCount': orderCount,
      'branchIds': branchIds,
    };
  }
}

class PromoSaleModel {
  final String saleId;
  final String name;
  final String? nameAr;
  final String description;
  final String? descriptionAr;
  final String imageUrl;
  final String discountType; // "percentage" or "fixed"
  final double discountValue;
  final String targetType; // "specific_items", "category", or "all"
  final List<String>? targetItemIds;
  final List<String>? targetCategoryIds;
  final DateTime startDate;
  final DateTime endDate;
  final bool isActive;
  final bool stackableWithCoupons;
  final double? minOrderValue;
  final double? maxDiscountCap;
  final int priority;
  final List<String> branchIds;

  PromoSaleModel({
    required this.saleId,
    required this.name,
    this.nameAr,
    required this.description,
    this.descriptionAr,
    required this.imageUrl,
    required this.discountType,
    required this.discountValue,
    required this.targetType,
    this.targetItemIds,
    this.targetCategoryIds,
    required this.startDate,
    required this.endDate,
    required this.isActive,
    required this.stackableWithCoupons,
    this.minOrderValue,
    this.maxDiscountCap,
    required this.priority,
    required this.branchIds,
  });

  factory PromoSaleModel.fromMap(Map<String, dynamic> map, String id) {
    // Robust branch parsing
    List<String> bIds = [];
    if (map['branchIds'] is List) {
      bIds = List<String>.from(map['branchIds'] as List);
    } else if (map['branchids'] is List) {
      bIds = List<String>.from(map['branchids'] as List);
    } else if (map['branchId'] is String && (map['branchId'] as String).isNotEmpty) {
      bIds = [map['branchId'] as String];
    }

    return PromoSaleModel(
      saleId: id,
      name: map['name'] ?? '',
      nameAr: map['nameAr'] as String?,
      description: map['description'] ?? '',
      descriptionAr: map['descriptionAr'] as String?,
      imageUrl: map['imageUrl'] ?? '',
      discountType: map['discountType'] ?? 'percentage',
      discountValue: (map['discountValue'] as num?)?.toDouble() ?? 0.0,
      targetType: map['targetType'] ?? 'all',
      targetItemIds: map['targetItemIds'] != null
          ? List<String>.from(map['targetItemIds'])
          : null,
      targetCategoryIds: map['targetCategoryIds'] != null
          ? List<String>.from(map['targetCategoryIds'])
          : null,
      startDate: (map['startDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      endDate: (map['endDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isActive: map['isActive'] ?? false,
      stackableWithCoupons: map['stackableWithCoupons'] ?? false,
      minOrderValue: (map['minOrderValue'] as num?)?.toDouble(),
      maxDiscountCap: (map['maxDiscountCap'] as num?)?.toDouble(),
      priority: map['priority'] ?? 0,
      branchIds: bIds,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'saleId': saleId,
      'name': name,
      if (nameAr != null && nameAr!.isNotEmpty) 'nameAr': nameAr,
      'description': description,
      if (descriptionAr != null && descriptionAr!.isNotEmpty)
        'descriptionAr': descriptionAr,
      'imageUrl': imageUrl,
      'discountType': discountType,
      'discountValue': discountValue,
      'targetType': targetType,
      'targetItemIds': targetItemIds,
      'targetCategoryIds': targetCategoryIds,
      'startDate': Timestamp.fromDate(startDate),
      'endDate': Timestamp.fromDate(endDate),
      'isActive': isActive,
      'stackableWithCoupons': stackableWithCoupons,
      'minOrderValue': minOrderValue,
      'maxDiscountCap': maxDiscountCap,
      'priority': priority,
      'branchIds': branchIds,
    };
  }
}
