import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../Widgets/BranchFilterService.dart';
import '../../main.dart';
import '../../services/inventory/PurchaseOrderService.dart';
import '../../services/inventory/SupplierImportService.dart';
import 'supplier_import_format_dialog.dart';
import 'SupplierPurchaseOrdersDialog.dart';

class SuppliersScreen extends StatefulWidget {
  const SuppliersScreen({
    super.key,
    this.initialSearchQuery = '',
  });

  final String initialSearchQuery;

  @override
  State<SuppliersScreen> createState() => _SuppliersScreenState();
}

enum _SupplierCardAction {
  viewProfile,
  call,
  email,
  toggleStatus,
}

class _SuppliersScreenState extends State<SuppliersScreen> {
  late final PurchaseOrderService _service;
  bool _serviceInitialized = false;
  String _filter = 'all';
  String _categoryFilter = 'All';
  String _searchQuery = '';
  bool _isImportingSuppliers = false;
  final Set<String> _busySupplierIds = <String>{};
  final TextEditingController _searchCtrl = TextEditingController();
  String? _expandedSupplierId;

  final List<String> availableCategories = [
    'Produce',
    'Dairy',
    'Meat',
    'Poultry',
    'Seafood',
    'Spices',
    'Dry Goods',
    'Beverages',
    'Packaging',
    'Other'
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_serviceInitialized) {
      _serviceInitialized = true;
      _service = Provider.of<PurchaseOrderService>(context, listen: false);
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _showSnackBar(
    String message, {
    Color backgroundColor = Colors.red,
  }) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
      ),
    );
  }

  Future<void> _launchSupplierUri(
    Uri uri, {
    required String failureMessage,
  }) async {
    try {
      final launched = await launchUrl(uri);
      if (!launched) {
        _showSnackBar(failureMessage);
      }
    } catch (_) {
      _showSnackBar(failureMessage);
    }
  }

  Future<void> _handleSupplierImport(List<String> branchIds) async {
    if (_isImportingSuppliers) {
      return;
    }
    if (branchIds.isEmpty) {
      _showSnackBar('Select at least one branch before importing suppliers.');
      return;
    }

    final progress = ValueNotifier<String>('Preparing supplier import');
    var dialogShown = false;
    setState(() => _isImportingSuppliers = true);

    try {
      dialogShown = true;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return PopScope(
            canPop: false,
            child: AlertDialog(
              content: ValueListenableBuilder<String>(
                valueListenable: progress,
                builder: (_, value, __) {
                  return Row(
                    children: [
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.deepPurple,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          value,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          );
        },
      );

      final result = await SupplierImportService().pickAndImportSuppliers(
        branchIds: branchIds,
        onProgress: (message) => progress.value = message,
      );

      if (dialogShown && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        dialogShown = false;
      }

      if (result == null) {
        return;
      }

      final summary = StringBuffer('Supplier import complete: ')
        ..write('${result.createdCount} added')
        ..write(', ${result.updatedCount} updated');
      if (result.skippedCount > 0) {
        summary.write(', ${result.skippedCount} skipped');
      }
      _showSnackBar(summary.toString(), backgroundColor: Colors.green);

      if (result.warnings.isNotEmpty && mounted) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Import Warnings'),
            content: SizedBox(
              width: 420,
              child: ListView(
                shrinkWrap: true,
                children: result.warnings
                    .take(10)
                    .map((warning) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(warning),
                        ))
                    .toList(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (dialogShown && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      _showSnackBar('Supplier import failed: $e');
    } finally {
      progress.dispose();
      if (mounted) {
        setState(() => _isImportingSuppliers = false);
      }
    }
  }

  Future<void> _showImportGuideAndImport(List<String> branchIds) async {
    final shouldContinue = await showSupplierImportFormatDialog(context);
    if (!shouldContinue || !mounted) {
      return;
    }
    await _handleSupplierImport(branchIds);
  }

  Future<void> _handleSupplierCardAction({
    required _SupplierCardAction action,
    required Map<String, dynamic> data,
    required List<String> branchIds,
    required VoidCallback onEdit,
  }) async {
    switch (action) {
      case _SupplierCardAction.viewProfile:
        onEdit();
        return;
      case _SupplierCardAction.call:
        final phone = (data['phone'] ?? '').toString().trim();
        if (phone.isEmpty) {
          _showSnackBar('This supplier does not have a phone number.');
          return;
        }
        await _launchSupplierUri(
          Uri.parse('tel:$phone'),
          failureMessage: 'Unable to start a call for this supplier.',
        );
        return;
      case _SupplierCardAction.email:
        final email = (data['email'] ?? '').toString().trim();
        if (email.isEmpty) {
          _showSnackBar('This supplier does not have an email address.');
          return;
        }
        await _launchSupplierUri(
          Uri.parse('mailto:$email'),
          failureMessage: 'Unable to open an email app for this supplier.',
        );
        return;
      case _SupplierCardAction.toggleStatus:
        final supplierId = (data['id'] ?? '').toString();
        if (supplierId.isEmpty) {
          _showSnackBar('Supplier record is missing an id.');
          return;
        }
        if (_busySupplierIds.contains(supplierId)) {
          return;
        }

        final effectiveBranchIds = List<String>.from(
          data['branchIds'] as List? ?? branchIds,
        );
        if (effectiveBranchIds.isEmpty) {
          _showSnackBar('This supplier is not linked to any branch.');
          return;
        }

        setState(() => _busySupplierIds.add(supplierId));
        try {
          final currentlyActive = data['isActive'] == true;
          await _service.saveSupplier(
            supplierId: supplierId,
            branchIds: effectiveBranchIds,
            data: {'isActive': !currentlyActive},
          );
          _showSnackBar(
            currentlyActive ? 'Supplier deactivated' : 'Supplier activated',
            backgroundColor: Colors.green,
          );
        } catch (e) {
          _showSnackBar('Unable to update supplier status: $e');
        } finally {
          if (mounted) {
            setState(() => _busySupplierIds.remove(supplierId));
          }
        }
        return;
    }
  }

  Widget _buildNoBranchState(String message) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            color: Colors.grey.shade700,
            height: 1.5,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userScope = context.watch<UserScopeService>();
    final branchFilter = context.watch<BranchFilterService>();
    final branchIds = branchFilter.getFilterBranchIds(userScope.branchIds);

    bool? streamIsActive;
    if (_filter == 'active') {
      streamIsActive = true;
    } else if (_filter == 'inactive') {
      streamIsActive = false;
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Column(
        children: [
          // Header Section
          Container(
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
                    const Text('Suppliers',
                        style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87)),
                    Text(
                        'Manage supplier relationships and contact information.',
                        style: TextStyle(color: Colors.grey[600])),
                  ],
                ),
                Row(
                  children: [
                    Container(
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
                          hintStyle:
                              TextStyle(color: Colors.grey[500], fontSize: 14),
                          prefixIcon: Icon(Icons.search,
                              color: Colors.grey[500], size: 20),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          isDense: true,
                        ),
                        onChanged: (val) => setState(
                            () => _searchQuery = val.trim().toLowerCase()),
                      ),
                    ),
                    const SizedBox(width: 16),
                    OutlinedButton.icon(
                      onPressed: branchIds.isEmpty || _isImportingSuppliers
                          ? null
                          : () => _showImportGuideAndImport(branchIds),
                      icon: _isImportingSuppliers
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.upload_file_outlined, size: 18),
                      label: const Text(
                        'Import',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.deepPurple,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 16,
                        ),
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: branchIds.isEmpty
                          ? null
                          : () =>
                              _openSupplierForm(context, userScope, branchIds),
                      icon: const Icon(Icons.add, size: 20),
                      label: const Text('Add New Supplier',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Filter Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Supplier Directory',
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87)),
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
                  ),
                  const SizedBox(height: 16),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _categoryFilterChip('All'),
                        ...availableCategories.map((c) => Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: _categoryFilterChip(c),
                            )),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  Expanded(
                    child: branchIds.isEmpty
                        ? _buildNoBranchState(
                            'Select at least one branch to view, add, or import suppliers.',
                          )
                        : StreamBuilder<List<Map<String, dynamic>>>(
                            stream: _service.streamSuppliers(
                              branchIds,
                              isActive: streamIsActive,
                            ),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const Center(
                                  child: CircularProgressIndicator(
                                    color: Colors.deepPurple,
                                  ),
                                );
                              }
                              if (snapshot.hasError) {
                                return Center(
                                  child: Text(
                                    'Failed to load suppliers: ${snapshot.error}',
                                    style: const TextStyle(color: Colors.red),
                                  ),
                                );
                              }
                              var suppliers = snapshot.data ?? [];

                              if (_searchQuery.isNotEmpty) {
                                suppliers = suppliers.where((supplier) {
                                  final values = [
                                    supplier['companyName'],
                                    supplier['contactPerson'],
                                    supplier['email'],
                                    supplier['phone'],
                                    supplier['notes'],
                                  ]
                                      .map((value) => (value ?? '')
                                          .toString()
                                          .toLowerCase())
                                      .join(' ');
                                  return values.contains(_searchQuery);
                                }).toList();
                              }

                              if (_categoryFilter != 'All') {
                                suppliers = suppliers.where((supplier) {
                                  final cats = List<String>.from(
                                    supplier['supplierCategories'] as List? ??
                                        const [],
                                  );
                                  return cats.contains(_categoryFilter);
                                }).toList();
                              }

                              if (suppliers.isEmpty) {
                                return const Center(
                                  child: Text(
                                    'No suppliers found.',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey,
                                    ),
                                  ),
                                );
                              }

                              return LayoutBuilder(
                                builder: (context, constraints) {
                                  var crossAxisCount = 1;
                                  if (constraints.maxWidth >= 1200) {
                                    crossAxisCount = 3;
                                  } else if (constraints.maxWidth >= 800) {
                                    crossAxisCount = 2;
                                  }

                                  final cardWidth = (constraints.maxWidth - ((crossAxisCount - 1) * 24)) / crossAxisCount - 0.1; // minor subtraction to prevent wrap rounding issues

                                  return SingleChildScrollView(
                                    padding: const EdgeInsets.only(bottom: 32),
                                    child: Wrap(
                                      spacing: 24,
                                      runSpacing: 24,
                                      children: suppliers.map((supplier) {
                                        return SizedBox(
                                          width: cardWidth,
                                          child: _supplierCard(
                                            context: context,
                                            data: supplier,
                                            branchIds: branchIds,
                                            onEdit: () => _openSupplierForm(
                                              context,
                                              userScope,
                                              branchIds,
                                              existing: supplier,
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  );
                                },
                              );
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

  Widget _categoryFilterChip(String label) {
    final selected = _categoryFilter == label;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => setState(() => _categoryFilter = label),
      color: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? Colors.deepPurple
            : Colors.white;
      }),
      side: BorderSide(
        color: selected ? Colors.deepPurple : Colors.grey.shade300,
      ),
      labelStyle: TextStyle(
        color: selected ? Colors.white : Colors.grey[700],
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  Widget _supplierCard({
    required BuildContext context,
    required Map<String, dynamic> data,
    required List<String> branchIds,
    required VoidCallback onEdit,
  }) {
    final isActive = data['isActive'] == true;
    final companyName = (data['companyName'] ?? '').toString();
    final initials = companyName.isNotEmpty
        ? companyName.substring(0, companyName.length > 1 ? 2 : 1).toUpperCase()
        : 'S';
    final contactPerson = (data['contactPerson']?.toString().trim().isEmpty ?? true) ? '-' : data['contactPerson'].toString();
    final phone = (data['phone']?.toString().trim().isEmpty ?? true) ? '-' : data['phone'].toString();
    final email = (data['email']?.toString().trim().isEmpty ?? true) ? '-' : data['email'].toString();
    final phoneValue = (data['phone'] ?? '').toString().trim();
    final emailValue = (data['email'] ?? '').toString().trim();
    final paymentTerms = (data['paymentTerms'] ?? 'Net 30').toString();
    final List cats = data['supplierCategories'] as List? ?? [];

    final isExpanded = _expandedSupplierId == (data['id']?.toString());
    
    return InkWell(
      onTap: () {
        setState(() {
          if (isExpanded) {
            _expandedSupplierId = null;
          } else {
            _expandedSupplierId = data['id']?.toString();
          }
        });
      },
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            if (isExpanded)
              BoxShadow(
                color: Colors.deepPurple.withOpacity(0.08),
                blurRadius: 15,
                offset: const Offset(0, 8),
              )
            else
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.deepPurple.shade100),
                  ),
                  child: Center(
                    child: Text(initials,
                        style: TextStyle(
                            color: Colors.deepPurple.shade700,
                            fontWeight: FontWeight.bold,
                            fontSize: 20)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        companyName,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Colors.black87),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isActive ? Colors.green : Colors.grey,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isActive ? 'Active' : 'Inactive',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey.shade600),
                          ),
                        ],
                      )
                    ],
                  ),
                ),
                PopupMenuButton<_SupplierCardAction>(
                  icon: Icon(Icons.more_vert, color: Colors.grey.shade400),
                  padding: EdgeInsets.zero,
                  tooltip: 'Supplier actions',
                  constraints: const BoxConstraints(),
                  onSelected: (action) => _handleSupplierCardAction(
                    action: action,
                    data: data,
                    branchIds: branchIds,
                    onEdit: onEdit,
                  ),
                  itemBuilder: (menuContext) => [
                    const PopupMenuItem(
                      value: _SupplierCardAction.viewProfile,
                      child: Text('View Profile'),
                    ),
                    PopupMenuItem(
                      value: _SupplierCardAction.toggleStatus,
                      child: Text(
                        isActive ? 'Mark Inactive' : 'Mark Active',
                      ),
                    ),
                    PopupMenuItem(
                      value: _SupplierCardAction.call,
                      enabled: phoneValue.isNotEmpty,
                      child: const Text('Call Supplier'),
                    ),
                    PopupMenuItem(
                      value: _SupplierCardAction.email,
                      enabled: emailValue.isNotEmpty,
                      child: const Text('Email Supplier'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1, color: Color(0xFFEEEEEE)),
            const SizedBox(height: 16),
            _infoRow(Icons.person_outline, contactPerson),
            const SizedBox(height: 10),
            _infoRow(
              Icons.phone_outlined,
              phone,
              isPhone: true,
              phoneValue: data['phone']?.toString(),
            ),
            const SizedBox(height: 10),
            _infoRow(
              Icons.email_outlined,
              email,
              isEmail: true,
              emailValue: data['email']?.toString(),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('TOP SUPPLIED',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade400,
                              letterSpacing: 0.5)),
                      const SizedBox(height: 8),
                      cats.isEmpty
                          ? Text('-', style: TextStyle(color: Colors.grey.shade500, fontSize: 12))
                          : Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: cats.take(3).map((cat) => Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(cat.toString(),
                                        style: TextStyle(fontSize: 10, color: Colors.grey.shade700)),
                                  )).toList(),
                            ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('PAYMENT TERMS',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade400,
                            letterSpacing: 0.5)),
                    const SizedBox(height: 8),
                    Text(
                      paymentTerms,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.black87),
                    ),
                  ],
                ),
              ],
            ),
            if (!isExpanded) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _expandedSupplierId = data['id']?.toString();
                    });
                  },
                  icon: const Icon(Icons.receipt_long_outlined, size: 18),
                  label: const Text('View Purchase Orders'),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.grey.shade50,
                    foregroundColor: Colors.deepPurple,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: Colors.grey.shade200),
                    ),
                  ),
                ),
              ),
            ],
            if (isExpanded) ...[
              const SizedBox(height: 16),
              const Divider(color: Color(0xFFEEEEEE)),
              const SizedBox(height: 12),
              Container(
                constraints: const BoxConstraints(maxHeight: 300),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: _SupplierInlinePurchaseOrders(
                  supplierId: data['id']?.toString() ?? '',
                  branchIds: branchIds,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _expandedSupplierId = null;
                    });
                  },
                  icon: const Icon(Icons.keyboard_arrow_up, size: 20),
                  label: const Text('Collapse History'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey.shade600,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text,
      {bool isPhone = false,
      bool isEmail = false,
      String? phoneValue,
      String? emailValue}) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade400),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (isPhone && (phoneValue?.trim().isNotEmpty ?? false))
          InkWell(
            onTap: () => _launchSupplierUri(
              Uri.parse('tel:${phoneValue!.trim()}'),
              failureMessage: 'Unable to start a call for this supplier.',
            ),
            child: const Icon(Icons.call, size: 16, color: Colors.green),
          ),
        if (isEmail && (emailValue?.trim().isNotEmpty ?? false))
          Padding(
            padding: const EdgeInsets.only(left: 8.0),
            child: InkWell(
              onTap: () => _launchSupplierUri(
                Uri.parse('mailto:${emailValue!.trim()}'),
                failureMessage:
                    'Unable to open an email app for this supplier.',
              ),
              child:
                  const Icon(Icons.email, size: 16, color: Colors.deepPurple),
            ),
          ),
      ],
    );
  }

  Widget _buildTextInput({
    required TextEditingController controller,
    required String label,
    IconData? icon,
    TextInputType? keyboardType,
    int maxLines = 1,
    bool required = false,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: icon != null
            ? Icon(icon, color: Colors.deepPurple.shade300, size: 20)
            : null,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.deepPurple, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        labelStyle: TextStyle(color: Colors.grey[700], fontSize: 14),
      ),
      validator: required
          ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
          : null,
    );
  }

  Widget _buildSelector({
    required String label,
    required String value,
    required List<String> items,
    required void Function(String) onChanged,
    IconData? icon,
  }) {
    return InkWell(
      onTap: () {
        showModalBottomSheet(
          context: context,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          builder: (ctx) => Container(
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text(label,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: items.length,
                    itemBuilder: (ctx, i) {
                      final item = items[i];
                      final selected = item == value;
                      return ListTile(
                        onTap: () {
                          onChanged(item);
                          Navigator.pop(ctx);
                        },
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: selected
                                  ? Colors.deepPurple.withValues(alpha: 0.3)
                                  : Colors.grey.shade200,
                            ),
                          ),
                          child: Icon(icon ?? Icons.label_outline,
                              size: 18,
                              color: selected
                                  ? Colors.deepPurple
                                  : Colors.grey[600]),
                        ),
                        title: Text(item,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: selected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color:
                                  selected ? Colors.deepPurple : Colors.black87,
                            )),
                        trailing: selected
                            ? const Icon(Icons.check_circle,
                                color: Colors.deepPurple, size: 20)
                            : null,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(14),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.white,
          prefixIcon: Icon(icon ?? Icons.label_outline,
              size: 20, color: Colors.deepPurple.shade300),
          suffixIcon:
              Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey[400]),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Colors.deepPurple, width: 1.5),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
        child: Text(
          value,
          style: const TextStyle(fontSize: 14, color: Colors.black87),
        ),
      ),
    );
  }

  Future<void> _openSupplierForm(
    BuildContext context,
    UserScopeService userScope,
    List<String> branchIds, {
    Map<String, dynamic>? existing,
  }) async {
    final isEdit = existing != null;
    final companyCtrl = TextEditingController(
        text: (existing?['companyName'] ?? '').toString());
    final contactCtrl = TextEditingController(
        text: (existing?['contactPerson'] ?? '').toString());
    final phoneCtrl =
        TextEditingController(text: (existing?['phone'] ?? '').toString());
    final emailCtrl =
        TextEditingController(text: (existing?['email'] ?? '').toString());
    final addressCtrl =
        TextEditingController(text: (existing?['address'] ?? '').toString());
    final notesCtrl =
        TextEditingController(text: (existing?['notes'] ?? '').toString());
    final ingredientIds =
        List<String>.from(existing?['ingredientIds'] as List? ?? []);
    final supplierCategories =
        List<String>.from(existing?['supplierCategories'] as List? ?? []);
    String paymentTerms = (existing?['paymentTerms'] ?? 'Net 30').toString();
    bool isActive = existing?['isActive'] != false;
    int rating = (existing?['rating'] as num?)?.toInt() ?? 0;
    final formKey = GlobalKey<FormState>();

    try {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) {
          return StatefulBuilder(builder: (ctx, setSheet) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isEdit ? 'Edit Supplier' : 'Add Supplier',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.deepPurple,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildTextInput(
                        controller: companyCtrl,
                        label: 'Company name *',
                        icon: Icons.business_outlined,
                        required: true,
                      ),
                      const SizedBox(height: 10),
                      _buildTextInput(
                        controller: contactCtrl,
                        label: 'Contact person',
                        icon: Icons.person_outline,
                      ),
                      const SizedBox(height: 10),
                      _buildTextInput(
                        controller: phoneCtrl,
                        label: 'Phone',
                        icon: Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 10),
                      _buildTextInput(
                        controller: emailCtrl,
                        label: 'Email',
                        icon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 10),
                      _buildTextInput(
                        controller: addressCtrl,
                        label: 'Address',
                        icon: Icons.location_on_outlined,
                        maxLines: 2,
                      ),
                      const SizedBox(height: 10),
                      _buildSelector(
                        label: 'Payment terms',
                        value: paymentTerms,
                        items: const ['Net 15', 'Net 30', 'COD', 'Prepaid'],
                        onChanged: (v) => setSheet(() => paymentTerms = v),
                        icon: Icons.payments_outlined,
                      ),
                      const SizedBox(height: 12),
                      const Text('Categories',
                          style: TextStyle(
                              fontSize: 14,
                              color: Colors.black87,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: availableCategories.map((cat) {
                          final isSelected = supplierCategories.contains(cat);
                          return FilterChip(
                            label: Text(cat),
                            selected: isSelected,
                            onSelected: (selected) {
                              setSheet(() {
                                if (selected) {
                                  supplierCategories.add(cat);
                                } else {
                                  supplierCategories.remove(cat);
                                }
                              });
                            },
                            selectedColor: Colors.deepPurple.shade100,
                            checkmarkColor: Colors.deepPurple,
                            labelStyle: TextStyle(
                              color: isSelected
                                  ? Colors.deepPurple.shade900
                                  : Colors.black87,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(left: 12),
                            child: Icon(Icons.star_outline,
                                size: 20, color: Colors.deepPurple),
                          ),
                          const SizedBox(width: 12),
                          Wrap(
                            spacing: 6,
                            children: List.generate(
                              5,
                              (i) => IconButton(
                                onPressed: () => setSheet(() => rating = i + 1),
                                icon: Icon(
                                  i < rating ? Icons.star : Icons.star_border,
                                  color: Colors.amber,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: SwitchListTile(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          title: const Text('Active',
                              style: TextStyle(fontSize: 14)),
                          value: isActive,
                          onChanged: (v) => setSheet(() => isActive = v),
                          secondary: Icon(Icons.check_circle_outline,
                              color: isActive ? Colors.green : Colors.grey),
                          activeColor: Colors.deepPurple,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _buildTextInput(
                        controller: notesCtrl,
                        label: 'Notes',
                        icon: Icons.notes_outlined,
                        maxLines: 2,
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () async {
                            if (!formKey.currentState!.validate()) return;
                            try {
                              await _service.saveSupplier(
                                supplierId: existing?['id']?.toString(),
                                branchIds: branchIds,
                                data: {
                                  'companyName': companyCtrl.text.trim(),
                                  'contactPerson': contactCtrl.text.trim(),
                                  'phone': phoneCtrl.text.trim(),
                                  'email': emailCtrl.text.trim(),
                                  'address': addressCtrl.text.trim(),
                                  'paymentTerms': paymentTerms,
                                  'notes': notesCtrl.text.trim(),
                                  'ingredientIds': ingredientIds,
                                  'supplierCategories': supplierCategories,
                                  'rating': rating,
                                  'isActive': isActive,
                                },
                              );
                              if (ctx.mounted) Navigator.pop(ctx);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(isEdit
                                        ? 'Supplier updated'
                                        : 'Supplier added'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Save failed: $e'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepPurple,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text(isEdit ? 'Save Changes' : 'Add Supplier'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          });
        },
      );
    } finally {
      companyCtrl.dispose();
      contactCtrl.dispose();
      phoneCtrl.dispose();
      emailCtrl.dispose();
      addressCtrl.dispose();
      notesCtrl.dispose();
    }
  }
}

class _SupplierInlinePurchaseOrders extends StatelessWidget {
  final String supplierId;
  final List<String> branchIds;

  const _SupplierInlinePurchaseOrders({
    required this.supplierId,
    required this.branchIds,
  });

  @override
  Widget build(BuildContext context) {
    final poService = Provider.of<PurchaseOrderService>(context, listen: false);
    final userScope = context.watch<UserScopeService>();
    final isAllBranches = branchIds.length >= userScope.branchIds.length && branchIds.length > 1;

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: poService.streamPurchaseOrders(
        branchIds,
        supplierId: supplierId,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24.0),
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.deepPurple),
            ),
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text('Error loading history: ${snapshot.error}',
                  style: const TextStyle(color: Colors.red, fontSize: 12)),
            ),
          );
        }
        final orders = snapshot.data ?? [];
        if (orders.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.receipt_long_outlined, size: 32, color: Colors.grey),
                  SizedBox(height: 8),
                  Text('No purchase orders found',
                      style: TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ),
            ),
          );
        }

        return Scrollbar(
          thumbVisibility: true,
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: orders.length,
            shrinkWrap: true,
            separatorBuilder: (_, __) => const Divider(height: 16, color: Color(0xFFEEEEEE)),
            itemBuilder: (context, index) {
              final order = orders[index];
              final poNumber = (order['poNumber'] ?? 'Unknown').toString();
              final status = (order['status'] ?? 'draft').toString().toLowerCase();
              final amount = (order['totalAmount'] as num?)?.toDouble() ?? 0.0;
              final date = (order['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
              final orderBranchIds = List<String>.from(order['branchIds'] ?? []);

              Color statusColor;
              switch (status) {
                case 'received': statusColor = Colors.green; break;
                case 'partial': statusColor = Colors.orange; break;
                case 'submitted': statusColor = Colors.blue; break;
                case 'cancelled': statusColor = Colors.red; break;
                default: statusColor = Colors.grey;
              }

              return Row(
                children: [
                   Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.description_outlined, size: 16, color: statusColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          poNumber,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
                        ),
                        Text(
                          DateFormat('MMM dd, yyyy • hh:mm a').format(date),
                          style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                        ),
                        if (isAllBranches && orderBranchIds.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 4,
                            children: orderBranchIds.take(2).map((b) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Branch $b',
                                style: TextStyle(fontSize: 8, color: Colors.blue.shade700, fontWeight: FontWeight.bold),
                              ),
                            )).toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '\$${amount.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: statusColor.withOpacity(0.3)),
                        ),
                        child: Text(
                          status.toUpperCase(),
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
