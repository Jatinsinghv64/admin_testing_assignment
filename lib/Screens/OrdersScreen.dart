import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:provider/provider.dart';
import 'package:printing/printing.dart';
import 'package:pdf/widgets.dart' as pw;

import '../Widgets/RiderAssignment.dart';
import '../main.dart';

// ✅ HELPER: Convert Device/Server Time -> Restaurant Time (UTC+3 for Qatar)
DateTime getRestaurantTime(DateTime date) {
  // 1. Convert to UTC to remove device timezone bias
  DateTime utc = date.toUtc();
  // 2. Add the Restaurant's Offset (e.g., +3 hours for Qatar/Saudi)
  return utc.add(const Duration(hours: 3));
}

class OrdersScreen extends StatefulWidget {
  final String? initialOrderType;
  final String? initialStatus;
  final String? initialOrderId;

  const OrdersScreen({
    super.key,
    this.initialOrderType,
    this.initialStatus,
    this.initialOrderId,
  });

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;
  String _selectedStatus = 'all';
  late ScrollController _scrollController;

  // Optimization: Cache font to prevent reloading on every print
  static ByteData? _cachedArabicFont;

  // Optimization: Cache branch data to prevent refetching on every print
  static final Map<String, Map<String, dynamic>> _branchCache = {};

  bool _shouldHighlightOrder = false;
  final Set<String> _processingOrderIds = {};

  String? _orderToScrollTo;
  String? _orderToScrollType;
  String? _orderToScrollStatus;

