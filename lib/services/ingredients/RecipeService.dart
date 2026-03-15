import 'package:cloud_firestore/cloud_firestore.dart';
import '../../constants.dart';
import '../../Models/RecipeModel.dart';
import 'IngredientService.dart';

class RecipeService {
  final _db = FirebaseFirestore.instance;
  final _ingredientService = IngredientService();

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(AppConstants.collectionRecipes);

  // ─── STREAMS ──────────────────────────────────────────────────────────────

  Stream<List<RecipeModel>> streamRecipes(List<String> branchIds) {
    if (branchIds.isEmpty) return const Stream.empty();
    Query<Map<String, dynamic>> q = _col.where('isActive', isEqualTo: true);
    if (branchIds.length == 1) {
      q = q.where('branchIds', arrayContains: branchIds.first);
    } else {
      q = q.where('branchIds', arrayContainsAny: branchIds.take(10).toList());
    }
    return q.orderBy('createdAt', descending: true).snapshots().map(
          (snap) => snap.docs.map((d) => RecipeModel.fromFirestore(d)).toList(),
        );
  }

  // ─── COST CALCULATION ────────────────────────────────────────────────────

  /// Calculates total cost from current ingredient prices (from Firestore).
  Future<double> calculateCost(List<RecipeIngredientLine> lines) async {
    if (lines.isEmpty) return 0.0;
    final ids = lines.map((l) => l.ingredientId).toList();
    final costMap = await _ingredientService.getCostMap(ids);

    double total = 0.0;
    for (final line in lines) {
      final baseCost = costMap[line.ingredientId] ?? 0.0;
      total += baseCost * line.quantity;
    }
    return total;
  }

  Future<List<String>> _collectAllergenTags(
    List<RecipeIngredientLine> lines,
  ) async {
    final allergenTags = <String>{};
    final ingredientIds = lines.map((l) => l.ingredientId).toSet();

    for (final ingredientId in ingredientIds) {
      if (ingredientId.isEmpty) continue;
      final ingredientDoc = await _db
          .collection(AppConstants.collectionIngredients)
          .doc(ingredientId)
          .get();

      if (ingredientDoc.exists) {
        final tags = List<String>.from(
          ingredientDoc.data()?['allergenTags'] ?? const [],
        );
        allergenTags.addAll(tags);
      }
    }
    return allergenTags.toList();
  }

  // ─── CRUD ─────────────────────────────────────────────────────────────────

  Future<void> addRecipe(RecipeModel recipe) async {
    final cost = await calculateCost(recipe.ingredients);
    final inferredAllergens = await _collectAllergenTags(recipe.ingredients);
    final combinedAllergens = {
      ...recipe.allergenTags,
      ...inferredAllergens,
    }.toList();
    final now = DateTime.now();
    final docRef = _col.doc();

    final saved = recipe.copyWith(
      id: docRef.id,
      totalCost: cost,
      createdAt: now,
      updatedAt: now,
      allergenTags: combinedAllergens,
    );
    final recipeData = saved.toFirestore();
    await docRef.set(recipeData);

    // Bidirectional: write recipeId back to the linked menu item
    if (saved.linkedMenuItemId?.isNotEmpty == true) {
      await _db
          .collection(AppConstants.collectionMenuItems)
          .doc(saved.linkedMenuItemId)
          .update({'recipeId': docRef.id}).catchError((_) {});
    }
  }

  Future<void> updateRecipe(
    RecipeModel recipe, {
    String? previousLinkedMenuItemId,
  }) async {
    final cost = await calculateCost(recipe.ingredients);
    final inferredAllergens = await _collectAllergenTags(recipe.ingredients);
    final combinedAllergens = {
      ...recipe.allergenTags,
      ...inferredAllergens,
    }.toList();

    final saved = recipe.copyWith(
      totalCost: cost,
      allergenTags: combinedAllergens,
    );
    await _col.doc(recipe.id).update({
      ...saved.toFirestore(),
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });

    // Unlink old menu item if the linked item changed
    if (previousLinkedMenuItemId != null &&
        previousLinkedMenuItemId.isNotEmpty &&
        previousLinkedMenuItemId != recipe.linkedMenuItemId) {
      await _db
          .collection(AppConstants.collectionMenuItems)
          .doc(previousLinkedMenuItemId)
          .update({'recipeId': FieldValue.delete()}).catchError((_) {});
    }
    // Link to new menu item
    if (recipe.linkedMenuItemId?.isNotEmpty == true) {
      await _db
          .collection(AppConstants.collectionMenuItems)
          .doc(recipe.linkedMenuItemId)
          .update({'recipeId': recipe.id}).catchError((_) {});
    }
  }

  Future<void> deleteRecipe(String id) async {
    await _col.doc(id).update({
      'isActive': false,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  // ─── RECALCULATE ALL COSTS ────────────────────────────────────────────────

  /// Batch-recalculates totalCost for all active recipes in a branch.
  /// Returns the count of recipes updated.
  Future<int> recalculateAllCosts(List<String> branchIds) async {
    if (branchIds.isEmpty) return 0;

    // Fetch all active recipes
    Query<Map<String, dynamic>> q = _col.where('isActive', isEqualTo: true);
    if (branchIds.length == 1) {
      q = q.where('branchIds', arrayContains: branchIds.first);
    } else {
      q = q.where('branchIds', arrayContainsAny: branchIds.take(10).toList());
    }

    final snap = await q.get();
    final recipes = snap.docs.map((d) => RecipeModel.fromFirestore(d)).toList();

    if (recipes.isEmpty) return 0;

    // Collect all unique ingredient IDs
    final allIds = recipes
        .expand((r) => r.ingredients.map((l) => l.ingredientId))
        .toSet()
        .toList();

    final costMap = await _ingredientService.getCostMap(allIds);

    // Write batches (Firestore limit: 500 ops per batch)
    const batchSize = 400;
    int updated = 0;

    for (int i = 0; i < recipes.length; i += batchSize) {
      final chunk = recipes.sublist(
        i,
        i + batchSize > recipes.length ? recipes.length : i + batchSize,
      );
      final batch = _db.batch();
      for (final recipe in chunk) {
        double newCost = 0.0;
        for (final line in recipe.ingredients) {
          newCost += (costMap[line.ingredientId] ?? 0.0) * line.quantity;
        }
        batch.update(_col.doc(recipe.id), {
          'totalCost': newCost,
          'updatedAt': Timestamp.fromDate(DateTime.now()),
        });
        updated++;
      }
      await batch.commit();
    }

    return updated;
  }

  // ─── FETCH ────────────────────────────────────────────────────────────────

  Future<RecipeModel?> getRecipe(String id) async {
    final doc = await _col.doc(id).get();
    if (!doc.exists) return null;
    return RecipeModel.fromFirestore(doc);
  }

  Future<List<RecipeModel>> getRecipesByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    final snaps = await Future.wait(ids.map((id) => _col.doc(id).get()));
    return snaps
        .where((s) => s.exists)
        .map((s) => RecipeModel.fromFirestore(s))
        .toList();
  }
}
