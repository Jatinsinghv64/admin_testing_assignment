import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../Models/IngredientModel.dart';
import '../../Widgets/BranchFilterService.dart';
import '../../main.dart';
import '../../services/inventory/InventoryService.dart';
import '../../services/CsvExportService.dart';
import '../../utils/responsive_helper.dart';
import '../management/MenuManagementWidgets.dart';
import '../purchases/CreatePurchaseOrderScreen.dart';
import '../large/DishEditScreenLarge.dart';
import 'IngredientStockListScreen.dart';
import 'StocktakeScreen.dart';
import 'WasteDashboardScreen.dart';
import 'WasteEntryScreenLarge.dart';
import '../../Widgets/IngredientFormSheet.dart';
import '../../services/ingredients/IngredientService.dart';
import '../../services/inventory/ExcelImportService.dart';
import '../settings/RecipesScreen.dart';
import '../../services/ExportReportService.dart';
import 'ingredient_import_format_dialog.dart';
import 'QuickStockInScreen.dart';
import '../../Widgets/ai/reorder_predictions_panel.dart';
import '../../Widgets/ai/trending_suggestions_panel.dart';

// ─── Theme Colors (matching app ThemeData: light bg, deepPurple primary) ─────
class _InvColors {
  static Color background(BuildContext context) => Theme.of(context).scaffoldBackgroundColor;
  static Color surface(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? Colors.white.withOpacity(0.02) : Theme.of(context).cardColor;
  static Color border(BuildContext context) => Theme.of(context).dividerColor;
  static Color primary(BuildContext context) => Theme.of(context).colorScheme.primary;
  static Color textMain(BuildContext context) => Theme.of(context).textTheme.bodyLarge?.color ?? const Color(0xFF1E293B);
  static Color textMuted(BuildContext context) => Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6) ?? const Color(0xFF64748B);
}

class InventoryDashboardScreen extends StatefulWidget {
  const InventoryDashboardScreen({super.key});

  @override
  State<InventoryDashboardScreen> createState() =>
      _InventoryDashboardScreenState();
}