  final Map<String, String> _orderTypeMap = {
    'Delivery': 'delivery',
    'Takeaway': 'takeaway',
    'Pickup': 'pickup',
    'Dine-in': 'dine_in',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController = ScrollController();
    _loadFont(); // Preload font

    final selectedOrder = OrderSelectionService.getSelectedOrder();
    if (selectedOrder['orderId'] != null) {
      _orderToScrollTo = selectedOrder['orderId'];
      _orderToScrollType = selectedOrder['orderType'];
      _orderToScrollStatus = selectedOrder['status'];
      _shouldHighlightOrder = true;

      if (_orderToScrollStatus != null &&
          _getStatusValues().contains(_orderToScrollStatus)) {
        _selectedStatus = _orderToScrollStatus!;
      }
    }

    int initialTabIndex = 0;
    if (widget.initialOrderType != null) {
      final orderTypes = _orderTypeMap.values.toList();
      initialTabIndex = orderTypes.indexOf(widget.initialOrderType!);
      if (initialTabIndex == -1) initialTabIndex = 0;
    } else if (_orderToScrollType != null) {
      final orderTypes = _orderTypeMap.values.toList();
      initialTabIndex = orderTypes.indexOf(_orderToScrollType!);
      if (initialTabIndex == -1) initialTabIndex = 0;
    }

    _tabController = TabController(
      length: _orderTypeMap.length,
      vsync: this,
      initialIndex: initialTabIndex,
    );

    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _shouldHighlightOrder =
              widget.initialOrderId != null || _orderToScrollTo != null;
        });
      }
    });

    _shouldHighlightOrder =
        widget.initialOrderId != null || _orderToScrollTo != null;
  }

  Future<void> _loadFont() async {
    if (_cachedArabicFont == null) {
      try {
        _cachedArabicFont = await rootBundle.load("assets/fonts/NotoSansArabic-Regular.ttf");
      } catch (e) {
        debugPrint("Error pre-loading font: $e");
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    OrderSelectionService.clearSelectedOrder();
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (mounted) setState(() {});
    }
  }

  List<String> _getStatusValues() {
    return [
      'all',
      'pending',
      'preparing',
      'prepared',
      'rider_assigned',
      'pickedUp',
      'delivered',
      'cancelled',
      'needs_rider_assignment',
    ];
  }

  Future<void> updateOrderStatus(String orderId, String newStatus,
      {String? reason}) async {
    if (!mounted) return;

    setState(() {
      _processingOrderIds.add(orderId);
    });

    final db = FirebaseFirestore.instance;
    final orderRef = db.collection('Orders').doc(orderId);

    try {
      if (newStatus == 'cancelled') {
        // ✅ Transaction for Cancellation
        await db.runTransaction((transaction) async {
          final snapshot = await transaction.get(orderRef);
          if (!snapshot.exists) throw Exception("Order does not exist!");

          final data = snapshot.data() as Map<String, dynamic>;
          if (data['status'] == 'delivered') {
            throw Exception("Cannot cancel an order that is already delivered!");
          }

          // 1. Prepare Order Updates
          final Map<String, dynamic> updates = {
            'status': 'cancelled',
            'timestamps.cancelled': FieldValue.serverTimestamp(),
            'riderId': FieldValue.delete(), // Remove rider link
          };

          if (reason != null) updates['cancellationReason'] = reason;
          if (mounted) {
            updates['cancelledBy'] = context.read<UserScopeService>().userEmail;
          }

          transaction.update(orderRef, updates);

          // 2. Handle Rider Cleanup
          final String? riderId = data['riderId'];
          if (riderId != null && riderId.isNotEmpty) {
            final driverRef = db.collection('Drivers').doc(riderId);
            transaction.update(driverRef, {
              'assignedOrderId': '',
              'isAvailable': true,
            });
          }
        });

        await RiderAssignmentService.cancelAutoAssignment(orderId);

      } else {
        // ✅ Standard Batch Update
        final WriteBatch batch = db.batch();
        final Map<String, dynamic> updateData = {
          'status': newStatus,
        };

        if (newStatus == 'prepared') {
          updateData['timestamps.prepared'] = FieldValue.serverTimestamp();
        } else if (newStatus == 'delivered') {
          updateData['timestamps.delivered'] = FieldValue.serverTimestamp();

          // Free up rider (Only if Delivery type)
          final orderDoc = await orderRef.get();
          final data = orderDoc.data() as Map<String, dynamic>? ?? {};
          final String orderType = (data['Order_type'] as String?)?.toLowerCase() ?? '';
          final String? riderId = data['riderId'] as String?;

          if (orderType == 'delivery' && riderId != null && riderId.isNotEmpty) {
            final driverRef = db.collection('Drivers').doc(riderId);
            batch.update(driverRef, {
              'assignedOrderId': '',
              'isAvailable': true,
            });
          }
        } else if (newStatus == 'pickedUp') {
          updateData['timestamps.pickedUp'] = FieldValue.serverTimestamp();
        } else if (newStatus == 'rider_assigned') {
          updateData['timestamps.riderAssigned'] = FieldValue.serverTimestamp();
        }

        batch.update(orderRef, updateData);
        await batch.commit();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Order status updated to "$newStatus"!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _processingOrderIds.remove(orderId);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        centerTitle: true,
        title: const Text(
          'Orders',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.deepPurple,
            fontSize: 24,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: _buildOrderTypeTabs(),
        ),
      ),
      body: Column(
        children: [
          _buildEnhancedStatusFilterBar(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: _orderTypeMap.values.map((orderTypeKey) {
                return _buildOrdersList(orderTypeKey);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderTypeTabs() {
    return Container(
      color: Colors.white,
      child: TabBar(
        controller: _tabController,
        indicatorSize: TabBarIndicatorSize.tab,
        indicatorColor: Colors.deepPurple,
        labelColor: Colors.deepPurple,
        unselectedLabelColor: Colors.grey,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        tabs: _orderTypeMap.keys.map((tabName) {
          return Tab(text: tabName);
        }).toList(),
      ),
    );
  }

  Widget _buildEnhancedStatusFilterBar() {
    return Container(
      margin: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.deepPurple.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.filter_list_rounded,
                    color: Colors.deepPurple,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Filter by Status',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.deepPurple,
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Row(
              children: [
                _buildEnhancedStatusChip('All', 'all', Icons.apps_rounded),
                _buildEnhancedStatusChip(
                    'Placed', 'pending', Icons.schedule_rounded),
                _buildEnhancedStatusChip(
                    'Preparing', 'preparing', Icons.restaurant_rounded),
                _buildEnhancedStatusChip(
                    'Prepared', 'prepared', Icons.done_all_rounded),
                // Only show relevant status chips for Delivery context usually, but keeping all is safer for Admin
                _buildEnhancedStatusChip('Needs Assign',
                    'needs_rider_assignment', Icons.person_pin_circle_outlined),
                _buildEnhancedStatusChip('Rider Assigned', 'rider_assigned',
                    Icons.delivery_dining_rounded),
                _buildEnhancedStatusChip(
                    'Picked Up', 'pickedUp', Icons.local_shipping_rounded),
                _buildEnhancedStatusChip(
                    'Delivered', 'delivered', Icons.check_circle_rounded),
                _buildEnhancedStatusChip(
                    'Cancelled', 'cancelled', Icons.cancel_rounded),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnhancedStatusChip(String label, String value, IconData icon) {
    final bool isSelected = _selectedStatus == value;
    Color chipColor;
    switch (value) {
      case 'pending':
      case 'needs_rider_assignment':
        chipColor = Colors.orange;
        break;
      case 'preparing':
        chipColor = Colors.teal;
        break;
      case 'prepared':
        chipColor = Colors.blueAccent;
        break;
      case 'rider_assigned':
        chipColor = Colors.purple;
        break;
      case 'pickedUp':
        chipColor = Colors.deepPurple;
        break;
      case 'delivered':
        chipColor = Colors.green;
        break;
      case 'cancelled':
        chipColor = Colors.red;
        break;
      default:
        chipColor = Colors.deepPurple;
    }

    return Container(
      margin: const EdgeInsets.only(right: 12),
      child: FilterChip(
        showCheckmark: false,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: const VisualDensity(horizontal: -1, vertical: -2),
        avatar: CircleAvatar(
          radius: 12,
          backgroundColor: isSelected
              ? Colors.white.withOpacity(0.2)
              : chipColor.withOpacity(0.12),
          child: Icon(
            icon,
            size: 14,
            color: isSelected ? Colors.white : chipColor,
          ),
        ),
        labelPadding: const EdgeInsets.symmetric(horizontal: 8),
        label: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : chipColor,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            fontSize: 12,
          ),
        ),
        selected: isSelected,
        onSelected: (selected) {
          setState(() {
            _selectedStatus = selected ? value : 'all';
            _shouldHighlightOrder =
                widget.initialOrderId != null || _orderToScrollTo != null;
          });
        },
        selectedColor: chipColor,
        backgroundColor: chipColor.withOpacity(0.1),
        elevation: isSelected ? 4 : 1,
        shadowColor: chipColor.withOpacity(0.3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(25),
          side: BorderSide(
            color: isSelected ? chipColor : chipColor.withOpacity(0.3),
            width: 1.5,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }

  Widget _buildOrdersList(String orderType) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _getOrdersStream(orderType),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(Colors.deepPurple),
                ),
                const SizedBox(height: 16),
                Text('Loading orders...',
                    style: TextStyle(color: Colors.grey[600])),
              ],
            ),
          );
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.receipt_long_outlined,
                    size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text('No orders found.',
                    style: TextStyle(color: Colors.grey[600], fontSize: 18)),
              ],
            ),
          );
        }

        final docs = snapshot.data!.docs;

        return ListView.separated(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 16),
          itemBuilder: (context, index) {
            final orderDoc = docs[index];
            final isHighlighted = _shouldHighlightOrder &&
                (orderDoc.id == widget.initialOrderId || orderDoc.id == _orderToScrollTo);

            return _OrderCard(
              key: ValueKey(orderDoc.id),
              order: orderDoc,
              orderType: orderType,
              onStatusChange: updateOrderStatus,
              isHighlighted: isHighlighted,
              isProcessing: _processingOrderIds.contains(orderDoc.id),
            );
          },
        );
      },
    );
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _getOrdersStream(
      String orderType) {
    Query<Map<String, dynamic>> baseQuery = FirebaseFirestore.instance
        .collection('Orders')
        .where('Order_type', isEqualTo: orderType);

    final userScope = context.read<UserScopeService>();
    if (!userScope.isSuperAdmin) {
      baseQuery =
          baseQuery.where('branchIds', arrayContains: userScope.branchId);
    }

    if (_selectedStatus == 'all') {
      final now = DateTime.now();
      final startOfToday = DateTime(now.year, now.month, now.day);
      final endOfToday = startOfToday.add(const Duration(days: 1));

      baseQuery = baseQuery
          .where('timestamp', isGreaterThanOrEqualTo: startOfToday)
          .where('timestamp', isLessThan: endOfToday);
    } else {
      baseQuery = baseQuery.where('status', isEqualTo: _selectedStatus);
    }

    return baseQuery.orderBy('timestamp', descending: true).snapshots();
  }
}

class _OrderCard extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> order;
  final String orderType;
  final Function(String, String, {String? reason}) onStatusChange;
  final bool isHighlighted;
  final bool isProcessing;

  const _OrderCard({
    super.key,
    required this.order,
    required this.orderType,
    required this.onStatusChange,
    this.isHighlighted = false,
    this.isProcessing = false,
  });

  @override
  State<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<_OrderCard> {
  bool _isAssigning = false;

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending': return Colors.orange;
      case 'preparing': return Colors.teal;
      case 'prepared': return Colors.blueAccent;
      case 'rider_assigned': return Colors.purple;
      case 'pickedup': return Colors.deepPurple;
      case 'delivered': return Colors.green;
      case 'cancelled': return Colors.red;
      case 'needs_rider_assignment': return Colors.orange;
      default: return Colors.grey;
    }
  }

  Future<void> _handleCancelPress(BuildContext context) async {
    final String? reason = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => const CancellationReasonDialog(),
    );

    if (reason != null && reason.isNotEmpty) {
      widget.onStatusChange(widget.order.id, 'cancelled', reason: reason);
    }
  }

  Future<void> _assignRiderManually(BuildContext context) async {
    final userScope = context.read<UserScopeService>();
    final currentBranchId = userScope.branchId;

    final riderId = await showDialog<String>(
      context: context,
      builder: (context) =>
          _RiderSelectionDialog(currentBranchId: currentBranchId),
    );

    if (riderId != null && riderId.isNotEmpty) {
      setState(() => _isAssigning = true);

      final bool success = await RiderAssignmentService.manualAssignRider(
        orderId: widget.order.id,
        riderId: riderId,
        context: context,
      );

      if (mounted) {
        setState(() => _isAssigning = false);
      }
    }
  }

  Widget _buildActionButtons(BuildContext context, String status) {
    if (widget.isProcessing || _isAssigning) {
      return const SizedBox(
        width: double.infinity,
        height: 50,
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.deepPurple),
              ),
              SizedBox(width: 10),
              Text("Updating...",
                  style: TextStyle(
                      color: Colors.deepPurple, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      );
    }

    final List<Widget> buttons = [];
    final data = widget.order.data();
    final String orderTypeLower = widget.orderType.toLowerCase();

    // ✅ CHECK FOR AUTO ASSIGNMENT (Only visible for Delivery)
    final bool isAutoAssigning = data.containsKey('autoAssignStarted') && orderTypeLower == 'delivery';
    final bool needsManualAssignment = status == 'needs_rider_assignment';

    const EdgeInsets btnPadding = EdgeInsets.symmetric(horizontal: 14, vertical: 10);
    const Size btnMinSize = Size(0, 40);

    // --- BUTTON GENERATION LOGIC ---

    if (status == 'pending') {
      buttons.add(
        ElevatedButton.icon(
          icon: const Icon(Icons.check, size: 16),
          label: const Text('Accept Order'),
          onPressed: () => widget.onStatusChange(widget.order.id, 'preparing'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            padding: btnPadding,
            minimumSize: btnMinSize,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );
    }

    if (status == 'preparing') {
      buttons.add(
        ElevatedButton.icon(
          icon: const Icon(Icons.done_all, size: 16),
          label: const Text('Mark as Prepared'),
          onPressed: () => widget.onStatusChange(widget.order.id, 'prepared'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            padding: btnPadding,
            minimumSize: btnMinSize,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );
    }

    // --- REPRINT RECEIPT (Always available except cancelled) ---
    if (status != 'pending' && status != 'cancelled') {
      buttons.add(
        OutlinedButton.icon(
          icon: const Icon(Icons.print, size: 16),
          label: const Text('Reprint Receipt'),
          onPressed: () async {
            final rootCtx = navigatorKey.currentState?.context ?? context;
            await printReceipt(rootCtx, widget.order);
          },
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.deepPurple,
            side: BorderSide(color: Colors.deepPurple.shade300),
            padding: btnPadding,
            minimumSize: btnMinSize,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );
    }

    // --- NON-DELIVERY LOGIC (Pickup, Takeaway, Dine-in) ---
    // ✅ FIX: Strict separation. No rider assignment code enters here.
    if (orderTypeLower == 'pickup' || orderTypeLower == 'takeaway' || orderTypeLower == 'dine_in') {
      if (status == 'prepared') {
        String label = 'Mark as Completed';
        IconData icon = Icons.task_alt;

        if (orderTypeLower == 'dine_in') {
          label = 'Served to Table';
          icon = Icons.restaurant_menu;
        } else if (orderTypeLower == 'pickup' || orderTypeLower == 'takeaway') {
          label = 'Handed to Customer';
          icon = Icons.local_mall;
        }

        buttons.add(
          ElevatedButton.icon(
            icon: Icon(icon, size: 16),
            label: Text(label),
            // ✅ ACTION: Directly move to 'delivered' (Completed state)
            onPressed: () => widget.onStatusChange(widget.order.id, 'delivered'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
              padding: btnPadding,
              minimumSize: btnMinSize,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        );
      }
    }
    // --- DELIVERY LOGIC ---
    else if (orderTypeLower == 'delivery') {
      final bool canAssign = (status == 'prepared' || status == 'preparing' || needsManualAssignment);

      if (canAssign && !isAutoAssigning) {
        buttons.add(
          ElevatedButton.icon(
            icon: const Icon(Icons.delivery_dining, size: 16),
            label: Text(needsManualAssignment ? 'Assign Manually' : 'Assign Rider'),
            onPressed: () => _assignRiderManually(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: needsManualAssignment ? Colors.orange : Colors.blue,
              foregroundColor: Colors.white,
              padding: btnPadding,
              minimumSize: btnMinSize,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        );
      }

      if (status == 'pickedUp') {
        buttons.add(
          ElevatedButton.icon(
            icon: const Icon(Icons.task_alt, size: 16),
            label: const Text('Mark as Delivered'),
            onPressed: () => widget.onStatusChange(widget.order.id, 'delivered'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
              padding: btnPadding,
              minimumSize: btnMinSize,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        );
      }

      // Auto-assigning UI (Only for Delivery)
      if (isAutoAssigning) {
        buttons.add(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 40),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.blue))),
                      SizedBox(width: 8),
                      Text('Auto-assigning...',
                          style: TextStyle(
                              color: Colors.blue,
                              fontWeight: FontWeight.w600,
                              fontSize: 13)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                icon: const Icon(Icons.stop_circle_outlined, size: 16),
                label: const Text('Override'),
                onPressed: () => _assignRiderManually(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade700,
                  foregroundColor: Colors.white,
                  padding: btnPadding,
                  minimumSize: btnMinSize,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        );
      }
    }

    if (status != 'cancelled' && status != 'delivered') {
      buttons.add(
        ElevatedButton.icon(
          icon: const Icon(Icons.cancel, size: 16),
          label: const Text('Cancel Order'),
          onPressed: () => _handleCancelPress(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            padding: btnPadding,
            minimumSize: btnMinSize,
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: Wrap(
        spacing: 8.0,
        runSpacing: 8.0,
        alignment: WrapAlignment.end,
        children: buttons,
      ),
    );
  }

  // ... helper methods (getStatusDisplayText, etc) ...
  String _getStatusDisplayText(String status) {
    switch (status.toLowerCase()) {
      case 'needs_rider_assignment': return 'NEEDS ASSIGN';
      case 'rider_assigned': return 'RIDER ASSIGNED';
      case 'pickedup': return 'PICKED UP';
      default: return status.toUpperCase();
    }
  }

  double _getStatusFontSize(String status) {
    final displayText = _getStatusDisplayText(status);
    if (displayText.length > 12) return 9;
    if (displayText.length > 8) return 10;
    return 11;
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.deepPurple, size: 18),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.deepPurple)),
      ],
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.deepPurple.shade400),
          const SizedBox(width: 10),
          Expanded(flex: 2, child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
          Expanded(flex: 3, child: Text(value, style: const TextStyle(fontSize: 13, color: Colors.black87))),
        ],
      ),
    );
  }

  Widget _buildItemRow(Map<String, dynamic> item) {
    final String name = item['name'] ?? 'Unnamed Item';
    final int qty = (item['quantity'] as num? ?? 1).toInt();
    final double price = (item['price'] as num? ?? 0.0).toDouble();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            flex: 5,
            child: Text.rich(TextSpan(
                text: name,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                children: [
                  TextSpan(text: ' (x$qty)', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.normal, color: Colors.black54)),
                ])),
          ),
          Expanded(
            flex: 2,
            child: Text('QAR ${(price * qty).toStringAsFixed(2)}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, color: Colors.black)),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, double amount, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: isTotal ? 15 : 13, fontWeight: isTotal ? FontWeight.bold : FontWeight.normal, color: isTotal ? Colors.black : Colors.grey[800])),
          Text('QAR ${amount.toStringAsFixed(2)}', style: TextStyle(fontSize: isTotal ? 15 : 13, fontWeight: isTotal ? FontWeight.bold : FontWeight.normal, color: isTotal ? Colors.black : Colors.grey[800])),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.order.data();
    final items = List<Map<String, dynamic>>.from(data['items'] ?? []);
    final status = data['status']?.toString() ?? 'pending';
    final String orderTypeLower = widget.orderType.toLowerCase();

    // ✅ TIMEZONE FIX: Use helper instead of raw toDate()
    final DateTime? rawTimestamp = (data['timestamp'] as Timestamp?)?.toDate();
    final DateTime? timestamp = rawTimestamp != null ? getRestaurantTime(rawTimestamp) : null;

    final orderNumber = data['dailyOrderNumber']?.toString() ?? widget.order.id.substring(0, 6).toUpperCase();
    final double subtotal = (data['subtotal'] as num? ?? 0.0).toDouble();
    final double deliveryFee = (data['deliveryFee'] as num? ?? 0.0).toDouble();
    final double totalAmount = (data['totalAmount'] as num? ?? 0.0).toDouble();

    // ✅ CHECK FOR AUTO ASSIGNMENT (Only visible for Delivery)
    final bool isAutoAssigning = data.containsKey('autoAssignStarted') && orderTypeLower == 'delivery';
    final bool needsManualAssignment = status == 'needs_rider_assignment';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
          if (widget.isHighlighted)
            BoxShadow(
              color: Colors.blue.withOpacity(0.3),
              blurRadius: 15,
              spreadRadius: 2,
              offset: const Offset(0, 0),
            ),
        ],
        border: widget.isHighlighted
            ? Border.all(color: Colors.blue, width: 2)
            : null,
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          title: Row(
            children: [
              if (widget.isHighlighted)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                      color: Colors.blue, shape: BoxShape.circle),
                  child: const Icon(Icons.arrow_forward,
                      color: Colors.white, size: 12),
                ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _getStatusColor(status).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Stack(
                  children: [
                    Icon(Icons.receipt_long_outlined,
                        color: _getStatusColor(status), size: 20),
                    if (isAutoAssigning)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                              color: Colors.blue,
                              borderRadius: BorderRadius.circular(6)),
                          child: const Icon(Icons.autorenew,
                              color: Colors.white, size: 8),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Order #$orderNumber',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: widget.isHighlighted
                                ? Colors.blue.shade800
                                : Colors.black87)),
                    const SizedBox(height: 4),
                    Text(
                        timestamp != null
                            ? DateFormat('MMM dd, yyyy hh:mm a')
                            .format(timestamp)
                            : 'No date',
                        style: TextStyle(
                            color: widget.isHighlighted
                                ? Colors.blue.shade600
                                : Colors.grey[600],
                            fontSize: 12)),
                    if (isAutoAssigning) ...[
                      const SizedBox(height: 4),
                      const Text('Auto-assigning rider...',
                          style: TextStyle(
                              color: Colors.blue,
                              fontSize: 11,
                              fontWeight: FontWeight.w500)),
                    ],
                    if (needsManualAssignment) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                          border:
                          Border.all(color: Colors.orange.withOpacity(0.3)),
                        ),
                        child: const Text('Needs manual assignment',
                            style: TextStyle(
                                color: Colors.orange,
                                fontSize: 10,
                                fontWeight: FontWeight.w500)),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          trailing: ConstrainedBox(
            constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.3),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: _getStatusColor(status).withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border:
                Border.all(color: _getStatusColor(status).withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _getStatusColor(status))),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(_getStatusDisplayText(status),
                        style: TextStyle(
                            color: _getStatusColor(status),
                            fontWeight: FontWeight.bold,
                            fontSize: _getStatusFontSize(status),
                            overflow: TextOverflow.ellipsis),
                        maxLines: 1),
                  ),
                ],
              ),
            ),
          ),
          children: [
            _buildSectionHeader('Customer Details', Icons.person_outline),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Column(
                children: [
                  if (widget.orderType == 'delivery') ...[
                    _buildDetailRow(Icons.person, 'Customer:', data['customerName'] ?? 'N/A'),
                    _buildDetailRow(Icons.phone, 'Phone:', data['customerPhone'] ?? 'N/A'),
                    _buildDetailRow(Icons.location_on, 'Address:', '${data['deliveryAddress']?['street'] ?? ''}, ${data['deliveryAddress']?['city'] ?? ''}'),
                    if (data['riderId']?.isNotEmpty == true)
                      _buildDetailRow(Icons.delivery_dining, 'Rider:', data['riderId']),
                  ],
                  if (widget.orderType == 'pickup') ...[
                    _buildDetailRow(Icons.store, 'Pickup Branch', data['branchIds']?.join(', ') ?? 'N/A'),
                  ],
                  if (widget.orderType == 'takeaway') ...[
                    _buildDetailRow(Icons.directions_car, 'Car Plate:', (data['carPlateNumber']?.toString().isNotEmpty ?? false) ? data['carPlateNumber'] : 'N/A'),
                    if ((data['specialInstructions']?.toString().isNotEmpty ?? false))
                      _buildDetailRow(Icons.note, 'Instructions:', data['specialInstructions']),
                  ] else if (widget.orderType == 'dine_in') ...[
                    _buildDetailRow(Icons.table_restaurant, 'Table(s):', data['tableNumber'] != null ? (data['tableNumber'] as String) : 'N/A'),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            _buildSectionHeader('Ordered Items', Icons.list_alt),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Column(
                  children: items.map((item) => _buildItemRow(item)).toList()),
            ),
            const SizedBox(height: 20),
            _buildSectionHeader('Order Summary', Icons.summarize),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Column(
                children: [
                  _buildSummaryRow('Subtotal', subtotal),
                  if (deliveryFee > 0)
                    _buildSummaryRow('Delivery Fee', deliveryFee),
                  const Divider(height: 20),
                  _buildSummaryRow('Total Amount', totalAmount, isTotal: true),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _buildSectionHeader('Actions', Icons.touch_app),
            const SizedBox(height: 16),
            _buildActionButtons(context, status),
          ],
        ),
      ),
    );
  }
}

