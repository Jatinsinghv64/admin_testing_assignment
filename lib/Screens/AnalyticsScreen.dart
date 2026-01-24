import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:excel/excel.dart' as excel_lib;
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import '../utils/responsive_helper.dart';
import '../services/AnalyticsPdfService.dart';
import '../Widgets/BranchFilterService.dart';
import '../main.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DateTimeRange _dateRange = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 7)),
    end: DateTime.now(),
  );
  String _selectedOrderType = 'all';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(_handleTabSelection);
    
    // Load branch names if needed (for multi-branch users)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userScope = context.read<UserScopeService>();
      final branchFilter = context.read<BranchFilterService>();
      if (userScope.branchIds.length > 1 && !branchFilter.isLoaded) {
        branchFilter.loadBranchNames(userScope.branchIds);
      }
    });
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabSelection);
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabSelection() {
    if (!_tabController.indexIsChanging) {
      setState(() {
        // Switched to a case statement for better readability
        switch (_tabController.index) {
          case 0:
            _selectedOrderType = 'all';
            break;
          case 1:
            _selectedOrderType = 'delivery';
            break;
          case 2:
            _selectedOrderType = 'takeaway';
            break;
          case 3: // New case for Pickup
            _selectedOrderType = 'pickup';
            break;
          case 4:
            _selectedOrderType = 'dine_in';
            break;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final userScope = context.watch<UserScopeService>();
    final branchFilter = context.watch<BranchFilterService>();
    final bool showBranchSelector = userScope.branchIds.length > 1;
    
    // Get effective branch IDs for filtering
    final effectiveBranchIds = branchFilter.getFilterBranchIds(userScope.branchIds);
    
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        centerTitle: true,
        title: const Text(
          'Analytics & Reports',
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Branch Selector - Full width at top
            if (showBranchSelector) ...[
              _buildBranchSelectorCard(userScope, branchFilter),
              const SizedBox(height: 16),
            ],
            _buildDateRangeSelector(),
            const SizedBox(height: 16),

            // Export Report Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.file_download_outlined, size: 24),
                label: const Text(
                  'Export Report',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 4,
                  shadowColor: Colors.deepPurple.withOpacity(0.4),
                ),
                onPressed: () => _showExportDialog(context),
              ),
            ),
            const SizedBox(height: 32),

            // Analytics Overview Cards
            _buildAnalyticsOverviewCards(effectiveBranchIds),
            const SizedBox(height: 32),

            // ✅ RESPONSIVE LAYOUT
            if (ResponsiveHelper.isDesktop(context))
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        buildSectionHeader('Sales Trend', Icons.trending_up),
                        const SizedBox(height: 16),
                        _buildSalesChart(effectiveBranchIds),
                        const SizedBox(height: 32),
                        buildSectionHeader('Performance', Icons.star_border),
                        const SizedBox(height: 16),
                        _buildTopItemsList(effectiveBranchIds),
                      ],
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    flex: 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        buildSectionHeader(
                            'Distribution', Icons.pie_chart_outline),
                        const SizedBox(height: 16),
                        _buildOrderTypeDistributionChart(effectiveBranchIds),
                      ],
                    ),
                  ),
                ],
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  buildSectionHeader('Sales Trend', Icons.trending_up),
                  const SizedBox(height: 16),
                  _buildSalesChart(effectiveBranchIds),
                  const SizedBox(height: 32),
                  buildSectionHeader('Performance', Icons.star_border),
                  const SizedBox(height: 16),
                  _buildTopItemsList(effectiveBranchIds),
                  const SizedBox(height: 32),
                  buildSectionHeader('Distribution', Icons.pie_chart_outline),
                  const SizedBox(height: 16),
                  _buildOrderTypeDistributionChart(effectiveBranchIds),
                ],
              ),
            const SizedBox(height: 20),
            // NEW: Top Delivery Riders Section
            buildSectionHeader('Top Delivery Riders', Icons.delivery_dining),
            const SizedBox(height: 16),
            _buildTopRidersList(effectiveBranchIds),
            const SizedBox(height: 32),
            // NEW: Top Customers Section
            buildSectionHeader('Top Customers', Icons.people_outline),
            const SizedBox(height: 16),
            _buildTopCustomersList(effectiveBranchIds),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderTypeTabs() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(25),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(25),
          color: Colors.deepPurple,
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.deepPurple,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        dividerColor: Colors.transparent,
        tabs: const [
          Tab(
            icon: Icon(Icons.dashboard_outlined, size: 18),
            text: 'All',
          ),
          Tab(
            icon: Icon(Icons.delivery_dining_outlined, size: 18),
            text: 'Delivery',
          ),
          Tab(
            icon: Icon(Icons.shopping_bag_outlined, size: 18),
            text: 'Takeaway',
          ),
          // --- NEW TAB ADDED ---
          Tab(
            icon: Icon(Icons.storefront_outlined, size: 18),
            text: 'Pickup',
          ),
          // --- END NEW TAB ---
          Tab(
            icon: Icon(Icons.table_bar_outlined, size: 18),
            text: 'Dine In',
          ),
        ],
      ),
    );
  }

  // Branch selector as a full-width card (placed in body for better visibility)
  Widget _buildBranchSelectorCard(
      UserScopeService userScope, BranchFilterService branchFilter) {
    return Container(
      padding: const EdgeInsets.all(16),
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
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.deepPurple.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.store_rounded,
              color: Colors.deepPurple,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select Branch',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  branchFilter.selectedBranchId == null
                      ? 'All Branches'
                      : branchFilter.getBranchName(branchFilter.selectedBranchId!),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.deepPurple,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            offset: const Offset(0, 45),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.deepPurple,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Text(
                    'Change',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  SizedBox(width: 4),
                  Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 20),
                ],
              ),
            ),
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                value: BranchFilterService.allBranchesValue,
                child: Row(children: [
                  Icon(
                      branchFilter.selectedBranchId == null
                          ? Icons.check_circle
                          : Icons.circle_outlined,
                      size: 20,
                      color: branchFilter.selectedBranchId == null
                          ? Colors.deepPurple
                          : Colors.grey),
                  const SizedBox(width: 12),
                  const Text('All Branches', style: TextStyle(fontSize: 15)),
                ]),
              ),
              const PopupMenuDivider(),
              ...userScope.branchIds.map((branchId) => PopupMenuItem<String>(
                    value: branchId,
                    child: Row(children: [
                      Icon(
                          branchFilter.selectedBranchId == branchId
                              ? Icons.check_circle
                              : Icons.circle_outlined,
                          size: 20,
                          color: branchFilter.selectedBranchId == branchId
                              ? Colors.deepPurple
                              : Colors.grey),
                      const SizedBox(width: 12),
                      Flexible(
                          child: Text(branchFilter.getBranchName(branchId),
                              style: const TextStyle(fontSize: 15),
                              overflow: TextOverflow.ellipsis)),
                    ]),
                  )),
            ],
            onSelected: (value) => branchFilter.selectBranch(value),
          ),
        ],
      ),
    );
  }

  // Branch selector dropdown (kept for reference, not used currently)
  Widget _buildBranchSelector(
      UserScopeService userScope, BranchFilterService branchFilter) {
    return Container(
      margin: const EdgeInsets.only(right: 16),
      child: PopupMenuButton<String>(
        offset: const Offset(0, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.deepPurple.withOpacity(0.1),
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: Colors.deepPurple.withOpacity(0.4), width: 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.store_rounded, size: 20, color: Colors.deepPurple),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: Text(
                  branchFilter.selectedBranchId == null
                      ? 'All Branches'
                      : branchFilter
                          .getBranchName(branchFilter.selectedBranchId!),
                  style: const TextStyle(
                    color: Colors.deepPurple,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.keyboard_arrow_down_rounded, color: Colors.deepPurple, size: 24),
            ],
          ),
        ),
        itemBuilder: (context) => [
          PopupMenuItem<String>(
            value: BranchFilterService.allBranchesValue,
            child: Row(children: [
              Icon(
                  branchFilter.selectedBranchId == null
                      ? Icons.check_circle
                      : Icons.circle_outlined,
                  size: 20,
                  color: branchFilter.selectedBranchId == null
                      ? Colors.deepPurple
                      : Colors.grey),
              const SizedBox(width: 12),
              const Text('All Branches', style: TextStyle(fontSize: 15)),
            ]),
          ),
          const PopupMenuDivider(),
          ...userScope.branchIds.map((branchId) => PopupMenuItem<String>(
                value: branchId,
                child: Row(children: [
                  Icon(
                      branchFilter.selectedBranchId == branchId
                          ? Icons.check_circle
                          : Icons.circle_outlined,
                      size: 20,
                      color: branchFilter.selectedBranchId == branchId
                          ? Colors.deepPurple
                          : Colors.grey),
                  const SizedBox(width: 12),
                  Flexible(
                      child: Text(branchFilter.getBranchName(branchId),
                          style: const TextStyle(fontSize: 15),
                          overflow: TextOverflow.ellipsis)),
                ]),
              )),
        ],
        onSelected: (value) => branchFilter.selectBranch(value),
      ),
    );
  }


  Widget _buildDateRangeSelector() {
    return Column(
      children: [
        // Quick Presets Row
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildDatePresetChip('Last 24h', const Duration(hours: 24)),
              const SizedBox(width: 8),
              _buildDatePresetChip('Last 7 Days', const Duration(days: 7)),
              const SizedBox(width: 8),
              _buildDatePresetChip('Last 15 Days', const Duration(days: 15)),
              const SizedBox(width: 8),
              _buildDatePresetChip('Last 30 Days', const Duration(days: 30)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Custom Date Range Selector
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.deepPurple.shade400, Colors.deepPurple.shade600],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.deepPurple.withOpacity(0.3),
                blurRadius: 15,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final newRange = await showDateRangePicker(
                      context: context,
                      initialDateRange: _dateRange,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 1)),
                      builder: (context, child) {
                        return Theme(
                          data: Theme.of(context).copyWith(
                            colorScheme: const ColorScheme.light(
                              primary: Colors.deepPurple,
                              onPrimary: Colors.white,
                              onSurface: Colors.black87,
                            ),
                          ),
                          child: child!,
                        );
                      },
                    );
                    if (newRange != null) {
                      setState(() {
                        _dateRange = DateTimeRange(
                          start: newRange.start,
                          end: DateTime(newRange.end.year, newRange.end.month,
                              newRange.end.day, 23, 59, 59),
                        );
                      });
                    }
                  },
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_outlined,
                          color: Colors.white, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Custom Range',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${DateFormat('MMM dd, yyyy').format(_dateRange.start)} - ${DateFormat('MMM dd, yyyy').format(_dateRange.end)}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _dateRange = DateTimeRange(
                        start: DateTime.now().subtract(const Duration(days: 7)),
                        end: DateTime.now(),
                      );
                    });
                  },
                  child: const Icon(
                    Icons.refresh_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDatePresetChip(String label, Duration duration) {
    final now = DateTime.now();
    final presetStart = now.subtract(duration);
    final isSelected = _dateRange.start.day == presetStart.day &&
        _dateRange.start.month == presetStart.month &&
        _dateRange.start.year == presetStart.year;

    return ActionChip(
      label: Text(label),
      backgroundColor: isSelected ? Colors.deepPurple : Colors.grey[200],
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.deepPurple,
        fontWeight: FontWeight.w600,
        fontSize: 12,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isSelected ? Colors.deepPurple : Colors.grey.shade300,
        ),
      ),
      onPressed: () {
        setState(() {
          _dateRange = DateTimeRange(
            start: presetStart,
            end: now,
          );
        });
      },
    );
  }

  Widget _buildAnalyticsOverviewCards(List<String> branchIds) {
    return StreamBuilder<QuerySnapshot>(
      stream: _getOrdersQuery(branchIds).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final orders = snapshot.data?.docs ?? [];
        final totalOrders = orders.length;

        // Define completed statuses for revenue calculation
        const completedStatuses = {'delivered', 'paid', 'collected', 'served'};

        // Count orders by status and collect them for detail view
        int cancelledCount = 0;
        int refundedCount = 0;
        int completedCount = 0;
        List<QueryDocumentSnapshot> cancelledOrders = [];
        List<QueryDocumentSnapshot> refundedOrders = [];
        List<QueryDocumentSnapshot> completedOrders = [];
        
        for (var doc in orders) {
          final data = doc.data() as Map<String, dynamic>;
          final status = (data['status'] as String?)?.toLowerCase() ?? '';
          if (status == 'cancelled') {
            cancelledCount++;
            cancelledOrders.add(doc);
          } else if (status == 'refunded') {
            refundedCount++;
            refundedOrders.add(doc);
          } else if (completedStatuses.contains(status)) {
            completedCount++;
            completedOrders.add(doc);
          }
        }

        // Calculate revenue only from completed orders
        final totalRevenue = orders.fold<double>(
          0,
          (sum, doc) {
            final data = doc.data() as Map<String, dynamic>;
            final status = (data['status'] as String?)?.toLowerCase() ?? '';
            if (completedStatuses.contains(status)) {
              return sum + ((data['totalAmount'] as num?)?.toDouble() ?? 0);
            }
            return sum;
          },
        );
        final avgOrderValue = completedCount > 0 ? totalRevenue / completedCount : 0;

        return Column(
          children: [
            // First row: Total Orders, Revenue, Avg Order
            Row(
              children: [
                Expanded(
                  child: _buildMetricCard(
                    'Total Orders',
                    totalOrders.toString(),
                    Icons.receipt_long_outlined,
                    Colors.blue,
                    onTap: () => _showOrdersDetailDialog(
                      context,
                      'All Orders',
                      orders,
                      Colors.blue,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildMetricCard(
                    'Revenue',
                    'QAR ${totalRevenue.toStringAsFixed(0)}',
                    Icons.attach_money_outlined,
                    Colors.green,
                    onTap: () => _showOrdersDetailDialog(
                      context,
                      'Completed Orders',
                      completedOrders,
                      Colors.green,
                      showRevenue: true,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildMetricCard(
                    'Avg Order',
                    'QAR ${avgOrderValue.toStringAsFixed(0)}',
                    Icons.trending_up_outlined,
                    Colors.orange,
                    onTap: () => _showOrdersDetailDialog(
                      context,
                      'Completed Orders',
                      completedOrders,
                      Colors.orange,
                      showRevenue: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Second row: Cancelled and Refunded Orders
            Row(
              children: [
                Expanded(
                  child: _buildMetricCard(
                    'Cancelled',
                    cancelledCount.toString(),
                    Icons.cancel_outlined,
                    Colors.red,
                    onTap: () => _showOrdersDetailDialog(
                      context,
                      'Cancelled Orders',
                      cancelledOrders,
                      Colors.red,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildMetricCard(
                    'Refunded',
                    refundedCount.toString(),
                    Icons.money_off_outlined,
                    Colors.purple,
                    onTap: () => _showOrdersDetailDialog(
                      context,
                      'Refunded Orders',
                      refundedOrders,
                      Colors.purple,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Percentage of problematic orders
                Expanded(
                  child: _buildMetricCard(
                    'Problem Rate',
                    totalOrders > 0
                        ? '${((cancelledCount + refundedCount) / totalOrders * 100).toStringAsFixed(1)}%'
                        : '0%',
                    Icons.warning_amber_outlined,
                    Colors.amber,
                    onTap: () => _showOrdersDetailDialog(
                      context,
                      'Problematic Orders',
                      [...cancelledOrders, ...refundedOrders],
                      Colors.amber,
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }


  Widget _buildMetricCard(
      String title, String value, IconData icon, Color color, {VoidCallback? onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.2)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(height: 8),

              // Center and scale long values
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.visible,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),

              const SizedBox(height: 2),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Shows a professional dialog with filtered order details
  void _showOrdersDetailDialog(
    BuildContext context,
    String title,
    List<QueryDocumentSnapshot> orders,
    Color themeColor, {
    bool showRevenue = false,
  }) {
    // Sort orders by timestamp (most recent first)
    final sortedOrders = List<QueryDocumentSnapshot>.from(orders);
    sortedOrders.sort((a, b) {
      final aTime = (a.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
      final bTime = (b.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
      if (aTime == null || bTime == null) return 0;
      return bTime.compareTo(aTime);
    });

    // Calculate total if showing revenue
    double totalAmount = 0;
    if (showRevenue) {
      for (var doc in sortedOrders) {
        final data = doc.data() as Map<String, dynamic>;
        totalAmount += (data['totalAmount'] as num?)?.toDouble() ?? 0;
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: themeColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(Icons.receipt_long_rounded, color: themeColor, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: themeColor,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${sortedOrders.length} orders',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (showRevenue)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: themeColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'QAR ${totalAmount.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: themeColor,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close_rounded, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Orders list
              Expanded(
                child: sortedOrders.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inbox_outlined, size: 64, color: Colors.grey[300]),
                            const SizedBox(height: 16),
                            Text(
                              'No orders found',
                              style: TextStyle(color: Colors.grey[500], fontSize: 16),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: sortedOrders.length,
                        itemBuilder: (context, index) {
                          final doc = sortedOrders[index];
                          final data = doc.data() as Map<String, dynamic>;
                          return _buildOrderDetailCard(data, themeColor, doc.id);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds a professional order detail card
  Widget _buildOrderDetailCard(Map<String, dynamic> data, Color themeColor, String orderId) {
    final status = (data['status'] as String?) ?? 'unknown';
    final orderType = (data['Order_type'] as String?) ?? 'unknown';
    final totalAmount = (data['totalAmount'] as num?)?.toDouble() ?? 0;
    final timestamp = data['timestamp'] as Timestamp?;
    final dailyOrderNumber = data['dailyOrderNumber'] as int? ?? 0;
    final items = List<Map<String, dynamic>>.from(data['items'] ?? []);
    final customerName = data['customerName'] as String? ?? '';
    final customerPhone = data['customerPhone'] as String? ?? '';

    // Format date
    String formattedDate = 'N/A';
    String formattedTime = 'N/A';
    if (timestamp != null) {
      final date = timestamp.toDate();
      formattedDate = DateFormat('MMM dd, yyyy').format(date);
      formattedTime = DateFormat('hh:mm a').format(date);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: _getStatusColor(status).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                '#$dailyOrderNumber',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: _getStatusColor(status),
                ),
              ),
            ),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  'QAR ${totalAmount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              _buildStatusBadge(status),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.access_time, size: 14, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Text(
                      '$formattedDate • $formattedTime',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _formatOrderType(orderType),
                    style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                  ),
                ),
              ],
            ),
          ),
          children: [
            // Customer info
            if (customerName.isNotEmpty || customerPhone.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.person_outline, size: 18, color: Colors.grey[600]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        customerName.isNotEmpty ? customerName : 'Customer',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                    if (customerPhone.isNotEmpty)
                      Text(
                        customerPhone,
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            // Items list
            Container(
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                    child: Row(
                      children: [
                        Icon(Icons.shopping_bag_outlined, size: 16, color: Colors.grey[600]),
                        const SizedBox(width: 8),
                        Text(
                          'Items (${items.length})',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  ...items.map((item) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          children: [
                            Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: themeColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Center(
                                child: Text(
                                  '${item['quantity'] ?? 1}x',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: themeColor,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                item['name'] ?? 'Unknown Item',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            Builder(
                              builder: (context) {
                                // Use discountedPrice if available for accurate display
                                final originalPrice = (item['price'] as num?)?.toDouble() ?? 0;
                                final discountedPrice = (item['discountedPrice'] as num?)?.toDouble();
                                final effectivePrice = (discountedPrice != null && discountedPrice > 0) 
                                    ? discountedPrice 
                                    : originalPrice;
                                final quantity = (item['quantity'] as num?)?.toInt() ?? 1;
                                return Text(
                                  'QAR ${(effectivePrice * quantity).toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[700],
                                    fontWeight: FontWeight.w500,
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Returns color based on order status
  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'delivered':
      case 'paid':
      case 'collected':
      case 'served':
        return Colors.green;
      case 'preparing':
        return Colors.orange;
      case 'ready':
        return Colors.blue;
      case 'cancelled':
        return Colors.red;
      case 'refunded':
        return Colors.purple;
      case 'pending':
        return Colors.amber;
      default:
        return Colors.grey;
    }
  }

  /// Builds a status badge widget
  Widget _buildStatusBadge(String status) {
    final color = _getStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  /// Formats order type for display
  String _formatOrderType(String type) {
    switch (type.toLowerCase()) {
      case 'delivery':
        return 'Delivery';
      case 'takeaway':
      case 'take_away':
        return 'Takeaway';
      case 'pickup':
        return 'Pickup';
      case 'dine_in':
        return 'Dine In';
      default:
        return type;
    }
  }

  Widget buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.deepPurple.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: Colors.deepPurple, size: 20),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.deepPurple,
          ),
        ),
      ],
    );
  }

  Widget _buildSalesChart(List<String> branchIds) {
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
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SizedBox(
          height: 300,
          child: StreamBuilder<QuerySnapshot>(
            stream: _getOrdersQuery(branchIds).snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return _buildEmptyState(
                  icon: Icons.bar_chart_outlined,
                  message: 'No sales data available for this range.',
                );
              }

              // Aggregate sales by day
              final ordersByDay =
                  snapshot.data!.docs.fold<Map<DateTime, double>>(
                {},
                (map, doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final timestamp = data['timestamp'] as Timestamp;
                  final date = timestamp.toDate();
                  final day = DateTime(date.year, date.month, date.day);
                  final total = (data['totalAmount'] as num?)?.toDouble() ?? 0;
                  map[day] = (map[day] ?? 0) + total;
                  return map;
                },
              );

              // Generate all days in the range
              final List<DateTime> allDays = [];
              DateTime current = DateTime(_dateRange.start.year,
                  _dateRange.start.month, _dateRange.start.day);
              final end = DateTime(_dateRange.end.year, _dateRange.end.month,
                      _dateRange.end.day)
                  .add(const Duration(days: 1));

              while (current.isBefore(end)) {
                allDays.add(current);
                current = current.add(const Duration(days: 1));
              }

              // Prepare chart data
              final chartData = allDays.map((day) {
                return SalesData(
                  day,
                  ordersByDay[day] ?? 0,
                  DateFormat('MMM dd').format(day),
                );
              }).toList();

              return SfCartesianChart(
                primaryXAxis: CategoryAxis(
                  majorGridLines: const MajorGridLines(width: 0),
                  axisLine: const AxisLine(width: 0),
                  labelStyle: TextStyle(color: Colors.black87, fontSize: 12),
                ),
                primaryYAxis: NumericAxis(
                  title: AxisTitle(
                    text: 'Sales Amount (QAR)',
                    textStyle: TextStyle(
                        color: Colors.black87, fontWeight: FontWeight.bold),
                  ),
                  majorGridLines:
                      const MajorGridLines(width: 0.5, color: Colors.grey),
                  axisLine: const AxisLine(width: 0),
                  labelStyle: TextStyle(color: Colors.black87, fontSize: 12),
                ),
                tooltipBehavior: TooltipBehavior(
                  enable: true,
                  header: '',
                  canShowMarker: false,
                  animationDuration: 0,
                  color: Colors.deepPurpleAccent,
                  textStyle: const TextStyle(color: Colors.white, fontSize: 14),
                  format: 'QAR point.y',
                ),
                series: <CartesianSeries<SalesData, String>>[
                  ColumnSeries<SalesData, String>(
                    dataSource: chartData,
                    xValueMapper: (SalesData sales, _) => sales.label,
                    yValueMapper: (SalesData sales, _) => sales.amount,
                    gradient: LinearGradient(
                      colors: [
                        Colors.deepPurple.shade300,
                        Colors.deepPurple.shade600,
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    width: 0.7,
                    animationDuration: 1000,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildTopItemsList(List<String> branchIds) {
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
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: StreamBuilder<QuerySnapshot>(
          stream: _getOrdersQuery(branchIds).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return _buildEmptyState(
                icon: Icons.restaurant_menu_outlined,
                message: 'No items sold in selected range.',
              );
            }

            // Only count items from completed orders
            const completedStatuses = {'delivered', 'paid', 'collected', 'served'};
            final itemCounts = <String, int>{};
            final itemRevenue = <String, double>{};

            for (var doc in snapshot.data!.docs) {
              final data = doc.data() as Map<String, dynamic>;
              final status = (data['status'] as String?)?.toLowerCase() ?? '';
              
              // Skip non-completed orders
              if (!completedStatuses.contains(status)) continue;
              
              final items =
                  List<Map<String, dynamic>>.from(data['items'] ?? []);

              for (var item in items) {
                final itemName = item['name'] ?? 'Unknown Item';
                final quantity = (item['quantity'] as num?)?.toInt() ?? 1;
                // Use discountedPrice if available, otherwise fall back to regular price
                // This ensures revenue calculations match actual amounts charged
                final originalPrice = (item['price'] as num?)?.toDouble() ?? 0;
                final discountedPrice = (item['discountedPrice'] as num?)?.toDouble();
                final effectivePrice = (discountedPrice != null && discountedPrice > 0) 
                    ? discountedPrice 
                    : originalPrice;

                itemCounts.update(itemName, (value) => value + quantity,
                    ifAbsent: () => quantity);
                itemRevenue.update(
                  itemName,
                  (value) => value + (effectivePrice * quantity),
                  ifAbsent: () => effectivePrice * quantity,
                );
              }
            }

            if (itemCounts.isEmpty) {
              return _buildEmptyState(
                icon: Icons.restaurant_menu_outlined,
                message: 'No items sold in selected range.',
              );
            }

            final sortedItems = itemCounts.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value));
            final topItems = sortedItems.take(5).toList();

            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: topItems.length,
              itemBuilder: (context, index) {
                final item = topItems[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.deepPurple.withOpacity(0.1),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              Colors.deepPurple.shade300,
                              Colors.deepPurple.shade500,
                            ],
                          ),
                        ),
                        child: Center(
                          child: Text(
                            '#${index + 1}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.key,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Revenue: QAR ${itemRevenue[item.key]?.toStringAsFixed(2) ?? '0.00'}',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${item.value}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: Colors.green,
                            ),
                          ),
                          Text(
                            'sold',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildOrderTypeDistributionChart(List<String> branchIds) {
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
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SizedBox(
          height: 300,
          child: StreamBuilder<QuerySnapshot>(
            stream: _getOrdersQuery(branchIds).snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return _buildEmptyState(
                  icon: Icons.pie_chart_outline,
                  message: 'No order type data for the selected range.',
                );
              }

              final orderTypeCounts = <String, int>{
                'delivery': 0,
                'takeaway': 0,
                'pickup': 0,
                'dine_in': 0,
              };
              int totalOrders = 0;

              for (var doc in snapshot.data!.docs) {
                final data = doc.data() as Map<String, dynamic>;
                String rawOrderType =
                    (data['Order_type'] as String?) ?? 'unknown';
                String cleanedRaw = rawOrderType.trim().toLowerCase();
                String normalizedKey;

                if (cleanedRaw == 'delivery') {
                  normalizedKey = 'delivery';
                } else if (cleanedRaw == 'takeaway' ||
                    cleanedRaw == 'take_away') {
                  normalizedKey = 'takeaway';
                } else if (cleanedRaw == 'pickup') {
                  // Add check for pickup
                  normalizedKey = 'pickup';
                } else if (cleanedRaw == 'dine_in') {
                  normalizedKey = 'dine_in';
                } else {
                  normalizedKey = 'unknown';
                }

                if (orderTypeCounts.containsKey(normalizedKey)) {
                  orderTypeCounts[normalizedKey] =
                      orderTypeCounts[normalizedKey]! + 1;
                  totalOrders++;
                }
              }

              final chartData = orderTypeCounts.entries
                  .where((entry) => entry.value > 0)
                  .map((entry) => OrderTypeData(
                        entry.key,
                        entry.value,
                        _getOrderTypeColor(entry.key),
                      ))
                  .toList();

              if (chartData.isEmpty) {
                return _buildEmptyState(
                  icon: Icons.pie_chart_outline,
                  message: 'No order type data for the selected range.',
                );
              }

              return SfCircularChart(
                legend: Legend(
                  isVisible: true,
                  overflowMode: LegendItemOverflowMode.wrap,
                  position: LegendPosition.bottom,
                  // ✅ IMPROVED: Better legend styling
                  textStyle: TextStyle(
                      color: Colors.grey[800],
                      fontSize: 13,
                      fontWeight: FontWeight.w500),
                  iconHeight: 12,
                  iconWidth: 12,
                  padding: 16,
                ),
                series: <PieSeries<OrderTypeData, String>>[
                  PieSeries<OrderTypeData, String>(
                    dataSource: chartData,
                    // ✅ FIXED: Legend now shows formatted text (e.g. "Dine In") instead of keys
                    xValueMapper: (OrderTypeData data, _) =>
                        _formatOrderTypeForPieLabel(data.orderType),
                    yValueMapper: (OrderTypeData data, _) => data.count,
                    pointColorMapper: (OrderTypeData data, _) => data.color,
                    dataLabelMapper: (OrderTypeData data, _) {
                      final percentage =
                          (data.count / totalOrders * 100).toStringAsFixed(1);
                      return '${_formatOrderTypeForPieLabel(data.orderType)}\n$percentage%';
                    },
                    dataLabelSettings: const DataLabelSettings(
                      isVisible: true,
                      labelPosition: ChartDataLabelPosition.inside,
                      // ✅ IMPROVED: High contrast black labels
                      textStyle: TextStyle(
                          fontSize: 11,
                          color: Colors.black87,
                          fontWeight: FontWeight.bold),
                      connectorLineSettings:
                          ConnectorLineSettings(type: ConnectorType.curve),
                    ),
                    explode: true,
                    explodeIndex: 0,
                    radius: '75%', // Slightly smaller to give breathing room
                    strokeWidth: 2, // ✅ IMPROVED: White separation lines
                    strokeColor: Colors.white,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState({required IconData icon, required String message}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: Colors.grey[400]),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Query<Map<String, dynamic>> _getOrdersQuery(List<String> branchIds) {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('Orders')
        .where('timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(_dateRange.start))
        .where('timestamp',
            isLessThanOrEqualTo: Timestamp.fromDate(_dateRange.end));
    
    // Filter by branch - arrayContainsAny supports up to 30 values
    if (branchIds.isNotEmpty) {
      if (branchIds.length == 1) {
        query = query.where('branchIds', arrayContains: branchIds.first);
      } else {
        query = query.where('branchIds', arrayContainsAny: branchIds);
      }
    }
    
    query = query.orderBy('timestamp', descending: true);

    if (_selectedOrderType != 'all') {
      query = query.where('Order_type', isEqualTo: _selectedOrderType);
    }
    return query;
  }

  Color _getOrderTypeColor(String orderType) {
    switch (orderType.toLowerCase()) {
      case 'delivery':
        return Colors.blue.shade600;
      case 'takeaway':
        return Colors.orange.shade600;
      case 'pickup': // Add color for pickup
        return Colors.purple.shade600;
      case 'dine_in':
        return Colors.green.shade600;
      default:
        return Colors.grey.shade400;
    }
  }

  String _formatOrderTypeForPieLabel(String normalizedKey) {
    switch (normalizedKey) {
      case 'all':
        return 'All Orders';
      case 'delivery':
        return 'Delivery';
      case 'takeaway':
        return 'Take Away';
      case 'pickup': // Add label for pickup
        return 'Pick Up';
      case 'dine_in':
        return 'Dine In';
      default:
        return 'Other';
    }
  }

  Widget _buildTopRidersList(List<String> branchIds) {
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
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: StreamBuilder<QuerySnapshot>(
          // Use branch-filtered query for consistency
          stream: _getOrdersQuery(branchIds).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _buildEmptyState(
                icon: Icons.error_outline,
                message: 'Error loading data: ${snapshot.error}',
              );
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return _buildEmptyState(
                icon: Icons.delivery_dining_outlined,
                message: 'No delivery data for this range.',
              );
            }

            // Aggregate by riderId - only count delivery orders with assigned riders
            final riderCounts = <String, int>{};
            for (var doc in snapshot.data!.docs) {
              final data = doc.data() as Map<String, dynamic>;
              final orderType =
                  (data['Order_type'] as String?)?.toLowerCase() ?? '';
              // Only count delivery orders
              if (orderType != 'delivery') continue;

              final riderId = data['riderId'] as String?;
              if (riderId != null && riderId.isNotEmpty) {
                riderCounts.update(riderId, (v) => v + 1, ifAbsent: () => 1);
              }
            }

            if (riderCounts.isEmpty) {
              return _buildEmptyState(
                icon: Icons.delivery_dining_outlined,
                message: 'No rider data available.',
              );
            }

            final sortedRiders = riderCounts.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value));
            final topRiders = sortedRiders.take(5).toList();

            // Fetch rider names from Drivers collection
            return FutureBuilder<List<Map<String, dynamic>>>(
              future: _fetchRiderNames(topRiders),
              builder: (context, riderSnapshot) {
                if (riderSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final ridersWithNames = riderSnapshot.data ?? [];

                if (ridersWithNames.isEmpty) {
                  return _buildEmptyState(
                    icon: Icons.delivery_dining_outlined,
                    message: 'Could not load rider data.',
                  );
                }

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: ridersWithNames.length,
                  itemBuilder: (context, index) {
                    final rider = ridersWithNames[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.blue.withOpacity(0.2)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [
                                  Colors.blue.shade300,
                                  Colors.blue.shade500,
                                ],
                              ),
                            ),
                            child: Center(
                              child: Text(
                                '#${index + 1}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              rider['name'] ?? 'Unknown Rider',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${rider['count']}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: Colors.blue,
                                ),
                              ),
                              Text(
                                'deliveries',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _fetchRiderNames(
      List<MapEntry<String, int>> riderEntries) async {
    final results = <Map<String, dynamic>>[];
    for (var entry in riderEntries) {
      try {
        final driverDoc = await FirebaseFirestore.instance
            .collection('Drivers')
            .doc(entry.key)
            .get();
        final name = driverDoc.data()?['name'] as String? ?? 'Unknown Rider';
        results.add({'name': name, 'count': entry.value, 'id': entry.key});
      } catch (e) {
        results.add({
          'name': 'Rider ${entry.key.substring(0, 6)}...',
          'count': entry.value,
          'id': entry.key
        });
      }
    }
    return results;
  }

  Widget _buildTopCustomersList(List<String> branchIds) {
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
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: StreamBuilder<QuerySnapshot>(
          stream: _getOrdersQuery(branchIds).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return _buildEmptyState(
                icon: Icons.people_outline,
                message: 'No customer data for this range.',
              );
            }

            final customerData = <String, Map<String, dynamic>>{};
            for (var doc in snapshot.data!.docs) {
              final data = doc.data() as Map<String, dynamic>;
              final customerName = data['customerName'] as String? ??
                  data['customer_name'] as String? ??
                  'Unknown';
              final amount = (data['totalAmount'] as num?)?.toDouble() ?? 0;
              customerData.update(
                customerName,
                (v) => {
                  'orderCount': (v['orderCount'] as int) + 1,
                  'totalSpend': (v['totalSpend'] as double) + amount
                },
                ifAbsent: () => {'orderCount': 1, 'totalSpend': amount},
              );
            }

            if (customerData.isEmpty) {
              return _buildEmptyState(
                icon: Icons.people_outline,
                message: 'No customer data available.',
              );
            }

            final sortedCustomers = customerData.entries.toList()
              ..sort((a, b) => (b.value['orderCount'] as int)
                  .compareTo(a.value['orderCount'] as int));
            final topCustomers = sortedCustomers.take(5).toList();

            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: topCustomers.length,
              itemBuilder: (context, index) {
                final customer = topCustomers[index];
                final orderCount = customer.value['orderCount'] as int;
                final totalSpend = customer.value['totalSpend'] as double;
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.green.withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              Colors.green.shade300,
                              Colors.green.shade500,
                            ],
                          ),
                        ),
                        child: Center(
                          child: Text(
                            '#${index + 1}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              customer.key,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Total Spend: QAR ${totalSpend.toStringAsFixed(2)}',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '$orderCount',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: Colors.green,
                            ),
                          ),
                          Text(
                            'orders',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _showExportDialog(BuildContext context) async {
    DateTimeRange reportDateRange = _dateRange;
    String reportOrderType = _selectedOrderType;
    String exportFormat = 'pdf'; // Default to PDF

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.file_download_outlined,
                      color: Colors.deepPurple, size: 28),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Export Report',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Configure your report settings below.',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 20),

                  // Export Format Selection
                  const Text(
                    'Export Format',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () =>
                              setDialogState(() => exportFormat = 'pdf'),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: exportFormat == 'pdf'
                                  ? Colors.deepPurple.withOpacity(0.1)
                                  : Colors.grey[100],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: exportFormat == 'pdf'
                                    ? Colors.deepPurple
                                    : Colors.grey[300]!,
                                width: exportFormat == 'pdf' ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.picture_as_pdf,
                                  color: exportFormat == 'pdf'
                                      ? Colors.deepPurple
                                      : Colors.grey[600],
                                  size: 32,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'PDF',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: exportFormat == 'pdf'
                                        ? Colors.deepPurple
                                        : Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InkWell(
                          onTap: () =>
                              setDialogState(() => exportFormat = 'excel'),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: exportFormat == 'excel'
                                  ? Colors.green.withOpacity(0.1)
                                  : Colors.grey[100],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: exportFormat == 'excel'
                                    ? Colors.green
                                    : Colors.grey[300]!,
                                width: exportFormat == 'excel' ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.table_chart,
                                  color: exportFormat == 'excel'
                                      ? Colors.green
                                      : Colors.grey[600],
                                  size: 32,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Excel',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: exportFormat == 'excel'
                                        ? Colors.green
                                        : Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Date Range Selection
                  const Text(
                    'Date Range',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () async {
                      final picked = await showDateRangePicker(
                        context: context,
                        initialDateRange: reportDateRange,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 1)),
                        builder: (context, child) {
                          return Theme(
                            data: Theme.of(context).copyWith(
                              colorScheme: const ColorScheme.light(
                                primary: Colors.deepPurple,
                                onPrimary: Colors.white,
                                onSurface: Colors.black87,
                              ),
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (picked != null) {
                        setDialogState(() {
                          reportDateRange = DateTimeRange(
                            start: picked.start,
                            end: DateTime(picked.end.year, picked.end.month,
                                picked.end.day, 23, 59, 59),
                          );
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.deepPurple.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.deepPurple.withOpacity(0.2)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_month,
                              color: Colors.deepPurple),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '${DateFormat('MMM dd, yyyy').format(reportDateRange.start)} - ${DateFormat('MMM dd, yyyy').format(reportDateRange.end)}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                          ),
                          const Icon(Icons.edit,
                              size: 18, color: Colors.deepPurple),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Order Type Selection
                  const Text(
                    'Order Type',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildOrderTypeChip('all', 'All', reportOrderType, (val) {
                        setDialogState(() => reportOrderType = val);
                      }),
                      _buildOrderTypeChip(
                          'delivery', 'Delivery', reportOrderType, (val) {
                        setDialogState(() => reportOrderType = val);
                      }),
                      _buildOrderTypeChip(
                          'takeaway', 'Takeaway', reportOrderType, (val) {
                        setDialogState(() => reportOrderType = val);
                      }),
                      _buildOrderTypeChip('dine_in', 'Dine In', reportOrderType,
                          (val) {
                        setDialogState(() => reportOrderType = val);
                      }),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                icon: Icon(
                  exportFormat == 'pdf'
                      ? Icons.picture_as_pdf
                      : Icons.table_chart,
                  size: 18,
                ),
                label: Text('Download ${exportFormat.toUpperCase()}'),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      exportFormat == 'pdf' ? Colors.deepPurple : Colors.green,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  Navigator.pop(ctx);
                  if (exportFormat == 'pdf') {
                    await _generatePdfReportWithParams(
                        reportDateRange, reportOrderType);
                  } else {
                    await _generateExcelReportWithParams(
                        reportDateRange, reportOrderType);
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildOrderTypeChip(
      String value, String label, String selected, Function(String) onSelect) {
    final isSelected = value == selected;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: Colors.deepPurple,
      backgroundColor: Colors.grey[200],
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.deepPurple,
        fontWeight: FontWeight.w600,
      ),
      onSelected: (_) => onSelect(value),
    );
  }

  Future<void> _generatePdfReportWithParams(
      DateTimeRange reportDateRange, String reportOrderType) async {
    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: CircularProgressIndicator(color: Colors.deepPurple),
      ),
    );

    try {
      // Build query with passed parameters
      Query<Map<String, dynamic>> query = FirebaseFirestore.instance
          .collection('Orders')
          .where('timestamp',
              isGreaterThanOrEqualTo: Timestamp.fromDate(reportDateRange.start))
          .where('timestamp',
              isLessThanOrEqualTo: Timestamp.fromDate(reportDateRange.end))
          .orderBy('timestamp', descending: true);

      if (reportOrderType != 'all') {
        query = query.where('Order_type', isEqualTo: reportOrderType);
      }

      final ordersSnapshot = await query.get();
      final orders = ordersSnapshot.docs;

      // Calculate KPIs
      final totalOrders = orders.length;
      final totalRevenue = orders.fold<double>(
        0,
        (sum, doc) {
          final data = doc.data();
          return sum + ((data['totalAmount'] as num?)?.toDouble() ?? 0);
        },
      );
      final avgOrderValue = totalOrders > 0 ? totalRevenue / totalOrders : 0.0;

      // Aggregate top items with detailed pricing info
      final itemCounts = <String, int>{};
      final itemRevenue = <String, double>{};
      final itemOriginalRevenue = <String, double>{}; // Revenue at original prices
      final itemHasDiscount = <String, bool>{}; // Track if item ever had discounts
      for (var doc in orders) {
        final data = doc.data();
        final items = List<Map<String, dynamic>>.from(data['items'] ?? []);
        for (var item in items) {
          final itemName = item['name'] ?? 'Unknown Item';
          final quantity = (item['quantity'] as num?)?.toInt() ?? 1;
          // Use discountedPrice if available for accurate revenue calculation
          final originalPrice = (item['price'] as num?)?.toDouble() ?? 0;
          final discountedPrice = (item['discountedPrice'] as num?)?.toDouble();
          final hasDiscount = discountedPrice != null && discountedPrice > 0 && discountedPrice < originalPrice;
          final effectivePrice = hasDiscount ? discountedPrice! : originalPrice;
          
          itemCounts.update(itemName, (v) => v + quantity,
              ifAbsent: () => quantity);
          itemRevenue.update(itemName, (v) => v + (effectivePrice * quantity),
              ifAbsent: () => effectivePrice * quantity);
          itemOriginalRevenue.update(itemName, (v) => v + (originalPrice * quantity),
              ifAbsent: () => originalPrice * quantity);
          if (hasDiscount) {
            itemHasDiscount[itemName] = true;
          }
        }
      }
      final topItems = itemCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final topItemsList = topItems
          .take(10)
          .map((e) => {
                'name': e.key,
                'quantity': e.value,
                'revenue': itemRevenue[e.key] ?? 0,
                'originalRevenue': itemOriginalRevenue[e.key] ?? 0,
                'hasDiscount': itemHasDiscount[e.key] ?? false,
                'savings': (itemOriginalRevenue[e.key] ?? 0) - (itemRevenue[e.key] ?? 0),
              })
          .toList();

      // Aggregate order type distribution
      final orderTypeCounts = <String, int>{
        'delivery': 0,
        'takeaway': 0,
        'pickup': 0,
        'dine_in': 0
      };
      for (var doc in orders) {
        final data = doc.data();
        final rawType =
            (data['Order_type'] as String?)?.toLowerCase().trim() ?? 'unknown';
        String normalizedKey;
        if (rawType == 'delivery')
          normalizedKey = 'delivery';
        else if (rawType == 'takeaway' || rawType == 'take_away')
          normalizedKey = 'takeaway';
        else if (rawType == 'pickup')
          normalizedKey = 'pickup';
        else if (rawType == 'dine_in')
          normalizedKey = 'dine_in';
        else
          normalizedKey = 'unknown';
        if (orderTypeCounts.containsKey(normalizedKey)) {
          orderTypeCounts[normalizedKey] = orderTypeCounts[normalizedKey]! + 1;
        }
      }

      // Aggregate top riders (for delivery orders) using riderId
      final riderIdCounts = <String, int>{};
      for (var doc in orders) {
        final data = doc.data();
        final riderId = data['riderId'] as String?;
        if (riderId != null && riderId.isNotEmpty) {
          riderIdCounts.update(riderId, (v) => v + 1, ifAbsent: () => 1);
        }
      }
      final topRiderIds = riderIdCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      // Fetch rider names from Drivers collection
      final topRidersList = <Map<String, dynamic>>[];
      for (var entry in topRiderIds.take(5)) {
        try {
          final driverDoc = await FirebaseFirestore.instance
              .collection('Drivers')
              .doc(entry.key)
              .get();
          final name = driverDoc.data()?['name'] as String? ?? 'Unknown Rider';
          topRidersList.add({'name': name, 'count': entry.value});
        } catch (e) {
          topRidersList.add({
            'name': 'Rider ${entry.key.substring(0, 6)}...',
            'count': entry.value
          });
        }
      }

      // Aggregate top customers
      final customerData = <String, Map<String, dynamic>>{};
      for (var doc in orders) {
        final data = doc.data();
        final customerName = data['customerName'] as String? ??
            data['customer_name'] as String? ??
            'Unknown';
        final amount = (data['totalAmount'] as num?)?.toDouble() ?? 0;
        customerData.update(
          customerName,
          (v) => {
            'orderCount': (v['orderCount'] as int) + 1,
            'totalSpend': (v['totalSpend'] as double) + amount
          },
          ifAbsent: () => {'orderCount': 1, 'totalSpend': amount},
        );
      }
      final topCustomers = customerData.entries.toList()
        ..sort((a, b) => (b.value['orderCount'] as int)
            .compareTo(a.value['orderCount'] as int));
      final topCustomersList = topCustomers
          .take(5)
          .map((e) => {
                'name': e.key,
                'orderCount': e.value['orderCount'],
                'totalSpend': e.value['totalSpend'],
              })
          .toList();

      // Count cancelled and refunded orders
      int cancelledCount = 0;
      int refundedCount = 0;
      for (var doc in orders) {
        final data = doc.data();
        final status = (data['status'] as String?)?.toLowerCase() ?? '';
        if (status == 'cancelled') cancelledCount++;
        if (status == 'refunded') refundedCount++;
      }

      // Close loading dialog
      if (mounted) Navigator.pop(context);

      // Generate PDF
      await AnalyticsPdfService.generateReport(
        context: context,
        reportTitle: reportOrderType == 'all'
            ? 'Full Analytics Report'
            : '${_formatOrderTypeForPieLabel(reportOrderType)} Report',
        dateRange: reportDateRange,
        orderType: reportOrderType,
        totalOrders: totalOrders,
        totalRevenue: totalRevenue,
        avgOrderValue: avgOrderValue,
        topItems: topItemsList,
        orderTypeDistribution: orderTypeCounts,
        cancelledCount: cancelledCount,
        refundedCount: refundedCount,
        topRiders: topRidersList.isNotEmpty ? topRidersList : null,
        topCustomers: topCustomersList.isNotEmpty ? topCustomersList : null,
      );
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating report: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _generateExcelReportWithParams(
      DateTimeRange reportDateRange, String reportOrderType) async {
    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: CircularProgressIndicator(color: Colors.green),
      ),
    );

    try {
      // Build query with passed parameters
      Query<Map<String, dynamic>> query = FirebaseFirestore.instance
          .collection('Orders')
          .where('timestamp',
              isGreaterThanOrEqualTo: Timestamp.fromDate(reportDateRange.start))
          .where('timestamp',
              isLessThanOrEqualTo: Timestamp.fromDate(reportDateRange.end))
          .orderBy('timestamp', descending: true);

      if (reportOrderType != 'all') {
        query = query.where('Order_type', isEqualTo: reportOrderType);
      }

      final ordersSnapshot = await query.get();
      final orders = ordersSnapshot.docs;

      // Create Excel workbook
      final excelFile = excel_lib.Excel.createExcel();

      // ===== Summary Sheet =====
      final summarySheet = excelFile['Summary'];

      // Calculate KPIs
      final totalOrders = orders.length;
      final totalRevenue = orders.fold<double>(
        0,
        (sum, doc) {
          final data = doc.data();
          return sum + ((data['totalAmount'] as num?)?.toDouble() ?? 0);
        },
      );
      final avgOrderValue = totalOrders > 0 ? totalRevenue / totalOrders : 0.0;

      // Count cancelled and refunded
      int cancelledCount = 0;
      int refundedCount = 0;
      for (var doc in orders) {
        final data = doc.data();
        final status = (data['status'] as String?)?.toLowerCase() ?? '';
        if (status == 'cancelled') cancelledCount++;
        if (status == 'refunded') refundedCount++;
      }

      // Write summary data
      summarySheet
          .appendRow([excel_lib.TextCellValue('Analytics Report Summary')]);
      summarySheet.appendRow([
        excel_lib.TextCellValue('Date Range'),
        excel_lib.TextCellValue(
            '${DateFormat('MMM dd, yyyy').format(reportDateRange.start)} - ${DateFormat('MMM dd, yyyy').format(reportDateRange.end)}')
      ]);
      summarySheet.appendRow([
        excel_lib.TextCellValue('Order Type'),
        excel_lib.TextCellValue(_formatOrderTypeForPieLabel(reportOrderType))
      ]);
      summarySheet.appendRow([excel_lib.TextCellValue('')]);
      summarySheet.appendRow([
        excel_lib.TextCellValue('Metric'),
        excel_lib.TextCellValue('Value')
      ]);
      summarySheet.appendRow([
        excel_lib.TextCellValue('Total Orders'),
        excel_lib.IntCellValue(totalOrders)
      ]);
      summarySheet.appendRow([
        excel_lib.TextCellValue('Total Revenue (QAR)'),
        excel_lib.DoubleCellValue(totalRevenue)
      ]);
      summarySheet.appendRow([
        excel_lib.TextCellValue('Average Order Value (QAR)'),
        excel_lib.DoubleCellValue(avgOrderValue)
      ]);
      summarySheet.appendRow([
        excel_lib.TextCellValue('Cancelled Orders'),
        excel_lib.IntCellValue(cancelledCount)
      ]);
      summarySheet.appendRow([
        excel_lib.TextCellValue('Refunded Orders'),
        excel_lib.IntCellValue(refundedCount)
      ]);

      // ===== Orders Sheet =====
      final ordersSheet = excelFile['Orders'];
      ordersSheet.appendRow([
        excel_lib.TextCellValue('Order ID'),
        excel_lib.TextCellValue('Date'),
        excel_lib.TextCellValue('Customer'),
        excel_lib.TextCellValue('Order Type'),
        excel_lib.TextCellValue('Status'),
        excel_lib.TextCellValue('Total Amount (QAR)'),
        excel_lib.TextCellValue('Payment Method'),
      ]);

      for (var doc in orders) {
        final data = doc.data();
        final timestamp = data['timestamp'] as Timestamp?;
        ordersSheet.appendRow([
          excel_lib.TextCellValue(doc.id),
          excel_lib.TextCellValue(timestamp != null
              ? DateFormat('yyyy-MM-dd HH:mm').format(timestamp.toDate())
              : ''),
          excel_lib.TextCellValue(data['customerName'] as String? ??
              data['customer_name'] as String? ??
              'Unknown'),
          excel_lib.TextCellValue(_formatOrderTypeForPieLabel(
              (data['Order_type'] as String?) ?? 'unknown')),
          excel_lib.TextCellValue((data['status'] as String?) ?? 'unknown'),
          excel_lib.DoubleCellValue(
              (data['totalAmount'] as num?)?.toDouble() ?? 0),
          excel_lib.TextCellValue(
              (data['payment_method'] as String?) ?? 'unknown'),
        ]);
      }

      // ===== Top Items Sheet with Price Breakdown =====
      final itemsSheet = excelFile['Top Items'];
      itemsSheet.appendRow([
        excel_lib.TextCellValue('Item Name'),
        excel_lib.TextCellValue('Quantity Sold'),
        excel_lib.TextCellValue('Original Revenue (QAR)'),
        excel_lib.TextCellValue('Actual Revenue (QAR)'),
        excel_lib.TextCellValue('Discount Given (QAR)'),
        excel_lib.TextCellValue('Has Discount'),
      ]);

      final itemCounts = <String, int>{};
      final itemRevenue = <String, double>{};
      final itemOriginalRevenue = <String, double>{};
      final itemHasDiscount = <String, bool>{};
      for (var doc in orders) {
        final data = doc.data();
        final items = List<Map<String, dynamic>>.from(data['items'] ?? []);
        for (var item in items) {
          final itemName = item['name'] ?? 'Unknown Item';
          final quantity = (item['quantity'] as num?)?.toInt() ?? 1;
          // Use discountedPrice if available for accurate revenue calculation
          final originalPrice = (item['price'] as num?)?.toDouble() ?? 0;
          final discountedPrice = (item['discountedPrice'] as num?)?.toDouble();
          final hasDiscount = discountedPrice != null && discountedPrice > 0 && discountedPrice < originalPrice;
          final effectivePrice = hasDiscount ? discountedPrice! : originalPrice;
          
          itemCounts.update(itemName, (v) => v + quantity,
              ifAbsent: () => quantity);
          itemRevenue.update(itemName, (v) => v + (effectivePrice * quantity),
              ifAbsent: () => effectivePrice * quantity);
          itemOriginalRevenue.update(itemName, (v) => v + (originalPrice * quantity),
              ifAbsent: () => originalPrice * quantity);
          if (hasDiscount) {
            itemHasDiscount[itemName] = true;
          }
        }
      }
      final sortedItems = itemCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (var item in sortedItems.take(20)) {
        final originalRev = itemOriginalRevenue[item.key] ?? 0;
        final actualRev = itemRevenue[item.key] ?? 0;
        final discount = originalRev - actualRev;
        final hasDiscount = itemHasDiscount[item.key] ?? false;
        itemsSheet.appendRow([
          excel_lib.TextCellValue(item.key),
          excel_lib.IntCellValue(item.value),
          excel_lib.DoubleCellValue(originalRev),
          excel_lib.DoubleCellValue(actualRev),
          excel_lib.DoubleCellValue(discount),
          excel_lib.TextCellValue(hasDiscount ? 'Yes' : 'No'),
        ]);
      }
      
      // Add total discounts row
      final totalOriginal = itemOriginalRevenue.values.fold<double>(0, (a, b) => a + b);
      final totalActual = itemRevenue.values.fold<double>(0, (a, b) => a + b);
      final totalDiscount = totalOriginal - totalActual;
      itemsSheet.appendRow([]);
      itemsSheet.appendRow([
        excel_lib.TextCellValue('TOTAL'),
        excel_lib.TextCellValue(''),
        excel_lib.DoubleCellValue(totalOriginal),
        excel_lib.DoubleCellValue(totalActual),
        excel_lib.DoubleCellValue(totalDiscount),
        excel_lib.TextCellValue(''),
      ]);

      // Remove the default 'Sheet1'
      excelFile.delete('Sheet1');

      // Save file
      final fileBytes = excelFile.save();
      if (fileBytes == null) throw Exception('Failed to generate Excel file');

      final fileName =
          'Analytics_Report_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx';

      // Save to temp directory first, then share
      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/$fileName';
      final file = File(filePath);
      await file.writeAsBytes(fileBytes);

      if (mounted) Navigator.pop(context);

      // Open the file directly
      final result = await OpenFile.open(filePath);

      if (mounted) {
        if (result.type == ResultType.done) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Opening Excel report...'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Could not open file: ${result.message}'), // Fallback if no app found
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: 'Retry',
                textColor: Colors.white,
                onPressed: () => OpenFile.open(filePath),
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating Excel report: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

class SalesData {
  final DateTime date;
  final double amount;
  final String label;
  SalesData(this.date, this.amount, this.label);
}

class OrderTypeData {
  final String orderType;
  final int count;
  final Color color;
  OrderTypeData(this.orderType, this.count, this.color);
}
