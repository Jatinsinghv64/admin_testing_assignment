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
import '../services/inventory/InventoryService.dart';
import '../services/ingredients/IngredientService.dart';
import '../services/ingredients/RecipeService.dart';
import '../services/inventory/PurchaseOrderService.dart';
import '../services/inventory/WasteService.dart';
import '../Widgets/BranchFilterService.dart';
import '../main.dart';
import '../constants.dart';

class AnalyticsScreen extends StatefulWidget {
  static bool autoShowExportDialog = false;

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
  Future<_InventoryAnalyticsData>? _inventoryAnalyticsFuture;
  Future<_FoodCostAnalyticsData>? _foodCostAnalyticsFuture;
  Future<_WasteAnalyticsData>? _wasteAnalyticsFuture;
  Future<_PurchasesAnalyticsData>? _purchasesAnalyticsFuture;
  String _inventoryAnalyticsKey = '';
  String _foodCostAnalyticsKey = '';
  String _wasteAnalyticsKey = '';
  String _purchasesAnalyticsKey = '';
  String? _selectedFoodIngredientId;
  String? _selectedPurchaseIngredientId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);

    // Load branch names if needed (for multi-branch users)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userScope = context.read<UserScopeService>();
      final branchFilter = context.read<BranchFilterService>();
      if (userScope.branchIds.length > 1 && !branchFilter.isLoaded) {
        branchFilter.loadBranchNames(userScope.branchIds);
      }

      if (AnalyticsScreen.autoShowExportDialog) {
        AnalyticsScreen.autoShowExportDialog = false;
        _showExportDialog(context);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // Removed _handleTabSelection as tabs now control main sections
  // (Sales, Inventory, Food Cost, Waste, Purchases)

  @override
  Widget build(BuildContext context) {
    final userScope = context.watch<UserScopeService>();
    final branchFilter = context.watch<BranchFilterService>();
    final bool showBranchSelector = userScope.branchIds.length > 1;

    // Get effective branch IDs for filtering
    final effectiveBranchIds =
        branchFilter.getFilterBranchIds(userScope.branchIds);

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
          child: _buildMainAnalyticsTabs(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // 1. Sales Tab
          _buildSalesTab(effectiveBranchIds, userScope, branchFilter),
          // 2. Inventory Tab
          _buildInventoryTab(effectiveBranchIds, userScope, branchFilter),
          // 3. Food Cost Tab
          _buildFoodCostTab(effectiveBranchIds, userScope, branchFilter),
          // 4. Waste Tab
          _buildWasteTab(effectiveBranchIds, userScope, branchFilter),
          // 5. Purchases Tab
          _buildPurchasesTab(effectiveBranchIds, userScope, branchFilter),
          // 6. Registers Tab
          _buildRegistersTab(effectiveBranchIds, userScope, branchFilter),
        ],
      ),
    );
  }

  Widget _buildSalesTab(List<String> effectiveBranchIds,
      UserScopeService userScope, BranchFilterService branchFilter) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDateRangeSelector(),
          const SizedBox(height: 16),
          _buildSalesOrderTypeFilter(),
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
          _buildAnalyticsOverviewCards(effectiveBranchIds),
          const SizedBox(height: 32),
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
          buildSectionHeader('Top Delivery Riders', Icons.delivery_dining),
          const SizedBox(height: 16),
          _buildTopRidersList(effectiveBranchIds),
          const SizedBox(height: 32),
          buildSectionHeader('Top Customers', Icons.people_outline),
          const SizedBox(height: 16),
          _buildTopCustomersList(effectiveBranchIds),
        ],
      ),
    );
  }

  Widget _buildInventoryTab(List<String> effectiveBranchIds,
      UserScopeService userScope, BranchFilterService branchFilter) {
    final future = _getInventoryAnalyticsFuture(effectiveBranchIds);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDateRangeSelector(),
          const SizedBox(height: 24),
          buildSectionHeader('Inventory Analytics', Icons.inventory_2),
          const SizedBox(height: 16),
          FutureBuilder<_InventoryAnalyticsData>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: Colors.deepPurple),
                );
              }
              if (!snapshot.hasData || snapshot.data!.ingredientCount == 0) {
                return _buildEmptyState(
                  icon: Icons.inventory_2_outlined,
                  message:
                      'No inventory data found for selected period/branch.',
                );
              }
              final data = snapshot.data!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricCard(
                          'Total Value',
                          'QAR ${data.totalValue.toStringAsFixed(2)}',
                          Icons.account_balance_wallet,
                          Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildMetricCard(
                          'Inventory Turnover',
                          data.turnoverRate != null
                              ? data.turnoverRate!.toStringAsFixed(2)
                              : 'N/A',
                          Icons.sync_alt,
                          Colors.deepPurple,
                        ),
                      ),
                    ],
                  ),
                  if (data.turnoverNote.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      data.turnoverNote,
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricCard(
                          'Dead Stock Items',
                          '${data.deadStockRows.length}',
                          Icons.remove_circle_outline,
                          Colors.red,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildMetricCard(
                          'Stock Accuracy',
                          data.stockAccuracyPct != null
                              ? '${data.stockAccuracyPct!.toStringAsFixed(1)}%'
                              : 'N/A',
                          Icons.fact_check_outlined,
                          Colors.teal,
                        ),
                      ),
                    ],
                  ),
                  if (data.stockAccuracyNote.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      data.stockAccuracyNote,
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 24),
                  buildSectionHeader(
                    'Carrying Cost Over Time',
                    Icons.show_chart_rounded,
                  ),
                  const SizedBox(height: 12),
                  _buildChartCard(
                    height: 300,
                    child: SfCartesianChart(
                      primaryXAxis: CategoryAxis(
                        majorGridLines: const MajorGridLines(width: 0),
                        axisLine: const AxisLine(width: 0),
                      ),
                      primaryYAxis: NumericAxis(
                        axisLine: const AxisLine(width: 0),
                        numberFormat:
                            NumberFormat.compactCurrency(symbol: 'QAR '),
                        majorGridLines: const MajorGridLines(
                          width: 0.5,
                          color: Colors.grey,
                        ),
                      ),
                      tooltipBehavior: TooltipBehavior(enable: true),
                      series: <CartesianSeries<_TimeValuePoint, String>>[
                        LineSeries<_TimeValuePoint, String>(
                          dataSource: data.carryingCostSeries,
                          xValueMapper: (p, _) => p.label,
                          yValueMapper: (p, _) => p.value,
                          color: Colors.deepPurple,
                          markerSettings: const MarkerSettings(isVisible: true),
                          width: 3,
                        ),
                      ],
                    ),
                  ),
                  if (data.carryingCostNote.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      data.carryingCostNote,
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 24),
                  buildSectionHeader(
                      'Dead Stock Identification', Icons.inventory),
                  const SizedBox(height: 12),
                  if (data.deadStockRows.isEmpty)
                    _buildEmptyState(
                      icon: Icons.check_circle_outline,
                      message: 'No dead stock found in selected period.',
                    )
                  else
                    _buildChartCard(
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: data.deadStockRows.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, color: Color(0xFFEFEFEF)),
                        itemBuilder: (context, index) {
                          final row = data.deadStockRows[index];
                          return ListTile(
                            dense: true,
                            title: Text(
                              row.name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              'Stock: ${row.currentStock.toStringAsFixed(2)} | Value: QAR ${row.currentValue.toStringAsFixed(2)}',
                            ),
                            trailing: Text(
                              row.daysSinceLastUsed != null
                                  ? '${row.daysSinceLastUsed}d'
                                  : 'Never used',
                              style: TextStyle(color: Colors.grey[700]),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFoodCostTab(List<String> effectiveBranchIds,
      UserScopeService userScope, BranchFilterService branchFilter) {
    final future = _getFoodCostAnalyticsFuture(effectiveBranchIds);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDateRangeSelector(),
          const SizedBox(height: 24),
          buildSectionHeader('Food Cost Analytics', Icons.attach_money),
          const SizedBox(height: 16),
          FutureBuilder<_FoodCostAnalyticsData>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: Colors.deepPurple),
                );
              }
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return _buildEmptyState(
                  icon: Icons.attach_money,
                  message:
                      'No food cost data found for selected period/branch.',
                );
              }
              final data = snapshot.data!;
              if (_selectedFoodIngredientId == null &&
                  data.ingredients.isNotEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && _selectedFoodIngredientId == null) {
                    setState(() =>
                        _selectedFoodIngredientId = data.ingredients.first.id);
                  }
                });
              }

              final selectedIngredientId = _selectedFoodIngredientId;
              final ingredientPricePoints = selectedIngredientId == null
                  ? <_TimeValuePoint>[]
                  : (data.ingredientPriceHistory[selectedIngredientId] ?? []);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricCard(
                          'Avg Food Cost %',
                          '${data.averageFoodCostPercent.toStringAsFixed(1)}%',
                          Icons.percent_rounded,
                          Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildMetricCard(
                          'Avg Cost Per Serving',
                          'QAR ${data.averageCostPerServing.toStringAsFixed(2)}',
                          Icons.trending_down,
                          Colors.green,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  buildSectionHeader('Food Cost % Trend', Icons.show_chart),
                  const SizedBox(height: 12),
                  _buildChartCard(
                    height: 300,
                    child: SfCartesianChart(
                      primaryXAxis: CategoryAxis(
                        majorGridLines: const MajorGridLines(width: 0),
                        axisLine: const AxisLine(width: 0),
                      ),
                      primaryYAxis: NumericAxis(
                        axisLine: const AxisLine(width: 0),
                        labelFormat: '{value}%',
                        majorGridLines: const MajorGridLines(
                            width: 0.5, color: Colors.grey),
                        plotBands: <PlotBand>[
                          PlotBand(
                            start: 30,
                            end: 30,
                            borderColor: Colors.orange,
                            borderWidth: 2,
                            dashArray: const <double>[6, 6],
                            text: '30% Benchmark',
                            textStyle: TextStyle(
                              color: Colors.orange.shade700,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      tooltipBehavior: TooltipBehavior(enable: true),
                      series: <CartesianSeries<_TimeValuePoint, String>>[
                        LineSeries<_TimeValuePoint, String>(
                          dataSource: data.foodCostTrend,
                          xValueMapper: (p, _) => p.label,
                          yValueMapper: (p, _) => p.value,
                          color: Colors.deepPurple,
                          width: 3,
                          markerSettings: const MarkerSettings(isVisible: true),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  buildSectionHeader(
                    'Top 10 Most Expensive Ingredients',
                    Icons.bar_chart_rounded,
                  ),
                  const SizedBox(height: 12),
                  _buildChartCard(
                    height: 320,
                    child: SfCartesianChart(
                      primaryXAxis: CategoryAxis(
                        majorGridLines: const MajorGridLines(width: 0),
                        axisLine: const AxisLine(width: 0),
                        labelRotation: -45,
                      ),
                      primaryYAxis: NumericAxis(
                        axisLine: const AxisLine(width: 0),
                        majorGridLines: const MajorGridLines(
                            width: 0.5, color: Colors.grey),
                        numberFormat:
                            NumberFormat.compactCurrency(symbol: 'QAR '),
                      ),
                      tooltipBehavior: TooltipBehavior(enable: true),
                      series: <CartesianSeries<_NamedValue, String>>[
                        BarSeries<_NamedValue, String>(
                          dataSource: data.topIngredientSpend,
                          xValueMapper: (p, _) => p.name,
                          yValueMapper: (p, _) => p.value,
                          color: Colors.deepPurple.shade400,
                          dataLabelSettings: const DataLabelSettings(
                            isVisible: true,
                            textStyle: TextStyle(fontSize: 10),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildChartCard(
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: data.topIngredientSpend.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, color: Color(0xFFEFEFEF)),
                      itemBuilder: (context, index) {
                        final item = data.topIngredientSpend[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.deepPurple.withOpacity(0.1),
                            child: Text('${index + 1}'),
                          ),
                          title: Text(
                            item.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          trailing: Text(
                            'QAR ${item.value.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                  buildSectionHeader('Cost Per Serving Trend', Icons.timeline),
                  const SizedBox(height: 12),
                  _buildChartCard(
                    height: 300,
                    child: data.costPerServingTrend.isEmpty
                        ? _buildEmptyState(
                            icon: Icons.timeline,
                            message: 'No cost-per-serving data for this range.',
                          )
                        : SfCartesianChart(
                            primaryXAxis: CategoryAxis(
                              majorGridLines: const MajorGridLines(width: 0),
                              axisLine: const AxisLine(width: 0),
                            ),
                            primaryYAxis: NumericAxis(
                              axisLine: const AxisLine(width: 0),
                              numberFormat:
                                  NumberFormat.compactCurrency(symbol: 'QAR '),
                              majorGridLines: const MajorGridLines(
                                width: 0.5,
                                color: Colors.grey,
                              ),
                            ),
                            tooltipBehavior: TooltipBehavior(enable: true),
                            series: <CartesianSeries<_TimeValuePoint, String>>[
                              LineSeries<_TimeValuePoint, String>(
                                dataSource: data.costPerServingTrend,
                                xValueMapper: (p, _) => p.label,
                                yValueMapper: (p, _) => p.value,
                                color: Colors.green.shade600,
                                width: 3,
                                markerSettings:
                                    const MarkerSettings(isVisible: true),
                              ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 24),
                  buildSectionHeader(
                    'Ingredient Price Tracking',
                    Icons.price_change_outlined,
                  ),
                  const SizedBox(height: 12),
                  _buildChartCard(
                    child: Column(
                      children: [
                        DropdownButtonFormField<String>(
                          value: selectedIngredientId,
                          decoration: const InputDecoration(
                            labelText: 'Select Ingredient',
                            border: OutlineInputBorder(),
                          ),
                          items: data.ingredients
                              .map(
                                (i) => DropdownMenuItem<String>(
                                  value: i.id,
                                  child: Text(i.name),
                                ),
                              )
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _selectedFoodIngredientId = v),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 280,
                          child: ingredientPricePoints.isEmpty
                              ? _buildEmptyState(
                                  icon: Icons.price_change_outlined,
                                  message:
                                      'No receiving price data for selected ingredient.',
                                )
                              : SfCartesianChart(
                                  primaryXAxis: CategoryAxis(
                                    majorGridLines:
                                        const MajorGridLines(width: 0),
                                    axisLine: const AxisLine(width: 0),
                                  ),
                                  primaryYAxis: NumericAxis(
                                    axisLine: const AxisLine(width: 0),
                                    numberFormat: NumberFormat.currency(
                                      symbol: 'QAR ',
                                      decimalDigits: 2,
                                    ),
                                  ),
                                  tooltipBehavior:
                                      TooltipBehavior(enable: true),
                                  series: <CartesianSeries<_TimeValuePoint,
                                      String>>[
                                    LineSeries<_TimeValuePoint, String>(
                                      dataSource: ingredientPricePoints,
                                      xValueMapper: (p, _) => p.label,
                                      yValueMapper: (p, _) => p.value,
                                      color: Colors.deepPurple,
                                      markerSettings:
                                          const MarkerSettings(isVisible: true),
                                      width: 3,
                                    ),
                                  ],
                                ),
                        ),
                        if (ingredientPricePoints.length == 1)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'More data points will appear with future purchases.',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildWasteTab(List<String> effectiveBranchIds,
      UserScopeService userScope, BranchFilterService branchFilter) {
    final future = _getWasteAnalyticsFuture(effectiveBranchIds);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDateRangeSelector(),
          const SizedBox(height: 24),
          buildSectionHeader('Waste Analytics', Icons.delete_outline),
          const SizedBox(height: 16),
          FutureBuilder<_WasteAnalyticsData>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: Colors.deepPurple),
                );
              }
              if (!snapshot.hasData || snapshot.data!.wasteCount == 0) {
                return _buildEmptyState(
                  icon: Icons.delete_outline,
                  message: 'No waste recorded for selected period/branch.',
                );
              }
              final data = snapshot.data!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricCard(
                          'Total Waste Cost',
                          'QAR ${data.totalWasteCost.toStringAsFixed(2)}',
                          Icons.trending_down,
                          Colors.red,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildMetricCard(
                          'Waste as % Food Cost',
                          '${data.wastePct.toStringAsFixed(1)}%',
                          data.wastePctDelta > 0
                              ? Icons.trending_up
                              : Icons.trending_down,
                          data.wastePctColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'vs previous period: ${data.wastePctDelta >= 0 ? '+' : ''}${data.wastePctDelta.toStringAsFixed(1)}%',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                  const SizedBox(height: 24),
                  buildSectionHeader('Total Waste Cost Trend', Icons.bar_chart),
                  const SizedBox(height: 12),
                  _buildChartCard(
                    height: 300,
                    child: SfCartesianChart(
                      primaryXAxis: CategoryAxis(
                        majorGridLines: const MajorGridLines(width: 0),
                        axisLine: const AxisLine(width: 0),
                      ),
                      primaryYAxis: NumericAxis(
                        axisLine: const AxisLine(width: 0),
                        numberFormat:
                            NumberFormat.compactCurrency(symbol: 'QAR '),
                        majorGridLines: const MajorGridLines(
                            width: 0.5, color: Colors.grey),
                      ),
                      tooltipBehavior: TooltipBehavior(enable: true),
                      series: <CartesianSeries<_TimeValuePoint, String>>[
                        ColumnSeries<_TimeValuePoint, String>(
                          dataSource: data.groupedWasteSeries,
                          xValueMapper: (p, _) => p.label,
                          yValueMapper: (p, _) => p.value,
                          color: Colors.red.shade400,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(8)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  buildSectionHeader(
                    'Waste by Reason Breakdown',
                    Icons.donut_large_outlined,
                  ),
                  const SizedBox(height: 12),
                  _buildChartCard(
                    child: Column(
                      children: [
                        SizedBox(
                          height: 320,
                          child: SfCircularChart(
                            legend: const Legend(
                              isVisible: false,
                            ),
                            tooltipBehavior: TooltipBehavior(enable: true),
                            series: <CircularSeries<_NamedValue, String>>[
                              DoughnutSeries<_NamedValue, String>(
                                dataSource: data.reasonBreakdown,
                                xValueMapper: (p, _) => p.name,
                                yValueMapper: (p, _) => p.value,
                                pointColorMapper: (p, idx) =>
                                    _reasonColor(p.name),
                                dataLabelSettings:
                                    const DataLabelSettings(isVisible: true),
                                innerRadius: '60%',
                              ),
                            ],
                          ),
                        ),
                        ...data.reasonBreakdown.map((reason) {
                          final pct = data.totalWasteCost > 0
                              ? (reason.value / data.totalWasteCost) * 100
                              : 0.0;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: _reasonColor(reason.name),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(child: Text(reason.name)),
                                Text(
                                  'QAR ${reason.value.toStringAsFixed(2)} (${pct.toStringAsFixed(1)}%)',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  buildSectionHeader('Waste Trend Analysis', Icons.timeline),
                  const SizedBox(height: 12),
                  _buildChartCard(
                    height: 320,
                    child: SfCartesianChart(
                      primaryXAxis: CategoryAxis(
                        majorGridLines: const MajorGridLines(width: 0),
                        axisLine: const AxisLine(width: 0),
                      ),
                      primaryYAxis: NumericAxis(
                        axisLine: const AxisLine(width: 0),
                        numberFormat:
                            NumberFormat.compactCurrency(symbol: 'QAR '),
                      ),
                      legend: const Legend(
                        isVisible: true,
                        position: LegendPosition.bottom,
                      ),
                      tooltipBehavior: TooltipBehavior(enable: true),
                      series: <CartesianSeries<_TimeValuePoint, String>>[
                        LineSeries<_TimeValuePoint, String>(
                          name: 'Daily Waste',
                          dataSource: data.dailyWasteSeries,
                          xValueMapper: (p, _) => p.label,
                          yValueMapper: (p, _) => p.value,
                          color: Colors.deepOrange.shade200,
                          width: 2,
                          markerSettings: const MarkerSettings(isVisible: true),
                        ),
                        LineSeries<_TimeValuePoint, String>(
                          name: '7-day Moving Avg',
                          dataSource: data.movingAverageSeries,
                          xValueMapper: (p, _) => p.label,
                          yValueMapper: (p, _) => p.value,
                          color: Colors.deepOrange.shade700,
                          width: 3,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPurchasesTab(List<String> effectiveBranchIds,
      UserScopeService userScope, BranchFilterService branchFilter) {
    final future = _getPurchasesAnalyticsFuture(effectiveBranchIds);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDateRangeSelector(),
          const SizedBox(height: 24),
          buildSectionHeader(
              'Purchase Analytics', Icons.shopping_cart_outlined),
          const SizedBox(height: 16),
          FutureBuilder<_PurchasesAnalyticsData>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: Colors.deepPurple),
                );
              }
              if (!snapshot.hasData || snapshot.data!.poCount == 0) {
                return _buildEmptyState(
                  icon: Icons.shopping_cart_outlined,
                  message:
                      'No purchase orders found for selected period/branch.',
                );
              }
              final data = snapshot.data!;
              if (_selectedPurchaseIngredientId == null &&
                  data.ingredients.isNotEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && _selectedPurchaseIngredientId == null) {
                    setState(
                      () => _selectedPurchaseIngredientId =
                          data.ingredients.first.id,
                    );
                  }
                });
              }

              final selectedIngredientId = _selectedPurchaseIngredientId;
              final ingredientSupplierCosts = selectedIngredientId == null
                  ? <_SupplierCostPoint>[]
                  : (data.ingredientPriceBySupplier[selectedIngredientId] ??
                      []);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricCard(
                          'Total Purchases',
                          'QAR ${data.totalPurchases.toStringAsFixed(2)}',
                          Icons.account_balance_wallet,
                          Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildMetricCard(
                          'PO Count',
                          '${data.poCount}',
                          Icons.receipt,
                          Colors.purple,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricCard(
                          'Pending POs',
                          '${data.pendingCount}',
                          Icons.pending_actions,
                          Colors.orange,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildMetricCard(
                          'Received/Partial',
                          '${data.receivedOrPartialCount}',
                          Icons.check_circle_outline,
                          Colors.teal,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  buildSectionHeader(
                    'Total Spend by Supplier',
                    Icons.bar_chart_rounded,
                  ),
                  const SizedBox(height: 12),
                  _buildChartCard(
                    height: 320,
                    child: SfCartesianChart(
                      primaryXAxis: CategoryAxis(
                        majorGridLines: const MajorGridLines(width: 0),
                        axisLine: const AxisLine(width: 0),
                        labelRotation: -35,
                      ),
                      primaryYAxis: NumericAxis(
                        axisLine: const AxisLine(width: 0),
                        numberFormat:
                            NumberFormat.compactCurrency(symbol: 'QAR '),
                      ),
                      tooltipBehavior: TooltipBehavior(enable: true),
                      series: <CartesianSeries<_NamedValue, String>>[
                        BarSeries<_NamedValue, String>(
                          dataSource: data.supplierSpend,
                          xValueMapper: (p, _) => p.name,
                          yValueMapper: (p, _) => p.value,
                          color: Colors.deepPurple.shade400,
                          dataLabelSettings:
                              const DataLabelSettings(isVisible: true),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  buildSectionHeader(
                    'Average Delivery Time by Supplier',
                    Icons.local_shipping_outlined,
                  ),
                  const SizedBox(height: 12),
                  _buildChartCard(
                    height: 300,
                    child: data.supplierLeadTimes.isEmpty
                        ? _buildEmptyState(
                            icon: Icons.local_shipping_outlined,
                            message:
                                'No received purchase orders with delivery dates.',
                          )
                        : SfCartesianChart(
                            primaryXAxis: CategoryAxis(
                              majorGridLines: const MajorGridLines(width: 0),
                              axisLine: const AxisLine(width: 0),
                              labelRotation: -35,
                            ),
                            primaryYAxis: NumericAxis(
                              axisLine: const AxisLine(width: 0),
                              labelFormat: '{value}d',
                            ),
                            tooltipBehavior: TooltipBehavior(enable: true),
                            series: <CartesianSeries<_SupplierLeadTime,
                                String>>[
                              BarSeries<_SupplierLeadTime, String>(
                                dataSource: data.supplierLeadTimes,
                                xValueMapper: (p, _) => p.supplierName,
                                yValueMapper: (p, _) => p.avgDays,
                                color: Colors.teal.shade400,
                                dataLabelSettings:
                                    const DataLabelSettings(isVisible: true),
                              ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 24),
                  buildSectionHeader('Order Frequency', Icons.timeline),
                  const SizedBox(height: 12),
                  _buildChartCard(
                    height: 300,
                    child: SfCartesianChart(
                      primaryXAxis: CategoryAxis(
                        majorGridLines: const MajorGridLines(width: 0),
                        axisLine: const AxisLine(width: 0),
                      ),
                      primaryYAxis: NumericAxis(
                        axisLine: const AxisLine(width: 0),
                      ),
                      tooltipBehavior: TooltipBehavior(enable: true),
                      series: <CartesianSeries<_TimeValuePoint, String>>[
                        ColumnSeries<_TimeValuePoint, String>(
                          dataSource: data.orderFrequencySeries,
                          xValueMapper: (p, _) => p.label,
                          yValueMapper: (p, _) => p.value,
                          color: Colors.deepPurple.shade300,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  buildSectionHeader(
                    'Price Comparison Per Ingredient',
                    Icons.compare_arrows_outlined,
                  ),
                  const SizedBox(height: 12),
                  _buildChartCard(
                    child: Column(
                      children: [
                        DropdownButtonFormField<String>(
                          value: selectedIngredientId,
                          decoration: const InputDecoration(
                            labelText: 'Select Ingredient',
                            border: OutlineInputBorder(),
                          ),
                          items: data.ingredients
                              .map((i) => DropdownMenuItem<String>(
                                    value: i.id,
                                    child: Text(i.name),
                                  ))
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _selectedPurchaseIngredientId = v),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 280,
                          child: ingredientSupplierCosts.isEmpty
                              ? _buildEmptyState(
                                  icon: Icons.compare_arrows_outlined,
                                  message:
                                      'No supplier price data for selected ingredient.',
                                )
                              : SfCartesianChart(
                                  primaryXAxis: CategoryAxis(
                                    majorGridLines:
                                        const MajorGridLines(width: 0),
                                    axisLine: const AxisLine(width: 0),
                                  ),
                                  primaryYAxis: NumericAxis(
                                    axisLine: const AxisLine(width: 0),
                                    numberFormat: NumberFormat.currency(
                                      symbol: 'QAR ',
                                      decimalDigits: 2,
                                    ),
                                  ),
                                  tooltipBehavior:
                                      TooltipBehavior(enable: true),
                                  series: <CartesianSeries<_SupplierCostPoint,
                                      String>>[
                                    BarSeries<_SupplierCostPoint, String>(
                                      dataSource: ingredientSupplierCosts,
                                      xValueMapper: (p, _) => p.supplierName,
                                      yValueMapper: (p, _) => p.unitCost,
                                      pointColorMapper: (p, _) => p.isCheapest
                                          ? Colors.green
                                          : Colors.deepPurple,
                                      dataLabelSettings:
                                          const DataLabelSettings(
                                        isVisible: true,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                        if (ingredientSupplierCosts.length == 1)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'Only one supplier on record',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<_InventoryAnalyticsData> _getInventoryAnalyticsFuture(
    List<String> branchIds,
  ) {
    final key = _analyticsKey(branchIds);
    if (_inventoryAnalyticsFuture == null || _inventoryAnalyticsKey != key) {
      _inventoryAnalyticsKey = key;
      _inventoryAnalyticsFuture = _loadInventoryAnalytics(branchIds);
    }
    return _inventoryAnalyticsFuture!;
  }

  Future<_FoodCostAnalyticsData> _getFoodCostAnalyticsFuture(
    List<String> branchIds,
  ) {
    final key = _analyticsKey(branchIds);
    if (_foodCostAnalyticsFuture == null || _foodCostAnalyticsKey != key) {
      _foodCostAnalyticsKey = key;
      _foodCostAnalyticsFuture = _loadFoodCostAnalytics(branchIds);
    }
    return _foodCostAnalyticsFuture!;
  }

  Future<_WasteAnalyticsData> _getWasteAnalyticsFuture(
    List<String> branchIds,
  ) {
    final key = _analyticsKey(branchIds);
    if (_wasteAnalyticsFuture == null || _wasteAnalyticsKey != key) {
      _wasteAnalyticsKey = key;
      _wasteAnalyticsFuture = _loadWasteAnalytics(branchIds);
    }
    return _wasteAnalyticsFuture!;
  }

  Future<_PurchasesAnalyticsData> _getPurchasesAnalyticsFuture(
    List<String> branchIds,
  ) {
    final key = _analyticsKey(branchIds);
    if (_purchasesAnalyticsFuture == null || _purchasesAnalyticsKey != key) {
      _purchasesAnalyticsKey = key;
      _purchasesAnalyticsFuture = _loadPurchasesAnalytics(branchIds);
    }
    return _purchasesAnalyticsFuture!;
  }

  String _analyticsKey(List<String> branchIds) {
    final sorted = [...branchIds]..sort();
    return '${sorted.join(",")}|${_dateRange.start.millisecondsSinceEpoch}|${_dateRange.end.millisecondsSinceEpoch}';
  }

  Widget _buildChartCard({required Widget child, double? height}) {
    return Container(
      width: double.infinity,
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
        padding: const EdgeInsets.all(16),
        child: height != null ? SizedBox(height: height, child: child) : child,
      ),
    );
  }

  Color _reasonColor(String reason) {
    switch (reason.toLowerCase()) {
      case 'expired':
        return Colors.red.shade400;
      case 'spilled':
        return Colors.orange.shade400;
      case 'damaged':
        return Colors.deepOrange.shade400;
      case 'overproduction':
        return Colors.amber.shade600;
      case 'returned':
        return Colors.blue.shade400;
      case 'quality':
        return Colors.purple.shade400;
      case 'contamination':
        return Colors.brown.shade400;
      default:
        return Colors.grey.shade500;
    }
  }

  Future<List<Map<String, dynamic>>> _getOrdersForRange(
    List<String> branchIds, {
    required DateTime start,
    required DateTime end,
  }) async {
    if (branchIds.isEmpty) return [];
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('Orders')
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(end));

    if (branchIds.isNotEmpty) {
      if (branchIds.length == 1) {
        q = q.where('branchIds', arrayContains: branchIds.first);
      } else {
        q = q.where('branchIds', arrayContainsAny: branchIds.take(10).toList());
      }
    }
    final snap = await q.orderBy('timestamp', descending: true).get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  Future<_InventoryAnalyticsData> _loadInventoryAnalytics(
    List<String> branchIds,
  ) async {
    if (branchIds.isEmpty) return _InventoryAnalyticsData.empty();
    final inventoryService =
        Provider.of<InventoryService>(context, listen: false);

    final ingredients = await inventoryService.getIngredients(branchIds);
    final movements = await inventoryService.getStockMovements(
      branchIds,
      start: _dateRange.start,
      end: _dateRange.end,
    );
    final allDeductions = await inventoryService.getStockMovements(
      branchIds,
      movementType: 'order_deduction',
    );

    final ingredientById = {for (final i in ingredients) i.id: i};
    final totalValue = ingredients.fold<double>(
      0.0,
      (sum, i) =>
          sum +
          (i.getStock(branchIds.isNotEmpty ? branchIds.first : "default") *
              i.costPerUnit),
    );

    final usedCost = movements.where((m) {
      return (m['movementType'] ?? '').toString() == 'order_deduction';
    }).fold<double>(0.0, (sum, m) {
      final id = (m['ingredientId'] ?? '').toString();
      final qty = (m['quantity'] as num?)?.toDouble() ?? 0.0;
      final unitCost = ingredientById[id]?.costPerUnit ?? 0.0;
      return sum + qty.abs() * unitCost;
    });

    final turnoverRate =
        usedCost > 0 && totalValue > 0 ? usedCost / totalValue : null;
    final turnoverNote = turnoverRate == null
        ? 'N/A: no order-deduction movements in selected period.'
        : '';

    final stocktakes = movements.where((m) {
      return (m['movementType'] ?? '').toString() == 'stocktake';
    }).toList();
    double? stockAccuracyPct;
    String stockAccuracyNote = '';
    if (stocktakes.isEmpty) {
      stockAccuracyNote = 'No stocktakes recorded in selected period.';
    } else {
      final accurate = stocktakes.where((m) {
        final before = (m['balanceBefore'] as num?)?.toDouble() ?? 0.0;
        final after = (m['balanceAfter'] as num?)?.toDouble() ?? 0.0;
        return (before - after).abs() < 0.0001;
      }).length;
      stockAccuracyPct = (accurate / stocktakes.length) * 100;
    }

    final latestDeduction = <String, DateTime>{};
    for (final m in allDeductions) {
      final id = (m['ingredientId'] ?? '').toString();
      if (id.isEmpty) continue;
      final dt = (m['createdAt'] as Timestamp?)?.toDate();
      if (dt == null) continue;
      final existing = latestDeduction[id];
      if (existing == null || dt.isAfter(existing)) {
        latestDeduction[id] = dt;
      }
    }

    final usedInRange = movements
        .where((m) => (m['movementType'] ?? '').toString() == 'order_deduction')
        .map((m) => (m['ingredientId'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet();

    final deadStockRows = ingredients
        .where((i) =>
            i.getStock(branchIds.isNotEmpty ? branchIds.first : "default") >
                0 &&
            !usedInRange.contains(i.id))
        .map((i) {
      final lastUsed = latestDeduction[i.id];
      final days =
          lastUsed == null ? null : DateTime.now().difference(lastUsed).inDays;
      return _DeadStockRow(
        name: i.name,
        currentStock:
            i.getStock(branchIds.isNotEmpty ? branchIds.first : "default"),
        currentValue:
            i.getStock(branchIds.isNotEmpty ? branchIds.first : "default") *
                i.costPerUnit,
        daysSinceLastUsed: days,
      );
    }).toList()
      ..sort((a, b) => b.currentValue.compareTo(a.currentValue));

    final rangeDays = _dateRange.end.difference(_dateRange.start).inDays + 1;
    final carryingCostSeries = <_TimeValuePoint>[];
    final step = rangeDays <= 30 ? 1 : 7;
    DateTime cursor = DateTime(
        _dateRange.start.year, _dateRange.start.month, _dateRange.start.day);
    final endDate =
        DateTime(_dateRange.end.year, _dateRange.end.month, _dateRange.end.day);
    while (!cursor.isAfter(endDate)) {
      carryingCostSeries.add(
        _TimeValuePoint(
          date: cursor,
          label:
              DateFormat(rangeDays <= 30 ? 'dd MMM' : 'dd MMM').format(cursor),
          value: totalValue,
        ),
      );
      cursor = cursor.add(Duration(days: step));
    }

    return _InventoryAnalyticsData(
      ingredientCount: ingredients.length,
      totalValue: totalValue,
      turnoverRate: turnoverRate,
      turnoverNote: turnoverNote,
      stockAccuracyPct: stockAccuracyPct,
      stockAccuracyNote: stockAccuracyNote,
      deadStockRows: deadStockRows.take(20).toList(),
      carryingCostSeries: carryingCostSeries,
      carryingCostNote: 'Historical tracking starts from today.',
    );
  }

  Future<_FoodCostAnalyticsData> _loadFoodCostAnalytics(
    List<String> branchIds,
  ) async {
    if (branchIds.isEmpty) return _FoodCostAnalyticsData.empty();
    final ingredientService =
        Provider.of<IngredientService>(context, listen: false);
    final recipeService = Provider.of<RecipeService>(context, listen: false);
    final purchaseService =
        Provider.of<PurchaseOrderService>(context, listen: false);

    final ingredients =
        await ingredientService.streamIngredients(branchIds).first;
    final orders = await _getOrdersForRange(
      branchIds,
      start: _dateRange.start,
      end: _dateRange.end,
    );
    Query<Map<String, dynamic>> menuQuery =
        FirebaseFirestore.instance.collection('menu_items');
    if (branchIds.length == 1) {
      menuQuery = menuQuery.where('branchIds', arrayContains: branchIds.first);
    } else {
      menuQuery = menuQuery.where('branchIds',
          arrayContainsAny: branchIds.take(10).toList());
    }
    final menuItemsSnap = await menuQuery.get();
    final menuById = <String, Map<String, dynamic>>{
      for (final d in menuItemsSnap.docs) d.id: d.data(),
    };

    final recipeIds = menuById.values
        .map((m) => (m['recipeId'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    final recipes = await recipeService.getRecipesByIds(recipeIds);
    final recipeById = {for (final r in recipes) r.id: r};

    const completedStatuses = {'delivered', 'paid', 'collected', 'served'};
    final foodCostByDay = <DateTime, double>{};
    final revenueByDay = <DateTime, double>{};
    final qtyByDay = <DateTime, int>{};

    for (final order in orders) {
      final status = (order['status'] ?? '').toString().toLowerCase();
      if (!completedStatuses.contains(status)) continue;
      final ts = order['timestamp'] as Timestamp?;
      if (ts == null) continue;
      final d = ts.toDate();
      final day = DateTime(d.year, d.month, d.day);
      final items = List<Map<String, dynamic>>.from(order['items'] ?? const []);
      for (final item in items) {
        final menuItemId =
            (item['menuItemId'] ?? item['itemId'] ?? '').toString();
        final qty = (item['quantity'] as num?)?.toInt() ?? 1;
        final unitPrice = (item['discountedPrice'] as num?)?.toDouble() ??
            (item['price'] as num?)?.toDouble() ??
            0.0;
        final menu = menuById[menuItemId];
        final recipeId = (menu?['recipeId'] ?? '').toString();
        if (recipeId.isEmpty || !recipeById.containsKey(recipeId)) continue;
        final recipeCost = (recipeById[recipeId]!.totalCost) * qty;
        final revenue = unitPrice * qty;
        foodCostByDay[day] = (foodCostByDay[day] ?? 0.0) + recipeCost;
        revenueByDay[day] = (revenueByDay[day] ?? 0.0) + revenue;
        qtyByDay[day] = (qtyByDay[day] ?? 0) + qty;
      }
    }

    final allDays = _allDaysInRange(_dateRange.start, _dateRange.end);
    final foodCostTrend = <_TimeValuePoint>[];
    final costPerServingTrend = <_TimeValuePoint>[];
    double totalCost = 0.0;
    double totalRevenue = 0.0;
    int totalItems = 0;
    for (final day in allDays) {
      final c = foodCostByDay[day] ?? 0.0;
      final r = revenueByDay[day] ?? 0.0;
      final q = qtyByDay[day] ?? 0;
      totalCost += c;
      totalRevenue += r;
      totalItems += q;
      foodCostTrend.add(
        _TimeValuePoint(
          date: day,
          label: DateFormat('dd MMM').format(day),
          value: r > 0 ? (c / r) * 100 : 0.0,
        ),
      );
      costPerServingTrend.add(
        _TimeValuePoint(
          date: day,
          label: DateFormat('dd MMM').format(day),
          value: q > 0 ? c / q : 0.0,
        ),
      );
    }

    final pos = await purchaseService.getPurchaseOrdersByRange(
      branchIds,
      start: _dateRange.start,
      end: _dateRange.end,
      statuses: const ['received', 'partial'],
    );
    final spendByIngredient = <String, double>{};
    final ingredientPriceHistory = <String, List<_TimeValuePoint>>{};
    for (final po in pos) {
      final orderDate = (po['orderDate'] as Timestamp?)?.toDate();
      if (orderDate == null) continue;
      final lineItems =
          List<Map<String, dynamic>>.from(po['lineItems'] as List? ?? const []);
      for (final line in lineItems) {
        final ingredientName = (line['ingredientName'] ?? '').toString();
        final ingredientId = (line['ingredientId'] ?? '').toString();
        if (ingredientName.isEmpty) continue;
        final lineTotal = (line['lineTotal'] as num?)?.toDouble() ?? 0.0;
        spendByIngredient[ingredientName] =
            (spendByIngredient[ingredientName] ?? 0.0) + lineTotal;

        final unitCost = (line['unitCost'] as num?)?.toDouble() ?? 0.0;
        if (ingredientId.isNotEmpty && unitCost > 0) {
          ingredientPriceHistory.putIfAbsent(ingredientId, () => []);
          ingredientPriceHistory[ingredientId]!.add(
            _TimeValuePoint(
              date: orderDate,
              label: DateFormat('dd MMM').format(orderDate),
              value: unitCost,
            ),
          );
        }
      }
    }

    final topIngredientSpend = spendByIngredient.entries
        .map((e) => _NamedValue(name: e.key, value: e.value))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    for (final list in ingredientPriceHistory.values) {
      list.sort((a, b) => a.date.compareTo(b.date));
    }

    return _FoodCostAnalyticsData(
      isEmpty: orders.isEmpty && pos.isEmpty,
      averageFoodCostPercent:
          totalRevenue > 0 ? (totalCost / totalRevenue) * 100 : 0.0,
      averageCostPerServing: totalItems > 0 ? totalCost / totalItems : 0.0,
      foodCostTrend: foodCostTrend,
      costPerServingTrend:
          costPerServingTrend.where((e) => e.value > 0).toList(),
      topIngredientSpend: topIngredientSpend.take(10).toList(),
      ingredients: ingredients
          .map((i) => _IngredientOption(id: i.id, name: i.name))
          .toList(),
      ingredientPriceHistory: ingredientPriceHistory,
    );
  }

  Future<_WasteAnalyticsData> _loadWasteAnalytics(
    List<String> branchIds,
  ) async {
    if (branchIds.isEmpty) return _WasteAnalyticsData.empty();
    final wasteService = Provider.of<WasteService>(context, listen: false);
    final wasteEntries = await wasteService.getWasteEntriesByRange(
      branchIds,
      start: _dateRange.start,
      end: _dateRange.end,
    );

    final totalWasteCost = wasteEntries.fold<double>(
      0.0,
      (sum, w) => sum + ((w['estimatedLoss'] as num?)?.toDouble() ?? 0.0),
    );
    final wasteCount = wasteEntries.length;

    final rangeDays = _dateRange.end.difference(_dateRange.start).inDays + 1;
    final grouping = rangeDays <= 30
        ? _Grouping.daily
        : rangeDays <= 90
            ? _Grouping.weekly
            : _Grouping.monthly;

    final groupedWaste = <DateTime, double>{};
    final dailyWaste = <DateTime, double>{};
    final reasons = <String, double>{};
    for (final w in wasteEntries) {
      final date = (w['wasteDate'] as Timestamp?)?.toDate();
      if (date == null) continue;
      final value = (w['estimatedLoss'] as num?)?.toDouble() ?? 0.0;
      final reason = (w['reason'] ?? 'other').toString();
      final groupDate = _bucketDate(date, grouping);
      groupedWaste[groupDate] = (groupedWaste[groupDate] ?? 0.0) + value;
      final day = DateTime(date.year, date.month, date.day);
      dailyWaste[day] = (dailyWaste[day] ?? 0.0) + value;
      reasons[reason] = (reasons[reason] ?? 0.0) + value;
    }

    final groupedWasteSeries = groupedWaste.entries
        .map(
          (e) => _TimeValuePoint(
            date: e.key,
            label: _bucketLabel(e.key, grouping),
            value: e.value,
          ),
        )
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    final allDays = _allDaysInRange(_dateRange.start, _dateRange.end);
    final dailyWasteSeries = allDays
        .map(
          (d) => _TimeValuePoint(
            date: d,
            label: DateFormat('dd MMM').format(d),
            value: dailyWaste[d] ?? 0.0,
          ),
        )
        .toList();
    final movingAverageSeries = <_TimeValuePoint>[];
    for (int i = 0; i < dailyWasteSeries.length; i++) {
      final start = i - 6 < 0 ? 0 : i - 6;
      final window = dailyWasteSeries.sublist(start, i + 1);
      final avg =
          window.fold<double>(0.0, (s, p) => s + p.value) / window.length;
      movingAverageSeries.add(
        _TimeValuePoint(
          date: dailyWasteSeries[i].date,
          label: dailyWasteSeries[i].label,
          value: avg,
        ),
      );
    }

    final reasonBreakdown = reasons.entries
        .map((e) => _NamedValue(name: e.key, value: e.value))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final currentFoodCostSummary = await _computeFoodCostSummary(
      branchIds,
      _dateRange.start,
      _dateRange.end,
    );
    final wastePct = currentFoodCostSummary.foodCostTotal > 0
        ? (totalWasteCost / currentFoodCostSummary.foodCostTotal) * 100
        : 0.0;

    final period = _dateRange.end.difference(_dateRange.start);
    final prevStart = _dateRange.start.subtract(period);
    final prevEnd = _dateRange.end.subtract(period);
    final prevWaste = await wasteService.getWasteEntriesByRange(
      branchIds,
      start: prevStart,
      end: prevEnd,
    );
    final prevWasteCost = prevWaste.fold<double>(
      0.0,
      (sum, w) => sum + ((w['estimatedLoss'] as num?)?.toDouble() ?? 0.0),
    );
    final prevFoodCostSummary = await _computeFoodCostSummary(
      branchIds,
      prevStart,
      prevEnd,
    );
    final prevWastePct = prevFoodCostSummary.foodCostTotal > 0
        ? (prevWasteCost / prevFoodCostSummary.foodCostTotal) * 100
        : 0.0;
    final delta = wastePct - prevWastePct;

    final wastePctColor = wastePct <= 5
        ? Colors.green
        : wastePct <= 10
            ? Colors.orange
            : Colors.red;

    return _WasteAnalyticsData(
      totalWasteCost: totalWasteCost,
      wasteCount: wasteCount,
      wastePct: wastePct,
      wastePctDelta: delta,
      wastePctColor: wastePctColor,
      groupedWasteSeries: groupedWasteSeries,
      reasonBreakdown: reasonBreakdown,
      dailyWasteSeries: dailyWasteSeries,
      movingAverageSeries: movingAverageSeries,
    );
  }

  Future<_PurchasesAnalyticsData> _loadPurchasesAnalytics(
    List<String> branchIds,
  ) async {
    if (branchIds.isEmpty) return _PurchasesAnalyticsData.empty();
    final purchaseService =
        Provider.of<PurchaseOrderService>(context, listen: false);
    final ingredientService =
        Provider.of<IngredientService>(context, listen: false);

    final pos = await purchaseService.getPurchaseOrdersByRange(
      branchIds,
      start: _dateRange.start,
      end: _dateRange.end,
    );
    final receivedOrPartial = pos.where((po) {
      final s = (po['status'] ?? '').toString();
      return s == 'received' || s == 'partial';
    }).toList();
    final pendingCount =
        pos.where((po) => (po['status'] ?? '') == 'pending').length;

    final supplierSpendMap = <String, double>{};
    final leadTimeMap = <String, List<double>>{};
    final frequencyMap = <DateTime, int>{};
    final ingredientLatestSupplierPrice =
        <String, Map<String, _SupplierCostPoint>>{};

    for (final po in pos) {
      final orderDate = (po['orderDate'] as Timestamp?)?.toDate();
      final receivedDate = (po['receivedDate'] as Timestamp?)?.toDate();
      final supplierName = (po['supplierName'] ?? 'Unknown').toString();
      final status = (po['status'] ?? '').toString();
      final total = (po['totalAmount'] as num?)?.toDouble() ?? 0.0;

      if (status == 'received' || status == 'partial') {
        supplierSpendMap[supplierName] =
            (supplierSpendMap[supplierName] ?? 0.0) + total;
      }
      if (status == 'received' && orderDate != null && receivedDate != null) {
        final days = receivedDate.difference(orderDate).inHours / 24.0;
        leadTimeMap.putIfAbsent(supplierName, () => []).add(days);
      }
      if (orderDate != null) {
        final bucket = _bucketDate(orderDate, _Grouping.weekly);
        frequencyMap[bucket] = (frequencyMap[bucket] ?? 0) + 1;
      }

      final lineItems =
          List<Map<String, dynamic>>.from(po['lineItems'] ?? const []);
      for (final item in lineItems) {
        final ingredientId = (item['ingredientId'] ?? '').toString();
        if (ingredientId.isEmpty || orderDate == null) continue;
        final unitCost = (item['unitCost'] as num?)?.toDouble() ?? 0.0;
        if (unitCost <= 0) continue;
        ingredientLatestSupplierPrice.putIfAbsent(ingredientId, () => {});
        final current =
            ingredientLatestSupplierPrice[ingredientId]![supplierName];
        if (current == null || orderDate.isAfter(current.date)) {
          ingredientLatestSupplierPrice[ingredientId]![supplierName] =
              _SupplierCostPoint(
            supplierName: supplierName,
            unitCost: unitCost,
            date: orderDate,
          );
        }
      }
    }

    final supplierSpend = supplierSpendMap.entries
        .map((e) => _NamedValue(name: e.key, value: e.value))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final supplierLeadTimes = leadTimeMap.entries
        .map(
          (e) => _SupplierLeadTime(
            supplierName: e.key,
            avgDays: e.value.reduce((a, b) => a + b) / e.value.length,
          ),
        )
        .toList()
      ..sort((a, b) => a.avgDays.compareTo(b.avgDays));

    final orderFrequencySeries = frequencyMap.entries
        .map(
          (e) => _TimeValuePoint(
            date: e.key,
            label: _bucketLabel(e.key, _Grouping.weekly),
            value: e.value.toDouble(),
          ),
        )
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    final ingredients =
        await ingredientService.streamIngredients(branchIds).first;
    final ingredientOptions = ingredients
        .map((i) => _IngredientOption(id: i.id, name: i.name))
        .toList();

    final ingredientPriceBySupplier = <String, List<_SupplierCostPoint>>{};
    ingredientLatestSupplierPrice.forEach((ingredientId, supplierMap) {
      final list = supplierMap.values.toList()
        ..sort((a, b) => a.unitCost.compareTo(b.unitCost));
      if (list.isNotEmpty) {
        final cheapest = list.first.unitCost;
        for (final point in list) {
          point.isCheapest = (point.unitCost - cheapest).abs() < 0.0001;
        }
      }
      ingredientPriceBySupplier[ingredientId] = list;
    });

    return _PurchasesAnalyticsData(
      totalPurchases: pos.fold<double>(
        0.0,
        (sum, po) => sum + ((po['totalAmount'] as num?)?.toDouble() ?? 0.0),
      ),
      poCount: pos.length,
      pendingCount: pendingCount,
      receivedOrPartialCount: receivedOrPartial.length,
      supplierSpend: supplierSpend.take(10).toList(),
      supplierLeadTimes: supplierLeadTimes,
      orderFrequencySeries: orderFrequencySeries,
      ingredients: ingredientOptions,
      ingredientPriceBySupplier: ingredientPriceBySupplier,
    );
  }

  Future<_FoodCostSummary> _computeFoodCostSummary(
    List<String> branchIds,
    DateTime start,
    DateTime end,
  ) async {
    if (branchIds.isEmpty) return const _FoodCostSummary(foodCostTotal: 0.0);
    final recipeService = Provider.of<RecipeService>(context, listen: false);
    final orders = await _getOrdersForRange(branchIds, start: start, end: end);
    Query<Map<String, dynamic>> menuQuery =
        FirebaseFirestore.instance.collection('menu_items');
    if (branchIds.length == 1) {
      menuQuery = menuQuery.where('branchIds', arrayContains: branchIds.first);
    } else {
      menuQuery = menuQuery.where('branchIds',
          arrayContainsAny: branchIds.take(10).toList());
    }
    final menuItemsSnap = await menuQuery.get();
    final menuById = <String, Map<String, dynamic>>{
      for (final d in menuItemsSnap.docs) d.id: d.data(),
    };
    final recipeIds = menuById.values
        .map((m) => (m['recipeId'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    final recipes = await recipeService.getRecipesByIds(recipeIds);
    final recipeById = {for (final r in recipes) r.id: r};
    const completedStatuses = {'delivered', 'paid', 'collected', 'served'};
    double total = 0.0;
    for (final order in orders) {
      final status = (order['status'] ?? '').toString().toLowerCase();
      if (!completedStatuses.contains(status)) continue;
      final items = List<Map<String, dynamic>>.from(order['items'] ?? const []);
      for (final item in items) {
        final menuItemId =
            (item['menuItemId'] ?? item['itemId'] ?? '').toString();
        final qty = (item['quantity'] as num?)?.toInt() ?? 1;
        final menu = menuById[menuItemId];
        final recipeId = (menu?['recipeId'] ?? '').toString();
        if (recipeId.isEmpty || !recipeById.containsKey(recipeId)) continue;
        total += recipeById[recipeId]!.totalCost * qty;
      }
    }
    return _FoodCostSummary(foodCostTotal: total);
  }

  List<DateTime> _allDaysInRange(DateTime start, DateTime end) {
    final list = <DateTime>[];
    var cursor = DateTime(start.year, start.month, start.day);
    final last = DateTime(end.year, end.month, end.day);
    while (!cursor.isAfter(last)) {
      list.add(cursor);
      cursor = cursor.add(const Duration(days: 1));
    }
    return list;
  }

  DateTime _bucketDate(DateTime date, _Grouping grouping) {
    switch (grouping) {
      case _Grouping.daily:
        return DateTime(date.year, date.month, date.day);
      case _Grouping.weekly:
        final monday = date.subtract(Duration(days: date.weekday - 1));
        return DateTime(monday.year, monday.month, monday.day);
      case _Grouping.monthly:
        return DateTime(date.year, date.month, 1);
    }
  }

  String _bucketLabel(DateTime date, _Grouping grouping) {
    switch (grouping) {
      case _Grouping.daily:
        return DateFormat('dd MMM').format(date);
      case _Grouping.weekly:
        return 'Wk ${DateFormat('dd MMM').format(date)}';
      case _Grouping.monthly:
        return DateFormat('MMM yyyy').format(date);
    }
  }

  Widget _buildMainAnalyticsTabs() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(25),
      ),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(25),
          color: Colors.deepPurple,
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.deepPurple,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        dividerColor: Colors.transparent,
        tabs: const [
          Tab(
            icon: Icon(Icons.trending_up, size: 18),
            text: 'Sales',
          ),
          Tab(
            icon: Icon(Icons.inventory_2_outlined, size: 18),
            text: 'Inventory',
          ),
          Tab(
            icon: Icon(Icons.attach_money, size: 18),
            text: 'Food Cost',
          ),
          Tab(
            icon: Icon(Icons.delete_outline, size: 18),
            text: 'Waste',
          ),
          Tab(
            icon: Icon(Icons.shopping_cart_outlined, size: 18),
            text: 'Purchases',
          ),
          Tab(
            icon: Icon(Icons.point_of_sale, size: 18),
            text: 'Registers',
          ),
        ],
      ),
    );
  }

  Widget _buildSalesOrderTypeFilter() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildSalesOrderFilterChip(
                'all', 'All Orders', Icons.dashboard_outlined),
            _buildSalesOrderFilterChip(
                'delivery', 'Delivery', Icons.delivery_dining_outlined),
            _buildSalesOrderFilterChip(
                'takeaway', 'Takeaway', Icons.shopping_bag_outlined),
            _buildSalesOrderFilterChip(
                'pickup', 'Pickup', Icons.storefront_outlined),
            _buildSalesOrderFilterChip(
                'dine_in', 'Dine In', Icons.table_bar_outlined),
          ],
        ),
      ),
    );
  }

  Widget _buildSalesOrderFilterChip(String value, String label, IconData icon) {
    final isSelected = _selectedOrderType == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        selected: isSelected,
        label: Text(label),
        avatar: Icon(icon,
            size: 18, color: isSelected ? Colors.white : Colors.deepPurple),
        selectedColor: Colors.deepPurple,
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : Colors.deepPurple,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
        onSelected: (bool selected) {
          if (selected) {
            setState(() {
              _selectedOrderType = value;
            });
          }
        },
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
            border: Border.all(
                color: Colors.deepPurple.withOpacity(0.4), width: 1.5),
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
              Icon(Icons.keyboard_arrow_down_rounded,
                  color: Colors.deepPurple, size: 24),
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
        final avgOrderValue =
            completedCount > 0 ? totalRevenue / completedCount : 0;

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
      String title, String value, IconData icon, Color color,
      {VoidCallback? onTap}) {
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
      final aTime =
          (a.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
      final bTime =
          (b.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
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
                      child: Icon(Icons.receipt_long_rounded,
                          color: themeColor, size: 24),
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
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
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
                            Icon(Icons.inbox_outlined,
                                size: 64, color: Colors.grey[300]),
                            const SizedBox(height: 16),
                            Text(
                              'No orders found',
                              style: TextStyle(
                                  color: Colors.grey[500], fontSize: 16),
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
                          return _buildOrderDetailCard(
                              data, themeColor, doc.id);
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
  Widget _buildOrderDetailCard(
      Map<String, dynamic> data, Color themeColor, String orderId) {
    final status = (data['status'] as String?) ?? 'unknown';
    final orderType = (data['Order_type'] as String?) ?? 'unknown';
    final totalAmount = (data['totalAmount'] as num?)?.toDouble() ?? 0;
    final timestamp = data['timestamp'] as Timestamp?;
    final dailyOrderNumber =
        OrderNumberHelper.getDisplayNumber(data, orderId: orderId);
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
                dailyOrderNumber == OrderNumberHelper.loadingText ||
                        dailyOrderNumber.startsWith('#')
                    ? dailyOrderNumber
                    : '#$dailyOrderNumber',
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
                    Icon(Icons.person_outline,
                        size: 18, color: Colors.grey[600]),
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
                        Icon(Icons.shopping_bag_outlined,
                            size: 16, color: Colors.grey[600]),
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
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
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
                                final originalPrice =
                                    (item['price'] as num?)?.toDouble() ?? 0;
                                final discountedPrice =
                                    (item['discountedPrice'] as num?)
                                        ?.toDouble();
                                final effectivePrice =
                                    (discountedPrice != null &&
                                            discountedPrice > 0)
                                        ? discountedPrice
                                        : originalPrice;
                                final quantity =
                                    (item['quantity'] as num?)?.toInt() ?? 1;
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
    final s = AppConstants.normalizeStatus(status);
    switch (s) {
      case AppConstants.statusDelivered:
      case AppConstants.statusPaid:
      case AppConstants.statusCollected:
      case AppConstants.statusServed:
        return Colors.green;
      case AppConstants.statusPreparing:
        return Colors.orange;
      case AppConstants.statusPrepared:
        return Colors.blue;
      case AppConstants.statusCancelled:
        return Colors.red;
      case AppConstants.statusRefunded:
        return Colors.purple;
      case AppConstants.statusPending:
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
            const completedStatuses = {
              'delivered',
              'paid',
              'collected',
              'served'
            };
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
                final discountedPrice =
                    (item['discountedPrice'] as num?)?.toDouble();
                final effectivePrice =
                    (discountedPrice != null && discountedPrice > 0)
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

              // Use standardized normalization logic
              final rawType =
                  (data['Order_type'] ?? data['order_type'] ?? '').toString();
              if (!AppConstants.isDeliveryOrder(rawType)) continue;

              // Greedy extraction for rider ID
              final riderIdRaw = (data['riderId'] ??
                  data['rider_id'] ??
                  data['driverId'] ??
                  data['driver_id'] ??
                  data['assignedRiderId'] ??
                  (data['rider_info'] is Map
                      ? data['rider_info']['id']
                      : null));

              final riderId = riderIdRaw?.toString().trim();

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

            // Fetch rider names from staff collection
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
            .collection('staff')
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
      final userScope = context.read<UserScopeService>();
      final branchFilter = context.read<BranchFilterService>();
      final effectiveBranchIds =
          branchFilter.getFilterBranchIds(userScope.branchIds);

      Query<Map<String, dynamic>> query = FirebaseFirestore.instance
          .collection('Orders')
          .where('timestamp',
              isGreaterThanOrEqualTo: Timestamp.fromDate(reportDateRange.start))
          .where('timestamp',
              isLessThanOrEqualTo: Timestamp.fromDate(reportDateRange.end));

      // Filter by branch
      if (effectiveBranchIds.isNotEmpty) {
        if (effectiveBranchIds.length == 1) {
          query =
              query.where('branchIds', arrayContains: effectiveBranchIds.first);
        } else {
          query =
              query.where('branchIds', arrayContainsAny: effectiveBranchIds);
        }
      }

      query = query.orderBy('timestamp', descending: true);

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
      final itemOriginalRevenue =
          <String, double>{}; // Revenue at original prices
      final itemHasDiscount =
          <String, bool>{}; // Track if item ever had discounts
      for (var doc in orders) {
        final data = doc.data();
        final items = List<Map<String, dynamic>>.from(data['items'] ?? []);
        for (var item in items) {
          final itemName = item['name'] ?? 'Unknown Item';
          final quantity = (item['quantity'] as num?)?.toInt() ?? 1;
          // Use discountedPrice if available for accurate revenue calculation
          final originalPrice = (item['price'] as num?)?.toDouble() ?? 0;
          final discountedPrice = (item['discountedPrice'] as num?)?.toDouble();
          final hasDiscount = discountedPrice != null &&
              discountedPrice > 0 &&
              discountedPrice < originalPrice;
          final effectivePrice = hasDiscount ? discountedPrice! : originalPrice;

          itemCounts.update(itemName, (v) => v + quantity,
              ifAbsent: () => quantity);
          itemRevenue.update(itemName, (v) => v + (effectivePrice * quantity),
              ifAbsent: () => effectivePrice * quantity);
          itemOriginalRevenue.update(
              itemName, (v) => v + (originalPrice * quantity),
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
                'savings': (itemOriginalRevenue[e.key] ?? 0) -
                    (itemRevenue[e.key] ?? 0),
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

      // Aggregate top riders (for delivery orders) using greedy ID extraction
      final riderIdCounts = <String, int>{};
      for (var doc in orders) {
        final data = doc.data();

        // Ensure it's a delivery order using robust check
        final rawType =
            (data['Order_type'] ?? data['order_type'] ?? '').toString();
        if (!AppConstants.isDeliveryOrder(rawType)) continue;

        final riderIdRaw = (data['riderId'] ??
            data['rider_id'] ??
            data['driverId'] ??
            data['driver_id'] ??
            data['assignedRiderId'] ??
            (data['rider_info'] is Map ? data['rider_info']['id'] : null));

        final riderId = riderIdRaw?.toString().trim();

        if (riderId != null && riderId.isNotEmpty) {
          riderIdCounts.update(riderId, (v) => v + 1, ifAbsent: () => 1);
        }
      }
      final topRiderIds = riderIdCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      // Fetch rider names from staff collection
      final topRidersList = <Map<String, dynamic>>[];
      for (var entry in topRiderIds.take(5)) {
        try {
          final driverDoc = await FirebaseFirestore.instance
              .collection('staff')
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

      // Fetch new analytics data
      double totalInventoryValue = 0;
      int lowStockCount = 0;
      int deadStockCount = 0;

      final ingredientsSnapshot = await FirebaseFirestore.instance
          .collectionGroup('ingredients')
          .where('branchIds',
              arrayContainsAny: effectiveBranchIds.isEmpty
                  ? ['dummy']
                  : effectiveBranchIds.take(10).toList())
          .get();
      for (var doc in ingredientsSnapshot.docs) {
        final data = doc.data();
        final stock = (data['currentStock'] ?? 0).toDouble();
        final cost = (data['costPerUnit'] ?? 0).toDouble();
        final minThreshold = (data['minStockThreshold'] ?? 0).toDouble();
        totalInventoryValue += (stock * cost);
        if (stock <= minThreshold) lowStockCount++;
        if (stock == 0) deadStockCount++;
      }

      double totalWasteCost = 0;
      int wasteCount = 0;
      final Map<String, dynamic> itemsWaste = {};

      final wasteSnapshot = await FirebaseFirestore.instance
          .collectionGroup('waste_entries')
          .where('branchIds',
              arrayContainsAny: effectiveBranchIds.isEmpty
                  ? ['dummy']
                  : effectiveBranchIds.take(10).toList())
          .where('wasteDate',
              isGreaterThanOrEqualTo: Timestamp.fromDate(reportDateRange.start))
          .where('wasteDate',
              isLessThanOrEqualTo: Timestamp.fromDate(reportDateRange.end))
          .get();
      wasteCount = wasteSnapshot.docs.length;

      for (var doc in wasteSnapshot.docs) {
        final data = doc.data();
        final loss = (data['estimatedLoss'] ?? 0).toDouble();
        totalWasteCost += loss;

        final name = data['itemName'] ?? 'Unknown';
        final qty = (data['quantity'] ?? 0).toDouble();
        final unit = data['unit'] ?? '';
        if (itemsWaste.containsKey(name)) {
          itemsWaste[name]['loss'] += loss;
          itemsWaste[name]['qty'] += qty;
        } else {
          itemsWaste[name] = {
            'name': name,
            'loss': loss,
            'qty': qty,
            'unit': unit
          };
        }
      }
      final sortedWastedItems = itemsWaste.values.toList()
        ..sort((a, b) => (b['loss'] as double).compareTo(a['loss'] as double));
      final topWastedItems = sortedWastedItems.take(5).toList();

      double totalPurchases = 0;
      int poCount = 0;
      final poSnapshot = await FirebaseFirestore.instance
          .collection('purchase_orders')
          .where('branchIds',
              arrayContainsAny: effectiveBranchIds.isEmpty
                  ? ['dummy']
                  : effectiveBranchIds.take(10).toList())
          .where('orderDate',
              isGreaterThanOrEqualTo: Timestamp.fromDate(reportDateRange.start))
          .where('orderDate',
              isLessThanOrEqualTo: Timestamp.fromDate(reportDateRange.end))
          .get();
      poCount = poSnapshot.docs.length;
      for (var doc in poSnapshot.docs) {
        final data = doc.data();
        totalPurchases += (data['totalAmount'] ?? 0).toDouble();
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
        totalInventoryValue: totalInventoryValue,
        lowStockCount: lowStockCount,
        deadStockCount: deadStockCount,
        totalWasteCost: totalWasteCost,
        wasteCount: wasteCount,
        totalPurchases: totalPurchases,
        poCount: poCount,
        topWastedItems: topWastedItems,
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
      final userScope = context.read<UserScopeService>();
      final branchFilter = context.read<BranchFilterService>();
      final effectiveBranchIds =
          branchFilter.getFilterBranchIds(userScope.branchIds);

      Query<Map<String, dynamic>> query = FirebaseFirestore.instance
          .collection('Orders')
          .where('timestamp',
              isGreaterThanOrEqualTo: Timestamp.fromDate(reportDateRange.start))
          .where('timestamp',
              isLessThanOrEqualTo: Timestamp.fromDate(reportDateRange.end));

      // Filter by branch
      if (effectiveBranchIds.isNotEmpty) {
        if (effectiveBranchIds.length == 1) {
          query =
              query.where('branchIds', arrayContains: effectiveBranchIds.first);
        } else {
          query =
              query.where('branchIds', arrayContainsAny: effectiveBranchIds);
        }
      }

      query = query.orderBy('timestamp', descending: true);

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
        final rawType = (data['Order_type'] as String?) ??
            (data['order_type'] as String?) ??
            'unknown';

        ordersSheet.appendRow([
          excel_lib.TextCellValue(doc.id),
          excel_lib.TextCellValue(timestamp != null
              ? DateFormat('yyyy-MM-dd HH:mm').format(timestamp.toDate())
              : ''),
          excel_lib.TextCellValue(data['customerName'] as String? ??
              data['customer_name'] as String? ??
              'Unknown'),
          excel_lib.TextCellValue(_formatOrderTypeForPieLabel(rawType)),
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
          final hasDiscount = discountedPrice != null &&
              discountedPrice > 0 &&
              discountedPrice < originalPrice;
          final effectivePrice = hasDiscount ? discountedPrice! : originalPrice;

          itemCounts.update(itemName, (v) => v + quantity,
              ifAbsent: () => quantity);
          itemRevenue.update(itemName, (v) => v + (effectivePrice * quantity),
              ifAbsent: () => effectivePrice * quantity);
          itemOriginalRevenue.update(
              itemName, (v) => v + (originalPrice * quantity),
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
      final totalOriginal =
          itemOriginalRevenue.values.fold<double>(0, (a, b) => a + b);
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

      // ===== Inventory Sheet =====
      final ingredientsSnapshot = await FirebaseFirestore.instance
          .collectionGroup('ingredients')
          .where('branchIds',
              arrayContainsAny: effectiveBranchIds.isEmpty
                  ? ['dummy']
                  : effectiveBranchIds.take(10).toList())
          .get();

      final inventorySheet = excelFile['Inventory Health'];
      inventorySheet.appendRow([
        excel_lib.TextCellValue('Name'),
        excel_lib.TextCellValue('Category'),
        excel_lib.TextCellValue('Current Stock'),
        excel_lib.TextCellValue('Min Threshold'),
        excel_lib.TextCellValue('Cost Per Unit (QAR)'),
        excel_lib.TextCellValue('Total Value (QAR)'),
        excel_lib.TextCellValue('Status'),
      ]);
      for (var doc in ingredientsSnapshot.docs) {
        final data = doc.data();
        final name = data['name'] ?? 'Unknown';
        final category = data['category'] ?? '-';
        final stock = (data['currentStock'] ?? 0).toDouble();
        final minThreshold = (data['minStockThreshold'] ?? 0).toDouble();
        final cost = (data['costPerUnit'] ?? 0).toDouble();

        String status = 'OK';
        if (stock == 0)
          status = 'Out of Stock';
        else if (stock <= minThreshold) status = 'Low Stock';

        inventorySheet.appendRow([
          excel_lib.TextCellValue(name),
          excel_lib.TextCellValue(category),
          excel_lib.DoubleCellValue(stock),
          excel_lib.DoubleCellValue(minThreshold),
          excel_lib.DoubleCellValue(cost),
          excel_lib.DoubleCellValue(stock * cost),
          excel_lib.TextCellValue(status),
        ]);
      }

      // ===== Waste Sheet =====
      final wasteSnapshot = await FirebaseFirestore.instance
          .collectionGroup('waste_entries')
          .where('branchIds',
              arrayContainsAny: effectiveBranchIds.isEmpty
                  ? ['dummy']
                  : effectiveBranchIds.take(10).toList())
          .where('wasteDate',
              isGreaterThanOrEqualTo: Timestamp.fromDate(reportDateRange.start))
          .where('wasteDate',
              isLessThanOrEqualTo: Timestamp.fromDate(reportDateRange.end))
          .get();

      final wasteSheet = excelFile['Waste Logs'];
      wasteSheet.appendRow([
        excel_lib.TextCellValue('Date'),
        excel_lib.TextCellValue('Item Name'),
        excel_lib.TextCellValue('Quantity'),
        excel_lib.TextCellValue('Reason'),
        excel_lib.TextCellValue('Est. Loss (QAR)'),
        excel_lib.TextCellValue('Recorded By'),
      ]);
      for (var doc in wasteSnapshot.docs) {
        final data = doc.data();
        final wasteDate = (data['wasteDate'] as Timestamp?)?.toDate();
        wasteSheet.appendRow([
          excel_lib.TextCellValue(wasteDate != null
              ? DateFormat('yyyy-MM-dd HH:mm').format(wasteDate)
              : '-'),
          excel_lib.TextCellValue(data['itemName'] ?? 'Unknown'),
          excel_lib.TextCellValue(
              '${data['quantity'] ?? 0} ${data['unit'] ?? ''}'),
          excel_lib.TextCellValue(data['reason'] ?? 'Unknown'),
          excel_lib.DoubleCellValue((data['estimatedLoss'] ?? 0).toDouble()),
          excel_lib.TextCellValue(data['recordedBy'] ?? 'System'),
        ]);
      }

      // ===== Purchases Sheet =====
      final poSnapshot = await FirebaseFirestore.instance
          .collection('purchase_orders')
          .where('branchIds',
              arrayContainsAny: effectiveBranchIds.isEmpty
                  ? ['dummy']
                  : effectiveBranchIds.take(10).toList())
          .where('orderDate',
              isGreaterThanOrEqualTo: Timestamp.fromDate(reportDateRange.start))
          .where('orderDate',
              isLessThanOrEqualTo: Timestamp.fromDate(reportDateRange.end))
          .get();

      final poSheet = excelFile['Purchase Orders'];
      poSheet.appendRow([
        excel_lib.TextCellValue('PO Number'),
        excel_lib.TextCellValue('PO Date'),
        excel_lib.TextCellValue('Supplier'),
        excel_lib.TextCellValue('Amount (QAR)'),
        excel_lib.TextCellValue('Status'),
        excel_lib.TextCellValue('Expected Delivery'),
      ]);
      for (var doc in poSnapshot.docs) {
        final data = doc.data();
        final orderDate = (data['orderDate'] as Timestamp?)?.toDate();
        final deliveryDate =
            (data['expectedDeliveryDate'] as Timestamp?)?.toDate();
        poSheet.appendRow([
          excel_lib.TextCellValue(data['poNumber'] as String? ?? '-'),
          excel_lib.TextCellValue(orderDate != null
              ? DateFormat('yyyy-MM-dd').format(orderDate)
              : '-'),
          excel_lib.TextCellValue(data['supplierName'] as String? ?? 'Unknown'),
          excel_lib.DoubleCellValue((data['totalAmount'] ?? 0).toDouble()),
          excel_lib.TextCellValue(data['status'] as String? ?? 'pending'),
          excel_lib.TextCellValue(deliveryDate != null
              ? DateFormat('yyyy-MM-dd').format(deliveryDate)
              : '-'),
        ]);
      }

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

  // ---------------------------------------------------------
  // Registers Tab
  // ---------------------------------------------------------

  Widget _buildRegistersTab(List<String> effectiveBranchIds,
      UserScopeService userScope, BranchFilterService branchFilter) {
    if (effectiveBranchIds.isEmpty) {
      return const Center(child: Text('No branches selected.'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDateRangeSelector(),
          const SizedBox(height: 16),
          FutureBuilder<_RegistersAnalyticsData>(
            future: _loadRegistersAnalytics(effectiveBranchIds),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }
              final data = snapshot.data ?? _RegistersAnalyticsData.empty();

              if (data.totalSessions == 0) {
                return _buildEmptyState(
                  icon: Icons.point_of_sale,
                  message: 'No Register Sessions found. Adjust your date range or select a different branch.',
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricCard(
                          'Total Sessions',
                          data.totalSessions.toString(),
                          Icons.point_of_sale,
                          Colors.purple,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildMetricCard(
                          'Expected Cash',
                          'QAR ${data.totalExpected.toStringAsFixed(2)}',
                          Icons.account_balance_wallet,
                          Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildMetricCard(
                          'Actual Cash',
                          'QAR ${data.totalActual.toStringAsFixed(2)}',
                          Icons.attach_money,
                          Colors.green,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildMetricCard(
                          'Net Variance',
                          'QAR ${data.totalVariance.toStringAsFixed(2)}',
                          Icons.compare_arrows,
                          data.totalVariance < 0 ? Colors.red : (data.totalVariance == 0 ? Colors.grey : Colors.green),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Recent Register Sessions',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                        ),
                        const SizedBox(height: 16),
                        ...data.sessions.map((session) {
                          final variance = session.closingBalance - session.expectedBalance;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.grey[50],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey[200]!),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: Colors.deepPurple.withOpacity(0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.point_of_sale, color: Colors.deepPurple, size: 20),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            branchFilter.getBranchName(session.branchId),
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Opened by ${session.openedBy}',
                                            style: TextStyle(color: Colors.grey[600], fontSize: 12),
                                          ),
                                          const SizedBox(height: 2),
                                          if (session.closedAt != null)
                                            Text(
                                              'Closed: ${DateFormat('MMM dd, yyyy  h:mm a').format(session.closedAt!)}',
                                              style: TextStyle(color: Colors.grey[600], fontSize: 11),
                                            ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          'Actual: QAR ${session.closingBalance.toStringAsFixed(2)}',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Expected: QAR ${session.expectedBalance.toStringAsFixed(2)}',
                                          style: TextStyle(color: Colors.grey[600], fontSize: 12),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Variance: ${variance >= 0 ? '+' : ''}${variance.toStringAsFixed(2)}',
                                          style: TextStyle(
                                            color: variance < 0 ? Colors.red : (variance > 0 ? Colors.green : Colors.grey[600]),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                        if (session.isForceClosed) ...[
                                          const SizedBox(height: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.orange.withOpacity(0.1),
                                              border: Border.all(color: Colors.orange.withOpacity(0.5)),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              'Force Closed (${session.activeOrdersAtClose} orders)',
                                              style: TextStyle(color: Colors.orange[800], fontSize: 10, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                                if (session.closedAt != null) ...[
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 12),
                                    child: Divider(height: 1),
                                  ),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      _buildSessionMetricChip('Orders', session.totalOrders.toString(), Colors.blue),
                                      _buildSessionMetricChip('Cash', 'QAR ${session.totalCashSales.toStringAsFixed(0)}', Colors.teal),
                                      _buildSessionMetricChip('Card', 'QAR ${session.totalCardSales.toStringAsFixed(0)}', Colors.indigo),
                                      _buildSessionMetricChip('Online', 'QAR ${session.totalOnlineSales.toStringAsFixed(0)}', Colors.cyan),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          );
                        }).toList(),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSessionMetricChip(String label, String value, MaterialColor color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 8, color: color),
        const SizedBox(width: 4),
        Text('$label: ', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        Text(value, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color[800])),
      ],
    );
  }

  Future<_RegistersAnalyticsData> _loadRegistersAnalytics(List<String> branchIds) async {
    if (branchIds.isEmpty) return _RegistersAnalyticsData.empty();
    
    final query = await FirebaseFirestore.instance
        .collection('pos_registers')
        .where('openedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(_dateRange.start))
        .where('openedAt', isLessThanOrEqualTo: Timestamp.fromDate(DateTime(_dateRange.end.year, _dateRange.end.month, _dateRange.end.day, 23, 59, 59)))
        .where('branchId', whereIn: branchIds.take(10).toList())
        .get();
        
    final sessions = query.docs.map((doc) => _RegisterSessionPoint.fromFirestore(doc)).toList()
      ..sort((a, b) => (b.closedAt ?? b.openedAt).compareTo((a.closedAt ?? a.openedAt)));

    double totalExpected = 0;
    double totalActual = 0;
    int forceClosedCount = 0;
    for (var s in sessions) {
      if (s.closedAt != null) {
        totalExpected += s.expectedBalance;
        totalActual += s.closingBalance;
      }
      if (s.isForceClosed) {
        forceClosedCount++;
      }
    }

    return _RegistersAnalyticsData(
      totalSessions: sessions.length,
      totalExpected: totalExpected,
      totalActual: totalActual,
      totalVariance: totalActual - totalExpected,
      sessions: sessions,
      forceClosedCount: forceClosedCount,
    );
  }
}

class _RegisterSessionPoint {
  final String id;
  final String branchId;
  final String openedBy;
  final String closedBy;
  final DateTime openedAt;
  final DateTime? closedAt;
  final double openingBalance;
  final double closingBalance;
  final double expectedBalance;
  final String notes;
  final int totalOrders;
  final int totalCancelled;
  final double totalCashSales;
  final double totalCardSales;
  final double totalOnlineSales;
  final double totalRefunds;
  final bool isForceClosed;
  final String? overriddenBy;
  final int activeOrdersAtClose;

  _RegisterSessionPoint({
    required this.id,
    required this.branchId,
    required this.openedBy,
    required this.closedBy,
    required this.openedAt,
    this.closedAt,
    required this.openingBalance,
    required this.closingBalance,
    required this.expectedBalance,
    required this.notes,
    this.totalOrders = 0,
    this.totalCancelled = 0,
    this.totalCashSales = 0.0,
    this.totalCardSales = 0.0,
    this.totalOnlineSales = 0.0,
    this.totalRefunds = 0.0,
    this.isForceClosed = false,
    this.overriddenBy,
    this.activeOrdersAtClose = 0,
  });

  factory _RegisterSessionPoint.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return _RegisterSessionPoint(
      id: doc.id,
      branchId: data['branchId'] ?? '',
      openedBy: data['openedBy'] ?? '',
      closedBy: data['closedBy'] ?? '',
      openedAt: (data['openedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      closedAt: (data['closedAt'] as Timestamp?)?.toDate(),
      openingBalance: (data['openingBalance'] as num?)?.toDouble() ?? 0.0,
      closingBalance: (data['closingBalance'] as num?)?.toDouble() ?? 0.0,
      expectedBalance: (data['expectedBalance'] as num?)?.toDouble() ?? 0.0,
      notes: data['notes'] ?? '',
      totalOrders: (data['totalOrders'] as num?)?.toInt() ?? 0,
      totalCancelled: (data['totalCancelled'] as num?)?.toInt() ?? 0,
      totalCashSales: (data['totalCashSales'] as num?)?.toDouble() ?? 0.0,
      totalCardSales: (data['totalCardSales'] as num?)?.toDouble() ?? 0.0,
      totalOnlineSales: (data['totalOnlineSales'] as num?)?.toDouble() ?? 0.0,
      totalRefunds: (data['totalRefunds'] as num?)?.toDouble() ?? 0.0,
      isForceClosed: data['isForceClosed'] == true,
      overriddenBy: data['overriddenBy'],
      activeOrdersAtClose: (data['activeOrdersAtClose'] as num?)?.toInt() ?? 0,
    );
  }
}

class _RegistersAnalyticsData {
  final int totalSessions;
  final double totalExpected;
  final double totalActual;
  final double totalVariance;
  final int forceClosedCount;
  final List<_RegisterSessionPoint> sessions;

  _RegistersAnalyticsData({
    required this.totalSessions,
    required this.totalExpected,
    required this.totalActual,
    required this.totalVariance,
    required this.sessions,
    this.forceClosedCount = 0,
  });

  factory _RegistersAnalyticsData.empty() => _RegistersAnalyticsData(
        totalSessions: 0,
        totalExpected: 0,
        totalActual: 0,
        totalVariance: 0,
        sessions: const [],
        forceClosedCount: 0,
      );
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

enum _Grouping { daily, weekly, monthly }

class _NamedValue {
  final String name;
  final double value;
  _NamedValue({required this.name, required this.value});
}

class _TimeValuePoint {
  final DateTime date;
  final String label;
  final double value;
  _TimeValuePoint({
    required this.date,
    required this.label,
    required this.value,
  });
}

class _IngredientOption {
  final String id;
  final String name;
  _IngredientOption({required this.id, required this.name});
}

class _DeadStockRow {
  final String name;
  final double currentStock;
  final double currentValue;
  final int? daysSinceLastUsed;
  _DeadStockRow({
    required this.name,
    required this.currentStock,
    required this.currentValue,
    required this.daysSinceLastUsed,
  });
}

class _InventoryAnalyticsData {
  final int ingredientCount;
  final double totalValue;
  final double? turnoverRate;
  final String turnoverNote;
  final double? stockAccuracyPct;
  final String stockAccuracyNote;
  final List<_DeadStockRow> deadStockRows;
  final List<_TimeValuePoint> carryingCostSeries;
  final String carryingCostNote;
  _InventoryAnalyticsData({
    required this.ingredientCount,
    required this.totalValue,
    required this.turnoverRate,
    required this.turnoverNote,
    required this.stockAccuracyPct,
    required this.stockAccuracyNote,
    required this.deadStockRows,
    required this.carryingCostSeries,
    required this.carryingCostNote,
  });

  factory _InventoryAnalyticsData.empty() => _InventoryAnalyticsData(
        ingredientCount: 0,
        totalValue: 0,
        turnoverRate: null,
        turnoverNote: '',
        stockAccuracyPct: null,
        stockAccuracyNote: '',
        deadStockRows: const [],
        carryingCostSeries: const [],
        carryingCostNote: '',
      );
}

class _FoodCostAnalyticsData {
  final bool isEmpty;
  final double averageFoodCostPercent;
  final double averageCostPerServing;
  final List<_TimeValuePoint> foodCostTrend;
  final List<_TimeValuePoint> costPerServingTrend;
  final List<_NamedValue> topIngredientSpend;
  final List<_IngredientOption> ingredients;
  final Map<String, List<_TimeValuePoint>> ingredientPriceHistory;
  _FoodCostAnalyticsData({
    required this.isEmpty,
    required this.averageFoodCostPercent,
    required this.averageCostPerServing,
    required this.foodCostTrend,
    required this.costPerServingTrend,
    required this.topIngredientSpend,
    required this.ingredients,
    required this.ingredientPriceHistory,
  });

  factory _FoodCostAnalyticsData.empty() => _FoodCostAnalyticsData(
        isEmpty: true,
        averageFoodCostPercent: 0,
        averageCostPerServing: 0,
        foodCostTrend: const [],
        costPerServingTrend: const [],
        topIngredientSpend: const [],
        ingredients: const [],
        ingredientPriceHistory: const {},
      );
}

class _WasteAnalyticsData {
  final double totalWasteCost;
  final int wasteCount;
  final double wastePct;
  final double wastePctDelta;
  final Color wastePctColor;
  final List<_TimeValuePoint> groupedWasteSeries;
  final List<_NamedValue> reasonBreakdown;
  final List<_TimeValuePoint> dailyWasteSeries;
  final List<_TimeValuePoint> movingAverageSeries;
  _WasteAnalyticsData({
    required this.totalWasteCost,
    required this.wasteCount,
    required this.wastePct,
    required this.wastePctDelta,
    required this.wastePctColor,
    required this.groupedWasteSeries,
    required this.reasonBreakdown,
    required this.dailyWasteSeries,
    required this.movingAverageSeries,
  });

  factory _WasteAnalyticsData.empty() => _WasteAnalyticsData(
        totalWasteCost: 0,
        wasteCount: 0,
        wastePct: 0,
        wastePctDelta: 0,
        wastePctColor: Colors.green,
        groupedWasteSeries: const [],
        reasonBreakdown: const [],
        dailyWasteSeries: const [],
        movingAverageSeries: const [],
      );
}

class _SupplierLeadTime {
  final String supplierName;
  final double avgDays;
  _SupplierLeadTime({required this.supplierName, required this.avgDays});
}

class _SupplierCostPoint {
  final String supplierName;
  final double unitCost;
  final DateTime date;
  bool isCheapest;
  _SupplierCostPoint({
    required this.supplierName,
    required this.unitCost,
    required this.date,
    this.isCheapest = false,
  });
}

class _PurchasesAnalyticsData {
  final double totalPurchases;
  final int poCount;
  final int pendingCount;
  final int receivedOrPartialCount;
  final List<_NamedValue> supplierSpend;
  final List<_SupplierLeadTime> supplierLeadTimes;
  final List<_TimeValuePoint> orderFrequencySeries;
  final List<_IngredientOption> ingredients;
  final Map<String, List<_SupplierCostPoint>> ingredientPriceBySupplier;
  _PurchasesAnalyticsData({
    required this.totalPurchases,
    required this.poCount,
    required this.pendingCount,
    required this.receivedOrPartialCount,
    required this.supplierSpend,
    required this.supplierLeadTimes,
    required this.orderFrequencySeries,
    required this.ingredients,
    required this.ingredientPriceBySupplier,
  });

  factory _PurchasesAnalyticsData.empty() => _PurchasesAnalyticsData(
        totalPurchases: 0,
        poCount: 0,
        pendingCount: 0,
        receivedOrPartialCount: 0,
        supplierSpend: const [],
        supplierLeadTimes: const [],
        orderFrequencySeries: const [],
        ingredients: const [],
        ingredientPriceBySupplier: const {},
      );
}

class _FoodCostSummary {
  final double foodCostTotal;
  const _FoodCostSummary({required this.foodCostTotal});
}
