import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
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
import '../../Models/inventory/supplier.dart';
import '../../Models/inventory/purchase_order.dart';
import '../../services/SinglePurchaseOrderPdfService.dart';
import 'components/purchase_order_table.dart';
import 'components/supplier_quick_grid.dart';
import 'components/purchase_order_filters.dart';

class _InvColors {
  static final Color bgDark = Colors.grey.shade50;
  static const Color surfaceDark = Colors.white;
  static final Color surfaceLighter = Color(0xFFF1F5F9);
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

class _PurchaseOrdersScreenState extends State<PurchaseOrdersScreen> {
  late final PurchaseOrderService _service;
  bool _servicesInitialized = false;
  String _searchQuery = '';
  PurchaseFilterSelection _filters = const PurchaseFilterSelection.all();
  bool _isImportingSuppliers = false;
  List<PurchaseOrder> _latestPurchaseOrders = const [];
 
  UserScopeService get userScope => Provider.of<UserScopeService>(context, listen: false);
  String? _drawerSupplierId;
  String _drawerSupplierName = '';
  String _drawerSupplierEmail = '';
  PurchaseOrder? _editingPo;
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

  void _showSnackBar(String message, {Color backgroundColor = Colors.red}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: backgroundColor),
    );
  }

  void _openPurchaseDrawer({Supplier? supplier, PurchaseOrder? editingPo}) {
    if (editingPo != null) {
      if (editingPo.status == 'received' || editingPo.status == 'partial') {
        _showSnackBar(
          'Warning: Editing a ${editingPo.status.toUpperCase()} order may lead to inventory discrepancies.',
          backgroundColor: Colors.orange,
        );
      }
    }
    setState(() {
      if (editingPo != null) {
        _drawerSupplierId = editingPo.supplierId;
        _drawerSupplierName = editingPo.supplierName;
        _drawerSupplierEmail = '';
        _editingPo = editingPo;
      } else {
        _drawerSupplierId = supplier?.id;
        _drawerSupplierName = supplier?.companyName ?? '';
        _drawerSupplierEmail = supplier?.email ?? '';
        _editingPo = null;
      }
      _drawerSessionKey++;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scaffoldKey.currentState?.openEndDrawer();
    });
  }

  List<PurchaseOrder> _applyOrderFilters(List<PurchaseOrder> orders) {
    final search = _searchQuery.trim().toLowerCase();
    return orders.where((order) {
      if (order.status == 'deleted') return false;
      
      final searchHaystack = [
        order.poNumber,
        order.supplierName,
        order.status,
        order.notes,
        order.createdBy,
      ].map((v) => v.toLowerCase()).join(' ');

      if (search.isNotEmpty && !searchHaystack.contains(search)) return false;
      if (_filters.status != 'all' && order.status != _filters.status) return false;
      if ((_filters.supplierId ?? '').isNotEmpty && order.supplierId != _filters.supplierId) return false;

      if (_filters.dateRange != null) {
        final orderDate = order.orderDate;
        final start = DateTime(_filters.dateRange!.start.year, _filters.dateRange!.start.month, _filters.dateRange!.start.day);
        final end = DateTime(_filters.dateRange!.end.year, _filters.dateRange!.end.month, _filters.dateRange!.end.day, 23, 59, 59);
        if (orderDate.isBefore(start) || orderDate.isAfter(end)) return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
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
          initialSupplierName: _drawerSupplierName,
          initialSupplierEmail: _drawerSupplierEmail,
          editingPo: _editingPo?.toMap(), // Mapping back for compatibility
        ),
      ),
      body: Column(
        children: [
          _buildHeader(branchIds),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                _buildSectionHeader('Active Suppliers', trail: _ViewAllButton(onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const SuppliersScreen()));
                })),
                const SizedBox(height: 16),
                _buildSuppliersGrid(branchIds),
                const SizedBox(height: 40),
                _buildSectionHeader('Purchase Order History', trail: _buildHistoryActions()),
                const SizedBox(height: 16),
                _buildOrdersTable(branchIds),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, {Widget? trail}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _InvColors.textMain)),
        if (trail != null) trail,
      ],
    );
  }

  Widget _buildHistoryActions() {
    return Row(
      children: [
        PurchaseOrderFilters(
          selection: _filters,
          supplierOptions: _buildSupplierFilterOptions(_latestPurchaseOrders),
          onFilterChanged: (newFilters) => setState(() => _filters = newFilters),
        ),
        const SizedBox(width: 12),
        ElevatedButton.icon(
          onPressed: _openExportOptionsDialog,
          icon: const Icon(Icons.file_download_outlined, size: 18),
          label: const Text('Export'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.deepPurple,
            side: const BorderSide(color: Colors.deepPurple, width: 1),
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(List<String> branchIds) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _InvColors.borderDark)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Suppliers & Purchase Orders', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: _InvColors.textMain)),
              SizedBox(height: 4),
              Text('Track inventory orders and manage supplier relationships.', style: TextStyle(color: _InvColors.textMuted)),
            ],
          ),
          Row(
            children: [
              _SearchField(onChanged: (val) => setState(() => _searchQuery = val)),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: () => _openPurchaseDrawer(),
                icon: const Icon(Icons.add),
                label: const Text('New Order'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSuppliersGrid(List<String> branchIds) {
    if (branchIds.isEmpty) return const SizedBox.shrink();
    return StreamBuilder<List<Supplier>>(
      stream: _service.streamSuppliers(branchIds, isActive: true),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        return SupplierQuickGrid(
          suppliers: snapshot.data!,
          onCreatePO: (s) => _openPurchaseDrawer(supplier: s),
          onViewSupplier: (s) => Navigator.push(context, MaterialPageRoute(builder: (_) => SuppliersScreen(initialSearchQuery: s.companyName))),
          onCall: (s) => _launchSupplierCall(s.phone),
          onEmail: (s) => _launchSupplierEmail(s.email),
        );
      },
    );
  }

  Widget _buildOrdersTable(List<String> branchIds) {
    if (branchIds.isEmpty) return _buildNoBranchState('Please select a branch to view orders.');
    return StreamBuilder<List<PurchaseOrder>>(
      stream: _service.streamPurchaseOrders(branchIds),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        _latestPurchaseOrders = snapshot.data!;
        final filtered = _applyOrderFilters(_latestPurchaseOrders);
        return PurchaseOrderTable(
          orders: filtered,
          onEdit: (o) => _openPurchaseDrawer(editingPo: o),
          onReceive: (o) => Navigator.push(context, MaterialPageRoute(builder: (_) => ReceivePurchaseOrderScreen(purchaseOrder: o.toMap()))),
          onDownload: (o) => SinglePurchaseOrderPdfService.downloadPoPdf(o.toMap()),
          onDelete: _confirmDeletePO,
        );
      },
    );
  }

  Widget _buildNoBranchState(String msg) {
    return Center(child: Padding(padding: const EdgeInsets.all(40), child: Text(msg, style: const TextStyle(color: Colors.grey))));
  }

  // --- Actions ---

  Future<void> _confirmDeletePO(PurchaseOrder po) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Order?'),
        content: Text('Delete ${po.poNumber}? This will hide it from active history.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true) {
      await _service.deletePurchaseOrder(id: po.id, userId: userScope.userIdentifier, userName: userScope.userEmail);
      _showSnackBar('Order deleted', backgroundColor: Colors.red);
    }
  }

  void _launchSupplierCall(String phone) {
    if (phone.isEmpty) return _showSnackBar('No phone number available.');
    launchUrl(Uri.parse('tel:$phone'));
  }

  void _launchSupplierEmail(String email) {
    if (email.isEmpty) return _showSnackBar('No email available.');
    launchUrl(Uri.parse('mailto:$email'));
  }

  List<Map<String, String>> _buildSupplierFilterOptions(List<PurchaseOrder> orders) {
    final seen = <String>{};
    final options = <Map<String, String>>[];
    for (final order in orders) {
      if (seen.add(order.supplierId)) options.add({'id': order.supplierId, 'name': order.supplierName});
    }
    return options;
  }

  Future<void> _openExportOptionsDialog() async {
    final filtered = _applyOrderFilters(_latestPurchaseOrders);
    if (filtered.isEmpty) return _showSnackBar('Nothing to export.', backgroundColor: Colors.orange);
    
    final format = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Export Format'),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'csv'), child: const ListTile(leading: Icon(Icons.table_rows), title: Text('CSV'))),
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'excel'), child: const ListTile(leading: Icon(Icons.table_chart), title: Text('Excel'))),
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'pdf'), child: const ListTile(leading: Icon(Icons.picture_as_pdf), title: Text('PDF'))),
        ],
      ),
    );
    if (format != null) await PurchaseOrderExportService.exportOrders(context, orders: filtered, format: format);
  }
}

class _ViewAllButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ViewAllButton({required this.onTap});
  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      label: const Text('View All', style: TextStyle(color: Colors.deepPurple, fontWeight: FontWeight.bold)),
      icon: const Icon(Icons.arrow_forward, size: 16, color: Colors.deepPurple),
    );
  }
}

class _SearchField extends StatelessWidget {
  final ValueChanged<String> onChanged;
  const _SearchField({required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      decoration: BoxDecoration(color: Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
      child: TextField(
        onChanged: onChanged,
        decoration: const InputDecoration(
          hintText: 'Search orders, suppliers...',
          prefixIcon: Icon(Icons.search, size: 20, color: Colors.grey),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }
}
