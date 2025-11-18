import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
// import 'package:flutter/material.dart' as pw; // This line seems unused, commenting out.
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:provider/provider.dart';
import '../main.dart'; // Assuming navigatorKey is here
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Main screen for viewing and managing orders.
/// Filters orders based on the user's role (super_admin vs. branch_admin)
/// and the selected order type/status.
///
// final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>(); // This is already in main.dart

/// Main screen for viewing and managing orders.
/// Filters orders based on the user's role (super_admin vs. branch_admin)
/// and the selected order type/status.
import 'package:flutter/material.dart';

import 'package:intl/intl.dart';

/// Main screen for viewing and managing orders.
/// Filters orders based on the user's role (super_admin vs. branch_admin)
/// and the selected order type/status.
///
// final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>(); // This is already in main.dart

/// Main screen for viewing and managing orders.
/// Filters orders based on the user's role (super_admin vs. branch_admin)
/// and the selected order type/status.


import 'dart:async';

import 'dart:async';



class OrdersScreen extends StatefulWidget {
  @override
  _OrdersScreenState createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // --- FIX 1: REMOVED ALL NOTIFICATION LOGIC ---
  // The OrderNotificationService, initialized in your main.dart or
  // MainScreen.dart, is already responsible for new order sounds
  // and popups. This screen should not do it again.
  //
  // final OrderNotificationService _notificationService = OrderNotificationService(); // <- DELETED
  // StreamSubscription<QuerySnapshot>? _newOrdersSubscription; // <- DELETED
  // --- END FIX 1 ---

  // Manage selectedBranchId locally in this screen's state
  String _selectedBranchId = 'all';

  final List<String> _orderStatusTabs = [
    'pending',
    'preparing',
    'prepared',
    'rider_assigned',
    'out_for_delivery',
    'needs_rider_assignment', // Added for the new server flow
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _orderStatusTabs.length, vsync: this);

    // Simplified initState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final scopeService = Provider.of<UserScopeService>(context, listen: false);

        // Set default branch if user only has one
        if (!scopeService.isSuperAdmin && scopeService.branchIds.length == 1) {
          if (mounted) {
            setState(() {
              _selectedBranchId = scopeService.branchIds.first;
            });
          }
        }
      }
    });

    // _listenForNewOrders(); // <- DELETED
  }

  // --- FIX 1 (CONTINUED): REMOVED REDUNDANT METHOD ---
  // void _listenForNewOrders() { ... } // <- ENTIRE METHOD DELETED
  // --- END FIX 1 ---

  @override
  void dispose() {
    _tabController.dispose();
    // _newOrdersSubscription?.cancel(); // <- DELETED
    super.dispose();
  }

  Future<void> _updateOrderStatus(BuildContext context, String orderId, String newStatus) async {
    // This is the loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Center(child: CircularProgressIndicator());
      },
    );

    try {
      await FirebaseFirestore.instance.collection('Orders').doc(orderId).update({
        'status': newStatus,
        'timestamps.$newStatus': FieldValue.serverTimestamp(),
      });

      // This is the core logic. When status is 'preparing',
      // the Cloud Function will take over.

      Navigator.of(context).pop(); // Dismiss loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Order status updated to $newStatus')),
      );
    } catch (e) {
      Navigator.of(context).pop(); // Dismiss loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update status: $e')),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    // Get the correct service
    final scopeService = Provider.of<UserScopeService>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Live Orders'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: _orderStatusTabs.map((status) => Tab(text: status.toUpperCase().replaceAll('_', ' '))).toList(),
        ),
        actions: [
          // --- FIX 2: REBUILD DROPDOWN WITH STREAMBUILDER ---
          // This StreamBuilder fetches the Branch documents using the
          // 'branchIds' from your UserScopeService.
          StreamBuilder<QuerySnapshot>(
            // If super admin, get all branches. Otherwise, get only branches
            // matching the IDs from the scope service.
            stream: scopeService.isSuperAdmin
                ? FirebaseFirestore.instance.collection('Branch').snapshots()
                : (scopeService.branchIds.isEmpty
                ? Stream.empty() // Handle case where user has no branches
                : FirebaseFirestore.instance
                .collection('Branch')
                .where(FieldPath.documentId, whereIn: scopeService.branchIds)
                .snapshots()),
            builder: (context, snapshot) {
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                // If no branches, show nothing in the app bar
                return SizedBox.shrink();
              }

              // Create the list of DropdownMenuItem widgets from the documents
              var branchItems = snapshot.data!.docs.map((doc) {
                // Assuming branch documents have 'name' field
                var branchName = (doc.data() as Map<String, dynamic>)['name'] ?? 'Unknown Branch';
                return DropdownMenuItem<String>(
                  value: doc.id,
                  child: Text(branchName, style: TextStyle(color: Colors.white)),
                );
              }).toList();

              // Add the "All Branches" option ONLY if super admin
              if (scopeService.isSuperAdmin) {
                branchItems.insert(0, DropdownMenuItem<String>(
                  value: 'all',
                  child: Text('All Branches', style: TextStyle(color: Colors.white)),
                ));
              }

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: DropdownButton<String>(
                  value: _selectedBranchId,
                  dropdownColor: Theme.of(context).appBarTheme.backgroundColor,
                  icon: Icon(Icons.store, color: Colors.white),
                  underline: Container(),
                  onChanged: (String? newValue) {
                    if (newValue != null) {
                      setState(() {
                        _selectedBranchId = newValue; // Update local state
                      });
                      // No need to call _listenForNewOrders,
                      // the OrderList StreamBuilder will rebuild automatically
                    }
                  },
                  items: branchItems,
                ),
              );
            },
          ),
          // --- END FIX 2 ---
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: _orderStatusTabs.map((status) {
          return OrderList(
            status: status,
            onUpdateStatus: _updateOrderStatus,
            selectedBranchId: _selectedBranchId, // Pass local state down
          );
        }).toList(),
      ),
    );
  }
}

