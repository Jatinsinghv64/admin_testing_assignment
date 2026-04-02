import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';

import '../../constants.dart';

class SupplierImportResult {
  final int createdCount;
  final int updatedCount;
  final int skippedCount;
  final List<String> warnings;

  const SupplierImportResult({
    required this.createdCount,
    required this.updatedCount,
    required this.skippedCount,
    this.warnings = const [],
  });
}

class SupplierImportService {
  SupplierImportService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _suppliersCol =>
      _db.collection(AppConstants.collectionSuppliers);

  Future<SupplierImportResult?> pickAndImportSuppliers({
    required List<String> branchIds,
    required void Function(String message) onProgress,
  }) async {
    if (branchIds.isEmpty) {
      throw const FormatException(
        'Select at least one branch before importing suppliers.',
      );
    }

    onProgress('Select a supplier file');
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'xlsx', 'xls'],
      allowMultiple: false,
      withData: true,
    );

    if (picked == null || picked.files.isEmpty) {
      return null;
    }

    final file = picked.files.single;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw const FormatException('Unable to read the selected file.');
    }

    onProgress('Reading ${file.name}');
    final rows = _parseFileRows(file.name, bytes);
    if (rows.length < 2) {
      throw const FormatException(
        'The selected file does not contain any supplier rows.',
      );
    }

    final headerMap = _buildHeaderMap(rows.first);
    final companyIndex = _resolveHeader(headerMap, const [
      'company_name',
      'company',
      'companyname',
      'supplier',
      'supplier_name',
      'name',
    ]);
    if (companyIndex == null) {
      throw const FormatException(
        'Missing required company column. Use one of: company_name, company, supplier_name, or name.',
      );
    }

    final contactIndex = _resolveHeader(headerMap, const [
      'contact_person',
      'contact',
      'contact_name',
      'person',
    ]);
    final phoneIndex = _resolveHeader(headerMap, const ['phone', 'mobile']);
    final emailIndex = _resolveHeader(headerMap, const ['email', 'mail']);
    final addressIndex =
        _resolveHeader(headerMap, const ['address', 'location']);
    final paymentTermsIndex = _resolveHeader(headerMap, const [
      'payment_terms',
      'payment_term',
      'terms',
    ]);
    final notesIndex = _resolveHeader(headerMap, const ['notes', 'note']);
    final categoriesIndex = _resolveHeader(headerMap, const [
      'supplier_categories',
      'categories',
      'category',
      'top_supplied',
    ]);
    final ratingIndex = _resolveHeader(headerMap, const ['rating', 'score']);
    final activeIndex = _resolveHeader(headerMap, const [
      'is_active',
      'active',
      'status',
    ]);

    onProgress('Matching existing suppliers');
    final existingSuppliers = await _fetchExistingSuppliers(branchIds);
    final lookup = _SupplierLookup(existingSuppliers);
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

      final companyName = _readString(row, companyIndex);
      if (companyName.isEmpty) {
        skippedCount++;
        warnings
            .add('Row ${rowIndex + 1}: skipped because company name is empty.');
        continue;
      }

      final imported = _ImportedSupplier(
        companyName: companyName,
        contactPerson: _readString(row, contactIndex),
        phone: _readString(row, phoneIndex),
        email: _readString(row, emailIndex),
        address: _readString(row, addressIndex),
        paymentTerms: _readString(row, paymentTermsIndex),
        notes: _readString(row, notesIndex),
        categories: _readCategories(row, categoriesIndex),
        rating: _readInt(row, ratingIndex),
        isActive: _readBool(row, activeIndex),
      );

      final now = Timestamp.now();
      final existing = lookup.find(imported);
      if (existing == null) {
        final docRef = _suppliersCol.doc();
        batch.set(docRef, imported.toCreatePayload(branchIds, now));
        lookup.register(docRef.id, {
          'companyName': imported.companyName,
          'phone': imported.phone,
          'email': imported.email,
          'branchIds': branchIds,
        });
        createdCount++;
      } else {
        batch.update(
          _suppliersCol.doc(existing.id),
          imported.toUpdatePayload(existing.data, branchIds, now),
        );
        lookup.register(existing.id, {
          ...existing.data,
          'companyName': imported.companyName.isNotEmpty
              ? imported.companyName
              : existing.data['companyName'],
          'contactPerson': imported.contactPerson.isNotEmpty
              ? imported.contactPerson
              : existing.data['contactPerson'],
          'phone': imported.phone.isNotEmpty
              ? imported.phone
              : existing.data['phone'],
          'email': imported.email.isNotEmpty
              ? imported.email
              : existing.data['email'],
          'address': imported.address.isNotEmpty
              ? imported.address
              : existing.data['address'],
          'paymentTerms': imported.paymentTerms.isNotEmpty
              ? imported.paymentTerms
              : existing.data['paymentTerms'],
          'notes': imported.notes.isNotEmpty
              ? imported.notes
              : existing.data['notes'],
          'supplierCategories': imported.categories.isNotEmpty
              ? imported.categories
              : existing.data['supplierCategories'],
          'rating': imported.rating ?? existing.data['rating'],
          'isActive': imported.isActive ?? existing.data['isActive'],
          'branchIds': _mergeBranchIds(existing.data, branchIds),
        });
        updatedCount++;
      }

      pendingWrites++;
      if (pendingWrites >= 400) {
        onProgress('Saving supplier changes');
        await batch.commit();
        batch = _db.batch();
        pendingWrites = 0;
      }
    }

    if (pendingWrites > 0) {
      onProgress('Finalizing supplier import');
      await batch.commit();
    }

    return SupplierImportResult(
      createdCount: createdCount,
      updatedCount: updatedCount,
      skippedCount: skippedCount,
      warnings: warnings,
    );
  }

  Future<List<_ExistingSupplier>> _fetchExistingSuppliers(
    List<String> branchIds,
  ) async {
    Query<Map<String, dynamic>> query = _suppliersCol;
    if (branchIds.length == 1) {
      query = query.where('branchIds', arrayContains: branchIds.first);
    } else {
      query = query.where('branchIds',
          arrayContainsAny: branchIds.take(10).toList());
    }

    final snapshot = await query.get();
    return snapshot.docs
        .map((doc) => _ExistingSupplier(id: doc.id, data: doc.data()))
        .toList();
  }

  List<List<dynamic>> _parseFileRows(String fileName, List<int> bytes) {
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
      throw const FormatException('The selected Excel file is empty.');
    }

    final sheet = excel.tables.values.first;
    return sheet.rows
        .map(
          (row) => row.map((cell) => cell?.value).toList(),
        )
        .toList();
  }

  Map<String, int> _buildHeaderMap(List<dynamic> headerRow) {
    final map = <String, int>{};
    for (var index = 0; index < headerRow.length; index++) {
      final raw = _normalizeHeader(headerRow[index]?.toString() ?? '');
      if (raw.isNotEmpty) {
        map.putIfAbsent(raw, () => index);
      }
    }
    return map;
  }

  String _normalizeHeader(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
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

  int? _readInt(List<dynamic> row, int? index) {
    final raw = _readString(row, index);
    if (raw.isEmpty) {
      return null;
    }
    final value = int.tryParse(raw) ?? double.tryParse(raw)?.round();
    if (value == null) {
      return null;
    }
    return value.clamp(0, 5);
  }

  bool? _readBool(List<dynamic> row, int? index) {
    final raw = _readString(row, index).toLowerCase();
    if (raw.isEmpty) {
      return null;
    }
    if (const ['true', 'yes', 'y', '1', 'active'].contains(raw)) {
      return true;
    }
    if (const ['false', 'no', 'n', '0', 'inactive'].contains(raw)) {
      return false;
    }
    return null;
  }

  List<String> _readCategories(List<dynamic> row, int? index) {
    final raw = _readString(row, index);
    if (raw.isEmpty) {
      return const [];
    }
    return raw
        .split(RegExp(r'[,;|\n]'))
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .map(_toTitleCase)
        .toSet()
        .toList()
      ..sort();
  }

  String _toTitleCase(String value) {
    return value
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .map(
          (word) => word.length == 1
              ? word.toUpperCase()
              : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  List<String> _mergeBranchIds(
    Map<String, dynamic> existingData,
    List<String> branchIds,
  ) {
    return {
      ...List<String>.from(existingData['branchIds'] as List? ?? const []),
      ...branchIds,
    }.toList();
  }
}

class _ImportedSupplier {
  const _ImportedSupplier({
    required this.companyName,
    required this.contactPerson,
    required this.phone,
    required this.email,
    required this.address,
    required this.paymentTerms,
    required this.notes,
    required this.categories,
    required this.rating,
    required this.isActive,
  });

  final String companyName;
  final String contactPerson;
  final String phone;
  final String email;
  final String address;
  final String paymentTerms;
  final String notes;
  final List<String> categories;
  final int? rating;
  final bool? isActive;

  Map<String, dynamic> toCreatePayload(
    List<String> branchIds,
    Timestamp now,
  ) {
    return {
      'companyName': companyName,
      'contactPerson': contactPerson,
      'phone': phone,
      'email': email,
      'address': address,
      'paymentTerms': paymentTerms.isNotEmpty ? paymentTerms : 'Net 30',
      'notes': notes,
      'ingredientIds': const <String>[],
      'supplierCategories': categories,
      'rating': rating ?? 0,
      'isActive': isActive ?? true,
      'branchIds': branchIds,
      'createdAt': now,
      'updatedAt': now,
    };
  }

  Map<String, dynamic> toUpdatePayload(
    Map<String, dynamic> existingData,
    List<String> branchIds,
    Timestamp now,
  ) {
    return {
      'companyName':
          companyName.isNotEmpty ? companyName : existingData['companyName'],
      'contactPerson': contactPerson.isNotEmpty
          ? contactPerson
          : existingData['contactPerson'],
      'phone': phone.isNotEmpty ? phone : existingData['phone'],
      'email': email.isNotEmpty ? email : existingData['email'],
      'address': address.isNotEmpty ? address : existingData['address'],
      'paymentTerms': paymentTerms.isNotEmpty
          ? paymentTerms
          : (existingData['paymentTerms'] ?? 'Net 30'),
      'notes': notes.isNotEmpty ? notes : existingData['notes'],
      'supplierCategories': categories.isNotEmpty
          ? categories
          : List<String>.from(
              existingData['supplierCategories'] as List? ?? const [],
            ),
      'rating': rating ?? existingData['rating'] ?? 0,
      'isActive': isActive ?? existingData['isActive'] ?? true,
      'branchIds': {
        ...List<String>.from(existingData['branchIds'] as List? ?? const []),
        ...branchIds,
      }.toList(),
      'updatedAt': now,
    };
  }
}

class _ExistingSupplier {
  const _ExistingSupplier({
    required this.id,
    required this.data,
  });

  final String id;
  final Map<String, dynamic> data;
}

class _SupplierLookup {
  _SupplierLookup(List<_ExistingSupplier> suppliers) {
    for (final supplier in suppliers) {
      register(supplier.id, supplier.data);
    }
  }

  final Map<String, _ExistingSupplier> _suppliersById = {};
  final Map<String, String> _idsByEmail = {};
  final Map<String, String> _idsByCompany = {};
  final Map<String, String> _idsByCompanyPhone = {};

  _ExistingSupplier? find(_ImportedSupplier supplier) {
    final emailKey = _normalizeKey(supplier.email);
    if (emailKey.isNotEmpty) {
      final id = _idsByEmail[emailKey];
      if (id != null) {
        return _suppliersById[id];
      }
    }

    final companyPhoneKey = _normalizeKey(
      '${supplier.companyName}::${supplier.phone}',
    );
    if (companyPhoneKey.isNotEmpty) {
      final id = _idsByCompanyPhone[companyPhoneKey];
      if (id != null) {
        return _suppliersById[id];
      }
    }

    final companyKey = _normalizeKey(supplier.companyName);
    if (companyKey.isEmpty) {
      return null;
    }
    final id = _idsByCompany[companyKey];
    if (id == null) {
      return null;
    }
    return _suppliersById[id];
  }

  void register(String id, Map<String, dynamic> data) {
    final supplier =
        _ExistingSupplier(id: id, data: Map<String, dynamic>.from(data));
    _suppliersById[id] = supplier;

    final emailKey = _normalizeKey((data['email'] ?? '').toString());
    if (emailKey.isNotEmpty) {
      _idsByEmail[emailKey] = id;
    }

    final companyKey = _normalizeKey((data['companyName'] ?? '').toString());
    if (companyKey.isNotEmpty) {
      _idsByCompany[companyKey] = id;
    }

    final phoneKey = _normalizeKey(
      '${(data['companyName'] ?? '').toString()}::${(data['phone'] ?? '').toString()}',
    );
    if (phoneKey.isNotEmpty && phoneKey != '::') {
      _idsByCompanyPhone[phoneKey] = id;
    }
  }

  String _normalizeKey(String value) {
    return value.trim().toLowerCase();
  }
}