class _InventoryDashboardScreenState extends State<InventoryDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isImportingIngredients = false;

  static const _tabLabels = [
    'Stock Overview',
    'Stock List',
    'Stocktake',
    'Waste',
    'Categories',
    'Menu Items',
    'Recipes',
    'Trending ✨',
  ];
  static const _tabIcons = [
    Icons.dashboard_outlined,
    Icons.inventory_2_outlined,
    Icons.fact_check_outlined,
    Icons.delete_sweep_outlined,
    Icons.category_outlined,
    Icons.restaurant_menu_outlined,
    Icons.menu_book_outlined,
    Icons.auto_awesome_outlined,
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 8, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onTabChanged() => setState(() {});

  void _showSnackBar(
    String message, {
    Color backgroundColor = Colors.red,
  }) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
      ),
    );
  }

  Future<void> _handleBulkUpload(BuildContext context) async {
    if (_isImportingIngredients) {
      return;
    }

    final userScope = context.read<UserScopeService>();
    final branchFilter = context.read<BranchFilterService>();
    final branchIds = branchFilter.getFilterBranchIds(userScope.branchIds);

    if (branchIds.length != 1) {
      _showSnackBar(
        branchIds.isEmpty
            ? 'Select one branch before bulk uploading ingredients.'
            : 'Bulk upload works on one branch at a time. Please select a single branch.',
      );
      return;
    }

    final shouldContinue = await showIngredientImportFormatDialog(context);
    if (!shouldContinue || !mounted) {
      return;
    }

    final progress = ValueNotifier<String>('Preparing ingredient import');
    var dialogShown = false;
    setState(() => _isImportingIngredients = true);

    try {
      dialogShown = true;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PopScope(
          canPop: false,
          child: AlertDialog(
            content: ValueListenableBuilder<String>(
              valueListenable: progress,
              builder: (_, value, __) => Row(
                children: [
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.deepPurple,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(child: Text(value)),
                ],
              ),
            ),
          ),
        ),
      );

      final result = await ExcelImportService().pickAndImportFile(
        branchIds.first,
        onProgress: (message) => progress.value = message,
      );

      if (dialogShown && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        dialogShown = false;
      }

      if (result == null) {
        return;
      }

      final summary = StringBuffer('Ingredient import complete: ')
        ..write('${result.createdCount} added')
        ..write(', ${result.updatedCount} updated');
      if (result.skippedCount > 0) {
        summary.write(', ${result.skippedCount} skipped');
      }
      _showSnackBar(summary.toString(), backgroundColor: Colors.green);

      if (result.warnings.isNotEmpty && mounted) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Import Warnings'),
            content: SizedBox(
              width: 460,
              child: ListView(
                shrinkWrap: true,
                children: result.warnings
                    .take(12)
                    .map(
                      (warning) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(warning),
                      ),
                    )
                    .toList(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (dialogShown && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      _showSnackBar('Ingredient import failed: $e');
    } finally {
      progress.dispose();
      if (mounted) {
        setState(() => _isImportingIngredients = false);
      }
    }
  }

  Future<void> _handleInventoryExport(BuildContext context) async {
    try {
      final selectedFormat = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            'Export Inventory',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.table_view, color: Colors.green),
                title: const Text('CSV Format'),
                onTap: () => Navigator.pop(ctx, 'csv'),
              ),
              ListTile(
                leading: const Icon(Icons.table_chart, color: Colors.blue),
                title: const Text('Excel Format'),
                onTap: () => Navigator.pop(ctx, 'excel'),
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                title: const Text('PDF Format'),
                onTap: () => Navigator.pop(ctx, 'pdf'),
              ),
            ],
          ),
        ),
      );

      if (selectedFormat == null || !mounted) {
        return;
      }

      final userScope = context.read<UserScopeService>();
      final branchFilter = context.read<BranchFilterService>();
      final branchIds = branchFilter.getFilterBranchIds(userScope.branchIds);

      if (branchIds.isEmpty) {
        _showSnackBar('Select at least one branch before exporting inventory.');
        return;
      }

      final range = DateTimeRange(
        start: DateTime.now().subtract(const Duration(days: 30)),
        end: DateTime.now(),
      );

      if (selectedFormat == 'csv') {
        if (branchIds.length != 1) {
          _showSnackBar(
            'CSV inventory export works on one branch at a time. Please select a single branch.',
            backgroundColor: Colors.orange,
          );
          return;
        }

        final ingredients = await InventoryService().getIngredients(
          branchIds,
          isSuperAdmin: userScope.isSuperAdmin,
        );
        if (ingredients.isEmpty) {
          _showSnackBar(
            'No inventory items available to export.',
            backgroundColor: Colors.orange,
          );
          return;
        }

        await CsvExportService.exportInventoryStockFromData(
          context,
          ingredients,
          branchId: branchIds.first,
        );
        return;
      }

      _showSnackBar(
        'Generating ${selectedFormat.toUpperCase()} report...',
        backgroundColor: Theme.of(context).colorScheme.primary,
      );
      await ExportReportService.generateReport(
        context: context,
        dateRange: range,
        format: selectedFormat,
        selectedSections: {'inventory_stock'},
        branchIds: branchIds,
        branchFilter: branchFilter,
        userScope: userScope,
      );
    } catch (e) {
      _showSnackBar('Inventory export failed: $e');
    }
  }

  void _openAddIngredientForm(BuildContext context) {
    final userScope = Provider.of<UserScopeService>(context, listen: false);
    final branchFilter =
        Provider.of<BranchFilterService>(context, listen: false);
    final branchIds = branchFilter.getFilterBranchIds(userScope.branchIds);
    final effectiveBranchIds =
        branchIds.isNotEmpty ? branchIds : userScope.branchIds;

    if (effectiveBranchIds.isEmpty) {
      _showSnackBar('Select at least one branch before adding an ingredient.');
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => IngredientFormSheet(
        existing: null,
        branchIds: effectiveBranchIds,
        service: IngredientService(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final idx = _tabController.index;
    final isCategoryTab = idx == 4;
    final isMenuTab = idx == 5;
    final isRecipeTab = idx == 6;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          // ─── Header ────────────────────────────────────────────────
          _buildHeader(idx, isCategoryTab, isMenuTab, isRecipeTab),
          // ─── Search (for Categories / Menu Items) ──────────────────
          if (isCategoryTab || isMenuTab)
            Container(
              color: Theme.of(context).brightness == Brightness.dark ? Colors.white.withOpacity(0.02) : Theme.of(context).cardColor,
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
              child: TextField(
                controller: _searchController,
                style:
                    TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color, fontSize: 14),
                decoration: InputDecoration(
                  hintText: isCategoryTab
                      ? 'Search categories by name...'
                      : 'Search menu items by name...',
                  hintStyle: TextStyle(
                      color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6), fontSize: 14),
                  prefixIcon: Icon(Icons.search_rounded,
                      color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6)),
                  filled: true,
                  fillColor: Theme.of(context).scaffoldBackgroundColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onChanged: (v) =>
                    setState(() => _searchQuery = v.toLowerCase()),
              ),
            ),
          // ─── Tab Content ───────────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _StockOverviewTab(
                  onGoStockList: () => _tabController.animateTo(1),
                  onGoStocktake: () => _tabController.animateTo(2),
                  onGoWaste: () => _tabController.animateTo(3),
                ),
                const IngredientStockListScreen(),
                const StocktakeScreen(),
                const WasteDashboardScreen(),
                _CategoriesManagementTab(searchQuery: _searchQuery),
                _MenuItemsManagementTab(searchQuery: _searchQuery),
                const RecipesScreen(),
                const TrendingSuggestionsPanel(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
      int idx, bool isCategoryTab, bool isMenuTab, bool isRecipeTab) {
    return Container(
      padding: const EdgeInsets.only(left: 24, right: 24, top: 24, bottom: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor, width: 1),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title row
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Inventory Management',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: Theme.of(context).textTheme.bodyLarge?.color,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Track stock levels, manage waste, and monitor categories.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                // Export button
                if (idx == 0 || idx == 1) ...[
                  _headerButton(
                    icon: Icons.qr_code_scanner,
                    label: 'Quick Stock-In',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const QuickStockInScreen()),
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (idx == 1) ...[
                    _headerButton(
                      icon: Icons.upload_file_rounded,
                      label: 'Bulk Upload',
                      onTap: () => _handleBulkUpload(context),
                    ),
                    const SizedBox(width: 10),
                    _headerButton(
                      icon: Icons.add_rounded,
                      label: 'Add Ingredient',
                      filled: true,
                      onTap: () => _openAddIngredientForm(context),
                    ),
                    const SizedBox(width: 10),
                  ],
                  _headerButton(
                    icon: Icons.download_rounded,
                    label: 'Export',
                    onTap: () => _handleInventoryExport(context),
                  ),
                  const SizedBox(width: 10),
                ],
                // Add button for Categories / Menu Items
                if (isCategoryTab || isMenuTab)
                  _headerButton(
                    icon: Icons.add_rounded,
                    label: isCategoryTab ? 'Add Category' : 'Add Item',
                    filled: true,
                    onTap: () {
                      if (isCategoryTab) {
                        showDialog(
                          context: context,
                          builder: (_) => const CategoryDialog(),
                        );
                      } else {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const DishEditScreenLarge(),
                          ),
                        );
                      }
                    },
                  ),
                // Note: Recipes tab has its own built-in FAB from RecipesScreen
              ],
            ),
            const SizedBox(height: 18),
            // Tab pills (Filter Bar)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: List.generate(_tabLabels.length, (i) {
                    final selected = _tabController.index == i;
                    return Padding(
                      padding: EdgeInsets.only(
                          right: i == _tabLabels.length - 1 ? 0 : 12),
                      child: InkWell(
                        onTap: () => _tabController.animateTo(i),
                        borderRadius: BorderRadius.circular(12),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: selected
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.primary.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selected
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.primary.withOpacity(0.2),
                              width: 1.2,
                            ),
                            boxShadow: selected
                                ? [
                                    BoxShadow(
                                      color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    )
                                  ]
                                : [],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _tabIcons[i],
                                size: 16,
                                color: selected
                                    ? Colors.white
                                    : Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _tabLabels[i],
                                style: GoogleFonts.outfit(
                                  fontSize: 13,
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                  color: selected
                                      ? Colors.white
                                      : Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool filled = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: filled ? Theme.of(context).colorScheme.primary : (Theme.of(context).brightness == Brightness.dark ? Colors.white.withOpacity(0.02) : const Color(0xFFF1F5F9)),
            borderRadius: BorderRadius.circular(10),
            border: filled ? null : Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.2)),
            boxShadow: filled
                ? [
                    BoxShadow(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.25),
                        blurRadius: 12)
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 18,
                  color: filled ? Colors.white : Theme.of(context).colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: filled ? Colors.white : Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STOCK OVERVIEW TAB
