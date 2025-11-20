import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:provider/provider.dart';
import '../main.dart'; // Assuming navigatorKey is here
import 'package:printing/printing.dart';
import 'package:pdf/widgets.dart' as pw;



/// Service to pass selected order from Notification/Dashboard to OrdersScreen
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

class _OrdersScreenState extends State<OrdersScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedStatus = 'all';
  late ScrollController _scrollController;
  final Map<String, GlobalKey> _orderKeys = {};
  bool _shouldScrollToOrder = false;

  // Track if we need to scroll to a specific order from dashboard/notification
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

    // Check if there's a selected order from dashboard/service
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
    } else if (widget.initialOrderId != null) {
      _orderToScrollTo = widget.initialOrderId;
      _shouldScrollToOrder = true;
    }

    // Initialize tab controller
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

    // Reset scroll flag when tab changes manually
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          // Only try scrolling if we are on the initial load
          // Logic can be adjusted if you want persistent highlighting
        });
      }
    });
  }

  @override
  void dispose() {
    OrderSelectionService.clearSelectedOrder();
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
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

  Future<void> updateOrderStatus(BuildContext context, String orderId, String newStatus) async {
    if (!mounted) return;

    try {
      final db = FirebaseFirestore.instance;
      final orderRef = db.collection('Orders').doc(orderId);
      final WriteBatch batch = db.batch();

      final Map<String, dynamic> updateData = {
        'status': newStatus,
      };

      if (newStatus == 'prepared') {
        updateData['timestamps.prepared'] = FieldValue.serverTimestamp();
      } else if (newStatus == 'delivered') {
        updateData['timestamps.delivered'] = FieldValue.serverTimestamp();

        // Free rider if delivery
        final orderDoc = await orderRef.get();
        final data = orderDoc.data() as Map<String, dynamic>? ?? {};
        final String orderType = (data['Order_type'] as String?)?.toLowerCase() ?? '';
        final String? riderId = data.containsKey('riderId') ? data['riderId'] as String? : null;

        if (orderType == 'delivery' && riderId != null && riderId.isNotEmpty) {
          final driverRef = db.collection('Drivers').doc(riderId);
          batch.update(driverRef, {
            'assignedOrderId': '',
            'isAvailable': true,
          });
        }
      } else if (newStatus == 'cancelled') {
        updateData['timestamps.cancelled'] = FieldValue.serverTimestamp();

        // Free rider and remove from order
        final orderDoc = await orderRef.get();
        final data = orderDoc.data() as Map<String, dynamic>? ?? {};
        final String? riderId = data['riderId'] as String?;

        if (riderId != null && riderId.isNotEmpty) {
          final driverRef = db.collection('Drivers').doc(riderId);
          batch.update(driverRef, {
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

      batch.update(orderRef, updateData);
      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Order $orderId status updated to "$newStatus"!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
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
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple, fontSize: 24),
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
        tabs: _orderTypeMap.keys.map((tabName) => Tab(text: tabName)).toList(),
      ),
    );
  }

  Widget _buildEnhancedStatusFilterBar() {
    return Container(
      margin: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.deepPurple.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))],
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
                  decoration: BoxDecoration(color: Colors.deepPurple.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.filter_list_rounded, color: Colors.deepPurple, size: 20),
                ),
                const SizedBox(width: 12),
                const Text('Filter by Status', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Row(
              children: [
                _buildEnhancedStatusChip('All', 'all', Icons.apps_rounded),
                _buildEnhancedStatusChip('Placed', 'pending', Icons.schedule_rounded),
                _buildEnhancedStatusChip('Preparing', 'preparing', Icons.restaurant_rounded),
                _buildEnhancedStatusChip('Prepared', 'prepared', Icons.done_all_rounded),
                _buildEnhancedStatusChip('Needs Assign', 'needs_rider_assignment', Icons.person_pin_circle_outlined),
                _buildEnhancedStatusChip('Rider Assigned', 'rider_assigned', Icons.delivery_dining_rounded),
                _buildEnhancedStatusChip('Picked Up', 'pickedUp', Icons.local_shipping_rounded),
                _buildEnhancedStatusChip('Delivered', 'delivered', Icons.check_circle_rounded),
                _buildEnhancedStatusChip('Cancelled', 'cancelled', Icons.cancel_rounded),
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
      case 'pending': chipColor = Colors.orange; break;
      case 'needs_rider_assignment': chipColor = Colors.orange; break;
      case 'preparing': chipColor = Colors.teal; break;
      case 'prepared': chipColor = Colors.blueAccent; break;
      case 'rider_assigned': chipColor = Colors.purple; break;
      case 'pickedUp': chipColor = Colors.deepPurple; break;
      case 'delivered': chipColor = Colors.green; break;
      case 'cancelled': chipColor = Colors.red; break;
      default: chipColor = Colors.deepPurple;
    }

    return Container(
      margin: const EdgeInsets.only(right: 12),
      child: FilterChip(
        showCheckmark: false,
        label: Text(label, style: TextStyle(color: isSelected ? Colors.white : chipColor, fontWeight: isSelected ? FontWeight.bold : FontWeight.w600, fontSize: 12)),
        selected: isSelected,
        onSelected: (selected) {
          setState(() {
            _selectedStatus = selected ? value : 'all';
            _shouldScrollToOrder = widget.initialOrderId != null || _orderToScrollTo != null;
          });
        },
        selectedColor: chipColor,
        backgroundColor: chipColor.withOpacity(0.1),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        avatar: CircleAvatar(
          radius: 12,
          backgroundColor: isSelected ? Colors.white.withOpacity(0.2) : chipColor.withOpacity(0.12),
          child: Icon(icon, size: 14, color: isSelected ? Colors.white : chipColor),
        ),
      ),
    );
  }

  Widget _buildOrdersList(String orderType) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _getOrdersStream(orderType),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text('No orders found.', style: TextStyle(color: Colors.grey[600], fontSize: 18)),
              ],
            ),
          );
        }

        final docs = snapshot.data!.docs;

        // Scroll Logic for robust navigation
        if (_shouldScrollToOrder && _orderToScrollTo != null) {
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
                  alignment: 0.1, // Scroll to near top
                );
                setState(() {
                  _shouldScrollToOrder = false;
                  _orderToScrollTo = null;
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
            final isHighlighted = orderDoc.id == _orderToScrollTo;

            return _OrderCard(
              key: _orderKeys[orderDoc.id],
              order: orderDoc,
              orderType: orderType,
              onStatusChange: updateOrderStatus,
              isHighlighted: isHighlighted,
            );
          },
        );
      },
    );
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _getOrdersStream(String orderType) {
    Query<Map<String, dynamic>> baseQuery = FirebaseFirestore.instance
        .collection('Orders')
        .where('Order_type', isEqualTo: orderType);

    final userScope = context.read<UserScopeService>();
    if (!userScope.isSuperAdmin) {
      baseQuery = baseQuery.where('branchIds', arrayContains: userScope.branchId);
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

  @override
  Widget build(BuildContext context) {
    final data = order.data();
    final items = List<Map<String, dynamic>>.from(data['items'] ?? []);
    final status = data['status']?.toString() ?? 'pending';
    final timestamp = (data['timestamp'] as Timestamp?)?.toDate();
    final orderNumber = data['dailyOrderNumber']?.toString() ?? order.id.substring(0, 6).toUpperCase();
    final double subtotal = (data['subtotal'] as num? ?? 0.0).toDouble();
    final double deliveryFee = (data['deliveryFee'] as num? ?? 0.0).toDouble();
    final double totalAmount = (data['totalAmount'] as num? ?? 0.0).toDouble();
    final bool isAutoAssigning = data.containsKey('autoAssignStarted');

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
          if (isHighlighted)
            BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 15, spreadRadius: 2),
        ],
        border: isHighlighted ? Border.all(color: Colors.blue, width: 2) : null,
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          title: Row(
            children: [
              if (isHighlighted)
                Padding(padding: const EdgeInsets.only(right: 8), child: Icon(Icons.arrow_forward, color: Colors.blue.shade700, size: 18)),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: _getStatusColor(status).withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                child: Stack(
                  children: [
                    Icon(Icons.receipt_long_outlined, color: _getStatusColor(status), size: 20),
                    if (isAutoAssigning)
                      const Positioned(right: -2, top: -2, child: Icon(Icons.autorenew, color: Colors.blue, size: 8)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Order #$orderNumber', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isHighlighted ? Colors.blue.shade800 : Colors.black87)),
                    const SizedBox(height: 4),
                    Text(timestamp != null ? DateFormat('MMM dd, yyyy hh:mm a').format(timestamp) : 'No date', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                    if (isAutoAssigning) const Text('Auto-assigning rider...', style: TextStyle(color: Colors.blue, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(color: _getStatusColor(status).withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
            child: Text(status.toUpperCase(), style: TextStyle(color: _getStatusColor(status), fontWeight: FontWeight.bold, fontSize: 10)),
          ),
          children: [
            // Order Details
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDetailRow("Customer", data['customerName'] ?? 'N/A'),
                  if (orderType.toLowerCase() == 'delivery')
                    _buildDetailRow("Address", '${data['deliveryAddress']?['street'] ?? ''}'),
                  const Divider(),
                  ...items.map((item) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("${item['quantity']}x ${item['name']}"),
                        Text("QAR ${(item['price'] * (item['quantity'] ?? 1)).toStringAsFixed(2)}"),
                      ],
                    ),
                  )),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Total", style: TextStyle(fontWeight: FontWeight.bold)),
                      Text("QAR ${totalAmount.toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  )
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildActionButtons(context, status),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 80, child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12))),
        Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13))),
      ]),
    );
  }

  Widget _buildActionButtons(BuildContext context, String status) {
    final List<Widget> buttons = [];
    const EdgeInsets btnPadding = EdgeInsets.symmetric(horizontal: 14, vertical: 10);

    if (status == 'pending') {
      buttons.add(ElevatedButton.icon(
        icon: const Icon(Icons.check, size: 16),
        label: const Text('Accept Order'),
        onPressed: () => onStatusChange(context, order.id, 'preparing'),
        style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: btnPadding),
      ));
    }

    if (status == 'preparing') {
      buttons.add(ElevatedButton.icon(
        icon: const Icon(Icons.done_all, size: 16),
        label: const Text('Mark as Prepared'),
        onPressed: () => onStatusChange(context, order.id, 'prepared'),
        style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white, padding: btnPadding),
      ));
    }

    // Reprint Receipt Button
    if (status != 'cancelled' && status != 'pending') {
      buttons.add(OutlinedButton.icon(
        icon: const Icon(Icons.print, size: 16),
        label: const Text('Reprint'),
        onPressed: () => printReceipt(context, order),
        style: OutlinedButton.styleFrom(padding: btnPadding),
      ));
    }

    // Status specific completions
    if (status == 'prepared') {
      if (orderType.toLowerCase() == 'pickup' || orderType.toLowerCase() == 'takeaway' || orderType.toLowerCase() == 'dine_in') {
        buttons.add(ElevatedButton.icon(
          icon: const Icon(Icons.task_alt, size: 16),
          label: const Text('Complete'),
          onPressed: () => onStatusChange(context, order.id, 'delivered'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white, padding: btnPadding),
        ));
      }
    }

    if (status == 'pickedUp' && orderType.toLowerCase() == 'delivery') {
      buttons.add(ElevatedButton.icon(
        icon: const Icon(Icons.task_alt, size: 16),
        label: const Text('Mark Delivered'),
        onPressed: () => onStatusChange(context, order.id, 'delivered'),
        style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white, padding: btnPadding),
      ));
    }

    if (status == 'pending' || status == 'preparing') {
      buttons.add(TextButton(
        onPressed: () => onStatusChange(context, order.id, 'cancelled'),
        child: const Text('Cancel', style: TextStyle(color: Colors.red)),
      ));
    }

    return Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: buttons);
  }
}


// --- Helper: Receipt Printing ---
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


// --- Rider Selection Dialog (used by ManualAssignment or other flows) ---
