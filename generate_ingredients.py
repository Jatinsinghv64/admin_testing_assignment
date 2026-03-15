import re

file_path = "lib/Screens/DashboardScreen.dart"
with open(file_path, "r") as f:
    content = f.read()

# 1. Add generate ingredients method to DashboardScreenState
generate_code = """
  bool _isGeneratingIngredients = false;

  Future<void> _generateDefaultIngredients() async {
    final userScope = context.read<UserScopeService>();
    final branchId = userScope.branchId;
    if (branchId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a branch first', style: TextStyle(color: Colors.white)), backgroundColor: Colors.red)
      );
      return;
    }

    setState(() => _isGeneratingIngredients = true);
    try {
      final db = FirebaseFirestore.instance;
      
      // List of core restaurant ingredients
      final ingredients = [
        {'name': 'Chicken Breast', 'category': 'Meat', 'unit': 'kg', 'currentStock': 50.0, 'lowStockThreshold': 10.0, 'costPerUnit': 25.0},
        {'name': 'Beef Mince', 'category': 'Meat', 'unit': 'kg', 'currentStock': 30.0, 'lowStockThreshold': 8.0, 'costPerUnit': 45.0},
        {'name': 'Basmati Rice', 'category': 'Grains', 'unit': 'kg', 'currentStock': 100.0, 'lowStockThreshold': 20.0, 'costPerUnit': 6.5},
        {'name': 'Flour', 'category': 'Grains', 'unit': 'kg', 'currentStock': 80.0, 'lowStockThreshold': 15.0, 'costPerUnit': 3.0},
        {'name': 'Onions', 'category': 'Vegetables', 'unit': 'kg', 'currentStock': 40.0, 'lowStockThreshold': 15.0, 'costPerUnit': 4.0},
        {'name': 'Tomatoes', 'category': 'Vegetables', 'unit': 'kg', 'currentStock': 35.0, 'lowStockThreshold': 10.0, 'costPerUnit': 5.5},
        {'name': 'Potatoes', 'category': 'Vegetables', 'unit': 'kg', 'currentStock': 60.0, 'lowStockThreshold': 20.0, 'costPerUnit': 3.5},
        {'name': 'Garlic', 'category': 'Vegetables', 'unit': 'kg', 'currentStock': 10.0, 'lowStockThreshold': 2.0, 'costPerUnit': 12.0},
        {'name': 'Ginger', 'category': 'Vegetables', 'unit': 'kg', 'currentStock': 8.0, 'lowStockThreshold': 2.0, 'costPerUnit': 15.0},
        {'name': 'Cooking Oil', 'category': 'Dairy & Oils', 'unit': 'L', 'currentStock': 50.0, 'lowStockThreshold': 10.0, 'costPerUnit': 8.0},
        {'name': 'Milk', 'category': 'Dairy & Oils', 'unit': 'L', 'currentStock': 20.0, 'lowStockThreshold': 5.0, 'costPerUnit': 6.0},
        {'name': 'Butter', 'category': 'Dairy & Oils', 'unit': 'kg', 'currentStock': 15.0, 'lowStockThreshold': 3.0, 'costPerUnit': 28.0},
        {'name': 'Salt', 'category': 'Spices', 'unit': 'kg', 'currentStock': 20.0, 'lowStockThreshold': 5.0, 'costPerUnit': 2.0},
        {'name': 'Black Pepper', 'category': 'Spices', 'unit': 'kg', 'currentStock': 5.0, 'lowStockThreshold': 1.0, 'costPerUnit': 35.0},
        {'name': 'Cumin Powder', 'category': 'Spices', 'unit': 'kg', 'currentStock': 4.0, 'lowStockThreshold': 1.0, 'costPerUnit': 40.0},
        {'name': 'Eggs', 'category': 'Dairy & Oils', 'unit': 'pcs', 'currentStock': 360.0, 'lowStockThreshold': 30.0, 'costPerUnit': 0.8},
        {'name': 'Cheddar Cheese', 'category': 'Dairy & Oils', 'unit': 'kg', 'currentStock': 12.0, 'lowStockThreshold': 3.0, 'costPerUnit': 45.0},
        {'name': 'Lettuce', 'category': 'Vegetables', 'unit': 'heads', 'currentStock': 30.0, 'lowStockThreshold': 8.0, 'costPerUnit': 4.5},
        {'name': 'Burger Buns', 'category': 'Bakery', 'unit': 'pcs', 'currentStock': 200.0, 'lowStockThreshold': 50.0, 'costPerUnit': 1.2},
        {'name': 'Tomato Ketchup', 'category': 'Condiments', 'unit': 'L', 'currentStock': 15.0, 'lowStockThreshold': 3.0, 'costPerUnit': 12.0},
      ];

      final batch = db.batch();
      for (var ing in ingredients) {
        final docRef = db.collection('ingredients').doc();
        batch.set(docRef, {
          'name': ing['name'],
          'category': ing['category'],
          'unit': ing['unit'],
          'currentStock': ing['currentStock'],
          'lowStockThreshold': ing['lowStockThreshold'],
          'costPerUnit': ing['costPerUnit'],
          'supplierId': '',
          'allergenTags': [],
          'isExpiringSoon': false,
          'isExpired': false,
          'expiryDate': null,
          'barcode': '',
          'sku': 'ING-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
          'branchId': branchId,
          'isActive': true,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'lastRestockedAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Successfully generated default ingredients!', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green)
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('Failed to generate ingredients: $e', style: const TextStyle(color: Colors.white)), backgroundColor: Colors.red)
        );
      }
    } finally {
      if (mounted) setState(() => _isGeneratingIngredients = false);
    }
  }
"""

if "_generateDefaultIngredients" not in content:
    # insert before widget build
    content = content.replace("  @override\n  Widget build(BuildContext context) {", generate_code + "\n  @override\n  Widget build(BuildContext context) {")


# 2. Add an action button to the app bar
app_bar_actions = """        actions: [
          if (userScope.isSuperAdmin) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 10.0),
              child: ElevatedButton.icon(
                onPressed: _isGeneratingIngredients ? null : _generateDefaultIngredients,
                icon: _isGeneratingIngredients 
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.auto_awesome, size: 16),
                label: const Text('Add Test Ingredients', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
          if (showBranchSelector) _buildBranchSelector(userScope, branchFilter, isDark),
        ],"""

# Replace the existing actions
actions_pattern = r"        actions: \[\n          if \(showBranchSelector\) _buildBranchSelector\(userScope, branchFilter, isDark\),\n        \],"
content = re.sub(actions_pattern, app_bar_actions, content)


with open(file_path, "w") as f:
    f.write(content)

print("Added Bulk Generate Button")
