import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../Widgets/BranchFilterService.dart';
import '../../main.dart';
import '../../services/inventory/InventoryService.dart';
import '../../services/inventory/PurchaseOrderService.dart';
import '../../services/CsvExportService.dart';
import 'CreatePurchaseOrderScreen.dart';
import 'ReceivePurchaseOrderScreen.dart';
import 'SuppliersScreen.dart';

class _InvColors {
  static final Color bgDark       = Colors.grey.shade50;
  static const Color surfaceDark  = Colors.white;
  static final Color surfaceLighter = Color(0xFFF1F5F9); // slate-100
  static final Color borderDark   = Colors.grey.shade200;
  static final Color primary      = Colors.deepPurple;
  static final Color primaryLight = Colors.deepPurple.shade300;
  static const Color textMain     = Color(0xFF1E293B);
  static const Color textMuted    = Color(0xFF64748B);
}

class PurchaseOrdersScreen extends StatefulWidget {
  const PurchaseOrdersScreen({super.key});

  @override
  State<PurchaseOrdersScreen> createState() => _PurchaseOrdersScreenState();
}

class _PurchaseOrdersScreenState extends State<PurchaseOrdersScreen> {
  late final PurchaseOrderService _service;
  late final InventoryService _inventoryService;
  bool _servicesInitialized = false;
  String _searchQuery = '';
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_servicesInitialized) {
      _servicesInitialized = true;
      _service = Provider.of<PurchaseOrderService>(context, listen: false);
      _inventoryService = Provider.of<InventoryService>(context, listen: false);
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
        child: const CreatePurchaseOrderScreen(isDrawer: true),
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
                              Navigator.push(context, MaterialPageRoute(builder: (_) => const SuppliersScreen()));
                            },
                            icon: const Text('View All', style: TextStyle(color: Colors.deepPurple, fontWeight: FontWeight.w500)),
                            label: const Icon(Icons.arrow_forward, size: 16, color: Colors.deepPurple),
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
                                onTap: () {
                                  // Add filter behavior here if needed
                                },
                              ),
                              const SizedBox(width: 8),
                              _actionButton(
                                icon: Icons.download,
                                label: 'Export',
                                onTap: () {
                                  final range = DateTimeRange(
                                    start: DateTime.now().subtract(const Duration(days: 30)),
                                    end: DateTime.now()
                                  );
                                  CsvExportService.exportPurchaseOrders(context, branchIds, range);
                                },
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
                      hintStyle: TextStyle(color: _InvColors.textMuted, fontSize: 13),
                      prefixIcon: Icon(Icons.search, color: _InvColors.textMuted, size: 18),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 12),
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () {
                    _scaffoldKey.currentState?.openEndDrawer();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _InvColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    elevation: 4,
                    shadowColor: _InvColors.primary.withOpacity(0.4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('New Purchase Order', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton({required IconData icon, required String label, required VoidCallback onTap}) {
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

  Widget _buildSuppliersGrid(List<String> branchIds) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _service.streamSuppliers(branchIds, isActive: true),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: Padding(
            padding: EdgeInsets.all(20.0),
            child: CircularProgressIndicator(),
          ));
        }
        final suppliers = snapshot.data ?? [];
        if (suppliers.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('No active suppliers found.', style: TextStyle(color: _InvColors.textMuted)),
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
          itemCount: suppliers.length > 3 ? 3 : suppliers.length, // Show top 3 or less
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
    final initials = companyName.isNotEmpty ? companyName[0].toUpperCase() : '?';

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
                        const Text('Active', style: TextStyle(fontSize: 12, color: _InvColors.textMuted)),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.more_horiz, color: _InvColors.textMuted),
                onPressed: () {},
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
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
                  onTap: () async {
                    final phone = (data['phone'] ?? '').toString().trim();
                    if (phone.isEmpty) return;
                    final uri = Uri.parse('tel:$phone');
                    if (await canLaunchUrl(uri)) await launchUrl(uri);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _contactButton(
                  icon: Icons.mail_outline,
                  label: 'Email',
                  onTap: () async {
                    final email = (data['email'] ?? '').toString().trim();
                    if (email.isEmpty) return;
                    final uri = Uri.parse('mailto:$email');
                    if (await canLaunchUrl(uri)) await launchUrl(uri);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _contactButton({required IconData icon, required String label, required VoidCallback onTap}) {
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
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _service.streamPurchaseOrders(branchIds),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: Padding(
            padding: EdgeInsets.all(20.0),
            child: CircularProgressIndicator(),
          ));
        }
        if (snapshot.hasError) {
          return Center(child: Text('Failed to load purchase orders: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
        }
        
        var orders = snapshot.data ?? [];
        
        // Apply search filter locally
        if (_searchQuery.isNotEmpty) {
          orders = orders.where((po) {
            final poNum = (po['poNumber'] ?? '').toString().toLowerCase();
            final supName = (po['supplierName'] ?? '').toString().toLowerCase();
            return poNum.contains(_searchQuery) || supName.contains(_searchQuery);
          }).toList();
        }

        if (orders.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: _InvColors.surfaceDark,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _InvColors.borderDark),
            ),
            alignment: Alignment.center,
            child: const Text('No purchase orders found.'),
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
              // Header Row
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
              // Body Rows
              ...orders.map((po) {
                final status = (po['status'] ?? '').toString();
                final color = switch (status) {
                  'received' => Colors.green,
                  'partial' => Colors.orange,
                  'submitted' => Colors.blue,
                  'draft' => Colors.grey.shade600,
                  'cancelled' => Colors.red,
                  _ => Colors.grey
                };
                final total = (po['totalAmount'] as num?)?.toDouble() ?? 0.0;
                final orderDate = (po['orderDate'] as Timestamp?)?.toDate();
                final itemsCount = (po['lineItems'] as List?)?.length ?? 0;

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: _InvColors.borderDark)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(
                          (po['poNumber'] ?? '').toString(),
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _InvColors.textMain),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          (po['supplierName'] ?? 'Unknown').toString(),
                          style: const TextStyle(fontSize: 13, color: _InvColors.textMain),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          orderDate?.toLocal().toString().split(' ').first ?? '-',
                          style: const TextStyle(fontSize: 13, color: _InvColors.textMuted),
                        ),
                      ),
                      Expanded(
                        flex: 1,
                        child: Text(
                          '$itemsCount Items',
                          style: const TextStyle(fontSize: 13, color: _InvColors.textMuted),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          'QAR ${total.toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _InvColors.textMain),
                        ),
                      ),
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
                            child: Text(
                              status.toUpperCase(),
                              style: TextStyle(
                                color: color,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 1,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert, size: 20, color: _InvColors.textMuted),
                                padding: EdgeInsets.zero,
                                tooltip: 'Actions',
                                onSelected: (val) async {
                                  if (val == 'receive') {
                                    Navigator.of(context, rootNavigator: true).push(
                                      MaterialPageRoute(
                                        builder: (_) => ReceivePurchaseOrderScreen(purchaseOrder: po),
                                      ),
                                    );
                                  } else if (val == 'cancel') {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('Cancel PO'),
                                        content: const Text('Are you sure you want to cancel this purchase order?'),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
                                          TextButton(
                                            onPressed: () => Navigator.pop(ctx, true), 
                                            child: const Text('Yes, Cancel', style: TextStyle(color: Colors.red)),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm == true) {
                                      try {
                                        await _service.updatePurchaseOrder(id: po['id'].toString(), updates: {'status': 'cancelled'});
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PO Cancelled'), backgroundColor: Colors.red));
                                        }
                                      } catch (e) {
                                        debugPrint('Error cancelling PO: $e');
                                      }
                                    }
                                  } else if (val == 'duplicate') {
                                    try {
                                      await _service.duplicateAsDraft(po['id'].toString());
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Duplicated as Draft'), backgroundColor: Colors.green));
                                      }
                                    } catch (e) {
                                      debugPrint('Error duplicating PO: $e');
                                    }
                                  }
                                },
                                itemBuilder: (ctx) => [
                                  if (status == 'submitted' || status == 'partial')
                                    const PopupMenuItem(value: 'receive', child: Text('Receive Items')),
                                  if (status != 'received' && status != 'cancelled')
                                    const PopupMenuItem(value: 'cancel', child: Text('Cancel Purchase Order')),
                                  const PopupMenuItem(value: 'duplicate', child: Text('Duplicate as Draft')),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
              // Footer
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: _InvColors.surfaceLighter.withOpacity(0.5),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Showing ${orders.length} orders',
                      style: const TextStyle(fontSize: 12, color: _InvColors.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
