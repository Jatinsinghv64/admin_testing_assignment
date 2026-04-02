import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import '../../Models/IngredientModel.dart';

class IngredientImportResult {
  final int createdCount;
  final int updatedCount;
  final int skippedCount;
  final List<String> warnings;

  const IngredientImportResult({
    required this.createdCount,
    required this.updatedCount,
    required this.skippedCount,
    this.warnings = const [],
  });
}

class ExcelImportService {
  ExcelImportService();
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<IngredientImportResult?> pickAndImportFile(
    String branchId, {
    required void Function(String message) onProgress,
  }) async {
    if (branchId.trim().isEmpty) {
      throw const FormatException(
          'Select exactly one branch before importing.');
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'xlsx', 'xls'],
      allowMultiple: false,
      withData: true,
    );

    if (result == null || result.files.isEmpty) {
      return null;
    }

    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw const FormatException('Unable to read the selected file.');
    }

    onProgress('Reading ${file.name}');
    final rows = _parseRows(file.name, bytes);
    if (rows.length < 2) {
      throw const FormatException(
          'The selected file does not contain any data rows.');
    }

    final headerMap = _buildHeaderMap(rows.first);
    final nameIndex = _resolveHeader(headerMap, const ['name']);
    final costIndex =
        _resolveHeader(headerMap, const ['cost', 'cost_per_unit']);
    if (nameIndex == null || costIndex == null) {
      throw const FormatException(
        'Missing required headers. Use `name` and either `cost` or `cost_per_unit`.',
      );
    }

    final categoryIndex = _resolveHeader(headerMap, const ['category']);
    final unitIndex = _resolveHeader(headerMap, const ['unit']);
    final skuIndex = _resolveHeader(headerMap, const ['sku']);
    final barcodeIndex = _resolveHeader(headerMap, const ['barcode']);
    final stockIndex =
        _resolveHeader(headerMap, const ['stock', 'current_stock']);
    final minStockIndex = _resolveHeader(headerMap, const [
      'min_stock',
      'min_threshold',
      'minimum_stock',
    ]);

    onProgress('Loading existing ingredients');
    final existingIngredients = await _fetchExistingIngredients(branchId);
    final lookup = _IngredientLookup(existingIngredients);

    final warnings = <String>[];
    var createdCount = 0;
    var updatedCount = 0;
    var skippedCount = 0;
    var batch = _db.batch();
    var pendingWrites = 0;

    for (var rowIndex = 1; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      if (_isRowEmpty(row)) {
        continue;
      }

      final rowLabel = 'Row ${rowIndex + 1}';
      final name = _readString(row, nameIndex);
      if (name.isEmpty) {
        skippedCount++;
        warnings.add('$rowLabel skipped because ingredient name is empty.');
        continue;
      }

      final sku = _readString(row, skuIndex);
      final barcode = _readString(row, barcodeIndex);
      final existing = lookup.find(name: name, sku: sku, barcode: barcode);

      final costValue = _readDouble(row, costIndex);
      if (costValue.invalid) {
        warnings.add(
            '$rowLabel has an invalid cost value. Existing/default cost was kept.');
      }

      final stockValue = _readDouble(row, stockIndex);
      if (stockValue.invalid) {
        warnings.add(
            '$rowLabel has an invalid stock value. Existing/default stock was kept.');
      }

      final minStockValue = _readDouble(row, minStockIndex);
      if (minStockValue.invalid) {
        warnings.add(
            '$rowLabel has an invalid min_stock value. Existing/default threshold was kept.');
      }

      final category = _normalizeCategory(
        _readString(row, categoryIndex),
        existing?.category,
        rowLabel,
        warnings,
      );
      final unit = _normalizeUnit(
        _readString(row, unitIndex),
        existing?.unit,
        rowLabel,
        warnings,
      );

      if (existing != null) {
        final updatedModel = _buildUpdatedIngredient(
          existing,
          branchId: branchId,
          name: name,
          category: category,
          unit: unit,
          sku: sku,
          barcode: barcode,
          costValue: costValue,
          stockValue: stockValue,
          minStockValue: minStockValue,
        );

        batch.update(
          _db.collection('ingredients').doc(existing.id),
          updatedModel.toFirestore(),
        );
        lookup.register(updatedModel);
        updatedCount++;
      } else {
        final newDoc = _db.collection('ingredients').doc();
        final newModel = _buildNewIngredient(
          id: newDoc.id,
          branchId: branchId,
          name: name,
          category: category,
          unit: unit,
          sku: sku,
          barcode: barcode,
          costValue: costValue,
          stockValue: stockValue,
          minStockValue: minStockValue,
        );

        batch.set(newDoc, newModel.toFirestore());
        lookup.register(newModel);
        createdCount++;
      }

      pendingWrites++;
      if (pendingWrites >= 400) {
        onProgress('Saving imported ingredients');
        await batch.commit();
        batch = _db.batch();
        pendingWrites = 0;
      }
    }

    if (pendingWrites > 0) {
      onProgress('Finalizing ingredient import');
      await batch.commit();
    }

    return IngredientImportResult(
      createdCount: createdCount,
      updatedCount: updatedCount,
      skippedCount: skippedCount,
      warnings: warnings,
    );
  }

  Future<List<IngredientModel>> _fetchExistingIngredients(
      String branchId) async {
    final snapshot = await _db
        .collection('ingredients')
        .where('branchIds', arrayContains: branchId)
        .get();
    return snapshot.docs.map(IngredientModel.fromFirestore).toList();
  }

  List<List<dynamic>> _parseRows(String fileName, List<int> bytes) {
    final extension = fileName.split('.').last.toLowerCase();
    if (extension == 'csv') {
      final text = utf8.decode(bytes, allowMalformed: true).replaceFirst(
            '\u{feff}',
            '',
          );
      return const CsvToListConverter(
        shouldParseNumbers: false,
      ).convert(text);
    }

    final excel = Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) {
      throw const FormatException('The selected spreadsheet is empty.');
    }

    final table = excel.tables.values.first;
    return table.rows
        .map((row) => row.map((cell) => cell?.value).toList())
        .toList();
  }

  Map<String, int> _buildHeaderMap(List<dynamic> headerRow) {
    final map = <String, int>{};
    for (var index = 0; index < headerRow.length; index++) {
      final key = _normalizeHeader((headerRow[index] ?? '').toString());
      if (key.isNotEmpty) {
        map.putIfAbsent(key, () => index);
      }
    }
    return map;
  }

  int? _resolveHeader(Map<String, int> headerMap, List<String> candidates) {
    for (final candidate in candidates) {
      final key = _normalizeHeader(candidate);
      if (headerMap.containsKey(key)) {
        return headerMap[key];
      }
    }
    return null;
  }

  String _normalizeHeader(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  bool _isRowEmpty(List<dynamic> row) {
    for (final value in row) {
      if (value != null && value.toString().trim().isNotEmpty) {
        return false;
      }
    }
    return true;
  }

  String _readString(List<dynamic> row, int? index) {
    if (index == null || index >= row.length) {
      return '';
    }
    return (row[index] ?? '').toString().trim();
  }

  _ParsedDouble _readDouble(List<dynamic> row, int? index) {
    if (index == null || index >= row.length) {
      return const _ParsedDouble();
    }

    final raw = row[index];
    if (raw == null) {
      return const _ParsedDouble();
    }
    if (raw is num) {
      return _ParsedDouble(value: raw.toDouble(), hasValue: true);
    }

    final text = raw.toString().trim();
    if (text.isEmpty) {
      return const _ParsedDouble();
    }

    final parsed = double.tryParse(text.replaceAll(',', ''));
    if (parsed == null) {
      return const _ParsedDouble(invalid: true);
    }
    return _ParsedDouble(value: parsed, hasValue: true);
  }

  String _normalizeCategory(
    String raw,
    String? existingValue,
    String rowLabel,
    List<String> warnings,
  ) {
    if (raw.trim().isEmpty) {
      return existingValue ?? IngredientModel.categories.first;
    }

    final normalized = raw
        .trim()
        .toLowerCase()
        .replaceAll('&', 'and')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');

    if (IngredientModel.categories.contains(normalized)) {
      return normalized;
    }

    warnings.add(
      '$rowLabel uses unsupported category "$raw". Existing/default category was kept.',
    );
    return existingValue ?? IngredientModel.categories.first;
  }

  String _normalizeUnit(
    String raw,
    String? existingValue,
    String rowLabel,
    List<String> warnings,
  ) {
    if (raw.trim().isEmpty) {
      return existingValue ?? IngredientModel.units.first;
    }

    const unitMap = <String, String>{
      'kg': 'kg',
      'g': 'g',
      'l': 'L',
      'ml': 'mL',
      'pieces': 'pieces',
      'piece': 'pieces',
      'pcs': 'pieces',
      'dozen': 'dozen',
      'bunch': 'bunch',
    };

    final normalized = raw.trim().toLowerCase();
    final canonical = unitMap[normalized];
    if (canonical != null && IngredientModel.units.contains(canonical)) {
      return canonical;
    }

    warnings.add(
      '$rowLabel uses unsupported unit "$raw". Existing/default unit was kept.',
    );
    return existingValue ?? IngredientModel.units.first;
  }

  IngredientModel _buildUpdatedIngredient(
    IngredientModel existing, {
    required String branchId,
    required String name,
    required String category,
    required String unit,
    required String sku,
    required String barcode,
    required _ParsedDouble costValue,
    required _ParsedDouble stockValue,
    required _ParsedDouble minStockValue,
  }) {
    final updatedStocks = Map<String, double>.from(existing.branchStocks);
    if (stockValue.hasValue) {
      updatedStocks[branchId] = stockValue.value!;
    }

    final updatedThresholds =
        Map<String, double>.from(existing.branchMinThresholds);
    if (minStockValue.hasValue) {
      updatedThresholds[branchId] = minStockValue.value!;
    }

    return existing.copyWith(
      branchIds: {
        ...existing.branchIds,
        branchId,
      }.toList(),
      name: name,
      category: category,
      unit: unit,
      costPerUnit: costValue.hasValue ? costValue.value : existing.costPerUnit,
      branchStocks: updatedStocks,
      branchMinThresholds: updatedThresholds,
      sku: sku.isNotEmpty ? sku : existing.sku,
      barcode: barcode.isNotEmpty ? barcode : existing.barcode,
      isActive: true,
      updatedAt: DateTime.now(),
    );
  }

  IngredientModel _buildNewIngredient({
    required String id,
    required String branchId,
    required String name,
    required String category,
    required String unit,
    required String sku,
    required String barcode,
    required _ParsedDouble costValue,
    required _ParsedDouble stockValue,
    required _ParsedDouble minStockValue,
  }) {
    final now = DateTime.now();
    return IngredientModel(
      id: id,
      branchIds: [branchId],
      name: name,
      category: category,
      unit: unit,
      costPerUnit: costValue.value ?? 0,
      branchStocks: {branchId: stockValue.value ?? 0},
      branchMinThresholds: {branchId: minStockValue.value ?? 0},
      supplierIds: const [],
      allergenTags: const [],
      isPerishable: false,
      sku: sku.isEmpty ? null : sku,
      barcode: barcode.isEmpty ? null : barcode,
      isActive: true,
      createdAt: now,
      updatedAt: now,
    );
  }
}

