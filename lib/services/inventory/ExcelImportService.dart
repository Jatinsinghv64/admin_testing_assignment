import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import '../../Models/IngredientModel.dart';
import '../ingredients/IngredientService.dart';

class ExcelImportService {
  final IngredientService _ingredientService;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  ExcelImportService(this._ingredientService);

  Future<void> pickAndImportExcel(String branchId, {required Function(String) onProgress, required Function(String) onError, required Function() onSuccess}) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
      );

      if (result == null || result.files.single.path == null) {
        return; // User canceled
      }

      File file = File(result.files.single.path!);
      var bytes = file.readAsBytesSync();
      var excel = Excel.decodeBytes(bytes);

      if (excel.tables.keys.isEmpty) {
        onError("Excel file is empty");
        return;
      }

      String table = excel.tables.keys.first;
      var rows = excel.tables[table]?.rows ?? [];

      if (rows.length <= 1) {
        onError("Excel file has no data rows");
        return;
      }

      // Read Header Row to map column indices dynamically (in case user swaps columns)
      var headerRow = rows[0];
      Map<String, int> columnMap = {};
      for (int i = 0; i < headerRow.length; i++) {
        var cellValue = headerRow[i]?.value;
        if (cellValue != null) {
          columnMap[cellValue.toString().toLowerCase().trim()] = i;
        }
      }

      // Check required columns
      if (!columnMap.containsKey('name') || !columnMap.containsKey('cost')) {
        onError("Missing required columns. Ensure 'name' and 'cost' exist.");
        return;
      }

      onProgress("Parsing ${rows.length - 1} rows...");

      int newlyAdded = 0;
      int updated = 0;

      for (int r = 1; r < rows.length; r++) {
        var row = rows[r];
        if (row.isEmpty || row[columnMap['name']!]?.value == null) continue; // Skip empty rows

        String name = row[columnMap['name']!]?.value.toString().trim() ?? '';
        String category = columnMap.containsKey('category') ? (row[columnMap['category']!]?.value.toString().trim() ?? IngredientModel.categories.first) : IngredientModel.categories.first;
        String unit = columnMap.containsKey('unit') ? (row[columnMap['unit']!]?.value.toString().trim() ?? IngredientModel.units.first) : IngredientModel.units.first;
        String sku = columnMap.containsKey('sku') ? (row[columnMap['sku']!]?.value.toString().trim() ?? '') : '';
        String barcode = columnMap.containsKey('barcode') ? (row[columnMap['barcode']!]?.value.toString().trim() ?? '') : '';

        double cost = _parseDouble(row[columnMap['cost']!]?.value);
        double stock = columnMap.containsKey('stock') ? _parseDouble(row[columnMap['stock']!]?.value) : 0.0;
        double minStock = columnMap.containsKey('min_stock') ? _parseDouble(row[columnMap['min_stock']!]?.value) : 0.0;

        // Try matching by SKU or Barcode first
        IngredientModel? existingIngredient = await _findExistingIngredient(sku, barcode, name, branchId);

        if (existingIngredient != null) {
          // Update existing
          IngredientModel updatedModel = existingIngredient.copyWith(
            name: name.isNotEmpty ? name : existingIngredient.name,
            costPerUnit: cost > 0 ? cost : existingIngredient.costPerUnit,
            currentStock: stock > 0 ? stock : existingIngredient.currentStock,
            minStockThreshold: minStock > 0 ? minStock : existingIngredient.minStockThreshold,
            category: category.isNotEmpty && IngredientModel.categories.contains(category) ? category : existingIngredient.category,
            unit: unit.isNotEmpty && IngredientModel.units.contains(unit) ? unit : existingIngredient.unit,
            sku: sku.isNotEmpty ? sku : existingIngredient.sku,
            barcode: barcode.isNotEmpty ? barcode : existingIngredient.barcode,
          );
          
          await _ingredientService.updateIngredient(updatedModel, List.from(existingIngredient.supplierIds));
          updated++;
        } else {
          // Create new
          IngredientModel newModel = IngredientModel(
            id: _db.collection('ingredients').doc().id,
            branchIds: [branchId],
            name: name,
            category: IngredientModel.categories.contains(category) ? category : IngredientModel.categories.first,
            unit: IngredientModel.units.contains(unit) ? unit : IngredientModel.units.first,
            costPerUnit: cost,
            currentStock: stock,
            minStockThreshold: minStock,
            supplierIds: [],
            allergenTags: [],
            isPerishable: false,
            sku: sku,
            barcode: barcode,
            isActive: true,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          );
          
          await _ingredientService.addIngredient(newModel);
          newlyAdded++;
        }
      }

      onSuccess();
    } catch (e) {
      onError(e.toString());
    }
  }

  Future<IngredientModel?> _findExistingIngredient(String sku, String barcode, String name, String branchId) async {
    // Attempt 1: by SKU
    if (sku.isNotEmpty) {
      var snapshot = await _db.collection('ingredients')
        .where('branchIds', arrayContains: branchId)
        .where('sku', isEqualTo: sku)
        .limit(1)
        .get();
      if (snapshot.docs.isNotEmpty) {
        return IngredientModel.fromFirestore(snapshot.docs.first);
      }
    }

    // Attempt 2: by Barcode
    if (barcode.isNotEmpty) {
      var snapshot = await _db.collection('ingredients')
        .where('branchIds', arrayContains: branchId)
        .where('barcode', isEqualTo: barcode)
        .limit(1)
        .get();
      if (snapshot.docs.isNotEmpty) {
        return IngredientModel.fromFirestore(snapshot.docs.first);
      }
    }

    // Attempt 3: by Name (exact match)
    if (name.isNotEmpty) {
      var snapshot = await _db.collection('ingredients')
        .where('branchIds', arrayContains: branchId)
        .where('name', isEqualTo: name)
        .limit(1)
        .get();
      if (snapshot.docs.isNotEmpty) {
        return IngredientModel.fromFirestore(snapshot.docs.first);
      }
    }

    return null;
  }

  double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }
}
