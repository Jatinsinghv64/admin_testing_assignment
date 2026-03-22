import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../main.dart'; // Imports UserScopeService
import '../constants.dart'; // For OrderNumberHelper
import '../Widgets/BranchFilterService.dart';
import '../Widgets/PrintingService.dart';
import 'dart:html' as html; // For web CSV download
import 'dart:convert';

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
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

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
      final branchFilter = Provider.of<BranchFilterService>(context, listen: false);
      Query query = FirebaseFirestore.instance.collection('Orders');

      // 1. Branch Filtering
      final selectedId = branchFilter.selectedBranchId;
      if (selectedId != null) {
        query = query.where('branchIds', arrayContains: selectedId);
      } else if (userScope.branchIds.isNotEmpty) {
        query = query.where('branchIds', arrayContainsAny: userScope.branchIds);
      } else if (!userScope.isSuperAdmin) {
        // If not a super admin and no branchIds are associated,
        // then the user should not see any orders.
        setState(() {
          _isLoading = false;
          _hasMore = false;
        });
        return;
      }

      List<String> statusList = [];
      if (_statusFilter == 'All') {
        statusList = ['delivered', 'cancelled', 'refunded', 'pending'];
      } else {
        statusList = [_statusFilter.toLowerCase()];
      }

      query = query.where('status', whereIn: statusList);

      if (_sourceFilter != 'All') {
        query = query.where('Order_source', isEqualTo: _sourceFilter.toUpperCase());
      }

      query = query.orderBy('timestamp', descending: true);

      if (_startDate != null) {
        query = query.where('timestamp', isGreaterThanOrEqualTo: _startDate);
      }

      if (_endDate != null) {
        final inclusiveEndDate = DateTime(
            _endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59);
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
        _calculateMetrics();
      }
    }
  }

  double _totalSalesMTD = 0;
  double _avgOrderValue = 0;
  double _fulfillmentRate = 0;
  int _successfulDeliveries = 0;

  void _calculateMetrics() {
    final filtered = _filteredOrders;
    if (filtered.isEmpty) {
      setState(() {
        _totalSalesMTD = 0;
        _successfulDeliveries = 0;
        _avgOrderValue = 0;
        _fulfillmentRate = 0;
      });
      return;
    }
    
    double total = 0;
    int deliveredCount = 0;
    
    for (var doc in filtered) {
      final data = doc.data() as Map<String, dynamic>;
      final amount = (data['totalAmount'] as num?)?.toDouble() ?? 0.0;
      total += amount;
      if (data['status']?.toString().toLowerCase() == 'delivered') {
        deliveredCount++;
      }
    }
    
    setState(() {
      _totalSalesMTD = total;
      _successfulDeliveries = deliveredCount;
      _avgOrderValue = _orders.isNotEmpty ? total / _orders.length : 0;
      _fulfillmentRate = _orders.isNotEmpty ? (deliveredCount / _orders.length) * 100 : 0;
    });
  }

  List<DocumentSnapshot> get _filteredOrders {
    if (_searchQuery.isEmpty) return _orders;
    
    final query = _searchQuery.toLowerCase();
    return _orders.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final orderId = doc.id.toLowerCase();
      final customer = (data['customerName'] ?? '').toString().toLowerCase();
      final orderNum = OrderNumberHelper.getDisplayNumber(data, orderId: doc.id).toLowerCase();
      
      return orderId.contains(query) || 
             customer.contains(query) || 
             orderNum.contains(query);
    }).toList();
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

  // State for advanced filtering
  String _statusFilter = 'All';
  String _sourceFilter = 'All';

  @override
  Widget build(BuildContext context) {
    final isLarge = MediaQuery.of(context).size.width > 900;
    
    if (isLarge) {
      return _buildZenithLayout();
    }

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
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            children: [
              if (_startDate != null)
                Container(
                  width: double.infinity,
                  color: Colors.deepPurple.withValues(alpha: 0.05),
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  child: Text(
                    'Filtering: ${DateFormat('MMM d').format(_startDate!)} - ${DateFormat('MMM d').format(_endDate!)}',
                    style: const TextStyle(
                        color: Colors.deepPurple, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
              Expanded(
                child: _buildOrdersList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildZenithLayout() {
    final primaryColor = Colors.deepPurple;
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallZenith = screenWidth < 1200;
    
    return Container(
      color: Colors.grey[50],
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildZenithHeader(primaryColor),
            const SizedBox(height: 32),
            _buildKPIGrid(primaryColor, isSmallZenith),
            const SizedBox(height: 32),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Filter Sidebar
                SizedBox(
                  width: 280,
                  child: _buildFilterSidebar(primaryColor),
                ),
                const SizedBox(width: 32),
                // Data Table Section
                Expanded(
                  child: _buildTransactionTable(primaryColor),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildZenithHeader(Color primaryColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('ORDER HISTORY', 
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.black87, letterSpacing: -1)),
                const SizedBox(width: 16),
                Container(height: 24, width: 1, color: Colors.grey[300]),
                const SizedBox(width: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: primaryColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                  child: Text('LIVE FEED', style: TextStyle(color: primaryColor, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('Operational archive and transaction performance.', 
              style: TextStyle(color: Colors.grey[600], fontSize: 13, fontWeight: FontWeight.w500)),
          ],
        ),
        _buildSearchBox(primaryColor),
      ],
    );
  }

  Widget _buildSearchBox(Color primaryColor) {
    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _searchQuery.isNotEmpty ? primaryColor : Colors.grey[200]!),
        boxShadow: _searchQuery.isNotEmpty ? [BoxShadow(color: primaryColor.withValues(alpha: 0.1), blurRadius: 8)] : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Icon(Icons.search, size: 20, color: _searchQuery.isNotEmpty ? primaryColor : Colors.grey),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Search Order ID, Customer...',
                hintStyle: TextStyle(fontSize: 13, color: Colors.grey),
                border: InputBorder.none,
                isDense: true,
              ),
              onChanged: (val) {
                setState(() => _searchQuery = val);
              },
            ),
          ),
          if (_searchQuery.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close, size: 16, color: Colors.grey),
              onPressed: () {
                _searchController.clear();
                setState(() => _searchQuery = '');
              },
            ),
        ],
      ),
    );
  }

  Widget _buildKPIGrid(Color primaryColor, bool isSmallZenith) {
    return GridView.count(
      shrinkWrap: true,
      crossAxisCount: isSmallZenith ? 2 : 4,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: isSmallZenith ? 2.8 : 2.0,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _buildKPICard('Total Sales (MTD)', 'QAR ${_totalSalesMTD.toStringAsFixed(0)}', '+12.4%', Icons.payments, primaryColor),
        _buildKPICard('Avg Order Value', 'QAR ${_avgOrderValue.toStringAsFixed(2)}', '+2.1%', Icons.shopping_bag, Colors.orange),
        _buildKPICard('Fulfillment Rate', '${_fulfillmentRate.toStringAsFixed(1)}%', 'Stable', Icons.verified, primaryColor),
        _buildKPICard('Successful Deliveries', _successfulDeliveries.toString(), '↑ 412', Icons.local_shipping, Colors.green),
      ],
    );
  }

  Widget _buildKPICard(String label, String value, String trend, IconData icon, Color accent) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(label.toUpperCase(), 
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.grey, letterSpacing: 1.2),
                  overflow: TextOverflow.ellipsis),
              ),
              Icon(icon, color: accent, size: 20),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.black87)),
                const SizedBox(width: 8),
                Text(trend, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: accent)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterSidebar(Color primaryColor) {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey[200]!),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('ADVANCED FILTER', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _startDate = null; _endDate = null;
                        _statusFilter = 'All'; _sourceFilter = 'All';
                      });
                      _resetAndFetchOrders();
                    },
                    child: const Text('RESET', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildFilterLabel('Date Range'),
              _buildDateFilterToggle(primaryColor),
              const SizedBox(height: 20),
              _buildFilterLabel('Branch Location'),
              Consumer<BranchFilterService>(
                builder: (context, filter, child) {
                  final userScope = Provider.of<UserScopeService>(context, listen: false);
                  final branchIds = userScope.branchIds;
                  final branchEntries = branchIds.map((id) => MapEntry(id, filter.getBranchName(id))).toList();
                  
                  return _buildFilterDropdown(
                    ['All Branches', ...branchEntries.map((e) => e.value)], 
                    filter.selectedBranchId == null ? 'All Branches' : filter.getBranchName(filter.selectedBranchId!),
                    (val) {
                      if (val == 'All Branches') {
                        filter.selectBranch(null);
                      } else {
                        final id = branchEntries.firstWhere((e) => e.value == val).key;
                        filter.selectBranch(id);
                      }
                      _resetAndFetchOrders();
                    }
                  );
                }
              ),
              const SizedBox(height: 20),
              _buildFilterLabel('Order Source'),
              _buildFilterChips(['All', 'App', 'Web', 'Talabat', 'Snoonu'], _sourceFilter, (val) {
                setState(() => _sourceFilter = val);
                _resetAndFetchOrders();
              }, primaryColor),
              const SizedBox(height: 20),
              _buildFilterLabel('Status Filter'),
              _buildFilterCheckboxGroup(['All', 'Delivered', 'Cancelled', 'Refunded', 'Pending'], primaryColor),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _buildInsightTip(primaryColor),
      ],
    );
  }

  Widget _buildFilterLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(label.toUpperCase(), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1.5)),
    );
  }

  Widget _buildDateFilterToggle(Color primaryColor) {
    return InkWell(
      onTap: () => _selectDateRange(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[200]!)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _startDate == null ? 'Last 30 Days' : '${DateFormat('MMM d').format(_startDate!)} - ${DateFormat('MMM d').format(_endDate!)}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87),
            ),
            Icon(Icons.calendar_month, size: 16, color: primaryColor),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterDropdown(List<String> items, String current, ValueChanged<String?> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[200]!)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: items.contains(current) ? current : items.first,
          isExpanded: true,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87, fontFamily: 'Inter'),
          items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildFilterChips(List<String> chips, String selected, ValueChanged<String> onSelect, Color primaryColor) {
    return Wrap(
      spacing: 8, runSpacing: 8,
      children: chips.map((c) {
        final isSelected = selected == c;
        return InkWell(
          onTap: () => onSelect(c),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? primaryColor.withValues(alpha: 0.1) : Colors.grey[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: isSelected ? primaryColor.withValues(alpha: 0.2) : Colors.grey[200]!),
            ),
            child: Text(c, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: isSelected ? primaryColor : Colors.grey[600])),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFilterCheckboxGroup(List<String> statuses, Color primaryColor) {
    return Column(
      children: statuses.map((s) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            SizedBox(
              width: 18, height: 18,
              child: Checkbox(
                value: _statusFilter == s, 
                onChanged: (v) {
                  if (v == true) {
                    setState(() => _statusFilter = s);
                    _resetAndFetchOrders();
                  }
                }, 
                activeColor: primaryColor, 
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3))
              ),
            ),
            const SizedBox(width: 12),
            Text(s, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.black87)),
          ],
        ),
      )).toList(),
    );
  }

  Widget _buildInsightTip(Color primaryColor) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primaryColor.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: primaryColor, size: 16),
              const SizedBox(width: 8),
              Text('INSIGHT TIP', style: TextStyle(color: primaryColor, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1)),
            ],
          ),
          const SizedBox(height: 12),
          Text('Orders from Talabat have increased by 14% this week. Consider adjusting stock levels at Downtown HQ.', 
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.grey[700], height: 1.5)),
        ],
      ),
    );
  }

  Widget _buildTransactionTable(Color primaryColor) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('TRANSACTION RECORDS', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: -0.5, color: Colors.black87)),
                Row(
                  children: [
                    _buildTableAction('EXPORT CSV', Icons.download, onTap: _exportToCSV),
                    const SizedBox(width: 12),
                    _buildTableAction('PRINT ALL', Icons.print, onTap: _printVisibleOrders),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          _buildTableHeader(),
          const Divider(height: 1),
          if (_isLoading && _orders.isEmpty)
            const Padding(padding: EdgeInsets.all(100), child: CircularProgressIndicator())
          else if (_filteredOrders.isEmpty)
            const Padding(padding: EdgeInsets.all(100), child: Text('No transactions found.'))
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _filteredOrders.length,
              separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey[100]),
              itemBuilder: (context, index) {
                final doc = _filteredOrders[index];
                return _buildTransactionRow(doc.data() as Map<String, dynamic>, doc.id, primaryColor);
              },
            ),
          const Divider(height: 1),
          _buildPaginationFooter(),
        ],
      ),
    );
  }

  Widget _buildTableAction(String label, IconData icon, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[200]!)),
        child: Row(
          children: [
            Icon(icon, size: 14, color: Colors.grey[600]),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.black87)),
          ],
        ),
      ),
    );
  }

  Color _getSourceColor(String source) {
    switch (source.toUpperCase()) {
      case 'APP': return Colors.deepPurple;
      case 'TALABAT': return Colors.pink;
      case 'SNOONU': return Colors.orange;
      case 'WEB': return Colors.blue;
      default: return Colors.grey;
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'delivered': return Colors.green;
      case 'cancelled': return Colors.red;
      case 'refunded': return Colors.orange;
      case 'pending': return Colors.blue;
      default: return Colors.grey;
    }
  }

  Widget _buildTableHeader() {
    return Container(
      color: Colors.grey[50],
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          _buildHeaderCell('Order ID', 1.5),
          _buildHeaderCell('Customer & Branch', 2.5),
          _buildHeaderCell('Timestamp', 2),
          _buildHeaderCell('Amount & Payment', 2),
          _buildHeaderCell('Source', 1),
          _buildHeaderCell('Status', 1.5),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(String label, double flex) {
    return Expanded(
      flex: (flex * 10).toInt(),
      child: Text(label.toUpperCase(), 
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1)),
    );
  }

  Widget _buildTransactionRow(Map<String, dynamic> data, String id, Color primaryColor) {
    final status = data['status']?.toString() ?? 'unknown';
    final timestamp = (data['timestamp'] as Timestamp?)?.toDate();
    final totalAmount = (data['totalAmount'] as num?)?.toDouble() ?? 0.0;
    final source = data['Order_source'] ?? (data['Order_type'] == 'delivery' ? 'APP' : 'POS');
    final branch = (data['branchIds'] as List?)?.first ?? 'Downtown HQ';
    final payment = data['paymentMethod'] ?? 'Visa •••• 4242';

    return InkWell(
      onTap: () => _printOrder(id),
      onSecondaryTap: () => _showDetails(context, id, data),
      hoverColor: primaryColor.withValues(alpha: 0.02),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Row(
          children: [
            // Order ID
            Expanded(
              flex: 15,
              child: Text('#${id.substring(0,8).toUpperCase()}', 
                  style: TextStyle(fontWeight: FontWeight.w900, color: primaryColor, fontSize: 11, fontFamily: 'Monospace')),
            ),
            // Customer & Branch
            Expanded(
              flex: 25,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(data['customerName'] ?? 'N/A', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87)),
                  Text(branch.toString().toUpperCase(), style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            // Timestamp
            Expanded(
              flex: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(timestamp != null ? DateFormat('MMM d, yyyy').format(timestamp) : 'N/A', 
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.black87)),
                  Text(timestamp != null ? DateFormat('HH:mm:ss').format(timestamp) : '', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                ],
              ),
            ),
            // Amount
            Expanded(
              flex: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('QAR ${totalAmount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.black87)),
                  Row(
                    children: [
                      const Icon(Icons.credit_card, size: 12, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(payment, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                    ],
                  ),
                ],
              ),
            ),
            // Source
            Expanded(
              flex: 10,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _getSourceColor(source).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(source.toString().toUpperCase(), 
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: _getSourceColor(source))),
                ),
              ),
            ),
            // Status
            Expanded(
              flex: 15,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: _getStatusColor(status).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 6, height: 6, decoration: BoxDecoration(color: _getStatusColor(status), shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Text(status.toUpperCase(), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: _getStatusColor(status))),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _printOrder(String docId) async {
    final doc = await FirebaseFirestore.instance.collection('Orders').doc(docId).get();
    if (doc.exists && mounted) {
      await PrintingService.printReceipt(context, doc);
    }
  }


  Widget _buildPaginationFooter() {
    if (!_hasMore) return const SizedBox.shrink();
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
      ),
      child: Center(
        child: _isLoading 
          ? const CircularProgressIndicator(strokeWidth: 2)
          : TextButton.icon(
              onPressed: _fetchOrders,
              icon: const Icon(Icons.add_circle_outline, size: 18),
              label: const Text('LOAD MORE TRANSACTIONS', 
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1)),
              style: TextButton.styleFrom(foregroundColor: Colors.deepPurple),
            ),
      ),
    );
  }

  void _exportToCSV() {
    if (_filteredOrders.isEmpty) return;

    List<List<String>> rows = [];
    rows.add(['Order ID', 'Customer', 'Date', 'Time', 'Amount', 'Payment', 'Source', 'Status']);

    for (var doc in _filteredOrders) {
      final data = doc.data() as Map<String, dynamic>;
      final timestamp = (data['timestamp'] as Timestamp?)?.toDate();
      rows.add([
        doc.id,
        data['customerName'] ?? 'N/A',
        timestamp != null ? DateFormat('yyyy-MM-dd').format(timestamp) : 'N/A',
        timestamp != null ? DateFormat('HH:mm:ss').format(timestamp) : 'N/A',
        ((data['totalAmount'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2),
        data['paymentMethod'] ?? 'N/A',
        data['Order_source'] ?? 'N/A',
        data['status'] ?? 'N/A',
      ]);
    }

    String csv = rows.map((e) => e.join(',')).join('\n');
    final bytes = utf8.encode(csv);
    final blob = html.Blob([bytes]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute("download", "orders_export_${DateTime.now().millisecondsSinceEpoch}.csv")
      ..click();
    html.Url.revokeObjectUrl(url);
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('CSV Export Started'), backgroundColor: Colors.green),
    );
  }

  void _printVisibleOrders() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Bulk printing is not supported. Please select individual orders.'), backgroundColor: Colors.orange),
    );
  }

  Widget _buildPageButton(IconData? icon, {String? label, bool isSelected = false, bool isActive = true}) {
    return Container(
      width: 32, height: 32,
      decoration: BoxDecoration(
        color: isSelected ? Colors.deepPurple : Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isSelected ? Colors.deepPurple : Colors.grey[200]!),
      ),
      child: Center(
        child: icon != null 
          ? Icon(icon, size: 16, color: isActive ? Colors.grey[800] : Colors.grey[300])
          : Text(label!, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.grey[800])),
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
              Text(_errorMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              ElevatedButton(
                  onPressed: _resetAndFetchOrders, child: const Text('Retry')),
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
            Text('No completed orders found',
                style: TextStyle(fontSize: 18, color: Colors.grey[600])),
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
                  : ElevatedButton(
                      onPressed: _fetchOrders, child: const Text('Load More')),
            ),
          );
        }

        final orderDoc = _orders[index];
        return _OrderHistoryItem(orderDoc: orderDoc);
      },
    );
  }

  void _showDetails(BuildContext context, String id, Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (context) => OrderDetailsDialog(data: data, orderId: id),
    );
  }
}

