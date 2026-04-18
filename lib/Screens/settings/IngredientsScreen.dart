import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rxdart/rxdart.dart';
import 'package:image_picker/image_picker.dart';

import '../../Models/IngredientModel.dart';
import '../../constants.dart';
import '../../services/ingredients/IngredientService.dart';
import '../../main.dart'; // UserScopeService is defined here
import '../../Widgets/BranchFilterService.dart';
import '../../Widgets/IngredientFormSheet.dart';

class IngredientsScreen extends StatefulWidget {
  const IngredientsScreen({super.key});

  @override
  State<IngredientsScreen> createState() => _IngredientsScreenState();
}

class _IngredientsScreenState extends State<IngredientsScreen> {
  late final IngredientService _ingredientService;
  bool _serviceInitialized = false;
  String _searchQuery = '';
  String _selectedCategory = 'all';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_serviceInitialized) {
      _serviceInitialized = true;
      _ingredientService =
          Provider.of<IngredientService>(context, listen: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userScope = context.watch<UserScopeService>();
    final branchFilter = context.watch<BranchFilterService>();
    final branchIds = branchFilter.getFilterBranchIds(userScope.branchIds);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isLargeScreen = constraints.maxWidth > 800;
          return Column(
            children: [
              if (!isLargeScreen) _buildSearchAndFilter(),
              Expanded(
                child: StreamBuilder<List<IngredientModel>>(
                  stream: _ingredientService.streamAllIngredients(branchIds),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(color: Colors.deepPurple),
                      );
                    }
                    if (snapshot.hasError) {
                      return _buildError(snapshot.error.toString());
                    }
                    final all = snapshot.data ?? [];
                    final filtered = _filter(all);

                    if (isLargeScreen) {
                      return _buildLargeScreenLayout(
                        filtered,
                        all,
                        userScope,
                        branchIds,
                      );
                    }

                    if (filtered.isEmpty) return _buildEmpty();
                    return _buildList(filtered, userScope, branchIds);
                  },
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 800) return const SizedBox.shrink();
          return FloatingActionButton.extended(
            onPressed: () => _openForm(context, userScope, branchIds),
            backgroundColor: Colors.deepPurple,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add),
            label: const Text('Add Ingredient'),
            elevation: 4,
          );
        },
      ),
    );
  }

  // ─── PC LAYOUT (LARGE SCREEN) ────────────────────────────────────────────────
  
  Widget _buildLargeScreenLayout(
    List<IngredientModel> filtered,
    List<IngredientModel> all,
    UserScopeService userScope,
    List<String> branchIds,
  ) {
    // Top headers and layout matching the prompt but with app colors
    return Column(
      children: [
        // Header
        _buildTopHeader(context, userScope, branchIds),
        
        // Dashboard Content
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSummaryStatsRow(all, branchIds),
                const SizedBox(height: 32),
                _buildFiltersBarPC(),
                const SizedBox(height: 32),
                if (filtered.isEmpty) 
                  Padding(
                    padding: const EdgeInsets.only(top: 48.0),
                    child: _buildEmpty(),
                  )
                else
                  _buildInventoryTable(filtered, userScope, branchIds),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTopHeader(
    BuildContext context, 
    UserScopeService userScope, 
    List<String> branchIds
  ) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          const Text(
            'Inventory Management',
            style: TextStyle(
              color: Colors.black87, 
              fontSize: 20, 
              fontWeight: FontWeight.bold
            ),
          ),
          const SizedBox(width: 48),
          
          // Search Bar
          Expanded(
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: TextField(
                style: const TextStyle(color: Colors.black87, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search by Name, SKU, or Barcode...',
                  hintStyle: TextStyle(color: Colors.grey.shade500),
                  prefixIcon: Icon(Icons.search, color: Colors.deepPurple.shade300, size: 20),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
              ),
            ),
          ),
          
          const SizedBox(width: 32),
          
          // Actions
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: () => _openForm(context, userScope, branchIds),
                icon: const Icon(Icons.add, size: 18, color: Colors.white),
                label: const Text(
                  'Add New Ingredient', 
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildSummaryStatsRow(List<IngredientModel> all, List<String> branchIds) {
    final totalValue = all.fold<double>(0, (sum, i) => sum + (i.costPerUnit * i.getStock(branchIds.isNotEmpty ? branchIds.first : "default")));
    final lowStockCount = all.where((i) => i.isLowStock(branchIds.isNotEmpty ? branchIds.first : "default")).length;
    final outOfStockCount = all.where((i) => i.isOutOfStock(branchIds.isNotEmpty ? branchIds.first : "default")).length;
    
    return Row(
      children: [
        _buildStatCard(
          title: 'Total Ingredients',
          value: all.length.toString(),
          icon: Icons.inventory_2_outlined,
          iconColor: Colors.deepPurple,
          bgColor: Colors.deepPurple.shade50,
        ),
        const SizedBox(width: 16),
        _buildStatCard(
          title: 'Low Stock Items',
          value: lowStockCount.toString(),
          icon: Icons.warning_amber_rounded,
          iconColor: Colors.orange.shade700,
          bgColor: Colors.orange.shade50,
        ),
        const SizedBox(width: 16),
        _buildStatCard(
          title: 'Out of Stock',
          value: outOfStockCount.toString().padLeft(2, '0'),
          icon: Icons.block,
          iconColor: Colors.red.shade600,
          bgColor: Colors.red.shade50,
        ),
        const SizedBox(width: 16),
        _buildStatCard(
          title: 'Inventory Value',
          value: 'QAR ${totalValue.toStringAsFixed(2)}',
          icon: Icons.payments_outlined,
          iconColor: Colors.teal.shade600,
          bgColor: Colors.teal.shade50,
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
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ]
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title, 
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 14, fontWeight: FontWeight.w600)
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: iconColor, size: 22),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              value, 
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyLarge?.color, 
                fontSize: 32, 
                fontWeight: FontWeight.bold
              )
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFiltersBarPC() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Text(
            'FILTERS:', 
            style: TextStyle(
              color: Colors.grey.shade500, 
              fontSize: 12, 
              fontWeight: FontWeight.bold, 
              letterSpacing: 1.0
            )
          ),
          const SizedBox(width: 16),
          _buildFilterDropdown(
            label: 'Category',
            value: _selectedCategory,
            items: ['all', ...IngredientModel.categories],
            labelFn: (v) => v == 'all' ? 'All Categories' : IngredientModel.categoryLabel(v),
            onChanged: (v) => setState(() => _selectedCategory = v ?? 'all'),
          ),
          
          const Spacer(),
          
          // View Toggles (Visual only for now matching UI)
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.deepPurple.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.deepPurple.shade100),
            ),
            child: const Icon(Icons.view_list, color: Colors.deepPurple, size: 20),
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
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              icon: Icon(Icons.expand_more, color: Colors.grey.shade600, size: 18),
              style: const TextStyle(color: Colors.black87, fontSize: 14, fontWeight: FontWeight.w600),
              onChanged: onChanged,
              items: items.map((String item) {
                return DropdownMenuItem<String>(
                  value: item,
                  child: Text(labelFn(item)),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInventoryTable(
    List<IngredientModel> ingredients, 
    UserScopeService userScope,
    List<String> branchIds,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ]
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Table constraints for horizontal scrolling
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: 1200, // min-w-[1200px]
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Table Header
                  Container(
                    color: Colors.grey.shade50,
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
                  
                  // Table Rows
                  ...ingredients.map((i) => _buildTableRowPC(
                    context: context, 
                    ingredient: i, 
                    userScope: userScope, 
                    branchIds: branchIds
                  )),
                ],
              ),
            ),
          ),
          
          // Pagination Footer placeholder
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade100)),
            ),
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
          style: TextStyle(color: Colors.grey.shade500, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5),
        ),
      ),
    );
  }

  Widget _buildTableRowPC({
    required BuildContext context,
    required IngredientModel ingredient,
    required UserScopeService userScope,
    required List<String> branchIds,
  }) {
    final i = ingredient;
    
    // Icon and colors based on category
    final catIcon = _getCategoryIcon(i.category);
    final catColor = _getCategoryColor(i.category);
    
    // Stock indicators
    final stockPercent = i.getMinThreshold(branchIds.isNotEmpty ? branchIds.first : "default") > 0 
        ? (i.getStock(branchIds.isNotEmpty ? branchIds.first : "default") / (i.getMinThreshold(branchIds.isNotEmpty ? branchIds.first : "default") * 2)).clamp(0.0, 1.0) 
        : 1.0;
        
    Color stockColor = Colors.green;
    if (i.isOutOfStock(branchIds.isNotEmpty ? branchIds.first : "default")) stockColor = Colors.red;
    else if (i.isLowStock(branchIds.isNotEmpty ? branchIds.first : "default")) stockColor = Colors.orange;
    
    // Expiry indicators
    IconData expiryIcon = Icons.event_available;
    Color expiryColor = Colors.grey.shade600;
    String expiryText = '-';
    String statusStr = 'Good';
    
    if (i.isPerishable) {
      if (i.isExpired) {
        expiryIcon = Icons.error_outline;
        expiryColor = Colors.red;
        expiryText = 'Expired';
        statusStr = 'Discard';
      } else if (i.isExpiringSoon) {
        expiryIcon = Icons.alarm;
        expiryColor = Colors.orange.shade700;
        expiryText = 'Expiring Soon';
        statusStr = 'Urgent';
      } else if (i.expiryDate != null) {
        expiryColor = Colors.green.shade600;
        expiryText = '${i.expiryDate!.day}/${i.expiryDate!.month}/${i.expiryDate!.year}';
        statusStr = 'Fresh';
      } else if (i.shelfLifeDays != null) {
        expiryIcon = Icons.timer_outlined;
        expiryText = '${i.shelfLifeDays} days';
      }
    }

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          // 1. Ingredient / SKU
          SizedBox(
            width: 300,
            child: Row(
              children: [
                _buildAvatarPC(i, catColor, catIcon),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        i.name, 
                        style: const TextStyle(color: Colors.black87, fontSize: 15, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (i.sku != null && i.sku!.isNotEmpty) ...[
                            Text('SKU: ${i.sku}', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                            Container(
                              width: 4, height: 4,
                              margin: const EdgeInsets.symmetric(horizontal: 8),
                              decoration: BoxDecoration(color: Colors.grey.shade300, shape: BoxShape.circle),
                            ),
                          ],
                          if (i.barcode != null && i.barcode!.isNotEmpty)
                            Text('BC: ${i.barcode}', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                        ],
                      )
                    ],
                  ),
                )
              ],
            ),
          ),
          
          // 2. Category
          SizedBox(
            width: 110,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: catColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: catColor.withOpacity(0.2)),
                ),
                child: Text(
                  IngredientModel.categoryLabel(i.category).toUpperCase(),
                  style: TextStyle(color: catColor, fontSize: 11, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
          
          // 3. Current Stock
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
                      Text(
                        '${i.getStock(branchIds.isNotEmpty ? branchIds.first : "default")} ${i.unit}', 
                        style: TextStyle(color: Colors.black87, fontSize: 14, fontWeight: FontWeight.bold)
                      ),
                      Text(
                        'Min: ${i.getMinThreshold(branchIds.isNotEmpty ? branchIds.first : "default")}${i.unit}', 
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 11)
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 6,
                    decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(3)),
                    child: Row(
                      children: [
                        Expanded(
                          flex: (stockPercent * 100).toInt(),
                          child: Container(
                            decoration: BoxDecoration(color: stockColor, borderRadius: BorderRadius.circular(3)),
                          ),
                        ),
                        Expanded(
                          flex: ((1 - stockPercent) * 100).toInt().clamp(0, 100),
                          child: Container(),
                        )
                      ],
                    ),
                  )
                ],
              ),
            ),
          ),
          
          // 4. Unit Cost
          SizedBox(
            width: 110,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'QAR ${i.costPerUnit.toStringAsFixed(2)}', 
                  style: const TextStyle(color: Colors.black87, fontSize: 14, fontWeight: FontWeight.w600)
                ),
                const SizedBox(height: 2),
                Text(
                  'Per ${i.unit}', 
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 11)
                ),
              ],
            ),
          ),
          
          // 5. Allergens
          SizedBox(
            width: 110,
            child: i.allergenTags.isEmpty
              ? Container(
                  width: 24, height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Text('-', style: TextStyle(color: Colors.grey.shade400, fontSize: 12, fontWeight: FontWeight.bold)),
                )
              : Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: i.allergenTags.take(2).map((allergen) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Text(
                      IngredientModel.allergenLabel(allergen).toUpperCase(), 
                      style: TextStyle(color: Colors.orange.shade800, fontSize: 9, fontWeight: FontWeight.bold)
                    ),
                  )).toList(),
                ),
          ),
          
          // 6. Expiry / Status
          SizedBox(
            width: 150,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(expiryIcon, size: 14, color: expiryColor),
                    const SizedBox(width: 6),
                    Text(
                      expiryText, 
                      style: TextStyle(
                        color: expiryColor, 
                        fontSize: 13, 
                        fontWeight: expiryColor != Colors.grey.shade600 ? FontWeight.bold : FontWeight.w500
                      )
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  statusStr.toUpperCase(),
                  style: TextStyle(
                    color: i.isActive ? Colors.grey.shade500 : Colors.red,
                    fontSize: 10, 
                    fontWeight: FontWeight.bold, 
                    letterSpacing: 0.5
                  )
                ),
              ],
            ),
          ),
          
          // 7. Actions
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: Icon(Icons.edit_square, size: 20, color: Colors.deepPurple.shade300), 
                    onPressed: () => _openForm(context, userScope, branchIds, existing: i), 
                    tooltip: 'Edit',
                    splashRadius: 24,
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_outline, size: 20, color: Colors.red.shade300), 
                    onPressed: () => _confirmDelete(context, i), 
                    tooltip: 'Delete', 
                    hoverColor: Colors.red.shade50,
                    splashRadius: 24,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarPC(IngredientModel i, Color catColor, IconData catIcon) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: catColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: catColor.withOpacity(0.2)),
        image: i.imageUrl != null
            ? DecorationImage(
                image: NetworkImage(i.imageUrl!),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: i.imageUrl == null
          ? Icon(catIcon, color: catColor, size: 24)
          : null,
    );
  }

  IconData _getCategoryIcon(String cat) {
    switch (cat) {
      case 'produce':
        return Icons.eco_outlined;
      case 'dairy':
        return Icons.egg_outlined;
      case 'meat':
        return Icons.kebab_dining_outlined;
      case 'spices':
        return Icons.grain_outlined;
      case 'dry_goods':
        return Icons.inventory_2_outlined;
      case 'beverages':
        return Icons.local_drink_outlined;
      default:
        return Icons.category_outlined;
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

  // ─── END PC LAYOUT ───────────────────────────────────────────────────────────


  // ─── FILTER BAR ────────────────────────────────────────────────────────────

  Widget _buildSearchAndFilter() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        children: [
          // Search
          TextField(
            decoration: InputDecoration(
              hintText: 'Search ingredients…',
              hintStyle: TextStyle(color: Colors.grey[400]),
              prefixIcon:
                  Icon(Icons.search_rounded, color: Colors.deepPurple.shade300),
              filled: true,
              fillColor: Colors.grey[100],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
          ),
          const SizedBox(height: 10),
          // Category chips
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _categoryChip('all', 'All'),
                ...IngredientModel.categories.map(
                  (c) => _categoryChip(c, IngredientModel.categoryLabel(c)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _categoryChip(String value, String label) {
    final selected = _selectedCategory == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: selected,
        onSelected: (_) => setState(() => _selectedCategory = value),
        showCheckmark: false,
        color: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.deepPurple;
          return Colors.grey[100];
        }),
        labelStyle: TextStyle(
          color: selected ? Colors.white : Colors.grey[700],
          fontWeight: selected ? FontWeight.bold : FontWeight.w500,
        ),
        side: BorderSide(
          color: selected ? Colors.deepPurple : Colors.grey.shade300,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
  }

  // ─── LIST ──────────────────────────────────────────────────────────────────

  List<IngredientModel> _filter(List<IngredientModel> all) {
    return all.where((i) {
      final matchSearch =
          _searchQuery.isEmpty || i.name.toLowerCase().contains(_searchQuery);
      final matchCat =
          _selectedCategory == 'all' || i.category == _selectedCategory;
      return matchSearch && matchCat;
    }).toList();
  }

  Widget _buildList(
    List<IngredientModel> items,
    UserScopeService userScope,
    List<String> branchIds,
  ) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (ctx, i) => _IngredientCard(
        ingredient: items[i],
        onEdit: () => _openForm(ctx, userScope, branchIds, existing: items[i]),
        onDelete: () => _confirmDelete(ctx, items[i]),
        branchIds: branchIds,
      ),
    );
  }

  // ─── FORM OPENER ───────────────────────────────────────────────────────────

  void _openForm(
    BuildContext context,
    UserScopeService userScope,
    List<String> branchIds, {
    IngredientModel? existing,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => IngredientFormSheet(
        existing: existing,
        branchIds: branchIds,
        service: _ingredientService,
      ),
    );
  }

  // ─── DELETE ────────────────────────────────────────────────────────────────

  Future<void> _confirmDelete(
      BuildContext ctx, IngredientModel ingredient) async {
    final confirm = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Ingredient?'),
        content: Text(
          '"${ingredient.name}" will be deactivated and hidden from all screens.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true && ctx.mounted) {
      try {
        await _ingredientService.deleteIngredient(
          ingredient.id,
          ingredient.supplierIds,
        );
        if (ctx.mounted) {
          ScaffoldMessenger.of(ctx).showSnackBar(
            SnackBar(
              content: Text('"${ingredient.name}" deleted.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (ctx.mounted) {
          ScaffoldMessenger.of(ctx).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  // ─── EMPTY / ERROR ─────────────────────────────────────────────────────────

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.blender_outlined, size: 72, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isNotEmpty
                ? 'No ingredients found'
                : 'No ingredients yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isNotEmpty
                ? 'Try a different search or category.'
                : 'Tap + to add your first ingredient.',
            style: TextStyle(color: Colors.grey[500], fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildError(String msg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            const Text('Failed to load ingredients',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(msg,
                style: const TextStyle(color: Colors.red, fontSize: 13),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// INGREDIENT CARD
// ─────────────────────────────────────────────────────────────────────────────

class _IngredientCard extends StatelessWidget {
  final IngredientModel ingredient;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final List<String> branchIds;

  const _IngredientCard({
    required this.ingredient,
    required this.onEdit,
    required this.onDelete,
    required this.branchIds,
  });

  @override
  Widget build(BuildContext context) {
    final i = ingredient;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.deepPurple.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onEdit,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Avatar / image
                _buildAvatar(i),
                const SizedBox(width: 14),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              i.name,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          _stockBadge(i, branchIds),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _chip(
                            IngredientModel.categoryLabel(i.category),
                            Colors.deepPurple.shade50,
                            Colors.deepPurple,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'QAR ${i.costPerUnit.toStringAsFixed(2)} / ${i.unit}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Stock row
                      Row(
                        children: [
                          Icon(Icons.inventory_2_outlined,
                              size: 13, color: Colors.grey[500]),
                          const SizedBox(width: 4),
                          Text(
                            'Stock: ${i.getStock(branchIds.isNotEmpty ? branchIds.first : "default")} ${i.unit}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                          if (i.isExpiringSoon || i.isExpired) ...[
                            const SizedBox(width: 8),
                            _expiryBadge(i),
                          ],
                        ],
                      ),
                      // Allergen row
                      if (i.allergenTags.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 4,
                          runSpacing: 2,
                          children: i.allergenTags
                              .map((a) => _chip(
                                    IngredientModel.allergenLabel(a),
                                    Colors.orange.shade50,
                                    Colors.orange.shade800,
                                  ))
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                ),
                // Actions
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined,
                          size: 20, color: Colors.deepPurple),
                      onPressed: onEdit,
                      tooltip: 'Edit',
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      icon: Icon(Icons.delete_outline,
                          size: 20, color: Colors.red.shade400),
                      onPressed: onDelete,
                      tooltip: 'Delete',
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(IngredientModel i) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.deepPurple.withOpacity(0.08),
        image: i.imageUrl != null
            ? DecorationImage(
                image: NetworkImage(i.imageUrl!),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: i.imageUrl == null
          ? const Icon(Icons.blender_outlined,
              color: Colors.deepPurple, size: 28)
          : null,
    );
  }

  Widget _stockBadge(IngredientModel i, List<String> branchIds) {
    Color color;
    String label;
    if (i.isOutOfStock(branchIds.isNotEmpty ? branchIds.first : "default")) {
      color = Colors.red;
      label = 'Out';
    } else if (i.isLowStock(branchIds.isNotEmpty ? branchIds.first : "default")) {
      color = Colors.orange;
      label = 'Low';
    } else {
      color = Colors.green;
      label = 'OK';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _expiryBadge(IngredientModel i) {
    final color = i.isExpired ? Colors.red : Colors.amber.shade700;
    final label = i.isExpired ? 'Expired' : 'Expiring';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  Widget _chip(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label,
          style:
              TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}
