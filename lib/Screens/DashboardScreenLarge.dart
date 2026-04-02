import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../Widgets/OrderService.dart';
import '../Widgets/BranchFilterService.dart';

import '../constants.dart';
import '../main.dart';
import '../services/DashboardThemeService.dart'; // ✅ Added for Dark/Light Theme
import '../Widgets/ExportReportDialog.dart';
import '../Widgets/BusinessPerformancePanel.dart';
import '../services/inventory/InventoryService.dart';
import '../Models/IngredientModel.dart';

// ─── Theme Colors ───────────────────────────────────────────────────────────
class _DashColors {
  final bool isDark;

  const _DashColors({required this.isDark});

  Color get backgroundDark => isDark ? const Color(0xFF1A1A2E) : Colors.grey[50]!;
  Color get surfaceDark => isDark ? const Color(0xFF16213E) : Colors.white;
  Color get primary => Colors.deepPurple;
  Color get primaryLight => const Color(0xFFBB86FC);
  Color get textPrimary => isDark ? Colors.white : Colors.black87;
  Color get textSecondary => isDark ? const Color(0xFF94A3B8) : Colors.grey[600]!;
  Color get borderSubtle => isDark ? const Color(0x0DFFFFFF) : Colors.black.withOpacity(0.05);
}

// ─── Chart Data Model ───────────────────────────────────────────────────────
class _HourlyOrderData {
  final String hour;
  final double revenue;
  final int orderCount;
  _HourlyOrderData(this.hour, this.revenue, this.orderCount);
}

class DashboardScreenLarge extends StatelessWidget {
  final Function(int) onTabChange;

  const DashboardScreenLarge({super.key, required this.onTabChange});

