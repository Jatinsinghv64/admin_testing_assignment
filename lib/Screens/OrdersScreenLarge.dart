import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';
import '../Widgets/OrderService.dart';
import '../Widgets/BranchFilterService.dart';
import '../Widgets/OrderUIComponents.dart';
import '../Widgets/PrintingService.dart';
import '../Widgets/RiderAssignment.dart';
import '../Widgets/CancellationDialog.dart';
import '../Widgets/TimeUtils.dart';
import '../main.dart';
import '../constants.dart';
import 'pos/pos_payment_dialog.dart';
import '../services/pos/pos_models.dart';
import '../services/pos/pos_service.dart';
import '../utils/responsive_helper.dart';
import '../Widgets/ExportReportDialog.dart';

// ─── Theme Colors ───
const _kPrimary = Colors.deepPurple;
const _kBg = Color(0xFFF8F9FA);

class OrdersScreenLarge extends StatefulWidget {
  final String? initialOrderType;
  final String? initialOrderId;
  const OrdersScreenLarge({super.key, this.initialOrderType, this.initialOrderId});
  @override
  State<OrdersScreenLarge> createState() => _OrdersScreenLargeState();
}

class _OrdersScreenLargeState extends State<OrdersScreenLarge>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _orderTypeMap = {
    'Delivery': 'delivery',
    'Takeaway': 'takeaway',
    'Pickup': 'pickup',
    'Dine-in': 'dine_in',
  };

  String? _selectedOrderId;
  DocumentSnapshot? _selectedOrderDoc;
  String _statusFilter = 'all';
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _orderTypeMap.length, vsync: this);
    if (widget.initialOrderId != null) _selectedOrderId = widget.initialOrderId;
    if (widget.initialOrderType != null) {
      final idx = _orderTypeMap.values.toList().indexOf(widget.initialOrderType!);
      if (idx != -1) _tabController.animateTo(idx);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userScope = context.watch<UserScopeService>();
    final branchFilter = context.watch<BranchFilterService>();
    return Scaffold(
      backgroundColor: _kBg,
      body: Column(
        children: [
          _buildHeader(context, userScope, branchFilter),
          _buildOrderTypeTabs(),
          _buildStatusFilterBar(),
          Expanded(
            child: Row(
              children: [
                // ── Left: Order Table ──
                Expanded(
                  flex: _selectedOrderDoc != null ? 6 : 10,
                  child: TabBarView(
                    controller: _tabController,
                    children: _orderTypeMap.values
                        .map((t) => _buildOrderTable(t, userScope, branchFilter))
                        .toList(),
                  ),
                ),
                // ── Right: Detail Panel ──
                if (_selectedOrderDoc != null)
                  SizedBox(
                    width: 420,
                    child: _OrderDetailPanel(
                      key: ValueKey(_selectedOrderId),
                      order: _selectedOrderDoc!,
                      userScope: userScope,
                      onClose: () => setState(() {
                        _selectedOrderDoc = null;
                        _selectedOrderId = null;
                      }),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Header ───
  Widget _buildHeader(BuildContext ctx, UserScopeService us, BranchFilterService bf) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          const Text('Live Orders',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _kPrimary)),
          const SizedBox(width: 24),
          // Search
          SizedBox(
            width: 320,
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search Order ID, Customer...',
                prefixIcon: Icon(Icons.search, color: Colors.grey.shade400),
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 14),
            ),
          ),
          const Spacer(),
          _buildExportButton(),
        ],
      ),
    );
  }

  Widget _buildExportButton() {
    return ElevatedButton.icon(
      onPressed: () {
        ExportReportDialog.show(context, preSelectedSections: {
          'order_details',
          'sales_summary',
        });
      },
      icon: const Icon(Icons.download_rounded, size: 18),
      label: const Text('Export Report'),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: _kPrimary,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: Colors.grey.shade300),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      ),
    );
  }

  // ─── Order Type Tabs ───
  Widget _buildOrderTypeTabs() {
    return Container(
      color: Colors.white,
      child: TabBar(
        controller: _tabController,
        labelColor: _kPrimary,
        unselectedLabelColor: Colors.grey,
        indicatorColor: _kPrimary,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        tabs: _orderTypeMap.keys.map((t) => Tab(text: t)).toList(),
      ),
    );
  }

  // ─── Status Filter Bar ───
  Widget _buildStatusFilterBar() {
    final statuses = [
      ('All', 'all', Icons.apps),
      ('Pending', AppConstants.statusPending, Icons.schedule),
      ('Preparing', AppConstants.statusPreparing, Icons.restaurant),
      ('Ready', AppConstants.statusPrepared, Icons.check_circle_outline),
      ('Needs Rider', AppConstants.statusNeedsAssignment, Icons.person_pin_circle_outlined),
      ('Rider Assigned', AppConstants.statusRiderAssigned, Icons.delivery_dining),
      ('Picked Up', AppConstants.statusPickedUp, Icons.local_shipping),
      ('Delivered', AppConstants.statusDelivered, Icons.done_all),
      ('Paid', AppConstants.statusPaid, Icons.payments),
      ('Cancelled', AppConstants.statusCancelled, Icons.cancel),
    ];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: statuses.map((s) {
            final isSelected = _statusFilter == s.$2;
            final color = s.$2 == 'all' ? _kPrimary : StatusUtils.getColor(s.$2);
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                showCheckmark: false,
                avatar: Icon(s.$3, size: 14, color: isSelected ? Colors.white : color),
                label: Text(s.$1),
                selected: isSelected,
                selectedColor: color,
                backgroundColor: color.withOpacity(0.08),
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : color,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  fontSize: 12,
                ),
                onSelected: (_) => setState(() => _statusFilter = s.$2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(color: isSelected ? color : color.withOpacity(0.3)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ─── Order Table ───
  Widget _buildOrderTable(
      String orderType, UserScopeService userScope, BranchFilterService branchFilter) {
    final filterBranchIds = branchFilter.getFilterBranchIds(userScope.branchIds);
    return StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      stream: OrderService().getOrdersStreamMerged(
          orderType: orderType,
          status: _statusFilter,
          userScope: userScope,
          filterBranchIds: filterBranchIds),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: _kPrimary));
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey.shade300),
              const SizedBox(height: 16),
              Text('No orders found', style: TextStyle(fontSize: 16, color: Colors.grey.shade500)),
            ]),
          );
        }

        var orders = snapshot.data!;
        // Apply search filter
        if (_searchQuery.isNotEmpty) {
          orders = orders.where((o) {
            final d = o.data();
            final orderNum = (d['dailyOrderNumber'] ?? o.id).toString().toLowerCase();
            final customer = (d['customerName'] ?? '').toString().toLowerCase();
            final phone = (d['customerPhone'] ?? '').toString().toLowerCase();
            return orderNum.contains(_searchQuery) ||
                customer.contains(_searchQuery) ||
                phone.contains(_searchQuery);
          }).toList();
        }

        return Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            children: [
              // Table header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: _kPrimary.withOpacity(0.04),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: const Row(
                  children: [
                    Expanded(flex: 2, child: _ColHeader('ORDER ID')),
                    Expanded(flex: 3, child: _ColHeader('CUSTOMER / TABLE')),
                    Expanded(flex: 2, child: _ColHeader('ORDER TYPE')),
                    Expanded(flex: 2, child: _ColHeader('TOTAL')),
                    Expanded(flex: 2, child: _ColHeader('STATUS')),
                    Expanded(flex: 2, child: _ColHeader('TIME')),
                    SizedBox(width: 32),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Table body
              Expanded(
                child: ListView.separated(
                  itemCount: orders.length,
                  separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade100),
                  itemBuilder: (context, index) {
                    final order = orders[index];
                    final data = order.data();
                    final isSelected = _selectedOrderId == order.id;
                    return _buildOrderRow(order, data, isSelected, orderType);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOrderRow(QueryDocumentSnapshot<Map<String, dynamic>> order,
      Map<String, dynamic> data, bool isSelected, String orderType) {
    final status = data['status'] ?? 'pending';
    final statusColor = StatusUtils.getColor(status);
    final orderNum = OrderNumberHelper.getDisplayNumber(data, orderId: order.id);
    final rawTs = (data['timestamp'] as Timestamp?)?.toDate();
    final ts = rawTs != null ? TimeUtils.getRestaurantTime(rawTs) : null;
    final timeStr = ts != null ? DateFormat('MMM d, hh:mm a').format(ts) : 'N/A';
    final total = (data['totalAmount'] as num? ?? 0).toDouble();
    final customerName = data['customerName']?.toString() ?? 'Guest';
    final customerPhone = data['customerPhone']?.toString() ?? '';
    final tableNumber = data['tableNumber']?.toString() ?? '';
    final displayOrderType = AppConstants.normalizeOrderType(orderType)
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
        .join(' ');

    return InkWell(
      onTap: () => setState(() {
        _selectedOrderId = order.id;
        _selectedOrderDoc = order;
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? _kPrimary.withOpacity(0.05) : null,
          border: isSelected ? const Border(left: BorderSide(color: _kPrimary, width: 3)) : null,
        ),
        child: Row(
          children: [
            Expanded(
                flex: 2,
                child: Text('#$orderNum',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isSelected ? _kPrimary : Colors.black87,
                        fontSize: 13))),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      AppConstants.isDineInOrder(orderType) && tableNumber.isNotEmpty
                          ? 'Table $tableNumber'
                          : customerName,
                      style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  if (customerPhone.isNotEmpty)
                    Text(customerPhone,
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _kPrimary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(displayOrderType,
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600, color: _kPrimary),
                    textAlign: TextAlign.center),
              ),
            ),
            Expanded(
                flex: 2,
                child: Text('${AppConstants.currencySymbol}${total.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, color: _kPrimary, fontSize: 13))),
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: statusColor)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(StatusUtils.getDisplayText(status, orderType: orderType),
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.bold, color: statusColor),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                ]),
              ),
            ),
            Expanded(
                flex: 2,
                child: Text(timeStr,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500))),
            Icon(Icons.chevron_right, size: 20, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}

// ─── Column Header ───
class _ColHeader extends StatelessWidget {
  final String text;
  const _ColHeader(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: TextStyle(
          fontSize: 10, fontWeight: FontWeight.bold, color: _kPrimary.withOpacity(0.6),
          letterSpacing: 1));
}

// ═══════════════════════════════════════════════════════════════
// ORDER DETAIL PANEL (right side)
// ═══════════════════════════════════════════════════════════════
class _OrderDetailPanel extends StatefulWidget {
  final DocumentSnapshot order;
  final UserScopeService userScope;
  final VoidCallback onClose;
  const _OrderDetailPanel(
      {super.key, required this.order, required this.userScope, required this.onClose});
  @override
  State<_OrderDetailPanel> createState() => _OrderDetailPanelState();
}

class _OrderDetailPanelState extends State<_OrderDetailPanel> {
  bool _isLoading = false;
  bool _isProcessingRefund = false;

  Future<void> _processPayment(DocumentSnapshot order, Map<String, dynamic> data) async {
    final branchIds = data['branchIds'] is List 
        ? List<String>.from(data['branchIds']) 
        : [data['branchId']?.toString() ?? ''];
    
    final totalAmount = (data['totalAmount'] as num? ?? 0).toDouble();

    final PosPayment? payment = await showDialog<PosPayment>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PosPaymentDialog(
        totalAmount: 0, // Since we are not adding new items
        existingTableTotal: totalAmount,
        existingOrders: [order],
        branchIds: branchIds,
        returnPaymentOnly: true,
        onPaymentComplete: (orderId) {
          // Note: returnPaymentOnly: true makes the dialog pop with PoSPayment return value
          // so this callback is not strictly required for the logic but required by constructor.
        },
      ),
    );


    if (payment != null && mounted) {
      try {
        setState(() => _isLoading = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Processing payment...'), duration: Duration(seconds: 1)),
        );
        
        final userScope = Provider.of<UserScopeService>(context, listen: false);
        await OrderService().markOrderAsPaidWithPayment(
          context,
          order.id,
          payment,
          currentUserEmail: userScope.userEmail,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Order marked as paid successfully!'), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }

  }

  Future<void> _updateStatus(String newStatus, {String? reason}) async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      await OrderService().updateOrderStatus(context, widget.order.id, newStatus,
          reason: reason, currentUserEmail: widget.userScope.userIdentifier);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Status updated to "${StatusUtils.getDisplayText(newStatus)}"'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 1),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(NetworkUtils.getUserFriendlyError(e)), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleCancelPress() async {
    if (!await NetworkUtils.hasConnectivity()) {
      if (mounted) NetworkUtils.showNetworkError(context);
      return;
    }
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const CancellationReasonDialog(),
    );
    if (reason != null && reason.isNotEmpty) {
      _updateStatus(AppConstants.statusCancelled, reason: reason);
    }
  }

  Future<void> _assignRiderManually() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final data = widget.order.data() as Map<String, dynamic>? ?? {};
    String? branchId;
    if (data['branchIds'] is List && (data['branchIds'] as List).isNotEmpty) {
      branchId = data['branchIds'][0].toString();
    }
    if (branchId == null && widget.userScope.branchIds.isNotEmpty) {
      branchId = widget.userScope.branchIds.first;
    }
    final riderId = await showDialog<String>(
      context: context,
      builder: (_) => _RiderSelectionDialog(currentBranchId: branchId),
    );
    if (riderId != null && riderId.isNotEmpty) {
      setState(() => _isLoading = true);
      final result = await RiderAssignmentService.manualAssignRider(
          orderId: widget.order.id, riderId: riderId);
      if (mounted) {
        setState(() => _isLoading = false);
        scaffoldMessenger.showSnackBar(
            SnackBar(content: Text(result.message), backgroundColor: result.backgroundColor));
      }
    }
  }

  Future<void> _handleRefundAction(bool approved, String? imageUrl) async {
    setState(() => _isProcessingRefund = true);
    try {
      if (imageUrl != null && imageUrl.isNotEmpty) {
        try { await FirebaseStorage.instance.refFromURL(imageUrl).delete(); } catch (_) {}
      }
      final status = approved ? 'accepted' : 'rejected';
      final update = <String, dynamic>{
        'refundRequest.status': status,
        'refundRequest.adminActionAt': FieldValue.serverTimestamp(),
        'refundRequest.imageUrl': null,
      };
      if (approved) {
        update['status'] = 'refunded';
        update['timestamps.refunded'] = FieldValue.serverTimestamp();
      }
      await FirebaseFirestore.instance.collection('Orders').doc(widget.order.id).update(update);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Refund $status'), backgroundColor: approved ? Colors.green : Colors.grey));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isProcessingRefund = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection(AppConstants.collectionOrders)
          .doc(widget.order.id)
          .snapshots(),
      builder: (context, snapshot) {
        final doc = snapshot.data ?? widget.order;
        final data = doc.data() as Map<String, dynamic>? ?? {};
        final status = data['status']?.toString() ?? 'pending';
        final items = List<Map<String, dynamic>>.from(data['items'] ?? []);
        final orderNum =
            OrderNumberHelper.getDisplayNumber(data, orderId: widget.order.id);
        final rawTs = (data['timestamp'] as Timestamp?)?.toDate();
        final ts = rawTs != null ? TimeUtils.getRestaurantTime(rawTs) : null;
        final total = (data['totalAmount'] as num? ?? 0).toDouble();
        final subtotal = (data['subtotal'] as num? ?? 0).toDouble();
        final deliveryFee = (data['riderPaymentAmount'] as num? ??
                data['deliveryFee'] as num? ??
                data['deliveryCharge'] as num? ?? 0)
            .toDouble();
        final orderType = (data['Order_type'] ?? 'delivery').toString();
        final specialInstructions =
            (data['specialInstructions'] ?? '').toString();
        final statusColor = StatusUtils.getColor(status);
        final bool isDelivery = AppConstants.isDeliveryOrder(orderType);
        final bool isDineIn = AppConstants.isDineInOrder(orderType);

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(left: BorderSide(color: Colors.grey.shade200)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(-2, 0))
            ],
          ),
          child: Column(
            children: [
              // ── Panel Header ──
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                    border: Border(
                        bottom: BorderSide(color: Colors.grey.shade200))),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Order #$orderNum',
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                        IconButton(
                            onPressed: widget.onClose,
                            icon:
                                Icon(Icons.close, color: Colors.grey.shade400)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                  shape: BoxShape.circle, color: statusColor)),
                          const SizedBox(width: 6),
                          Text(
                              StatusUtils.getDisplayText(status,
                                  orderType: orderType),
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: statusColor)),
                        ]),
                      ),
                      const Spacer(),
                      if (ts != null)
                        Text(DateFormat('MMM d, hh:mm a').format(ts),
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade500)),
                    ]),
                    const SizedBox(height: 12),
                    // Print KOT + Receipt buttons
                    Row(children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              PrintingService.printKOT(context, doc),
                          icon: const Icon(Icons.print, size: 16),
                          label: const Text('Print KOT',
                              style: TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.bold)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _kPrimary,
                            side: BorderSide(color: _kPrimary.withOpacity(0.3)),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              PrintingService.printReceipt(context, doc),
                          icon: const Icon(Icons.receipt_long, size: 16),
                          label: const Text('Receipt',
                              style: TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.bold)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.grey.shade700,
                            side: BorderSide(color: Colors.grey.shade300),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
              // ── Scrollable Body ──
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Refund Section
                      _buildRefundSection(data),
                      // Customer Info
                      _sectionTitle('Customer Details'),
                      const SizedBox(height: 10),
                      _buildCustomerInfo(data, orderType),
                      const SizedBox(height: 20),
                      // Items
                      _sectionTitle('Itemized Order'),
                      const SizedBox(height: 10),
                      ...items.map((item) => _buildItemRow(item)),
                      const SizedBox(height: 20),
                      // Special Instructions
                      if (specialInstructions.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.05),
                            border: Border.all(
                                color: Colors.orange.withOpacity(0.2)),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.info_outline,
                                    color: Colors.orange, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text('INSTRUCTIONS',
                                            style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.orange)),
                                        const SizedBox(height: 4),
                                        Text('"$specialInstructions"',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey.shade600,
                                                fontStyle: FontStyle.italic)),
                                      ]),
                                ),
                              ]),
                        ),
                        const SizedBox(height: 20),
                      ],
                      // Payment Summary
                      _sectionTitle('Payment Summary'),
                      const SizedBox(height: 10),
                      _summaryRow('Subtotal', subtotal),
                      if (deliveryFee > 0)
                        _summaryRow('Delivery Fee', deliveryFee),
                      Divider(height: 20, color: Colors.grey.shade200),
                      _summaryRow('Total', total, isTotal: true),
                    ],
                  ),
                ),
              ),
              // ── Footer Actions ──
              _buildActionFooter(
                  context, data, status, orderType, isDelivery, isDineIn, total),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionTitle(String t) => Text(t.toUpperCase(),
      style: TextStyle(
          fontSize: 10, fontWeight: FontWeight.bold, color: _kPrimary.withOpacity(0.5),
          letterSpacing: 1.5));

  Widget _summaryRow(String label, double amount, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label,
            style: TextStyle(
                fontSize: isTotal ? 15 : 13,
                fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
                color: isTotal ? Colors.black : Colors.grey.shade600)),
        Text('${AppConstants.currencySymbol}${amount.toStringAsFixed(2)}',
            style: TextStyle(
                fontSize: isTotal ? 15 : 13,
                fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
                color: isTotal ? _kPrimary : Colors.black87)),
      ]),
    );
  }

  Widget _buildCustomerInfo(Map<String, dynamic> data, String orderType) {
    final name = data['customerName']?.toString() ?? 'Guest';
    final phone = data['customerPhone']?.toString() ?? 'N/A';
    final table = data['tableNumber']?.toString() ?? '';
    final carPlate = data['carPlateNumber']?.toString() ?? '';
    String addressText = 'N/A';
    final rawAddr = data['deliveryAddress'];
    if (rawAddr is Map) {
      addressText = '${rawAddr['street'] ?? ''}, ${rawAddr['city'] ?? ''}';
    } else if (rawAddr is String) {
      addressText = rawAddr;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _detailRow(Icons.person, 'Customer', name),
        _detailRow(Icons.phone, 'Phone', phone),
        if (AppConstants.isDineInOrder(orderType) && table.isNotEmpty)
          _detailRow(Icons.table_restaurant, 'Table', table),
        if (AppConstants.isDeliveryOrder(orderType))
          _detailRow(Icons.location_on, 'Address', addressText),
        if (AppConstants.isTakeawayOrder(orderType) && carPlate.isNotEmpty)
          _detailRow(Icons.directions_car, 'Car Plate', carPlate),
        if (data['riderId']?.toString().isNotEmpty == true)
          _detailRow(Icons.delivery_dining, 'Rider', data['riderId'].toString()),
      ]),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Icon(icon, size: 16, color: _kPrimary.withOpacity(0.6)),
        const SizedBox(width: 10),
        SizedBox(width: 80, child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
      ]),
    );
  }

  Widget _buildItemRow(Map<String, dynamic> item) {
    final name = item['name'] ?? 'Item';
    final qty = (item['quantity'] as num? ?? 1).toInt();
    final price = (item['price'] as num? ?? 0).toDouble();
    final discountedPrice = (item['discountedPrice'] as num?)?.toDouble();
    final finalPrice = (item['finalPrice'] as num?)?.toDouble() ?? discountedPrice ?? price;
    final isCombo = item['isCombo'] == true;
    final hasDiscount = discountedPrice != null && discountedPrice < price;
    final subItems = <Map<String, dynamic>>[];
    if (isCombo && item['comboSubItems'] is List) {
      for (final s in item['comboSubItems'] as List) {
        if (s is Map<String, dynamic>) subItems.add(s);
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
            child: item['imageUrl'] != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(item['imageUrl'], fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(Icons.fastfood, color: Colors.grey, size: 20)))
                : const Icon(Icons.fastfood, color: Colors.grey, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                if (isCombo)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                        color: _kPrimary.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                    child: const Text('COMBO',
                        style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: _kPrimary)),
                  ),
                if (hasDiscount)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                    child: const Text('PROMO',
                        style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.green)),
                  ),
                Flexible(child: Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
              ]),
              Text('Qty: $qty', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (hasDiscount)
              Text('${AppConstants.currencySymbol}${(price * qty).toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey, decoration: TextDecoration.lineThrough)),
            Text('${AppConstants.currencySymbol}${(finalPrice * qty).toStringAsFixed(2)}',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                    color: hasDiscount ? Colors.green.shade700 : Colors.black87)),
          ]),
        ]),
        if (subItems.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 52, top: 4),
            child: Column(children: subItems.map((s) {
              final sName = s['name']?.toString() ?? 'Item';
              final sQty = (s['quantity'] as num? ?? 1).toInt();
              return Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(children: [
                  Icon(Icons.subdirectory_arrow_right, size: 14, color: _kPrimary.withOpacity(0.5)),
                  const SizedBox(width: 4),
                  Text(sQty > 1 ? '$sName (x$sQty)' : sName,
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                ]),
              );
            }).toList()),
          ),
      ]),
    );
  }

  Widget _buildRefundSection(Map<String, dynamic> data) {
    final refund = data['refundRequest'] as Map<String, dynamic>?;
    if (refund == null || refund['status'] != 'pending') return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.shade50, borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.shade200)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.money_off, color: Colors.red.shade700, size: 18),
          const SizedBox(width: 8),
          Text('Refund Request',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.red.shade900)),
        ]),
        const SizedBox(height: 8),
        Text('Reason: ${refund['reason'] ?? 'No reason'}',
            style: TextStyle(fontSize: 12, color: Colors.red.shade800)),
        if (refund['imageUrl'] != null && refund['imageUrl'].toString().isNotEmpty) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(refund['imageUrl'], height: 120, width: double.infinity, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(height: 60, color: Colors.grey.shade200,
                    child: const Icon(Icons.broken_image, color: Colors.grey))),
          ),
        ],
        const SizedBox(height: 12),
        if (_isProcessingRefund)
          const Center(child: CircularProgressIndicator(strokeWidth: 2))
        else
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _handleRefundAction(false, refund['imageUrl']),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.grey.shade700),
                child: const Text('Reject', style: TextStyle(fontSize: 12)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: () => _handleRefundAction(true, refund['imageUrl']),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                child: const Text('Approve', style: TextStyle(fontSize: 12)),
              ),
            ),
          ]),
      ]),
    );
  }

  // ─── Action Footer ───
  Widget _buildActionFooter(BuildContext context, Map<String, dynamic> data, String status,
      String orderType, bool isDelivery, bool isDineIn, double total) {
    final isPickup = AppConstants.normalizeOrderType(orderType) == AppConstants.orderTypePickup;
    final isTakeaway = AppConstants.normalizeOrderType(orderType) == AppConstants.orderTypeTakeaway;
    final riderId = data['riderId']?.toString() ?? '';
    final isAutoAssigning = data.containsKey('autoAssignStarted') && isDelivery;
    final needsManualAssignment = status == AppConstants.statusNeedsAssignment;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kPrimary.withOpacity(0.03),
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Total Payable', style: TextStyle(fontSize: 13, color: _kPrimary.withOpacity(0.6))),
          Text('${AppConstants.currencySymbol}${total.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 12),
        if (_isLoading)
          const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(color: _kPrimary, strokeWidth: 2)))
        else
          _buildActionButtons(data, status, isDelivery, isDineIn, isPickup, isTakeaway, riderId, isAutoAssigning, needsManualAssignment),
      ]),
    );
  }

  Widget _buildActionButtons(Map<String, dynamic> data, String status, bool isDelivery, bool isDineIn, bool isPickup,
      bool isTakeaway, String riderId, bool isAutoAssigning, bool needsManualAssignment) {

    final List<Widget> buttons = [];

    // Accept Order
    if (status == AppConstants.statusPending) {
      buttons.add(_actionBtn('Accept Order', Icons.check_circle, _kPrimary, () async {
        await _updateStatus(AppConstants.statusPreparing);
        if (isDelivery) await RiderAssignmentService.autoAssignRider(orderId: widget.order.id);
      }));
    }

    // Non-delivery flows
    if (!isDelivery) {
      if (status == AppConstants.statusPreparing) {
        buttons.add(_actionBtn('Mark Prepared', Icons.check_circle_outline, Colors.teal.shade600,
            () => _updateStatus(AppConstants.statusPrepared)));
      }
      if (status == AppConstants.statusPrepared) {
        if (isDineIn) {
          buttons.add(_actionBtn('Mark Served', Icons.restaurant_menu, Colors.green.shade600,
              () => _updateStatus(AppConstants.statusServed)));
        } else if (isPickup) {
          buttons.add(_actionBtn('Collected', Icons.shopping_bag_outlined, Colors.green.shade700,
              () => _updateStatus(AppConstants.statusCollected)));
        } else if (isTakeaway) {
          final isPaidStatus = status == AppConstants.statusPaid || status == AppConstants.statusCollected;
          final needsRobustPayment = (isDineIn || isTakeaway) && !isPaidStatus;

          buttons.add(_actionBtn('Mark Paid', Icons.payments, Colors.blue.shade700, () {
            if (needsRobustPayment) {
              _processPayment(widget.order, data);
            } else {
              _updateStatus(AppConstants.statusPaid);
            }
          }));
        }
      }
      if (status == AppConstants.statusServed && isDineIn) {
        buttons.add(_actionBtn('Mark Paid', Icons.payments, Colors.blue.shade700, () {
          _processPayment(widget.order, data);
        }));
      }

      if (needsManualAssignment) {
        buttons.add(_actionBtn(
            isDineIn ? 'Mark Served' : (isPickup ? 'Collected' : 'Mark Paid'),
            isDineIn ? Icons.restaurant_menu : Icons.local_mall,
            Colors.green.shade700,
            () => _updateStatus(isDineIn
                ? AppConstants.statusServed
                : (isPickup ? AppConstants.statusCollected : AppConstants.statusPaid))));
      }
    }

    // Delivery flows
    if (isDelivery && !ResponsiveHelper.isMobile(context)) {
      if ((status == AppConstants.statusPreparing || needsManualAssignment) &&
          !isAutoAssigning && (riderId.isEmpty)) {
        buttons.add(_actionBtn('Assign Driver', Icons.person_add, _kPrimary, _assignRiderManually));
      }
      if (status == AppConstants.statusRiderAssigned) {
        buttons.add(_actionBtn('Mark Picked Up', Icons.local_shipping, Colors.indigo,
            () => _updateStatus(AppConstants.statusPickedUp)));
      }
      if (status == AppConstants.statusPickedUp) {
        buttons.add(_actionBtn('Mark Delivered', Icons.done_all, Colors.green.shade700,
            () => _updateStatus(AppConstants.statusDelivered)));
      }
      if (isAutoAssigning) {
        buttons.add(Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(width: 14, height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.blue))),
            const SizedBox(width: 8),
            const Text('Auto-assigning...', style: TextStyle(color: Colors.blue, fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
        ));
      }
    }

    // Cancel (for non-terminal statuses)
    if (status != AppConstants.statusCancelled &&
        status != AppConstants.statusDelivered &&
        status != AppConstants.statusPaid &&
        status != AppConstants.statusCollected &&
        status != 'refunded') {
      buttons.add(SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _handleCancelPress,
          icon: const Icon(Icons.cancel, size: 16),
          label: const Text('Cancel Order'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.red,
            side: const BorderSide(color: Colors.red),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ));
    }

    return Wrap(spacing: 8, runSpacing: 8, children: buttons);
  }

  Widget _actionBtn(String label, IconData icon, Color color, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          elevation: 0,
        ),
      ),
    );
  }
}

