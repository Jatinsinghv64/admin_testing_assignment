import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../utils/responsive_helper.dart';
import '../Widgets/BranchFilterService.dart';
import '../main.dart'; // UserScopeService

class AnalyticsScreenLarge extends StatefulWidget {
  const AnalyticsScreenLarge({super.key});

  @override
  State<AnalyticsScreenLarge> createState() => _AnalyticsScreenLargeState();
}

class _AnalyticsScreenLargeState extends State<AnalyticsScreenLarge> {
  DateTimeRange _dateRange = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 7)),
    end: DateTime.now(),
  );
  String _orderTypeFilter = 'All';
  String _statusFilter = 'All';

  // App Palette COLORS
  static const Color appBackground = Color(0xFFF9FAFB); // grey[50]
  static const Color appPrimary = Colors.deepPurple;
  static const Color appTertiary = Colors.orange;
  static const Color appError = Colors.red;
  static const Color appSurface = Colors.white;
  static const Color appText = Colors.black87;
  static const Color appTextVariant = Colors.grey;

  @override
  Widget build(BuildContext context) {
    final userScope = context.watch<UserScopeService>();
    final branchFilter = context.watch<BranchFilterService>();
    final effectiveBranchIds = branchFilter.getFilterBranchIds(userScope.branchIds);
    final primaryColor = Theme.of(context).primaryColor;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: appBackground,
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('Orders')
            .where('timestamp', isGreaterThanOrEqualTo: _dateRange.start)
            .where('timestamp', isLessThanOrEqualTo: _dateRange.end)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: primaryColor));
          }

          final allOrders = snapshot.data?.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            
            // 1. Branch Filter
            final docBranchIds = (data['branchIds'] as List?)?.map((e) => e.toString()).toList() ?? [];
            bool matchesBranch = false;
            for (var id in effectiveBranchIds) {
              if (docBranchIds.contains(id)) {
                matchesBranch = true;
                break;
              }
            }
            if (!matchesBranch) return false;
            
            // 2. Order Type Filter
            if (_orderTypeFilter != 'All') {
              final type = data['Order_type']?.toString().toLowerCase() ?? '';
              if (!type.contains(_orderTypeFilter.toLowerCase())) return false;
            }
            
            // 3. Status Filter
            if (_statusFilter != 'All') {
              final status = data['status']?.toString().toLowerCase() ?? '';
              if (!status.contains(_statusFilter.toLowerCase())) return false;
            }
            
            return true;
          }).toList() ?? [];

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(textTheme, primaryColor, userScope, branchFilter),
                const SizedBox(height: 32),
                _buildFilterRow(primaryColor),
                const SizedBox(height: 40),
                _buildKPIGrid(allOrders, primaryColor),
                const SizedBox(height: 32),
                _buildBentoMain(allOrders, primaryColor),
                const SizedBox(height: 32),
                _buildLeaderboardsRow(allOrders, primaryColor),
                const SizedBox(height: 32),
                _buildLiveTransactionTable(allOrders, primaryColor),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(TextTheme textTheme, Color primaryColor, UserScopeService userScope, BranchFilterService branchFilter) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ANALYTICS HUB',
              style: textTheme.headlineLarge?.copyWith(
                fontWeight: FontWeight.w900,
                color: Colors.black87,
                letterSpacing: -1,
                fontSize: 36,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Real-time performance monitoring across all channels',
              style: textTheme.bodyMedium?.copyWith(color: Colors.grey[600], fontWeight: FontWeight.w500),
            ),
          ],
        ),
        _buildDateRangePresets(primaryColor),
      ],
    );
  }

  Widget _buildFilterRow(Color primaryColor) {
    return Row(
      children: [
        // Branch Selector (if Super Admin or multi-branch)
        Consumer2<UserScopeService, BranchFilterService>(
          builder: (context, userScope, branchFilter, _) {
            if (userScope.branchIds.length <= 1 && !userScope.isSuperAdmin) return const SizedBox.shrink();
            
            return _buildDropdown(
              label: 'Branch Selection',
              value: branchFilter.selectedBranchId ?? 'All',
              items: [
                const DropdownMenuItem(value: 'All', child: Text('All Branches')),
                ...branchFilter.branchNames.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))),
              ],
              onChanged: (val) {
                branchFilter.selectBranch(val == 'All' ? null : val);
              },
            );
          },
        ),
        const SizedBox(width: 16),
        _buildDropdown(
          label: 'Order Type',
          value: _orderTypeFilter,
          items: ['All', 'Delivery', 'Take Away', 'Dine-in']
              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
              .toList(),
          onChanged: (val) => setState(() => _orderTypeFilter = val!),
        ),
        const SizedBox(width: 16),
        _buildDropdown(
          label: 'Status',
          value: _statusFilter,
          items: ['All', 'Delivered', 'Cancelled', 'Pending']
              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
              .toList(),
          onChanged: (val) => setState(() => _statusFilter = val!),
        ),
      ],
    );
  }

  Widget _buildDropdown({required String label, required String value, required List<DropdownMenuItem<String>> items, required void Function(String?) onChanged}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: appSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
          DropdownButton<String>(
            value: value,
            underline: const SizedBox(),
            items: items,
            onChanged: onChanged,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
            icon: const Icon(Icons.expand_more, size: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildDateRangePresets(Color primaryColor) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: appSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          _buildPresetButton('Last 24h', _isLast24h(), primaryColor),
          _buildPresetButton('Last 7 Days', _isLast7Days(), primaryColor),
          _buildPresetButton('Last 30 Days', _isLast30Days(), primaryColor),
          const SizedBox(width: 8),
          _buildCustomRangeButton(primaryColor),
        ],
      ),
    );
  }

  bool _isLast24h() {
    final now = DateTime.now();
    return _dateRange.end.isAfter(now.subtract(const Duration(minutes: 5))) && 
           _dateRange.start.isAfter(now.subtract(const Duration(hours: 24, minutes: 5)));
  }
  bool _isLast7Days() {
    final now = DateTime.now();
    return !_isLast24h() && _dateRange.start.isAfter(now.subtract(const Duration(days: 7, hours: 1)));
  }
  bool _isLast30Days() {
    final now = DateTime.now();
    return !_isLast7Days() && !_isLast24h() && _dateRange.start.isAfter(now.subtract(const Duration(days: 30, hours: 1)));
  }

  Widget _buildPresetButton(String label, bool isSelected, Color primaryColor) {
    return InkWell(
      onTap: () {
        setState(() {
          if (label == 'Last 24h') _dateRange = DateTimeRange(start: DateTime.now().subtract(const Duration(hours: 24)), end: DateTime.now());
          if (label == 'Last 7 Days') _dateRange = DateTimeRange(start: DateTime.now().subtract(const Duration(days: 7)), end: DateTime.now());
          if (label == 'Last 30 Days') _dateRange = DateTimeRange(start: DateTime.now().subtract(const Duration(days: 30)), end: DateTime.now());
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(color: isSelected ? Colors.white : Colors.grey[600], fontSize: 12, fontWeight: isSelected ? FontWeight.w900 : FontWeight.w500),
        ),
      ),
    );
  }

  Widget _buildCustomRangeButton(Color primaryColor) {
    return InkWell(
      onTap: () async {
        final picked = await showDateRangePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime.now(), initialDateRange: _dateRange);
        if (picked != null) setState(() => _dateRange = picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(8)),
        child: Row(
          children: [
            Icon(Icons.calendar_today, size: 14, color: primaryColor),
            const SizedBox(width: 8),
            const Text('Custom Range', style: TextStyle(color: Colors.black87, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more, size: 12, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildKPIGrid(List<QueryDocumentSnapshot> orders, Color primaryColor) {
    double totalRevenue = 0;
    int totalOrders = orders.length;
    int cancelledOrders = 0;

    for (var doc in orders) {
      final data = doc.data() as Map<String, dynamic>;
      totalRevenue += (data['totalAmount'] as num?)?.toDouble() ?? 0;
      if (data['status'] == 'Cancelled' || data['status'] == 'Failed') cancelledOrders++;
    }

    double aov = totalOrders > 0 ? totalRevenue / totalOrders : 0;
    double problemRate = totalOrders > 0 ? (cancelledOrders / totalOrders) * 100 : 0;

    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 24,
      crossAxisSpacing: 24,
      childAspectRatio: 1.55, // Increased height
      children: [
        _buildKPICard('Total Orders', totalOrders.toString(), '+12.5%', primaryColor, Icons.shopping_cart, 0.75),
        _buildKPICard('Revenue', '\$${totalRevenue.toStringAsFixed(0)}', '+8.2%', appTertiary, Icons.payments, 0.5),
        _buildKPICard('Avg Order Value', '\$${aov.toStringAsFixed(2)}', 'Static', Colors.blue, Icons.speed, 0.65),
        _buildKPICard('Problem Rate', '${problemRate.toStringAsFixed(1)}%', '-2.4%', appError, Icons.report_problem, 0.2),
      ],
    );
  }

  Widget _buildKPICard(String label, String value, String trend, Color color, IconData icon, double progress) {
    return Container(
      padding: const EdgeInsets.all(16), // Reduced padding
      decoration: BoxDecoration(
        color: appSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: color, size: 18)), // Smaller container/icon
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                child: Row(
                  children: [
                    Icon(trend.startsWith('+') ? Icons.trending_up : (trend == 'Static' ? Icons.remove : Icons.trending_down), color: color, size: 10),
                    const SizedBox(width: 4),
                    Text(trend, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12), // Explicit spacing
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label.toUpperCase(), style: const TextStyle(color: Colors.grey, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.2), overflow: TextOverflow.ellipsis), // Smaller label
              const SizedBox(height: 2), // Tighter spacing
              Text(value, style: const TextStyle(color: Colors.black87, fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: -1), overflow: TextOverflow.ellipsis), // Smaller value
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 4, width: double.infinity,
            decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(2)),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft, widthFactor: progress,
              child: Container(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBentoMain(List<QueryDocumentSnapshot> orders, Color primaryColor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 2, child: _buildSalesTrendSection(orders, primaryColor)),
        const SizedBox(width: 24),
        Expanded(flex: 1, child: _buildChannelDistributionSection(orders, primaryColor)),
      ],
    );
  }

  Widget _buildSalesTrendSection(List<QueryDocumentSnapshot> orders, Color primaryColor) {
    final diff = _dateRange.end.difference(_dateRange.start);
    final isHourly = diff.inHours <= 48;
    
    final Map<String, double> salesData = {};
    
    if (isHourly) {
      // Initialize all hours in the range
      for (int i = 0; i <= diff.inHours; i++) {
        final time = _dateRange.start.add(Duration(hours: i));
        final label = DateFormat('HH:00').format(time);
        salesData[label] = 0;
      }
      
      for (var doc in orders) {
        final data = doc.data() as Map<String, dynamic>;
        final timestamp = (data['timestamp'] as Timestamp).toDate();
        final label = DateFormat('HH:00').format(timestamp);
        if (salesData.containsKey(label)) {
          salesData[label] = salesData[label]! + ((data['totalAmount'] as num?)?.toDouble() ?? 0);
        }
      }
    } else {
      // Initialize all days in range
      for (int i = 0; i <= diff.inDays; i++) {
        final time = _dateRange.start.add(Duration(days: i));
        final label = DateFormat('MMM dd').format(time);
        salesData[label] = 0;
      }

      for (var doc in orders) {
        final data = doc.data() as Map<String, dynamic>;
        final timestamp = (data['timestamp'] as Timestamp).toDate();
        final label = DateFormat('MMM dd').format(timestamp);
        if (salesData.containsKey(label)) {
          salesData[label] = salesData[label]! + ((data['totalAmount'] as num?)?.toDouble() ?? 0);
        }
      }
    }

    final List<Map<String, dynamic>> trendData = salesData.entries.map((e) {
      return {'label': e.key, 'value': e.value};
    }).toList();

    return Container(
      height: 460, padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: appSurface, borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.grey[200]!)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(isHourly ? 'Hourly Sales' : 'Sales Trend', style: const TextStyle(color: Colors.black87, fontSize: 20, fontWeight: FontWeight.bold)),
                Text(isHourly ? 'Volume breakdown by hour' : 'Daily order volume distribution', style: const TextStyle(color: Colors.grey, fontSize: 14)),
              ]),
              Row(children: [_buildSmallIconBtn(Icons.download), const SizedBox(width: 8), _buildSmallIconBtn(Icons.more_vert)]),
            ],
          ),
          const SizedBox(height: 32),
          Expanded(
            child: SfCartesianChart(
              plotAreaBorderWidth: 0,
              primaryXAxis: CategoryAxis(
                axisLine: const AxisLine(width: 0), 
                majorGridLines: const MajorGridLines(width: 0), 
                labelStyle: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.w700),
                labelRotation: isHourly ? -45 : 0,
              ),
              primaryYAxis: const NumericAxis(isVisible: false, majorGridLines: MajorGridLines(width: 0)),
              series: <CartesianSeries<dynamic, String>>[
                ColumnSeries<dynamic, String>(
                  dataSource: trendData, 
                  xValueMapper: (datum, _) => datum['label'], 
                  yValueMapper: (datum, _) => datum['value'],
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                  color: primaryColor.withOpacity(0.8),
                ),
              ],
              tooltipBehavior: TooltipBehavior(enable: true, header: isHourly ? 'Hour' : 'Date'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelDistributionSection(List<QueryDocumentSnapshot> orders, Color primaryColor) {
    int delivery = 0, takeaway = 0, dinein = 0;
    for (var doc in orders) {
      final data = doc.data() as Map<String, dynamic>;
      final type = data['Order_type']?.toString().toLowerCase() ?? '';
      if (type.contains('delivery')) delivery++;
      else if (type.contains('takeaway')) takeaway++;
      else dinein++;
    }
    int total = orders.length;

    final channelData = [
      {'label': 'Delivery', 'value': total > 0 ? (delivery / total * 100).toDouble() : 0.0, 'color': primaryColor, 'raw': delivery},
      {'label': 'Take Away', 'value': total > 0 ? (takeaway / total * 100).toDouble() : 0.0, 'color': appTertiary, 'raw': takeaway},
      {'label': 'Dine In', 'value': total > 0 ? (dinein / total * 100).toDouble() : 0.0, 'color': Colors.blue, 'raw': dinein},
    ];

    return Container(
      height: 460, padding: const EdgeInsets.all(24), // Increased height for consistency
      decoration: BoxDecoration(color: appSurface, borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.grey[200]!)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Channel Dist.', style: TextStyle(color: Colors.black87, fontSize: 20, fontWeight: FontWeight.bold)),
          const Text('Sales by source type', style: TextStyle(color: Colors.grey, fontSize: 14)),
          const SizedBox(height: 24), // Reduced spacing
          SizedBox(
            height: 180, // Reduced height for chart
            child: SfCircularChart(
              series: <CircularSeries>[
                DoughnutSeries<dynamic, String>(
                  dataSource: channelData, xValueMapper: (datum, _) => datum['label'], yValueMapper: (datum, _) => datum['value'],
                  pointColorMapper: (datum, _) => datum['color'], innerRadius: '75%', radius: '100%', cornerStyle: CornerStyle.bothCurve,
                ),
              ],
              annotations: <CircularChartAnnotation>[
                CircularChartAnnotation(widget: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(total.toString(), style: const TextStyle(color: Colors.black87, fontSize: 28, fontWeight: FontWeight.bold)),
                  const Text('TOTAL VOL', style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1)),
                ])),
              ],
            ),
          ),
          const SizedBox(height: 24), // Reduced spacing
          _buildChannelLegend('Delivery', '${(channelData[0]['value'] as num).toStringAsFixed(0)}%', primaryColor),
          const SizedBox(height: 12),
          _buildChannelLegend('Take Away', '${(channelData[1]['value'] as num).toStringAsFixed(0)}%', appTertiary),
          const SizedBox(height: 12),
          _buildChannelLegend('Dine In', '${(channelData[2]['value'] as num).toStringAsFixed(0)}%', Colors.blue),
        ],
      ),
    );
  }

  Widget _buildChannelLegend(String label, String pct, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(children: [Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)), const SizedBox(width: 12), Text(label, style: const TextStyle(color: Colors.black87, fontSize: 14, fontWeight: FontWeight.w600))]),
        Text(pct, style: const TextStyle(color: Colors.black87, fontSize: 14, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildLeaderboardsRow(List<QueryDocumentSnapshot> orders, Color primaryColor) {
    return Row(
      children: [
        Expanded(child: _buildRiderLeaderboard(orders, primaryColor)),
        const SizedBox(width: 24),
        Expanded(child: _buildProductLeaderboard(orders, primaryColor)),
        const SizedBox(width: 24),
        Expanded(child: _buildCustomerLeaderboard(orders, primaryColor)),
      ],
    );
  }

  Widget _buildRiderLeaderboard(List<QueryDocumentSnapshot> orders, Color primaryColor) {
    if (orders.isEmpty) return _buildLeaderboardBox('Top Riders', Icons.delivery_dining, primaryColor, [const Center(child: Text('No data', style: TextStyle(color: Colors.grey, fontSize: 12)))]);

    final Map<String, int> riderDeliveries = {};
    final Map<String, double> riderRatings = {}; // Default ratings
    
    for (var doc in orders) {
      final data = doc.data() as Map<String, dynamic>;
      
      // Greedy extraction for rider name/ID
      final riderName = (
        data['riderName'] ?? 
        data['rider_name'] ?? 
        data['driverName'] ?? 
        data['driver_name'] ?? 
        (data['rider_info'] is Map ? data['rider_info']['name'] : null) ??
        data['riderId'] ??
        data['rider_id'] ??
        'Rider'
      ).toString();

      if (riderName != 'Rider' && riderName.isNotEmpty) {
        riderDeliveries[riderName] = (riderDeliveries[riderName] ?? 0) + 1;
        riderRatings[riderName] = 4.8; 
      }
    }
    
    final sortedRiders = riderDeliveries.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final topRiders = sortedRiders.take(2).toList();
    
    return _buildLeaderboardBox('Top Riders', Icons.delivery_dining, primaryColor, [
      if (topRiders.isEmpty) 
        const Center(child: Text('No delivery data', style: TextStyle(color: Colors.grey, fontSize: 12)))
      else ...topRiders.asMap().entries.map((e) {
        final index = e.key + 1;
        final name = e.value.key;
        final count = e.value.value;
        return _buildLeaderboardItem(name, '$count Deliveries', riderRatings[name]?.toStringAsFixed(1) ?? '4.8', index.toString(), '', primaryColor);
      }),
    ]);
  }

  Widget _buildProductLeaderboard(List<QueryDocumentSnapshot> orders, Color primaryColor) {
    if (orders.isEmpty) return _buildLeaderboardBox('Best Sellers', Icons.restaurant_menu, primaryColor, [const Center(child: Text('No data', style: TextStyle(color: Colors.grey, fontSize: 12)))]);
    
    final Map<String, int> productSales = {};
    for (var doc in orders) {
      final data = doc.data() as Map<String, dynamic>;
      // Support both 'items' (POS) and 'cart' (Legacy/Web)
      final items = (data['items'] ?? data['cart']) as List? ?? [];
      for (var item in items) {
        final name = item['name']?.toString() ?? 'Unknown';
        final qty = (item['quantity'] as num?)?.toInt() ?? 1;
        productSales[name] = (productSales[name] ?? 0) + qty;
      }
    }
    final sortedProducts = productSales.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final topProducts = sortedProducts.take(2).toList();

    return _buildLeaderboardBox('Best Sellers', Icons.restaurant_menu, primaryColor, [
      if (topProducts.isEmpty) 
        const Center(child: Text('No sales data', style: TextStyle(color: Colors.grey, fontSize: 12)))
      else ...topProducts.map((e) => _buildLeaderboardItem(e.key, '${e.value} Sold', e == topProducts.first ? '#1 Choice' : 'Popular', '', '', primaryColor, isProduct: true)),
    ]);
  }

  Widget _buildCustomerLeaderboard(List<QueryDocumentSnapshot> orders, Color primaryColor) {
    if (orders.isEmpty) return _buildLeaderboardBox('Loyal Patrons', Icons.groups, primaryColor, [const Center(child: Text('No data', style: TextStyle(color: Colors.grey, fontSize: 12)))]);

    final Map<String, double> customerSpend = {};
    for (var doc in orders) {
      final data = doc.data() as Map<String, dynamic>;
      final name = data['customerName']?.toString() ?? data['customerPhone']?.toString() ?? 'Guest';
      customerSpend[name] = (customerSpend[name] ?? 0) + ((data['totalAmount'] as num?)?.toDouble() ?? 0);
    }
    final sortedCustomers = customerSpend.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final topCustomers = sortedCustomers.take(2).toList();

    return _buildLeaderboardBox('Loyal Patrons', Icons.groups, primaryColor, [
      if (topCustomers.isEmpty) 
        const Center(child: Text('No customer data', style: TextStyle(color: Colors.grey, fontSize: 12)))
      else ...topCustomers.map((e) => _buildLeaderboardItem(e.key, 'LTV Enthusiast', 'QAR ${e.value.toStringAsFixed(0)}', e.key.substring(0, 2).toUpperCase(), '', primaryColor, isAvatar: true)),
    ]);
  }

  Widget _buildLeaderboardBox(String title, IconData icon, Color primaryColor, List<Widget> items) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: appSurface, borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.grey[200]!)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(title, style: const TextStyle(color: Colors.black87, fontSize: 18, fontWeight: FontWeight.bold)), Icon(icon, color: Colors.grey, size: 20)]),
        const SizedBox(height: 24),
        ...items,
      ]),
    );
  }

  Widget _buildLeaderboardItem(String name, String sub, String stat, String rank, String img, Color primaryColor, {bool isProduct = false, bool isAvatar = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: isProduct && stat == '#1 Choice' ? primaryColor.withOpacity(0.05) : Colors.transparent, borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            if (isAvatar) Container(width: 40, height: 40, decoration: BoxDecoration(color: Colors.grey[100], shape: BoxShape.circle), alignment: Alignment.center, child: Text(rank, style: const TextStyle(color: Colors.black87, fontSize: 12, fontWeight: FontWeight.bold)))
            else Container(width: 40, height: 40, decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(isProduct ? 8 : 20)), child: const Icon(Icons.person, color: Colors.grey, size: 20)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(name, style: const TextStyle(color: Colors.black87, fontSize: 14, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis), Text(sub, style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.w500))])),
            Text(stat, style: TextStyle(color: primaryColor, fontSize: 14, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveTransactionTable(List<QueryDocumentSnapshot> orders, Color primaryColor) {
    final recentOrders = orders.take(5).toList();
    return Container(
      decoration: BoxDecoration(color: appSurface, borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.grey[200]!)),
      child: Column(
        children: [
          Padding(padding: const EdgeInsets.all(24), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Live Transaction Flow', style: TextStyle(color: Colors.black87, fontSize: 20, fontWeight: FontWeight.bold)), Row(children: [const Icon(Icons.circle, color: Colors.green, size: 8), const SizedBox(width: 8), Text('LIVE', style: TextStyle(color: Colors.green[700], fontSize: 12, fontWeight: FontWeight.w900))])])),
          Table(
            columnWidths: const {0: FlexColumnWidth(1.2), 1: FlexColumnWidth(2), 2: FlexColumnWidth(1.5), 3: FlexColumnWidth(1.2), 4: FlexColumnWidth(1.2), 5: FlexColumnWidth(1)},
            children: [
              _buildTableRow(['Order ID', 'Customer', 'Status', 'Channel', 'Time', 'Amount'], primaryColor, isHeader: true),
              ...recentOrders.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final timestamp = (data['timestamp'] as Timestamp).toDate();
                return _buildTableRow([
                  data['orderId']?.toString().substring(0, 8) ?? 'Unknown',
                  data['customerName']?.toString() ?? 'Guest',
                  data['status']?.toString() ?? 'Pending',
                  data['Order_source']?.toString() ?? 'POS',
                  timeago(timestamp),
                  '\$${((data['totalAmount'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}'
                ], primaryColor);
              }),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  String timeago(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return DateFormat('MMM dd').format(dt);
  }

  TableRow _buildTableRow(List<String> cells, Color primaryColor, {bool isHeader = false}) {
    return TableRow(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey[100]!))),
      children: cells.asMap().entries.map((entry) {
        final i = entry.key; final cell = entry.value;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: i == 2 && !isHeader ? _buildStatusBadge(cell, primaryColor) : Text(cell, textAlign: i == 5 ? TextAlign.right : TextAlign.left, style: TextStyle(color: isHeader ? Colors.grey : Colors.black87, fontSize: isHeader ? 10 : 13, fontWeight: isHeader ? FontWeight.w900 : (i == 5 ? FontWeight.bold : FontWeight.w600), fontFamily: i == 0 ? 'monospace' : null), overflow: TextOverflow.ellipsis),
        );
      }).toList(),
    );
  }

  Widget _buildStatusBadge(String status, Color primaryColor) {
    final color = status.toLowerCase().contains('delivered') ? Colors.green : (status.toLowerCase().contains('prep') ? Colors.orange : primaryColor);
    return Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20)), child: Text(status.toUpperCase(), style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w900)));
  }

  Widget _buildSmallIconBtn(IconData icon) {
    return Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[200]!)), child: Icon(icon, color: Colors.grey, size: 14));
  }
}