  // ─── Data Streams ───────────────────────────────────────────────────────
  Stream<QuerySnapshot<Map<String, dynamic>>> _getTodayOrdersStream(
      BuildContext context) {
    final userScope = Provider.of<UserScopeService>(context, listen: true);
    final branchFilter =
        Provider.of<BranchFilterService>(context, listen: true);
    final filterBranchIds =
        branchFilter.getFilterBranchIds(userScope.branchIds);
    return OrderService().getTodayOrdersStream(
        userScope: userScope, filterBranchIds: filterBranchIds);
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _getActiveRidersStream(
      BuildContext context) {
    final userScope = Provider.of<UserScopeService>(context, listen: true);
    final branchFilter =
        Provider.of<BranchFilterService>(context, listen: true);
    final filterBranchIds =
        branchFilter.getFilterBranchIds(userScope.branchIds);
    return OrderService().getActiveRidersStream(
        userScope: userScope, filterBranchIds: filterBranchIds);
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _getAvailableMenuItemsStream(
      BuildContext context) {
    final userScope = Provider.of<UserScopeService>(context, listen: true);
    final branchFilter =
        Provider.of<BranchFilterService>(context, listen: true);
    final filterBranchIds =
        branchFilter.getFilterBranchIds(userScope.branchIds);
    return OrderService().getAvailableMenuItemsStream(
        userScope: userScope, filterBranchIds: filterBranchIds);
  }

  Stream<List<IngredientModel>> _getIngredientsStream(BuildContext context) {
    final userScope = Provider.of<UserScopeService>(context, listen: true);
    final branchFilter = Provider.of<BranchFilterService>(context, listen: true);
    final filterBranchIds = branchFilter.getFilterBranchIds(userScope.branchIds);
    return InventoryService().streamIngredients(
      filterBranchIds.isEmpty ? userScope.branchIds : filterBranchIds,
      isSuperAdmin: userScope.isSuperAdmin,
    );
  }

  @override
  Widget build(BuildContext context) {
    final userScope = context.watch<UserScopeService>();
    final branchFilter = context.watch<BranchFilterService>();
    final themeService = context.watch<DashboardThemeService>();
    final isDark = themeService.isDarkMode;
    final dashColors = _DashColors(isDark: isDark);

    return Scaffold(
      backgroundColor: dashColors.backgroundDark,
      body: Column(
        children: [
          // ─── Sticky Header ─────────────────────────────────────────
          _buildHeader(context, userScope, branchFilter, dashColors),
          // ─── Scrollable Content ────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1400),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildKpiCardsRow(context, dashColors),
                      const SizedBox(height: 32),
                      BusinessPerformancePanel(
                        branchIds: branchFilter.getFilterBranchIds(userScope.branchIds),
                        primaryColor: dashColors.primary,
                        surfaceColor: dashColors.surfaceDark,
                        textColor: dashColors.textPrimary,
                      ),
                      const SizedBox(height: 32),
                      _buildChartSection(context, dashColors),
                      const SizedBox(height: 32),
                      _buildRecentOrdersTable(context, dashColors),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HEADER
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildHeader(BuildContext context, UserScopeService userScope,
      BranchFilterService branchFilter, _DashColors dashColors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      decoration: BoxDecoration(
        color: dashColors.backgroundDark,
        border: Border(
          bottom: BorderSide(color: dashColors.borderSubtle, width: 1),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Left: Title
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Dashboard Overview',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    color: dashColors.textPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Track orders, riders, and revenue in real-time.',
                  style: TextStyle(
                    fontSize: 14,
                    color: dashColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          // Branch selector removed — now global in MainScreen app bar
          // Export button
          _buildHeaderButton(
            icon: Icons.download_rounded,
            label: 'Export Report',
            onTap: () {
              ExportReportDialog.show(context);
            },
            dashColors: dashColors,
          ),
          const SizedBox(width: 12),
          // Primary action removed
        ],
      ),
    );
  }

  Widget _buildHeaderButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required _DashColors dashColors,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: dashColors.surfaceDark,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: dashColors.borderSubtle),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: dashColors.textPrimary),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: dashColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBranchChip(BuildContext context,
      BranchFilterService branchFilter, UserScopeService userScope, _DashColors dashColors) {
    return Container(
      height: 44, // Match sibling button heights
      decoration: BoxDecoration(
        color: dashColors.surfaceDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: dashColors.borderSubtle),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: branchFilter.selectedBranchId ??
              BranchFilterService.allBranchesValue,
          icon: Icon(Icons.storefront_outlined,
              size: 18, color: dashColors.textPrimary),
          dropdownColor: dashColors.surfaceDark,
          style: TextStyle(
            color: dashColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          onChanged: (String? newValue) {
            if (newValue != null) {
              branchFilter.selectBranch(
                  newValue == BranchFilterService.allBranchesValue
                      ? null
                      : newValue);
            }
          },
          items: [
            DropdownMenuItem<String>(
              value: BranchFilterService.allBranchesValue,
              child: Text('All Branches', style: TextStyle(color: dashColors.textPrimary)),
            ),
            ...userScope.branchIds
                .where((id) => id != BranchFilterService.allBranchesValue)
                .toSet()
                .map((id) {
              return DropdownMenuItem<String>(
                value: id,
                child: Text(branchFilter.getBranchName(id),
                  style: TextStyle(color: dashColors.textPrimary)),
              );
            }),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // KPI CARDS ROW
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildKpiCardsRow(BuildContext context, _DashColors dashColors) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cards = _buildKpiCards(context, dashColors);
        
        // Mobile/Tablet views (narrower than 900) - 2 cards per row
        if (constraints.maxWidth < 900) {
          return Wrap(
            spacing: 16,
            runSpacing: 16,
            children: cards
                .map((card) => SizedBox(
                      width: (constraints.maxWidth - 16) / 2,
                      child: card,
                    ))
                .toList(),
          );
        }
        
        // PC views - 4 cards per row
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: cards
              .map((card) => SizedBox(
                    width: (constraints.maxWidth - (16 * 3)) / 4,
                    child: card,
                  ))
              .toList(),
        );
      },
    );
  }

  List<Widget> _buildKpiCards(BuildContext context, _DashColors dashColors) {
    return [
      // 1. Today's Orders
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _getTodayOrdersStream(context),
        builder: (context, snapshot) {
          final count = snapshot.hasData ? snapshot.data!.docs.length : 0;
          final isLoading = !snapshot.hasData;
          return _KpiCard(
            title: "Today's Orders",
            value: isLoading ? '...' : count.toString(),
            icon: Icons.shopping_bag_outlined,
            iconColor: Colors.blueAccent,
            badge: isLoading ? null : '+$count today',
            badgeColor: Colors.blueAccent,
            onTap: () => onTabChange(2),
            dashColors: dashColors,
          );
        },
      ),
      // 2. Active Riders
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _getActiveRidersStream(context),
        builder: (context, snapshot) {
          final count = snapshot.hasData ? snapshot.data!.docs.length : 0;
          final isLoading = !snapshot.hasData;
          return _KpiCard(
            title: 'Active Riders',
            value: isLoading ? '...' : count.toString(),
            icon: Icons.delivery_dining_outlined,
            iconColor: Colors.green,
            badge: isLoading
                ? null
                : count > 0
                    ? 'Online'
                    : 'None active',
            badgeColor: count > 0 ? Colors.green : Colors.orange,
            onTap: () => onTabChange(4),
            dashColors: dashColors,
          );
        },
      ),
      // 3. Total Revenue
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _getTodayOrdersStream(context),
        builder: (context, snapshot) {
          double revenue = 0;
          if (snapshot.hasData) {
            revenue = OrderService.calculateRevenue(snapshot.data!.docs);
          }
          final isLoading = !snapshot.hasData;
          return _KpiCard(
            title: 'Total Revenue',
            value: isLoading
                ? '...'
                : 'QAR ${revenue.toStringAsFixed(2)}',
            icon: Icons.attach_money_rounded,
            iconColor: Colors.orangeAccent,
            badge: isLoading ? null : 'Today',
            badgeColor: dashColors.primary,
            onTap: () => onTabChange(2),
            dashColors: dashColors,
          );
        },
      ),
      // 4. Menu Items
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _getAvailableMenuItemsStream(context),
        builder: (context, snapshot) {
          final count = snapshot.hasData ? snapshot.data!.docs.length : 0;
          final isLoading = !snapshot.hasData;
          return _KpiCard(
            title: 'Menu Items',
            value: isLoading ? '...' : count.toString(),
            icon: Icons.restaurant_menu_rounded,
            iconColor: Colors.purpleAccent,
            badge: isLoading ? null : 'Available',
            badgeColor: Colors.purpleAccent,
            onTap: () => onTabChange(1),
            dashColors: dashColors,
          );
        },
      ),
      // 5. Orders in Kitchen
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _getTodayOrdersStream(context),
        builder: (context, snapshot) {
          int count = 0;
          if (snapshot.hasData) {
            count = snapshot.data!.docs.where((doc) {
              final status = doc.data()['status'] as String? ?? '';
              return status.toLowerCase() == AppConstants.statusPreparing.toLowerCase();
            }).length;
          }
          final isLoading = !snapshot.hasData;
          return _KpiCard(
            title: 'Kitchen Orders',
            value: isLoading ? '...' : count.toString(),
            icon: Icons.microwave_outlined,
            iconColor: Colors.deepOrange,
            badge: isLoading ? null : 'Preparing',
            badgeColor: count > 0 ? Colors.deepOrange : Colors.grey,
            onTap: () => onTabChange(2),
            dashColors: dashColors,
          );
        },
      ),
      // 6. Active Dine-in
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _getTodayOrdersStream(context),
        builder: (context, snapshot) {
          int count = 0;
          if (snapshot.hasData) {
            count = snapshot.data!.docs.where((doc) {
              final data = doc.data();
              final status = data['status'] as String? ?? '';
              final type = data['Order_type'] as String? ?? '';
              final isActive = [
                AppConstants.statusPending,
                AppConstants.statusPreparing,
                AppConstants.statusPrepared,
                AppConstants.statusServed,
              ].contains(status);
              return type.toLowerCase() == 'dine_in' && isActive;
            }).length;
          }
          final isLoading = !snapshot.hasData;
          return _KpiCard(
            title: 'Active Dine-in',
            value: isLoading ? '...' : count.toString(),
            icon: Icons.table_restaurant_outlined,
            iconColor: Colors.teal,
            badge: isLoading ? null : 'Occupied',
            badgeColor: count > 0 ? Colors.teal : Colors.grey,
            onTap: () => onTabChange(2),
            dashColors: dashColors,
          );
        },
      ),
      // 7. Takeaway Orders Today
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _getTodayOrdersStream(context),
        builder: (context, snapshot) {
          int count = 0;
          if (snapshot.hasData) {
            count = snapshot.data!.docs.where((doc) {
              final type = doc.data()['Order_type'] as String? ?? '';
              return type.toLowerCase() == 'takeaway';
            }).length;
          }
          final isLoading = !snapshot.hasData;
          return _KpiCard(
            title: 'Takeaway Orders',
            value: isLoading ? '...' : count.toString(),
            icon: Icons.shopping_basket_outlined,
            iconColor: Colors.indigo,
            badge: isLoading ? null : 'Today',
            badgeColor: Colors.indigo,
            onTap: () => onTabChange(2),
            dashColors: dashColors,
          );
        },
      ),
      // 8. Low Stock Items
      StreamBuilder<List<IngredientModel>>(
        stream: _getIngredientsStream(context),
        builder: (context, snapshot) {
          int count = 0;
          if (snapshot.hasData) {
            final userScope = context.read<UserScopeService>();
            final branchFilter = context.read<BranchFilterService>();
            final effectiveBranchIds = branchFilter.getFilterBranchIds(userScope.branchIds);
            final branchId = effectiveBranchIds.isNotEmpty ? effectiveBranchIds.first : "default";
            count = snapshot.data!.where((ing) => ing.isLowStock(branchId) || ing.isOutOfStock(branchId)).length;
          }
          final isLoading = !snapshot.hasData;
          return _KpiCard(
            title: 'Low Stock Alerts',
            value: isLoading ? '...' : count.toString(),
            icon: Icons.warning_amber_rounded,
            iconColor: Colors.redAccent,
            badge: isLoading ? null : 'Needs Refill',
            badgeColor: count > 0 ? Colors.redAccent : Colors.grey,
            onTap: () => onTabChange(7), // Assuming tab 7 or similar is Inventory, or just keep it 0 if not mapped. Let's send them to dashboard but ideally inventory.
            dashColors: dashColors,
          );
        },
      ),
    ];
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CHART SECTION
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildChartSection(BuildContext context, _DashColors dashColors) {
    return Container(
      decoration: BoxDecoration(
        color: dashColors.surfaceDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: dashColors.borderSubtle),
      ),
      padding: const EdgeInsets.all(24),
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _getTodayOrdersStream(context),
        builder: (context, snapshot) {
          // Compute hourly data
          List<_HourlyOrderData> hourlyData = [];
          double totalRevenue = 0;
          int totalOrders = 0;

          if (snapshot.hasData) {
            final docs = snapshot.data!.docs;
            totalOrders = docs.length;
            totalRevenue = OrderService.calculateRevenue(docs);

            // Group by hour
            Map<int, double> hourlyRevenue = {};
            Map<int, int> hourlyCount = {};
            for (final doc in docs) {
              final data = doc.data();
              final timestamp = data['timestamp'] as Timestamp?;
              if (timestamp != null) {
                final hour = timestamp.toDate().hour;
                final amount =
                    (data['totalAmount'] as num?)?.toDouble() ?? 0.0;
                hourlyRevenue[hour] = (hourlyRevenue[hour] ?? 0) + amount;
                hourlyCount[hour] = (hourlyCount[hour] ?? 0) + 1;
              }
            }

            // Fill 24 hours
            for (int h = 0; h < 24; h++) {
              final label = '${h.toString().padLeft(2, '0')}:00';
              hourlyData.add(_HourlyOrderData(
                label,
                hourlyRevenue[h] ?? 0,
                hourlyCount[h] ?? 0,
              ));
            }
          } else {
            // Empty chart placeholder
            for (int h = 0; h < 24; h++) {
              hourlyData.add(_HourlyOrderData(
                '${h.toString().padLeft(2, '0')}:00',
                0,
                0,
              ));
            }
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Chart header
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Live Order Flow',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: dashColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Revenue flow over the current business day.',
                          style: TextStyle(
                            fontSize: 13,
                            color: dashColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        snapshot.hasData
                            ? 'QAR ${totalRevenue.toStringAsFixed(2)}'
                            : '...',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: dashColors.textPrimary,
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            totalOrders > 0
                                ? Icons.trending_up_rounded
                                : Icons.trending_flat_rounded,
                            size: 16,
                            color: totalOrders > 0
                                ? dashColors.primaryLight
                                : dashColors.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$totalOrders orders today',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: totalOrders > 0
                                  ? dashColors.primaryLight
                                  : dashColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Syncfusion Area Chart
              SizedBox(
                height: 220,
                child: SfCartesianChart(
                  plotAreaBorderWidth: 0,
                  margin: EdgeInsets.zero,
                  primaryXAxis: CategoryAxis(
                    labelStyle: TextStyle(
                      color: dashColors.textSecondary.withOpacity(0.6),
                      fontSize: 11,
                    ),
                    majorGridLines: const MajorGridLines(width: 0),
                    axisLine: const AxisLine(width: 0),
                    majorTickLines: const MajorTickLines(size: 0),
                    interval: 4, // Show every 4th label
                  ),
                  primaryYAxis: NumericAxis(
                    labelStyle: TextStyle(
                      color: dashColors.textSecondary.withOpacity(0.5),
                      fontSize: 10,
                    ),
                    majorGridLines: MajorGridLines(
                      width: 0.5,
                      color: Colors.white.withOpacity(0.05),
                      dashArray: const <double>[4, 4],
                    ),
                    axisLine: const AxisLine(width: 0),
                    majorTickLines: const MajorTickLines(size: 0),
                    numberFormat: NumberFormat.compactCurrency(
                      symbol: '',
                      decimalDigits: 0,
                    ),
                  ),
                  tooltipBehavior: TooltipBehavior(
                    enable: true,
                    color: dashColors.surfaceDark,
                    textStyle: TextStyle(
                        color: dashColors.textPrimary, fontSize: 12),
                    format: 'point.x\nQAR point.y',
                  ),
                  series: <CartesianSeries>[
                    SplineAreaSeries<_HourlyOrderData, String>(
                      dataSource: hourlyData,
                      xValueMapper: (data, _) => data.hour,
                      yValueMapper: (data, _) => data.revenue,
                      splineType: SplineType.monotonic,
                      color: dashColors.primary.withOpacity(0.6),
                      borderColor: dashColors.primaryLight,
                      borderWidth: 2.5,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          dashColors.primary.withOpacity(0.25),
                          dashColors.primary.withOpacity(0.0),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RECENT ORDERS TABLE
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildRecentOrdersTable(BuildContext context, _DashColors dashColors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 16),
          child: Text(
            'Recent Orders',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: dashColors.textPrimary,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: dashColors.surfaceDark,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: dashColors.borderSubtle),
          ),
          clipBehavior: Clip.antiAlias,
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _getTodayOrdersStream(context),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return Padding(
                  padding: const EdgeInsets.all(48),
                  child: Center(
                    child: CircularProgressIndicator(
                      valueColor:
                          AlwaysStoppedAnimation(dashColors.primaryLight),
                    ),
                  ),
                );
              }

              final orders = snapshot.data!.docs.take(8).toList();
              if (orders.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(48),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.receipt_long_outlined,
                            size: 48,
                            color: dashColors.textSecondary.withOpacity(0.4)),
                        const SizedBox(height: 12),
                        Text(
                          'No orders yet today',
                          style: TextStyle(
                            color: dashColors.textSecondary,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return Column(
                children: [
                  // Table header
                  Container(
                    color: Colors.white.withOpacity(0.03),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 14),
                    child: Row(
                      children: [
                        _tableHeader('ORDER', flex: 3, dashColors: dashColors),
                        _tableHeader('TYPE', flex: 2, dashColors: dashColors),
                        _tableHeader('STATUS', flex: 2, dashColors: dashColors),
                        _tableHeader('AMOUNT', flex: 2, align: TextAlign.right, dashColors: dashColors),
                        _tableHeader('ACTION', flex: 1, align: TextAlign.center, dashColors: dashColors),
                      ],
                    ),
                  ),
                  // Table rows
                  ...orders.map((doc) => _buildOrderRow(doc, dashColors)),
                  // Footer
                  Container(
                    color: Colors.white.withOpacity(0.03),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Showing ${orders.length} of ${snapshot.data!.docs.length} orders',
                          style: TextStyle(
                            fontSize: 13,
                            color: dashColors.textSecondary,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => onTabChange(2),
                          icon: const Icon(Icons.arrow_forward_rounded,
                              size: 16),
                          label: const Text('View All'),
                          style: TextButton.styleFrom(
                            foregroundColor: dashColors.primaryLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _tableHeader(String label,
      {int flex = 1, TextAlign align = TextAlign.left, required _DashColors dashColors}) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        textAlign: align,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: dashColors.textSecondary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildOrderRow(QueryDocumentSnapshot<Map<String, dynamic>> doc, _DashColors dashColors) {
    final data = doc.data();
    final orderId = doc.id;
    final displayNumber =
        OrderNumberHelper.getDisplayNumber(data, orderId: orderId);
    final customer = data['customerName'] as String? ?? 'Guest';
    final status = data['status'] as String? ?? 'pending';
    final orderType = data['Order_type'] as String? ?? 'delivery';
    final amount = (data['totalAmount'] as num?)?.toDouble() ?? 0;

    final statusColor = _getStatusColor(status);
    final typeIcon = _getOrderTypeIcon(orderType);

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: dashColors.borderSubtle, width: 1),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onTabChange(2),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            child: Row(
              children: [
                // Order info
                Expanded(
                  flex: 3,
                  child: Row(
                    children: [
                      Container(
                        height: 36,
                        width: 36,
                        decoration: BoxDecoration(
                          color: dashColors.primary.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.receipt_long_rounded,
                          size: 18,
                          color: dashColors.primaryLight,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayNumber,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: dashColors.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              customer,
                              style: TextStyle(
                                fontSize: 12,
                                color: dashColors.textSecondary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Type
                Expanded(
                  flex: 2,
                  child: Row(
                    children: [
                      Icon(typeIcon, size: 16, color: dashColors.textSecondary),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          _formatOrderType(orderType),
                          style: TextStyle(
                            fontSize: 13,
                            color: dashColors.textSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                // Status
                Expanded(
                  flex: 2,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: statusColor.withOpacity(0.25),
                        ),
                      ),
                      child: Text(
                        AppConstants.getStatusDisplayText(status),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ),
                ),
                // Amount
                Expanded(
                  flex: 2,
                  child: Text(
                    'QAR ${amount.toStringAsFixed(2)}',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: dashColors.textPrimary,
                    ),
                  ),
                ),
                // Action
                Expanded(
                  flex: 1,
                  child: Center(
                    child: IconButton(
                      onPressed: () => onTabChange(2),
                      icon: Icon(
                        Icons.more_horiz_rounded,
                        color: dashColors.textSecondary,
                        size: 20,
                      ),
                      splashRadius: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }



  // ─── Helpers ─────────────────────────────────────────────────────────────
  String _formatOrderType(String type) {
    switch (AppConstants.normalizeOrderType(type)) {
      case AppConstants.orderTypeDelivery:
        return 'Delivery';
      case AppConstants.orderTypeTakeaway:
        return 'Takeaway';
      case AppConstants.orderTypePickup:
        return 'Pick Up';
      case AppConstants.orderTypeDineIn:
        return 'Dine-in';
      default:
        return type.capitalize();
    }
  }

  IconData _getOrderTypeIcon(String type) {
    switch (AppConstants.normalizeOrderType(type)) {
      case AppConstants.orderTypeDelivery:
        return Icons.delivery_dining;
      case AppConstants.orderTypeTakeaway:
        return Icons.takeout_dining;
      case AppConstants.orderTypePickup:
        return Icons.store;
      case AppConstants.orderTypeDineIn:
        return Icons.restaurant;
      default:
        return Icons.receipt;
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'delivered':
      case 'completed':
      case 'paid':
      case 'collected':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'preparing':
        return Colors.blue;
      case 'prepared':
      case 'served':
        return Colors.teal;
      case 'cancelled':
      case 'refunded':
        return Colors.red;
      case 'needs_rider_assignment':
      case 'rider_assigned':
        return Colors.amber;
      case 'pickedup':
        return Colors.cyan;
      default:
        return Colors.grey;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// KPI CARD WIDGET
// ═══════════════════════════════════════════════════════════════════════════════
class _KpiCard extends StatefulWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color iconColor;
  final String? badge;
  final Color badgeColor;
  final VoidCallback onTap;
  final _DashColors dashColors;

  const _KpiCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.iconColor,
    this.badge,
    required this.badgeColor,
    required this.onTap,
    required this.dashColors,
  });

  @override
  State<_KpiCard> createState() => _KpiCardState();
}

class _KpiCardState extends State<_KpiCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: widget.dashColors.surfaceDark,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _isHovered
                  ? widget.iconColor.withOpacity(0.3)
                  : widget.dashColors.borderSubtle,
            ),
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: widget.iconColor.withOpacity(0.08),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : [],
          ),
          child: Stack(
            children: [
              // Background icon
              Positioned(
                top: -4,
                right: -4,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: _isHovered ? 0.2 : 0.08,
                  child: Icon(
                    widget.icon,
                    size: 48,
                    color: widget.iconColor,
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: widget.dashColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            widget.value,
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              color: widget.dashColors.textPrimary,
                            ),
                          ),
                        ),
                      ),
                      if (widget.badge != null) ...[
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: widget.badgeColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            widget.badge!,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: widget.badgeColor,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

