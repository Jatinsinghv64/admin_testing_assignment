import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../../Models/IngredientModel.dart';
import '../../Widgets/BranchFilterService.dart';
import '../../main.dart';
import '../../services/inventory/InventoryService.dart';
import '../../services/CsvExportService.dart';

class _StockColors {
  static const Color primary = Color(0xFF673AB7); // Deep Purple
  static const Color backgroundLight = Color(0xFFF8FAFC);
  static const Color surfaceLight = Color(0xFFF1F5F9);
  static const Color textMain = Color(0xFF0F172A);
  static const Color textMuted = Color(0xFF64748B);
  static const Color border = Color(0x1A673AB7); // primary with 10% opacity
}

class StocktakeScreen extends StatefulWidget {
  const StocktakeScreen({super.key});

  @override
  State<StocktakeScreen> createState() => _StocktakeScreenState();
}

class _StocktakeScreenState extends State<StocktakeScreen> {
  late final InventoryService _service;
  bool _serviceInitialized = false;

  final Map<String, TextEditingController> _actualControllers = {};
  final Map<String, String> _reasons = {};
  final Map<String, TextEditingController> _noteControllers = {};

  String _searchQuery = '';
  String _selectedCategory = 'All';
  bool _isSavingDraft = false;
  bool _isConfirming = false;
  DateTime _lastSync = DateTime.now();
  String? _lastLoadedDraftKey;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_serviceInitialized) {
      _serviceInitialized = true;
      _service = Provider.of<InventoryService>(context, listen: false);
    }
  }

  @override
  void dispose() {
    for (final c in _actualControllers.values) c.dispose();
    for (final c in _noteControllers.values) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userScope = context.watch<UserScopeService>();
    final branchFilter = context.watch<BranchFilterService>();
    final branchIds = branchFilter.selectedBranchId != null
        ? [branchFilter.selectedBranchId!]
        : userScope.branchIds.take(1).toList();
    final draftKey = _draftKey(branchIds);

    if (branchIds.isEmpty) {
      return _buildNoBranchState();
    }

    return Container(
      color: _StockColors.backgroundLight,
      child: Column(
        children: [
          _buildHeaderAndControls(branchFilter, userScope),
          Expanded(
            child: StreamBuilder<List<IngredientModel>>(
              stream: _service.streamIngredients(branchIds,
                  isSuperAdmin: userScope.isSuperAdmin),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(
                          color: _StockColors.primary));
                }
                if (snapshot.hasError) {
                  return Center(
                      child: Text('Error: ${snapshot.error}',
                          style: const TextStyle(color: Colors.red)));
                }

                final allItems = snapshot.data ?? [];

                return Column(
                  children: [
                    Expanded(
                      child: allItems.isEmpty
                          ? const Center(
                              child:
                                  Text('No active ingredients for stocktake.'))
                          : _buildMainContent(allItems, draftKey, branchIds),
                    ),
                    _buildActionBar(allItems, userScope, draftKey, branchIds),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent(
      List<IngredientModel> allItems, String draftKey, List<String> branchIds) {
    _ensureState(allItems, branchIds);
    _loadDraftOnce(draftKey);

    final filteredItems = allItems.where((item) {
      final matchesSearch =
          item.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              (item.sku?.toLowerCase().contains(_searchQuery.toLowerCase()) ??
                  false);
      final matchesCategory = _selectedCategory == 'All' ||
          IngredientModel.categoryLabel(item.category) == _selectedCategory;
      return matchesSearch && matchesCategory;
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          _buildItemsTable(filteredItems, branchIds),
          const SizedBox(height: 24),
          _buildSummaryArea(allItems, branchIds),
        ],
      ),
    );
  }

  Widget _buildHeaderAndControls(
      BranchFilterService branchFilter, UserScopeService userScope) {
    return Container(
      padding: const EdgeInsets.fromLTRB(32, 16, 32, 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _StockColors.border)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text('Physical Stocktake',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 16),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: _StockColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text('Active Session',
                        style: TextStyle(
                            color: _StockColors.primary,
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              Row(
                children: [
                  SizedBox(
                    width: 256,
                    height: 40,
                    child: TextField(
                      onChanged: (v) => setState(() => _searchQuery = v),
                      decoration: InputDecoration(
                        hintText: 'Search ingredients...',
                        hintStyle: const TextStyle(
                            fontSize: 13, color: _StockColors.textMuted),
                        prefixIcon: const Icon(Icons.search,
                            size: 18, color: _StockColors.textMuted),
                        filled: true,
                        fillColor: _StockColors.surfaceLight,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  _iconButton(Icons.notifications_none, hasBadge: true),
                  const SizedBox(width: 8),
                  _iconButton(Icons.settings),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('BRANCH',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: _StockColors.textMuted,
                              letterSpacing: 1)),
                      const SizedBox(height: 4),
                      Container(
                        width: 192,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                            color: _StockColors.surfaceLight,
                            borderRadius: BorderRadius.circular(8)),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: branchFilter.selectedBranchId ??
                                userScope.branchIds.firstOrNull,
                            items: userScope.branchIds
                                .map((id) => DropdownMenuItem(
                                    value: id,
                                    child: Text(id.replaceAll('_', ' '),
                                        style: const TextStyle(fontSize: 13))))
                                .toList(),
                            onChanged: (v) {
                              if (v != null) branchFilter.selectBranch(v);
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 32),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('CATEGORY',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: _StockColors.textMuted,
                              letterSpacing: 1)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          'All',
                          'Meat',
                          'Vegetables',
                          'Grains',
                          'Dairy'
                        ]
                            .map((cat) => Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: InkWell(
                                    onTap: () =>
                                        setState(() => _selectedCategory = cat),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: _selectedCategory == cat
                                            ? _StockColors.primary
                                            : _StockColors.surfaceLight,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(cat,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: _selectedCategory == cat
                                                ? Colors.white
                                                : _StockColors.textMain,
                                          )),
                                    ),
                                  ),
                                ))
                            .toList(),
                      ),
                    ],
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Last sync',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: _StockColors.textMuted)),
                  Text(DateFormat('MMM d, yyyy - h:mm a').format(_lastSync),
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNoBranchState() {
    return Container(
      color: _StockColors.backgroundLight,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _StockColors.border),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.account_tree_outlined,
              size: 34,
              color: _StockColors.primary,
            ),
            SizedBox(height: 14),
            Text(
              'Assign or select a branch before starting stocktake.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _StockColors.textMain,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemsTable(List<IngredientModel> items, List<String> branchIds) {
    return Container(
      margin: const EdgeInsets.only(top: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _StockColors.border),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Table(
          columnWidths: const {
            0: FlexColumnWidth(2.5),
            1: FlexColumnWidth(0.8),
            2: FlexColumnWidth(1),
            3: FlexColumnWidth(1),
            4: FlexColumnWidth(0.8),
            5: FlexColumnWidth(2),
          },
          children: [
            // Header Row
            TableRow(
              decoration:
                  BoxDecoration(color: _StockColors.primary.withOpacity(0.05)),
              children: [
                _th('Ingredient Name / SKU'),
                _th('Unit'),
                _th('System Stock'),
                _th('Actual Count'),
                _th('Variance'),
                _th('Reason / Notes'),
              ],
            ),
            // Data Rows
            ...items.map((item) {
              final controller = _actualControllers[item.id]!;
              final actual = double.tryParse(controller.text.trim()) ?? 0.0;
              final diff = actual - item.getStock(branchIds.first);

              return TableRow(
                decoration: const BoxDecoration(
                  border:
                      Border(bottom: BorderSide(color: _StockColors.border)),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.name,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.bold)),
                        Text(item.sku ?? '-',
                            style: const TextStyle(
                                fontSize: 10, color: _StockColors.textMuted)),
                      ],
                    ),
                  ),
                  _td(item.unit),
                  _td(item.getStock(branchIds.first).toStringAsFixed(2),
                      isMono: true),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Center(
                      child: SizedBox(
                        width: 96,
                        height: 36,
                        child: TextField(
                          controller: controller,
                          onChanged: (_) => setState(() {}),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.bold),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: _StockColors.backgroundLight,
                            contentPadding: EdgeInsets.zero,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    const BorderSide(color: Color(0x3317CF54))),
                            focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                    color: _StockColors.primary, width: 2)),
                          ),
                        ),
                      ),
                    ),
                  ),
                  TableCell(
                    verticalAlignment: TableCellVerticalAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 24),
                      child: Text(
                        (diff == 0
                            ? '0.00'
                            : '${diff > 0 ? '+' : ''}${diff.toStringAsFixed(2)}'),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: diff == 0
                              ? _StockColors.primary
                              : (diff < 0 ? Colors.red : _StockColors.primary),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              isExpanded: true,
                              value: _reasons[item.id] == 'Select reason...'
                                  ? null
                                  : _reasons[item.id],
                              hint: const Text('Select reason...',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontStyle: FontStyle.italic)),
                              style: const TextStyle(
                                  fontSize: 12, color: _StockColors.textMain),
                              items: [
                                'Waste / Spoilage',
                                'Unrecorded sale',
                                'Theft',
                                'Inventory Adjustment',
                                'Incorrect Delivery'
                              ]
                                  .map((r) => DropdownMenuItem(
                                      value: r, child: Text(r)))
                                  .toList(),
                              onChanged: (v) => setState(() =>
                                  _reasons[item.id] = v ?? 'Select reason...'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _noteControllers[item.id],
                            style: const TextStyle(
                                fontSize: 11, fontStyle: FontStyle.italic),
                            decoration: const InputDecoration(
                              hintText: 'Add note...',
                              hintStyle: TextStyle(
                                  fontSize: 11, color: _StockColors.textMuted),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryArea(
      List<IngredientModel> allItems, List<String> branchIds) {
    double totalVarianceValue = 0;
    int itemsWithVariance = 0;
    int completedCount = 0;

    for (final item in allItems) {
      final actualStr = _actualControllers[item.id]?.text ?? '';
      if (actualStr.isNotEmpty) completedCount++;

      final actual =
          double.tryParse(actualStr) ?? item.getStock(branchIds.first);
      final diff = actual - item.getStock(branchIds.first);
      if (diff.abs() > 0.001) {
        itemsWithVariance++;
        totalVarianceValue += diff * item.costPerUnit;
      }
    }

    final progress = allItems.isEmpty ? 0.0 : completedCount / allItems.length;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: _summaryCard(
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: _StockColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(999)),
                  child: const Icon(Icons.info_outline,
                      color: _StockColors.primary),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Discrepancy Policy',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.bold)),
                      SizedBox(height: 4),
                      Text(
                        'Any variance exceeding 5% of system stock or QAR 50 in value requires manager approval and a secondary recount. Please ensure all waste logs from the previous shift have been entered before submitting.',
                        style: TextStyle(
                            fontSize: 11,
                            color: _StockColors.textMuted,
                            height: 1.4),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 24),
        Expanded(
          child: _summaryCard(
            Column(
              children: [
                _summaryRow('Total Variance Value',
                    'QAR ${totalVarianceValue.toStringAsFixed(2)}',
                    color: totalVarianceValue < 0
                        ? Colors.red
                        : (totalVarianceValue > 0
                            ? _StockColors.primary
                            : _StockColors.textMain),
                    isBold: true),
                const SizedBox(height: 12),
                _summaryRow('Items with Variance', '$itemsWithVariance Items'),
                const SizedBox(height: 12),
                _summaryRow('Total Recount Progress',
                    '${(progress * 100).toInt()}% Complete'),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: _StockColors.surfaceLight,
                    valueColor:
                        const AlwaysStoppedAnimation(_StockColors.primary),
                    minHeight: 6,
                  ),
                ),
              ],
            ),
            padding: const EdgeInsets.all(24),
            borderColor: _StockColors.primary.withOpacity(0.2),
            bgColor: _StockColors.primary.withOpacity(0.05),
          ),
        ),
      ],
    );
  }

  Widget _buildActionBar(List<IngredientModel> allItems,
      UserScopeService userScope, String draftKey, List<String> branchIds) {
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _StockColors.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              _actionBtn('Print Sheet', Icons.print, onTap: () {}),
              const SizedBox(width: 16),
              _actionBtn('Export CSV', Icons.cloud_download, onTap: () {
                if (branchIds.isEmpty || allItems.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('No stocktake data available to export.'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }
                CsvExportService.exportInventoryStockFromData(
                  context,
                  allItems,
                  branchId: branchIds.first,
                );
              }),
            ],
          ),
          Row(
            children: [
              OutlinedButton(
                onPressed:
                    _isSavingDraft ? null : () => _saveDraft(context, draftKey),
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  side: const BorderSide(color: Color(0x3317CF54)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: _isSavingDraft
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: _StockColors.primary))
                    : const Text('Save Progress',
                        style: TextStyle(
                            color: _StockColors.primary,
                            fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 16),
              ElevatedButton(
                onPressed: _isConfirming || allItems.isEmpty
                    ? null
                    : () => _confirmStocktake(
                        context: context,
                        items: allItems,
                        userScope: userScope,
                        draftKey: draftKey,
                        branchIds: branchIds),
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  backgroundColor: _StockColors.primary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: _isConfirming
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Submit Stocktake',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _th(String text) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: _StockColors.textMuted,
                letterSpacing: 1)),
      );

  Widget _td(String text, {bool isMono = false}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Text(text,
            style: TextStyle(
                fontSize: 13,
                fontWeight: isMono ? FontWeight.bold : FontWeight.normal,
                fontFamily: isMono ? 'monospace' : null)),
      );

  Widget _iconButton(IconData icon, {bool hasBadge = false}) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
      child: Stack(
        children: [
          Icon(icon, color: _StockColors.textMuted, size: 22),
          if (hasBadge)
            Positioned(
                top: 2,
                right: 2,
                child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                        color: _StockColors.primary, shape: BoxShape.circle))),
        ],
      ),
    );
  }

  Widget _actionBtn(String label, IconData icon,
      {required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        decoration: BoxDecoration(
            color: _StockColors.surfaceLight,
            borderRadius: BorderRadius.circular(8)),
        child: Row(
          children: [
            Icon(icon, size: 18, color: _StockColors.textMain),
            const SizedBox(width: 8),
            Text(label,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: _StockColors.textMain)),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard(Widget child,
      {EdgeInsets? padding, Color? borderColor, Color? bgColor}) {
    return Container(
      padding: padding ?? const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: bgColor ?? _StockColors.surfaceLight.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor ?? _StockColors.border),
      ),
      child: child,
    );
  }

  Widget _summaryRow(String label, String value,
      {Color? color, bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: _StockColors.textMuted,
                letterSpacing: 0.5)),
        Text(value,
            style: TextStyle(
                fontSize: isBold ? 18 : 13,
                fontWeight: isBold ? FontWeight.w900 : FontWeight.bold,
                color: color ?? _StockColors.textMain)),
      ],
    );
  }

  void _ensureState(List<IngredientModel> items, List<String> branchIds) {
    for (final i in items) {
      _actualControllers.putIfAbsent(
          i.id,
          () => TextEditingController(
              text: i.getStock(branchIds.first).toStringAsFixed(2)));
      _reasons.putIfAbsent(i.id, () => 'Select reason...');
      _noteControllers.putIfAbsent(i.id, () => TextEditingController());
    }
  }

  String _draftKey(List<String> branchIds) =>
      'stocktake_draft_v2_${branchIds.join("_")}';

  Future<void> _loadDraftOnce(String key) async {
    if (_lastLoadedDraftKey == key) return;
    _lastLoadedDraftKey = key;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final counts = map['counts'] as Map<String, dynamic>;
      final reasons = map['reasons'] as Map<String, dynamic>? ?? {};
      final notes = map['notes'] as Map<String, dynamic>? ?? {};

      setState(() {
        counts.forEach((k, v) =>
            _actualControllers[k]?.text = (v as num).toStringAsFixed(2));
        reasons.forEach((k, v) => _reasons[k] = v.toString());
        notes.forEach((k, v) => _noteControllers[k]?.text = v.toString());
      });
    } catch (_) {}
  }

  Future<void> _saveDraft(BuildContext context, String key) async {
    setState(() => _isSavingDraft = true);
    try {
      final counts = <String, double>{};
      final reasons = <String, String>{};
      final notes = <String, String>{};

      for (final id in _actualControllers.keys) {
        counts[id] =
            double.tryParse(_actualControllers[id]!.text.trim()) ?? 0.0;
        reasons[id] = _reasons[id] ?? '';
        notes[id] = _noteControllers[id]!.text.trim();
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key,
          jsonEncode({'counts': counts, 'reasons': reasons, 'notes': notes}));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Progress saved'),
            backgroundColor: _StockColors.primary));
      }
    } finally {
      if (mounted) setState(() => _isSavingDraft = false);
    }
  }

  Future<void> _confirmStocktake({
    required BuildContext context,
    required List<IngredientModel> items,
    required UserScopeService userScope,
    required String draftKey,
    required List<String> branchIds,
  }) async {
    final actualCounts = <IngredientModel, double>{};
    final reasonsMap = <String, String>{};
    final notesMap = <String, String>{};
    int matched = 0;
    int mismatched = 0;

    for (final i in items) {
      final actual = double.tryParse(_actualControllers[i.id]!.text.trim()) ??
          i.getStock(branchIds.first);
      actualCounts[i] = actual;
      reasonsMap[i.id] = _reasons[i.id] ?? '';
      notesMap[i.id] = _noteControllers[i.id]!.text.trim();

      if ((actual - i.getStock(branchIds.first)).abs() < 0.001)
        matched++;
      else
        mismatched++;
    }

    final proceed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Submit Stocktake'),
            content: Text(
                '$matched items matched.\n$mismatched items have discrepancies.\n\nProceed with updates?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: _StockColors.primary),
                  child: const Text('Confirm')),
            ],
          ),
        ) ??
        false;

    if (!proceed) return;
    setState(() => _isConfirming = true);
    try {
      final updatedCount = await _service.applyStocktake(
        branchIds: branchIds,
        recordedBy: userScope.userIdentifier,
        actualCounts: actualCounts,
        reasons: reasonsMap,
        notes: notesMap,
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(draftKey);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Stocktake completed. $updatedCount items adjusted.'),
            backgroundColor: _StockColors.primary));
      }
    } catch (e) {
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isConfirming = false);
    }
  }
}
