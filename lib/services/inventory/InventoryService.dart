import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../constants.dart';
import '../../Models/IngredientModel.dart';
import '../../Models/RecipeModel.dart';
import '../ingredients/IngredientService.dart';

class InventoryService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final IngredientService _ingredientService = IngredientService();

  CollectionReference<Map<String, dynamic>> get _ingredientsCol =>
      _db.collection(AppConstants.collectionIngredients);

  CollectionReference<Map<String, dynamic>> get _movementsCol =>
      _db.collection(AppConstants.collectionStockMovements);

  CollectionReference<Map<String, dynamic>> get _recipesCol =>
      _db.collection(AppConstants.collectionRecipes);

  Stream<List<IngredientModel>> streamIngredients(List<String> branchIds, {bool isSuperAdmin = false}) {
    if (branchIds.isEmpty && !isSuperAdmin) return const Stream.empty();
    Query<Map<String, dynamic>> q =
        _ingredientsCol.where('isActive', isEqualTo: true);
    
    if (branchIds.isNotEmpty) {
      if (branchIds.length == 1) {
        q = q.where('branchIds', arrayContains: branchIds.first);
      } else {
        q = q.where('branchIds', arrayContainsAny: branchIds.take(10).toList());
      }
    }

    return q.snapshots().map((snap) {
      final list =
          snap.docs.map((d) => IngredientModel.fromFirestore(d)).toList();
      // Client-side sorting
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return list;
    });
  }

  Stream<List<RecipeModel>> streamRecipes(List<String> branchIds, {bool isSuperAdmin = false}) {
    if (branchIds.isEmpty && !isSuperAdmin) return const Stream.empty();
    Query<Map<String, dynamic>> q =
        _recipesCol.where('isActive', isEqualTo: true);
    
    if (branchIds.isNotEmpty) {
      if (branchIds.length == 1) {
        q = q.where('branchIds', arrayContains: branchIds.first);
      } else {
        q = q.where('branchIds', arrayContainsAny: branchIds.take(10).toList());
      }
    }

    return q.snapshots().map(
          (snap) => snap.docs.map((d) => RecipeModel.fromFirestore(d)).toList(),
        );
  }

  Future<List<IngredientModel>> getIngredients(
    List<String> branchIds, {
    bool includeInactive = false,
    bool isSuperAdmin = false,
  }) async {
    if (branchIds.isEmpty && !isSuperAdmin) return [];
    Query<Map<String, dynamic>> q = includeInactive
        ? _ingredientsCol
        : _ingredientsCol.where('isActive', isEqualTo: true);
    
    if (branchIds.isNotEmpty) {
      if (branchIds.length == 1) {
        q = q.where('branchIds', arrayContains: branchIds.first);
      } else {
        q = q.where('branchIds', arrayContainsAny: branchIds.take(10).toList());
      }
    }

    final snap = await q.get();
    final list =
        snap.docs.map((d) => IngredientModel.fromFirestore(d)).toList();
    // Client-side sorting
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  Future<List<Map<String, dynamic>>> getStockMovements(
    List<String> branchIds, {
    DateTime? start,
    DateTime? end,
    String? movementType,
    bool isSuperAdmin = false,
  }) async {
    if (branchIds.isEmpty && !isSuperAdmin) return [];
    Query<Map<String, dynamic>> q = _movementsCol;
    
    if (branchIds.isNotEmpty) {
      if (branchIds.length == 1) {
        q = q.where('branchIds', arrayContains: branchIds.first);
      } else {
        q = q.where('branchIds', arrayContainsAny: branchIds.take(10).toList());
      }
    }

    if (movementType != null && movementType.isNotEmpty) {
      q = q.where('movementType', isEqualTo: movementType);
    }
    if (start != null) {
      q = q.where(
        'createdAt',
        isGreaterThanOrEqualTo: Timestamp.fromDate(start),
      );
    }
    if (end != null) {
      q = q.where(
        'createdAt',
        isLessThanOrEqualTo: Timestamp.fromDate(end),
      );
    }
    final snap = await q.get();
    final list = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    // Client-side sorting
    list.sort((a, b) {
      final dateA = (a['createdAt'] as Timestamp?)?.toDate() ?? DateTime(0);
      final dateB = (b['createdAt'] as Timestamp?)?.toDate() ?? DateTime(0);
      return dateB.compareTo(dateA); // descending
    });
    return list;
  }

  Stream<List<Map<String, dynamic>>> streamRecentMovements(
    List<String> branchIds, {
    int limit = 10,
    bool isSuperAdmin = false,
  }) {
    if (branchIds.isEmpty && !isSuperAdmin) return const Stream.empty();
    Query<Map<String, dynamic>> q = _movementsCol;
    
    if (branchIds.isNotEmpty) {
      if (branchIds.length == 1) {
        q = q.where('branchIds', arrayContains: branchIds.first);
      } else {
        q = q.where('branchIds', arrayContainsAny: branchIds.take(10).toList());
      }
    }

    // Fetch and sort on client to avoid composite index requirement
    return q.snapshots().map((snap) {
      final list = snap.docs
          .map((d) => {
                'id': d.id,
                ...d.data(),
              })
          .toList();
      list.sort((a, b) {
        final dateA = (a['createdAt'] as Timestamp?)?.toDate() ?? DateTime(0);
        final dateB = (b['createdAt'] as Timestamp?)?.toDate() ?? DateTime(0);
        return dateB.compareTo(dateA); // descending
      });
      return list.take(limit).toList();
    });
  }

  Stream<List<Map<String, dynamic>>> streamIngredientMovements(
    List<String> branchIds,
    String ingredientId, {
    bool isSuperAdmin = false,
  }) {
    if (branchIds.isEmpty && !isSuperAdmin || ingredientId.isEmpty) return const Stream.empty();
    Query<Map<String, dynamic>> q =
        _movementsCol.where('ingredientId', isEqualTo: ingredientId);
    
    if (branchIds.isNotEmpty) {
      if (branchIds.length == 1) {
        q = q.where('branchIds', arrayContains: branchIds.first);
      } else {
        q = q.where('branchIds', arrayContainsAny: branchIds.take(10).toList());
      }
    }

    return q.snapshots().map((snap) {
      final list = snap.docs
          .map((d) => {
                'id': d.id,
                ...d.data(),
              })
          .toList();
      // Client-side sorting
      list.sort((a, b) {
        final dateA = (a['createdAt'] as Timestamp?)?.toDate() ?? DateTime(0);
        final dateB = (b['createdAt'] as Timestamp?)?.toDate() ?? DateTime(0);
        return dateB.compareTo(dateA); // descending
      });
      return list;
    });
  }

  Future<double> manualAdjustStock({
    required String ingredientId,
    required List<String> branchIds,
    required double delta,
    required String reason,
    required String recordedBy,
    String? note,
  }) {
    final mergedReason = (note?.trim().isNotEmpty ?? false)
        ? '$reason | ${note!.trim()}'
        : reason;
    return _ingredientService.adjustStock(
      ingredientId: ingredientId,
      branchIds: branchIds,
      delta: delta,
      movementType: 'manual_adjustment',
      recordedBy: recordedBy,
      reason: mergedReason,
    );
  }

  Future<int> applyStocktake({
    required List<String> branchIds,
    required String recordedBy,
    required Map<IngredientModel, double> actualCounts,
    Map<String, String>? reasons,
    Map<String, String>? notes,
  }) async {
    int updated = 0;
    for (final entry in actualCounts.entries) {
      final ingredient = entry.key;
      final actual = entry.value;
      final delta = actual - ingredient.currentStock;
      if (delta == 0) continue;

      final reason = reasons?[ingredient.id] ?? 'Stocktake adjustment';
      final note = notes?[ingredient.id];
      final mergedReason = (note?.trim().isNotEmpty ?? false)
          ? '$reason | ${note!.trim()}'
          : reason;

      await _ingredientService.adjustStock(
        ingredientId: ingredient.id,
        branchIds: branchIds,
        delta: delta,
        movementType: 'stocktake',
        recordedBy: recordedBy,
        reason: mergedReason,
      );
      updated++;
    }
    return updated;
  }

  static double? convertQuantity(double qty, String fromUnit, String toUnit) {
    return IngredientService.convertUnit(qty, fromUnit, toUnit);
  }

  /// Auto-deducts ingredient stock for a completed order.
  /// Called after an order reaches a terminal status (delivered/paid/collected).
  /// Guards against double-deduction by checking the [inventoryDeducted] flag.
  Future<void> deductForOrder({
    required String orderId,
    required List<String> branchIds,
    required String recordedBy,
  }) async {
    try {
      await _db.runTransaction((transaction) async {
        await performDeductionInTransaction(
          transaction: transaction,
          orderId: orderId,
          branchIds: branchIds,
          recordedBy: recordedBy,
        );
      }).timeout(const Duration(seconds: 30));
    } catch (e, stack) {
      debugPrint('❌ InventoryService.deductForOrder error: $e\n$stack');
    }
  }

  /// Core logic for inventory deduction that can be used within an existing transaction.
  /// INDUSTRY GRADE: Ensures atomicity when bundled with order status updates.
  Future<void> performDeductionInTransaction({
    required Transaction transaction,
    required String orderId,
    required List<String> branchIds,
    required String recordedBy,
  }) async {
    final orderRef = _db.collection(AppConstants.collectionOrders).doc(orderId);
    final orderSnap = await transaction.get(orderRef);
    
    if (!orderSnap.exists) return;
    final orderData = orderSnap.data()!;

    // Guard: already deducted
    if (orderData['inventoryDeducted'] == true) return;

    final rawItems = (orderData['items'] ?? orderData['orderItems'] ?? [])
        as List<dynamic>;
    
    if (rawItems.isNotEmpty) {
      await deductItemsInTransaction(
        transaction: transaction,
        items: rawItems.cast<Map<String, dynamic>>(),
        branchIds: branchIds.isNotEmpty ? branchIds : List<String>.from(orderData['branchIds'] ?? []),
        orderId: orderId,
        recordedBy: recordedBy,
      );
    }

    transaction.update(orderRef, {'inventoryDeducted': true});
  }

  /// Deducts a specific list of items in a transaction.
  /// Useful for "append order" flows or direct item deductions.
  Future<void> deductItemsInTransaction({
    required Transaction transaction,
    required List<Map<String, dynamic>> items,
    required List<String> branchIds,
    required String orderId,
    required String recordedBy,
    String batchKey = 'main',
    String reason = 'Inventory deduction',
  }) async {
    await _applyInventoryDeltaInTransaction(
      transaction: transaction,
      items: items,
      branchIds: branchIds,
      orderId: orderId,
      recordedBy: recordedBy,
      movementType: 'order_deduction',
      reason: reason,
      batchKey: batchKey,
      direction: -1,
    );
  }

  /// Restores ingredient stock for a cancelled order or item.
  /// Reverts the deductions made by [deductItemsInTransaction].
  Future<void> restoreForOrder({
    required String orderId,
    required List<String> branchIds,
    required String recordedBy,
  }) async {
    try {
      await _db.runTransaction((transaction) async {
        final orderRef = _db.collection(AppConstants.collectionOrders).doc(orderId);
        final orderSnap = await transaction.get(orderRef);
        
        if (!orderSnap.exists) return;
        final orderData = orderSnap.data()!;

        // Guard: nothing to restore
        if (orderData['inventoryDeducted'] != true) return;
        if (orderData['inventoryRestored'] == true) return;

        final rawItems = (orderData['items'] ?? orderData['orderItems'] ?? [])
            as List<dynamic>;
        
        if (rawItems.isNotEmpty) {
          await restoreItemsInTransaction(
            transaction: transaction,
            items: rawItems.cast<Map<String, dynamic>>(),
            branchIds: branchIds.isNotEmpty ? branchIds : List<String>.from(orderData['branchIds'] ?? []),
            orderId: orderId,
            recordedBy: recordedBy,
            reason: 'Order cancellation restoration',
          );
        }

        transaction.update(orderRef, {'inventoryRestored': true});
      }).timeout(const Duration(seconds: 30));
    } catch (e, stack) {
      debugPrint('❌ InventoryService.restoreForOrder error: $e\n$stack');
    }
  }

  /// Restores stock for a specific list of items in a transaction.
  Future<void> restoreItemsInTransaction({
    required Transaction transaction,
    required List<Map<String, dynamic>> items,
    required List<String> branchIds,
    required String orderId,
    required String recordedBy,
    required String reason,
    String batchKey = 'main',
  }) async {
    await _applyInventoryDeltaInTransaction(
      transaction: transaction,
      items: items,
      branchIds: branchIds,
      orderId: orderId,
      recordedBy: recordedBy,
      movementType: 'order_restoration',
      reason: reason,
      batchKey: batchKey,
      direction: 1,
    );
  }

  Future<void> _applyInventoryDeltaInTransaction({
    required Transaction transaction,
    required List<Map<String, dynamic>> items,
    required List<String> branchIds,
    required String orderId,
    required String recordedBy,
    required String movementType,
    required String reason,
    required String batchKey,
    required int direction,
  }) async {
    final normalizedBatchKey = batchKey.trim().isEmpty ? 'main' : batchKey.trim();
    final operationRef = _db
        .collection(AppConstants.collectionOrders)
        .doc(orderId)
        .collection('inventoryOperations')
        .doc('${movementType}_$normalizedBatchKey');

    final operationSnap = await transaction.get(operationRef);
    if (operationSnap.exists && operationSnap.data()?['applied'] == true) {
      return;
    }

    final Map<String, double> runningBalances = {};
    final List<Function()> pendingWrites = [];

    for (int itemIndex = 0; itemIndex < items.length; itemIndex++) {
      final item = items[itemIndex];
      final menuItemId = (item['menuItemId'] ?? item['itemId'] ?? item['productId'] ?? '').toString();
      final int itemQuantity = (item['quantity'] as num?)?.toInt() ?? 1;
      if (menuItemId.isEmpty || itemQuantity <= 0) continue;

      final menuRef = _db.collection(AppConstants.collectionMenuItems).doc(menuItemId);
      final menuSnap = await transaction.get(menuRef);
      if (!menuSnap.exists) continue;

      final recipeId = (menuSnap.data()?['recipeId'] ?? '').toString();
      DocumentSnapshot? recipeSnap;

      if (recipeId.isNotEmpty) {
        final recipeRef = _db.collection(AppConstants.collectionRecipes).doc(recipeId);
        recipeSnap = await transaction.get(recipeRef);
      }

      if (recipeSnap == null || !recipeSnap.exists) {
        // Fallback: If no direct recipeId, we skip. 
        // We removed the .get() query here because it violates transaction rules on Web.
        continue;
      }

      final recipeData = recipeSnap?.data() as Map<String, dynamic>? ?? {};
      final recipeIngredients = List<Map<String, dynamic>>.from(recipeData['ingredients'] ?? []);
      if (recipeIngredients.isEmpty) continue;

      for (final ri in recipeIngredients) {
        final ingredientId = (ri['ingredientId'] ?? '').toString();
        if (ingredientId.isEmpty) continue;

        final double recipeQty = (ri['quantity'] as num?)?.toDouble() ?? 0.0;
        final String recipeUnit = (ri['unit'] ?? '').toString();

        final ingRef = _ingredientsCol.doc(ingredientId);
        final ingSnap = await transaction.get(ingRef);
        if (!ingSnap.exists) continue;

        final ingData = ingSnap.data()!;
        final String ingUnit = (ingData['unit'] ?? '').toString();
        final double before = runningBalances[ingredientId] ??
            (ingData['currentStock'] as num?)?.toDouble() ??
            0.0;

        double adjustedQty = recipeQty * itemQuantity;
        if (recipeUnit != ingUnit) {
          final converted = IngredientService.convertUnit(adjustedQty, recipeUnit, ingUnit);
          if (converted == null) continue;
          adjustedQty = converted;
        }
        if (adjustedQty <= 0) continue;

        final signedQty = adjustedQty * direction;
        final rawAfter = before + signedQty;
        final double after = direction < 0 ? rawAfter.clamp(0.0, double.infinity) : rawAfter;
        final bool clamped = direction < 0 && rawAfter < 0;

        runningBalances[ingredientId] = after;

        pendingWrites.add(() {
          transaction.update(ingRef, {
            'currentStock': after,
            'updatedAt': FieldValue.serverTimestamp(),
          });

          final movRef = _movementsCol.doc();
          transaction.set(movRef, {
            'branchIds': branchIds,
            'ingredientId': ingredientId,
            'ingredientName': (ingData['name'] ?? '').toString(),
            'movementType': movementType,
            'quantity': signedQty,
            'balanceBefore': before,
            'balanceAfter': after,
            'referenceId': orderId,
            'batchKey': normalizedBatchKey,
            'itemIndex': itemIndex,
            'menuItemId': menuItemId,
            'recipeId': recipeSnap?.id,
            'reason': reason,
            if (clamped) 'warning': 'Stock clamped to 0 (insufficient stock)',
            'recordedBy': recordedBy,
            'createdAt': FieldValue.serverTimestamp(),
          });
        });
      }
    }

    for (final write in pendingWrites) {
      write();
    }

    transaction.set(operationRef, {
      'applied': true,
      'movementType': movementType,
      'batchKey': normalizedBatchKey,
      'itemCount': items.length,
      'recordedBy': recordedBy,
      'createdAt': FieldValue.serverTimestamp(),
      'reason': reason,
    });
  }
}
