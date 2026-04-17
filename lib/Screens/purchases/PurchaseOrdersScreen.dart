import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../Widgets/BranchFilterService.dart';
import '../../main.dart';
import '../../services/inventory/PurchaseOrderService.dart';
import '../../services/PurchaseOrderExportService.dart';
import '../../services/inventory/SupplierImportService.dart';
import 'CreatePurchaseOrderScreen.dart';
import 'ReceivePurchaseOrderScreen.dart';
import 'SuppliersScreen.dart';
import 'supplier_import_format_dialog.dart';
import '../../services/SinglePurchaseOrderPdfService.dart';

class _InvColors {
  static final Color bgDark = Colors.grey.shade50;
  static const Color surfaceDark = Colors.white;
  static final Color surfaceLighter = Color(0xFFF1F5F9); // slate-100
  static final Color borderDark = Colors.grey.shade200;
  static final Color primary = Colors.deepPurple;
  static const Color textMain = Color(0xFF1E293B);
  static const Color textMuted = Color(0xFF64748B);
}

class PurchaseOrdersScreen extends StatefulWidget {
  const PurchaseOrdersScreen({super.key});

  @override
  State<PurchaseOrdersScreen> createState() => _PurchaseOrdersScreenState();
}

enum _PurchaseSupplierCardAction {
  createPurchaseOrder,
  viewSupplier,
  call,
  email,
}

class _PurchaseFilterSelection {
  const _PurchaseFilterSelection({
    required this.status,
    required this.supplierId,
    required this.dateRange,
  });

  final String status;
  final String? supplierId;
  final DateTimeRange? dateRange;
}

class _PurchaseOrdersScreenState extends State<PurchaseOrdersScreen> {
  late final PurchaseOrderService _service;
  bool _servicesInitialized = false;
  String _searchQuery = '';
  String _statusFilter = 'all';
  String? _supplierFilterId;
  DateTimeRange? _dateRangeFilter;
  bool _isImportingSuppliers = false;
  List<Map<String, dynamic>> _latestPurchaseOrders = const [];
 
