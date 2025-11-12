import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
// import 'package:flutter/material.dart' as pw;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:provider/provider.dart';
import '../Widgets/RiderAssignment.dart';
import '../Widgets/ScopeLoader.dart';
import '../main.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Main screen for viewing and managing orders.
/// Filters orders based on the user's role (super_admin vs. branch_admin)
/// and the selected order type/status.
///
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();


/// Main screen for viewing and managing orders.
/// Filters orders based on the user's role (super_admin vs. branch_admin)
/// and the selected order type/status.

/// Main screen for viewing and managing orders.
/// Filters orders based on the user's role (super_admin vs. branch_admin)
/// and the selected order type/status.
class OrdersScreen extends StatefulWidget {
  final String? initialOrderType;
  final String? initialStatus;
  final String? initialOrderId; // The ID of the order to scroll to/highlight

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
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedStatus = 'all';
  late ScrollController _scrollController;
  final Map<String, GlobalKey> _orderKeys = {};
  bool _shouldScrollToOrder = false;

  // Add this to track if we need to scroll to a specific order from dashboard
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
    _scrollController = ScrollController();

    // Check if there's a selected order from dashboard
    final selectedOrder = OrderSelectionService.getSelectedOrder();
    if (selectedOrder['orderId'] != null) {
      _orderToScrollTo = selectedOrder['orderId'];
      _orderToScrollType = selectedOrder['orderType'];
      _orderToScrollStatus = selectedOrder['status'];
      _shouldScrollToOrder = true;

      // Set initial status filter based on order from dashboard
      if (_orderToScrollStatus != null && _getStatusValues().contains(_orderToScrollStatus)) {
        _selectedStatus = _orderToScrollStatus!;
      }
    }

    // Initialize tab controller based on widget parameters or dashboard selection
    int initialTabIndex = 0;
    if (widget.initialOrderType != null) {
      final orderTypes = _orderTypeMap.values.toList();
      initialTabIndex = orderTypes.indexOf(widget.initialOrderType!);
      if (initialTabIndex == -1) initialTabIndex = 0;
    } else if (_orderToScrollType != null) {
      // Use order type from dashboard selection
      final orderTypes = _orderTypeMap.values.toList();
      initialTabIndex = orderTypes.indexOf(_orderToScrollType!);
      if (initialTabIndex == -1) initialTabIndex = 0;
    }

    _tabController = TabController(
      length: _orderTypeMap.length,
      vsync: this,
      initialIndex: initialTabIndex,
    );

