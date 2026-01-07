import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../main.dart'; // Imports UserScopeService
import '../constants.dart'; // For OrderNumberHelper

class OrderHistoryScreen extends StatefulWidget {
  const OrderHistoryScreen({super.key});

  @override
  State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen> {
  final int _ordersPerPage = 10;
  List<DocumentSnapshot> _orders = [];
  bool _isLoading = false;
  bool _hasMore = true;
  DocumentSnapshot? _lastDocument;
  String _errorMessage = '';

  // State for date filtering
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchOrders();
    });
  }

  void _resetAndFetchOrders() {
    setState(() {
      _orders = [];
      _lastDocument = null;
      _hasMore = true;
    });
    _fetchOrders();
  }

  Future<void> _fetchOrders() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final userScope = Provider.of<UserScopeService>(context, listen: false);
      Query query = FirebaseFirestore.instance.collection('Orders');

      if (!userScope.isSuperAdmin) {
        if (userScope.branchId != null) {
          query = query.where('branchIds', arrayContains: userScope.branchId);
        } else {
          setState(() {
            _isLoading = false;
            _hasMore = false;
          });
          return;
        }
      }

      query = query
          .where('status', whereIn: ['delivered', 'cancelled'])
          .orderBy('timestamp', descending: true);

      if (_startDate != null) {
        query = query.where('timestamp', isGreaterThanOrEqualTo: _startDate);
      }

      if (_endDate != null) {
        final inclusiveEndDate =
        DateTime(_endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59);
        query = query.where('timestamp', isLessThanOrEqualTo: inclusiveEndDate);
      }

      query = query.limit(_ordersPerPage);

      if (_lastDocument != null) {
        query = query.startAfterDocument(_lastDocument!);
      }

      final querySnapshot = await query.get();

      if (querySnapshot.docs.isNotEmpty) {
        _lastDocument = querySnapshot.docs.last;
      }

      if (mounted) {
        setState(() {
          _orders.addAll(querySnapshot.docs);
          _hasMore = querySnapshot.docs.length == _ordersPerPage;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = "Error fetching orders: ${e.toString()}";
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _selectDateRange(BuildContext context) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.deepPurple,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _resetAndFetchOrders();
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
        iconTheme: const IconThemeData(color: Colors.deepPurple),
        title: const Text(
          'Order History',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.deepPurple,
            fontSize: 24,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _startDate != null ? Icons.filter_alt : Icons.filter_alt_outlined,
              color: Colors.deepPurple,
            ),
            onPressed: () => _selectDateRange(context),
          ),
          if (_startDate != null)
            IconButton(
              icon: const Icon(Icons.clear, color: Colors.red),
              onPressed: () {
                setState(() {
                  _startDate = null;
                  _endDate = null;
                });
                _resetAndFetchOrders();
              },
            ),
        ],
      ),
      body: Column(
        children: [
          if (_startDate != null)
            Container(
              width: double.infinity,
              color: Colors.deepPurple.withOpacity(0.05),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: Text(
                'Filtering: ${DateFormat('MMM d').format(_startDate!)} - ${DateFormat('MMM d').format(_endDate!)}',
                style: const TextStyle(color: Colors.deepPurple, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
          Expanded(
            child: _buildOrdersList(),
          ),
        ],
      ),
    );
  }

  Widget _buildOrdersList() {
    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text(_errorMessage, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _resetAndFetchOrders, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    if (_orders.isEmpty && _isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_orders.isEmpty && !_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text('No completed orders found', style: TextStyle(fontSize: 18, color: Colors.grey[600])),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _orders.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _orders.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: _isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(onPressed: _fetchOrders, child: const Text('Load More')),
            ),
          );
        }

        final orderDoc = _orders[index];
        return _OrderHistoryItem(orderDoc: orderDoc);
      },
    );
  }
}

class _OrderHistoryItem extends StatelessWidget {
  final DocumentSnapshot orderDoc;