// ═══════════════════════════════════════════════════════════════════════════
class _StockOverviewTab extends StatefulWidget {
  final VoidCallback onGoStockList;
  final VoidCallback onGoStocktake;
  final VoidCallback onGoWaste;

  const _StockOverviewTab({
    required this.onGoStockList,
    required this.onGoStocktake,
    required this.onGoWaste,
  });

  @override
  State<_StockOverviewTab> createState() => _StockOverviewTabState();
}

class _StockOverviewTabState extends State<_StockOverviewTab> {
  late final InventoryService _service;
  bool _serviceInitialized = false;
  int _rangeDays = 7;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_serviceInitialized) {
      _serviceInitialized = true;
      _service = Provider.of<InventoryService>(context, listen: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userScope = context.watch<UserScopeService>();
    final branchFilter = context.watch<BranchFilterService>();
    final branchIds = branchFilter.getFilterBranchIds(userScope.branchIds);

    return StreamBuilder<List<IngredientModel>>(
      stream: _service.streamIngredients(branchIds,
          isSuperAdmin: userScope.isSuperAdmin),
      builder: (context, ingSnap) {
        if (branchIds.isEmpty && !userScope.isSuperAdmin) {
          return _buildNoBranchState(
            'Select at least one branch to view inventory insights.',
          );
        }
        if (ingSnap.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
          );
        }
        if (ingSnap.hasError) {
          return Center(
            child: Text(
              'Failed to load inventory data: ${ingSnap.error}',
              style: const TextStyle(color: Colors.red),
            ),
          );
        }
        final items = ingSnap.data ?? [];
        final totalValue = items.fold<double>(
          0,
          (total, i) =>
              total + (i.getStockForBranches(branchIds) * i.costPerUnit),
        );
        final lowCount =
            items.where((i) => i.isLowStockInAnyBranch(branchIds)).length;
        final outCount =
            items.where((i) => i.isOutOfStockInAnyBranch(branchIds)).length;
        final expiringCount =
            items.where((i) => i.isExpiringSoon || i.isExpired).length;

        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: _service.streamRecentMovements(branchIds,
              limit: 500, isSuperAdmin: userScope.isSuperAdmin),
          builder: (context, movSnap) {
            final movements = movSnap.data ?? [];
            final now = DateTime.now();
            final from =
                now.subtract(Duration(days: _rangeDays == 1 ? 1 : _rangeDays));
            final ranged = movements.where((m) {
              final dt = (m['createdAt'] as Timestamp?)?.toDate();
              if (dt == null) return false;
              return !dt.isBefore(from);
            }).toList();
            final received =
                ranged.where((m) => m['movementType'] == 'receiving').length;
            final deducted = ranged.where((m) {
              final t = (m['movementType'] ?? '').toString();
              return t == 'order_deduction' || t == 'waste';
            }).length;
            final adjusted = ranged
                .where((m) => m['movementType'] == 'manual_adjustment')
                .length;

            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                // ─── KPI Stats ─────────────────────────────────
                _kpiGrid(
                  totalItems: items.length,
                  totalValue: totalValue,
                  lowCount: lowCount,
                  outCount: outCount,
                  expiringCount: expiringCount,
                  onTapLow: widget.onGoStockList,
                  onTapOut: widget.onGoStockList,
                  onTapExpiring: widget.onGoStockList,
                ),
                const SizedBox(height: 24),
                // ─── AI Reorder + Stock Movement Side-by-Side ──
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 3,
                        child: _card(
                          title: 'AI Smart Reorder',
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Colors.deepPurple.shade400, Colors.deepPurple.shade700],
                              ),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Icons.auto_awesome, color: Colors.white, size: 12),
                                SizedBox(width: 4),
                                Text('AI Powered', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                          child: const ReorderPredictionsPanel(),
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        flex: 2,
                        child: GestureDetector(
                          onTap: () => _showMovementHistoryDialog(context, ranged),
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: _card(
                              title: 'Stock Movement Summary',
                              trailing: Icon(Icons.open_in_new, size: 14, color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    _rangeChip('Today', 1),
                                    const SizedBox(width: 8),
                                    _rangeChip('7 Days', 7),
                                    const SizedBox(width: 8),
                                    _rangeChip('30 Days', 30),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),
                              // Side-by-side count tiles
                              Row(
                                children: [
                                  Expanded(child: _countTile('Received', received, Colors.green)),
                                  const SizedBox(width: 10),
                                  Expanded(child: _countTile('Deducted', deducted, Colors.red)),
                                  const SizedBox(width: 10),
                                  Expanded(child: _countTile('Adjusted', adjusted, Colors.orange)),
                                ],
                              ),
                              if (movements.isNotEmpty) ...[
                                const SizedBox(height: 18),
                                Divider(color: Theme.of(context).dividerColor, height: 1),
                                const SizedBox(height: 12),
                                Text(
                                  'Recent Activity',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6),
                                    letterSpacing: 0.4,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                ...ranged.take(5).map((m) {
                                  final qty = (m['quantity'] as num?)?.toDouble() ?? 0.0;
                                  final isPositive = qty >= 0;
                                  final name = (m['ingredientName'] ?? '').toString();
                                  final type = (m['movementType'] ?? '').toString().replaceAll('_', ' ');
                                  final dt = (m['createdAt'] as Timestamp?)?.toDate();
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 30,
                                          height: 30,
                                          decoration: BoxDecoration(
                                            color: (isPositive ? Colors.green : Colors.red).withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Icon(
                                            isPositive ? Icons.add_rounded : Icons.remove_rounded,
                                            size: 14,
                                            color: isPositive ? Colors.green.shade600 : Colors.red.shade600,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                name,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: Theme.of(context).textTheme.bodyLarge?.color,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              Text(
                                                type,
                                                style: TextStyle(fontSize: 10, color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6)),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              '${isPositive ? '+' : ''}${qty.toStringAsFixed(1)}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: isPositive ? Colors.green.shade600 : Colors.red.shade600,
                                              ),
                                            ),
                                            if (dt != null)
                                              Text(
                                                dt.toLocal().toString().split(' ').first,
                                                style: TextStyle(fontSize: 10, color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6)),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            ],
                          ),
                        ),
                        ),
                      ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // ─── Quick Actions ─────────────────────────────
                _card(
                  title: 'Quick Actions',
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _actionButton(
                        icon: Icons.delete_sweep_outlined,
                        label: 'Log Waste',
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const WasteEntryScreenLarge())),
                      ),
                      _actionButton(
                        icon: Icons.shopping_cart_outlined,
                        label: 'Purchase Order',
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    const CreatePurchaseOrderScreen())),
                      ),
                      _actionButton(
                        icon: Icons.fact_check_outlined,
                        label: 'Stocktake',
                        onTap: widget.onGoStocktake,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _actionButton(
      {required IconData icon,
      required String label,
      required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6)),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).textTheme.bodyLarge?.color)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNoBranchState(String message) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark ? Colors.white.withOpacity(0.02) : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.account_tree_outlined,
              size: 34,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rangeChip(String label, int days) {
    final selected = _rangeDays == days;
    return GestureDetector(
      onTap: () => setState(() => _rangeDays = days),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.primary.withOpacity(0.15)
              : Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary.withOpacity(0.4)
                : Theme.of(context).dividerColor,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Theme.of(context).colorScheme.primary : Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6),
            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _countTile(String label, int value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Text(
            value.toString(),
            style: TextStyle(
                color: color, fontWeight: FontWeight.bold, fontSize: 20),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6), fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _kpiGrid({
    required int totalItems,
    required double totalValue,
    required int lowCount,
    required int outCount,
    required int expiringCount,
    required VoidCallback onTapLow,
    required VoidCallback onTapOut,
    required VoidCallback onTapExpiring,
  }) {
    final isDesktop = ResponsiveHelper.isDesktop(context);
    return GridView.count(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      crossAxisCount: isDesktop ? 5 : 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: isDesktop ? 1.4 : 1.35,
      children: [
        _kpiCard(
          title: 'Total Items',
          value: totalItems.toString(),
          icon: Icons.category_outlined,
          color: Theme.of(context).colorScheme.primary,
        ),
        _kpiCard(
          title: 'Inventory Value',
          value: 'QAR ${totalValue.toStringAsFixed(0)}',
          icon: Icons.account_balance_wallet_outlined,
          color: Colors.blue,
        ),
        _kpiCard(
          title: 'Out of Stock',
          value: '$outCount',
          icon: Icons.highlight_off_rounded,
          color: Colors.red.shade700,
          isAlert: outCount > 0,
          onTap: onTapOut,
        ),
        _kpiCard(
          title: 'Low Stock',
          value: '$lowCount',
          icon: Icons.warning_amber_rounded,
          color: Colors.orange,
          isAlert: lowCount > 0,
          onTap: onTapLow,
        ),
        _kpiCard(
          title: 'Expiring Soon',
          value: '$expiringCount',
          icon: Icons.event_busy_outlined,
          color: Colors.orange.shade700,
          onTap: onTapExpiring,
        ),
      ],
    );
  }

  Widget _kpiCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    bool isAlert = false,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Theme.of(context).brightness == Brightness.dark ? Colors.white.withOpacity(0.02) : Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color:
                  isAlert ? Colors.red.withOpacity(0.4) : Theme.of(context).dividerColor,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const Spacer(),
              Text(
                title,
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  color: isAlert ? Colors.red : Theme.of(context).textTheme.bodyLarge?.color,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card({
    required String title,
    required Widget child,
    Widget? trailing,
    bool fillContent = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark ? Colors.white.withOpacity(0.02) : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                  letterSpacing: -0.3,
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 16),
          fillContent ? Expanded(child: child) : child,
        ],
      ),
    );
  }

  void _showMovementHistoryDialog(BuildContext context, List<Map<String, dynamic>> movements) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            width: 700,
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark ? Colors.white.withOpacity(0.02) : Theme.of(context).cardColor,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Detailed Stock Movement',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(Icons.close, color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6)),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: movements.isEmpty
                      ? Center(child: Text('No movements to show.', style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6))))
                      : ListView.separated(
                          padding: const EdgeInsets.all(24),
                          itemCount: movements.length,
                          separatorBuilder: (_, __) => Divider(color: Theme.of(context).dividerColor, height: 24),
                          itemBuilder: (context, index) {
                            final m = movements[index];
                            final qty = (m['quantity'] as num?)?.toDouble() ?? 0.0;
                            final isPositive = qty >= 0;
                            final name = (m['ingredientName'] ?? '').toString();
                            final type = (m['movementType'] ?? '').toString().replaceAll('_', ' ');
                            final user = (m['userEmail'] ?? m['userName'] ?? 'System').toString();
                            final dt = (m['createdAt'] as Timestamp?)?.toDate();
                            final notes = (m['notes'] ?? m['reason'] ?? '').toString();
                            final poNumber = m['poNumber']?.toString();

                            final bBefore = (m['balanceBefore'] as num?)?.toDouble();
                            final bAfter = (m['balanceAfter'] as num?)?.toDouble();
                            final warning = (m['warning'] ?? '').toString();
                            final refId = m['referenceId']?.toString();
                            final displayRef = poNumber ?? refId;

                            final branchFilter = context.read<BranchFilterService>();
                            final branchIdsRaw = m['branchIds'] as List<dynamic>? ?? [];
                            final memBranchIds = branchIdsRaw.map((e) => e.toString()).toList();
                            String branchLabel = '';
                            if (memBranchIds.isNotEmpty) {
                              branchLabel = branchFilter.getBranchName(memBranchIds.first);
                              if (memBranchIds.length > 1) {
                                branchLabel += ' (+${memBranchIds.length - 1} more)';
                              }
                            }

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Theme.of(context).scaffoldBackgroundColor,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Theme.of(context).dividerColor),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 42,
                                        height: 42,
                                        decoration: BoxDecoration(
                                          color: (isPositive ? Colors.green : Colors.red).withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Icon(
                                          isPositive ? Icons.add_rounded : Icons.remove_rounded,
                                          size: 20,
                                          color: isPositive ? Colors.green.shade600 : Colors.red.shade600,
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color)),
                                            const SizedBox(height: 6),
                                            Row(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Text(type.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary)),
                                                ),
                                                if (displayRef != null) ...[
                                                  const SizedBox(width: 10),
                                                  Text('REF: $displayRef', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6))),
                                                ],
                                              ],
                                            ),
                                            if ((user.isNotEmpty && user != 'null') || branchLabel.isNotEmpty) ...[
                                              const SizedBox(height: 8),
                                              Row(
                                                children: [
                                                  if (user.isNotEmpty && user != 'null') ...[
                                                    Icon(Icons.person_outline, size: 14, color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6)),
                                                    const SizedBox(width: 4),
                                                    Text(user, style: TextStyle(fontSize: 12, color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6))),
                                                  ],
                                                  if (branchLabel.isNotEmpty) ...[
                                                    if (user.isNotEmpty && user != 'null')
                                                      const SizedBox(width: 12),
                                                    Icon(Icons.storefront_rounded, size: 14, color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6)),
                                                    const SizedBox(width: 4),
                                                    Flexible(child: Text(branchLabel, style: TextStyle(fontSize: 12, color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6)), overflow: TextOverflow.ellipsis)),
                                                  ]
                                                ],
                                              )
                                            ]
                                          ],
                                        ),
                                      ),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            '${isPositive ? '+' : ''}${qty.toStringAsFixed(2)}',
                                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: isPositive ? Colors.green.shade600 : Colors.red.shade600),
                                          ),
                                          if (dt != null) ...[
                                            const SizedBox(height: 6),
                                            Text(dt.toLocal().toString().split(' ').first, style: TextStyle(fontSize: 11, color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6))),
                                            Text(dt.toLocal().toString().split(' ')[1].substring(0, 5), style: TextStyle(fontSize: 11, color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6))),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                  if ((bBefore != null && bAfter != null) || notes.isNotEmpty || warning.isNotEmpty) ...[
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      child: Divider(height: 1, color: Theme.of(context).dividerColor),
                                    ),
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (bBefore != null && bAfter != null)
                                          Expanded(
                                            flex: 1,
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text('Balance Shift', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6))),
                                                const SizedBox(height: 6),
                                                Row(
                                                  children: [
                                                    Text(bBefore.toStringAsFixed(2), style: TextStyle(fontSize: 13, color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6), fontWeight: FontWeight.w600)),
                                                    Padding(
                                                      padding: EdgeInsets.symmetric(horizontal: 6),
                                                      child: Icon(Icons.arrow_forward_rounded, size: 14, color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6)),
                                                    ),
                                                    Text(bAfter.toStringAsFixed(2), style: TextStyle(fontSize: 14, color: Theme.of(context).textTheme.bodyLarge?.color, fontWeight: FontWeight.w900)),
                                                  ],
                                                ),
                                              ]
                                            ),
                                          ),
                                        if (notes.isNotEmpty || warning.isNotEmpty)
                                          Expanded(
                                            flex: 2,
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                if (notes.isNotEmpty) ...[
                                                  Text('Notes', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6))),
                                                  const SizedBox(height: 4),
                                                  Text(notes, style: TextStyle(fontSize: 12, color: Theme.of(context).textTheme.bodyLarge?.color)),
                                                ],
                                                if (warning.isNotEmpty) ...[
                                                  if (notes.isNotEmpty) const SizedBox(height: 10),
                                                  Row(
                                                    children: [
                                                      Icon(Icons.warning_amber_rounded, size: 14, color: Colors.orange.shade700),
                                                      const SizedBox(width: 4),
                                                      Flexible(child: Text(warning, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.orange.shade700))),
                                                    ]
                                                  )
                                                ]
                                              ]
                                            )
                                          )
                                      ]
                                    )
                                  ]
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CATEGORIES TAB
// ═══════════════════════════════════════════════════════════════════════════
class _CategoriesManagementTab extends StatefulWidget {
  final String searchQuery;
  const _CategoriesManagementTab({required this.searchQuery});