    // Add listener to reset scroll flag when tab changes
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _shouldScrollToOrder = widget.initialOrderId != null || _orderToScrollTo != null;
        });
      }
    });

    // Set shouldScrollToOrder flag if an initial order ID is provided or from dashboard
    _shouldScrollToOrder = widget.initialOrderId != null || _orderToScrollTo != null;
  }

  @override
  void dispose() {
    // Clear the selected order when leaving OrdersScreen
    OrderSelectionService.clearSelectedOrder();
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // Helper to get all valid status values
  List<String> _getStatusValues() {
    return [
      'all',
      'pending',
      'preparing',
      'prepared',
      'rider_assigned',
      'pickedUp',
      'delivered',
      'cancelled'
    ];
  }

  // Method to update order status in Firestore
  Future<void> updateOrderStatus(
      BuildContext context, String orderId, String newStatus) async {
    try {
      final Map<String, dynamic> updateData = {
        'status': newStatus,
      };

      if (newStatus == 'prepared') {
        updateData['timestamps.prepared'] = FieldValue.serverTimestamp();
      } else if (newStatus == 'delivered') {
        updateData['timestamps.delivered'] = FieldValue.serverTimestamp();
        // Safe rider cleanup only for delivery orders with riderId present
        final orderDoc = await FirebaseFirestore.instance
            .collection('Orders')
            .doc(orderId)
            .get();
        final data = orderDoc.data() as Map<String, dynamic>? ?? {};
        final String orderType =
            (data['Order_type'] as String?)?.toLowerCase() ?? '';
        final String? riderId =
        data.containsKey('riderId') ? data['riderId'] as String? : null;

        if (orderType == 'delivery' && riderId != null && riderId.isNotEmpty) {
          await FirebaseFirestore.instance
              .collection('Drivers')
              .doc(riderId)
              .update({
            'assignedOrderId': '',
            'isAvailable': true,
          });
        }
      } else if (newStatus == 'cancelled') {
        updateData['timestamps.cancelled'] = FieldValue.serverTimestamp();

        // IMPORTANT FIX: Cancel auto-assignment when order is cancelled
        await RiderAssignmentService.cancelAutoAssignment(orderId);

        // Also cleanup any rider assignment if exists
        final orderDoc = await FirebaseFirestore.instance
            .collection('Orders')
            .doc(orderId)
            .get();
        final data = orderDoc.data() as Map<String, dynamic>? ?? {};
        final String? riderId = data['riderId'] as String?;

        if (riderId != null && riderId.isNotEmpty) {
          // Free up the rider
          await FirebaseFirestore.instance
              .collection('Drivers')
              .doc(riderId)
              .update({
            'assignedOrderId': '',
            'isAvailable': true,
          });

          // Remove rider from order
          updateData['riderId'] = FieldValue.delete();
        }
      } else if (newStatus == 'pickedUp') {
        updateData['timestamps.pickedUp'] = FieldValue.serverTimestamp();
      } else if (newStatus == 'rider_assigned') {
        updateData['timestamps.riderAssigned'] = FieldValue.serverTimestamp();
      }

      await FirebaseFirestore.instance
          .collection('Orders')
          .doc(orderId)
          .update(updateData);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Order $orderId status updated to "$newStatus"!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update order status: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Method to assign rider
  Future<void> _assignRider(BuildContext context, String orderId) async {
    final userScope = context.read<UserScopeService>();
    final currentBranchId = userScope.branchId;

    final rider = await showDialog<String>(
      context: context,
      builder: (context) => _RiderSelectionDialog(currentBranchId: currentBranchId),
    );

    if (rider != null && rider.isNotEmpty) {
      try {
        final updateMap = {
          'status': 'rider_assigned',
          'riderId': rider,
          'timestamps.riderAssigned': FieldValue.serverTimestamp(),
          'timestamp': FieldValue.serverTimestamp(),
        };

        await FirebaseFirestore.instance
            .collection('Orders')
            .doc(orderId)
            .update(updateMap);

        await FirebaseFirestore.instance
            .collection('Drivers')
            .doc(rider)
            .update({'assignedOrderId': orderId, 'isAvailable': false});

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Rider assigned to order $orderId.'),
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to assign rider: $e'),
            backgroundColor: Colors.red,
          ),
        );
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
          // Header
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
                  child: Icon(
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
          // Filter chips
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
    // Keep your existing color mapping
    Color chipColor;
    switch (value) {
      case 'pending':
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
            _shouldScrollToOrder = widget.initialOrderId != null || _orderToScrollTo != null;
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
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(Colors.deepPurple),
                ),
                const SizedBox(height: 16),
                Text(
                  'Loading orders...',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                const SizedBox(height: 16),
                Text(
                  'Error: ${snapshot.error}',
                  style: const TextStyle(color: Colors.red, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.receipt_long_outlined,
                    size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No orders found.',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Orders will appear here when placed.',
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          );
        }

        final docs = snapshot.data!.docs;

        // Populate GlobalKeys and attempt to scroll if needed
        // First check for widget.initialOrderId (direct navigation)
        if (widget.initialOrderId != null && _shouldScrollToOrder) {
          _orderKeys.clear();
          for (var doc in docs) {
            _orderKeys[doc.id] = GlobalKey();
          }

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_shouldScrollToOrder) {
              final key = _orderKeys[widget.initialOrderId!];
              if (key != null && key.currentContext != null) {
                Scrollable.ensureVisible(
                  key.currentContext!,
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeInOut,
                  alignment: 0.1,
                );
                setState(() {
                  _shouldScrollToOrder = false;
                });
              }
            }
          });
        }

        // THEN check for _orderToScrollTo (from dashboard)
        if (_orderToScrollTo != null && _shouldScrollToOrder) {
          _orderKeys.clear();
          for (var doc in docs) {
            _orderKeys[doc.id] = GlobalKey();
          }

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_shouldScrollToOrder && _orderToScrollTo != null) {
              final key = _orderKeys[_orderToScrollTo!];
              if (key != null && key.currentContext != null) {
                Scrollable.ensureVisible(
                  key.currentContext!,
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeInOut,
                  alignment: 0.1,
                );
                setState(() {
                  _shouldScrollToOrder = false;
                  _orderToScrollTo = null; // Clear after scrolling
                });
              }
            }
          });
        }

        return ListView.separated(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 16),
          itemBuilder: (context, index) {
            final orderDoc = docs[index];
            final isHighlighted = orderDoc.id == widget.initialOrderId ||
                orderDoc.id == _orderToScrollTo;

            return _OrderCard(
              key: _orderKeys[orderDoc.id],
              order: orderDoc,
              orderType: orderType,
              onStatusChange: updateOrderStatus,
              onAssigned: _assignRider,
              isHighlighted: isHighlighted,
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

    // Apply branch filter for non-super admin users
    final userScope = context.read<UserScopeService>();
    if (!userScope.isSuperAdmin) {
      baseQuery = baseQuery.where('branchIds', arrayContains: userScope.branchId);
    }

    // Apply current day filtering for 'all' status
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

class _OrderCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> order;
  final String orderType;
  final Function(BuildContext, String, String) onStatusChange;
  final Function(BuildContext, String) onAssigned;
  final bool isHighlighted;

  const _OrderCard({
    super.key,
    required this.order,
    required this.orderType,
    required this.onStatusChange,
    required this.onAssigned,
    this.isHighlighted = false,
  });

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange;
      case 'preparing':
        return Colors.teal;
      case 'prepared':
        return Colors.blueAccent;
      case 'rider_assigned':
        return Colors.purple;
      case 'pickedup':
        return Colors.deepPurple;
      case 'delivered':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      case 'needs_rider_assignment':
        return Colors.orange; // Use orange for needs assignment
      default:
        return Colors.grey;
    }
  }

  Widget _buildActionButtons(BuildContext context, String status) {
    final List<Widget> buttons = [];
    final data = order.data() as Map? ?? {};
    final bool isAutoAssigning = data.containsKey('autoAssignStarted');
    final bool needsManualAssignment = status == 'needs_rider_assignment';

    // Consistent styling for all buttons
    const EdgeInsets btnPadding = EdgeInsets.symmetric(horizontal: 14, vertical: 10);
    const Size btnMinSize = Size(0, 40);

    // --- UNIVERSAL ACTIONS ---

    if (status == 'pending') {
      buttons.add(
        ElevatedButton.icon(
          icon: const Icon(Icons.check, size: 16),
          label: const Text('Accept Order'),
          onPressed: () => onStatusChange(context, order.id, 'preparing'),
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
          onPressed: () => onStatusChange(context, order.id, 'prepared'),
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

    final statusLower = status.toLowerCase();
    if (statusLower != 'pending' && statusLower != 'cancelled') {
      buttons.add(
        OutlinedButton.icon(
          icon: const Icon(Icons.print, size: 16),
          label: const Text('Reprint Receipt'),
          onPressed: () async {
            final rootCtx = navigatorKey.currentState?.context ?? context;
            final freshDoc = await order.reference.get();
            final freshData = freshDoc.data() as Map? ?? {};
            final s = (freshData['status'] as String?)?.toLowerCase() ?? '';
            if (s == 'cancelled') {
              ScaffoldMessenger.of(rootCtx).showSnackBar(
                const SnackBar(
                  content: Text('Cannot reprint a cancelled order.'),
                  backgroundColor: Colors.red,
                ),
              );
              return;
            }
            await printReceipt(rootCtx, freshDoc);
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

    // --- ORDER-TYPE SPECIFIC ACTIONS ---

    final orderTypeLower = orderType.toLowerCase();

    // **Custom flow for PICKUP orders**
    if (orderTypeLower == 'pickup') {
      if (status == 'prepared') {
        buttons.add(
          ElevatedButton.icon(
            icon: const Icon(Icons.task_alt, size: 16),
            label: const Text('Mark as Delivered'),
            onPressed: () => onStatusChange(context, order.id, 'delivered'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
              padding: btnPadding,
              minimumSize: btnMinSize,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        );
      }
    }
    // **Flow for other non-delivery types**
    else if (orderTypeLower == 'takeaway' || orderTypeLower == 'dine_in') {
      if (status == 'prepared') {
        buttons.add(
          ElevatedButton.icon(
            icon: const Icon(Icons.task_alt, size: 16),
            label: const Text('Mark as Picked Up'),
            onPressed: () => onStatusChange(context, order.id, 'delivered'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
              padding: btnPadding,
              minimumSize: btnMinSize,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        );
      }
    }
    // **Flow for DELIVERY orders**
    else if (orderTypeLower == 'delivery') {
      if ((status == 'prepared' || needsManualAssignment) && !isAutoAssigning) {
        buttons.add(
          ElevatedButton.icon(
            icon: const Icon(Icons.delivery_dining, size: 16),
            label: Text(needsManualAssignment ? 'Assign Manually' : 'Assign Rider'),
            onPressed: () => onAssigned(context, order.id),
            style: ElevatedButton.styleFrom(
              backgroundColor: needsManualAssignment ? Colors.orange : Colors.blue,
              foregroundColor: Colors.white,
              padding: btnPadding,
              minimumSize: btnMinSize,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        );
      }
      if (status == 'pickedUp') {
        buttons.add(
          ElevatedButton.icon(
            icon: const Icon(Icons.task_alt, size: 16),
            label: const Text('Mark as Delivered'),
            onPressed: () => onStatusChange(context, order.id, 'delivered'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
              padding: btnPadding,
              minimumSize: btnMinSize,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        );
      }
    }

    // Auto-assigning indicator
    if (isAutoAssigning) {
      buttons.add(
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
                    valueColor: AlwaysStoppedAnimation(Colors.blue),
                  ),
                ),
                SizedBox(width: 8),
                Text(
                  'Auto-assigning...',
                  style: TextStyle(
                    color: Colors.blue,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Cancel button
    if (status == 'pending' || status == 'preparing') {
      buttons.add(
        ElevatedButton.icon(
          icon: const Icon(Icons.cancel, size: 16),
          label: const Text('Cancel Order'),
          onPressed: () => onStatusChange(context, order.id, 'cancelled'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            padding: btnPadding,
            minimumSize: btnMinSize,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

  @override
  Widget build(BuildContext context) {
    final data = order.data();
    final items = List<Map<String, dynamic>>.from(data['items'] ?? []);
    final status = data['status']?.toString() ?? 'pending';
    final timestamp = (data['timestamp'] as Timestamp?)?.toDate();
    final orderNumber = data['dailyOrderNumber']?.toString() ??
        order.id.substring(0, 6).toUpperCase();
    final double subtotal = (data['subtotal'] as num? ?? 0.0).toDouble();
    final double deliveryFee = (data['deliveryFee'] as num? ?? 0.0).toDouble();
    final double totalAmount = (data['totalAmount'] as num? ?? 0.0).toDouble();

    // Check for auto-assignment status
    final bool isAutoAssigning = data.containsKey('autoAssignStarted');
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
          // Add highlight glow for selected order
          if (isHighlighted)
            BoxShadow(
              color: Colors.blue.withOpacity(0.3),
              blurRadius: 15,
              spreadRadius: 2,
              offset: const Offset(0, 0),
            ),
        ],
        // Add border for highlighted order
        border: isHighlighted
            ? Border.all(color: Colors.blue, width: 2)
            : null,
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          title: Row(
            children: [
              // Add selection indicator for highlighted order
              if (isHighlighted)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.arrow_forward,
                    color: Colors.white,
                    size: 12,
                  ),
                ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _getStatusColor(status).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Stack(
                  children: [
                    Icon(
                      Icons.receipt_long_outlined,
                      color: _getStatusColor(status),
                      size: 20,
                    ),
                    if (isAutoAssigning)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(
                            Icons.autorenew,
                            color: Colors.white,
                            size: 8,
                          ),
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
                    Text(
                      'Order #$orderNumber',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: isHighlighted ? Colors.blue.shade800 : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      timestamp != null
                          ? DateFormat('MMM dd, yyyy hh:mm a').format(timestamp)
                          : 'No date',
                      style: TextStyle(
                          color: isHighlighted ? Colors.blue.shade600 : Colors.grey[600],
                          fontSize: 12
                      ),
                    ),
                    if (isAutoAssigning) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Auto-assigning rider...',
                        style: TextStyle(
                          color: Colors.blue,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    if (needsManualAssignment) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.orange.withOpacity(0.3)),
                        ),
                        child: Text(
                          'Needs manual assignment',
                          style: TextStyle(
                            color: Colors.orange,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                    // Show "Selected Order" badge for highlighted orders
                    if (isHighlighted) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.blue.withOpacity(0.3)),
                        ),
                        child: Text(
                          'Selected Order',
                          style: TextStyle(
                            color: Colors.blue.shade700,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          trailing: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.3, // Limit width to 30% of screen
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: _getStatusColor(status).withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _getStatusColor(status).withOpacity(0.3),
                ),
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
                      color: _getStatusColor(status),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      _getStatusDisplayText(status),
                      style: TextStyle(
                        color: _getStatusColor(status),
                        fontWeight: FontWeight.bold,
                        fontSize: _getStatusFontSize(status),
                        overflow: TextOverflow.ellipsis,
                      ),
                      maxLines: 1,
                    ),
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
                  if (orderType == 'delivery') ...[
                    _buildDetailRow(Icons.person, 'Customer:',
                        data['customerName'] ?? 'N/A'),
                    _buildDetailRow(
                        Icons.phone, 'Phone:', data['customerPhone'] ?? 'N/A'),
                    _buildDetailRow(
                      Icons.location_on,
                      'Address:',
                      '${data['deliveryAddress']?['street'] ?? ''}, ${data['deliveryAddress']?['city'] ?? ''}',
                    ),
                    if (data['riderId']?.isNotEmpty == true)
                      _buildDetailRow(
                          Icons.delivery_dining, 'Rider:', data['riderId']),
                  ],
                  if (orderType == 'pickup') ...[
                    _buildDetailRow(Icons.store, 'Pickup Branch',
                        data['branchIds'] ?? 'N/A'),
                  ],
                  if (orderType == 'takeaway') ...[
                    _buildDetailRow(
                      Icons.directions_car,
                      'Car Plate:',
                      (data['carPlateNumber']?.toString().isNotEmpty ?? false)
                          ? data['carPlateNumber']
                          : 'N/A',
                    ),
                    if ((data['specialInstructions']?.toString().isNotEmpty ??
                        false))
                      _buildDetailRow(Icons.note, 'Instructions:',
                          data['specialInstructions']),
                  ] else if (orderType == 'dine_in') ...[
                    _buildDetailRow(
                      Icons.table_restaurant,
                      'Table(s):',
                      data['tableNumber'] != null
                          ? (data['tableNumber'] as String)
                          : 'N/A',
                    ),
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
                children: items.map((item) => _buildItemRow(item)).toList(),
              ),
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

  // Helper method to get display text for status
  String _getStatusDisplayText(String status) {
    switch (status.toLowerCase()) {
      case 'needs_rider_assignment':
        return 'NEEDS ASSIGN';
      case 'rider_assigned':
        return 'RIDER ASSIGNED';
      case 'pickedup':
        return 'PICKED UP';
      default:
        return status.toUpperCase();
    }
  }

  // Helper method to get appropriate font size based on status length
  double _getStatusFontSize(String status) {
    final displayText = _getStatusDisplayText(status);
    if (displayText.length > 12) {
      return 9;
    } else if (displayText.length > 8) {
      return 10;
    } else {
      return 11;
    }
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.deepPurple, size: 18),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: Colors.deepPurple),
        ),
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
          Expanded(
            flex: 2,
            child: Text(label,
                style:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ),
          Expanded(
            flex: 3,
            child: Text(value,
                style: const TextStyle(fontSize: 13, color: Colors.black87)),
          ),
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
            child: Text.rich(
              TextSpan(
                text: name,
                style:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                children: [
                  TextSpan(
                    text: ' (x$qty)',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.normal,
                        color: Colors.black54),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'QAR ${(price * qty).toStringAsFixed(2)}',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13, color: Colors.black),
            ),
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
          Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 15 : 13,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              color: isTotal ? Colors.black : Colors.grey[800],
            ),
          ),
          Text(
            'QAR ${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: isTotal ? 15 : 13,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              color: isTotal ? Colors.black : Colors.grey[800],
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Enhanced Rider Selection Dialog
// -----------------------------------------------------------------------------

class _RiderSelectionDialog extends StatelessWidget {
  final String currentBranchId;

  const _RiderSelectionDialog({required this.currentBranchId});

  @override
  Widget build(BuildContext context) {
    // Build the branch-aware query for available drivers
    Query query = FirebaseFirestore.instance
        .collection('Drivers')
        .where('isAvailable', isEqualTo: true)
        .where('status', isEqualTo: 'online');

    // Filter by branch for non-super admin
    query = query.where('branchIds', arrayContains: currentBranchId);

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.delivery_dining, color: Colors.deepPurple),
          SizedBox(width: 8),
          Text('Select Available Rider'),
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
                  const Text(
                    'Error loading riders',
                    style: TextStyle(color: Colors.red),
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
                    'All riders are currently busy',
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
                final String phone = data['phone'] ?? 'No phone';
                final String vehicle = data['vehicleType'] ?? 'No vehicle';

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
                      child: Icon(
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
                          Text(
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

/// A simple static service to pass a selected orderId from one screen
/// (like Dashboard) to the OrdersScreen.

Future<void> printReceipt(
    BuildContext context, DocumentSnapshot orderDoc) async {
  try {
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async {
        // --- 1. Extract Order Data ---
        final Map<String, dynamic> order =
        Map<String, dynamic>.from(orderDoc.data() as Map);

        final List<dynamic> rawItems = (order['items'] ?? []) as List<dynamic>;
        final List<Map<String, dynamic>> items = rawItems.map((e) {
          final m = Map<String, dynamic>.from(e as Map);
          final name = (m['name'] ?? 'Item').toString();
          final qtyRaw = m.containsKey('quantity') ? m['quantity'] : m['qty'];
          final qty = int.tryParse(qtyRaw?.toString() ?? '1') ?? 1;
          final priceRaw = m['price'] ?? m['unitPrice'] ?? m['amount'];
          final double price = switch (priceRaw) {
            num n => n.toDouble(),
            _ => double.tryParse(priceRaw?.toString() ?? '0') ?? 0.0,
          };
          return {'name': name, 'qty': qty, 'price': price};
        }).toList();

        final double subtotal = (order['subtotal'] as num?)?.toDouble() ?? 0.0;
        final double discount =
            (order['discountAmount'] as num?)?.toDouble() ?? 0.0;
        final double totalAmount =
            (order['totalAmount'] as num?)?.toDouble() ?? 0.0;
        final double calculatedSubtotal = items.fold(
            0, (sum, item) => sum + (item['price'] * item['qty']));
        final double finalSubtotal =
        subtotal > 0 ? subtotal : calculatedSubtotal;

        final DateTime? orderDate = (order['timestamp'] as Timestamp?)?.toDate();
        final String formattedDate = orderDate != null
            ? DateFormat('dd/MM/yyyy').format(orderDate)
            : "N/A";
        final String formattedTime = orderDate != null
            ? DateFormat('hh:mm a').format(orderDate)
            : "N/A";

        final String rawOrderType =
        (order['Order_type'] ?? order['Ordertype'] ?? 'Unknown').toString();
        final String displayOrderType = rawOrderType
            .replaceAll('_', ' ')
            .split(' ')
            .map((w) =>
        w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
            .join(' ');

        final String dailyOrderNumber = order['dailyOrderNumber']?.toString() ??
            orderDoc.id.substring(0, 6).toUpperCase();

        final String customerName =
        (order['customerName'] ?? 'Walk-in Customer').toString();
        final String carPlate = (order['carPlateNumber'] ?? '').toString();
        final String customerDisplay =
        rawOrderType.toLowerCase() == 'takeaway' && carPlate.isNotEmpty
            ? 'Car Plate: $carPlate'
            : customerName;

        // --- 2. Fetch Branch Details ---
        final List<dynamic> branchIds = order['branchIds'] ?? [];
        String primaryBranchId =
        branchIds.isNotEmpty ? branchIds.first.toString() : '';

        String branchName = "Restaurant Name"; // Fallback
        String branchPhone = "";
        String branchAddress = "";
        pw.ImageProvider? branchLogo;

        try {
          if (primaryBranchId.isNotEmpty) {
            final branchSnap = await FirebaseFirestore.instance
                .collection('Branch')
                .doc(primaryBranchId)
                .get();
            if (branchSnap.exists) {
              final branchData = branchSnap.data()!;
              branchName = branchData['name'] ?? "Restaurant Name";
              branchPhone = branchData['phone'] ?? "";
              final addressMap =
                  branchData['address'] as Map<String, dynamic>? ?? {};
              final street = addressMap['street'] ?? '';
              final city = addressMap['city'] ?? '';
              branchAddress = (street.isNotEmpty && city.isNotEmpty)
                  ? "$street, $city"
                  : (street + city);
            }
          }
        } catch (e) {
          debugPrint("Error fetching branch details for receipt: $e");
        }

        // --- 3. Build the PDF ---
        final pdf = pw.Document();
        const pw.TextStyle regular = pw.TextStyle(fontSize: 9);
        final pw.TextStyle bold =
        pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold);
        final pw.TextStyle small =
        pw.TextStyle(fontSize: 8, color: PdfColors.grey600);
        final pw.TextStyle heading = pw.TextStyle(
            fontSize: 16,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.black);
        final pw.TextStyle total = pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.black);

        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.roll80,
            build: (_) {
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (branchLogo != null)
                    pw.Center(
                      child:
                      pw.Image(branchLogo, height: 60, fit: pw.BoxFit.contain),
                    ),
                  pw.SizedBox(height: 5),
                  pw.Center(child: pw.Text(branchName, style: heading)),
                  if (branchAddress.isNotEmpty)
                    pw.Center(child: pw.Text(branchAddress, style: regular)),
                  if (branchPhone.isNotEmpty)
                    pw.Center(child: pw.Text("Tel: $branchPhone", style: regular)),
                  pw.SizedBox(height: 5),
                  pw.Center(
                      child: pw.Text("TAX INVOICE",
                          style: bold.copyWith(fontSize: 10))),
                  pw.SizedBox(height: 10),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Order #: $dailyOrderNumber', style: regular),
                      pw.Text('Type: $displayOrderType', style: bold),
                    ],
                  ),
                  pw.SizedBox(height: 3),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Date: $formattedDate', style: regular),
                      pw.Text('Time: $formattedTime', style: regular),
                    ],
                  ),
                  pw.SizedBox(height: 3),
                  pw.Text('Customer: $customerDisplay', style: regular),
                  pw.SizedBox(height: 10),
                  pw.Table(
                    columnWidths: {
                      0: const pw.FlexColumnWidth(5),
                      1: const pw.FlexColumnWidth(1.5),
                      2: const pw.FlexColumnWidth(2.5),
                    },
                    border: const pw.TableBorder(
                      top: pw.BorderSide(color: PdfColors.black, width: 1),
                      bottom: pw.BorderSide(color: PdfColors.black, width: 1),
                      horizontalInside:
                      pw.BorderSide(color: PdfColors.grey300, width: 0.5),
                    ),
                    children: [
                      pw.TableRow(
                        children: [
                          pw.Padding(
                              padding: const pw.EdgeInsets.symmetric(vertical: 4),
                              child: pw.Text('ITEM', style: bold)),
                          pw.Padding(
                              padding: const pw.EdgeInsets.symmetric(vertical: 4),
                              child: pw.Text('QTY',
                                  style: bold, textAlign: pw.TextAlign.center)),
                          pw.Padding(
                              padding: const pw.EdgeInsets.symmetric(vertical: 4),
                              child: pw.Text('TOTAL',
                                  style: bold,
                                  textAlign: pw.TextAlign.right)),
                        ],
                      ),
                      ...items.map((item) {
                        return pw.TableRow(
                          children: [
                            pw.Padding(
                                padding:
                                const pw.EdgeInsets.symmetric(vertical: 3),
                                child: pw.Text(item['name'], style: regular)),
                            pw.Padding(
                                padding:
                                const pw.EdgeInsets.symmetric(vertical: 3),
                                child: pw.Text(item['qty'].toString(),
                                    style: regular,
                                    textAlign: pw.TextAlign.center)),
                            pw.Padding(
                                padding:
                                const pw.EdgeInsets.symmetric(vertical: 3),
                                child: pw.Text(
                                    (item['price'] * item['qty'])
                                        .toStringAsFixed(2),
                                    style: regular,
                                    textAlign: pw.TextAlign.right)),
                          ],
                        );
                      }),
                    ],
                  ),
                  pw.SizedBox(height: 10),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.end,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Row(
                            children: [
                              pw.Text('Subtotal: ', style: regular),
                              pw.SizedBox(width: 10),
                              pw.Text('QAR ${finalSubtotal.toStringAsFixed(2)}',
                                  style: bold,
                                  textAlign: pw.TextAlign.right),
                            ],
                          ),
                          if (discount > 0)
                            pw.Row(
                              children: [
                                pw.Text('Discount: ', style: regular),
                                pw.SizedBox(width: 10),
                                pw.Text(
                                    '- QAR ${discount.toStringAsFixed(2)}',
                                    style: bold.copyWith(color: PdfColors.green),
                                    textAlign: pw.TextAlign.right),
                              ],
                            ),
                          pw.Divider(height: 5, color: PdfColors.grey),
                          pw.Row(
                            children: [
                              pw.Text('TOTAL: ', style: total),
                              pw.SizedBox(width: 10),
                              pw.Text('QAR ${totalAmount.toStringAsFixed(2)}',
                                  style: total,
                                  textAlign: pw.TextAlign.right),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 20),
                  pw.Divider(thickness: 1),
                  pw.SizedBox(height: 5),
                  pw.Center(
                      child: pw.Text("Thank You For Your Order!", style: bold)),
                  pw.SizedBox(height: 5),
                  pw.Center(
                      child: pw.Text("Invoice ID: ${orderDoc.id}", style: small)),
                ],
              );
            },
          ),
        );

        // --- 4. Save and return PDF bytes ---
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


/// A simple static service to pass a selected orderId from one screen
/// (like Dashboard) to the OrdersScreen.
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


