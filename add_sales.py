import re

file_path = "lib/Screens/DishEditScreenLarge.dart"
with open(file_path, "r") as f:
    content = f.read()

# 1. Add state variables and `_fetchWeeklySales` method
if "List<double> _weeklySalesData" not in content:
    vars_code = """
  List<double> _weeklySalesData = List.filled(7, 0.0);
  bool _isLoadingSales = false;

  Future<void> _fetchWeeklySales() async {
    if (widget.doc == null) return;
    setState(() => _isLoadingSales = true);
    try {
      final now = DateTime.now();
      // start of day 6 days ago
      final weekAgoDate = now.subtract(const Duration(days: 6));
      final weekAgo = DateTime(weekAgoDate.year, weekAgoDate.month, weekAgoDate.day);
      
      final snap = await FirebaseFirestore.instance.collection('orders')
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(weekAgo))
          .get();
      
      final sales = List.filled(7, 0.0);
      for (var doc in snap.docs) {
        final data = doc.data();
        final items = data['items'] as List<dynamic>? ?? [];
        final createdAt = (data['createdAt'] as Timestamp).toDate();
        final daysAgo = now.difference(DateTime(createdAt.year, createdAt.month, createdAt.day)).inDays;
        
        if (daysAgo >= 0 && daysAgo < 7) {
          for (var item in items) {
            if (item['menuItemId'] == widget.doc!.id) {
              final qty = (item['quantity'] as num?)?.toDouble() ?? 1.0;
              final idx = 6 - daysAgo; // 6 is today, 0 is 6 days ago
              sales[idx] += qty;
            }
          }
        }
      }
      if (mounted) {
        setState(() {
          _weeklySalesData = sales;
        });
      }
    } catch (e) {
      debugPrint('Error fetching sales: $e');
    } finally {
      if (mounted) setState(() => _isLoadingSales = false);
    }
  }
"""
    # Insert after `bool get _isEdit => widget.doc != null;`
    content = content.replace("bool get _isEdit => widget.doc != null;", "bool get _isEdit => widget.doc != null;\n" + vars_code)

# 2. Call `_fetchWeeklySales()` in initState
if "_fetchWeeklySales();" not in content:
    content = content.replace(
        "_loadAvailableIngredients(currentBranch);",
        "_loadAvailableIngredients(currentBranch);\n    _fetchWeeklySales();"
    )

# 3. Update `_buildWeeklySalesCard()` to use real data
real_sales_code = """
  Widget _buildWeeklySalesCard() {
    double maxSales = 0;
    for (var s in _weeklySalesData) {
      if (s > maxSales) maxSales = s;
    }
    final heights = _weeklySalesData.map((s) => maxSales > 0 ? (s / maxSales) : 0.0).toList();
    final totalSales = _weeklySalesData.reduce((a, b) => a + b).toInt();

    final now = DateTime.now();
    final labels = List.generate(7, (i) {
        final d = now.subtract(Duration(days: 6 - i));
        return ['M','T','W','T','F','S','S'][d.weekday - 1];
    });

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: _rSurface, borderRadius: BorderRadius.circular(12), border: Border.all(color: _rBorder)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
               const Text('Weekly Sales', style: TextStyle(color: _rTextMain, fontSize: 14, fontWeight: FontWeight.w600)),
               if (_isLoadingSales)
                 const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _rPrimary))
               else
                 Text('$totalSales total', style: const TextStyle(color: _rTextSubtle, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 100,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(7, (i) {
                return Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    child: FractionallySizedBox(
                      heightFactor: heights[i],
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        decoration: BoxDecoration(
                          color: _rPrimary.withOpacity(heights[i] > 0.8 ? 1.0 : heights[i] > 0.4 ? 0.6 : 0.2),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(2))
                        ),
                      ),
                    ),
                  )
                );
              }),
            ),
          ),
          const SizedBox(height: 8),
          Row(
             mainAxisAlignment: MainAxisAlignment.spaceBetween,
             children: labels.map((l) => Expanded(child: Center(child: Text(l, style: const TextStyle(color: _rTextSubtle, fontSize: 10))))).toList(),
          )
        ],
      )
    );
  }
"""

card_pattern = r"  Widget _buildWeeklySalesCard\(\) \{.*?\}\n  \}"
content = re.sub(card_pattern, real_sales_code + "\n}", content, flags=re.DOTALL)

with open(file_path, "w") as f:
    f.write(content)

print("Added real sales data")