  const _OrderHistoryItem({required this.orderDoc});

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'delivered': return Colors.green;
      case 'cancelled': return Colors.red;
      default: return Colors.grey;
    }
  }

  void _showDetails(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => OrderDetailsDialog(orderDoc: orderDoc),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = orderDoc.data() as Map<String, dynamic>;
    final status = data['status']?.toString() ?? 'Unknown';
    final orderNumber = OrderNumberHelper.getDisplayNumber(data, orderId: orderDoc.id);
    final timestamp = (data['timestamp'] as Timestamp?)?.toDate();
    final totalAmount = (data['totalAmount'] as num?)?.toDouble() ?? 0.0;
    final customerName = data['customerName']?.toString() ?? 'Guest';
    final orderType = data['Order_type']?.toString() ?? 'Delivery';

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showDetails(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Order #$orderNumber',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getStatusColor(status).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _getStatusColor(status).withOpacity(0.5)),
                    ),
                    child: Text(
                      status.toUpperCase(),
                      style: TextStyle(
                        color: _getStatusColor(status),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.calendar_today, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    timestamp != null
                        ? DateFormat('MMM d, yyyy • h:mm a').format(timestamp)
                        : 'No Date',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  ),
                ],
              ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Customer', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                      const SizedBox(height: 2),
                      Text(customerName, style: const TextStyle(fontWeight: FontWeight.w500)),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Total', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                      const SizedBox(height: 2),
                      Text(
                        'QAR ${totalAmount.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Show quick rejection reason if cancelled
              if (status.toLowerCase() == 'cancelled' && data['cancellationReason'] != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade100),
                  ),
                  child: Text(
                    'Cancelled: ${data['cancellationReason']}',
                    style: TextStyle(color: Colors.red.shade800, fontSize: 12, fontStyle: FontStyle.italic),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      orderType.toLowerCase() == 'delivery' ? Icons.delivery_dining : Icons.storefront,
                      size: 16,
                      color: Colors.grey[700],
                    ),
                    const SizedBox(width: 8),
                    Text(
                      orderType,
                      style: TextStyle(color: Colors.grey[800], fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                    const Spacer(),
                    const Text('Tap for details', style: TextStyle(color: Colors.blue, fontSize: 12)),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_forward_ios, size: 10, color: Colors.blue),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ✅ NEW: Detailed Order Popup for History
class OrderDetailsDialog extends StatelessWidget {
  final DocumentSnapshot orderDoc;

  const OrderDetailsDialog({super.key, required this.orderDoc});

  @override
  Widget build(BuildContext context) {
    final data = orderDoc.data() as Map<String, dynamic>;
    final status = data['status']?.toString() ?? 'unknown';
    final orderNumber = OrderNumberHelper.getDisplayNumber(data, orderId: orderDoc.id);
    final items = List<Map<String, dynamic>>.from(data['items'] ?? []);
    final double subtotal = (data['subtotal'] as num?)?.toDouble() ?? 0.0;
    final double deliveryFee = (data['deliveryFee'] as num?)?.toDouble() ?? 0.0;
    final double totalAmount = (data['totalAmount'] as num?)?.toDouble() ?? 0.0;

    // Cancellation Details
    final String? cancellationReason = data['cancellationReason'];
    final String? rejectedBy = data['rejectedBy'];
    final Timestamp? rejectedAt = data['rejectedAt'];

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Order #$orderNumber',
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.deepPurple),
                      ),
                      Text(
                        DateFormat('MMM d, yyyy • h:mm a').format((data['timestamp'] as Timestamp).toDate()),
                        style: const TextStyle(color: Colors.grey, fontSize: 14),
                      ),
                    ],
                  ),
                ),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
              ],
            ),
            const Divider(height: 30),

            // 🛑 CANCELLATION INFO (Only if cancelled)
            if (status.toLowerCase() == 'cancelled') ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
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
                        Icon(Icons.cancel, color: Colors.red.shade700, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'ORDER CANCELLED',
                          style: TextStyle(
                            color: Colors.red.shade900,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (cancellationReason != null)
                      Text('Reason: $cancellationReason', style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (rejectedBy != null)
                      Text('Cancelled by: $rejectedBy', style: const TextStyle(fontSize: 12)),
                    if (rejectedAt != null)
                      Text(
                        'Time: ${DateFormat('h:mm a').format(rejectedAt.toDate())}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Customer Details
            _buildSectionTitle('Customer Details', Icons.person),
            const SizedBox(height: 8),
            _buildDetailRow('Name', data['customerName'] ?? 'N/A'),
            _buildDetailRow('Phone', data['customerPhone'] ?? 'N/A'),
            if (data['Order_type'] == 'delivery')
              _buildDetailRow('Address', '${data['deliveryAddress']?['street'] ?? ''}, ${data['deliveryAddress']?['city'] ?? ''}'),

            const SizedBox(height: 20),

            // Items
            _buildSectionTitle('Items', Icons.restaurant_menu),
            const SizedBox(height: 8),
            ...items.map((item) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(4)),
                    child: Text('${item['quantity']}x', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(item['name'] ?? 'Item')),
                  Text('QAR ${((item['price'] ?? 0) * (item['quantity'] ?? 1)).toStringAsFixed(2)}'),
                ],
              ),
            )),

            const SizedBox(height: 20),
            const Divider(),

            // Payment Summary
            _buildSummaryRow('Subtotal', subtotal),
            if (deliveryFee > 0) _buildSummaryRow('Delivery Fee', deliveryFee),
            const SizedBox(height: 8),
            _buildSummaryRow('Total', totalAmount, isBold: true, color: Colors.deepPurple),

            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close Details'),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey[800])),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 80, child: Text('$label:', style: TextStyle(color: Colors.grey[600], fontSize: 13))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, double amount, {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal, fontSize: isBold ? 16 : 14)),
          Text('QAR ${amount.toStringAsFixed(2)}', style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal, fontSize: isBold ? 16 : 14, color: color)),
        ],
      ),
    );
  }
}