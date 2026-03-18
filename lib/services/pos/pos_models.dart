// lib/services/pos/pos_models.dart
// Data models for the POS system

import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a single item in the POS cart
class PosCartItem {
  final String productId;
  final String name;
  final String? nameAr; // Arabic name for bilingual receipt
  final double price;
  final String? imageUrl;
  final String? categoryId;
  final String? categoryName;
  int quantity;
  String notes; // Kitchen notes
  double discountPercent; // Per-item discount (0-100)
  List<PosAddon> addons;
  bool isAddOn; // Flag for items added to an existing order

  PosCartItem({
    required this.productId,
    required this.name,
    this.nameAr,
    required this.price,
    this.imageUrl,
    this.categoryId,
    this.categoryName,
    this.quantity = 1,
    this.notes = '',
    this.discountPercent = 0,
    this.addons = const [],
    this.isAddOn = false,
  });

  double get subtotal {
    double addonTotal = addons.fold(0.0, (acc, a) => acc + a.price * quantity);
    double itemTotal = price * quantity;
    double discount = itemTotal * (discountPercent / 100);
    // Round to 2 decimal places to prevent floating point inaccuracies in currency
    return double.parse((itemTotal - discount + addonTotal).toStringAsFixed(2));
  }

  /// Convert to Firestore-compatible map (matches existing order item schema)
  Map<String, dynamic> toOrderItemMap() {
    return {
      'productId': productId,
      // ── SYNC FIX: Also write menuItemId / itemId so InventoryService
      // deductForOrder can locate recipes linked to this menu item. ──
      'menuItemId': productId,
      'itemId': productId,
      'name': name,
      if (nameAr != null) 'nameAr': nameAr,
      'price': price,
      'quantity': quantity,
      'total': subtotal,
      if (notes.isNotEmpty) 'notes': notes,
      if (discountPercent > 0) 'discountPercent': discountPercent,
      if (imageUrl != null) 'imageUrl': imageUrl,
      if (addons.isNotEmpty) 'addons': addons.map((a) => a.toMap()).toList(),
      if (isAddOn) 'isAddOn': true,
    };
  }

  PosCartItem copyWith({
    int? quantity,
    String? notes,
    double? discountPercent,
    List<PosAddon>? addons,
  }) {
    return PosCartItem(
      productId: productId,
      name: name,
      nameAr: nameAr,
      price: price,
      imageUrl: imageUrl,
      categoryId: categoryId,
      categoryName: categoryName,
      quantity: quantity ?? this.quantity,
      notes: notes ?? this.notes,
      discountPercent: discountPercent ?? this.discountPercent,
      addons: addons ?? this.addons,
      isAddOn: isAddOn,
    );
  }
}

/// Addon item for a cart product
class PosAddon {
  final String name;
  final double price;

  PosAddon({required this.name, required this.price});

  Map<String, dynamic> toMap() => {'name': name, 'price': price};
}

/// Payment record
class PosPayment {
  final String method; // 'cash', 'card', 'online'
  final String? label;
  final double amount; // Tendered amount
  final double change;
  final double appliedAmount; // Amount actually applied to the order total
  final List<PosPayment> splits;
  final DateTime timestamp;

  PosPayment({
    required this.method,
    this.label,
    required this.amount,
    this.change = 0,
    double? appliedAmount,
    List<PosPayment> splits = const [],
    DateTime? timestamp,
  })  : appliedAmount = _roundMoney(
          appliedAmount ?? ((amount - change) < 0 ? 0 : (amount - change)),
        ),
        splits = List<PosPayment>.unmodifiable(splits),
        timestamp = timestamp ?? DateTime.now();

  bool get isSplit => splits.isNotEmpty;

  double get remainingFromTendered => _roundMoney(amount - change);

  Map<String, dynamic> toMap() => {
        'method': method,
        if (label != null && label!.isNotEmpty) 'label': label,
        'amount': _roundMoney(amount),
        'change': _roundMoney(change),
        'appliedAmount': _roundMoney(appliedAmount),
        'timestamp': Timestamp.fromDate(timestamp),
        if (splits.isNotEmpty)
          'payments': splits.map((payment) => payment.toMap()).toList(),
      };

  static double _roundMoney(double value) =>
      double.parse(value.toStringAsFixed(2));
}

/// Order types for POS (Delivery is handled separately via Delivery Orders panel)
enum PosOrderType {
  dineIn,
  takeaway,
}

extension PosOrderTypeExtension on PosOrderType {
  String get firestoreValue {
    switch (this) {
      case PosOrderType.dineIn:
        return 'dine_in';
      case PosOrderType.takeaway:
        return 'takeaway';
    }
  }

  String get displayName {
    switch (this) {
      case PosOrderType.dineIn:
        return 'Dine-in';
      case PosOrderType.takeaway:
        return 'Takeaway';
    }
  }

  IconDataLike get icon {
    switch (this) {
      case PosOrderType.dineIn:
        return IconDataLike(0xe56c); // Icons.restaurant
      case PosOrderType.takeaway:
        return IconDataLike(0xef49); // Icons.takeout_dining
    }
  }

  /// Safely parse a string into a PosOrderType. Falls back to [takeaway].
  static PosOrderType fromString(String? value) {
    if (value == null || value.isEmpty) return PosOrderType.takeaway;
    final cleaned =
        value.toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');
    if (cleaned == 'dine_in' || cleaned == 'dinein') return PosOrderType.dineIn;
    return PosOrderType.takeaway;
  }
}

/// Placeholder so we don't need to import material in this model file
class IconDataLike {
  final int codePoint;
  IconDataLike(this.codePoint);
}