class _OrderHistoryItem extends StatelessWidget {
  final DocumentSnapshot orderDoc;

  const _OrderHistoryItem({required this.orderDoc});

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'delivered':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
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
    final orderNumber =
        OrderNumberHelper.getDisplayNumber(data, orderId: orderDoc.id);
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
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getStatusColor(status).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: _getStatusColor(status).withOpacity(0.5)),
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
                      Text('Customer',
                          style:
                              TextStyle(color: Colors.grey[600], fontSize: 12)),
                      const SizedBox(height: 2),
                      Text(customerName,
                          style: const TextStyle(fontWeight: FontWeight.w500)),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Total',
                          style:
                              TextStyle(color: Colors.grey[600], fontSize: 12)),
                      const SizedBox(height: 2),
                      Text(
                        'QAR ${totalAmount.toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.deepPurple),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Show quick rejection reason if cancelled
              if (status.toLowerCase() == 'cancelled' &&
                  data['cancellationReason'] != null)
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
                    style: TextStyle(
                        color: Colors.red.shade800,
                        fontSize: 12,
                        fontStyle: FontStyle.italic),
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
                      orderType.toLowerCase() == 'delivery'
                          ? Icons.delivery_dining
                          : Icons.storefront,
                      size: 16,
                      color: Colors.grey[700],
                    ),
                    const SizedBox(width: 8),
                    Text(
                      orderType,
                      style: TextStyle(
                          color: Colors.grey[800],
                          fontSize: 13,
                          fontWeight: FontWeight.w500),
                    ),
                    const Spacer(),
                    const Text('Tap for details',
                        style: TextStyle(color: Colors.blue, fontSize: 12)),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_forward_ios,
                        size: 10, color: Colors.blue),
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