  UserScopeService get userScope => Provider.of<UserScopeService>(context, listen: false);
  String? _drawerSupplierId;
  String _drawerSupplierName = '';
  String _drawerSupplierEmail = '';
  Map<String, dynamic>? _editingPo;
  int _drawerSessionKey = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_servicesInitialized) {
      _servicesInitialized = true;
      _service = Provider.of<PurchaseOrderService>(context, listen: false);
    }
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

  Future<void> _launchExternalUri(
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

  void _openPurchaseDrawer(
      {Map<String, dynamic>? supplier, Map<String, dynamic>? editingPo}) {
    // Add warning if editing a received/partial PO
    if (editingPo != null) {
      final status = (editingPo['status'] ?? '').toString().toLowerCase();
      if (status == 'received' || status == 'partial') {
        _showSnackBar(
            'Warning: Editing a ${status.toUpperCase()} order may lead to inventory discrepancies.',
            backgroundColor: Colors.orange);
      }
    }
    setState(() {
      if (editingPo != null) {
        _drawerSupplierId = (editingPo['supplierId'] ?? '').toString();
        _drawerSupplierName = (editingPo['supplierName'] ?? '').toString();
        _drawerSupplierEmail = ''; // Not always available in PO doc
        _editingPo = editingPo;
      } else {
        _drawerSupplierId = (supplier?['id'] ?? '').toString().trim().isEmpty
            ? null
            : (supplier?['id'] ?? '').toString();
        _drawerSupplierName = (supplier?['companyName'] ?? '').toString();
        _drawerSupplierEmail = (supplier?['email'] ?? '').toString();
        _editingPo = null;
      }
      _drawerSessionKey++;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _scaffoldKey.currentState?.openEndDrawer();
      }
    });
  }

  DateTime? _extractOrderDate(Map<String, dynamic> order) {
    return (order['orderDate'] as Timestamp?)?.toDate() ??
        (order['createdAt'] as Timestamp?)?.toDate();
  }

  List<Map<String, dynamic>> _applyOrderFilters(
    List<Map<String, dynamic>> orders,
  ) {
    final search = _searchQuery.trim().toLowerCase();
    return orders.where((order) {
      final status = (order['status'] ?? '').toString().toLowerCase();
      if (status == 'deleted') return false; // Filter out deleted orders
      final supplierId = (order['supplierId'] ?? '').toString();
      final searchHaystack = [
        order['poNumber'],
        order['supplierName'],
        order['status'],
        order['notes'],
        order['createdBy'],
      ].map((value) => (value ?? '').toString().toLowerCase()).join(' ');

      if (search.isNotEmpty && !searchHaystack.contains(search)) {
        return false;
      }

      if (_statusFilter != 'all' && status != _statusFilter) {
        return false;
      }

      if ((_supplierFilterId ?? '').isNotEmpty &&
          supplierId != _supplierFilterId) {
        return false;
      }

      if (_dateRangeFilter != null) {
        final orderDate = _extractOrderDate(order);
        if (orderDate == null) {
          return false;
        }
        final start = DateTime(
          _dateRangeFilter!.start.year,
          _dateRangeFilter!.start.month,
          _dateRangeFilter!.start.day,
        );
        final end = DateTime(
          _dateRangeFilter!.end.year,
          _dateRangeFilter!.end.month,
          _dateRangeFilter!.end.day,
          23,
          59,
          59,
          999,
        );
        if (orderDate.isBefore(start) || orderDate.isAfter(end)) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  List<Map<String, String>> _buildSupplierFilterOptions(
    List<Map<String, dynamic>> orders,
  ) {
    final seen = <String>{};
    final options = <Map<String, String>>[];
    for (final order in orders) {
      final id = (order['supplierId'] ?? '').toString();
      final name = (order['supplierName'] ?? '').toString().trim();
      if (id.isEmpty || name.isEmpty || !seen.add(id)) {
        continue;
      }
      options.add({'id': id, 'name': name});
    }
    options.sort(
      (left, right) => (left['name'] ?? '').toLowerCase().compareTo(
            (right['name'] ?? '').toLowerCase(),
          ),
    );
    return options;
  }

  Future<void> _openFilterDialog() async {
    final supplierOptions = _buildSupplierFilterOptions(_latestPurchaseOrders);
    var tempStatus = _statusFilter;
    String? tempSupplierId = _supplierFilterId;
    DateTimeRange? tempDateRange = _dateRangeFilter;

    final selection = await showDialog<_PurchaseFilterSelection>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            String selectedSupplierName() {
              final match = supplierOptions.firstWhere(
                (supplier) => supplier['id'] == tempSupplierId,
                orElse: () => const {'name': 'All Suppliers'},
              );
              return match['name'] ?? 'All Suppliers';
            }

            return AlertDialog(
              title: const Text('Filter Purchase Orders'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<String>(
                      value: tempStatus,
                      decoration: const InputDecoration(
                        labelText: 'Status',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                            value: 'all', child: Text('All Statuses')),
                        DropdownMenuItem(value: 'draft', child: Text('Draft')),
                        DropdownMenuItem(
                            value: 'submitted', child: Text('Submitted')),
                        DropdownMenuItem(
                            value: 'partial', child: Text('Partial')),
                        DropdownMenuItem(
                            value: 'received', child: Text('Received')),
                        DropdownMenuItem(
                            value: 'cancelled', child: Text('Cancelled')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => tempStatus = value);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String?>(
                      value: tempSupplierId,
                      decoration: const InputDecoration(
                        labelText: 'Supplier',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('All Suppliers'),
                        ),
                        ...supplierOptions.map(
                          (supplier) => DropdownMenuItem<String?>(
                            value: supplier['id'],
                            child: Text(supplier['name'] ?? ''),
                          ),
                        ),
                      ],
                      onChanged: (value) =>
                          setDialogState(() => tempSupplierId = value),
                    ),
                    const SizedBox(height: 16),
                    InkWell(
                      onTap: () async {
                        final now = DateTime.now();
                        final picked = await showDateRangePicker(
                          context: dialogContext,
                          firstDate: DateTime(now.year - 3),
                          lastDate: DateTime(now.year + 3),
                          initialDateRange: tempDateRange,
                        );
                        if (picked != null) {
                          setDialogState(() => tempDateRange = picked);
                        }
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Order Date Range',
                          border: OutlineInputBorder(),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                tempDateRange == null
                                    ? 'All Dates'
                                    : '${DateFormat('dd MMM yyyy').format(tempDateRange!.start)} - ${DateFormat('dd MMM yyyy').format(tempDateRange!.end)}',
                                style: TextStyle(
                                  color: tempDateRange == null
                                      ? _InvColors.textMuted
                                      : _InvColors.textMain,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.date_range_outlined,
                              color: _InvColors.textMuted,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (tempDateRange != null || tempSupplierId != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: () {
                              setDialogState(() {
                                tempSupplierId = null;
                                tempDateRange = null;
                              });
                            },
                            child: const Text('Clear supplier/date'),
                          ),
                        ),
                      ),
                    if (supplierOptions.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'Supplier options will appear once purchase orders are loaded.',
                          style: TextStyle(
                            fontSize: 12,
                            color: _InvColors.textMuted,
                          ),
                        ),
                      ),
                    if (tempSupplierId != null && tempSupplierId!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Filtering by ${selectedSupplierName()}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: _InvColors.textMuted,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(
                    dialogContext,
                    const _PurchaseFilterSelection(
                      status: 'all',
                      supplierId: null,
                      dateRange: null,
                    ),
                  ),
                  child: const Text('Reset'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(
                    dialogContext,
                    _PurchaseFilterSelection(
                      status: tempStatus,
                      supplierId: tempSupplierId,
                      dateRange: tempDateRange,
                    ),
                  ),
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );

    if (selection == null || !mounted) {
      return;
    }

    setState(() {
      _statusFilter = selection.status;
      _supplierFilterId = selection.supplierId;
      _dateRangeFilter = selection.dateRange;
    });
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
                builder: (_, value, __) => Row(
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
                    Expanded(child: Text(value)),
                  ],
                ),
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
                    .map(
                      (warning) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(warning),
                      ),
                    )
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

  Future<void> _openExportOptionsDialog() async {
    final filteredOrders = _applyOrderFilters(_latestPurchaseOrders);
    if (filteredOrders.isEmpty) {
      _showSnackBar(
        'There are no purchase orders to export.',
        backgroundColor: Colors.orange,
      );
      return;
    }

    final selectedFormat = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Export Purchase Orders',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.table_view, color: Colors.green),
              title: const Text('CSV Format'),
              onTap: () => Navigator.pop(dialogContext, 'csv'),
            ),
            ListTile(
              leading: const Icon(Icons.table_chart, color: Colors.blue),
              title: const Text('Excel Format'),
              onTap: () => Navigator.pop(dialogContext, 'excel'),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
              title: const Text('PDF Format'),
              onTap: () => Navigator.pop(dialogContext, 'pdf'),
            ),
          ],
        ),
      ),
    );

    if (selectedFormat == null || !mounted) {
      return;
    }

    await PurchaseOrderExportService.exportOrders(
      context,
      orders: filteredOrders,
      format: selectedFormat,
    );
  }

  Future<void> _handleSupplierCardAction(
    _PurchaseSupplierCardAction action,
    Map<String, dynamic> supplier,
  ) async {
    switch (action) {
      case _PurchaseSupplierCardAction.createPurchaseOrder:
        _openPurchaseDrawer(supplier: supplier);
        return;
      case _PurchaseSupplierCardAction.viewSupplier:
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SuppliersScreen(
              initialSearchQuery: (supplier['companyName'] ?? '').toString(),
            ),
          ),
        );
        return;
      case _PurchaseSupplierCardAction.call:
        final phone = (supplier['phone'] ?? '').toString().trim();
        if (phone.isEmpty) {
          _showSnackBar('This supplier does not have a phone number.');
          return;
        }
        await _launchExternalUri(
          Uri.parse('tel:$phone'),
          failureMessage: 'Unable to start a call for this supplier.',
        );
        return;
      case _PurchaseSupplierCardAction.email:
        final email = (supplier['email'] ?? '').toString().trim();
        if (email.isEmpty) {
          _showSnackBar('This supplier does not have an email address.');
          return;
        }
        await _launchExternalUri(
          Uri.parse('mailto:$email'),
          failureMessage: 'Unable to open an email app for this supplier.',
        );
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final userScope = context.watch<UserScopeService>();
    final branchFilter = context.watch<BranchFilterService>();
    final branchIds = branchFilter.getFilterBranchIds(userScope.branchIds);

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: _InvColors.bgDark,
      endDrawer: Drawer(
        width: 450,
        child: CreatePurchaseOrderScreen(
          key: ValueKey(_drawerSessionKey),
          isDrawer: true,
          initialSupplierId: _drawerSupplierId,
          initialSupplierName: _drawerSupplierName ?? '',
          initialSupplierEmail: _drawerSupplierEmail ?? '',
          editingPo: _editingPo,
        ),
      ),
      body: Column(
        children: [
          _buildHeader(branchIds),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      // Active Suppliers Section
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Active Suppliers',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: _InvColors.textMain,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const SuppliersScreen(),
                                ),
                              );
                            },
                            icon: const Text('View All',
                                style: TextStyle(
                                    color: Colors.deepPurple,
                                    fontWeight: FontWeight.w500)),
                            label: const Icon(Icons.arrow_forward,
                                size: 16, color: Colors.deepPurple),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildSuppliersGrid(branchIds),
                      const SizedBox(height: 32),

                      // Purchase Order History Section
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Purchase Order History',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: _InvColors.textMain,
                            ),
                          ),
                          Row(
                            children: [
                              _actionButton(
                                icon: Icons.filter_list,
                                label: 'Filter',
                                onTap: _openFilterDialog,
                              ),
                              const SizedBox(width: 8),
                              _actionButton(
                                icon: Icons.download,
                                label: 'Export',
                                onTap: _openExportOptionsDialog,
                              ),
                            ],
                          )
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildOrdersTable(branchIds),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(List<String> branchIds) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: _InvColors.surfaceDark,
        border: Border(bottom: BorderSide(color: _InvColors.borderDark)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Suppliers & Purchase Orders',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: _InvColors.textMain,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Manage supplier relationships and track inventory orders.',
                  style: TextStyle(
                    fontSize: 14,
                    color: _InvColors.textMuted,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Container(
                  width: 260,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _InvColors.surfaceLighter,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _InvColors.borderDark),
                  ),
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search orders...',
                      hintStyle:
                          TextStyle(color: _InvColors.textMuted, fontSize: 13),
                      prefixIcon: Icon(Icons.search,
                          color: _InvColors.textMuted, size: 18),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 12),
                    ),
                    onChanged: (v) =>
                        setState(() => _searchQuery = v.trim().toLowerCase()),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: branchIds.isEmpty || _isImportingSuppliers
                      ? null
                      : () => _showImportGuideAndImport(branchIds),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _InvColors.primary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    side: BorderSide(color: _InvColors.borderDark),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: _isImportingSuppliers
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.upload_file_outlined, size: 18),
                  label: Text(
                    _isImportingSuppliers ? 'Importing...' : 'Import',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () {
                    _openPurchaseDrawer();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _InvColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    elevation: 4,
                    shadowColor: _InvColors.primary.withOpacity(0.4),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('New Purchase Order',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton(
      {required IconData icon,
      required String label,
      required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _InvColors.surfaceDark,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _InvColors.borderDark),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: _InvColors.textMain),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: _InvColors.textMain,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNoBranchState(String message) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _InvColors.surfaceDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _InvColors.borderDark),
      ),
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            color: _InvColors.textMuted,
            height: 1.5,
          ),
        ),
      ),
    );
  }

  Widget _buildSuppliersGrid(List<String> branchIds) {
    if (branchIds.isEmpty) {
      return _buildNoBranchState(
        'Select at least one branch to view or import active suppliers.',
      );
    }

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _service.streamSuppliers(branchIds, isActive: true),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: Padding(
            padding: EdgeInsets.all(20.0),
            child: CircularProgressIndicator(),
          ));
        }
        final suppliers = snapshot.data ?? [];
        if (suppliers.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('No active suppliers found.',
                style: TextStyle(color: _InvColors.textMuted)),
          );
        }
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 350,
            mainAxisExtent: 180,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount:
              suppliers.length > 3 ? 3 : suppliers.length, // Show top 3 or less
          itemBuilder: (context, index) {
            final s = suppliers[index];
            return _supplierCard(s);
          },
        );
      },
    );
  }

  Widget _supplierCard(Map<String, dynamic> data) {
    final companyName = (data['companyName'] ?? 'Unknown').toString();
    final notes = (data['notes'] ?? '').toString();
    final initials =
        companyName.isNotEmpty ? companyName[0].toUpperCase() : '?';
    final phone = (data['phone'] ?? '').toString().trim();
    final email = (data['email'] ?? '').toString().trim();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _InvColors.surfaceDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _InvColors.borderDark),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _InvColors.surfaceLighter,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _InvColors.borderDark),
                ),
                alignment: Alignment.center,
                child: Text(
                  initials,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: _InvColors.textMain,
                  ),
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
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: _InvColors.textMain,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text('Active',
                            style: TextStyle(
                                fontSize: 12, color: _InvColors.textMuted)),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<_PurchaseSupplierCardAction>(
                icon: const Icon(Icons.more_horiz, color: _InvColors.textMuted),
                padding: EdgeInsets.zero,
                tooltip: 'Supplier actions',
                constraints: const BoxConstraints(),
                onSelected: (action) => _handleSupplierCardAction(action, data),
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: _PurchaseSupplierCardAction.createPurchaseOrder,
                    child: Text('Create Purchase Order'),
                  ),
                  const PopupMenuItem(
                    value: _PurchaseSupplierCardAction.viewSupplier,
                    child: Text('View Supplier'),
                  ),
                  PopupMenuItem(
                    value: _PurchaseSupplierCardAction.call,
                    enabled: phone.isNotEmpty,
                    child: const Text('Call Supplier'),
                  ),
                  PopupMenuItem(
                    value: _PurchaseSupplierCardAction.email,
                    enabled: email.isNotEmpty,
                    child: const Text('Email Supplier'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Text(
              notes.isNotEmpty ? notes : 'Primary vendor for goods.',
              style: const TextStyle(
                fontSize: 13,
                color: _InvColors.textMuted,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _contactButton(
                  icon: Icons.call,
                  label: 'Call',
                  onTap: () {
                    if (phone.isEmpty) {
                      _showSnackBar(
                          'This supplier does not have a phone number.');
                      return;
                    }
                    _launchExternalUri(
                      Uri.parse('tel:$phone'),
                      failureMessage:
                          'Unable to start a call for this supplier.',
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _contactButton(
                  icon: Icons.mail_outline,
                  label: 'Email',
                  onTap: () {
                    if (email.isEmpty) {
                      _showSnackBar(
                          'This supplier does not have an email address.');
                      return;
                    }
                    _launchExternalUri(
                      Uri.parse('mailto:$email'),
                      failureMessage:
                          'Unable to open an email app for this supplier.',
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _contactButton(
      {required IconData icon,
      required String label,
      required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: _InvColors.surfaceLighter,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.withOpacity(0.1)),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: _InvColors.textMain),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: _InvColors.textMain,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrdersTable(List<String> branchIds) {
    if (branchIds.isEmpty) {
      _latestPurchaseOrders = const [];
      return _buildNoBranchState(
        'Select at least one branch to view or export purchase orders.',
      );
    }

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _service.streamPurchaseOrders(branchIds),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(20.0),
              child: CircularProgressIndicator(),
            ),
          );
        }
        if (snapshot.hasError) {
          _latestPurchaseOrders = const [];
          return Center(
            child: Text('Failed to load purchase orders: ${snapshot.error}',
                style: const TextStyle(color: Colors.red)),
          );
        }

        _latestPurchaseOrders = snapshot.data ?? [];
        final orders = _applyOrderFilters(_latestPurchaseOrders);

        if (orders.isEmpty) {
          final hasActiveFilters = _searchQuery.isNotEmpty ||
              _statusFilter != 'all' ||
              (_supplierFilterId ?? '').isNotEmpty ||
              _dateRangeFilter != null;
          return Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: _InvColors.surfaceDark,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _InvColors.borderDark),
            ),
            alignment: Alignment.center,
            child: Text(
              hasActiveFilters
                  ? 'No purchase orders match the current filters.'
                  : 'No purchase orders found.',
            ),
          );
        }

        return Container(
          decoration: BoxDecoration(
            color: _InvColors.surfaceDark,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _InvColors.borderDark),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.01),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: _InvColors.surfaceLighter,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  border: Border(bottom: BorderSide(color: _InvColors.borderDark)),
                ),
                child: const Row(
                  children: [
                    Expanded(flex: 2, child: Text('Order ID', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _InvColors.textMuted))),
                    Expanded(flex: 2, child: Text('Supplier', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _InvColors.textMuted))),
                    Expanded(flex: 2, child: Text('Date Created', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _InvColors.textMuted))),
                    Expanded(flex: 1, child: Text('Items', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _InvColors.textMuted))),
                    Expanded(flex: 2, child: Text('Total Cost', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _InvColors.textMuted))),
                    Expanded(flex: 2, child: Text('Status', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _InvColors.textMuted))),
                    Expanded(flex: 1, child: Text('Actions', textAlign: TextAlign.right, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _InvColors.textMuted))),
                  ],
                ),
              ),
              ...orders.map((po) {
                final status = (po['status'] ?? '').toString();
                final normalizedStatus = status.toLowerCase();
                final color = switch (normalizedStatus) {
                  'received' => Colors.green,
                  'partial' => Colors.orange,
                  'submitted' => Colors.blue,
                  'draft' => Colors.grey.shade600,
                  'cancelled' => Colors.red,
                  _ => Colors.grey
                };
                final total = (po['totalAmount'] as num?)?.toDouble() ?? 0.0;
                final orderDate = _extractOrderDate(po);
                final itemsCount = (po['lineItems'] as List?)?.length ?? 0;

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: _InvColors.borderDark)),
                  ),
                  child: Row(
                    children: [
                      Expanded(flex: 2, child: Text((po['poNumber'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _InvColors.textMain))),
                      Expanded(flex: 2, child: Text((po['supplierName'] ?? 'Unknown').toString(), style: const TextStyle(fontSize: 13, color: _InvColors.textMain))),
                      Expanded(flex: 2, child: Text(orderDate?.toLocal().toString().split(' ').first ?? '-', style: const TextStyle(fontSize: 13, color: _InvColors.textMuted))),
                      Expanded(flex: 1, child: Text('$itemsCount Items', style: const TextStyle(fontSize: 13, color: _InvColors.textMuted))),
                      Expanded(flex: 2, child: Text('QAR ${total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _InvColors.textMain))),
                      Expanded(
                        flex: 2,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: color.withOpacity(0.2)),
                            ),
                            child: Text(normalizedStatus.isEmpty ? 'UNKNOWN' : normalizedStatus.toUpperCase(), style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 1,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert, size: 20, color: _InvColors.textMuted),
                            padding: EdgeInsets.zero,
                            tooltip: 'Actions',
                            onSelected: (val) async {
                              final userScope = Provider.of<UserScopeService>(context, listen: false);
                              if (val == 'edit') {
                                _openPurchaseDrawer(editingPo: po);
                              } else if (val == 'delete') {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Delete PO'),
                                    content: const Text('Are you sure you want to PERMANENTLY delete this purchase order? This action cannot be undone.'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
                                      TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes, Delete', style: TextStyle(color: Colors.red))),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  try {
                                    await _service.deletePurchaseOrder(id: po['id'].toString(), userId: userScope.userIdentifier, userName: userScope.userEmail);
                                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PO Marked as Deleted'), backgroundColor: Colors.red));
                                  } catch (e) { _showSnackBar('Unable to delete purchase order: $e'); }
                                }
                              } else if (val == 'receive') {
                                Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => ReceivePurchaseOrderScreen(purchaseOrder: po)));
                              } else if (val == 'cancel') {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Cancel PO'),
                                    content: const Text('Are you sure you want to cancel this purchase order?'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
                                      TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes, Cancel', style: TextStyle(color: Colors.red))),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  try {
                                    await _service.updatePurchaseOrder(id: po['id'].toString(), updates: {'status': 'cancelled'}, userId: userScope.userIdentifier, userName: userScope.userEmail);
                                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PO Cancelled'), backgroundColor: Colors.red));
                                  } catch (e) { _showSnackBar('Unable to cancel purchase order: $e'); }
                                }
                              } else if (val == 'duplicate') {
                                try {
                                  await _service.duplicateAsDraft(po['id'].toString(), userId: userScope.userIdentifier, userName: userScope.userEmail);
                                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Duplicated as Draft'), backgroundColor: Colors.green));
                                } catch (e) { _showSnackBar('Unable to duplicate purchase order: $e'); }
                              } else if (val == 'view_history') {
                                _showPoHistoryDialog(po);
                              } else if (val == 'download_po') {
                                try {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                      content: Text('Generating PDF...'),
                                      backgroundColor: Colors.blue,
                                    ));
                                  }
                                  await SinglePurchaseOrderPdfService.downloadPoPdf(po);
                                } catch (e) {
                                  _showSnackBar('Failed to generate PDF: $e');
                                }
                              }
                            },
                            itemBuilder: (ctx) => [
                              if (normalizedStatus != 'cancelled' && normalizedStatus != 'deleted')
                                const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined, size: 20), title: Text('Edit'), contentPadding: EdgeInsets.zero, dense: true)),
                              if (normalizedStatus == 'submitted' || normalizedStatus == 'partial')
                                const PopupMenuItem(value: 'receive', child: ListTile(leading: Icon(Icons.shopping_cart_checkout, size: 20), title: Text('Receive Items'), contentPadding: EdgeInsets.zero, dense: true)),
                              const PopupMenuItem(value: 'duplicate', child: ListTile(leading: Icon(Icons.copy_outlined, size: 20), title: Text('Duplicate'), contentPadding: EdgeInsets.zero, dense: true)),
                              const PopupMenuItem(value: 'view_history', child: ListTile(leading: Icon(Icons.history_outlined, size: 20), title: Text('View History'), contentPadding: EdgeInsets.zero, dense: true)),
                              const PopupMenuItem(value: 'download_po', child: ListTile(leading: Icon(Icons.download_outlined, size: 20), title: Text('Download LPO'), contentPadding: EdgeInsets.zero, dense: true)),
                              if (normalizedStatus != 'received' && normalizedStatus != 'cancelled')
                                const PopupMenuItem(value: 'cancel', child: ListTile(leading: Icon(Icons.cancel_outlined, size: 20, color: Colors.red), title: Text('Cancel Purchase Order', style: TextStyle(color: Colors.red)), contentPadding: EdgeInsets.zero, dense: true)),
                              if (normalizedStatus != 'deleted')
                                const PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline, size: 20, color: Colors.red), title: Text('Delete Purchase Order', style: TextStyle(color: Colors.red)), contentPadding: EdgeInsets.zero, dense: true)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(color: _InvColors.surfaceLighter.withOpacity(0.5), borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12))),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Showing ${orders.length} orders', style: const TextStyle(fontSize: 12, color: _InvColors.textMuted))]),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showPoHistoryDialog(Map<String, dynamic> po) {
    final history = List<Map<String, dynamic>>.from(po['history'] as List? ?? []);
    history.sort((a, b) {
      final tA = (a['timestamp'] as Timestamp?)?.toDate() ?? DateTime(0);
      final tB = (b['timestamp'] as Timestamp?)?.toDate() ?? DateTime(0);
      return tB.compareTo(tA);
    });

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('PO History', style: TextStyle(color: _InvColors.primary, fontWeight: FontWeight.bold)),
            Text(po['poNumber'] ?? 'Unknown', style: const TextStyle(fontSize: 14, color: _InvColors.textMuted)),
          ],
        ),
        content: SizedBox(
          width: 450,
          child: history.isEmpty
              ? const Padding(padding: EdgeInsets.all(20.0), child: Text('No history logs found for this order.', textAlign: TextAlign.center))
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: history.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final item = history[i];
                    final timestamp = (item['timestamp'] as Timestamp?)?.toDate();
                    final action = (item['action'] ?? '').toString().replaceAll('_', ' ').toUpperCase();
                    final userName = (item['userName'] ?? item['userId'] ?? 'System');

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      leading: CircleAvatar(backgroundColor: _InvColors.primary.withOpacity(0.1), child: Icon(_getHistoryIcon(item['action']), color: _InvColors.primary, size: 18)),
                      title: Text(action, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('By: $userName', style: const TextStyle(fontSize: 12)),
                          if (timestamp != null) Text(DateFormat('dd MMM yyyy, hh:mm a').format(timestamp), style: const TextStyle(fontSize: 11, color: _InvColors.textMuted)),
                        ],
                      ),
                    );
                  },
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  IconData _getHistoryIcon(dynamic action) {
    final act = action.toString().toLowerCase();
    if (act.contains('create')) return Icons.add_circle_outline;
    if (act.contains('update')) return Icons.edit_note;
    if (act.contains('receive')) return Icons.inventory_2_outlined;
    if (act.contains('cancel')) return Icons.cancel_outlined;
    if (act.contains('delete')) return Icons.delete_outline;
    return Icons.history;
  }
}
