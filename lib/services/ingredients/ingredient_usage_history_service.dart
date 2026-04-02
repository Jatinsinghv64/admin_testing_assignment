import 'package:cloud_firestore/cloud_firestore.dart';
import '../../constants.dart';

/// Service for tracking ingredient usage history per menu item.
///
/// Each record captures which ingredient was used, how much, for which menu
/// item, and in which order — enabling full traceability of ingredient
/// consumption across the system.
class IngredientUsageHistoryService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(AppConstants.collectionIngredientUsageHistory);

  // ---------------------------------------------------------------------------
  // WRITE
  // ---------------------------------------------------------------------------

  /// Write a single usage history entry within an existing Firestore
  /// [transaction]. This is typically called from
  /// [InventoryService._applyInventoryDeltaInTransaction].
  void writeInTransaction({
    required Transaction transaction,
    required String ingredientId,
    required String ingredientName,
    required String menuItemId,
    required String menuItemName,
    required double quantity,
    required String unit,
    required String orderId,
    required List<String> branchIds,
    required String movementType,
    required String recordedBy,
    String? recipeId,
  }) {
    final docRef = _col.doc();
    transaction.set(docRef, {
      'ingredientId': ingredientId,
      'ingredientName': ingredientName,
      'menuItemId': menuItemId,
      'menuItemName': menuItemName,
      'quantity': quantity,
      'unit': unit,
      'orderId': orderId,
      'branchIds': branchIds,
      'movementType': movementType,
      'recipeId': recipeId ?? '',
      'recordedBy': recordedBy,
      'usedAt': FieldValue.serverTimestamp(),
    });
  }

  // ---------------------------------------------------------------------------
  // READ
  // ---------------------------------------------------------------------------

  /// Stream usage history for a specific ingredient, ordered by most recent.
  Stream<List<Map<String, dynamic>>> streamUsageHistory(String ingredientId) {
    if (ingredientId.isEmpty) return const Stream.empty();
    return _col
        .where('ingredientId', isEqualTo: ingredientId)
        .orderBy('usedAt', descending: true)
        .limit(100)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  /// Get usage history filtered by menu item.
  Future<List<Map<String, dynamic>>> getUsageHistoryByMenuItem(
      String menuItemId) async {
    if (menuItemId.isEmpty) return [];
    final snap = await _col
        .where('menuItemId', isEqualTo: menuItemId)
        .orderBy('usedAt', descending: true)
        .limit(200)
        .get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  /// Stream usage history filtered by branch.
  Stream<List<Map<String, dynamic>>> streamUsageHistoryByBranch(
      List<String> branchIds,
      {int limit = 50}) {
    if (branchIds.isEmpty) return const Stream.empty();
    Query<Map<String, dynamic>> q = _col;
    if (branchIds.length == 1) {
      q = q.where('branchIds', arrayContains: branchIds.first);
    } else {
      q = q.where('branchIds',
          arrayContainsAny: branchIds.take(10).toList());
    }
    return q
        .orderBy('usedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  // ---------------------------------------------------------------------------
  // HELPERS (static, for unit testing)
  // ---------------------------------------------------------------------------

  /// Build a usage history record map (useful for testing payloads).
  static Map<String, dynamic> buildRecord({
    required String ingredientId,
    required String ingredientName,
    required String menuItemId,
    required String menuItemName,
    required double quantity,
    required String unit,
    required String orderId,
    required List<String> branchIds,
    required String movementType,
    required String recordedBy,
    String? recipeId,
  }) {
    return {
      'ingredientId': ingredientId,
      'ingredientName': ingredientName,
      'menuItemId': menuItemId,
      'menuItemName': menuItemName,
      'quantity': quantity,
      'unit': unit,
      'orderId': orderId,
      'branchIds': branchIds,
      'movementType': movementType,
      'recipeId': recipeId ?? '',
      'recordedBy': recordedBy,
    };
  }
}
