// test/ingredient_usage_history_test.dart
// Unit tests for IngredientUsageHistoryService static helpers

import 'package:flutter_test/flutter_test.dart';
import 'package:mdd/services/ingredients/ingredient_usage_history_service.dart';

void main() {
  group('IngredientUsageHistoryService — buildRecord', () {
    test('produces complete record with all fields', () {
      final record = IngredientUsageHistoryService.buildRecord(
        ingredientId: 'ing_001',
        ingredientName: 'Flour',
        menuItemId: 'menu_chicken_burger',
        menuItemName: 'Chicken Burger',
        quantity: 0.25,
        unit: 'kg',
        orderId: 'order_abc123',
        branchIds: ['branch_1'],
        movementType: 'order_deduction',
        recordedBy: 'admin@test.com',
        recipeId: 'recipe_001',
      );

      expect(record['ingredientId'], 'ing_001');
      expect(record['ingredientName'], 'Flour');
      expect(record['menuItemId'], 'menu_chicken_burger');
      expect(record['menuItemName'], 'Chicken Burger');
      expect(record['quantity'], 0.25);
      expect(record['unit'], 'kg');
      expect(record['orderId'], 'order_abc123');
      expect(record['branchIds'], ['branch_1']);
      expect(record['movementType'], 'order_deduction');
      expect(record['recordedBy'], 'admin@test.com');
      expect(record['recipeId'], 'recipe_001');
    });

    test('defaults recipeId to empty string when null', () {
      final record = IngredientUsageHistoryService.buildRecord(
        ingredientId: 'ing_002',
        ingredientName: 'Tomato',
        menuItemId: 'menu_salad',
        menuItemName: 'Garden Salad',
        quantity: 2.0,
        unit: 'pieces',
        orderId: 'order_xyz',
        branchIds: ['branch_1', 'branch_2'],
        movementType: 'order_deduction',
        recordedBy: 'pos@test.com',
      );

      expect(record['recipeId'], '');
    });

    test('handles multiple branchIds', () {
      final record = IngredientUsageHistoryService.buildRecord(
        ingredientId: 'ing_003',
        ingredientName: 'Olive Oil',
        menuItemId: 'menu_pasta',
        menuItemName: 'Pasta Primavera',
        quantity: 50.0,
        unit: 'mL',
        orderId: 'order_123',
        branchIds: ['branch_a', 'branch_b', 'branch_c'],
        movementType: 'order_deduction',
        recordedBy: 'chef@test.com',
      );

      expect(record['branchIds'], hasLength(3));
      expect(record['branchIds'], contains('branch_a'));
      expect(record['branchIds'], contains('branch_c'));
    });

    test('record contains correct movementType for restoration', () {
      final record = IngredientUsageHistoryService.buildRecord(
        ingredientId: 'ing_004',
        ingredientName: 'Cheese',
        menuItemId: 'menu_pizza',
        menuItemName: 'Margherita Pizza',
        quantity: 0.15,
        unit: 'kg',
        orderId: 'order_cancelled_001',
        branchIds: ['branch_1'],
        movementType: 'order_restoration',
        recordedBy: 'manager@test.com',
      );

      expect(record['movementType'], 'order_restoration');
    });

    test('record quantity can be zero', () {
      final record = IngredientUsageHistoryService.buildRecord(
        ingredientId: 'ing_005',
        ingredientName: 'Salt',
        menuItemId: 'menu_water',
        menuItemName: 'Water',
        quantity: 0.0,
        unit: 'g',
        orderId: 'order_000',
        branchIds: ['branch_1'],
        movementType: 'order_deduction',
        recordedBy: 'system',
      );

      expect(record['quantity'], 0.0);
    });

    test('all required fields are present in record', () {
      final record = IngredientUsageHistoryService.buildRecord(
        ingredientId: 'id',
        ingredientName: 'name',
        menuItemId: 'mid',
        menuItemName: 'mname',
        quantity: 1.0,
        unit: 'kg',
        orderId: 'oid',
        branchIds: [],
        movementType: 'type',
        recordedBy: 'user',
      );

      final requiredKeys = [
        'ingredientId', 'ingredientName', 'menuItemId', 'menuItemName',
        'quantity', 'unit', 'orderId', 'branchIds', 'movementType',
        'recordedBy', 'recipeId',
      ];

      for (final key in requiredKeys) {
        expect(record.containsKey(key), true, reason: 'Missing key: $key');
      }
    });
  });
}