class OrderDetailsDialog extends StatelessWidget {
  final Map<String, dynamic>? data;
  final String? orderId;
  final DocumentSnapshot? orderDoc;

  const OrderDetailsDialog({super.key, this.data, this.orderId, this.orderDoc});

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> orderData = data ?? (orderDoc?.data() as Map<String, dynamic>);
    final id = orderId ?? orderDoc?.id ?? 'Unknown';
    final status = orderData['status']?.toString() ?? 'unknown';
    final orderNumber = OrderNumberHelper.getDisplayNumber(orderData, orderId: id);
    final items = List<Map<String, dynamic>>.from(orderData['items'] ?? []);
    final double subtotal = (orderData['subtotal'] as num?)?.toDouble() ?? 0.0;
    final double deliveryFee =
        (orderData['riderPaymentAmount'] as num? ?? orderData['deliveryFee'] as num?)
                ?.toDouble() ??
            0.0;
    final double totalAmount = (orderData['totalAmount'] as num?)?.toDouble() ?? 0.0;

    // Cancellation Details
    final String? cancellationReason = orderData['cancellationReason'];
    final String? rejectedBy = orderData['rejectedBy'];
    final Timestamp? rejectedAt = orderData['rejectedAt'];

    return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
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
                            style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.deepPurple),
                          ),
                          Text(
                            DateFormat('MMM d, yyyy • h:mm a').format(
                                (orderData['timestamp'] as Timestamp).toDate()),
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close)),
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
                            Icon(Icons.cancel,
                                color: Colors.red.shade700, size: 20),
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
                          Text('Reason: $cancellationReason',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                        if (rejectedBy != null)
                          Text('Cancelled by: $rejectedBy',
                              style: const TextStyle(fontSize: 12)),
                        if (rejectedAt != null)
                          Text(
                            'Time: ${DateFormat('h:mm a').format(rejectedAt.toDate())}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // Customer Details
                _buildSectionTitle('Customer Details', Icons.person),
                const SizedBox(height: 8),
                _buildDetailRow('Name', orderData['customerName'] ?? 'N/A'),
                _buildDetailRow('Phone', orderData['customerPhone'] ?? 'N/A'),
                if (orderData['Order_type'] == 'delivery')
                  _buildDetailRow('Address',
                      '${orderData['deliveryAddress']?['street'] ?? ''}, ${orderData['deliveryAddress']?['city'] ?? ''}'),

                const SizedBox(height: 20),

                // Items
                _buildSectionTitle('Items', Icons.restaurant_menu),
                const SizedBox(height: 8),
                ...items.map((item) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                                color: Colors.grey[200],
                                borderRadius: BorderRadius.circular(4)),
                            child: Text('${item['quantity']}x',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Text(item['name'] ?? 'Item')),
                          Text(
                              'QAR ${((item['price'] ?? 0) * (item['quantity'] ?? 1)).toStringAsFixed(2)}'),
                        ],
                      ),
                    )),

                const SizedBox(height: 20),
                const Divider(),

                // Payment Summary
                _buildSummaryRow('Subtotal', subtotal),
                if (deliveryFee > 0)
                  _buildSummaryRow('Delivery Fee', deliveryFee),
                const SizedBox(height: 8),
                _buildSummaryRow('Total', totalAmount,
                    isBold: true, color: Colors.deepPurple),

                const SizedBox(height: 24),
                _buildSectionTitle('Order Info', Icons.info_outline),
                const SizedBox(height: 8),
                _buildDetailRow('Order ID', id),
                _buildDetailRow('Branch IDs', (orderData['branchIds'] as List?)?.join(', ') ?? 'N/A'),

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
        ));
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(title,
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800])),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 80,
              child: Text('$label:',
                  style: TextStyle(color: Colors.grey[600], fontSize: 13))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, double amount,
      {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                  fontSize: isBold ? 16 : 14)),
          Text('QAR ${amount.toStringAsFixed(2)}',
              style: TextStyle(
                  fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                  fontSize: isBold ? 16 : 14,
                  color: color)),
        ],
      ),
    );
  }
}
