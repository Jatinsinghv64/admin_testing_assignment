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
import '../Widgets/CancellationDialog.dart'; // ✅ Shared cancellation dialog
import '../main.dart';
import '../constants.dart';
import '../Widgets/BranchFilterService.dart'; // ✅ Added
import '../Widgets/OrderUIComponents.dart'; // ✅ Shared UI components

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

    // Load branch names if needed (for multi-branch users)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userScope = context.read<UserScopeService>();
      final branchFilter = context.read<BranchFilterService>();
      if (userScope.branchIds.length > 1 && !branchFilter.isLoaded) {
        branchFilter.loadBranchNames(userScope.branchIds);
      }
    });

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

    // ✅ Network connectivity check
    if (!await NetworkUtils.hasConnectivity()) {
      if (mounted) {
        NetworkUtils.showNetworkError(context);
      }
      return;
    }

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
            content: Text('Order status updated to "${StatusUtils.getDisplayText(newStatus)}"'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        // ✅ User-friendly error message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(NetworkUtils.getUserFriendlyError(e)),
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
    final userScope = context.watch<UserScopeService>();
    final branchFilter = context.watch<BranchFilterService>();
    final bool showBranchSelector = userScope.branchIds.length > 1;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        centerTitle: !showBranchSelector, // Left-align when selector shown
        title: const Text(
          'Orders',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.deepPurple,
            fontSize: 24,
          ),
        ),
        actions: [
          if (showBranchSelector)
             _buildBranchSelector(userScope, branchFilter),
        ],
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

  // Same branch selector logic as DashboardScreen
  Widget _buildBranchSelector(UserScopeService userScope, BranchFilterService branchFilter) {
    return Container(
      margin: const EdgeInsets.only(right: 12),
      child: PopupMenuButton<String>(
        offset: const Offset(0, 45),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.deepPurple.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.deepPurple.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.store, size: 18, color: Colors.deepPurple),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 100),
                child: Text(
                  branchFilter.selectedBranchId == null
                      ? 'All Branches'
                      : branchFilter.getBranchName(branchFilter.selectedBranchId!),
                  style: const TextStyle(
                    color: Colors.deepPurple,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.arrow_drop_down, color: Colors.deepPurple, size: 20),
            ],
          ),
        ),
        itemBuilder: (context) => [
          PopupMenuItem<String>(
            value: BranchFilterService.allBranchesValue,
            child: Row(children: [
               Icon(branchFilter.selectedBranchId == null ? Icons.check_circle : Icons.circle_outlined, size:18, color: branchFilter.selectedBranchId == null ? Colors.deepPurple : Colors.grey),
               const SizedBox(width: 10),
               const Text('All Branches'),
            ]),
          ),
          const PopupMenuDivider(),
          ...userScope.branchIds.map((branchId) => PopupMenuItem<String>(
            value: branchId,
            child: Row(children: [
               Icon(branchFilter.selectedBranchId == branchId ? Icons.check_circle : Icons.circle_outlined, size:18, color: branchFilter.selectedBranchId == branchId ? Colors.deepPurple : Colors.grey),
               const SizedBox(width: 10),
               Flexible(child: Text(branchFilter.getBranchName(branchId), overflow: TextOverflow.ellipsis)),
            ]),
          )),
        ],
        onSelected: (value) => branchFilter.selectBranch(value),
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
                _buildEnhancedStatusChip('Prepared',
                    AppConstants.statusPrepared, Icons.check_circle_outline_rounded),
                _buildEnhancedStatusChip('Served',
                    AppConstants.statusServed, Icons.restaurant_menu_rounded),
                _buildEnhancedStatusChip('Needs Assign',
                    AppConstants.statusNeedsAssignment, Icons.person_pin_circle_outlined),
                _buildEnhancedStatusChip('Rider Assigned',
                    AppConstants.statusRiderAssigned, Icons.delivery_dining_rounded),
                _buildEnhancedStatusChip('Picked Up',
                    AppConstants.statusPickedUp, Icons.local_shipping_rounded),
                _buildEnhancedStatusChip('Delivered',
                    AppConstants.statusDelivered, Icons.check_circle_rounded),
                _buildEnhancedStatusChip('Paid',
                    AppConstants.statusPaid, Icons.payments_rounded),
                _buildEnhancedStatusChip('Collected',
                    AppConstants.statusCollected, Icons.shopping_bag_rounded),
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
    // ✅ FIX: Use watch for both so screen reacts to branch changes from backend
    final userScope = context.watch<UserScopeService>();
    final branchFilter = context.watch<BranchFilterService>(); // Watch for filter changes

    // Get branches to filter by (respects branch selector)
    // When "All Branches" is selected (null), getFilterBranchIds returns userScope.branchIds
    final effectiveFilterIds = branchFilter.getFilterBranchIds(userScope.branchIds);

    // ✅ IMPROVED: Add RefreshIndicator for pull-to-refresh
    return RefreshIndicator(
      onRefresh: () async {
        // Force rebuild by triggering setState
        if (mounted) setState(() {});
        // Small delay to show refresh indicator
        await Future.delayed(const Duration(milliseconds: 300));
      },
      color: Colors.deepPurple,
      // ✅ FIX: Use getOrdersStreamMerged to handle both branchId and branchIds fields
      child: StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
        stream: _orderService.getOrdersStreamMerged(
          orderType: orderType,
          status: _selectedStatus,
          userScope: userScope,
          filterBranchIds: effectiveFilterIds,
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
            // ✅ IMPROVED: User-friendly error display
            debugPrint('❌ OrdersScreen StreamBuilder error: ${snapshot.error}');
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
                  const SizedBox(height: 16),
                  Text(
                    'Unable to load orders',
                    style: TextStyle(color: Colors.grey[800], fontSize: 18),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Pull down to refresh',
                    style: TextStyle(color: Colors.grey[500], fontSize: 14),
                  ),
                ],
              ),
            );
          }

          final docs = snapshot.data ?? [];
          
          if (docs.isEmpty) {
            // ✅ IMPROVED: Wrap in ListView for pull-to-refresh to work on empty state
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.5,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.receipt_long_outlined,
                            size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text('No orders found.',
                            style: TextStyle(color: Colors.grey[600], fontSize: 18)),
                        const SizedBox(height: 8),
                        Text('Pull down to refresh.',
                            style: TextStyle(color: Colors.grey[400], fontSize: 14)),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }

          return ListView.separated(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(), // ✅ Enable pull-down even with items
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
      ),
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

  // ✅ IMPROVED: Use shared StatusUtils (removed duplicate code)
  Color _getStatusColor(String status) => StatusUtils.getColor(status);

  Color _getStatusColorForOrderType(String status, String orderType) =>
      StatusUtils.getColorForOrderType(status, orderType);


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
                // ✅ IMPROVED: Add loading indicator
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Container(
                    height: 200,
                    color: Colors.grey.shade200,
                    child: Center(
                      child: CircularProgressIndicator(
                        value: loadingProgress.expectedTotalBytes != null
                            ? loadingProgress.cumulativeBytesLoaded /
                                loadingProgress.expectedTotalBytes!
                            : null,
                        strokeWidth: 2,
                        color: Colors.red.shade400,
                      ),
                    ),
                  );
                },
                // ✅ IMPROVED: Better error display
                errorBuilder: (context, error, stackTrace) => Container(
                  height: 100,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.broken_image, color: Colors.grey, size: 32),
                      SizedBox(height: 4),
                      Text('Image unavailable', 
                          style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ),
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

  Future<void> _assignRiderManually(BuildContext parentContext) async {
    // Capture the ScaffoldMessengerState BEFORE async operations
    // This ensures we have a valid reference even if the dialog dismisses
    final scaffoldMessenger = ScaffoldMessenger.of(parentContext);
    
    // data is not available here, accessing widget.order.data()
    final data = widget.order.data();
    // ROBUST BRANCH ID EXTRACTION
    // Try top-level branchId -> branchIds[0] -> items[0].branchId
    String? orderBranchId = data['branchId']?.toString();
    
    if (orderBranchId == null && data['branchIds'] is List && (data['branchIds'] as List).isNotEmpty) {
      orderBranchId = data['branchIds'][0].toString();
    }
    
    // Fallback: Check items for Pickup/Dine-in orders
    if (orderBranchId == null && data['items'] is List && (data['items'] as List).isNotEmpty) {
       final firstItem = data['items'][0];
       if (firstItem is Map && firstItem['branchId'] != null) {
         orderBranchId = firstItem['branchId'].toString();
       }
    }
    
    // Final Fallback for SuperAdmin or malformed data: Use current user's first branch
    if (orderBranchId == null) {
      final userScope = Provider.of<UserScopeService>(parentContext, listen: false);
      if (userScope.branchIds.isNotEmpty) {
        orderBranchId = userScope.branchIds.first;
      }
    }

    final riderId = await showDialog<String>(
      context: parentContext,
      builder: (dialogContext) =>
          _RiderSelectionDialog(currentBranchId: orderBranchId),
    );

    if (riderId != null && riderId.isNotEmpty) {
      setState(() => _isAssigning = true);

      final result = await RiderAssignmentService.manualAssignRider(
        orderId: widget.order.id,
        riderId: riderId,
      );

      if (mounted) {
        setState(() => _isAssigning = false);
        
        // Use the pre-captured ScaffoldMessengerState (always valid)
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: result.backgroundColor,
          ),
        );
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
    final String orderType = widget.orderType;
    final String? riderId = data['riderId'];
    
    // Get branch info (Moved here for access in buttons)
    // Get branch info (Moved here for access in buttons)
    final branchId = (data['branchIds'] is List && (data['branchIds'] as List).isNotEmpty)
            ? data['branchIds'][0].toString()
            : null;

    // Use normalized order type for consistent comparison
    final bool isDelivery = AppConstants.isDeliveryOrder(orderType);
    final bool isDineIn = AppConstants.isDineInOrder(orderType);
    // Note: Pickup/Takeaway handled via !isDelivery && !isDineIn check


    final bool isAutoAssigning =
        data.containsKey('autoAssignStarted') && isDelivery;
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
          onPressed: () async {
            await widget.onStatusChange(
                widget.order.id, AppConstants.statusPreparing);

            // ✅ FIX: Explicitly start auto-assignment for delivery orders
            // This ensures the workflow is triggered immediately
            if (isDelivery) {
              await RiderAssignmentService.autoAssignRider(
                orderId: widget.order.id,
              );
            }
          },
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

    // 2. Order-type-specific flow logic
    // ========================================
    
    // DELIVERY: preparing → needs_rider_assignment → rider_assigned → pickedUp → delivered
    // PICKUP (prepaid): preparing → prepared → collected
    // TAKEAWAY (pay at counter): preparing → prepared → paid
    // DINE-IN: preparing → prepared → served → paid
    
    final bool isPickup = AppConstants.normalizeOrderType(orderType) == AppConstants.orderTypePickup;
    final bool isTakeaway = AppConstants.normalizeOrderType(orderType) == AppConstants.orderTypeTakeaway;
    
    if (!isDelivery) {
      // ===== NON-DELIVERY ORDER FLOWS =====
      
      // Step A: Mark as Prepared (Preparing → Prepared)
      if (status == AppConstants.statusPreparing) {
        buttons.add(
          ElevatedButton.icon(
            icon: const Icon(Icons.check_circle_outlined, size: 16),
            label: const Text('Mark Prepared'),
            onPressed: () => widget.onStatusChange(
                widget.order.id, AppConstants.statusPrepared),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal.shade600,
              foregroundColor: Colors.white,
              padding: btnPadding,
              minimumSize: btnMinSize,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        );
      }
      
      // Step B: Order-type-specific next action after Prepared
      if (status == AppConstants.statusPrepared) {
        if (isDineIn) {
          // DINE-IN: Prepared → Served
          buttons.add(
            ElevatedButton.icon(
              icon: const Icon(Icons.restaurant_menu, size: 16),
              label: const Text('Mark Served'),
              onPressed: () => widget.onStatusChange(
                  widget.order.id, AppConstants.statusServed),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade600,
                foregroundColor: Colors.white,
                padding: btnPadding,
                minimumSize: btnMinSize,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          );
        } else if (isPickup) {
          // PICKUP: Check payment method
          // - Prepaid (online payment): Prepared → Collected
          // - Cash on pickup: Prepared → Paid
          final String paymentMethod = (data['payment_method'] ?? data['paymentMethod'] ?? '').toString().toLowerCase();
          final bool isPrepaid = paymentMethod == 'online' || 
                                  paymentMethod == 'card' || 
                                  paymentMethod == 'prepaid' ||
                                  paymentMethod == 'apple_pay' ||
                                  paymentMethod == 'google_pay';
          
          if (isPrepaid) {
            // Prepaid pickup: Just mark as collected
            buttons.add(
              ElevatedButton.icon(
                icon: const Icon(Icons.shopping_bag_outlined, size: 16),
                label: const Text('Collected'),
                onPressed: () => widget.onStatusChange(
                    widget.order.id, AppConstants.statusCollected),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  foregroundColor: Colors.white,
                  padding: btnPadding,
                  minimumSize: btnMinSize,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            );
          } else {
            // Cash on pickup: Need to collect payment
            buttons.add(
              ElevatedButton.icon(
                icon: const Icon(Icons.payments, size: 16),
                label: const Text('Paid & Collected'),
                onPressed: () => widget.onStatusChange(
                    widget.order.id, AppConstants.statusPaid),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade700,
                  foregroundColor: Colors.white,
                  padding: btnPadding,
                  minimumSize: btnMinSize,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            );
          }
        } else if (isTakeaway) {
          // TAKEAWAY: Prepared → Paid
          buttons.add(
            ElevatedButton.icon(
              icon: const Icon(Icons.payments, size: 16),
              label: const Text('Mark Paid'),
              onPressed: () => widget.onStatusChange(
                  widget.order.id, AppConstants.statusPaid),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade700,
                foregroundColor: Colors.white,
                padding: btnPadding,
                minimumSize: btnMinSize,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          );
        }
      }
      
      // Step C: Dine-in Served → Paid
      if (status == AppConstants.statusServed && isDineIn) {
        buttons.add(
          ElevatedButton.icon(
            icon: const Icon(Icons.payments, size: 16),
            label: const Text('Mark Paid'),
            onPressed: () => widget.onStatusChange(
                widget.order.id, AppConstants.statusPaid),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade700,
              foregroundColor: Colors.white,
              padding: btnPadding,
              minimumSize: btnMinSize,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        );
      }
      
      // LEGACY SUPPORT: Handle old orders stuck on needs_rider_assignment
      // This ensures backward compatibility with orders created before this update
      if (status == AppConstants.statusNeedsAssignment) {
        buttons.add(
          ElevatedButton.icon(
            icon: Icon(isDineIn ? Icons.restaurant_menu : Icons.local_mall, size: 16),
            label: Text(isDineIn ? 'Mark Served' : (isPickup ? 'Collected' : 'Mark Paid')),
            onPressed: () => widget.onStatusChange(
                widget.order.id, 
                isDineIn ? AppConstants.statusServed : 
                  (isPickup ? AppConstants.statusCollected : AppConstants.statusPaid)),
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

    // 4. Order Completion and Assignment Logic (ONLY for delivery orders)
    if (isDelivery) {
      final bool canAssign = (status == AppConstants.statusPreparing ||
          needsManualAssignment);

      // Only show assignment buttons if no rider is currently assigned
      if (canAssign && !isAutoAssigning && (riderId == null || riderId.isEmpty)) {
        buttons.add(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. Auto Assign Button (New)
              ElevatedButton.icon(
                icon: const Icon(Icons.autorenew, size: 16),
                label: const Text('Auto Assign'),
                onPressed: () async {
                  // Trigger auto-assignment
                  final success = await RiderAssignmentService.autoAssignRider(
                    orderId: widget.order.id,
                  );
                  
                  if (mounted) {
                    if (success) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Auto-assignment started! Finding nearest rider...'),
                          backgroundColor: Colors.blue,
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Could not start auto-assignment. Check conditions.'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple.shade600,
                  foregroundColor: Colors.white,
                  padding: btnPadding,
                  minimumSize: btnMinSize,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(width: 8),
              
              // 2. Manual Assignment Button
              ElevatedButton.icon(
                icon: const Icon(Icons.person_add, size: 16),
                label: Text(
                    needsManualAssignment ? 'Assign Manually' : 'Manual Assign'),
                onPressed: () => _assignRiderManually(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                  needsManualAssignment ? Colors.orange : Colors.grey.shade700,
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

    // 5. Return Logic (For Pickup/Dine-in ONLY) - Post-Completion
    if (!isDelivery && status == AppConstants.statusDelivered) {
       buttons.add(
        ElevatedButton.icon(
          icon: const Icon(Icons.assignment_return, size: 16),
          label: const Text('Return / Exchange'),
          onPressed: () async {
            final result = await showDialog<Map<String, dynamic>>(
              context: context,
              builder: (context) => const _ReturnOptionsDialog(),
            );

            if (result != null) {
              final type = result['type'];
              final reason = result['reason'];
              
              if (type == 'exchange') {
                // For exchange, we need to mark it as exchange first so revenue isn't lost
                // We do this direct update to avoid changing the method signature of onStatusChange everywhere
                await FirebaseFirestore.instance
                    .collection(AppConstants.collectionOrders)
                    .doc(widget.order.id)
                    .update({
                      'isExchange': true,
                      'exchangeDetails': {
                        'reason': reason,
                        'timestamp': FieldValue.serverTimestamp(),
                        // 'adminId': ... (could add user email if available in this context)
                      }
                    });
                    
                widget.onStatusChange(
                  widget.order.id, 
                  AppConstants.statusPreparing, // Reset to Preparing
                  reason: "Exchange: $reason"
                );
              } else {
                // Refund
                widget.onStatusChange(
                  widget.order.id, 
                  AppConstants.statusRefunded,
                  reason: reason
                );
              }
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.pink,
            foregroundColor: Colors.white,
            padding: btnPadding,
            minimumSize: btnMinSize,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );
    }

    // 5. Cancel Order Logic (hide for terminal statuses)
    if (status != AppConstants.statusCancelled &&
        status != AppConstants.statusDelivered &&
        status != AppConstants.statusPaid &&
        status != AppConstants.statusCollected &&
        status != AppConstants.statusRefunded) {
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

  // ✅ IMPROVED: Use shared StatusUtils (removed duplicate code)
  String _getStatusDisplayText(String status, {String? orderType}) =>
      StatusUtils.getDisplayText(status, orderType: orderType);

  double _getStatusFontSize(String status, {String? orderType}) =>
      StatusUtils.getFontSize(status, orderType: orderType);


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

    final orderNumber = OrderNumberHelper.getDisplayNumber(data, orderId: widget.order.id);
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

    // Get branch info for badge
    // Get branch info for badge
    final branchId = (data['branchIds'] is List && (data['branchIds'] as List).isNotEmpty)
            ? data['branchIds'][0].toString()
            : null;
    final userScope = context.read<UserScopeService>();
    // Only show branch badge if user has access to multiple branches
    final showBranchBadge = branchId != null && userScope.branchIds.length > 1;

    // --- PAYMENT METHOD DETECTION ---
    final String paymentMethod = (data['payment_method'] ?? data['paymentMethod'] ?? '').toString().toLowerCase();
    final bool isCashPayment = paymentMethod == 'cash' || 
                                paymentMethod == 'cod' || 
                                paymentMethod == 'cash_on_delivery' ||
                                paymentMethod.isEmpty; // Treat empty as cash for safety
    final bool isPrepaid = paymentMethod == 'online' || 
                           paymentMethod == 'card' || 
                           paymentMethod == 'prepaid' ||
                           paymentMethod == 'apple_pay' ||
                           paymentMethod == 'google_pay';

    // --- BANNER LOGIC ---
    Color? bannerColor;
    String? bannerText;
    IconData? bannerIcon;
    bool showBanner = false;

    // Priority 1: Pending refund (highest priority)
    if (hasPendingRefund) {
      bannerColor = Colors.red;
      bannerText = 'RETURN REQUEST';
      bannerIcon = Icons.report_problem_outlined;
      showBanner = true;
    } 
    // Priority 2: Refunded order
    else if (status == AppConstants.statusRefunded || status == 'refunded') {
      bannerColor = Colors.pink;
      bannerText = 'RETURNED ORDER';
      bannerIcon = Icons.assignment_return_outlined;
      showBanner = true;
    } 
    // Priority 3: Exchange order
    else if (data['isExchange'] == true) {
      bannerColor = Colors.teal;
      bannerText = 'EXCHANGE ORDER';
      bannerIcon = Icons.swap_horiz_outlined;
      showBanner = true;
    }
    // Priority 4: Cash payment (only for active orders that need payment collection)
    else if (isCashPayment && 
             !AppConstants.isTerminalStatus(status) && 
             status != AppConstants.statusCancelled) {
      bannerColor = Colors.orange.shade700;
      bannerText = '💵 CASH PAYMENT';
      bannerIcon = Icons.attach_money;
      showBanner = true;
    }
    // Priority 5: Auto-assigning rider (delivery orders searching for riders)
    else if (isAutoAssigning) {
      bannerColor = Colors.blue.shade600;
      bannerText = '🔍 FINDING RIDER...';
      bannerIcon = Icons.delivery_dining;
      showBanner = true;
    }
    // Priority 6: Needs manual assignment (auto-assignment failed)
    else if (needsManualAssignment) {
      bannerColor = Colors.deepOrange.shade600;
      bannerText = '⚠️ NEEDS RIDER ASSIGNMENT';
      bannerIcon = Icons.person_pin_circle_outlined;
      showBanner = true;
    }

    return Container(
      clipBehavior: Clip.antiAlias, // Ensure banner doesn't overflow rounded corners
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
          if (showBanner) // ✅ Dynamic highlight
            BoxShadow(
              color: bannerColor!.withOpacity(0.2),
              blurRadius: 15,
              spreadRadius: 1,
              offset: const Offset(0, 0),
            ),
        ],
        border: showBanner 
            ? Border.all(color: bannerColor!, width: 2) // ✅ Dynamic border
            : widget.isHighlighted
                ? Border.all(color: Colors.blue, width: 2)
                : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showBanner) // ✅ DYNAMIC BANNER
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 6),
              color: bannerColor,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(bannerIcon, color: Colors.white, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    bannerText!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          Theme(
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
                    if (showBranchBadge) ...[ 
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          // Branch badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.grey.withOpacity(0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.store, size: 10, color: Colors.grey[700]),
                                const SizedBox(width: 4),
                                Builder(builder: (context) {
                                  final branchFilter = context.watch<BranchFilterService>();
                                  return Text(
                                    branchFilter.getBranchName(branchId!),
                                    style: TextStyle(
                                      color: Colors.grey[800],
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          // Payment method badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isCashPayment 
                                  ? Colors.orange.withOpacity(0.15) 
                                  : Colors.green.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: isCashPayment 
                                    ? Colors.orange.withOpacity(0.5) 
                                    : Colors.green.withOpacity(0.5),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isCashPayment ? Icons.attach_money : Icons.credit_card,
                                  size: 10,
                                  color: isCashPayment ? Colors.orange[800] : Colors.green[800],
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  AppConstants.getPaymentDisplayText(paymentMethod),
                                  style: TextStyle(
                                    color: isCashPayment ? Colors.orange[900] : Colors.green[900],
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                    // Show payment badge even without branch badge
                    if (!showBranchBadge) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isCashPayment 
                              ? Colors.orange.withOpacity(0.15) 
                              : Colors.green.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: isCashPayment 
                                ? Colors.orange.withOpacity(0.5) 
                                : Colors.green.withOpacity(0.5),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isCashPayment ? Icons.attach_money : Icons.credit_card,
                              size: 10,
                              color: isCashPayment ? Colors.orange[800] : Colors.green[800],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              AppConstants.getPaymentDisplayText(paymentMethod),
                              style: TextStyle(
                                color: isCashPayment ? Colors.orange[900] : Colors.green[900],
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (isAutoAssigning) ...[
                      const SizedBox(height: 4),
                      const Text('Auto-assigning rider...',
                          style: TextStyle(
                              color: Colors.blue,
                              fontSize: 11,
                              fontWeight: FontWeight.w500)),
                    ],
                    // Only show "needs manual assignment" badge for delivery orders
                    if (needsManualAssignment && orderTypeLower == 'delivery') ...[
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
                          color: _getStatusColorForOrderType(status, orderTypeLower))),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(_getStatusDisplayText(status, orderType: orderTypeLower),
                        style: TextStyle(
                            color: _getStatusColorForOrderType(status, orderTypeLower),
                            fontWeight: FontWeight.bold,
                            fontSize: _getStatusFontSize(status, orderType: orderTypeLower),
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
        ],
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
    // Capture references BEFORE async operations
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    
    final userScope = context.read<UserScopeService>();
    final currentBranchId = userScope.branchId;

    final riderId = await showDialog<String>(
      context: context,
      builder: (dialogContext) =>
          _RiderSelectionDialog(currentBranchId: currentBranchId),
    );

    if (riderId != null && riderId.isNotEmpty) {
      setState(() {
        _isLoading = true;
      });

      // ✅ FIX: Uses Transaction-based assignment to prevent Double-Assign bug
      final result = await RiderAssignmentService.manualAssignRider(
        orderId: orderId,
        riderId: riderId,
      );

      if (mounted) {
        setState(() => _isLoading = false);
        
        // Use pre-captured ScaffoldMessengerState (safe across async gaps)
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: result.backgroundColor,
          ),
        );
        
        if (result.isSuccess) {
          navigator.pop(); // Close popup only on success
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
    final String riderId = data['riderId']?.toString() ?? '';

    // Use normalized order type for consistent comparison
    final bool isDelivery = AppConstants.isDeliveryOrder(orderType);
    final bool isDineIn = AppConstants.isDineInOrder(orderType);

    final bool isAutoAssigning =
        data.containsKey('autoAssignStarted') && isDelivery;
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

    // Show completion buttons for non-delivery orders when preparing OR needs_rider_assignment
    if (!isDelivery && (status == AppConstants.statusPreparing || needsManualAssignment)) {
      buttons.add(
        ElevatedButton.icon(
          icon: Icon(isDineIn ? Icons.restaurant_menu : Icons.local_mall, size: 16),
          label: Text(AppConstants.getCompletionButtonText(orderType)),
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

    // Rider assignment logic (ONLY for delivery orders)
    if (isDelivery) {
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

      // ✅ NEW: Admin Override - Allow marking as Picked Up if Rider fails to do so
      if (status == AppConstants.statusRiderAssigned) {
        buttons.add(
          ElevatedButton.icon(
            icon: const Icon(Icons.local_shipping, size: 16),
            label: const Text('Mark as Picked Up'),
            onPressed: () => updateOrderStatus(
                orderId, AppConstants.statusPickedUp),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
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
        // Show indicator with Stop button
        buttons.add(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.blue),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Auto-assigning...',
                  style: TextStyle(
                    color: Colors.blue,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () async {
                    await RiderAssignmentService.cancelAutoAssignment(orderId);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Auto-assignment stopped')),
                      );
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Stop',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
      
      // Show "Restart Auto-Assignment" for orders that need assignment but aren't auto-assigning
      if (needsManualAssignment && !isAutoAssigning && riderId.isEmpty) {
        buttons.add(
          OutlinedButton.icon(
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Restart Auto-Assignment'),
            onPressed: () async {
              final success = await RiderAssignmentService.autoAssignRider(orderId: orderId);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(success 
                        ? 'Auto-assignment restarted' 
                        : 'Failed to restart auto-assignment'),
                    backgroundColor: success ? Colors.green : Colors.red,
                  ),
                );
              }
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.blue,
              side: const BorderSide(color: Colors.blue),
              padding: btnPadding,
              minimumSize: btnMinSize,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
    final orderNumber = OrderNumberHelper.getDisplayNumber(data, orderId: widget.order.id);
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

  // ✅ IMPROVED: Use shared StatusUtils
  Color _getStatusColor(String status) => StatusUtils.getColor(status);
}

// CancellationReasonDialog is now imported from '../Widgets/CancellationDialog.dart'


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

class _ReturnOptionsDialog extends StatefulWidget {
  const _ReturnOptionsDialog({super.key});

  @override
  State<_ReturnOptionsDialog> createState() => _ReturnOptionsDialogState();
}

class _ReturnOptionsDialogState extends State<_ReturnOptionsDialog> {
  final TextEditingController _reasonController = TextEditingController();
  final List<String> _commonReasons = [
    'Quality Issue',
    'Wrong Item(s)',
    'Missing Item(s)',
    'Customer Complaint',
    'Packaging Issue',
    'Other'
  ];
  String? _selectedReason;
  String _returnType = 'refund'; // 'refund' or 'exchange'

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.assignment_return, color: Colors.pink),
          SizedBox(width: 8),
          Text('Return Order'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Return Type Selector
            Row(
              children: [
                Expanded(
                  child: RadioListTile<String>(
                    title: const Text('Refund', style: TextStyle(fontSize: 14)),
                    value: 'refund',
                    groupValue: _returnType,
                    contentPadding: EdgeInsets.zero,
                    activeColor: Colors.pink,
                    onChanged: (value) => setState(() => _returnType = value!),
                  ),
                ),
                Expanded(
                  child: RadioListTile<String>(
                    title: const Text('Exchange', style: TextStyle(fontSize: 14)),
                    value: 'exchange',
                    groupValue: _returnType,
                    contentPadding: EdgeInsets.zero,
                    activeColor: Colors.teal,
                    onChanged: (value) => setState(() => _returnType = value!),
                  ),
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 8),
            
            const Text(
              'Select a reason:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _commonReasons.map((reason) {
                final isSelected = _selectedReason == reason;
                return ChoiceChip(
                  label: Text(reason),
                  selected: isSelected,
                  selectedColor: _returnType == 'exchange' 
                      ? Colors.teal.shade100 
                      : Colors.pink.shade100,
                  labelStyle: TextStyle(
                    color: isSelected 
                        ? (_returnType == 'exchange' ? Colors.teal.shade900 : Colors.pink.shade900) 
                        : Colors.black87,
                  ),
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedReason = reason;
                        if (reason != 'Other') {
                           _reasonController.text = reason;
                        } else {
                          _reasonController.clear();
                        }
                      } else {
                        _selectedReason = null;
                        _reasonController.clear();
                      }
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _reasonController,
              decoration: const InputDecoration(
                labelText: 'Details (Optional)',
                border: OutlineInputBorder(),
                hintText: 'Add more specific details...',
              ),
              maxLines: 2,
            ),
            if (_returnType == 'exchange') ...[
               const SizedBox(height: 12),
               Container(
                 padding: const EdgeInsets.all(8),
                 decoration: BoxDecoration(
                   color: Colors.teal.shade50,
                   borderRadius: BorderRadius.circular(8),
                   border: Border.all(color: Colors.teal.shade200),
                 ),
                 child: const Row(
                   children: [
                     Icon(Icons.info_outline, color: Colors.teal, size: 16),
                     SizedBox(width: 8),
                     Expanded(
                       child: Text(
                         'Exchange will reset order status to "Preparing". Revenue will NOT be deducted.',
                         style: TextStyle(fontSize: 12, color: Colors.teal),
                       ),
                     ),
                   ],
                 ),
               ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: _returnType == 'exchange' ? Colors.teal : Colors.pink,
            foregroundColor: Colors.white,
          ),
          onPressed: _selectedReason == null
              ? null
              : () {
                  Navigator.pop(context, {
                    'type': _returnType,
                    'reason': _reasonController.text
                  });
                },
          child: Text(_returnType == 'exchange' ? 'Confirm Exchange' : 'Confirm Refund'),
        ),
      ],
    );
  }
}