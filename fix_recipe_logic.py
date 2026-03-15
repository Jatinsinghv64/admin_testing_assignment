import re

file_path = "lib/Screens/DishEditScreenLarge.dart"
with open(file_path, "r") as f:
    content = f.read()

# 1. Update _saveMenuItem to include cost
# find: 'price': double.tryParse(_priceController.text) ?? 0.0,
content = content.replace(
    "'price': double.tryParse(_priceController.text) ?? 0.0,",
    "'price': double.tryParse(_priceController.text) ?? 0.0,\n      'cost': _recipeIngredients.isEmpty ? 0.0 : _recipeIngredients.map((e) => (_ingredientCosts[e.ingredientId] ?? 0.0) * e.quantity).fold(0.0, (a, b) => a + b),"
)

# 2. Update allergens card & methods
allergen_code = """
  final List<Map<String, dynamic>> _commonAllergens = [
    {'label': 'Dairy', 'icon': Icons.water_drop, 'color': Colors.blue},
    {'label': 'Eggs', 'icon': Icons.egg, 'color': Colors.orangeAccent},
    {'label': 'Gluten', 'icon': Icons.local_pizza, 'color': Colors.amber},
    {'label': 'Nuts', 'icon': Icons.cookie, 'color': Colors.brown},
    {'label': 'Soy', 'icon': Icons.grass, 'color': Colors.green},
    {'label': 'Fish', 'icon': Icons.set_meal, 'color': Colors.teal},
    {'label': 'Shellfish', 'icon': Icons.bug_report, 'color': Colors.redAccent},
  ];

  void _showAllergenDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: Colors.white,
              title: const Text('Edit Allergen Profile'),
              content: SizedBox(
                width: 400,
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: _commonAllergens.map((alg) {
                    final label = alg['label'] as String;
                    final isSelected = _linkedAllergens.contains(label);
                    return FilterChip(
                      selected: isSelected,
                      label: Text(label),
                      avatar: Icon(alg['icon'] as IconData, color: alg['color'] as Color, size: 16),
                      onSelected: (val) {
                        setStateDialog(() {
                          if (val) {
                            _linkedAllergens.add(label);
                          } else {
                            _linkedAllergens.remove(label);
                          }
                        });
                        setState(() {}); // update main screen
                      },
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildAllergenProfileCard() {
    final activeAllergens = _commonAllergens.where((a) => _linkedAllergens.contains(a['label'])).toList();
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: _rSurface, borderRadius: BorderRadius.circular(12), border: Border.all(color: _rBorder)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Allergen Profile', style: TextStyle(color: _rTextMain, fontSize: 14, fontWeight: FontWeight.w600)),
              IconButton(icon: const Icon(Icons.edit, size: 16, color: _rPrimary), onPressed: _showAllergenDialog),
            ],
          ),
          const SizedBox(height: 16),
          if (activeAllergens.isEmpty)
             const Text('No allergens selected.', style: TextStyle(color: _rTextSubtle, fontSize: 13))
          else
            Wrap(
              spacing: 8, runSpacing: 8,
              children: activeAllergens.map((a) => Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: _rBorder)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(a['icon'] as IconData, color: a['color'] as Color, size: 16),
                    const SizedBox(width: 6),
                    Text(a['label'] as String, style: const TextStyle(color: _rTextSubtle, fontSize: 12)),
                  ],
                ),
              )).toList(),
            ),
"""

card_pattern = r"  Widget _buildAllergenProfileCard\(\) \{.*?(?=  Widget _buildInventoryForecastCard)"
content = re.sub(card_pattern, allergen_code, content, flags=re.DOTALL)


# 3. Portions calculation
portions_code = """
  Widget _buildInventoryForecastCard() {
    int minPortions = -1;
    bool hasLowStock = false;
    
    for (final line in _recipeIngredients) {
      if (line.quantity <= 0) continue;
      final ing = _availableIngredients.firstWhere((i) => i.id == line.ingredientId, orElse: () => Ingredient(id: '', name: '', unit: '', currentStock: 0, category: '', isActive: false));
      if (ing.id.isEmpty) continue;
      
      final portions = (ing.currentStock / line.quantity).floor();
      if (minPortions == -1 || portions < minPortions) {
        minPortions = portions;
      }
      if (portions <= 5) hasLowStock = true;
    }
    final possiblePortions = minPortions < 0 ? 0 : minPortions;
    final progress = possiblePortions > 50 ? 1.0 : (possiblePortions / 50.0);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: _rSurface, borderRadius: BorderRadius.circular(12), border: Border.all(color: _rBorder)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
           const Text('Inventory Forecast', style: TextStyle(color: _rTextMain, fontSize: 14, fontWeight: FontWeight.w600)),
           const SizedBox(height: 16),
           Row(
             mainAxisAlignment: MainAxisAlignment.spaceBetween,
             children: [
               const Text('Possible Portions', style: TextStyle(color: _rTextSubtle, fontSize: 12)),
               Text('$possiblePortions', style: const TextStyle(color: _rTextMain, fontSize: 14, fontWeight: FontWeight.bold)),
             ],
           ),
           const SizedBox(height: 8),
           Container(
             height: 8,
             decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
             child: FractionallySizedBox(
               alignment: Alignment.centerLeft,
               widthFactor: progress,
               child: Container(decoration: BoxDecoration(color: hasLowStock ? Colors.redAccent : _rPrimary, borderRadius: BorderRadius.circular(4))),
             ),
           ),
           if (hasLowStock) ...[
             const SizedBox(height: 16),
             Container(
               padding: const EdgeInsets.all(12),
               decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.redAccent.withOpacity(0.2))),
               child: Column(
                 crossAxisAlignment: CrossAxisAlignment.start,
                 children: [
                   Row(
                     children: const [
                       Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 18),
                       SizedBox(width: 8),
                       Text('LOW STOCK ALERT', style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                     ]
                   ),
                   const SizedBox(height: 4),
                   const Text('Ingredients for this recipe are running low.', style: TextStyle(color: _rTextSubtle, fontSize: 11)),
                 ],
               )
             )
           ]
        ],
      ),
    );
  }
"""

portions_pattern = r"  Widget _buildInventoryForecastCard\(\) \{.*?(?=  Widget _buildWeeklySalesCard)"
content = re.sub(portions_pattern, portions_code, content, flags=re.DOTALL)

with open(file_path, "w") as f:
    f.write(content)

print("Updated DishEditScreenLarge")
