import 'dart:io';

void fixFile(String path) {
  final file = File(path);
  if (!file.existsSync()) return;
  String content = file.readAsStringSync();

  // IngredientStockListScreen & IngredientsScreen & AnalyticsScreen & DishEditScreen & Stocktake
  content = content.replaceAll('i.currentStock', 'i.getStock(branchIds.isNotEmpty ? branchIds.first : "default")');
  content = content.replaceAll('ingredient.currentStock', 'ingredient.getStock(branchIds.isNotEmpty ? branchIds.first : "default")');
  content = content.replaceAll('e.currentStock', 'e.getStock(branchIds.isNotEmpty ? branchIds.first : "default")');
  content = content.replaceAll('row.currentStock', 'row.getStock(branchIds.isNotEmpty ? branchIds.first : "default")');
  content = content.replaceAll('item.currentStock', 'item.getStock(branchIds.isNotEmpty ? branchIds.first : "default")');
  
  content = content.replaceAll('i.minStockThreshold', 'i.getMinThreshold(branchIds.isNotEmpty ? branchIds.first : "default")');
  content = content.replaceAll('ingredient.minStockThreshold', 'ingredient.getMinThreshold(branchIds.isNotEmpty ? branchIds.first : "default")');
  content = content.replaceAll('e.minStockThreshold', 'e.getMinThreshold(branchIds.isNotEmpty ? branchIds.first : "default")');
  
  content = content.replaceAll('i.isLowStock', 'i.isLowStock(branchIds.isNotEmpty ? branchIds.first : "default")');
  content = content.replaceAll('i.isOutOfStock', 'i.isOutOfStock(branchIds.isNotEmpty ? branchIds.first : "default")');
  content = content.replaceAll('ingredient.isLowStock', 'ingredient.isLowStock(branchIds.isNotEmpty ? branchIds.first : "default")');
  content = content.replaceAll('ingredient.isOutOfStock', 'ingredient.isOutOfStock(branchIds.isNotEmpty ? branchIds.first : "default")');

  file.writeAsStringSync(content);
  print('Fixed: $path');
}

void main() {
  final files = [
    'lib/Screens/inventory/IngredientStockListScreen.dart',
    'lib/Screens/settings/IngredientsScreen.dart',
    'lib/Screens/AnalyticsScreen.dart',
    'lib/Screens/inventory/StocktakeScreen.dart',
    'lib/Screens/DishEditScreenLarge.dart',
    'lib/Widgets/IngredientFormSheet.dart',
    'lib/Screens/inventory/InventoryDashboardScreen.dart',
    'lib/Screens/inventory/WasteEntryScreenLarge.dart',
  ];

  for (final f in files) {
    fixFile(f);
  }
}
