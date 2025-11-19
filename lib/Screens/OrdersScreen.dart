import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:provider/provider.dart';
import '../main.dart'; // Assuming navigatorKey is here
import 'package:printing/printing.dart';
import 'package:pdf/widgets.dart' as pw;

class OrdersScreen extends StatefulWidget {
  @override
  _OrdersScreenState createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Manage selectedBranchId locally in this screen's state
  String _selectedBranchId = 'all';

  final List<String> _orderStatusTabs = [
    'pending',
    'preparing',
    'prepared',
    'rider_assigned',
    'out_for_delivery',
    'needs_rider_assignment',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _orderStatusTabs.length, vsync: this);

    // Set default branch if user only has one
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final scopeService = Provider.of<UserScopeService>(context, listen: false);
        if (!scopeService.isSuperAdmin && scopeService.branchIds.length == 1) {
          if (mounted) {
            setState(() {
              _selectedBranchId = scopeService.branchIds.first;
            });
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _updateOrderStatus(BuildContext context, String orderId, String newStatus) async {
    // Loading dialog
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
          // Branch Selector
          StreamBuilder<QuerySnapshot>(
            stream: scopeService.isSuperAdmin
                ? FirebaseFirestore.instance.collection('Branch').snapshots()
                : (scopeService.branchIds.isEmpty
                ? Stream.empty()
                : FirebaseFirestore.instance
                .collection('Branch')
                .where(FieldPath.documentId, whereIn: scopeService.branchIds)
                .snapshots()),
            builder: (context, snapshot) {
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return SizedBox.shrink();
              }

              var branchItems = snapshot.data!.docs.map((doc) {
                var branchName = (doc.data() as Map<String, dynamic>)['name'] ?? 'Unknown Branch';
                return DropdownMenuItem<String>(
                  value: doc.id,
                  child: Text(branchName, style: TextStyle(color: Colors.white)),
                );
              }).toList();

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
                        _selectedBranchId = newValue;
                      });
                    }
                  },
                  items: branchItems,
                ),
              );
            },
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: _orderStatusTabs.map((status) {
          return OrderList(
            status: status,
            onUpdateStatus: _updateOrderStatus,
            selectedBranchId: _selectedBranchId,
          );
        }).toList(),
      ),
    );
  }
}

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
    if (['pending', 'preparing', 'prepared', 'rider_assigned', 'out_for_delivery', 'needs_rider_assignment'].contains(status)) {
      query = query.orderBy('timestamps.$status', descending: true);
    } else {
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
            var order = snapshot.data!.docs[index] as QueryDocumentSnapshot<Map<String, dynamic>>;
            var data = order.data();
            var orderType = data['Order_type'] ?? 'delivery';

            // Use the enhanced card for better visualization
            return _OrderCard(
              order: order,
              orderType: orderType,
              onStatusChange: onUpdateStatus,
            );
          },
        );
      },
    );
  }
}

