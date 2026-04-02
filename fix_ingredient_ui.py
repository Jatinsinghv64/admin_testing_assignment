import re

file_path = "lib/Screens/inventory/IngredientStockListScreen.dart"

with open(file_path, "r") as f:
    content = f.read()

# build SummaryStatsRow
content = content.replace("Widget _buildSummaryStatsRow(List<IngredientModel> all) {", "Widget _buildSummaryStatsRow(List<IngredientModel> all, List<String> branchIds) {\n    final String bId = branchIds.isNotEmpty ? branchIds.first : 'default';")
content = content.replace("final totalValue = all.fold<double>(0, (sum, i) => sum + (i.costPerUnit * i.currentStock));", "final totalValue = all.fold<double>(0, (sum, i) => sum + (i.costPerUnit * i.getStock(bId)));")
content = content.replace("final lowStockCount = all.where((i) => i.isLowStock).length;", "final lowStockCount = all.where((i) => i.isLowStock(bId)).length;")
content = content.replace("final outOfStockCount = all.where((i) => i.isOutOfStock).length;", "final outOfStockCount = all.where((i) => i.isOutOfStock(bId)).length;")
content = content.replace("_buildSummaryStatsRow(all),", "_buildSummaryStatsRow(all, branchIds),")

# buildAlertBanner
content = content.replace("if (allItems.any((i) => i.isLowStock || i.isOutOfStock) && _filter == 'all' && _search.isEmpty)\n                                _buildAlertBanner(allItems),", "if (allItems.any((i) => i.isLowStock(branchIds.isNotEmpty ? branchIds.first : 'default') || i.isOutOfStock(branchIds.isNotEmpty ? branchIds.first : 'default')) && _filter == 'all' && _search.isEmpty)\n                                _buildAlertBanner(allItems, branchIds),")
content = content.replace("Widget _buildAlertBanner(List<IngredientModel> allItems) {", "Widget _buildAlertBanner(List<IngredientModel> allItems, List<String> branchIds) {\n    final String bId = branchIds.isNotEmpty ? branchIds.first : 'default';")
content = content.replace("final outOfStock = allItems.where((i) => i.isOutOfStock).length;", "final outOfStock = allItems.where((i) => i.isOutOfStock(bId)).length;")
content = content.replace("final lowStock = allItems.where((i) => i.isLowStock).length;", "final lowStock = allItems.where((i) => i.isLowStock(bId)).length;")

# _filterItems
content = content.replace("List<IngredientModel> _filterItems(Licontent = content.replace("Widget _buildAlertBanner(List<IngredientModel> allItems) {", "Widget _buildAlertBanner(List<IngredientModel> allItems, List<String> branchIds) {\n    final String bId = branchIds.isNotEmpty ? branchI"return i.isLowStock;", "return i.isLowStock(bId);")
content = content.replace("return i.isOutOfStock;", "return i.isOutOfStock(bId);")
content = content.replace("final items = _filterItems(allItems);", "final items = _filterItems(allItems, branchIds);")

# _buildTableRowPC
content = content.replace("final i = ingredient;\n    final catIcon = _getCategoryIcon(i.category);", "final i = ingredient;\n    final String bId = branchIds.isNotEmpty ? branchIds.first : 'default';\n    final catIcon = _getCategoryIcon(i.category);")
content = content.replace("final stockPercent = i.minStockThreshold > 0 \n        ? (i.currentStock / (i.minStockThreshold * 2)).clamp(0.0, 1.0)", "final stockPercent = i.getMinThreshold(bId) > 0 \n        ? (i.getStock(bId) / (i.getMinThreshold(bId) * 2)).clamp(0.0, 1.0)")
content = content.replace("if (i.isOutOfStock) stockColor = Colors.red;\n    else if (i.isLowStock) stockColor = Colors.orange;", "if (i.isOutOfStock(bId)) stockColor = Colors.red;\n    else if (i.isLowStock(bId)) stockColor = Colors.orange;")
content = content.replace("${i.currentStock.toStringAsFixed(1).replaceAll(RegExp(r'\\.0$'), '')} ${i.unit}", "${i.getStock(bId).toStringAsFixed(1).replaceAll(RegExp(r'\\.0$'), '')} ${i.unit}")
content = content.replace("Min: ${i.minStockThreshold}${i.unit}", "Min: ${i.getMinThreshold(bId)}${i.unit}")

# _buildGridCardPC
content = content.replace("final i = ingredient;\n    final catIcon = _getCategoryIcon(i.category);", "final i = ingredient;\n    final String bId = branchIds.isNotEmpty ? branchIds.first : 'default';\n    final catIcon = _getCategoryIcon(i.category);")

# _buildIngredientCard
content = content.replace("final i = ingredient;\n    final catColor = _getCategoryColor(i.category);", "final i = ingredient;\n    final String bId = branchIds.isNotEmpty ? branchIds.first : 'default';\n    final catColor = _getCategoryColor(i.category);")
content = content.replace("'${i.currentStock} ${i.unit}',", "'${i.getStock(bId)} ${i.unit}',")

# _buildStatusBadge
content = content.replace("Widget _buildStatusBadge(IngredientModel i) {", "Widget _buildStatusBadge(IngredientModel i, String bId) {")
content = content.replace("if (i.isOutOfStock) {", "if (i.isOutOfStock(bId)) {")
content = content.replace("if (i.isLowStock) {", "if (i.isLowStock(bId)) {")
content = content.replace("_buildStatusBadge(i),", "_buildStatusBadge(i, branchIds.isNotEmpty ? branchIds.first : 'default'),")

# _showDetailsModal
content = content.replace("void _showDetailsModal(BuildContext context, IngredientModel ingredient) {", "void _showDetailsModal(BuildContext context, IngredientModel ingredient, List<String> branchIds) {\n    final String bId = branchIds.isNotEmpty ? branchIds.first : 'default';")
content = content.replace("Current stock: ${ingredient.currentStock} ${ingredient.unit}", "Current stock: ${ingredient.getStock(bId)} ${ingredient.unit}")
content = content.replace("_showDetailsModal(context, i);", "_showDetailsModal(context, i, branchIds);")

with open(file_path, "w") as f:
    f.write(content)

print("IngredientStockListScreen.dart updated via script")