// ─── Rider Selection Dialog (reused from mobile) ───
class _RiderSelectionDialog extends StatelessWidget {
  final String? currentBranchId;
  const _RiderSelectionDialog({required this.currentBranchId});

  @override
  Widget build(BuildContext context) {
    Query query = FirebaseFirestore.instance
        .collection(AppConstants.collectionStaff).where('staffType', isEqualTo: 'driver')
        .where('isAvailable', isEqualTo: true)
        .where('status', isEqualTo: 'online');
    if (currentBranchId != null && currentBranchId!.isNotEmpty) {
      query = query.where('branchIds', arrayContains: currentBranchId);
    }
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(children: [
        Icon(Icons.delivery_dining, color: _kPrimary),
        SizedBox(width: 8),
        Expanded(child: Text('Select Available Rider', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
      ]),
      content: SizedBox(
        width: double.maxFinite,
        child: StreamBuilder<QuerySnapshot>(
          stream: query.snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: _kPrimary));
            }
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.person_off_outlined, size: 48, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                const Text('No available riders found', style: TextStyle(color: Colors.grey)),
              ]);
            }
            final drivers = snapshot.data!.docs;
            return ListView.builder(
              shrinkWrap: true,
              itemCount: drivers.length,
              itemBuilder: (context, index) {
                final d = drivers[index].data() as Map<String, dynamic>;
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    leading: CircleAvatar(backgroundColor: _kPrimary.withOpacity(0.1),
                        child: const Icon(Icons.person, color: _kPrimary)),
                    title: Text(d['name'] ?? 'Unnamed', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(d['phone']?.toString() ?? ''),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                      child: const Text('Available',
                          style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                    onTap: () => Navigator.pop(context, drivers[index].id),
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
    );
  }
}
