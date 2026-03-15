import 'package:cloud_firestore/cloud_firestore.dart';

// Sentinel value to distinguish "not provided" from "explicitly set to null"
const _sentinel = Object();

class RecipeIngredientLine {
  final String ingredientId;
  final String ingredientName;
  final double quantity;
  final String unit;

  const RecipeIngredientLine({
    required this.ingredientId,
    required this.ingredientName,
    required this.quantity,
    required this.unit,
  });

  factory RecipeIngredientLine.fromMap(Map<String, dynamic> m) {
    return RecipeIngredientLine(
      ingredientId: m['ingredientId'] as String? ?? '',
      ingredientName: m['ingredientName'] as String? ?? '',
      quantity: (m['quantity'] as num?)?.toDouble() ?? 0.0,
      unit: m['unit'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'ingredientId': ingredientId,
        'ingredientName': ingredientName,
        'quantity': quantity,
        'unit': unit,
      };

  RecipeIngredientLine copyWith({
    String? ingredientId,
    String? ingredientName,
    double? quantity,
    String? unit,
  }) =>
      RecipeIngredientLine(
        ingredientId: ingredientId ?? this.ingredientId,
        ingredientName: ingredientName ?? this.ingredientName,
        quantity: quantity ?? this.quantity,
        unit: unit ?? this.unit,
      );
}

class RecipeModel {
  final String id;
  final List<String> branchIds;
  final String name;
  final String description;
  final List<RecipeIngredientLine> ingredients;
  final double totalCost; // auto-calculated
  final List<String> instructions;
  final int prepTimeMinutes;
  final String yield_;
  final String servingSize;
  final String difficultyLevel; // easy | medium | hard
  final List<String> categoryTags;
  final List<String> allergenTags;
  final List<String> photoUrls;
  final String? linkedMenuItemId; // optional link to a menu_items doc
  final String? linkedMenuItemName; // denormalized for display
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const RecipeModel({
    required this.id,
    required this.branchIds,
    required this.name,
    required this.description,
    required this.ingredients,
    required this.totalCost,
    required this.instructions,
    required this.prepTimeMinutes,
    required this.yield_,
    required this.servingSize,
    required this.difficultyLevel,
    required this.categoryTags,
    required this.allergenTags,
    required this.photoUrls,
    this.linkedMenuItemId,
    this.linkedMenuItemName,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  factory RecipeModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return RecipeModel(
      id: doc.id,
      branchIds: List<String>.from(d['branchIds'] as List? ?? []),
      name: d['name'] as String? ?? '',
      description: d['description'] as String? ?? '',
      ingredients: (d['ingredients'] as List? ?? [])
          .map((e) => RecipeIngredientLine.fromMap(e as Map<String, dynamic>))
          .toList(),
      totalCost: (d['totalCost'] as num?)?.toDouble() ?? 0.0,
      instructions: List<String>.from(d['instructions'] as List? ?? []),
      prepTimeMinutes: d['prepTimeMinutes'] as int? ?? 0,
      yield_: d['yield'] as String? ?? '',
      servingSize: d['servingSize'] as String? ?? '',
      difficultyLevel: d['difficultyLevel'] as String? ?? 'easy',
      categoryTags: List<String>.from(d['categoryTags'] as List? ?? []),
      allergenTags: List<String>.from(d['allergenTags'] as List? ?? []),
      photoUrls: List<String>.from(d['photoUrls'] as List? ?? []),
      linkedMenuItemId: d['linkedMenuItemId'] as String?,
      linkedMenuItemName: d['linkedMenuItemName'] as String?,
      isActive: d['isActive'] as bool? ?? true,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'branchIds': branchIds,
        'name': name,
        'description': description,
        'ingredients': ingredients.map((i) => i.toMap()).toList(),
        'totalCost': totalCost,
        'instructions': instructions,
        'prepTimeMinutes': prepTimeMinutes,
        'yield': yield_,
        'servingSize': servingSize,
        'difficultyLevel': difficultyLevel,
        'categoryTags': categoryTags,
        'allergenTags': allergenTags,
        'photoUrls': photoUrls,
        'linkedMenuItemId': linkedMenuItemId,
        'linkedMenuItemName': linkedMenuItemName,
        'isActive': isActive,
        'createdAt': Timestamp.fromDate(createdAt),
        'updatedAt': Timestamp.fromDate(updatedAt),
      };

  RecipeModel copyWith({
    String? id,
    List<String>? branchIds,
    String? name,
    String? description,
    List<RecipeIngredientLine>? ingredients,
    double? totalCost,
    List<String>? instructions,
    int? prepTimeMinutes,
    String? yield_,
    String? servingSize,
    String? difficultyLevel,
    List<String>? categoryTags,
    List<String>? allergenTags,
    List<String>? photoUrls,
    Object? linkedMenuItemId = _sentinel,
    Object? linkedMenuItemName = _sentinel,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      RecipeModel(
        id: id ?? this.id,
        branchIds: branchIds ?? this.branchIds,
        name: name ?? this.name,
        description: description ?? this.description,
        ingredients: ingredients ?? this.ingredients,
        totalCost: totalCost ?? this.totalCost,
        instructions: instructions ?? this.instructions,
        prepTimeMinutes: prepTimeMinutes ?? this.prepTimeMinutes,
        yield_: yield_ ?? this.yield_,
        servingSize: servingSize ?? this.servingSize,
        difficultyLevel: difficultyLevel ?? this.difficultyLevel,
        categoryTags: categoryTags ?? this.categoryTags,
        allergenTags: allergenTags ?? this.allergenTags,
        photoUrls: photoUrls ?? this.photoUrls,
        linkedMenuItemId: linkedMenuItemId == _sentinel
            ? this.linkedMenuItemId
            : linkedMenuItemId as String?,
        linkedMenuItemName: linkedMenuItemName == _sentinel
            ? this.linkedMenuItemName
            : linkedMenuItemName as String?,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  // ─── Static helpers ────────────────────────────────────────────────────────

  static const List<String> difficultyLevels = ['easy', 'medium', 'hard'];

  static String difficultyLabel(String d) {
    const m = {'easy': 'Easy', 'medium': 'Medium', 'hard': 'Hard'};
    return m[d] ?? d;
  }

  static const List<String> categoryTagOptions = [
    'breakfast',
    'lunch',
    'dinner',
    'snack',
    'dessert',
    'beverage',
    'side',
    'main',
    'starter',
  ];
}
