import 'package:cloud_firestore/cloud_firestore.dart';
import '../../constants.dart';

class PurchaseOrderService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _poCol =>
      _db.collection(AppConstants.collectionPurchaseOrders);

  CollectionReference<Map<String, dynamic>> get _suppliersCol =>
      _db.collection(AppConstants.collectionSuppliers);

  CollectionReference<Map<String, dynamic>> get _ingredientsCol =>
      _db.collection(AppConstants.collectionIngredients);

  CollectionReference<Map<String, dynamic>> get _movementsCol =>
      _db.collection(AppConstants.collectionStockMovements);

  Stream<List<Map<String, dynamic>>> streamSuppliers(
    List<String> branchIds, {
    bool? isActive,
  }) {
    if (branchIds.isEmpty) return const Stream.empty();
    Query<Map<String, dynamic>> q = _suppliersCol;
    if (branchIds.length == 1) {
      q = q.where('branchIds', arrayContains: branchIds.first);
    } else {
      q = q.where('branchIds', arrayContainsAny: branchIds.take(10).toList());
    }
    if (isActive != null) {
      q = q.where('isActive', isEqualTo: isActive);
    }
    return q.snapshots().map(
      (snap) {
        final docs = snap.docs
            .map((d) => {
                  'id': d.id,
                  ...d.data(),
                })
            .toList();
        // Client-side sorting to avoid composite index requirement
        docs.sort((a, b) {
          final nameA = (a['companyName'] ?? '').toString().toLowerCase();
          final nameB = (b['companyName'] ?? '').toString().toLowerCase();
          return nameA.compareTo(nameB);
        });
        return docs;
      },
    );
  }

  Future<void> saveSupplier({
    String? supplierId,
    required List<String> branchIds,
    required Map<String, dynamic> data,
  }) async {
    final doc = supplierId == null
        ? _suppliersCol.doc()
        : _suppliersCol.doc(supplierId);
    final now = Timestamp.fromDate(DateTime.now());
    final payload = {
      ...data,
      'branchIds': branchIds,
      'updatedAt': now,
      if (supplierId == null) 'createdAt': now,
    };
    if (supplierId == null) {
      await doc.set(payload);
    } else {
      await doc.update(payload);
    }
  }

  Stream<List<Map<String, dynamic>>> streamPurchaseOrders(
    List<String> branchIds, {
    String status = 'all',
    String? supplierId,
  }) {
    if (branchIds.isEmpty) return const Stream.empty();
    Query<Map<String, dynamic>> q = _poCol;
    if (branchIds.length == 1) {
      q = q.where('branchIds', arrayContains: branchIds.first);
    } else {
      q = q.where('branchIds', arrayContainsAny: branchIds.take(10).toList());
    }
    if (status != 'all') {
      q = q.where('status', isEqualTo: status);
    }
    if (supplierId != null && supplierId.isNotEmpty) {
      q = q.where('supplierId', isEqualTo: supplierId);
    }

    return q.snapshots().map(
      (snap) {
        final docs = snap.docs
            .map((d) => {
                  'id': d.id,
                  ...d.data(),
                })
            .toList();
        // Client-side sorting to avoid composite index requirement
        docs.sort((a, b) {
          final dateA = (a['createdAt'] as Timestamp?)?.toDate() ?? DateTime(0);
          final dateB = (b['createdAt'] as Timestamp?)?.toDate() ?? DateTime(0);
          return dateB.compareTo(dateA); // descending
        });
        return docs;
      },
    );
  }

  Future<List<Map<String, dynamic>>> getPurchaseOrdersByRange(
    List<String> branchIds, {
    required DateTime start,
    required DateTime end,
    List<String>? statuses,
  }) async {
    if (branchIds.isEmpty) return [];
    Query<Map<String, dynamic>> q = _poCol;
    if (branchIds.length == 1) {
      q = q.where('branchIds', arrayContains: branchIds.first);
    } else {
      q = q.where('branchIds', arrayContainsAny: branchIds.take(10).toList());
    }
    q = q
        .where('orderDate', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('orderDate', isLessThanOrEqualTo: Timestamp.fromDate(end));
    if (statuses != null && statuses.isNotEmpty) {
      q = q.where('status', whereIn: statuses.take(10).toList());
    }
    final snap = await q.get();
    final docs = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    // Client-side sorting
    docs.sort((a, b) {
      final dateA = (a['orderDate'] as Timestamp?)?.toDate() ?? DateTime(0);
      final dateB = (b['orderDate'] as Timestamp?)?.toDate() ?? DateTime(0);
      return dateB.compareTo(dateA); // descending
    });
    return docs;
  }

  Future<String> generatePoNumber(List<String> branchIds) async {
    final now = DateTime.now();
    final yyyyMm = '${now.year}${now.month.toString().padLeft(2, '0')}';
    final prefix = 'PO-$yyyyMm-';

    Query<Map<String, dynamic>> query = _poCol;
    if (branchIds.isNotEmpty) {
      query = query.where('branchIds', arrayContainsAny: branchIds.take(10).toList());
    }
    
    final latest = await query
        .orderBy('createdAt', descending: true)
        .limit(50)
        .get();

    int maxN = 0;
    for (final d in latest.docs) {
      final po = (d.data()['poNumber'] ?? '').toString();
      if (po.startsWith(prefix)) {
        final n = int.tryParse(po.substring(prefix.length)) ?? 0;
        if (n > maxN) maxN = n;
      }
    }
    return '$prefix${(maxN + 1).toString().padLeft(3, '0')}';
  }

  Future<String> createPurchaseOrder({
    required List<String> branchIds,
    required Map<String, dynamic> data,
    required String? userId,
    required String? userName,
  }) async {
    final doc = _poCol.doc();
    final now = Timestamp.fromDate(DateTime.now());
    await doc.set({
      ...data,
      'branchIds': branchIds,
      'createdAt': now,
      'updatedAt': now,
      'createdById': userId,
      'createdBy': userName,
      'history': FieldValue.arrayUnion([
        {
          'action': 'created',
          'userId': userId,
          'userName': userName,
          'timestamp': now,
        }
      ]),
    });
    return doc.id;
  }

  Future<void> updatePurchaseOrder({
    required String id,
    required Map<String, dynamic> updates,
    required String? userId,
    required String? userName,
  }) async {
    final now = Timestamp.fromDate(DateTime.now());
    await _poCol.doc(id).update({
      ...updates,
      'updatedAt': now,
      'updatedById': userId,
      'updatedBy': userName,
      'history': FieldValue.arrayUnion([
        {
          'action': 'updated',
          'userId': userId,
          'userName': userName,
          'timestamp': now,
          'changes': updates.keys.toList(),
        }
      ]),
    });
  }

  Future<void> deletePurchaseOrder({
    required String id,
    required String? userId,
    required String? userName,
  }) async {
    final now = Timestamp.fromDate(DateTime.now());
    // Log the deletion in history before deleting the document
    // Note: Since we are about to hard-delete, this record will be lost unless we moved it to a separate log.
    // However, to satisfy "id should be saved in logs", I will implement a soft-delete or a separate audit log.
    // In this codebase, let's use a separate 'audit_logs' collection if it exists, or just do a soft-delete status update.
    
    // Changing to soft-delete to preserve history as requested
    await _poCol.doc(id).update({
      'status': 'deleted',
      'updatedAt': now,
      'history': FieldValue.arrayUnion([
        {
          'action': 'deleted',
          'userId': userId,
          'userName': userName,
          'timestamp': now,
        }
      ]),
    });
  }

  Future<void> duplicateAsDraft(
    String poId, {
    required String? userId,
    required String? userName,
  }) async {
    final snap = await _poCol.doc(poId).get();
    if (!snap.exists) throw Exception('Purchase order not found');
    final data = Map<String, dynamic>.from(snap.data()!);
    final newNumber =
        await generatePoNumber(List<String>.from(data['branchIds'] ?? []));
    
    // Remove metadata that should not be duplicated
    data.remove('id');
    data.remove('createdAt');
    data.remove('updatedAt');
    data.remove('history');
    data.remove('receivedDate');
    data.remove('lineItems'); // Optional: should we clear received quantities? Yes.
    
    final lineItems = List<Map<String, dynamic>>.from(snap.data()!['lineItems'] ?? []);
    final resetItems = lineItems.map((item) {
      final newItem = Map<String, dynamic>.from(item);
      newItem['receivedQty'] = 0.0;
      return newItem;
    }).toList();

    await createPurchaseOrder(
      branchIds: List<String>.from(data['branchIds'] ?? []),
      data: {
        ...data,
        'poNumber': newNumber,
        'status': 'draft',
        'lineItems': resetItems,
      },
      userId: userId,
      userName: userName,
    );
  }

  Future<void> receivePurchaseOrder({
    required String poId,
    required String? userId,
    required String? userName,
    required DateTime receivedDate,
    required List<Map<String, dynamic>> receivedItems,
    required bool fullReceipt,
    String? notes,
  }) async {
    await _db.runTransaction((tx) async {
      final recordedBy = userName ?? userId ?? 'system';
      final poRef = _poCol.doc(poId);
      final poSnap = await tx.get(poRef);
      if (!poSnap.exists) throw Exception('Purchase order not found');
      final po = poSnap.data()!;
      final branchIds = List<String>.from(po['branchIds'] ?? []);

      for (final row in receivedItems) {
        final ingredientId = (row['ingredientId'] ?? '').toString();
        if (ingredientId.isEmpty) continue;
        final receivedQty = (row['receivedQty'] as num?)?.toDouble() ?? 0.0;
        final unitCost = (row['unitCost'] as num?)?.toDouble() ?? 0.0;
        if (receivedQty <= 0) continue;

        final ingRef = _ingredientsCol.doc(ingredientId);
        final ingSnap = await tx.get(ingRef);
        if (!ingSnap.exists) continue;
        final ing = ingSnap.data()!;
        final targetBranch = branchIds.isNotEmpty ? branchIds.first : 'default';
        final branchStocks = ing['branchStocks'] as Map<String, dynamic>? ?? {};
        final current = (branchStocks[targetBranch] as num?)?.toDouble() ?? 0.0;
        final newStock = current + receivedQty;
        final shelfLifeDays = (ing['shelfLifeDays'] as num?)?.toInt();
        final expiry = shelfLifeDays != null
            ? Timestamp.fromDate(
                receivedDate.add(Duration(days: shelfLifeDays)))
            : ing['expiryDate'];

        tx.update(ingRef, {
          'branchStocks.$targetBranch': newStock,
          'costPerUnit': unitCost > 0 ? unitCost : (ing['costPerUnit'] ?? 0),
          'expiryDate': expiry,
          'updatedAt': Timestamp.fromDate(DateTime.now()),
        });

        final movRef = _movementsCol.doc();
        tx.set(movRef, {
          'branchIds': branchIds,
          'ingredientId': ingredientId,
          'ingredientName': (row['ingredientName'] ?? '').toString(),
          'movementType': 'receiving',
          'quantity': receivedQty,
          'balanceBefore': current,
          'balanceAfter': newStock,
          'referenceId': poId,
          'reason': 'PO receiving',
          'recordedBy': recordedBy,
          'createdAt': Timestamp.fromDate(DateTime.now()),
        });
      }

      tx.update(poRef, {
        'status': fullReceipt ? 'received' : 'partial',
        'lineItems': receivedItems,
        'receivedDate': Timestamp.fromDate(receivedDate),
        'notes': notes,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
        'history': FieldValue.arrayUnion([
          {
            'action': fullReceipt ? 'received' : 'partially_received',
            'userId': userId,
            'userName': userName,
            'timestamp': Timestamp.fromDate(DateTime.now()),
            'notes': notes,
          }
        ]),
      });
    });
  }

  Future<void> directReceive({
    required List<String> branchIds,
    required String recordedBy,
    required List<Map<String, dynamic>> rows,
  }) async {
    await _db.runTransaction((tx) async {
      for (final row in rows) {
        final ingredientId = (row['ingredientId'] ?? '').toString();
        if (ingredientId.isEmpty) continue;
        final qty = (row['receivedQty'] as num?)?.toDouble() ?? 0.0;
        final unitCost = (row['unitCost'] as num?)?.toDouble() ?? 0.0;
        if (qty <= 0) continue;

        final ingRef = _ingredientsCol.doc(ingredientId);
        final ingSnap = await tx.get(ingRef);
        if (!ingSnap.exists) continue;
        final ing = ingSnap.data()!;
        final targetBranch = branchIds.isNotEmpty ? branchIds.first : 'default';
        final branchStocks = ing['branchStocks'] as Map<String, dynamic>? ?? {};
        final current = (branchStocks[targetBranch] as num?)?.toDouble() ?? 0.0;
        final newStock = current + qty;
        final shelfLifeDays = (ing['shelfLifeDays'] as num?)?.toInt();
        final expiry = shelfLifeDays != null
            ? Timestamp.fromDate(
                DateTime.now().add(Duration(days: shelfLifeDays)))
            : ing['expiryDate'];

        tx.update(ingRef, {
          'branchStocks.$targetBranch': newStock,
          'costPerUnit': unitCost > 0 ? unitCost : (ing['costPerUnit'] ?? 0),
          'expiryDate': expiry,
          'updatedAt': Timestamp.fromDate(DateTime.now()),
        });

        final movRef = _movementsCol.doc();
        tx.set(movRef, {
          'branchIds': branchIds,
          'ingredientId': ingredientId,
          'ingredientName': (row['ingredientName'] ?? '').toString(),
          'movementType': 'receiving',
          'quantity': qty,
          'balanceBefore': current,
          'balanceAfter': newStock,
          'reason': 'Direct receiving',
          'recordedBy': recordedBy,
          'createdAt': Timestamp.fromDate(DateTime.now()),
        });
      }
    });
  }
}
