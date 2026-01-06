import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../Widgets/OrderService.dart';
import '../Widgets/PrintingService.dart';
import '../Widgets/RiderAssignment.dart';
import '../Widgets/TimeUtils.dart';
import '../main.dart';
import '../constants.dart';

// Service for handling cross-screen order selection/highlighting
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
  late ScrollController _scrollController;
  String _selectedStatus = 'all';

  final OrderService _orderService = OrderService();

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
      AppConstants.statusPending,
      AppConstants.statusPreparing,
      AppConstants.statusRiderAssigned,
      AppConstants.statusPickedUp,
      AppConstants.statusDelivered,
      AppConstants.statusCancelled,
      AppConstants.statusNeedsAssignment,
    ];
  }

  Future<void> updateOrderStatus(String orderId, String newStatus,
      {String? reason}) async {
    if (!mounted) return;

    setState(() {
      _processingOrderIds.add(orderId);
    });

    try {
      final userScope = context.read<UserScopeService>();

      await _orderService.updateOrderStatus(
        context,
        orderId,
        newStatus,
        reason: reason,
        currentUserEmail: userScope.userEmail,
      );

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
                _buildEnhancedStatusChip('Placed', AppConstants.statusPending,
                    Icons.schedule_rounded),
                _buildEnhancedStatusChip('Preparing',
                    AppConstants.statusPreparing, Icons.restaurant_rounded),
                _buildEnhancedStatusChip('Needs Assign',
                    AppConstants.statusNeedsAssignment, Icons.person_pin_circle_outlined),
                _buildEnhancedStatusChip('Rider Assigned',
                    AppConstants.statusRiderAssigned, Icons.delivery_dining_rounded),
                _buildEnhancedStatusChip('Picked Up',
                    AppConstants.statusPickedUp, Icons.local_shipping_rounded),
                _buildEnhancedStatusChip('Delivered',
                    AppConstants.statusDelivered, Icons.check_circle_rounded),
                _buildEnhancedStatusChip('Cancelled',
                    AppConstants.statusCancelled, Icons.cancel_rounded),
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
      case AppConstants.statusPending:
      case AppConstants.statusNeedsAssignment:
        chipColor = Colors.orange;
        break;
      case AppConstants.statusPreparing:
        chipColor = Colors.teal;
        break;
      case AppConstants.statusRiderAssigned:
        chipColor = Colors.purple;
        break;
      case AppConstants.statusPickedUp:
        chipColor = Colors.deepPurple;
        break;
      case AppConstants.statusDelivered:
        chipColor = Colors.green;
        break;
      case AppConstants.statusCancelled:
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
    final userScope = context.read<UserScopeService>();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _orderService.getOrdersStream(
        orderType: orderType,
        status: _selectedStatus,
        userScope: userScope,
      ),
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
                (orderDoc.id == widget.initialOrderId ||
                    orderDoc.id == _orderToScrollTo);

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
  bool _isProcessingRefund = false;

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange;
      case 'preparing':
        return Colors.teal;
      case 'rider_assigned':
        return Colors.purple;
      case 'pickedup':
        return Colors.deepPurple;
      case 'delivered':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      case 'refunded':
        return Colors.pink;
      case 'needs_rider_assignment':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  Future<void> _showRefundConfirmationDialog(BuildContext context, bool isApprove, String? imageUrl) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(
                isApprove ? Icons.check_circle_outline : Icons.highlight_off,
                color: isApprove ? Colors.green : Colors.red,
                size: 28,
              ),
              const SizedBox(width: 10),
              Text(
                isApprove ? 'Approve Refund' : 'Reject Refund',
                style: TextStyle(
                  color: isApprove ? Colors.green[800] : Colors.red[800],
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text(
                  isApprove
                      ? 'Are you sure you want to APPROVE this refund request?'
                      : 'Are you sure you want to REJECT this refund request?',
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 10),
                Text(
                  isApprove
                      ? 'This will mark the order as "Refunded" and update the timestamps.'
                      : 'The refund request will be marked as "Rejected".',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isApprove ? Colors.green : Colors.red,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Confirm', style: TextStyle(color: Colors.white)),
              onPressed: () {
                Navigator.of(context).pop();
                _handleRefundAction(isApprove, imageUrl);
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleRefundAction(bool approved, String? imageUrl) async {
    setState(() => _isProcessingRefund = true);
    try {
      if (imageUrl != null && imageUrl.isNotEmpty) {
        try {
          await FirebaseStorage.instance.refFromURL(imageUrl).delete();
        } catch (e) {
          debugPrint("Image delete failed (may already be deleted): $e");
        }
      }

      final refundStatus = approved ? 'accepted' : 'rejected';
      final Map<String, dynamic> updateData = {
        'refundRequest.status': refundStatus,
        'refundRequest.adminActionAt': FieldValue.serverTimestamp(),
        'refundRequest.imageUrl': null,
      };

      if (approved) {
        updateData['status'] = 'refunded';
        updateData['timestamps.refunded'] = FieldValue.serverTimestamp();
      }

      await FirebaseFirestore.instance
          .collection('Orders')
          .doc(widget.order.id)
          .update(updateData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Refund request $refundStatus'),
            backgroundColor: approved ? Colors.green : Colors.grey,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error handling refund: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessingRefund = false);
      }
    }
  }

  Widget _buildRefundManagementSection(Map<String, dynamic> data) {
    final refund = data['refundRequest'] as Map<String, dynamic>?;
    if (refund == null || refund['status'] != 'pending') {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.money_off, color: Colors.red.shade700),
              const SizedBox(width: 8),
              Text(
                'Refund Request',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Reason:',
            style: TextStyle(
                fontWeight: FontWeight.bold, color: Colors.red.shade900),
          ),
          Text(
            refund['reason'] ?? 'No reason provided',
            style: TextStyle(color: Colors.red.shade800),
          ),
          const SizedBox(height: 12),
          if (refund['imageUrl'] != null &&
              refund['imageUrl'].toString().isNotEmpty) ...[
            Text(
              'Proof Image:',
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: Colors.red.shade900),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                refund['imageUrl'],
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                    height: 100,
                    color: Colors.grey.shade300,
                    child: const Icon(Icons.broken_image)),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (_isProcessingRefund)
            const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()))
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Reject'),
                    onPressed: () => _showRefundConfirmationDialog(context, false, refund['imageUrl']),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey.shade700,
                      side: BorderSide(color: Colors.grey.shade400),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Approve'),
                    onPressed: () => _showRefundConfirmationDialog(context, true, refund['imageUrl']),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _handleCancelPress(BuildContext context) async {
    final List<ConnectivityResult> connectivityResult =
    await (Connectivity().checkConnectivity());

    if (connectivityResult.contains(ConnectivityResult.none)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("⚠️ Internet connection required to cancel orders."),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final String? reason = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => const CancellationReasonDialog(),
    );

    if (reason != null && reason.isNotEmpty) {
      widget.onStatusChange(widget.order.id, AppConstants.statusCancelled,
          reason: reason);
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

      await RiderAssignmentService.manualAssignRider(
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
                      strokeWidth: 2, color: Colors.deepPurple)),
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
    final String? riderId = data['riderId'];

    final bool isAutoAssigning =
        data.containsKey('autoAssignStarted') && orderTypeLower == 'delivery';
    final bool needsManualAssignment =
        status == AppConstants.statusNeedsAssignment;

    const EdgeInsets btnPadding =
    EdgeInsets.symmetric(horizontal: 14, vertical: 10);
    const Size btnMinSize = Size(0, 40);

    // 1. Accept Order (Moves to Preparing)
    if (status == AppConstants.statusPending) {
      buttons.add(
        ElevatedButton.icon(
          icon: const Icon(Icons.check, size: 16),
          label: const Text('Accept Order'),
          onPressed: () => widget.onStatusChange(
              widget.order.id, AppConstants.statusPreparing),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            padding: btnPadding,
            minimumSize: btnMinSize,
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );
    }

    // 2. Ready for Pickup/Delivery - show completion for non-delivery, handled below for delivery
    if (status == AppConstants.statusPreparing) {
      if (orderTypeLower != 'delivery') {
        // For non-delivery orders, show completion button
        buttons.add(
          ElevatedButton.icon(
            icon: Icon(orderTypeLower == 'dine_in' ? Icons.restaurant_menu : Icons.local_mall, size: 16),
            label: Text(orderTypeLower == 'dine_in' ? 'Served to Table' : 'Handed to Customer'),
            onPressed: () => widget.onStatusChange(
                widget.order.id, AppConstants.statusDelivered),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
              padding: btnPadding,
              minimumSize: btnMinSize,
              shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        );
      }
    }

    // 3. Reprint Receipt (Not for Cancelled/Refunded)
    if (status != AppConstants.statusCancelled && status != 'refunded') {
      buttons.add(
        OutlinedButton.icon(
          icon: const Icon(Icons.print, size: 16),
          label: const Text('Reprint Receipt'),
          onPressed: () async {
            await PrintingService.printReceipt(context, widget.order);
          },
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.deepPurple,
            side: BorderSide(color: Colors.deepPurple.shade300),
            padding: btnPadding,
            minimumSize: btnMinSize,
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );
    }

    // 4. Order Completion and Assignment Logic
    if (orderTypeLower == 'delivery') {
      final bool canAssign = (status == AppConstants.statusPreparing ||
          needsManualAssignment);

      // Only show assignment buttons if no rider is currently assigned
      if (canAssign && !isAutoAssigning && (riderId == null || riderId.isEmpty)) {
        buttons.add(
          ElevatedButton.icon(
            icon: const Icon(Icons.delivery_dining, size: 16),
            label: Text(
                needsManualAssignment ? 'Assign Manually' : 'Assign Rider'),
            onPressed: () => _assignRiderManually(context),
            style: ElevatedButton.styleFrom(
              backgroundColor:
              needsManualAssignment ? Colors.orange : Colors.blue,
              foregroundColor: Colors.white,
              padding: btnPadding,
              minimumSize: btnMinSize,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        );
      }

      if (status == AppConstants.statusPickedUp) {
        buttons.add(
          ElevatedButton.icon(
            icon: const Icon(Icons.task_alt, size: 16),
            label: const Text('Mark as Delivered'),
            onPressed: () => widget.onStatusChange(
                widget.order.id, AppConstants.statusDelivered),
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

      if (isAutoAssigning) {
        buttons.add(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 40),
                child: Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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

    // 5. Cancel Order Logic
    if (status != AppConstants.statusCancelled &&
        status != AppConstants.statusDelivered &&
        status != 'refunded') {
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
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: Colors.deepPurple)),
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
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500))),
          Expanded(
              flex: 3,
              child: Text(value,
                  style: const TextStyle(fontSize: 13, color: Colors.black87))),
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
                style:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                children: [
                  TextSpan(
                      text: ' (x$qty)',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.normal,
                          color: Colors.black54)),
                ])),
          ),
          Expanded(
            flex: 2,
            child: Text('QAR ${(price * qty).toStringAsFixed(2)}',
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 13, color: Colors.black)),
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
          Text(label,
              style: TextStyle(
                  fontSize: isTotal ? 15 : 13,
                  fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
                  color: isTotal ? Colors.black : Colors.grey[800])),
          Text('QAR ${amount.toStringAsFixed(2)}',
              style: TextStyle(
                  fontSize: isTotal ? 15 : 13,
                  fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
                  color: isTotal ? Colors.black : Colors.grey[800])),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.order.data() as Map<String, dynamic>? ?? {};
    final items = List<Map<String, dynamic>>.from(data['items'] ?? []);
    final status = data['status']?.toString() ?? 'pending';
    final String orderTypeLower = widget.orderType.toLowerCase();

    final DateTime? rawTimestamp = (data['timestamp'] as Timestamp?)?.toDate();
    final DateTime? timestamp = rawTimestamp != null
        ? TimeUtils.getRestaurantTime(rawTimestamp)
        : null;

    final orderNumber = data['dailyOrderNumber']?.toString() ??
        widget.order.id.substring(0, 6).toUpperCase();
    final double subtotal = (data['subtotal'] as num? ?? 0.0).toDouble();
    final double deliveryFee = (data['deliveryFee'] as num? ?? 0.0).toDouble();
    final double totalAmount = (data['totalAmount'] as num? ?? 0.0).toDouble();

    final bool isAutoAssigning = data.containsKey('autoAssignStarted') &&
        orderTypeLower == 'delivery';
    final bool needsManualAssignment =
        status == AppConstants.statusNeedsAssignment;

    final refundRequest = data['refundRequest'] as Map<String, dynamic>?;
    final bool hasPendingRefund =
        refundRequest != null && refundRequest['status'] == 'pending';

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
                    if (hasPendingRefund) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                          border:
                          Border.all(color: Colors.red.withOpacity(0.3)),
                        ),
                        child: const Text(
                          'REFUND REQUESTED',
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: 10,
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
            _buildRefundManagementSection(data),

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
                    _buildDetailRow(Icons.person, 'Customer:',
                        data['customerName'] ?? 'N/A'),
                    _buildDetailRow(
                        Icons.phone, 'Phone:', data['customerPhone'] ?? 'N/A'),
                    _buildDetailRow(Icons.location_on, 'Address:',
                        '${data['deliveryAddress']?['street'] ?? ''}, ${data['deliveryAddress']?['city'] ?? ''}'),
                    if (data['riderId']?.isNotEmpty == true)
                      _buildDetailRow(
                          Icons.delivery_dining, 'Rider:', data['riderId']),
                  ],
                  if (widget.orderType == 'pickup') ...[
                    _buildDetailRow(Icons.store, 'Pickup Branch',
                        data['branchIds']?.join(', ') ?? 'N/A'),
                  ],
                  if (widget.orderType == 'takeaway') ...[
                    _buildDetailRow(
                        Icons.directions_car,
                        'Car Plate:',
                        (data['carPlateNumber']?.toString().isNotEmpty ?? false)
                            ? data['carPlateNumber']
                            : 'N/A'),
                    if ((data['specialInstructions']?.toString().isNotEmpty ??
                        false))
                      _buildDetailRow(Icons.note, 'Instructions:',
                          data['specialInstructions']),
                  ] else if (widget.orderType == 'dine_in') ...[
                    _buildDetailRow(
                        Icons.table_restaurant,
                        'Table(s):',
                        data['tableNumber'] != null
                            ? (data['tableNumber'] as String)
                            : 'N/A'),
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



class _OrderPopupDialog extends StatefulWidget {
  final DocumentSnapshot order;

  const _OrderPopupDialog({required this.order});

  @override
  State<_OrderPopupDialog> createState() => _OrderPopupDialogState();
}

class _OrderPopupDialogState extends State<_OrderPopupDialog> {
  bool _isLoading = false;

  Future<void> _handleRefundAction(bool approved, String? imageUrl) async {
    setState(() => _isLoading = true);
    try {
      if (imageUrl != null && imageUrl.isNotEmpty) {
        try {
          await FirebaseStorage.instance.refFromURL(imageUrl).delete();
        } catch (e) {
          debugPrint("Image delete failed (may already be deleted): $e");
        }
      }

      final status = approved ? 'accepted' : 'rejected';
      final updateData = {
        'refundRequest.status': status,
        'refundRequest.adminActionAt': FieldValue.serverTimestamp(),
        'refundRequest.imageUrl': null,
      };

      if (approved) {
        updateData['status'] = 'refunded';
        updateData['timestamps.refunded'] = FieldValue.serverTimestamp();
      }

      await FirebaseFirestore.instance
          .collection('Orders')
          .doc(widget.order.id)
          .update(updateData);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Refund request $status'),
            backgroundColor: approved ? Colors.green : Colors.grey,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error handling refund: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildRefundManagementSection(Map<String, dynamic> data) {
    final refund = data['refundRequest'] as Map<String, dynamic>?;
    if (refund == null || refund['status'] != 'pending') {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.money_off, color: Colors.red.shade700),
              const SizedBox(width: 8),
              Text(
                'Refund Request',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Reason:',
            style: TextStyle(
                fontWeight: FontWeight.bold, color: Colors.red.shade900),
          ),
          Text(
            refund['reason'] ?? 'No reason provided',
            style: TextStyle(color: Colors.red.shade900),
          ),
          const SizedBox(height: 12),
          if (refund['imageUrl'] != null &&
              refund['imageUrl'].toString().isNotEmpty) ...[
            Text(
              'Proof Image:',
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: Colors.red.shade900),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                refund['imageUrl'],
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                    height: 100,
                    color: Colors.grey.shade300,
                    child: const Icon(Icons.broken_image)),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () =>
                      _handleRefundAction(false, refund['imageUrl']),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey.shade700,
                    side: BorderSide(color: Colors.grey.shade400),
                  ),
                  child: const Text('Reject Refund'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () =>
                      _handleRefundAction(true, refund['imageUrl']),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text('Approve Refund'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ✅ UPDATED: Now uses centralized OrderService for Atomic Updates
  Future<void> updateOrderStatus(String orderId, String newStatus,
      {String? cancellationReason}) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final userScope = context.read<UserScopeService>();

      // ✅ FIX: Use the OrderService which handles Batches correctly
      // This ensures Driver and Order are updated at the exact same time.
      await OrderService().updateOrderStatus(
        context,
        orderId,
        newStatus,
        reason: cancellationReason,
        currentUserEmail: userScope.userEmail,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Order status updated to "$newStatus"!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
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
          _isLoading = false;
        });
      }
    }
  }

  // ✅ UPDATED: Now uses robust RiderAssignmentService
  Future<void> _assignRider(String orderId) async {
    final userScope = context.read<UserScopeService>();
    final currentBranchId = userScope.branchId;

    final riderId = await showDialog<String>(
      context: context,
      builder: (context) =>
          _RiderSelectionDialog(currentBranchId: currentBranchId),
    );

    if (riderId != null && riderId.isNotEmpty) {
      setState(() {
        _isLoading = true;
      });

      // ✅ FIX: Uses Transaction-based assignment to prevent Double-Assign bug
      final success = await RiderAssignmentService.manualAssignRider(
        orderId: orderId,
        riderId: riderId,
        context: context,
      );

      if (mounted) {
        setState(() => _isLoading = false);
        if (success) {
          Navigator.of(context).pop(); // Close popup only on success
        }
      }
    }
  }

  Widget _buildActionButtons(String status, String orderType, String orderId) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(Colors.deepPurple),
          ),
        ),
      );
    }

    final List<Widget> buttons = [];
    final data = widget.order.data() as Map<String, dynamic>? ?? {};
    final String orderTypeLower = orderType.toLowerCase();

    final bool isAutoAssigning =
        data.containsKey('autoAssignStarted') && orderTypeLower == 'delivery';
    final bool needsManualAssignment =
        status == AppConstants.statusNeedsAssignment;

    const EdgeInsets btnPadding =
    EdgeInsets.symmetric(horizontal: 14, vertical: 10);
    const Size btnMinSize = Size(0, 40);

    final statusLower = status.toLowerCase();

    // ✅ Updated to check for refunded
    if (statusLower != 'pending' && statusLower != 'cancelled' && statusLower != 'refunded') {
      buttons.add(
        OutlinedButton.icon(
          icon: const Icon(Icons.print, size: 16),
          label: const Text('Reprint Receipt'),
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Printer service not connected.')),
            );
          },
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.deepPurple,
            side: BorderSide(color: Colors.deepPurple.shade300),
            padding: btnPadding,
            minimumSize: btnMinSize,
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );
    }

    if (status == AppConstants.statusPending) {
      buttons.add(
        ElevatedButton.icon(
          icon: const Icon(Icons.check, size: 16),
          label: const Text('Accept Order'),
          onPressed: () => updateOrderStatus(
              orderId, AppConstants.statusPreparing),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            padding: btnPadding,
            minimumSize: btnMinSize,
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );
    }

    if (status == AppConstants.statusPreparing) {
      // Show completion buttons for non-delivery orders
      if (orderTypeLower != 'delivery') {
        buttons.add(
          ElevatedButton.icon(
            icon: Icon(orderTypeLower == 'dine_in' ? Icons.restaurant_menu : Icons.local_mall, size: 16),
            label: Text(orderTypeLower == 'dine_in' ? 'Served to Table' : 'Handed to Customer'),
            onPressed: () => updateOrderStatus(
                orderId, AppConstants.statusDelivered),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
              padding: btnPadding,
              minimumSize: btnMinSize,
              shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        );
      }
    }

    if (orderTypeLower == 'delivery') {
      if ((status == AppConstants.statusPreparing || needsManualAssignment) &&
          !isAutoAssigning) {
        buttons.add(
          ElevatedButton.icon(
            icon: const Icon(Icons.delivery_dining, size: 16),
            label: Text(
                needsManualAssignment ? 'Assign Manually' : 'Assign Rider'),
            onPressed: () => _assignRider(orderId),
            style: ElevatedButton.styleFrom(
              backgroundColor:
              needsManualAssignment ? Colors.orange : Colors.blue,
              foregroundColor: Colors.white,
              padding: btnPadding,
              minimumSize: btnMinSize,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        );
      }

      if (status == AppConstants.statusPickedUp) {
        buttons.add(
          ElevatedButton.icon(
            icon: const Icon(Icons.task_alt, size: 16),
            label: const Text('Mark as Delivered'),
            onPressed: () => updateOrderStatus(
                orderId, AppConstants.statusDelivered),
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
                    'Auto-assigning rider...',
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
    }

    if (status != AppConstants.statusCancelled &&
        status != AppConstants.statusDelivered &&
        status != 'refunded' &&
        status != AppConstants.statusPickedUp // Don't cancel after picked up usually
    ) {
      // NOTE: The previous condition was looser. Here is the strict "Terminal State" check logic you requested:
      // Show Cancel button ONLY if NOT terminal.
      // Terminal states: Cancelled, Delivered, Refunded.
      // Also usually you don't cancel after Picked Up easily, but sticking to your core request.
    }

    // Re-applying the simplified logic from the specific fix request:
    if (status != AppConstants.statusCancelled &&
        status != AppConstants.statusDelivered &&
        status != 'refunded') {
      buttons.add(
        ElevatedButton.icon(
          icon: const Icon(Icons.cancel, size: 16),
          label: const Text('Cancel Order'),
          onPressed: () async {
            final reason = await showDialog<String>(
              context: context,
              builder: (context) => const CancellationReasonDialog(),
            );
            if (reason != null && reason.trim().isNotEmpty) {
              updateOrderStatus(orderId, AppConstants.statusCancelled,
                  cancellationReason: reason);
            }
          },
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

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.deepPurple, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Colors.deepPurple,
          ),
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
          Icon(icon, size: 18, color: Colors.deepPurple.shade400),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Text(label,
                style:
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          ),
          Expanded(
            flex: 3,
            child: Text(value,
                style: const TextStyle(fontSize: 14, color: Colors.black87)),
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
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                children: [
                  TextSpan(
                    text: ' (x$qty)',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.normal,
                      color: Colors.black54,
                    ),
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
              style: const TextStyle(fontSize: 14, color: Colors.black),
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
              fontSize: isTotal ? 16 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              color: isTotal ? Colors.black : Colors.grey[800],
            ),
          ),
          Text(
            'QAR ${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: isTotal ? 16 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              color: isTotal ? Colors.black : Colors.grey[800],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.order.data() as Map<String, dynamic>? ?? {};
    final items = List<Map<String, dynamic>>.from(data['items'] ?? []);
    final status = data['status']?.toString() ?? 'pending';
    final timestamp = (data['timestamp'] as Timestamp?)?.toDate();
    final orderNumber = data['dailyOrderNumber']?.toString() ??
        widget.order.id.substring(0, 6).toUpperCase();
    final double subtotal = (data['subtotal'] as num? ?? 0.0).toDouble();
    final double deliveryFee = (data['deliveryFee'] as num? ?? 0.0).toDouble();
    final double totalAmount = (data['totalAmount'] as num? ?? 0.0).toDouble();
    final String orderType = data['Order_type'] as String? ?? 'delivery';

    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(20)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Order #$orderNumber',
                            style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.deepPurple)),
                        const SizedBox(height: 4),
                        Text(
                            timestamp != null
                                ? DateFormat('MMM dd, yyyy hh:mm a')
                                .format(timestamp)
                                : 'No date',
                            style: TextStyle(
                                color: Colors.grey[600], fontSize: 14)),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _getStatusColor(status).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: _getStatusColor(status).withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _getStatusColor(status))),
                        const SizedBox(width: 6),
                        Text(status.toUpperCase(),
                            style: TextStyle(
                                color: _getStatusColor(status),
                                fontWeight: FontWeight.bold,
                                fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              _buildRefundManagementSection(data),

              _buildSectionHeader('Customer Details', Icons.person_outline),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!)),
                child: Column(
                  children: [
                    if (orderType.toLowerCase() == 'delivery') ...[
                      _buildDetailRow(Icons.person, 'Customer:',
                          data['customerName'] ?? 'N/A'),
                      _buildDetailRow(Icons.phone, 'Phone:',
                          data['customerPhone'] ?? 'N/A'),
                      _buildDetailRow(Icons.location_on, 'Address:',
                          '${data['deliveryAddress']?['street'] ?? ''}, ${data['deliveryAddress']?['city'] ?? ''}'),
                      if (data['riderId']?.isNotEmpty == true)
                        _buildDetailRow(
                            Icons.delivery_dining, 'Rider:', data['riderId']),
                    ] else ...[
                      _buildDetailRow(Icons.person, 'Customer:',
                          data['customerName'] ?? 'N/A'),
                      _buildDetailRow(Icons.phone, 'Phone:',
                          data['customerPhone'] ?? 'N/A'),
                    ]
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
                    border: Border.all(color: Colors.grey[200]!)),
                child: Column(
                    children:
                    items.map((item) => _buildItemRow(item)).toList()),
              ),
              const SizedBox(height: 20),
              _buildSectionHeader('Order Summary', Icons.summarize),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!)),
                child: Column(
                  children: [
                    _buildSummaryRow('Subtotal', subtotal),
                    if (deliveryFee > 0)
                      _buildSummaryRow('Delivery Fee', deliveryFee),
                    const Divider(height: 20),
                    _buildSummaryRow('Total Amount', totalAmount,
                        isTotal: true),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _buildSectionHeader('Actions', Icons.touch_app),
              const SizedBox(height: 16),
              _buildActionButtons(status, orderType, widget.order.id),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed:
                  _isLoading ? null : () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange;
      case 'preparing':
        return Colors.teal;
      case 'rider_assigned':
        return Colors.purple;
      case 'pickedup':
        return Colors.deepPurple;
      case 'delivered':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      case 'refunded':
        return Colors.pink;
      case 'needs_rider_assignment':
        return Colors.orange;
      default:
        return Colors.grey;
    }
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
                          finalReason =
                              _otherReasonController.text.trim();
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

class _RiderSelectionDialog extends StatelessWidget {
  final String? currentBranchId;

  const _RiderSelectionDialog({required this.currentBranchId});

  @override
  Widget build(BuildContext context) {
    Query query = FirebaseFirestore.instance
        .collection(AppConstants.collectionDrivers)
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
                  // ✅ FIXED: textAlign moved to Text widget
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