// --- Enhanced Order Card with Status Indicators ---
class _OrderCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> order;
  final String orderType;
  final Function(BuildContext, String, String) onStatusChange;
  final bool isHighlighted;

  const _OrderCard({
    super.key,
    required this.order,
    required this.orderType,
    required this.onStatusChange,
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
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  Widget _buildActionButtons(BuildContext context, String status) {
    final List<Widget> buttons = [];
    final data = order.data();
    final bool isAutoAssigning = data.containsKey('autoAssignStarted');

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
            final freshDoc = await order.reference.get();
            final freshData = freshDoc.data() as Map? ?? {};
            final s = (freshData['status'] as String?)?.toLowerCase() ?? '';
            if (s == 'cancelled') {
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

    // --- ORDER-TYPE SPECIFIC ACTIONS ---

    final orderTypeLower = orderType.toLowerCase();

    // **PICKUP**
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
    // **TAKEAWAY / DINE-IN**
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
    // **DELIVERY**
    else if (orderTypeLower == 'delivery') {
      // NOTE: Manual assignment button is handled in Dashboard popup or ManualAssignmentScreen
      // to avoid clutter here, but the auto-assign status will be visible.

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
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
          if (isHighlighted)
            BoxShadow(
              color: Colors.blue.withOpacity(0.3),
              blurRadius: 15,
              spreadRadius: 2,
              offset: const Offset(0, 0),
            ),
        ],
        border: isHighlighted
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
              if (isHighlighted)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.arrow_forward, color: Colors.white, size: 12),
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
                          child: const Icon(Icons.autorenew, color: Colors.white, size: 8),
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
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.orange.withOpacity(0.3)),
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
                  ],
                ),
              ),
            ],
          ),
          trailing: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.3,
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
                        data['branchIds']?.join(', ') ?? 'N/A'),
                  ],
                  if (orderType == 'takeaway') ...[
                    _buildDetailRow(
                      Icons.directions_car,
                      'Car Plate:',
                      (data['carPlateNumber']?.toString().isNotEmpty ?? false)
                          ? data['carPlateNumber']
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
}

// --- Helper: Receipt Printing ---
Future<void> printReceipt(BuildContext context, DocumentSnapshot orderDoc) async {
  try {
    final fontData = await rootBundle.load("assets/fonts/NotoSansArabic-Regular.ttf");
    final pw.Font arabicFont = pw.Font.ttf(fontData);

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async {
        final Map<String, dynamic> order = Map<String, dynamic>.from(orderDoc.data() as Map);
        final List<dynamic> rawItems = (order['items'] ?? []) as List<dynamic>;
        final List<Map<String, dynamic>> items = rawItems.map((e) {
          final m = Map<String, dynamic>.from(e as Map);
          final name = (m['name'] ?? 'Item').toString();
          final nameAr = (m['name_ar'] ?? name).toString();
          final qty = int.tryParse(m['quantity']?.toString() ?? m['qty']?.toString() ?? '1') ?? 1;
          final double price = (m['price'] ?? m['unitPrice'] ?? 0.0).toDouble();
          return {'name': name, 'name_ar': nameAr, 'qty': qty, 'price': price};
        }).toList();

        final double subtotal = (order['subtotal'] as num?)?.toDouble() ?? 0.0;
        final double discount = (order['discountAmount'] as num?)?.toDouble() ?? 0.0;
        final double totalAmount = (order['totalAmount'] as num?)?.toDouble() ?? 0.0;
        final double calculatedSubtotal = items.fold(0, (sum, item) => sum + (item['price'] * item['qty']));
        final double finalSubtotal = subtotal > 0 ? subtotal : calculatedSubtotal;

        final DateTime? orderDate = (order['timestamp'] as Timestamp?)?.toDate();
        final String formattedDate = orderDate != null ? DateFormat('dd/MM/yyyy').format(orderDate) : "N/A";
        final String formattedTime = orderDate != null ? DateFormat('hh:mm a').format(orderDate) : "N/A";
        final String dailyOrderNumber = order['dailyOrderNumber']?.toString() ?? orderDoc.id.substring(0, 6).toUpperCase();

        final pdf = pw.Document();
        final pw.TextStyle regular = pw.TextStyle(fontSize: 9);
        final pw.TextStyle bold = pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold);
        final pw.TextStyle arRegular = pw.TextStyle(font: arabicFont, fontSize: 9);
        final pw.TextStyle arBold = pw.TextStyle(font: arabicFont, fontSize: 9, fontWeight: pw.FontWeight.bold);

        pw.Widget buildBilingualLabel(String en, String ar, {pw.CrossAxisAlignment alignment = pw.CrossAxisAlignment.start}) {
          return pw.Column(crossAxisAlignment: alignment, children: [pw.Text(en, style: regular), pw.Text(ar, style: arRegular, textDirection: pw.TextDirection.rtl)]);
        }

        pdf.addPage(pw.Page(pageFormat: PdfPageFormat.roll80, build: (_) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(child: pw.Text("TAX INVOICE", style: bold.copyWith(fontSize: 12))),
              pw.SizedBox(height: 10),
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Text('Order #: $dailyOrderNumber', style: bold),
                pw.Text('Date: $formattedDate', style: regular),
              ]),
              pw.Divider(),
              ...items.map((item) => pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(child: buildBilingualLabel(item['name'], item['name_ar'])),
                  pw.Text('x${item['qty']}', style: regular),
                  pw.Text((item['price'] * item['qty']).toStringAsFixed(2), style: bold),
                ],
              )).toList(),
              pw.Divider(),
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Total', style: bold), pw.Text(totalAmount.toStringAsFixed(2), style: bold)]),
            ],
          );
        }));
        return pdf.save();
      },
    );
  } catch (e) {
    debugPrint("Error printing: $e");
  }
}

// --- Service for passing selected orders ---
class OrderSelectionService {
  static Map<String, dynamic> _selectedOrder = {};
  static void setSelectedOrder({String? orderId, String? orderType, String? status}) {
    _selectedOrder = {'orderId': orderId, 'orderType': orderType, 'status': status};
  }
  static Map<String, dynamic> getSelectedOrder() => _selectedOrder;
  static void clearSelectedOrder() => _selectedOrder = {};
}

// --- Rider Selection Dialog (used by ManualAssignment or other flows) ---
class _RiderSelectionDialog extends StatelessWidget {
  final String currentBranchId;
  const _RiderSelectionDialog({required this.currentBranchId});

  @override
  Widget build(BuildContext context) {
    Query query = FirebaseFirestore.instance.collection('Drivers').where('isAvailable', isEqualTo: true).where('status', isEqualTo: 'online');
    if (currentBranchId.isNotEmpty) {
      query = query.where('branchIds', arrayContains: currentBranchId);
    }

    return AlertDialog(
      title: const Text('Select Available Rider'),
      content: SizedBox(
        width: double.maxFinite,
        child: StreamBuilder<QuerySnapshot>(
          stream: query.snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return Center(child: CircularProgressIndicator());
            if (snapshot.data!.docs.isEmpty) return Text('No riders available');
            return ListView.builder(
              shrinkWrap: true,
              itemCount: snapshot.data!.docs.length,
              itemBuilder: (context, index) {
                final driver = snapshot.data!.docs[index];
                return ListTile(
                  title: Text(driver['name']),
                  onTap: () => Navigator.of(context).pop(driver.id),
                );
              },
            );
          },
        ),
      ),
    );
  }
}