class CancellationReasonDialog extends StatefulWidget {
  const CancellationReasonDialog({super.key});

  @override
  State<CancellationReasonDialog> createState() =>
      _CancellationReasonDialogState();
}

class _CancellationReasonDialogState extends State<CancellationReasonDialog> {
  String? _selectedReason;
  final TextEditingController _otherReasonController = TextEditingController();
  final FocusNode _otherFocusNode = FocusNode();

  final List<String> _reasons = [
    'Customer Request',
    'Out of Stock',
    'Kitchen Busy / Closed',
    'Duplicate Order',
    'Other'
  ];

  @override
  void dispose() {
    _otherReasonController.dispose();
    _otherFocusNode.dispose();
    super.dispose();
  }

  void _onReasonSelected(String? value) {
    setState(() {
      _selectedReason = value;
    });

    if (value == 'Other') {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) FocusScope.of(context).requestFocus(_otherFocusNode);
      });
    } else {
      _otherFocusNode.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isOther = _selectedReason == 'Other';
    final bool isValid = _selectedReason != null &&
        (!isOther || _otherReasonController.text.trim().isNotEmpty);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 5,
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.red.shade700),
                  const SizedBox(width: 12),
                  Text(
                    'Cancel Order?',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.red.shade900),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Please select a reason for cancellation:",
                      style: TextStyle(
                          fontWeight: FontWeight.w500, color: Colors.grey),
                    ),
                    const SizedBox(height: 10),
                    ..._reasons.map((reason) {
                      final bool isSelected = _selectedReason == reason;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: InkWell(
                          onTap: () => _onReasonSelected(reason),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(
                                  color: isSelected
                                      ? Colors.red
                                      : Colors.grey.shade300,
                                  width: isSelected ? 2 : 1),
                              borderRadius: BorderRadius.circular(8),
                              color: isSelected
                                  ? Colors.red.shade50
                                  : Colors.white,
                            ),
                            child: RadioListTile<String>(
                              title: Text(
                                reason,
                                style: TextStyle(
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: isSelected
                                        ? Colors.red.shade900
                                        : Colors.black87),
                              ),
                              value: reason,
                              groupValue: _selectedReason,
                              onChanged: _onReasonSelected,
                              activeColor: Colors.red,
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                    AnimatedCrossFade(
                      firstChild:
                      const SizedBox(width: double.infinity, height: 0),
                      secondChild: Padding(
                        padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
                        child: TextField(
                          controller: _otherReasonController,
                          focusNode: _otherFocusNode,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: 'Specify reason...',
                            hintText: 'e.g. Customer changed mind',
                            filled: true,
                            fillColor: Colors.grey.shade50,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                              const BorderSide(color: Colors.red, width: 2),
                            ),
                          ),
                          maxLines: 2,
                        ),
                      ),
                      crossFadeState: isOther
                          ? CrossFadeState.showSecond
                          : CrossFadeState.showFirst,
                      duration: const Duration(milliseconds: 200),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(null),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        foregroundColor: Colors.grey.shade700,
                      ),
                      child: const Text('Keep Order'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: isValid
                          ? () {
                        String finalReason = _selectedReason!;
                        if (finalReason == 'Other') {
                          finalReason = _otherReasonController.text.trim();
                        }
                        Navigator.of(context).pop(finalReason);
                      }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        disabledBackgroundColor: Colors.red.shade100,
                      ),
                      child: const Text('Confirm Cancel'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> printReceipt(
    BuildContext context, DocumentSnapshot orderDoc) async {
  try {
    // ✅ CRITICAL OPTIMIZATION: Use pre-loaded font
    final fontData = _OrdersScreenState._cachedArabicFont ??
        await rootBundle.load("assets/fonts/NotoSansArabic-Regular.ttf");
    final pw.Font arabicFont = pw.Font.ttf(fontData);

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async {
        final Map<String, dynamic> order =
        Map<String, dynamic>.from(orderDoc.data() as Map);

        final List<dynamic> rawItems = (order['items'] ?? []) as List<dynamic>;
        final List<Map<String, dynamic>> items = rawItems.map((e) {
          final m = Map<String, dynamic>.from(e as Map);
          final name = (m['name'] ?? 'Item').toString();
          final nameAr = (m['name_ar'] ?? '').toString();
          final qtyRaw = m.containsKey('quantity') ? m['quantity'] : m['qty'];
          final qty = int.tryParse(qtyRaw?.toString() ?? '1') ?? 1;
          final priceRaw = m['price'] ?? m['unitPrice'] ?? m['amount'];
          final double price = switch (priceRaw) {
            num n => n.toDouble(),
            _ => double.tryParse(priceRaw?.toString() ?? '0') ?? 0.0,
          };
          return {'name': name, 'name_ar': nameAr, 'qty': qty, 'price': price};
        }).toList();

        final double subtotal = (order['subtotal'] as num?)?.toDouble() ?? 0.0;
        final double discount = (order['discountAmount'] as num?)?.toDouble() ?? 0.0;
        final double totalAmount = (order['totalAmount'] as num?)?.toDouble() ?? 0.0;
        final double calculatedSubtotal = items.fold(0, (sum, item) => sum + (item['price'] * item['qty']));
        final double finalSubtotal = subtotal > 0 ? subtotal : calculatedSubtotal;
        final double riderPaymentAmount = (order['riderPaymentAmount'] as num?)?.toDouble() ?? 0.0;

        // ✅ TIMEZONE FIX: Use helper instead of toDate()
        final DateTime? rawDate = (order['timestamp'] as Timestamp?)?.toDate();
        final DateTime? orderDate = rawDate != null ? getRestaurantTime(rawDate) : null;

        final String formattedDate = orderDate != null
            ? DateFormat('dd/MM/yyyy').format(orderDate)
            : "N/A";
        final String formattedTime = orderDate != null
            ? DateFormat('hh:mm a').format(orderDate)
            : "N/A";

        final String rawOrderType = (order['Order_type'] ?? order['Ordertype'] ?? 'Unknown').toString();
        final String displayOrderType = rawOrderType
            .replaceAll('_', ' ')
            .split(' ')
            .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
            .join(' ');

        final Map<String, String> orderTypeTranslations = {
          'Delivery': 'توصيل',
          'Takeaway': 'سفري',
          'Pickup': 'يستلم',
          'Dine-in': 'تناول الطعام في الداخل',
        };
        final String displayOrderTypeAr = orderTypeTranslations[displayOrderType] ?? displayOrderType;

        final String dailyOrderNumber = order['dailyOrderNumber']?.toString() ??
            orderDoc.id.substring(0, 6).toUpperCase();

        final String customerName = (order['customerName'] ?? 'Walk-in Customer').toString();
        final String carPlate = (order['carPlateNumber'] ?? '').toString();
        final String customerDisplay = rawOrderType.toLowerCase() == 'takeaway' && carPlate.isNotEmpty
            ? 'Car Plate: $carPlate'
            : customerName;
        final String customerDisplayAr = rawOrderType.toLowerCase() == 'takeaway' && carPlate.isNotEmpty
            ? 'لوحة السيارة: $carPlate'
            : (customerName == 'Walk-in Customer' ? 'عميل مباشر' : customerName);

        final List<dynamic> branchIds = order['branchIds'] ?? [];
        String primaryBranchId = branchIds.isNotEmpty ? branchIds.first.toString() : '';

        // ✅ CRITICAL OPTIMIZATION: Cache branch data
        String branchName = "Restaurant Name";
        String branchNameAr = "اسم المطعم";
        String branchPhone = "";
        String branchAddress = "";
        String branchAddressAr = "";
        pw.ImageProvider? branchLogo;

        try {
          if (primaryBranchId.isNotEmpty) {
            Map<String, dynamic>? branchData;

            // Check cache
            if (_OrdersScreenState._branchCache.containsKey(primaryBranchId)) {
              branchData = _OrdersScreenState._branchCache[primaryBranchId];
            } else {
              // Fetch and cache
              final branchSnap = await FirebaseFirestore.instance
                  .collection('Branch')
                  .doc(primaryBranchId)
                  .get();
              if (branchSnap.exists) {
                branchData = branchSnap.data();
                _OrdersScreenState._branchCache[primaryBranchId] = branchData!;
              }
            }

            if (branchData != null) {
              branchName = branchData['name'] ?? "Restaurant Name";
              branchNameAr = branchData['name_ar'] ?? branchName;
              branchPhone = branchData['phone'] ?? "";
              final addressMap = branchData['address'] as Map<String, dynamic>? ?? {};

              final street = addressMap['street'] ?? '';
              final city = addressMap['city'] ?? '';
              branchAddress = (street.isNotEmpty && city.isNotEmpty)
                  ? "$street, $city"
                  : (street + city);

              final streetAr = addressMap['street_ar'] ?? street;
              final cityAr = addressMap['city_ar'] ?? city;
              branchAddressAr = (streetAr.isNotEmpty && cityAr.isNotEmpty)
                  ? "$streetAr, $cityAr"
                  : (streetAr + cityAr);
            }
          }
        } catch (e) {
          debugPrint("Error fetching branch details for receipt: $e");
        }

        final pdf = pw.Document();

        const pw.TextStyle regular = pw.TextStyle(fontSize: 9);
        final pw.TextStyle bold = pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold);
        final pw.TextStyle small = pw.TextStyle(fontSize: 8, color: PdfColors.grey600);
        final pw.TextStyle heading = pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.black);
        final pw.TextStyle total = pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.black);

        final pw.TextStyle arRegular = pw.TextStyle(font: arabicFont, fontSize: 9);
        final pw.TextStyle arBold = pw.TextStyle(font: arabicFont, fontSize: 9, fontWeight: pw.FontWeight.bold);
        final pw.TextStyle arHeading = pw.TextStyle(font: arabicFont, fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.black);
        final pw.TextStyle arTotal = pw.TextStyle(font: arabicFont, fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.black);

        String toArabicNumerals(String number) {
          const en = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '.'];
          const ar = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩', '.'];
          for (int i = 0; i < en.length; i++) {
            number = number.replaceAll(en[i], ar[i]);
          }
          return number;
        }

        pw.Widget buildBilingualLabel(String en, String ar,
            {required pw.TextStyle enStyle,
              required pw.TextStyle arStyle,
              pw.CrossAxisAlignment alignment = pw.CrossAxisAlignment.start}) {
          return pw.Column(
            crossAxisAlignment: alignment,
            children: [
              pw.Text(en, style: enStyle),
              if (ar.isNotEmpty)
                pw.Text(ar,
                    style: arStyle, textDirection: pw.TextDirection.rtl),
            ],
          );
        }

        pw.Widget buildSummaryRow(String en, String ar, double amount,
            {required pw.TextStyle enLabelStyle,
              required pw.TextStyle arLabelStyle,
              required pw.TextStyle enValueStyle,
              required pw.TextStyle arValueStyle,
              PdfColor? valueColor,
              String prefix = ''}) {
          final finalEnValueStyle = valueColor != null
              ? enValueStyle.copyWith(color: valueColor)
              : enValueStyle;
          final finalArValueStyle = valueColor != null
              ? arValueStyle.copyWith(color: valueColor)
              : arValueStyle;

          final String enPrice = '$prefix${amount.toStringAsFixed(2)}';
          final String arPrice =
              '$prefix${toArabicNumerals(amount.toStringAsFixed(2))}';

          return pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(en, style: enLabelStyle),
                    pw.Text(ar,
                        style: arLabelStyle,
                        textDirection: pw.TextDirection.rtl),
                  ]),
              pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('QAR $enPrice',
                        style: finalEnValueStyle,
                        textAlign: pw.TextAlign.right),
                    pw.Text('ر.ق $arPrice',
                        style: finalArValueStyle,
                        textDirection: pw.TextDirection.rtl,
                        textAlign: pw.TextAlign.right),
                  ]),
            ],
          );
        }

        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.roll80,
            build: (_) {
              return pw.Container(
                width: format.availableWidth,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (branchLogo != null)
                      pw.Center(
                        child: pw.Image(branchLogo,
                            height: 60, fit: pw.BoxFit.contain),
                      ),
                    pw.SizedBox(height: 5),
                    pw.Center(child: pw.Text(branchName, style: heading)),
                    pw.Center(
                        child: pw.Text(branchNameAr,
                            style: arHeading,
                            textDirection: pw.TextDirection.rtl)),
                    if (branchAddress.isNotEmpty)
                      pw.Center(
                          child: pw.Text(branchAddress,
                              style: regular, textAlign: pw.TextAlign.center)),
                    if (branchAddressAr.isNotEmpty)
                      pw.Center(
                          child: pw.Text(branchAddressAr,
                              style: arRegular,
                              textDirection: pw.TextDirection.rtl,
                              textAlign: pw.TextAlign.center)),
                    if (branchPhone.isNotEmpty)
                      pw.Center(
                          child: pw.Text("Tel: $branchPhone", style: regular)),
                    pw.SizedBox(height: 5),
                    pw.Center(
                        child: pw.Text("TAX INVOICE",
                            style: bold.copyWith(fontSize: 10))),
                    pw.Center(
                        child: pw.Text("فاتورة ضريبية",
                            style: arBold.copyWith(fontSize: 10),
                            textDirection: pw.TextDirection.rtl)),
                    pw.SizedBox(height: 10),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        buildBilingualLabel('Order #: $dailyOrderNumber',
                            'رقم الطلب: $dailyOrderNumber',
                            enStyle: regular, arStyle: arRegular),
                        buildBilingualLabel(
                            'Type: $displayOrderType', 'نوع: $displayOrderTypeAr',
                            enStyle: bold,
                            arStyle: arBold,
                            alignment: pw.CrossAxisAlignment.end),
                      ],
                    ),
                    pw.SizedBox(height: 3),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        buildBilingualLabel(
                            'Date: $formattedDate', 'تاريخ: $formattedDate',
                            enStyle: regular, arStyle: arRegular),
                        buildBilingualLabel(
                            'Time: $formattedTime', 'زمن: $formattedTime',
                            enStyle: regular,
                            arStyle: arRegular,
                            alignment: pw.CrossAxisAlignment.end),
                      ],
                    ),
                    pw.SizedBox(height: 3),
                    buildBilingualLabel('Customer: $customerDisplay',
                        'عميل: $customerDisplayAr',
                        enStyle: regular, arStyle: arRegular),
                    pw.SizedBox(height: 10),
                    pw.Table(
                      columnWidths: {
                        0: const pw.FlexColumnWidth(5),
                        1: const pw.FlexColumnWidth(1.5),
                        2: const pw.FlexColumnWidth(2.5),
                      },
                      border: const pw.TableBorder(
                        top: pw.BorderSide(color: PdfColors.black, width: 1),
                        bottom:
                        pw.BorderSide(color: PdfColors.black, width: 1),
                        horizontalInside: pw.BorderSide(
                            color: PdfColors.grey300, width: 0.5),
                      ),
                      children: [
                        pw.TableRow(
                          children: [
                            pw.Padding(
                                padding:
                                const pw.EdgeInsets.symmetric(vertical: 4),
                                child: buildBilingualLabel('ITEM', 'بند',
                                    enStyle: bold, arStyle: arBold)),
                            pw.Padding(
                                padding:
                                const pw.EdgeInsets.symmetric(vertical: 4),
                                child: buildBilingualLabel('QTY', 'كمية',
                                    enStyle: bold,
                                    arStyle: arBold,
                                    alignment: pw.CrossAxisAlignment.center)),
                            pw.Padding(
                                padding:
                                const pw.EdgeInsets.symmetric(vertical: 4),
                                child: buildBilingualLabel('TOTAL', 'المجموع',
                                    enStyle: bold,
                                    arStyle: arBold,
                                    alignment: pw.CrossAxisAlignment.end)),
                          ],
                        ),
                        ...items.map((item) {
                          return pw.TableRow(
                            children: [
                              pw.Padding(
                                  padding:
                                  const pw.EdgeInsets.symmetric(vertical: 3),
                                  child: buildBilingualLabel(
                                      item['name'], item['name_ar'],
                                      enStyle: regular, arStyle: arRegular)),
                              pw.Padding(
                                  padding:
                                  const pw.EdgeInsets.symmetric(vertical: 3),
                                  child: pw.Text(item['qty'].toString(),
                                      style: regular,
                                      textAlign: pw.TextAlign.center)),
                              pw.Padding(
                                padding:
                                const pw.EdgeInsets.symmetric(vertical: 3),
                                child: pw.Column(
                                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                                  children: [
                                    pw.Text(
                                        'QAR ${(item['price'] * item['qty']).toStringAsFixed(2)}',
                                        style: regular,
                                        textAlign: pw.TextAlign.right),
                                    pw.Text(
                                        'ر.ق ${toArabicNumerals((item['price'] * item['qty']).toStringAsFixed(2))}',
                                        style: arRegular,
                                        textDirection: pw.TextDirection.rtl,
                                        textAlign: pw.TextAlign.right),
                                  ],
                                ),
                              ),
                            ],
                          );
                        }),
                      ],
                    ),
                    pw.SizedBox(height: 10),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.end,
                      children: [
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                            children: [
                              buildSummaryRow(
                                  'Subtotal:', 'المجموع الفرعي:', finalSubtotal,
                                  enLabelStyle: regular,
                                  arLabelStyle: arRegular,
                                  enValueStyle: bold,
                                  arValueStyle: arBold),
                              if (rawOrderType.toLowerCase() == 'delivery' &&
                                  riderPaymentAmount > 0)
                                buildSummaryRow(
                                    'Rider Payment:',
                                    'أجرة المندوب:',
                                    riderPaymentAmount,
                                    enLabelStyle: regular,
                                    arLabelStyle: arRegular,
                                    enValueStyle: bold,
                                    arValueStyle: arBold,
                                    valueColor: PdfColors.blueGrey),
                              if (discount > 0)
                                buildSummaryRow('Discount:', 'خصم:', discount,
                                    enLabelStyle: regular,
                                    arLabelStyle: arRegular,
                                    enValueStyle: bold,
                                    arValueStyle: arBold,
                                    valueColor: PdfColors.green,
                                    prefix: '- '),
                              pw.Divider(height: 5, color: PdfColors.grey),
                              buildSummaryRow(
                                  'TOTAL:', 'المجموع الكلي:', totalAmount,
                                  enLabelStyle: total,
                                  arLabelStyle: arTotal,
                                  enValueStyle: total,
                                  arValueStyle: arTotal),
                            ],
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 20),
                    pw.Divider(thickness: 1),
                    pw.SizedBox(height: 5),
                    pw.Center(
                        child: pw.Text("Thank You For Your Order!", style: bold)),
                    pw.Center(
                        child: pw.Text("شكرا لطلبك!",
                            style: arBold,
                            textDirection: pw.TextDirection.rtl)),
                    pw.SizedBox(height: 5),
                    pw.Center(
                        child: pw.Text("Invoice ID: ${orderDoc.id}",
                            style: small)),
                  ],
                ),
              );
            },
          ),
        );

        return pdf.save();
      },
    );
  } catch (e, st) {
    debugPrint("Error while printing: $e\n$st");
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to print: $e")),
      );
    }
  }
}