//
// --- NO CHANGES BELOW THIS LINE ---
//

class OrderList extends StatelessWidget {
  final String status;
  final String selectedBranchId;
  final Function(BuildContext, String, String) onUpdateStatus;

  OrderList({required this.status, required this.onUpdateStatus, required this.selectedBranchId});

  @override
  Widget build(BuildContext context) {
    Query query = FirebaseFirestore.instance
        .collection('Orders')
        .where('status', isEqualTo: status);

    // Safely add ordering
    if (status == 'pending' || status == 'preparing' || status =='prepared' || status == 'rider_assigned' || status == 'out_for_delivery' || status == 'needs_rider_assignment') {
      query = query.orderBy('timestamps.$status', descending: true);
    } else {
      // Fallback for statuses without a dedicated timestamp
      query = query.orderBy('timestamps.pending', descending: true);
    }

    // Filter by branch
    if (selectedBranchId != 'all') {
      query = query.where('branchId', isEqualTo: selectedBranchId);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          print("OrderList Error (${status}): ${snapshot.error}");
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(child: Text('No $status orders.'));
        }

        return ListView.builder(
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            var order = snapshot.data!.docs[index];
            return OrderCard(
              order: order,
              onUpdateStatus: onUpdateStatus,
            );
          },
        );
      },
    );
  }
}

class OrderCard extends StatelessWidget {
  final QueryDocumentSnapshot order;
  final Function(BuildContext, String, String) onUpdateStatus;

  OrderCard({required this.order, required this.onUpdateStatus});

  String _formatTimestamp(Map<String, dynamic> data) {
    var status = data['status'] ?? 'pending';
    var timestamps = data['timestamps'] as Map<String, dynamic>?;

    Timestamp? timestamp;
    if (timestamps != null && timestamps.containsKey(status)) {
      timestamp = timestamps[status] as Timestamp?;
    }

    // Fallback
    timestamp ??= timestamps?['pending'] as Timestamp?;

    if (timestamp != null) {
      return DateFormat('g:i a, d MMM').format(timestamp.toDate());
    }
    return 'No time data';
  }

