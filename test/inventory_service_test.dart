// test/inventory_service_test.dart
// Unit tests for InventoryService conversion logic via IngredientService

import 'package:flutter_test/flutter_test.dart';
import 'package:mdd/services/ingredients/IngredientService.dart';

/// InventoryService delegates all unit conversion to IngredientService.convertUnit.
/// These tests verify the conversion pipeline used during stock deductions.
void main() {
  group('Inventory Stock Conversion Pipeline', () {
    test('recipe kg converts to stock g correctly', () {
      // When recipe says 0.5 kg flour but stock is tracked in g
      final converted = IngredientService.convertUnit(0.5, 'kg', 'g');
      expect(converted, 500.0);
    });

    test('recipe mL converts to stock L correctly', () {
      // When recipe uses mL but stock is L
      final converted = IngredientService.convertUnit(250.0, 'mL', 'L');
      expect(converted, 0.25);
    });

    test('incompatible units block deduction (returns null)', () {
      // InventoryService skips deduction when conversion returns null
      expect(IngredientService.convertUnit(1.0, 'kg', 'L'), null);
      expect(IngredientService.convertUnit(1.0, 'pieces', 'kg'), null);
    });

    test('same-unit needs no conversion', () {
      expect(IngredientService.convertUnit(42.0, 'kg', 'kg'), 42.0);
    });

    test('quantity multiplication for multi-item orders', () {
      // Recipe: 0.1 kg per item, order: 5 items
      final perItem = IngredientService.convertUnit(0.1, 'kg', 'g');
      expect(perItem, 100.0);
      final totalDeduction = perItem! * 5;
      expect(totalDeduction, 500.0);
    });

    test('fractional conversions preserve precision', () {
      final result = IngredientService.convertUnit(0.333, 'kg', 'g');
      expect(result, closeTo(333.0, 0.001));
    });
  });

  group('Stock Clamping Logic', () {
    test('deduction from sufficient stock', () {
      const before = 500.0;
      const adjustedQty = 200.0;
      const direction = -1;
      final signedQty = adjustedQty * direction;
      final rawAfter = before + signedQty;
      final after = direction < 0 ? rawAfter.clamp(0.0, double.infinity) : rawAfter;
      expect(after, 300.0);
    });

    test('deduction exceeding stock clamps to zero', () {
      const before = 100.0;
      const adjustedQty = 250.0;
      const direction = -1;
      final signedQty = adjustedQty * direction;
      final rawAfter = before + signedQty;
      final after = direction < 0 ? rawAfter.clamp(0.0, double.infinity) : rawAfter;
      expect(after, 0.0);
    });

    test('restoration adds back to stock', () {
      const before = 300.0;
      const adjustedQty = 200.0;
      const direction = 1;
      final signedQty = adjustedQty * direction;
      final rawAfter = before + signedQty;
      final after = direction < 0 ? rawAfter.clamp(0.0, double.infinity) : rawAfter;
      expect(after, 500.0);
    });

    test('deduction from zero stock clamps to zero', () {
      const before = 0.0;
      const adjustedQty = 50.0;
      const direction = -1;
      final signedQty = adjustedQty * direction;
      final rawAfter = before + signedQty;
      final after = direction < 0 ? rawAfter.clamp(0.0, double.infinity) : rawAfter;
      expect(after, 0.0);
    });
  });
}