  @override
  State<_CategoriesManagementTab> createState() =>
      _CategoriesManagementTabState();
}

class _CategoriesManagementTabState extends State<_CategoriesManagementTab> {
  @override
  Widget build(BuildContext context) {
    final userScope = context.watch<UserScopeService>();
    final db = FirebaseFirestore.instance;

    final branchFilter = context.watch<BranchFilterService>();
    final filterBranchIds =
        branchFilter.getFilterBranchIds(userScope.branchIds);
    Query<Map<String, dynamic>> query;

    if (filterBranchIds.isNotEmpty) {
      if (filterBranchIds.length == 1) {
        query = db
            .collection('menu_categories')
            .where('branchIds', arrayContains: filterBranchIds.first)
            .orderBy('sortOrder');
      } else {
        query = db
            .collection('menu_categories')
            .where('branchIds', arrayContainsAny: filterBranchIds)
            .orderBy('sortOrder');
      }
    } else {
      query = db.collection('menu_categories').orderBy('sortOrder');
    }

    return StreamBuilder<QuerySnapshot>(
      stream: db.collection('menu_categories').snapshots(),
      builder: (context, catSnap) {
        final catMap = <String, String>{};
        if (catSnap.hasData) {
          for (var doc in catSnap.data!.docs) {
            catMap[doc.id] =
                (doc.data() as Map<String, dynamic>)['name'] ?? 'Unnamed';
          }
        }
        return StreamBuilder<QuerySnapshot>(
          stream: query.snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(
                child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
              );
            }
            if (snapshot.hasError) {
              return Center(
                child: Text(
                  'Unable to load categories: ${snapshot.error}',
                  style: const TextStyle(color: Colors.red),
                ),
              );
            }
            final docs = snapshot.data?.docs ?? [];
            final filtered = docs.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final name = (data['name'] ?? '').toString().toLowerCase();
              final nameAr = (data['name_ar'] ?? '').toString().toLowerCase();
              return name.contains(widget.searchQuery) ||
                  nameAr.contains(widget.searchQuery);
            }).toList();

            if (filtered.isEmpty) {
              return Center(
                child: Text(
                  widget.searchQuery.isNotEmpty
                      ? 'No categories match your search.'
                      : 'No categories found.',
                  style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6)),
                ),
              );
            }

            // ─── Table layout ─────────────────────────────────────────
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark ? Colors.white.withOpacity(0.02) : Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: Column(
                  children: [
                    // Header row
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark ? Colors.white.withOpacity(0.05) : Theme.of(context).cardColor,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(12)),
                      ),
                      child: Row(children: [
                        SizedBox(width: 52), // image col
                        Expanded(
                            flex: 3,
                            child: Text('CATEGORY NAME',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6),
                                    letterSpacing: 0.8))),
                        Expanded(
                            flex: 1,
                            child: Text('SORT',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6),
                                    letterSpacing: 0.8))),
                        Expanded(
                            flex: 1,
                            child: Text('BRANCHES',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6),
                                    letterSpacing: 0.8))),
                        Expanded(
                            flex: 1,
                            child: Text('STATUS',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6),
                                    letterSpacing: 0.8))),
                        SizedBox(
                            width: 100,
                            child: Text('ACTIONS',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6),
                                    letterSpacing: 0.8))),
                      ]),
                    ),
                    // Data rows
                    ...filtered.map((category) {
                      final data = category.data() as Map<String, dynamic>;
                      final isActive = data['isActive'] ?? false;
                      final imageUrl = data['imageUrl'] as String? ?? '';
                      final name = data['name'] ?? 'Unnamed';
                      final nameAr = data['name_ar'] as String? ?? '';
                      final sortOrder = data['sortOrder'] ?? 0;
                      final branchIds =
                          List<String>.from(data['branchIds'] ?? []);

                      return Container(
                        decoration: BoxDecoration(
                          border: Border(
                              top: BorderSide(
                                  color: Theme.of(context).dividerColor, width: 0.5)),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => showDialog(
                                context: context,
                                builder: (_) => CategoryDialog(doc: category)),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 14),
                              child: Row(children: [
                                // Image
                                Container(
                                  width: 40,
                                  height: 40,
                                  margin: const EdgeInsets.only(right: 12),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    color: Colors.deepPurple.withOpacity(0.08),
                                  ),
                                  child: imageUrl.isNotEmpty
                                      ? ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          child: Image.network(imageUrl,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) =>
                                                  const Icon(
                                                      Icons.category_rounded,
                                                      color: Colors.deepPurple,
                                                      size: 20)),
                                        )
                                      : const Icon(Icons.category_rounded,
                                          color: Colors.deepPurple, size: 20),
                                ),
                                // Name
                                Expanded(
                                    flex: 3,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(name,
                                            style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 14,
                                                color: Theme.of(context).textTheme.bodyLarge?.color),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis),
                                        if (nameAr.isNotEmpty)
                                          Text(nameAr,
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6)),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              textDirection: TextDirection.rtl),
                                      ],
                                    )),
                                // Sort Order
                                Expanded(
                                    flex: 1,
                                    child: Text('$sortOrder',
                                        style: TextStyle(
                                            fontSize: 13,
                                            color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6)))),
                                // Branches
                                Expanded(
                                    flex: 1,
                                    child: Text('${branchIds.length}',
                                        style: TextStyle(
                                            fontSize: 13,
                                            color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6)))),
                                // Status
                                Expanded(
                                    flex: 1,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isActive
                                            ? Colors.green.withOpacity(0.08)
                                            : Colors.red.withOpacity(0.08),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                                width: 6,
                                                height: 6,
                                                decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    color: isActive
                                                        ? Colors.green
                                                        : Colors.red)),
                                            const SizedBox(width: 6),
                                            Text(
                                                isActive
                                                    ? 'Active'
                                                    : 'Inactive',
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w500,
                                                    color: isActive
                                                        ? Colors.green.shade700
                                                        : Colors.red.shade700)),
                                          ]),
                                    )),
                                // Actions
                                SizedBox(
                                    width: 100,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.edit_outlined,
                                              size: 18),
                                          color: Colors.deepPurple,
                                          onPressed: () => showDialog(
                                              context: context,
                                              builder: (_) => CategoryDialog(
                                                  doc: category)),
                                          tooltip: 'Edit',
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                              minWidth: 36, minHeight: 36),
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                              Icons.delete_outline_rounded,
                                              size: 18),
                                          color: Colors.red.shade400,
                                          onPressed: () => _deleteDoc(
                                              context, category, 'Category'),
                                          tooltip: 'Delete',
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                              minWidth: 36, minHeight: 36),
                                        ),
                                      ],
                                    )),
                              ]),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MENU ITEMS TAB