  @override
  Widget build(BuildContext context) {
    var data = order.data() as Map<String, dynamic>;
    var items = (data['items'] as List<dynamic>?) ?? [];

    return Card(
      margin: EdgeInsets.all(10),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    'Order #${data['dailyOrderNumber'] ?? 'N/A'}',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  'QAR ${data['totalAmount']?.toStringAsFixed(2) ?? '0.00'}',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor),
                ),
              ],
            ),
            SizedBox(height: 8),
            Text('Customer: ${data['customerName'] ?? 'N/A'}'),
            Text('Type: ${data['Order_type'] ?? 'N/A'}'),
            if (data['status'] == 'needs_rider_assignment' && data['assignmentNotes'] != null)
              Text('Notes: ${data['assignmentNotes']}', style: TextStyle(color: Colors.red, fontStyle: FontStyle.italic)),
            SizedBox(height: 8),
            Text(
              'Time: ${_formatTimestamp(data)}',
              style: TextStyle(color: Colors.grey[700]),
            ),
            Divider(height: 20),
            ...items.map((item) {
              if (item is Map) {
                return ListTile(
                  title: Text(item['name'] ?? 'Item'),
                  subtitle: Text('Qty: ${item['quantity']}'),
                  trailing: Text('QAR ${item['price']?.toStringAsFixed(2) ?? '0.00'}'),
                );
              }
              return SizedBox.shrink();
            }).toList(),
            SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _buildActionButtons(context, order.id, data['status']),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildActionButtons(BuildContext context, String orderId, String status) {
    List<Widget> buttons = [];

    switch (status) {
      case 'pending':
        buttons.add(
          ElevatedButton(
            child: Text('Accept Order'),
            onPressed: () => onUpdateStatus(context, orderId, 'preparing'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
          ),
        );
        buttons.add(
          ElevatedButton(
            child: Text('Reject Order'),
            onPressed: () => onUpdateStatus(context, orderId, 'rejected'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          ),
        );
        break;
      case 'preparing':
        buttons.add(
          ElevatedButton(
            child: Text('Order Prepared'),
            onPressed: () => onUpdateStatus(context, orderId, 'prepared'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
          ),
        );
        break;
      case 'prepared':
        buttons.add(
            Text('Waiting for rider...', style: TextStyle(fontStyle: FontStyle.italic))
        );
        break;
      case 'rider_assigned':
        buttons.add(
          ElevatedButton(
            child: Text('Out for Delivery'),
            onPressed: () => onUpdateStatus(context, orderId, 'out_for_delivery'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
          ),
        );
        break;
      case 'out_for_delivery':
        buttons.add(
          ElevatedButton(
            child: Text('Mark as Delivered'),
            onPressed: () => onUpdateStatus(context, orderId, 'delivered'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
          ),
        );
        break;
      case 'needs_rider_assignment':
        buttons.add(
            Text('Go to "Needs Assignment" tab', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))
        );
        break;
    }

    return buttons;
  }
}


class _OrderCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> order;
  final String orderType;
  final Function(BuildContext, String, String) onStatusChange;
  // --- PARAMETER REMOVED ---
  // final Function(BuildContext, String) onAssigned;
  final bool isHighlighted;

  const _OrderCard({
    super.key,
    required this.order,
    required this.orderType,
    required this.onStatusChange,
    // required this.onAssigned, // --- PARAMETER REMOVED ---
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
    // --- VARIABLE NO LONGER NEEDED ---
    // final bool needsManualAssignment = status == 'needs_rider_assignment';

    // Consistent styling for all buttons
    const EdgeInsets btnPadding =
    EdgeInsets.symmetric(horizontal: 14, vertical: 10);
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
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
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
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        );
      }
    }
    // **Flow for DELIVERY orders**
    else if (orderTypeLower == 'delivery') {
      // --- BUTTON LOGIC REMOVED ---
      // if ((status == 'prepared' || needsManualAssignment) && !isAutoAssigning) {
      //   buttons.add(
      //     ElevatedButton.icon(
      //       icon: const Icon(Icons.delivery_dining, size: 16),
      //       label:
      //       Text(needsManualAssignment ? 'Assign Manually' : 'Assign Rider'),
      //       onPressed: () => onAssigned(context, order.id), // <-- This is removed
      //       style: ElevatedButton.styleFrom(
      //         backgroundColor:
      //         needsManualAssignment ? Colors.orange : Colors.blue,
      //         foregroundColor: Colors.white,
      //         padding: btnPadding,
      //         minimumSize: btnMinSize,
      //         shape: RoundedRectangleBorder(
      //             borderRadius: BorderRadius.circular(12)),
      //       ),
      //     ),
      //   );
      // }

      // We still keep the "Mark as Delivered" button for 'pickedUp' status
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
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
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
                  decoration: const BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
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
                        color: isHighlighted
                            ? Colors.blue.shade800
                            : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      timestamp != null
                          ? DateFormat('MMM dd, yyyy hh:mm a').format(timestamp)
                          : 'No date',
                      style: TextStyle(
                          color: isHighlighted
                              ? Colors.blue.shade600
                              : Colors.grey[600],
                          fontSize: 12),
                    ),
                    if (isAutoAssigning) ...[
                      const SizedBox(height: 4),
                      const Text(
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
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: Colors.orange.withOpacity(0.3)),
                        ),
                        child: const Text(
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
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                          border:
                          Border.all(color: Colors.blue.withOpacity(0.3)),
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
              maxWidth: MediaQuery.of(context).size.width *
                  0.3, // Limit width to 30% of screen
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
                        data['branchIds']?.join(', ') ?? 'N/A'), // Fixed to show branchIds
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
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500)),
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
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500),
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




