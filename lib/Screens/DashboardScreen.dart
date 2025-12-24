import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../Widgets/placeholders.dart';
import '../main.dart';
import 'OrdersScreen.dart';

class DashboardScreen extends StatelessWidget {
  final Function(int) onTabChange;

  const DashboardScreen({super.key, required this.onTabChange});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        centerTitle: true,
        title: const Text(
          'Dashboard',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.deepPurple,
            fontSize: 24,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildEnhancedStatCardsGrid(context),
            const SizedBox(height: 32),
            _buildSectionHeader('Recent Orders (Today)', Icons.receipt_long_outlined),
            const SizedBox(height: 16),
            _buildEnhancedRecentOrdersSection(context),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.deepPurple.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: Colors.deepPurple,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.deepPurple,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnhancedStatCardsGrid(BuildContext context) {
    final DateTime startOfToday = DateTime.now();
    final DateTime startOfDay = DateTime(startOfToday.year, startOfToday.month, startOfToday.day);
    final Timestamp startOfTodayTimestamp = Timestamp.fromDate(startOfDay);

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
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // First row of stat cards
          Row(
            children: [
              Expanded(
                child: _buildStatCardWrapper(
                  stream: FirebaseFirestore.instance
                      .collection('Orders')
                      .where('timestamp', isGreaterThanOrEqualTo: startOfTodayTimestamp)
                      .snapshots(),
                  builder: (context, snapshot) {
                    final count = snapshot.hasData ? snapshot.data!.docs.length : 0;
                    return _EnhancedStatCard(
                      title: "Today's Orders",
                      value: count.toString(),
                      icon: Icons.shopping_bag_outlined,
                      color: Colors.blueAccent,
                      onTap: () => _navigateToOrders(context),
                    );
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildStatCardWrapper(
                  stream: FirebaseFirestore.instance
                      .collection('Drivers')
                      .where('isAvailable', isEqualTo: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    final count = snapshot.hasData ? snapshot.data!.docs.length : 0;
                    return _EnhancedStatCard(
                      title: 'Active Riders',
                      value: count.toString(),
                      icon: Icons.delivery_dining_outlined,
                      color: Colors.green,
                      onTap: () => _navigateToRiders(context),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Second row of stat cards
          Row(
            children: [
              Expanded(
                child: _buildStatCardWrapper(
                  stream: FirebaseFirestore.instance
                      .collection('Orders')
                      .where('timestamp', isGreaterThanOrEqualTo: startOfTodayTimestamp)
                      .snapshots(),
                  builder: (context, snapshot) {
                    double totalRevenue = 0;
                    if (snapshot.hasData) {
                      final billableStatuses = {'delivered', 'completed', 'paid'};
                      for (var doc in snapshot.data!.docs) {
                        final data = doc.data() as Map<String, dynamic>;
                        final status = (data['status'] ?? '').toString().toLowerCase();
                        if (billableStatuses.contains(status)) {
                          totalRevenue += (data['totalAmount'] as num? ?? 0).toDouble();
                        }
                      }
                    }
                    return _EnhancedStatCard(
                      title: 'Revenue',
                      value: 'QAR ${totalRevenue.toStringAsFixed(2)}',
                      icon: Icons.attach_money_outlined,
                      color: Colors.orangeAccent,
                      onTap: () => _navigateToAnalytics(context),
                    );
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildStatCardWrapper(
                  stream: FirebaseFirestore.instance
                      .collection('menu_items')
                      .where('isAvailable', isEqualTo: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    final count = snapshot.hasData ? snapshot.data!.docs.length : 0;
                    return _EnhancedStatCard(
                      title: 'Menu Items',
                      value: count.toString(),
                      icon: Icons.restaurant_menu,
                      color: Colors.purpleAccent,
                      onTap: () => _navigateToMenuManagement(context),
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

  void _navigateToOrders(BuildContext context) {
    OrderSelectionService.setSelectedOrder(
      orderId: null,
      orderType: null,
      status: 'all',
    );
    onTabChange(2);
  }

  void _navigateToRiders(BuildContext context) {
    onTabChange(3);
  }

  void _navigateToAnalytics(BuildContext context) {
    onTabChange(4);
  }

  void _navigateToMenuManagement(BuildContext context) {
    onTabChange(1);
  }

  Widget _buildStatCardWrapper({
    required Stream<QuerySnapshot<Map<String, dynamic>>> stream,
    required Widget Function(BuildContext, AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>>) builder,
  }) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _EnhancedLoadingStatCard();
        }
        if (snapshot.hasError) {
          return _EnhancedErrorStatCard(errorMessage: 'Error loading data');
        }
        return builder(context, snapshot);
      },
    );
  }

  Widget _buildEnhancedRecentOrdersSection(BuildContext context) {
    // ✅ 1. Get Start of Today for Filtering
    final DateTime now = DateTime.now();
    final DateTime startOfDay = DateTime(now.year, now.month, now.day);
    final Timestamp startOfTodayTimestamp = Timestamp.fromDate(startOfDay);

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
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Icon(
                  Icons.access_time_rounded,
                  color: Colors.deepPurple.shade400,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Latest Activity',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () => _navigateToOrders(context),
                  icon: Icon(
                    Icons.arrow_forward_rounded,
                    size: 16,
                    color: Colors.deepPurple.shade600,
                  ),
                  label: Text(
                    'View All',
                    style: TextStyle(
                      color: Colors.deepPurple.shade600,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.grey[200]),
          SizedBox(
            height: 320,
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('Orders')
                  .where('timestamp', isGreaterThanOrEqualTo: startOfTodayTimestamp) // ✅ 2. Filter by Today
                  .orderBy('timestamp', descending: true)
                  .limit(5)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation(Colors.deepPurple),
                      ),
                    ),
                  );
                }
                if (snapshot.hasError) {
                  return _buildErrorState('Error loading orders: ${snapshot.error}');
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return _buildEmptyState();
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: snapshot.data!.docs.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    var order = snapshot.data!.docs[index];
                    return _EnhancedOrderListItem(order: order);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                message,
                style: TextStyle(
                  color: Colors.red[600],
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              'No orders today',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'New orders will appear here',
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EnhancedStatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _EnhancedStatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 140,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.8), color],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            spreadRadius: 1,
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, size: 24, color: Colors.white),
                    ),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 16,
                      color: Colors.white.withOpacity(0.7),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        value,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withOpacity(0.9),
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EnhancedLoadingStatCard extends StatelessWidget {
  const _EnhancedLoadingStatCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 140,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation(Colors.deepPurple),
          strokeWidth: 2,
        ),
      ),
    );
  }
}

class _EnhancedErrorStatCard extends StatelessWidget {
  final String errorMessage;
  const _EnhancedErrorStatCard({required this.errorMessage});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 140,
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red[200]!),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, color: Colors.red[400], size: 24),
              const SizedBox(height: 4),
              Text(
                'Error',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.red[600],
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EnhancedOrderListItem extends StatelessWidget {
  final DocumentSnapshot order;

  const _EnhancedOrderListItem({required this.order});

  String _formatOrderType(String type) {
    switch (type) {
      case 'delivery': return 'Delivery';
      case 'takeaway': return 'Takeaway';
      case 'pickup': return 'Pick Up';
      case 'dine_in': return 'Dine-in';
      default: return 'Unknown Type';
    }
  }

  void _showOrderPopup(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => _OrderPopupDialog(order: order),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = order.data() as Map<String, dynamic>? ?? {};
    final String displayOrderNumber = data['dailyOrderNumber']?.toString() ??
        order.id.substring(0, 6).toUpperCase();
    final String rawOrderType = data['Order_type'] ?? 'delivery';
    final String formattedOrderType = _formatOrderType(rawOrderType);
    final String status = data['status'] ?? 'Unknown';
    final double totalAmount = (data['totalAmount'] as num? ?? 0).toDouble();
    final Timestamp? placedTimestamp = data['timestamp'];
    final String placedDate = placedTimestamp != null
        ? DateFormat('MMM d, hh:mm a').format(placedTimestamp.toDate())
        : 'N/A';

    final Color statusColor = _getStatusColor(status);

    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showOrderPopup(context),
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.receipt_long_outlined, color: statusColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              '#$displayOrderNumber',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              formattedOrderType,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Colors.blue.shade700,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              'QAR ${totalAmount.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.green,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              ' • $placedDate',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  constraints: const BoxConstraints(
                    maxWidth: 90,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _getStatusDisplayText(status),
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                      fontSize: _getStatusFontSize(status),
                    ),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
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

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending': return Colors.orange;
      case 'preparing': return Colors.teal;
      case 'prepared': return Colors.blueAccent;
      case 'pickedup': return Colors.purple;
      case 'delivered': return Colors.green;
      case 'cancelled': return Colors.red;
      case 'needs_rider_assignment': return Colors.orange;
      default: return Colors.grey;
    }
  }
}

class _OrderPopupDialog extends StatefulWidget {
  final DocumentSnapshot order;

  const _OrderPopupDialog({required this.order});

  @override
  State<_OrderPopupDialog> createState() => _OrderPopupDialogState();
}

class _OrderPopupDialogState extends State<_OrderPopupDialog> {
  // ✅ 3. Added Loading State
  bool _isLoading = false;

  Future<void> updateOrderStatus(String orderId, String newStatus) async {
    // ✅ Set Loading
    setState(() {
      _isLoading = true;
    });

    try {
      final Map<String, dynamic> updateData = {
        'status': newStatus,
      };

      if (newStatus == 'prepared') {
        updateData['timestamps.prepared'] = FieldValue.serverTimestamp();
      } else if (newStatus == 'delivered') {
        updateData['timestamps.delivered'] = FieldValue.serverTimestamp();
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

        // Clean up rider assignment if exists
        final orderDoc = await FirebaseFirestore.instance
            .collection('Orders')
            .doc(orderId)
            .get();
        final data = orderDoc.data() as Map<String, dynamic>? ?? {};
        final String? riderId = data['riderId'] as String?;

        if (riderId != null && riderId.isNotEmpty) {
          await FirebaseFirestore.instance
              .collection('Drivers')
              .doc(riderId)
              .update({
            'assignedOrderId': '',
            'isAvailable': true,
          });
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
            content: Text('Failed to update order status: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      // ✅ Stop Loading (only if still mounted and not popped)
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _assignRider(String orderId) async {
    final userScope = context.read<UserScopeService>();
    final currentBranchId = userScope.branchId;

    final rider = await showDialog<String>(
      context: context,
      builder: (context) => _RiderSelectionDialog(currentBranchId: currentBranchId),
    );

    if (rider != null && rider.isNotEmpty) {
      // ✅ Set Loading
      setState(() {
        _isLoading = true;
      });

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

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Rider "$rider" assigned to order!'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).pop();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to assign rider: $e'),
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
  }

  Widget _buildActionButtons(String status, String orderType, String orderId) {
    // ✅ 4. Check Loading State
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
    final bool isAutoAssigning = data.containsKey('autoAssignStarted');
    final bool needsManualAssignment = status == 'needs_rider_assignment';

    const EdgeInsets btnPadding = EdgeInsets.symmetric(horizontal: 14, vertical: 10);
    const Size btnMinSize = Size(0, 40);

    // --- UNIVERSAL ACTIONS ---

    // Print Receipt Button (for all statuses except pending and cancelled)
    final statusLower = status.toLowerCase();
    if (statusLower != 'pending' && statusLower != 'cancelled') {
      buttons.add(
        OutlinedButton.icon(
          icon: const Icon(Icons.print, size: 16),
          label: const Text('Reprint Receipt'),
          onPressed: () async {
            final freshDoc = await widget.order.reference.get();
            final freshData = freshDoc.data() as Map<String, dynamic>? ?? {};
            final currentStatus = (freshData['status'] as String?)?.toLowerCase() ?? '';

            if (currentStatus == 'cancelled') {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Cannot reprint a cancelled order.'),
                  backgroundColor: Colors.red,
                ),
              );
              return;
            }

            await printReceipt(context, freshDoc);
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

    // --- STATUS-BASED ACTIONS ---

    // Pending → Preparing
    if (status == 'pending') {
      buttons.add(
        ElevatedButton.icon(
          icon: const Icon(Icons.check, size: 16),
          label: const Text('Accept Order'),
          onPressed: () => updateOrderStatus(orderId, 'preparing'),
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

    // Preparing → Prepared
    if (status == 'preparing') {
      buttons.add(
        ElevatedButton.icon(
          icon: const Icon(Icons.done_all, size: 16),
          label: const Text('Mark as Prepared'),
          onPressed: () => updateOrderStatus(orderId, 'prepared'),
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

    // --- ORDER-TYPE SPECIFIC ACTIONS ---
    final orderTypeLower = orderType.toLowerCase();

    // PICKUP Orders
    if (orderTypeLower == 'pickup') {
      if (status == 'prepared') {
        buttons.add(
          ElevatedButton.icon(
            icon: const Icon(Icons.task_alt, size: 16),
            label: const Text('Mark as Delivered'),
            onPressed: () => updateOrderStatus(orderId, 'delivered'),
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
    // TAKEWAY & DINE-IN Orders
    else if (orderTypeLower == 'takeaway' || orderTypeLower == 'dine_in') {
      if (status == 'prepared') {
        buttons.add(
          ElevatedButton.icon(
            icon: const Icon(Icons.task_alt, size: 16),
            label: const Text('Mark as Picked Up'),
            onPressed: () => updateOrderStatus(orderId, 'delivered'),
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
    // DELIVERY Orders
    else if (orderTypeLower == 'delivery') {
      // Assign Rider for prepared orders or manual assignment needed
      if ((status == 'prepared' || needsManualAssignment) && !isAutoAssigning) {
        buttons.add(
          ElevatedButton.icon(
            icon: const Icon(Icons.delivery_dining, size: 16),
            label: Text(needsManualAssignment ? 'Assign Manually' : 'Assign Rider'),
            onPressed: () => _assignRider(orderId),
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

      // PickedUp → Delivered
      if (status == 'pickedUp') {
        buttons.add(
          ElevatedButton.icon(
            icon: const Icon(Icons.task_alt, size: 16),
            label: const Text('Mark as Delivered'),
            onPressed: () => updateOrderStatus(orderId, 'delivered'),
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

    // --- SPECIAL STATES ---

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

    // --- CANCEL ACTIONS ---

    // Cancel Order (only for pending and preparing orders)
    if (status == 'pending' || status == 'preparing') {
      buttons.add(
        ElevatedButton.icon(
          icon: const Icon(Icons.cancel, size: 16),
          label: const Text('Cancel Order'),
          onPressed: () => updateOrderStatus(orderId, 'cancelled'),
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

    // --- LAYOUT ---
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
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
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
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
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
      default:
        return Colors.grey;
    }
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

    final bool isAutoAssigning = data.containsKey('autoAssignStarted');
    final bool needsManualAssignment = status == 'needs_rider_assignment';

    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Order #$orderNumber',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.deepPurple,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          timestamp != null
                              ? DateFormat('MMM dd, yyyy hh:mm a').format(timestamp)
                              : 'No date',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _getStatusColor(status).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _getStatusColor(status).withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _getStatusColor(status),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          status.toUpperCase(),
                          style: TextStyle(
                            color: _getStatusColor(status),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Customer Details
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
                      _buildDetailRow(Icons.person, 'Customer:', data['customerName'] ?? 'N/A'),
                      _buildDetailRow(Icons.phone, 'Phone:', data['customerPhone'] ?? 'N/A'),
                      _buildDetailRow(
                        Icons.location_on,
                        'Address:',
                        '${data['deliveryAddress']?['street'] ?? ''}, ${data['deliveryAddress']?['city'] ?? ''}',
                      ),
                      if (data['riderId']?.isNotEmpty == true)
                        _buildDetailRow(Icons.delivery_dining, 'Rider:', data['riderId']),
                    ],
                    if (orderType == 'pickup') ...[
                      _buildDetailRow(Icons.store, 'Pickup Branch',
                          (data['branchIds'] is List && (data['branchIds'] as List).isNotEmpty)
                              ? (data['branchIds'] as List).first.toString()
                              : 'N/A'),
                    ],
                    if (orderType == 'takeaway') ...[
                      _buildDetailRow(
                        Icons.directions_car,
                        'Car Plate:',
                        (data['carPlateNumber']?.toString().isNotEmpty ?? false)
                            ? data['carPlateNumber']
                            : 'N/A',
                      ),
                      if ((data['specialInstructions']?.toString().isNotEmpty ?? false))
                        _buildDetailRow(Icons.note, 'Instructions:', data['specialInstructions']),
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

              // Ordered Items
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

              // Order Summary
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

              // Actions
              _buildSectionHeader('Actions', Icons.touch_app),
              const SizedBox(height: 16),
              _buildActionButtons(status, orderType, widget.order.id),

              const SizedBox(height: 10),

              // Close button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
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
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'Select Driver',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('Drivers')
              .where('isAvailable', isEqualTo: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }

            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return const Center(child: Text('No available drivers found.'));
            }

            // Filter drivers by branch ID
            final filteredDrivers = snapshot.data!.docs.where((driver) {
              final data = driver.data() as Map<String, dynamic>;
              final driverBranchIds = List<String>.from(data['branchIds'] ?? []);

              if (currentBranchId == null) return true;

              return driverBranchIds.contains(currentBranchId);
            }).toList();

            if (filteredDrivers.isEmpty) {
              return const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.person_off, size: 48, color: Colors.grey),
                    SizedBox(height: 8),
                    Text(
                      'No drivers available\nfor your branch',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              );
            }

            return ListView.separated(
              shrinkWrap: true,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemCount: filteredDrivers.length,
              itemBuilder: (context, index) {
                var driver = filteredDrivers[index];
                var data = driver.data() as Map<String, dynamic>;
                final driverId = driver.id;
                final String name = data['name'] ?? 'Unnamed Driver';
                final String contact = (data['phone']?.toString()) ??
                    data['email'] ??
                    'No contact info';
                final String? profileImage = data['profileImageUrl'];
                final String status = data['status'] ?? 'offline';
                final List<String> driverBranchIds = List<String>.from(data['branchIds'] ?? []);

                return Card(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                  color: Colors.grey.shade50,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    leading: CircleAvatar(
                      radius: 25,
                      backgroundColor: Colors.deepPurple.shade100,
                      backgroundImage:
                      (profileImage != null && profileImage.isNotEmpty)
                          ? NetworkImage(profileImage)
                          : null,
                      child: (profileImage == null || profileImage.isEmpty)
                          ? Icon(Icons.person,
                          color: Colors.deepPurple.shade400, size: 28)
                          : null,
                    ),
                    title: Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          contact,
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _getStatusColor(status).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: _getStatusColor(status).withOpacity(0.3)),
                              ),
                              child: Text(
                                status.toUpperCase(),
                                style: TextStyle(
                                  color: _getStatusColor(status),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (currentBranchId == null) ...[
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                                ),
                                child: Text(
                                  '${driverBranchIds.length} ${driverBranchIds.length == 1 ? 'branch' : 'branches'}',
                                  style: const TextStyle(
                                    color: Colors.blue,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                    onTap: () => Navigator.pop(context, driverId),
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'Cancel',
            style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'online':
        return Colors.green;
      case 'offline':
        return Colors.grey;
      case 'on_delivery':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }
}