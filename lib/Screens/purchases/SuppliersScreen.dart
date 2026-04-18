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
    final theme = Theme.of(context);
    final userScope = context.watch<UserScopeService>();
    final branchFilter = context.watch<BranchFilterService>();
    final branchIds = branchFilter.getFilterBranchIds(userScope.branchIds);
    final poService = context.watch<PurchaseOrderService>();

    bool? streamIsActive;
    if (_filter == 'active') streamIsActive = true;
    if (_filter == 'inactive') streamIsActive = false;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        children: [
          _buildHeader(branchIds, theme),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFilterRow(theme),
                  const SizedBox(height: 16),
                  _buildCategoryFilter(theme),
                  const SizedBox(height: 24),
                  Expanded(
                    child: branchIds.isEmpty
                        ? _buildEmptyState('Select a branch to manage suppliers.', theme)
                        : StreamBuilder<List<Supplier>>(
                            stream: poService.streamSuppliers(branchIds, isActive: streamIsActive),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState == ConnectionState.waiting) {
                                return Center(child: CircularProgressIndicator(color: theme.colorScheme.primary));
                              }
                              if (snapshot.hasError) {
                                return _buildEmptyState('Error loading suppliers: ${snapshot.error}', theme);
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

                              if (suppliers.isEmpty) return _buildEmptyState('No suppliers found matching your criteria.', theme);

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

  Widget _buildHeader(List<String> branchIds, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Suppliers', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: theme.textTheme.bodyLarge?.color)),
              Text('Manage relationships, contacts, and purchase history.', style: TextStyle(color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6))),
            ],
          ),
          Row(
            children: [
              _buildSearchBar(theme),
              const SizedBox(width: 16),
              OutlinedButton.icon(
                onPressed: branchIds.isEmpty ? null : () => _handleSupplierImport(branchIds),
                icon: const Icon(Icons.upload_file_outlined, size: 18),
                label: const Text('Import'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  side: BorderSide(color: theme.dividerColor),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: branchIds.isEmpty ? null : () => _openSupplierForm(branchIds),
                icon: const Icon(Icons.add, size: 20),
                label: const Text('Add New Supplier', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
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

  Widget _buildSearchBar(ThemeData theme) {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark ? Colors.white.withOpacity(0.05) : Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor),
      ),
      child: TextField(
        controller: _searchCtrl,
        style: TextStyle(color: theme.textTheme.bodyLarge?.color),
        decoration: InputDecoration(
          hintText: 'Search suppliers...',
          hintStyle: TextStyle(color: theme.textTheme.bodyMedium?.color?.withOpacity(0.5), fontSize: 14),
          prefixIcon: Icon(Icons.search, color: theme.textTheme.bodyMedium?.color?.withOpacity(0.5), size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          isDense: true,
        ),
        onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
      ),
    );
  }

  Widget _buildFilterRow(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('Supplier Directory', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: theme.textTheme.bodyLarge?.color)),
        Row(
          children: [
            _statusFilterButton('All', 'all', theme),
            const SizedBox(width: 8),
            _statusFilterButton('Active', 'active', theme),
            const SizedBox(width: 8),
            _statusFilterButton('Inactive', 'inactive', theme),
          ],
        ),
      ],
    );
  }

  Widget _statusFilterButton(String label, String value, ThemeData theme) {
    final isSelected = _filter == value;
    return InkWell(
      onTap: () => setState(() => _filter = value),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? theme.colorScheme.primary.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? theme.colorScheme.primary : theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryFilter(ThemeData theme) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _categoryChip('All', theme),
          ...availableCategories.map((c) => Padding(
            padding: const EdgeInsets.only(left: 8),
            child: _categoryChip(c, theme),
          )),
        ],
      ),
    );
  }

  Widget _categoryChip(String label, ThemeData theme) {
    final selected = _categoryFilter == label;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _categoryFilter = label),
      selectedColor: theme.colorScheme.primary,
      backgroundColor: theme.cardColor,
      labelStyle: TextStyle(
        color: selected ? Colors.white : theme.textTheme.bodyMedium?.color?.withOpacity(0.8),
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

  Widget _buildEmptyState(String message, ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 64, color: theme.dividerColor),
          const SizedBox(height: 16),
          Text(message, style: TextStyle(color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6), fontSize: 16)),
        ],
      ),
    );
  }
}
