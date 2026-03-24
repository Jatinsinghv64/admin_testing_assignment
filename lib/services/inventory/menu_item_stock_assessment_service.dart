import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../Models/IngredientModel.dart';
import '../../Models/RecipeModel.dart';
import '../../constants.dart';
import '../ingredients/IngredientService.dart';

enum MenuItemStockSeverity { ok, low, out }

class MenuItemIngredientIssue {
  final String ingredientId;
  final String ingredientName;
  final double availableStock;
  final double requiredStock;
  final String unit;
  final int possibleServings;
  final double minStockThreshold;
  final MenuItemStockSeverity severity;
  final String? note;

  const MenuItemIngredientIssue({
    required this.ingredientId,
    required this.ingredientName,
    required this.availableStock,
    required this.requiredStock,
    required this.unit,
    required this.possibleServings,
    required this.minStockThreshold,
    required this.severity,
    this.note,
  });

  bool get isBlocking => severity == MenuItemStockSeverity.out;

  String get statusLabel {
    switch (severity) {
      case MenuItemStockSeverity.out:
        return 'Out of stock';
      case MenuItemStockSeverity.low:
        return 'Low stock';
      case MenuItemStockSeverity.ok:
        return 'OK';
    }
  }
}

class MenuItemStockAssessment {
  final String menuItemId;
  final String menuItemName;
  final String? recipeId;
  final String? recipeName;
  final bool hasRecipeLink;
  final List<String> warnings;
  final List<MenuItemIngredientIssue> ingredientIssues;

  const MenuItemStockAssessment({
    required this.menuItemId,
    required this.menuItemName,
    required this.recipeId,
    required this.recipeName,
    required this.hasRecipeLink,
    required this.warnings,
    required this.ingredientIssues,
  });

  bool get hasBlockingIssues =>
      ingredientIssues.any((issue) => issue.isBlocking);

  bool get hasLowStockIssues => ingredientIssues.any(
        (issue) => issue.severity == MenuItemStockSeverity.low,
      );

  bool get hasConfigurationWarnings => warnings.isNotEmpty;

  bool get needsAttention =>
      hasBlockingIssues || hasLowStockIssues || hasConfigurationWarnings;

  int? get minimumPossibleServings {
    if (ingredientIssues.isEmpty) return null;
    return ingredientIssues.map((issue) => issue.possibleServings).reduce(min);
  }
}

