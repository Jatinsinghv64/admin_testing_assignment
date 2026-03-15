import 'package:cloud_firestore/cloud_firestore.dart';
import '../../constants.dart';
import '../ingredients/IngredientService.dart';

class WasteService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final IngredientService _ingredientService = IngredientService();

  CollectionReference<Map<String, dynamic>> get _wasteCol =>
      _db.collection(AppConstants.collectionWasteEntries);

  CollectionReference<Map<String, dynamic>> get _menuItemsCol =>
      _db.collection(AppConstants.collectionMenuItems);

  CollectionReference<Map<String, dynamic>> get _ingredientsCol =>
      _db.collection(AppConstants.collectionIngredients);

  Stream<List<Map<String, dynamic>>> streamWasteEntries(
    List<String> branchIds, {
    int limit = 300,
    bool isSuperAdmin = false,
  }) {
    if (branchIds.isEmpty && !isSuperAdmin) return const Stream.empty();
    Query<Map<String, dynamic>> q = _wasteCol;
    
    if (branchIds.isNotEmpty) {
      if (branchIds.length == 1) {
        q = q.where('branchIds', arrayContains: branchIds.first);
      } else {
        // Firestore limit: arrayContainsAny handles max 10
        q = q.where('branchIds', arrayContainsAny: branchIds.take(10).toList());
      }
    } else if (isSuperAdmin) {
      // Super admin sees all if no specific branch filter is passed
    }

    return q
        .orderBy('wasteDate', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => {
                    'id': d.id,
                    ...d.data(),
                  })
              .toList(),
        );
  }

  Future<List<Map<String, dynamic>>> getWasteEntriesByRange(
    List<String> branchIds, {
    required DateTime start,
    required DateTime end,
    bool isSuperAdmin = false,
  }) async {
    if (branchIds.isEmpty && !isSuperAdmin) return [];
    Query<Map<String, dynamic>> q = _wasteCol;

    if (branchIds.isNotEmpty) {
      if (branchIds.length == 1) {
        q = q.where('branchIds', arrayContains: branchIds.first);
      } else {
        q = q.where('branchIds', arrayContainsAny: branchIds.take(10).toList());
      }
    }

    final snap = await q
        .where('wasteDate', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('wasteDate', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .orderBy('wasteDate', descending: true)
        .get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  Stream<List<Map<String, dynamic>>> streamIngredients(List<String> branchIds, {bool isSuperAdmin = false}) {
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

    return q.orderBy('name').snapshots().map(
          (snap) => snap.docs
              .map((d) => {
                    'id': d.id,
                    ...d.data(),
                  })
              .toList(),
        );
  }

  Stream<List<Map<String, dynamic>>> streamMenuItems(List<String> branchIds, {bool isSuperAdmin = false}) {
    if (branchIds.isEmpty && !isSuperAdmin) return const Stream.empty();
    Query<Map<String, dynamic>> q = _menuItemsCol;
    
    if (branchIds.isNotEmpty) {
      if (branchIds.length == 1) {
        q = q.where('branchIds', arrayContains: branchIds.first);
      } else {
        q = q.where('branchIds', arrayContainsAny: branchIds.take(10).toList());
      }
    }

    return q.orderBy('name').snapshots().map(
          (snap) => snap.docs
              .map((d) => {
                    'id': d.id,
                    ...d.data(),
                  })
              .toList(),
        );
  }

  Future<String> addWasteEntry({
    required List<String> branchIds,
    required String itemType,
    required String itemId,
    required String itemName,
    required String unit,
    required double quantity,
    required String reason,
    String? reasonNote,
    required double estimatedLoss,
    required DateTime wasteDate,
    required String recordedBy,
    String? notes,
    List<String> photoUrls = const [],
  }) async {
    final doc = _wasteCol.doc();
    final now = Timestamp.fromDate(DateTime.now());
    await doc.set({
      'branchIds': branchIds,
      'itemType': itemType,
      'itemId': itemId,
      'itemName': itemName,
      'unit': unit,
      'quantity': quantity,
      'reason': reason,
      'reasonNote': reasonNote,
      'estimatedLoss': estimatedLoss,
      'wasteDate': Timestamp.fromDate(wasteDate),
      'recordedBy': recordedBy,
      'notes': notes,
      'photoUrls': photoUrls,
      'createdAt': now,
      'updatedAt': now,
      'inventoryDeducted': false,
    });

    if (itemType == 'ingredient') {
      final delta = -quantity;
      await _ingredientService.adjustStock(
        ingredientId: itemId,
        branchIds: branchIds,
        delta: delta,
        movementType: 'waste',
        recordedBy: recordedBy,
        referenceId: doc.id,
        reason: 'Waste entry: $reason',
      );
      await doc.update({'inventoryDeducted': true});
    }

    return doc.id;
  }

  Future<void> deleteWasteEntry(String wasteEntryId) async {
    await _db.runTransaction((tx) async {
      final ref = _wasteCol.doc(wasteEntryId);
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final data = snap.data()!;
      final itemType = (data['itemType'] ?? '').toString();
      final deducted = data['inventoryDeducted'] == true;
      final itemId = (data['itemId'] ?? '').toString();
      final branchIdsRaw = data['branchIds'];
    final branchId = branchIdsRaw is List
        ? (branchIdsRaw.isNotEmpty ? branchIdsRaw.first.toString() : '')
        : (branchIdsRaw ?? data['branchId'] ?? '').toString();
      final qty = (data['quantity'] as num?)?.toDouble() ?? 0.0;

      tx.delete(ref);

      if (itemType == 'ingredient' &&
          deducted &&
          itemId.isNotEmpty &&
          qty > 0) {
        final ingRef = _ingredientsCol.doc(itemId);
        final ingSnap = await tx.get(ingRef);
        if (ingSnap.exists) {
          final ing = ingSnap.data()!;
          final before = (ing['currentStock'] as num?)?.toDouble() ?? 0.0;
          final after = before + qty;
          tx.update(ingRef, {
            'currentStock': after,
            'updatedAt': Timestamp.fromDate(DateTime.now()),
          });
          final movRef =
              _db.collection(AppConstants.collectionStockMovements).doc();
          tx.set(movRef, {
            'branchIds': branchId.isNotEmpty ? [branchId] : [],
            'ingredientId': itemId,
            'ingredientName': (data['itemName'] ?? '').toString(),
            'movementType': 'manual_adjustment',
            'quantity': qty,
            'balanceBefore': before,
            'balanceAfter': after,
            'referenceId': wasteEntryId,
            'reason': 'Waste entry deletion rollback',
            'recordedBy': 'system',
            'createdAt': Timestamp.fromDate(DateTime.now()),
          });
        }
      }
    });
  }
}