// ═══════════════════════════════════════════════════════════════════════════
class _MenuItemsManagementTab extends StatefulWidget {
  final String searchQuery;
  const _MenuItemsManagementTab({required this.searchQuery});

  @override
  State<_MenuItemsManagementTab> createState() =>
      _MenuItemsManagementTabState();
}

class _MenuItemsManagementTabState extends State<_MenuItemsManagementTab> {
  @override
  Widget build(BuildContext context) {
    final userScope = context.watch<UserScopeService>();
    final db = FirebaseFirestore.instance;

    final branchFilter = context.watch<BranchFilterService>();
    final filterBranchIds =
        branchFilter.getFilterBranchIds(userScope.branchIds);
    Query<Map<String, dynamic>> query;

    if (filterBranchIds.isNotEmpty) {
      if (filterBranchIds.length == 1) {
        query = db
            .collection('menu_items')
            .where('branchIds', arrayContains: filterBranchIds.first)
            .orderBy('sortOrder');
      } else {
        query = db
            .collection('menu_items')
            .where('branchIds', arrayContainsAny: filterBranchIds)
            .orderBy('sortOrder');
      }
    } else {
      query = db.collection('menu_items').orderBy('sortOrder');
    }

    return StreamBuilder<QuerySnapshot>(
      stream: db.collection('menu_categories').snapshots(),
      builder: (context, catSnap) {
        final catMap = <String, String>{};
        if (catSnap.hasData) {
          for (var doc in catSnap.data!.docs) {
            catMap[doc.id] =
                (doc.data() as Map<String, dynamic>)['name'] ?? 'Unnamed';
          }
        }
        return StreamBuilder<QuerySnapshot>(
          stream: query.snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(
                child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
              );
            }
            if (snapshot.hasError) {
              return Center(
                child: Text(
                  'Unable to load menu items: ${snapshot.error}',
                  style: const TextStyle(color: Colors.red),
                ),
              );
            }
            final docs = snapshot.data?.docs ?? [];
            final filtered = docs.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final name = (data['name'] ?? '').toString().toLowerCase();
              final nameAr = (data['name_ar'] ?? '').toString().toLowerCase();
              return name.contains(widget.searchQuery) ||
                  nameAr.contains(widget.searchQuery);
            }).toList();

            if (filtered.isEmpty) {
              return Center(
                child: Text(
                  widget.searchQuery.isNotEmpty
                      ? 'No menu items match your search.'
                      : 'No menu items found.',
                  style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6)),
                ),
              );
            }

            // ─── Table layout ─────────────────────────────────────────
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark ? Colors.white.withOpacity(0.02) : Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: Column(
                  children: [
                    // Header row
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark ? Colors.white.withOpacity(0.05) : Theme.of(context).cardColor,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(12)),
                      ),
                      child: Row(children: [
                        SizedBox(width: 52), // image col
                        Expanded(
                            flex: 3,
                            child: Text('ITEM NAME',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6),
                                    letterSpacing: 0.8))),
                        Expanded(
                            flex: 2,
                            child: Text('CATEGORY',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6),
                                    letterSpacing: 0.8))),
                        Expanded(
                            flex: 1,
                            child: Text('PRICE',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6),
                                    letterSpacing: 0.8))),
                        Expanded(
                            flex: 1,
                            child: Text('STATUS',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6),
                                    letterSpacing: 0.8))),
                        SizedBox(
                            width: 100,
                            child: Text('ACTIONS',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6),
                                    letterSpacing: 0.8))),
                      ]),
                    ),
                    // Data rows
                    ...filtered.map((item) {
                      final data = item.data() as Map<String, dynamic>;
                      final isActive = data['isAvailable'] ?? false;
                      final imageUrl = data['imageUrl'] as String? ?? '';
                      final name = data['name'] ?? 'Unnamed';
                      final nameAr = data['name_ar'] as String? ?? '';
                      final categoryName =
                          catMap[data['categoryId']] ?? 'Uncategorized';
                      final price = (data['price'] ?? 0).toDouble();
                      final discountedPrice =
                          (data['discountedPrice'] ?? 0).toDouble();
                      final hasDiscount =
                          discountedPrice > 0 && discountedPrice < price;
                      final isPopular = data['isPopular'] ?? false;

                      return Container(
                        decoration: BoxDecoration(
                          border: Border(
                              top: BorderSide(
                                  color: Theme.of(context).dividerColor, width: 0.5)),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => DishEditScreenLarge(doc: item),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 14),
                              child: Row(children: [
                                // Image
                                Container(
                                  width: 40,
                                  height: 40,
                                  margin: const EdgeInsets.only(right: 12),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    color: Colors.amber.withOpacity(0.08),
                                  ),
                                  child: imageUrl.isNotEmpty
                                      ? ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          child: Image.network(imageUrl,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) =>
                                                  Icon(Icons.fastfood_rounded,
                                                      color:
                                                          Colors.amber.shade600,
                                                      size: 20)),
                                        )
                                      : Icon(Icons.fastfood_rounded,
                                          color: Colors.amber.shade600,
                                          size: 20),
                                ),
                                // Name
                                Expanded(
                                    flex: 3,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(children: [
                                          Flexible(
                                              child: Text(name,
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize: 14,
                                                      color: Theme.of(context).textTheme.bodyLarge?.color),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis)),
                                          if (isPopular) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2),
                                              decoration: BoxDecoration(
                                                  color: Colors.amber
                                                      .withOpacity(0.12),
                                                  borderRadius:
                                                      BorderRadius.circular(8)),
                                              child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.star_rounded,
                                                        size: 12,
                                                        color: Colors
                                                            .amber.shade700),
                                                    const SizedBox(width: 2),
                                                    Text('Popular',
                                                        style: TextStyle(
                                                            fontSize: 10,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            color: Colors.amber
                                                                .shade700)),
                                                  ]),
                                            ),
                                          ],
                                        ]),
                                        if (nameAr.isNotEmpty)
                                          Text(nameAr,
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6)),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              textDirection: TextDirection.rtl),
                                      ],
                                    )),
                                // Category
                                Expanded(
                                  flex: 2,
                                  child: categoryName.isNotEmpty
                                      ? Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.deepPurple
                                                .withOpacity(0.08),
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: Text(categoryName,
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w500,
                                                  color: Colors.deepPurple),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis),
                                        )
                                      : Text('—',
                                          style: TextStyle(
                                              color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6))),
                                ),
                                // Price
                                Expanded(
                                    flex: 1,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'QAR ${(hasDiscount ? discountedPrice : price).toStringAsFixed(2)}',
                                          style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: hasDiscount
                                                  ? Colors.green.shade700
                                                  : Theme.of(context).textTheme.bodyLarge?.color),
                                        ),
                                        if (hasDiscount)
                                          Text(
                                              'QAR ${price.toStringAsFixed(2)}',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6),
                                                  decoration: TextDecoration
                                                      .lineThrough)),
                                      ],
                                    )),
                                // Status
                                Expanded(
                                    flex: 1,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isActive
                                            ? Colors.green.withOpacity(0.08)
                                            : Colors.red.withOpacity(0.08),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                                width: 6,
                                                height: 6,
                                                decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    color: isActive
                                                        ? Colors.green
                                                        : Colors.red)),
                                            const SizedBox(width: 6),
                                            Text(
                                                isActive
                                                    ? 'Active'
                                                    : 'Inactive',
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w500,
                                                    color: isActive
                                                        ? Colors.green.shade700
                                                        : Colors.red.shade700)),
                                          ]),
                                    )),
                                // Actions
                                SizedBox(
                                    width: 100,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.edit_outlined,
                                              size: 18),
                                          color: Colors.deepPurple,
                                          onPressed: () => Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  DishEditScreenLarge(
                                                      doc: item),
                                            ),
                                          ),
                                          tooltip: 'Edit',
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                              minWidth: 36, minHeight: 36),
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                              Icons.delete_outline_rounded,
                                              size: 18),
                                          color: Colors.red.shade400,
                                          onPressed: () => _deleteDoc(
                                              context, item, 'Menu item'),
                                          tooltip: 'Delete',
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                              minWidth: 36, minHeight: 36),
                                        ),
                                      ],
                                    )),
                              ]),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SHARED HELPERS
// ═══════════════════════════════════════════════════════════════════════════
Future<void> _deleteDoc(
  BuildContext context,
  QueryDocumentSnapshot doc,
  String itemType,
) async {
  final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Delete $itemType?'),
          content: Text('This will permanently delete this $itemType.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        ),
      ) ??
      false;

  if (!confirm) return;
  try {
    await doc.reference.delete();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$itemType deleted successfully.'),
          backgroundColor: Colors.green,
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Delete failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