class OrderSelectionService {
  static Map<String, dynamic> _selectedOrder = {};

  static void setSelectedOrder({
    String? orderId,
    String? orderType,
    String? status,
  }) {
    _selectedOrder = {
      'orderId': orderId,
      'orderType': orderType,
      'status': status,
    };
  }

  static Map<String, dynamic> getSelectedOrder() {
    return _selectedOrder;
  }

  static void clearSelectedOrder() {
    _selectedOrder = {};
  }
}

class _RiderSelectionDialog extends StatelessWidget {
  final String? currentBranchId;

  const _RiderSelectionDialog({required this.currentBranchId});

  @override
  Widget build(BuildContext context) {
    Query query = FirebaseFirestore.instance
        .collection('Drivers')
        .where('isAvailable', isEqualTo: true)
        .where('status', isEqualTo: 'online');

    if (currentBranchId != null && currentBranchId!.isNotEmpty) {
      query = query.where('branchIds', arrayContains: currentBranchId);
    }

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.delivery_dining, color: Colors.deepPurple),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Select Available Rider',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: StreamBuilder<QuerySnapshot>(
          stream: query.snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(Colors.deepPurple),
                ),
              );
            }
            if (snapshot.hasError) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
                  const SizedBox(height: 16),
                  Text(
                    'Error loading riders: ${snapshot.error}',
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ],
              );
            }
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.person_off_outlined,
                      size: 48, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  const Text(
                    'No available riders found',
                    style: TextStyle(color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'All riders are currently busy or offline.',
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              );
            }

            final drivers = snapshot.data!.docs;
            return ListView.builder(
              shrinkWrap: true,
              itemCount: drivers.length,
              itemBuilder: (context, index) {
                final driverDoc = drivers[index];
                final data = driverDoc.data() as Map<String, dynamic>;
                final String name = data['name'] ?? 'Unnamed Driver';
                final String phone = data['phone']?.toString() ?? 'No phone';
                final String vehicle = data['vehicle']?['type'] ?? 'No vehicle';

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  elevation: 1,
                  child: ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.deepPurple.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.person,
                        color: Colors.deepPurple,
                      ),
                    ),
                    title: Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(phone),
                        Text(
                          vehicle,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.green,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            'Available',
                            style: TextStyle(
                              color: Colors.green,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    onTap: () {
                      Navigator.of(context).pop(driverDoc.id);
                    },
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}