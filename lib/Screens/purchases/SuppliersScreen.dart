import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../Widgets/BranchFilterService.dart';
import '../../main.dart';
import '../../services/inventory/PurchaseOrderService.dart';
import '../../services/inventory/SupplierImportService.dart';
import '../../Models/inventory/supplier.dart';
import 'supplier_import_format_dialog.dart';
import 'components/supplier_card.dart';
import 'components/supplier_form_sheet.dart';

class SuppliersScreen extends StatefulWidget {
  const SuppliersScreen({
    super.key,
    this.initialSearchQuery = '',
  });

  final String initialSearchQuery;

  @override
  State<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends State<SuppliersScreen> {
  String _filter = 'all';
  String _categoryFilter = 'All';
  String _searchQuery = '';
  bool _isImportingSuppliers = false;
  final TextEditingController _searchCtrl = TextEditingController();
  String? _expandedSupplierId;

  final List<String> availableCategories = [
    'Produce', 'Dairy', 'Meat', 'Poultry', 'Seafood',
    'Spices', 'Dry Goods', 'Beverages', 'Packaging', 'Other'
  ];

  @override
  void initState() {
    super.initState();
    final initialQuery = widget.initialSearchQuery.trim();
    if (initialQuery.isNotEmpty) {
      _searchCtrl.text = initialQuery;
      _searchQuery = initialQuery.toLowerCase();
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _showSnackBar(String message, {Color backgroundColor = Colors.red}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: backgroundColor),
    );
  }

  Future<void> _handleSupplierImport(List<String> branchIds) async {
    if (_isImportingSuppliers) return;
    if (branchIds.isEmpty) {
      _showSnackBar('Select at least one branch before importing.');
      return;
    }

    final progress = ValueNotifier<String>('Preparing supplier import');
    setState(() => _isImportingSuppliers = true);

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          content: ValueListenableBuilder<String>(
            valueListenable: progress,
            builder: (_, val, __) => Row(
              children: [
                const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 16),
                Expanded(child: Text(val)),
              ],
            ),
          ),
        ),
      );

      final result = await SupplierImportService().pickAndImportSuppliers(
        branchIds: branchIds,
        onProgress: (msg) => progress.value = msg,
      );

      if (mounted) Navigator.pop(context);

      if (result != null) {
        _showSnackBar(
          'Import complete: ${result.createdCount} added, ${result.updatedCount} updated',
          backgroundColor: Colors.green,
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showSnackBar('Import failed: $e');
    } finally {
      if (mounted) setState(() => _isImportingSuppliers = false);
    }
  }

  Future<void> _openSupplierForm(List<String> branchIds, {Supplier? existing}) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SupplierFormSheet(
        existingSupplier: existing,
        branchIds: branchIds,
        availableCategories: availableCategories,
      ),
    );

    if (result == true) {
      _showSnackBar(existing == null ? 'Supplier added' : 'Supplier updated', backgroundColor: Colors.green);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userScope = context.watch<UserScopeService>();
    final branchFilter = context.watch<BranchFilterService>();
    final branchIds = branchFilter.getFilterBranchIds(userScope.branchIds);
    final poService = context.watch<PurchaseOrderService>();

    bool? streamIsActive;
    if (_filter == 'active') streamIsActive = true;
    if (_filter == 'inactive') streamIsActive = false;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Column(
        children: [
          _buildHeader(branchIds),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFilterRow(),
                  const SizedBox(height: 16),
                  _buildCategoryFilter(),
                  const SizedBox(height: 24),
                  Expanded(
                    child: branchIds.isEmpty
                        ? _buildEmptyState('Select a branch to manage suppliers.')
                        : StreamBuilder<List<Supplier>>(
                            stream: poService.streamSuppliers(branchIds, isActive: streamIsActive),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState == ConnectionState.waiting) {
                                return const Center(child: CircularProgressIndicator(color: Colors.deepPurple));
                              }
                              if (snapshot.hasError) {
                                return _buildEmptyState('Error loading suppliers: ${snapshot.error}');
                              }

                              var suppliers = snapshot.data ?? [];
                              if (_searchQuery.isNotEmpty) {
                                suppliers = suppliers.where((s) {
                                  final searchIn = '${s.companyName} ${s.contactPerson} ${s.email} ${s.phone}'.toLowerCase();
                                  return searchIn.contains(_searchQuery);
                                }).toList();
                              }

                              if (_categoryFilter != 'All') {
                                suppliers = suppliers.where((s) => s.supplierCategories.contains(_categoryFilter)).toList();
                              }

                              if (suppliers.isEmpty) return _buildEmptyState('No suppliers found matching your criteria.');

                              return _buildSupplierGrid(suppliers, branchIds);
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(List<String> branchIds) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Suppliers', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black87)),
              Text('Manage relationships, contacts, and purchase history.', style: TextStyle(color: Colors.grey[600])),
            ],
          ),
          Row(
            children: [
              _buildSearchBar(),
              const SizedBox(width: 16),
              OutlinedButton.icon(
                onPressed: branchIds.isEmpty ? null : () => _handleSupplierImport(branchIds),
                icon: const Icon(Icons.upload_file_outlined, size: 18),
                label: const Text('Import'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.deepPurple,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  side: BorderSide(color: Colors.grey.shade300),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: branchIds.isEmpty ? null : () => _openSupplierForm(branchIds),
                icon: const Icon(Icons.add, size: 20),
                label: const Text('Add New Supplier', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: TextField(
        controller: _searchCtrl,
        decoration: InputDecoration(
          hintText: 'Search suppliers...',
          hintStyle: TextStyle(color: Colors.grey[500], fontSize: 14),
          prefixIcon: Icon(Icons.search, color: Colors.grey[500], size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          isDense: true,
        ),
        onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
      ),
    );
  }

  Widget _buildFilterRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text('Supplier Directory', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)),
        Row(
          children: [
            _statusFilterButton('All', 'all'),
            const SizedBox(width: 8),
            _statusFilterButton('Active', 'active'),
            const SizedBox(width: 8),
            _statusFilterButton('Inactive', 'inactive'),
          ],
        ),
      ],
    );
  }

  Widget _statusFilterButton(String label, String value) {
    final isSelected = _filter == value;
    return InkWell(
      onTap: () => setState(() => _filter = value),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.deepPurple.shade50 : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.deepPurple : Colors.grey.shade600,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryFilter() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _categoryChip('All'),
          ...availableCategories.map((c) => Padding(
            padding: const EdgeInsets.only(left: 8),
            child: _categoryChip(c),
          )),
        ],
      ),
    );
  }

  Widget _categoryChip(String label) {
    final selected = _categoryFilter == label;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _categoryFilter = label),
      selectedColor: Colors.deepPurple,
      labelStyle: TextStyle(
        color: selected ? Colors.white : Colors.grey[700],
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  Widget _buildSupplierGrid(List<Supplier> suppliers, List<String> branchIds) {
    return LayoutBuilder(
      builder: (context, constraints) {
        int crossAxisCount = constraints.maxWidth >= 1200 ? 3 : (constraints.maxWidth >= 800 ? 2 : 1);
        final cardWidth = (constraints.maxWidth - ((crossAxisCount - 1) * 24)) / crossAxisCount - 0.1;

        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 32),
          child: Wrap(
            spacing: 24,
            runSpacing: 24,
            children: suppliers.map((s) => SizedBox(
              width: cardWidth,
              child: SupplierCard(
                supplier: s,
                branchIds: branchIds,
                onEdit: () => _openSupplierForm(branchIds, existing: s),
                initiallyExpanded: _expandedSupplierId == s.id,
              ),
            )).toList(),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[200]),
          const SizedBox(height: 16),
          Text(message, style: TextStyle(color: Colors.grey[500], fontSize: 16)),
        ],
      ),
    );
  }
}