class _ParsedDouble {
  const _ParsedDouble({
    this.value,
    this.hasValue = false,
    this.invalid = false,
  });

  final double? value;
  final bool hasValue;
  final bool invalid;
}

class _IngredientLookup {
  _IngredientLookup(List<IngredientModel> existingIngredients) {
    for (final ingredient in existingIngredients) {
      register(ingredient);
    }
  }

  final Map<String, IngredientModel> _bySku = {};
  final Map<String, IngredientModel> _byBarcode = {};
  final Map<String, IngredientModel> _byName = {};

  IngredientModel? find({
    required String name,
    required String sku,
    required String barcode,
  }) {
    if (sku.trim().isNotEmpty) {
      final match = _bySku[_normalize(sku)];
      if (match != null) {
        return match;
      }
    }
    if (barcode.trim().isNotEmpty) {
      final match = _byBarcode[_normalize(barcode)];
      if (match != null) {
        return match;
      }
    }
    return _byName[_normalize(name)];
  }

  void register(IngredientModel ingredient) {
    if ((ingredient.sku ?? '').trim().isNotEmpty) {
      _bySku[_normalize(ingredient.sku!)] = ingredient;
    }
    if ((ingredient.barcode ?? '').trim().isNotEmpty) {
      _byBarcode[_normalize(ingredient.barcode!)] = ingredient;
    }
    if (ingredient.name.trim().isNotEmpty) {
      _byName[_normalize(ingredient.name)] = ingredient;
    }
  }

  String _normalize(String value) => value.trim().toLowerCase();
}