class MenuItemStockAssessmentService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<MenuItemStockAssessment> assessMenuItem({
    required String menuItemId,
    String? menuItemName,
    String? explicitRecipeId,
    int quantity = 1,
  }) async {
    String resolvedName = menuItemName?.trim().isNotEmpty == true
        ? menuItemName!.trim()
        : 'This dish';
    var resolvedRecipeId = explicitRecipeId?.trim() ?? '';

    if (resolvedRecipeId.isEmpty) {
      final menuSnap = await _db
          .collection(AppConstants.collectionMenuItems)
          .doc(menuItemId)
          .get();
      final menuData = menuSnap.data();
      if (menuData != null) {
        resolvedName = (menuData['name'] ?? resolvedName).toString();
        resolvedRecipeId = (menuData['recipeId'] ?? '').toString().trim();
      }
    }

    final recipeSnap = await _resolveRecipeSnapshot(
      menuItemId: menuItemId,
      recipeId: resolvedRecipeId,
    );

    if (recipeSnap == null || !recipeSnap.exists) {
      return MenuItemStockAssessment(
        menuItemId: menuItemId,
        menuItemName: resolvedName,
        recipeId: resolvedRecipeId.isEmpty ? null : resolvedRecipeId,
        recipeName: null,
        hasRecipeLink: false,
        warnings: const [
          'No active recipe is linked to this dish. Ingredient stock cannot be validated.',
        ],
        ingredientIssues: const [],
      );
    }

    final recipe = RecipeModel.fromFirestore(recipeSnap);
    final ingredientIds = recipe.ingredients
        .map((line) => line.ingredientId)
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final ingredientSnaps = await Future.wait(
      ingredientIds.map(
        (ingredientId) => _db
            .collection(AppConstants.collectionIngredients)
            .doc(ingredientId)
            .get(),
      ),
    );

    final ingredients = ingredientSnaps
        .where((snap) => snap.exists)
        .map(IngredientModel.fromFirestore)
        .toList();

    return assessDraftMenuItem(
      menuItemId: menuItemId,
      menuItemName: resolvedName,
      recipeId: recipe.id,
      recipeName: recipe.name,
      ingredientLines: recipe.ingredients,
      ingredients: ingredients,
      quantity: quantity,
    );
  }

  MenuItemStockAssessment assessDraftMenuItem({
    required String menuItemId,
    required String menuItemName,
    String? recipeId,
    String? recipeName,
    required List<RecipeIngredientLine> ingredientLines,
    required List<IngredientModel> ingredients,
    int quantity = 1,
  }) {
    final effectiveQuantity = quantity < 1 ? 1 : quantity;
    final warnings = <String>[];
    final issues = <MenuItemIngredientIssue>[];
    final ingredientMap = <String, IngredientModel>{
      for (final ingredient in ingredients) ingredient.id: ingredient,
    };

    final cleanedLines =
        ingredientLines.where((line) => line.ingredientId.isNotEmpty).toList();

    if (cleanedLines.isEmpty) {
      warnings.add(
        'No ingredient lines are linked to this dish. Stock alerts cannot be generated for it.',
      );
      return MenuItemStockAssessment(
        menuItemId: menuItemId,
        menuItemName: menuItemName,
        recipeId: recipeId,
        recipeName: recipeName,
        hasRecipeLink: recipeId?.isNotEmpty == true,
        warnings: warnings,
        ingredientIssues: const [],
      );
    }

    for (final line in cleanedLines) {
      if (line.quantity <= 0) {
        continue;
      }

      final ingredient = ingredientMap[line.ingredientId];
      if (ingredient == null) {
        issues.add(
          MenuItemIngredientIssue(
            ingredientId: line.ingredientId,
            ingredientName: line.ingredientName.isNotEmpty
                ? line.ingredientName
                : 'Missing ingredient',
            availableStock: 0,
            requiredStock: line.quantity * effectiveQuantity,
            unit: line.unit,
            possibleServings: 0,
            minStockThreshold: 0,
            severity: MenuItemStockSeverity.out,
            note: 'Ingredient record is missing or inactive.',
          ),
        );
        continue;
      }

      var requiredStock = line.quantity * effectiveQuantity;
      var displayUnit =
          ingredient.unit.isNotEmpty ? ingredient.unit : line.unit;
      String? note;

      if (line.unit.isNotEmpty &&
          ingredient.unit.isNotEmpty &&
          line.unit != ingredient.unit) {
        final converted = IngredientService.convertUnit(
          requiredStock,
          line.unit,
          ingredient.unit,
        );
        if (converted == null) {
          issues.add(
            MenuItemIngredientIssue(
              ingredientId: ingredient.id,
              ingredientName: ingredient.name,
              availableStock: ingredient.currentStock,
              requiredStock: requiredStock,
              unit: ingredient.unit,
              possibleServings: 0,
              minStockThreshold: ingredient.minStockThreshold,
              severity: MenuItemStockSeverity.out,
              note:
                  'Unit conversion failed: ${line.unit} cannot be converted to ${ingredient.unit}.',
            ),
          );
          continue;
        }
        requiredStock = converted;
        displayUnit = ingredient.unit;
      }

      if (requiredStock <= 0) continue;

      final possibleServings =
          (ingredient.currentStock / requiredStock).floor();

      MenuItemStockSeverity severity = MenuItemStockSeverity.ok;
      if (ingredient.isOutOfStock || possibleServings <= 0) {
        severity = MenuItemStockSeverity.out;
        note = 'Required stock is not available.';
      } else if (ingredient.isLowStock || possibleServings <= 5) {
        severity = MenuItemStockSeverity.low;
        note = ingredient.isLowStock
            ? 'Ingredient is already below its minimum stock threshold.'
            : 'Only a few servings are left at the current stock level.';
      }

      if (severity == MenuItemStockSeverity.ok) {
        continue;
      }

      issues.add(
        MenuItemIngredientIssue(
          ingredientId: ingredient.id,
          ingredientName: ingredient.name,
          availableStock: ingredient.currentStock,
          requiredStock: requiredStock,
          unit: displayUnit,
          possibleServings: possibleServings,
          minStockThreshold: ingredient.minStockThreshold,
          severity: severity,
          note: note,
        ),
      );
    }

    issues.sort((a, b) {
      final severityCompare =
          _severityRank(a.severity).compareTo(_severityRank(b.severity));
      if (severityCompare != 0) return severityCompare;
      return a.ingredientName.toLowerCase().compareTo(
            b.ingredientName.toLowerCase(),
          );
    });

    return MenuItemStockAssessment(
      menuItemId: menuItemId,
      menuItemName: menuItemName,
      recipeId: recipeId,
      recipeName: recipeName,
      hasRecipeLink: recipeId?.isNotEmpty == true || cleanedLines.isNotEmpty,
      warnings: warnings,
      ingredientIssues: issues,
    );
  }

  Future<DocumentSnapshot<Map<String, dynamic>>?> _resolveRecipeSnapshot({
    required String menuItemId,
    required String recipeId,
  }) async {
    if (recipeId.isNotEmpty) {
      final recipeSnap = await _db
          .collection(AppConstants.collectionRecipes)
          .doc(recipeId)
          .get();
      final recipeData = recipeSnap.data();
      if (recipeSnap.exists && (recipeData?['isActive'] ?? true) == true) {
        return recipeSnap;
      }
    }

    final fallbackQuery = await _db
        .collection(AppConstants.collectionRecipes)
        .where('linkedMenuItemId', isEqualTo: menuItemId)
        .where('isActive', isEqualTo: true)
        .limit(1)
        .get();

    if (fallbackQuery.docs.isEmpty) {
      return null;
    }
    return fallbackQuery.docs.first;
  }

  int _severityRank(MenuItemStockSeverity severity) {
    switch (severity) {
      case MenuItemStockSeverity.out:
        return 0;
      case MenuItemStockSeverity.low:
        return 1;
      case MenuItemStockSeverity.ok:
        return 2;
    }
  }
}