// --- ADDED: Import for loading font assets ---

Future<void> printReceipt(
    BuildContext context, DocumentSnapshot orderDoc) async {
  try {
    // --- ADDED: Load Arabic Font ---
    // Make sure this path matches your file location in Step 1
    final fontData =
    await rootBundle.load("assets/fonts/NotoSansArabic-Regular.ttf");
    final pw.Font arabicFont = pw.Font.ttf(fontData);
    // --- END FONT ---

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async {
        // --- 1. Extract Order Data ---
        final Map<String, dynamic> order =
        Map<String, dynamic>.from(orderDoc.data() as Map);

        final List<dynamic> rawItems = (order['items'] ?? []) as List<dynamic>;
        final List<Map<String, dynamic>> items = rawItems.map((e) {
          final m = Map<String, dynamic>.from(e as Map);
          final name = (m['name'] ?? 'Item').toString();

          // --- UPDATED: This is the logic you asked for ---
          // It looks for 'name_ar' and falls back to the English 'name' if not found.
          final nameAr = (m['name_ar'] ?? name).toString();
          // --- End update ---

          final qtyRaw = m.containsKey('quantity') ? m['quantity'] : m['qty'];
          final qty = int.tryParse(qtyRaw?.toString() ?? '1') ?? 1;
          final priceRaw = m['price'] ?? m['unitPrice'] ?? m['amount'];
          final double price = switch (priceRaw) {
            num n => n.toDouble(),
            _ => double.tryParse(priceRaw?.toString() ?? '0') ?? 0.0,
          };

          // --- UPDATED: Add Arabic name to item map ---
          return {'name': name, 'name_ar': nameAr, 'qty': qty, 'price': price};
        }).toList();

        final double subtotal = (order['subtotal'] as num?)?.toDouble() ?? 0.0;

        // --- REQUIREMENT 1: Discount is already fetched here ---
        final double discount =
            (order['discountAmount'] as num?)?.toDouble() ?? 0.0;
        // ---

        final double totalAmount =
            (order['totalAmount'] as num?)?.toDouble() ?? 0.0;
        final double calculatedSubtotal =
        items.fold(0, (sum, item) => sum + (item['price'] * item['qty']));
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
            .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
            .join(' ');

        // --- ADDED: Arabic translations (you can expand this) ---
        final Map<String, String> orderTypeTranslations = {
          'Delivery': 'توصيل',
          'Takeaway': 'سفري',
          'Pickup': 'يستلم',
          'Dine-in': 'تناول الطعام في الداخل',
        };
        final String displayOrderTypeAr = orderTypeTranslations[displayOrderType] ?? displayOrderType;
        // --- End translations ---

        final String dailyOrderNumber = order['dailyOrderNumber']?.toString() ??
            orderDoc.id.substring(0, 6).toUpperCase();

        final String customerName =
        (order['customerName'] ?? 'Walk-in Customer').toString();
        final String carPlate = (order['carPlateNumber'] ?? '').toString();
        final String customerDisplay =
        rawOrderType.toLowerCase() == 'takeaway' && carPlate.isNotEmpty
            ? 'Car Plate: $carPlate'
            : customerName;
        // --- ADDED: Arabic customer display ---
        final String customerDisplayAr =
        rawOrderType.toLowerCase() == 'takeaway' && carPlate.isNotEmpty
            ? 'لوحة السيارة: $carPlate'
            : (customerName == 'Walk-in Customer' ? 'عميل مباشر' : customerName);


        // --- 2. Fetch Branch Details ---
        final List<dynamic> branchIds = order['branchIds'] ?? [];
        String primaryBranchId =
        branchIds.isNotEmpty ? branchIds.first.toString() : '';

        String branchName = "Restaurant Name"; // Fallback
        String branchNameAr = "اسم المطعم"; // --- ADDED Arabic fallback
        String branchPhone = "";
        String branchAddress = "";
        String branchAddressAr = ""; // --- ADDED
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

              // --- ADDED: Assumes 'name_ar' in your Branch data ---
              branchNameAr = branchData['name_ar'] ?? branchName;

              branchPhone = branchData['phone'] ?? "";
              final addressMap =
                  branchData['address'] as Map<String, dynamic>? ?? {};
              final street = addressMap['street'] ?? '';
              final city = addressMap['city'] ?? '';
              branchAddress = (street.isNotEmpty && city.isNotEmpty)
                  ? "$street, $city"
                  : (street + city);

              // --- ADDED: Assumes 'street_ar' and 'city_ar' in branch address map
              final streetAr = addressMap['street_ar'] ?? street;
              final cityAr = addressMap['city_ar'] ?? city;
              branchAddressAr = (streetAr.isNotEmpty && cityAr.isNotEmpty)
                  ? "$streetAr, $cityAr"
                  : (streetAr + cityAr);
              // --- End Added
            }
          }
        } catch (e) {
          debugPrint("Error fetching branch details for receipt: $e");
        }

        // --- 3. Build the PDF ---
        final pdf = pw.Document();

        // --- UPDATED: Bilingual Styles ---
        // English styles (default font)
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

        // Arabic styles (using the loaded font)
        final pw.TextStyle arRegular = pw.TextStyle(font: arabicFont, fontSize: 9);
        final pw.TextStyle arBold =
        pw.TextStyle(font: arabicFont, fontSize: 9, fontWeight: pw.FontWeight.bold);
        final pw.TextStyle arHeading = pw.TextStyle(
            font: arabicFont,
            fontSize: 16,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.black);
        final pw.TextStyle arTotal = pw.TextStyle(
            font: arabicFont,
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.black);
        // --- END STYLES ---


        // --- ADDED: Helper for bilingual text labels ---
        pw.Widget buildBilingualLabel(String en, String ar, {required pw.TextStyle enStyle, required pw.TextStyle arStyle, pw.CrossAxisAlignment alignment = pw.CrossAxisAlignment.start}) {
          return pw.Column(
            crossAxisAlignment: alignment,
            children: [
              pw.Text(en, style: enStyle),
              pw.Text(ar, style: arStyle, textDirection: pw.TextDirection.rtl),
            ],
          );
        }

        // --- ADDED: Helper for bilingual summary rows ---
        pw.Widget buildSummaryRow(String en, String ar, String value, {required pw.TextStyle enStyle, required pw.TextStyle arStyle, required pw.TextStyle valueStyle, PdfColor? valueColor}) {
          final finalValueStyle = valueColor != null ? valueStyle.copyWith(color: valueColor) : valueStyle;
          return pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(en, style: enStyle),
                    pw.Text(ar, style: arStyle, textDirection: pw.TextDirection.rtl),
                  ]
              ),
              pw.Text(value, style: finalValueStyle, textAlign: pw.TextAlign.right),
            ],
          );
        }
        // --- End Helpers ---


        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.roll80,
            build: (_) {
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (branchLogo != null)
                    pw.Center(
                      child: pw.Image(branchLogo,
                          height: 60, fit: pw.BoxFit.contain),
                    ),
                  pw.SizedBox(height: 5),

                  // --- UPDATED: Bilingual Headers ---
                  pw.Center(child: pw.Text(branchName, style: heading)),
                  pw.Center(child: pw.Text(branchNameAr, style: arHeading, textDirection: pw.TextDirection.rtl)),

                  if (branchAddress.isNotEmpty)
                    pw.Center(child: pw.Text(branchAddress, style: regular, textAlign: pw.TextAlign.center)),
                  if (branchAddressAr.isNotEmpty)
                    pw.Center(child: pw.Text(branchAddressAr, style: arRegular, textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),

                  if (branchPhone.isNotEmpty)
                    pw.Center(
                        child: pw.Text("Tel: $branchPhone", style: regular)),
                  pw.SizedBox(height: 5),

                  pw.Center(
                      child: pw.Text("TAX INVOICE",
                          style: bold.copyWith(fontSize: 10))),
                  pw.Center(
                      child: pw.Text("فاتورة ضريبية",
                          style: arBold.copyWith(fontSize: 10), textDirection: pw.TextDirection.rtl)),

                  pw.SizedBox(height: 10),

                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      buildBilingualLabel('Order #: $dailyOrderNumber', 'رقم الطلب: $dailyOrderNumber', enStyle: regular, arStyle: arRegular),
                      buildBilingualLabel('Type: $displayOrderType', 'نوع: $displayOrderTypeAr', enStyle: bold, arStyle: arBold, alignment: pw.CrossAxisAlignment.end),
                    ],
                  ),
                  pw.SizedBox(height: 3),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      buildBilingualLabel('Date: $formattedDate', 'تاريخ: $formattedDate', enStyle: regular, arStyle: arRegular),
                      buildBilingualLabel('Time: $formattedTime', 'زمن: $formattedTime', enStyle: regular, arStyle: arRegular, alignment: pw.CrossAxisAlignment.end),
                    ],
                  ),
                  pw.SizedBox(height: 3),
                  buildBilingualLabel('Customer: $customerDisplay', 'عميل: $customerDisplayAr', enStyle: regular, arStyle: arRegular),
                  // --- END UPDATED HEADERS ---

                  pw.SizedBox(height: 10),

                  // --- UPDATED: Bilingual Table Headers ---
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
                              padding:
                              const pw.EdgeInsets.symmetric(vertical: 4),
                              child: buildBilingualLabel('ITEM', 'بند', enStyle: bold, arStyle: arBold)),
                          pw.Padding(
                              padding:
                              const pw.EdgeInsets.symmetric(vertical: 4),
                              child: buildBilingualLabel('QTY', 'كمية', enStyle: bold, arStyle: arBold, alignment: pw.CrossAxisAlignment.center)),
                          pw.Padding(
                              padding:
                              const pw.EdgeInsets.symmetric(vertical: 4),
                              child: buildBilingualLabel('TOTAL', 'المجموع', enStyle: bold, arStyle: arBold, alignment: pw.CrossAxisAlignment.end)),
                        ],
                      ),
                      // --- END UPDATED TABLE HEADERS ---

                      // --- UPDATED: Bilingual Item Rows (using 'name_ar') ---
                      ...items.map((item) {
                        return pw.TableRow(
                          children: [
                            pw.Padding(
                                padding:
                                const pw.EdgeInsets.symmetric(vertical: 3),
                                child: buildBilingualLabel(item['name'], item['name_ar'], enStyle: regular, arStyle: arRegular)),
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
                      // --- END UPDATED ITEM ROWS ---
                    ],
                  ),
                  pw.SizedBox(height: 10),

                  // --- UPDATED: Bilingual Summary Section ---
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.end,
                    children: [
                      pw.Expanded( // Use Expanded to allow column to take width
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.stretch, // Stretch to fill width
                          children: [
                            // Subtotal
                            buildSummaryRow('Subtotal:', 'المجموع الفرعي:', 'QAR ${finalSubtotal.toStringAsFixed(2)}', enStyle: regular, arStyle: arRegular, valueStyle: bold),

                            // --- REQUIREMENT 1: Discount is displayed here if > 0 ---
                            if (discount > 0)
                              buildSummaryRow('Discount:', 'خصم:', '- QAR ${discount.toStringAsFixed(2)}', enStyle: regular, arStyle: arRegular, valueStyle: bold, valueColor: PdfColors.green),

                            pw.Divider(height: 5, color: PdfColors.grey),

                            // Total
                            buildSummaryRow('TOTAL:', 'المجموع الكلي:', 'QAR ${totalAmount.toStringAsFixed(2)}', enStyle: total, arStyle: arTotal, valueStyle: total),
                          ],
                        ),
                      ),
                    ],
                  ),
                  // --- END UPDATED SUMMARY ---

                  pw.SizedBox(height: 20),
                  pw.Divider(thickness: 1),
                  pw.SizedBox(height: 5),

                  // --- UPDATED: Bilingual Footer ---
                  pw.Center(
                      child: pw.Text("Thank You For Your Order!", style: bold)),
                  pw.Center(
                      child:
                      pw.Text("شكرا لطلبك!", style: arBold, textDirection: pw.TextDirection.rtl)),

                  pw.SizedBox(height: 5),
                  pw.Center(
                      child:
                      pw.Text("Invoice ID: ${orderDoc.id}", style: small)),
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

    // Filter by branch
    // This assumes non-super admins will always have a currentBranchId
    if (currentBranchId.isNotEmpty) {
      query = query.where('branchIds', arrayContains: currentBranchId);
    } else {
      // Handle super_admin case if they don't have a branchId
      // This will show all online/available drivers
      // Or you could build a branch selector for them
    }

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
                  Text(
                    'Error loading riders: ${snapshot.error}', // Show error
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
                    'All riders are currently busy or offline.', // More descriptive
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
                final String vehicle =
                    data['vehicle']?['type'] ?? 'No vehicle'; // Corrected path

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


/// A simple static service to pass a selected orderId from one screen
/// (like Dashboard) to the OrdersScreen.
