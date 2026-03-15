import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../constants.dart';
import '../../Models/IngredientModel.dart';

class IngredientService {
  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(AppConstants.collectionIngredients);

  // ─── STREAMS ──────────────────────────────────────────────────────────────

  /// All active ingredients for a branch, ordered by name.
  Stream<List<IngredientModel>> streamIngredients(List<String> branchIds) {
    if (branchIds.isEmpty) return const Stream.empty();

    final q = _col.where('isActive', isEqualTo: true);

    return q.orderBy('name').snapshots().map((snap) {
      final all = snap.docs.map((d) => IngredientModel.fromFirestore(d)).toList();
      return all.where((i) => i.branchIds.any((b) => branchIds.contains(b))).toList();
    });
  }

  /// Including inactive (for admin management list).
  Stream<List<IngredientModel>> streamAllIngredients(List<String> branchIds) {
    if (branchIds.isEmpty) return const Stream.empty();

    final q = _col;

    return q.orderBy('name').snapshots().map((snap) {
      final all = snap.docs.map((d) => IngredientModel.fromFirestore(d)).toList();
      return all.where((i) => i.branchIds.any((b) => branchIds.contains(b))).toList();
    });
  }

  // ─── CRUD ─────────────────────────────────────────────────────────────────

  Future<void> addIngredient(IngredientModel ingredient) async {
    final batch = _db.batch();
    final docRef = _col.doc();

    final now = DateTime.now();
    final data = ingredient
        .copyWith(
          id: docRef.id,
          createdAt: now,
          updatedAt: now,
        )
        .toFirestore();

    batch.set(docRef, data);

    // Bidirectional sync: add this ingredient to each linked supplier
    await _syncSuppliersAdd(batch, docRef.id, ingredient.supplierIds);

    await batch.commit();
  }

  Future<void> updateIngredient(
    IngredientModel updated,
    List<String> previousSupplierIds,
  ) async {
    final batch = _db.batch();
    final docRef = _col.doc(updated.id);

    batch.update(docRef, {
      ...updated.toFirestore(),
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });

    // Bidirectional sync: compute added/removed supplier links
    final added = updated.supplierIds
        .where((s) => !previousSupplierIds.contains(s))
        .toList();
    final removed = previousSupplierIds
        .where((s) => !updated.supplierIds.contains(s))
        .toList();

    await _syncSuppliersAdd(batch, updated.id, added);
    await _syncSuppliersRemove(batch, updated.id, removed);

    await batch.commit();
  }

  /// Soft-delete — sets isActive = false.
  Future<void> deleteIngredient(String id, List<String> supplierIds) async {
    final batch = _db.batch();
    batch.update(_col.doc(id), {
      'isActive': false,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
    await _syncSuppliersRemove(batch, id, supplierIds);
    await batch.commit();
  }

  // ─── SUPPLIER BIDIRECTIONAL SYNC ──────────────────────────────────────────

  Future<void> _syncSuppliersAdd(
    WriteBatch batch,
    String ingredientId,
    List<String> supplierIds,
  ) async {
    final suppCol = _db.collection(AppConstants.collectionSuppliers);
    for (final sid in supplierIds) {
      batch.update(suppCol.doc(sid), {
        'ingredientIds': FieldValue.arrayUnion([ingredientId]),
      });
    }
  }

  Future<void> _syncSuppliersRemove(
    WriteBatch batch,
    String ingredientId,
    List<String> supplierIds,
  ) async {
    final suppCol = _db.collection(AppConstants.collectionSuppliers);
    for (final sid in supplierIds) {
      batch.update(suppCol.doc(sid), {
        'ingredientIds': FieldValue.arrayRemove([ingredientId]),
      });
    }
  }

  // ─── STOCK HELPERS ────────────────────────────────────────────────────────

  /// Adjusts stock with 0-floor clamping. Returns actual delta applied.
  Future<double> adjustStock({
    required String ingredientId,
    required List<String> branchIds,
    required double delta,
    required String movementType,
    required String recordedBy,
    String? referenceId,
    String? reason,
  }) async {
    final docRef = _col.doc(ingredientId);

    double actualDelta = delta;

    await _db.runTransaction((tx) async {
      final snap = await tx.get(docRef);
      if (!snap.exists) throw Exception('Ingredient not found');

      final current = (snap.data()!['currentStock'] as num?)?.toDouble() ?? 0.0;
      final desired = current + delta;

      // Clamp: never go below 0
      final newStock = max(0.0, desired);
      actualDelta = newStock - current;

      final warning = desired < 0
          ? 'Deduction clamped: requested ${delta.abs()} but only $current available'
          : null;

      tx.update(docRef, {
        'currentStock': newStock,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });

      // Write audit movement
      final movDoc =
          _db.collection(AppConstants.collectionStockMovements).doc();
      final ingredientName = snap.data()!['name'] as String? ?? '';
      tx.set(movDoc, {
        'branchIds': branchIds,
        'ingredientId': ingredientId,
        'ingredientName': ingredientName,
        'movementType': movementType,
        'quantity': actualDelta,
        'balanceBefore': current,
        'balanceAfter': newStock,
        'referenceId': referenceId,
        'reason': reason,
        if (warning != null) 'warning': warning,
        'recordedBy': recordedBy,
        'createdAt': Timestamp.fromDate(DateTime.now()),
      });
    });

    return actualDelta;
  }

  // ─── FETCH ────────────────────────────────────────────────────────────────

  Future<IngredientModel?> getIngredient(String id) async {
    final doc = await _col.doc(id).get();
    if (!doc.exists) return null;
    return IngredientModel.fromFirestore(doc);
  }

  /// One-time fetch of multiple ingredients by IDs (for recipe cost calc).
  Future<Map<String, double>> getCostMap(List<String> ingredientIds) async {
    if (ingredientIds.isEmpty) return {};
    final snaps = await Future.wait(
      ingredientIds.map((id) => _col.doc(id).get()),
    );
    final map = <String, double>{};
    for (final snap in snaps) {
      if (snap.exists) {
        map[snap.id] = (snap.data()!['costPerUnit'] as num?)?.toDouble() ?? 0.0;
      }
    }
    return map;
  }

  // ─── UNIT CONVERSION ─────────────────────────────────────────────────────

  /// Converts [quantity] from [fromUnit] to [toUnit].
  /// Returns null if no conversion is possible.
  static double? convertUnit(double quantity, String fromUnit, String toUnit) {
    if (fromUnit == toUnit) return quantity;
    const conversions = <String, Map<String, double>>{
      'kg': {'g': 1000},
      'g': {'kg': 0.001},
      'L': {'mL': 1000},
      'mL': {'L': 0.001},
    };
    final factor = conversions[fromUnit]?[toUnit];
    return factor != null ? quantity * factor : null;
  }
}
