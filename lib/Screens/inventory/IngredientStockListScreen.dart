import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rxdart/rxdart.dart';
import '../../Models/IngredientModel.dart';
import '../../Models/RecipeModel.dart';
import '../../Widgets/BranchFilterService.dart';
import '../../Widgets/IngredientFormSheet.dart';
import '../../main.dart';
import '../../services/inventory/ExcelImportService.dart';
import '../../services/ingredients/IngredientService.dart';
import '../../services/inventory/InventoryService.dart';

class IngredientStockListScreen extends StatefulWidget {
  const IngredientStockListScreen({super.key});

  @override
  State<IngredientStockListScreen> createState() =>
      _IngredientStockListScreenState();
}

class _IngredientStockListScreenState extends State<IngredientStockListScreen> {
  late final InventoryService _service;
  bool _serviceInitialized = false;
  final TextEditingController _searchController = TextEditingController();
  String _search = '';
  String _filter = 'all';
  String _selectedCategory = 'all';
  bool _isGridView = false;

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
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userScope = context.watch<UserScopeService>();
    final branchFilter = context.watch<BranchFilterService>();
    final branchIds = branchFilter.getFilterBranchIds(userScope.branchIds);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isLargeScreen = constraints.maxWidth > 800;

        return StreamBuilder(
          stream: Rx.combineLatest2(
            _service.streamIngredients(branchIds,
                isSuperAdmin: userScope.isSuperAdmin),
            _service.streamRecipes(branchIds,
                isSuperAdmin: userScope.isSuperAdmin),
            (List<IngredientModel> ingredients, List<RecipeModel> recipes) =>
                {'ingredients': ingredients, 'recipes': recipes},
          ),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: Colors.deepPurple),
              );
            }
            if (snapshot.hasError) {
              return Center(
                child: Text(
                  'Failed to load stock list: ${snapshot.error}',
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              );
            }
            
            final data = snapshot.data as Map<String, dynamic>? ?? {};
            final allItems = (data['ingredients'] as List<IngredientModel>?) ?? [];
            final recipes = (data['recipes'] as List<RecipeModel>?) ?? [];
            
            final items = _filterItems(allItems);

            if (isLargeScreen) {
              return _buildLargeScreenLayout(
                context,
                items,
                allItems,
                recipes,
                userScope,
                branchIds,
              );
            }

            // Mobile view below
            return Container(
              color: Colors.grey[50], // Match global bg
              child: Column(
                children: [
                  _buildTopControls(),
                  Expanded(
                    child: items.isEmpty
                        ? Center(
                            child: Text(
                              _search.isNotEmpty
                                  ? 'No ingredients match this search.'
                                  : 'No ingredients available.',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          )
                        : Column(
                            children: [
                              if (allItems.any((i) => i.isLowStock || i.isOutOfStock) && _filter == 'all' && _search.isEmpty)
                                _buildAlertBanner(allItems),
                              Expanded(
                                child: ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                                  itemCount: items.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                                  itemBuilder: (_, i) => _buildIngredientCard(
                                    context,
                                    items[i],
                                    recipes,
                                    userScope,
                                    branchIds,
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ─── PC LAYOUT (LARGE SCREEN) ────────────────────────────────────────────────

  Widget _buildLargeScreenLayout(
    BuildContext context,
    List<IngredientModel> filtered,
    List<IngredientModel> all,
    List<RecipeModel> recipes,
    UserScopeService userScope,
    List<String> branchIds,
  ) {
    return Container(
      color: Colors.grey[50],
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSummaryStatsRow(all),
                  const SizedBox(height: 32),
                  _buildFiltersBarPC(),
                  const SizedBox(height: 32),
                  if (filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 48.0),
                      child: Center(
                        child: Text(
                          _search.isNotEmpty
                              ? 'No ingredients match this search.'
                              : 'No ingredients available in inventory.',
                          style: TextStyle(color: Colors.grey[500], fontSize: 16),
                        ),
                      ),
                    )
                  else
                    _isGridView 
                      ? _buildInventoryGridPC(filtered, recipes, userScope, branchIds)
                      : _buildInventoryTable(filtered, recipes, userScope, branchIds),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }


  void _openEditIngredientForm(BuildContext context, IngredientModel ingredient) {
    final userScope = Provider.of<UserScopeService>(context, listen: false);
    final branchIds = Provider.of<BranchFilterService>(context, listen: false)
        .getFilterBranchIds(userScope.branchIds);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => IngredientFormSheet(
        existing: ingredient,
        branchIds: branchIds,
        service: IngredientService(),
      ),
    );
  }

  Widget _buildSummaryStatsRow(List<IngredientModel> all) {
    final totalValue = all.fold<double>(0, (sum, i) => sum + (i.costPerUnit * i.currentStock));
    final lowStockCount = all.where((i) => i.isLowStock).length;
    final outOfStockCount = all.where((i) => i.isOutOfStock).length;
    
    return Row(
      children: [
        _buildStatCard(
          title: 'Total Ingredients',
          value: all.length.toString(),
          icon: Icons.inventory_2_outlined,
          iconColor: Colors.deepPurple,
          bgColor: Colors.deepPurple.shade50,
          subtitle: 'Active inventory',
        ),
        const SizedBox(width: 16),
        _buildStatCard(
          title: 'Low Stock Items',
          value: lowStockCount.toString(),
          icon: Icons.warning_amber_rounded,
          iconColor: Colors.orange.shade700,
          bgColor: Colors.orange.shade50,
          subtitle: '${lowStockCount > 0 ? 'Needs attention' : 'All good!'}',
          subtitleColor: lowStockCount > 0 ? Colors.orange.shade800 : Colors.green.shade600,
        ),
        const SizedBox(width: 16),
        _buildStatCard(
          title: 'Out of Stock',
          value: outOfStockCount.toString().padLeft(2, '0'),
          icon: Icons.block,
          iconColor: Colors.red.shade600,
          bgColor: Colors.red.shade50,
          subtitle: '${outOfStockCount > 0 ? 'Critical restock required' : 'Fully stocked'}',
          subtitleColor: outOfStockCount > 0 ? Colors.red.shade800 : Colors.green.shade600,
        ),
        const SizedBox(width: 16),
        _buildStatCard(
          title: 'Inventory Value',
          value: '\$${totalValue.toStringAsFixed(2)}',
          icon: Icons.payments_outlined,
          iconColor: Colors.teal.shade600,
          bgColor: Colors.teal.shade50,
          subtitle: 'Estimated cost basis',
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required String subtitle,
    Color? subtitleColor,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade200),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))
          ]
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: TextStyle(color: Colors.grey.shade600, fontSize: 13, fontWeight: FontWeight.w600)),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, color: iconColor, size: 22),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(value, style: const TextStyle(color: Colors.black87, fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(subtitle, style: TextStyle(color: subtitleColor ?? Colors.grey.shade500, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildFiltersBarPC() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.deepPurple.withOpacity(0.04),
        border: Border.all(color: Colors.deepPurple.withOpacity(0.1)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Text(
            'FILTERS:', 
            style: TextStyle(color: Colors.grey.shade500, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0)
          ),
          const SizedBox(width: 16),
          _buildFilterDropdown(
            label: 'Category',
            value: _selectedCategory,
            items: ['all', ...IngredientModel.categories],
            labelFn: (v) => v == 'all' ? 'All Categories' : IngredientModel.categoryLabel(v),
            onChanged: (v) => setState(() => _selectedCategory = v ?? 'all'),
          ),
          const SizedBox(width: 12),
          _buildFilterDropdown(
            label: 'Status',
            value: _filter,
            items: ['all', 'low', 'out', 'expiring'],
            labelFn: (v) {
              if (v == 'all') return 'All Status';
              if (v == 'low') return 'Low Stock';
              if (v == 'out') return 'Out of Stock';
              if (v == 'expiring') return 'Expiring Soon';
              return v;
            },
            onChanged: (v) => setState(() => _filter = v ?? 'all'),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => setState(() => _isGridView = false),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: !_isGridView ? Colors.deepPurple.shade100 : Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: !_isGridView ? Colors.transparent : Colors.grey.shade300),
              ),
              child: Icon(Icons.view_list, color: !_isGridView ? Colors.deepPurple : Colors.grey.shade400, size: 18),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => setState(() => _isGridView = true),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: _isGridView ? Colors.deepPurple.shade100 : Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _isGridView ? Colors.transparent : Colors.grey.shade300),
              ),
              child: Icon(Icons.grid_view, color: _isGridView ? Colors.deepPurple : Colors.grey.shade400, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterDropdown({
    required String label,
    required String value,
    required List<String> items,
    required String Function(String) labelFn,
    required void Function(String?) onChanged,
  }) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              icon: Icon(Icons.expand_more, color: Colors.grey.shade600, size: 16),
              style: const TextStyle(color: Colors.black87, fontSize: 13, fontWeight: FontWeight.w600),
              onChanged: onChanged,
              items: items.map((String item) {
                return DropdownMenuItem<String>(value: item, child: Text(labelFn(item)));
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInventoryTable(
    List<IngredientModel> ingredients, 
    List<RecipeModel> recipes,
    UserScopeService userScope,
    List<String> branchIds,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))]
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: 1200,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    color: Colors.deepPurple.shade50.withOpacity(0.5),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    child: Row(
                      children: [
                        _buildTableHeaderCell('Ingredient / SKU', 300),
                        _buildTableHeaderCell('Category', 110),
                        _buildTableHeaderCell('Current Stock', 200),
                        _buildTableHeaderCell('Unit Cost', 110),
                        _buildTableHeaderCell('Allergens', 110),
                        _buildTableHeaderCell('Expiry / Status', 150),
                        _buildTableHeaderCell('Actions', 150, alignment: Alignment.centerRight),
                      ],
                    ),
                  ),
                  ...ingredients.map((i) => _buildTableRowPC(
                    context: context, 
                    ingredient: i,
                    recipes: recipes, 
                    userScope: userScope, 
                    branchIds: branchIds
                  )),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.shade100))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                RichText(
                  text: TextSpan(
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13, fontWeight: FontWeight.w500),
                    children: [
                      const TextSpan(text: 'Showing total '),
                      TextSpan(text: '${ingredients.length}', style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
                      const TextSpan(text: ' entries'),
                    ]
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildTableHeaderCell(String text, double width, {Alignment alignment = Alignment.centerLeft}) {
    return SizedBox(
      width: width,
      child: Align(
        alignment: alignment,
        child: Text(
          text.toUpperCase(),
          style: TextStyle(color: Colors.grey.shade500, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
        ),
      ),
    );
  }

  Widget _buildTableRowPC({
    required BuildContext context,
    required IngredientModel ingredient,
    required List<RecipeModel> recipes,
    required UserScopeService userScope,
    required List<String> branchIds,
  }) {
    final i = ingredient;
    final catIcon = _getCategoryIcon(i.category);
    final catColor = _getCategoryColor(i.category);
    
    final stockPercent = i.minStockThreshold > 0 
        ? (i.currentStock / (i.minStockThreshold * 2)).clamp(0.0, 1.0) 
        : 1.0;
        
    Color stockColor = Colors.green;
    if (i.isOutOfStock) stockColor = Colors.red;
    else if (i.isLowStock) stockColor = Colors.orange;
    
    IconData expiryIcon = Icons.event_available;
    Color expiryColor = Colors.grey.shade500;
    String expiryText = '-';
    String statusStr = 'Good';
    
    if (i.isPerishable) {
      if (i.isExpired) {
        expiryIcon = Icons.error_outline;
        expiryColor = Colors.red;
        expiryText = 'Expired';
        statusStr = 'Discard needed';
      } else if (i.isExpiringSoon) {
        expiryIcon = Icons.alarm;
        expiryColor = Colors.orange.shade700;
        expiryText = 'Expiring Soon';
        statusStr = 'Urgent update';
      } else if (i.expiryDate != null) {
        expiryColor = Colors.green.shade600;
        expiryText = '${i.expiryDate!.day}/${i.expiryDate!.month}/${i.expiryDate!.year}';
        statusStr = 'Fresh';
      } else if (i.shelfLifeDays != null) {
        expiryIcon = Icons.timer_outlined;
        expiryText = '${i.shelfLifeDays} days';
        statusStr = 'Active';
      }
    }

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: () => _openEditIngredientForm(context, i),
        child: Container(
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade100))),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Row(
            children: [
              SizedBox(
                width: 300,
                child: Row(
                  children: [
                    _buildAvatarPC(i, catColor, catIcon),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(i.name, style: const TextStyle(color: Colors.black87, fontSize: 14, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              if (i.sku?.isNotEmpty == true) ...[
                                Text('SKU: ${i.sku}', style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                                Container(width: 4, height: 4, margin: const EdgeInsets.symmetric(horizontal: 6), decoration: BoxDecoration(color: Colors.grey.shade300, shape: BoxShape.circle)),
                              ],
                              if (i.barcode?.isNotEmpty == true)
                                Text('BC: ${i.barcode}', style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                            ],
                          )
                        ],
                      ),
                    )
                  ],
                ),
              ),
              
              SizedBox(
                width: 110,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: catColor.withOpacity(0.1), borderRadius: BorderRadius.circular(4), border: Border.all(color: catColor.withOpacity(0.2))),
                    child: Text(IngredientModel.categoryLabel(i.category).toUpperCase(), style: TextStyle(color: catColor, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
              
              SizedBox(
                width: 200,
                child: Padding(
                  padding: const EdgeInsets.only(right: 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('${i.currentStock.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '')} ${i.unit}', style: TextStyle(color: stockColor, fontSize: 14, fontWeight: FontWeight.bold)),
                          Text('Min: ${i.minStockThreshold}${i.unit}', style: TextStyle(color: Colors.grey.shade500, fontSize: 10)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Container(
                        height: 5,
                        decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(3)),
                        child: Row(
                          children: [
                            Expanded(flex: (stockPercent * 100).toInt(), child: Container(decoration: BoxDecoration(color: stockColor, borderRadius: BorderRadius.circular(3)))),
                            Expanded(flex: ((1 - stockPercent) * 100).toInt().clamp(0, 100), child: Container())
                          ],
                        ),
                      )
                    ],
                  ),
                ),
              ),
              
              SizedBox(
                width: 110,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('\$${i.costPerUnit.toStringAsFixed(2)}', style: const TextStyle(color: Colors.black87, fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text('Per ${i.unit}', style: TextStyle(color: Colors.grey.shade500, fontSize: 10)),
                  ],
                ),
              ),
              
              SizedBox(
                width: 110,
                child: i.allergenTags.isEmpty
                  ? Container(width: 20, height: 20, alignment: Alignment.center, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.grey.shade300)), child: Text('-', style: TextStyle(color: Colors.grey.shade400, fontSize: 10, fontWeight: FontWeight.bold)))
                  : Wrap(
                      spacing: 4, runSpacing: 4,
                      children: i.allergenTags.take(1).map((a) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.blue.shade200)),
                        child: Text(IngredientModel.allergenLabel(a).toUpperCase(), style: TextStyle(color: Colors.blue.shade800, fontSize: 9, fontWeight: FontWeight.bold)),
                      )).toList(),
                    ),
              ),
              
              SizedBox(
                width: 150,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(expiryIcon, size: 14, color: expiryColor),
                        const SizedBox(width: 6),
                        Text(expiryText, style: TextStyle(color: expiryColor, fontSize: 12, fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(statusStr.toUpperCase(), style: TextStyle(color: expiryColor.withOpacity(0.8), fontSize: 9, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        icon: Icon(Icons.edit, size: 20, color: Colors.blue.shade400), 
                        onPressed: () => _openEditIngredientForm(context, i), 
                        tooltip: 'Edit Details',
                        splashRadius: 24,
                      ),
                      IconButton(
                        icon: Icon(Icons.iso, size: 20, color: Colors.deepPurple.shade300), 
                        onPressed: () => _openAdjustmentSheet(context, i, userScope, branchIds), 
                        tooltip: 'Adjust Stock',
                        splashRadius: 24,
                      ),
                      IconButton(
                        icon: Icon(Icons.history, size: 20, color: Colors.grey.shade400), 
                        onPressed: () => _showMovementHistory(context, i.name, i.id, branchIds), 
                        tooltip: 'History Logs', 
                        hoverColor: Colors.deepPurple.shade50,
                        splashRadius: 24,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarPC(IngredientModel i, Color catColor, IconData catIcon) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: catColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: catColor.withOpacity(0.2)),
        image: i.imageUrl != null ? DecorationImage(image: NetworkImage(i.imageUrl!), fit: BoxFit.cover) : null,
      ),
      child: i.imageUrl == null ? Icon(catIcon, color: catColor, size: 22) : null,
    );
  }

  IconData _getCategoryIcon(String cat) {
    switch (cat) {
      case 'produce': return Icons.eco_outlined;
      case 'dairy': return Icons.egg_outlined;
      case 'meat': return Icons.kebab_dining_outlined;
      case 'spices': return Icons.grain_outlined;
      case 'dry_goods': return Icons.inventory_2_outlined;
      case 'beverages': return Icons.local_drink_outlined;
      default: return Icons.category_outlined;
    }
  }

  Color _getCategoryColor(String cat) {
    switch (cat) {
      case 'produce': return Colors.green.shade600;
      case 'dairy': return Colors.blue.shade600;
      case 'meat': return Colors.red.shade600;
      case 'spices': return Colors.orange.shade600;
      case 'dry_goods': return Colors.brown.shade500;
      case 'beverages': return Colors.cyan.shade600;
      default: return Colors.deepPurple.shade500;
    }
  }

  Widget _buildInventoryGridPC(
    List<IngredientModel> ingredients, 
    List<RecipeModel> recipes,
    UserScopeService userScope,
    List<String> branchIds,
  ) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: ingredients.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 350,
        mainAxisSpacing: 24,
        crossAxisSpacing: 24,
        childAspectRatio: 0.95,
      ),
      itemBuilder: (context, index) {
        return _buildGridCardPC(
          context: context,
          ingredient: ingredients[index],
          recipes: recipes,
          userScope: userScope,
          branchIds: branchIds,
        );
      },
    );
  }

  Widget _buildGridCardPC({
    required BuildContext context,
    required IngredientModel ingredient,
    required List<RecipeModel> recipes,
    required UserScopeService userScope,
    required List<String> branchIds,
  }) {
    final i = ingredient;
    final catIcon = _getCategoryIcon(i.category);
    final catColor = _getCategoryColor(i.category);
    
    final stockPercent = i.minStockThreshold > 0 
        ? (i.currentStock / (i.minStockThreshold * 2)).clamp(0.0, 1.0) 
        : 1.0;
        
    Color stockColor = Colors.green;
    if (i.isOutOfStock) stockColor = Colors.red;
    else if (i.isLowStock) stockColor = Colors.orange;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openEditIngredientForm(context, i),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 10,
                offset: const Offset(0, 4),
              )
            ],
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildAvatarPC(i, catColor, catIcon),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          i.name,
                          style: const TextStyle(color: Colors.black87, fontSize: 16, fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${i.currentStock.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '')} ${i.unit} in stock',
                          style: TextStyle(color: stockColor, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.edit, size: 20, color: Colors.blue.shade400),
                    onPressed: () => _openEditIngredientForm(context, i),
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                    splashRadius: 20,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('SKU:', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                  Text(i.sku?.isNotEmpty == true ? i.sku! : '-', style: const TextStyle(color: Colors.black87, fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Cost:', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                  Text('QAR ${i.costPerUnit.toStringAsFixed(2)} / ${i.unit}', style: const TextStyle(color: Colors.black87, fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Category:', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: catColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      IngredientModel.categoryLabel(i.category).toUpperCase(),
                      style: TextStyle(color: catColor, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Container(
                height: 6,
                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(3)),
                child: Row(
                  children: [
                    Expanded(flex: (stockPercent * 100).toInt(), child: Container(decoration: BoxDecoration(color: stockColor, borderRadius: BorderRadius.circular(3)))),
                    Expanded(flex: ((1 - stockPercent) * 100).toInt().clamp(0, 100), child: Container())
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _openAdjustmentSheet(context, i, userScope, branchIds),
                      icon: Icon(Icons.iso, size: 16, color: Colors.deepPurple.shade300),
                      label: Text('Adjust', style: TextStyle(color: Colors.deepPurple.shade400, fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        side: BorderSide(color: Colors.deepPurple.shade100),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => _showMovementHistory(context, i.name, i.id, branchIds),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.all(8),
                      side: BorderSide(color: Colors.grey.shade200),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Icon(Icons.history, size: 16, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── END PC LAYOUT ───────────────────────────────────────────────────────────

  Widget _buildTopControls() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search ingredients...',
              prefixIcon:
                  Icon(Icons.search_rounded, color: Colors.deepPurple.shade300),
              filled: true,
              fillColor: Colors.grey[100],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (v) => setState(() => _search = v.toLowerCase()),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _filterChip('all', 'All'),
                _filterChip('low', 'Low Stock'),
                _filterChip('out', 'Out of Stock'),
                _filterChip('expiring', 'Expiring Soon'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertBanner(List<IngredientModel> allItems) {
    final outOfStock = allItems.where((i) => i.isOutOfStock).length;
    final lowStock = allItems.where((i) => i.isLowStock).length;
    
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            setState(() {
              _filter = outOfStock > 0 ? 'out' : 'low';
            });
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Stock Warning',
                        style: TextStyle(
                          color: Colors.red.shade900,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${outOfStock > 0 ? '$outOfStock out of stock' : ''}${outOfStock > 0 && lowStock > 0 ? ' and ' : ''}${lowStock > 0 ? '$lowStock low on stock' : ''}. Tap to review.',
                        style: TextStyle(
                          color: Colors.red.shade800,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: Colors.red.shade400),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _filterChip(String value, String label) {
    final selected = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => setState(() => _filter = value),
        label: Text(label, style: const TextStyle(fontSize: 12)),
        color: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? Colors.deepPurple
              : Colors.grey[100];
        }),
        labelStyle: TextStyle(
          color: selected ? Colors.white : Colors.grey[700],
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }

  List<IngredientModel> _filterItems(List<IngredientModel> all) {
    return all.where((i) {
      final matchSearch =
          _search.isEmpty || i.name.toLowerCase().contains(_search) || 
          (i.sku != null && i.sku!.toLowerCase().contains(_search)) ||
          (i.barcode != null && i.barcode!.toLowerCase().contains(_search));
      if (!matchSearch) return false;
      if (_selectedCategory != 'all' && i.category != _selectedCategory) return false;
      
      switch (_filter) {
        case 'low':
          return i.isLowStock;
        case 'out':
          return i.isOutOfStock;
        case 'expiring':
          return i.isExpiringSoon || i.isExpired;
        default:
          return true;
      }
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  Widget _buildIngredientCard(
    BuildContext context,
    IngredientModel i,
    List<RecipeModel> recipes,
    UserScopeService userScope,
    List<String> branchIds,
  ) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openAdjustmentSheet(context, i, userScope, branchIds),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.deepPurple.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      i.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _stockBadge(i),
                        const SizedBox(width: 8),
                        Text(
                          '${i.currentStock} ${i.unit}',
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[700]),
                        ),
                      ],
                    ),
                    if (i.isExpiringSoon || i.isExpired) ...[
                      const SizedBox(height: 6),
                      _expiryBadge(i),
                      const SizedBox(height: 8),
                      // Extract affected dishes
                      Builder(builder: (context) {
                        final affected = recipes.where((r) {
                          return r.ingredients.any((ri) => ri.ingredientId == i.id);
                        }).toList();
                        
                        if (affected.isEmpty) return const SizedBox.shrink();
                        
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.shade100),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.warning_amber_rounded, size: 14, color: Colors.red.shade600),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Affects ${affected.length} Dish${affected.length == 1 ? '' : 'es'}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red.shade800,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                affected.map((r) => r.linkedMenuItemName?.isNotEmpty == true ? r.linkedMenuItemName : r.name).join(', '),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.red.shade700,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
              IconButton(
                onPressed: () =>
                    _showMovementHistory(context, i.name, i.id, branchIds),
                icon: const Icon(Icons.history, color: Colors.deepPurple),
                tooltip: 'View movement history',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stockBadge(IngredientModel i) {
    if (i.isOutOfStock) {
      return _badge('Out', Colors.red.shade50, Colors.red);
    }
    if (i.isLowStock) {
      return _badge('Low', Colors.orange.shade50, Colors.orange.shade700);
    }
    return _badge('OK', Colors.green.shade50, Colors.green.shade700);
  }

  Widget _expiryBadge(IngredientModel i) {
    if (i.isExpired) {
      return _badge('Expired', Colors.red.shade50, Colors.red);
    }
    return _badge('Expiring Soon', Colors.orange.shade50, Colors.orange);
  }

  Widget _badge(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withOpacity(0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: fg, fontWeight: FontWeight.w700),
      ),
    );
  }

  Future<void> _openAdjustmentSheet(
    BuildContext context,
    IngredientModel ingredient,
    UserScopeService userScope,
    List<String> branchIds,
  ) async {
    final deltaController = TextEditingController();
    final noteController = TextEditingController();
    String reason = 'correction';
    bool saving = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateSheet) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ingredient.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.deepPurple,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Current stock: ${ingredient.currentStock} ${ingredient.unit}',
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: deltaController,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true, signed: true),
                    decoration: const InputDecoration(
                      labelText: 'Adjustment delta (+/-)',
                      hintText: 'e.g. -1.5 or 2',
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: reason,
                    items: const [
                      DropdownMenuItem(
                          value: 'correction', child: Text('Correction')),
                      DropdownMenuItem(
                          value: 'transfer', child: Text('Transfer')),
                      DropdownMenuItem(
                          value: 'personal_use', child: Text('Personal Use')),
                      DropdownMenuItem(
                          value: 'spoilage', child: Text('Spoilage')),
                      DropdownMenuItem(value: 'other', child: Text('Other')),
                    ],
                    onChanged: (v) => setStateSheet(() => reason = v ?? reason),
                    decoration: const InputDecoration(labelText: 'Reason'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: noteController,
                    decoration: const InputDecoration(
                      labelText: 'Note (optional)',
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: saving
                          ? null
                          : () async {
                              final delta =
                                  double.tryParse(deltaController.text.trim());
                              if (delta == null || delta == 0) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Enter a non-zero adjustment'),
                                    backgroundColor: Colors.orange,
                                  ),
                                );
                                return;
                              }
                              setStateSheet(() => saving = true);
                              try {
                                await _service.manualAdjustStock(
                                  ingredientId: ingredient.id,
                                  branchIds: [ingredient.branchIds.first],
                                  delta: delta,
                                  reason: reason,
                                  recordedBy: userScope.userIdentifier.isNotEmpty
                                      ? userScope.userIdentifier
                                      : (userScope.userEmail.isNotEmpty
                                          ? userScope.userEmail
                                          : 'system'),
                                  note: noteController.text.trim(),
                                );
                                if (context.mounted) {
                                  Navigator.pop(ctx);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Stock adjusted successfully'),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Adjustment failed: $e'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              } finally {
                                if (ctx.mounted) {
                                  setStateSheet(() => saving = false);
                                }
                              }
                            },
                      child: saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text('Confirm Adjustment'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    deltaController.dispose();
    noteController.dispose();
  }

  void _showMovementHistory(
    BuildContext context,
    String ingredientName,
    String ingredientId,
    List<String> branchIds,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '$ingredientName Movement History',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.deepPurple,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: _service.streamIngredientMovements(branchIds, ingredientId),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child:
                          CircularProgressIndicator(color: Colors.deepPurple),
                    );
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'Failed to load history: ${snapshot.error}',
                        style: const TextStyle(color: Colors.red),
                      ),
                    );
                  }
                  final rows = snapshot.data ?? [];
                  if (rows.isEmpty) {
                    return const Center(
                      child: Text('No movements found.'),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final m = rows[i];
                      final qty = (m['quantity'] as num?)?.toDouble() ?? 0;
                      final createdAt =
                          (m['createdAt'] as Timestamp?)?.toDate();
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                color: qty >= 0 ? Colors.green : Colors.red,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    (m['movementType'] ?? '').toString(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    createdAt?.toLocal().toString() ?? '-',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '${qty >= 0 ? '+' : ''}${qty.toStringAsFixed(2)}',
                              style: TextStyle(
                                color: qty >= 0 ? Colors.green : Colors.red,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
