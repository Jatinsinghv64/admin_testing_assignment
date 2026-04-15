// lib/Widgets/BusinessPerformancePanel.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../constants.dart';
import '../Models/IngredientModel.dart'; // Standardized stock validation

class BusinessPerformancePanel extends StatelessWidget {
  final List<String> branchIds;
  final bool isMobile;
  final Color primaryColor;
  final Color surfaceColor;
  final Color textColor;

  const BusinessPerformancePanel({
    super.key,
    required this.branchIds,
    this.isMobile = false,
    this.primaryColor = Colors.deepPurple,
    this.surfaceColor = Colors.white,
    this.textColor = Colors.black87,
  });

  @override
  Widget build(BuildContext context) {
    // We only fetch today's orders to calculate margin/stats to be lightweight
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    
    Query<Map<String, dynamic>> ordersQuery = FirebaseFirestore.instance
        .collection('Orders')
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .orderBy('timestamp', descending: true);
        
    if (branchIds.isNotEmpty) {
      if (branchIds.length == 1) {
        ordersQuery = ordersQuery.where('branchIds', arrayContains: branchIds.first);
      } else {
        ordersQuery = ordersQuery.where('branchIds', arrayContainsAny: branchIds.take(10).toList());
      }
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: ordersQuery.snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Center(child: CircularProgressIndicator(color: primaryColor));
        }

        final orders = snapshot.data!.docs;
        
        double totalRevenue = 0;
        int completed = 0;
        int cancelled = 0;
        Map<int, int> ordersByHour = {};
        
        for (var doc in orders) {
          final data = doc.data();
          final status = (data['status']?.toString() ?? '').toLowerCase();
          final amount = (data['totalAmount'] as num?)?.toDouble() ?? 0;
          final ts = data['timestamp'] as Timestamp?;
          
          if (status == 'cancelled' || status == 'refunded') {
            cancelled++;
          } else {
            totalRevenue += amount;
            completed++;
          }
          
          if (ts != null) {
            final h = ts.toDate().hour;
            ordersByHour[h] = (ordersByHour[h] ?? 0) + 1;
          }
        }
        
        final totalOrders = orders.length;
        final avgOrderValue = completed > 0 ? (totalRevenue / completed) : 0.0;
        final cancelRate = totalOrders > 0 ? (cancelled / totalOrders * 100) : 0.0;
        
        int peakHour = 0;
        int maxOrders = 0;
        ordersByHour.forEach((h, c) {
          if (c > maxOrders) {
            maxOrders = c;
            peakHour = h;
          }
        });
        
        // Wait for margins and stock via static futures or just show real-time stats
        // We will show: AOV, Cancel Rate, Peak Hour here. 
        // Margin/Stock will be fetched via FutureBuilder since they don't change very rapidly
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Business Performance (Today)', 
              style: TextStyle(fontSize: isMobile ? 18 : 20, fontWeight: FontWeight.bold, color: textColor)),
            const SizedBox(height: 16),
            if (isMobile)
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                   _buildStatCard('Avg Order', 'QAR ${avgOrderValue.toStringAsFixed(1)}', Icons.receipt_long, Colors.blue),
                   _buildStatCard('Cancel Rate', '${cancelRate.toStringAsFixed(1)}%', Icons.cancel_outlined, Colors.red),
                   _buildStatCard('Peak Hour', '$peakHour:00', Icons.access_time, Colors.orange),
                ].map((c) => SizedBox(width: (MediaQuery.of(context).size.width - 60) / 2, child: c)).toList(),
              )
            else
              Row(
                children: [
                  Expanded(child: _buildStatCard('Avg Order Value', 'QAR ${avgOrderValue.toStringAsFixed(1)}', Icons.receipt_long, Colors.blue)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildStatCard('Cancel Rate', '${cancelRate.toStringAsFixed(1)}%', Icons.cancel_outlined, Colors.red)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildStatCard('Peak Hour', '$peakHour:00 ($maxOrders orders)', Icons.access_time, Colors.orange)),
                ],
              ),
              
            const SizedBox(height: 24),
            _buildInventoryAndMarginPanel(),
          ],
        );
      },
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color iconColor) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: iconColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, size: 16, color: iconColor),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w600))),
            ],
          ),
          const SizedBox(height: 12),
          Text(value, style: TextStyle(fontSize: isMobile ? 18 : 22, fontWeight: FontWeight.bold, color: textColor)),
        ],
      ),
    );
  }

  // Future builder to get margin and stock levels 
  Widget _buildInventoryAndMarginPanel() {
    return FutureBuilder<List<dynamic>>(
      future: Future.wait([
        _fetchOutAndLowStock(),
        _fetchAvgMargin(),
      ]),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox(height: 60, child: Center(child: CircularProgressIndicator()));
        
        final stockInfo = snapshot.data![0] as Map<String, int>;
        final avgMargin = snapshot.data![1] as double;
        final outStock = stockInfo['out'] ?? 0;
        final lowStock = stockInfo['low'] ?? 0;

        return Row(
          children: [
            Expanded(
              child: Container(
                padding: EdgeInsets.all(isMobile ? 12 : 16),
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: primaryColor.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.inventory_2, color: primaryColor, size: isMobile ? 24 : 32),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Inventory Alerts', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: primaryColor)),
                          const SizedBox(height: 4),
                          Text('$outStock Out of Stock • $lowStock Low Stock', style: TextStyle(fontSize: isMobile ? 13 : 15, fontWeight: FontWeight.w600, color: textColor)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Container(
                padding: EdgeInsets.all(isMobile ? 12 : 16),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.trending_up, color: Colors.green, size: isMobile ? 24 : 32),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Avg Profit Margin', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green)),
                          const SizedBox(height: 4),
                          Text('${avgMargin.toStringAsFixed(1)}%', style: TextStyle(fontSize: isMobile ? 13 : 15, fontWeight: FontWeight.w600, color: textColor)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<Map<String, int>> _fetchOutAndLowStock() async {
    try {
      final snap = await FirebaseFirestore.instance.collection(AppConstants.collectionIngredients).get();

      int outStock = 0;
      int lowStock = 0;

      // Determine effective branch IDs to check
      final effectiveBranchIds = branchIds.isNotEmpty ? branchIds : ['default'];

      for (var doc in snap.docs) {
        // Enforce centralized robust validation from IngredientModel
        final ingredient = IngredientModel.fromFirestore(doc as DocumentSnapshot<Map<String, dynamic>>);

        if (ingredient.isOutOfStockInAnyBranch(effectiveBranchIds)) {
          outStock++;
        } else if (ingredient.isLowStockInAnyBranch(effectiveBranchIds)) {
          lowStock++;
        }
      }
      return {'out': outStock, 'low': lowStock};
    } catch (_) {
      return {'out': 0, 'low': 0};
    }
  }

  Future<double> _fetchAvgMargin() async {
    try {
      final menuSnap = await FirebaseFirestore.instance.collection('menu_items').get();
      final recipeSnap = await FirebaseFirestore.instance.collection(AppConstants.collectionRecipes).get();

      final Map<String, double> recipeCostMap = {};
      for (final doc in recipeSnap.docs) {
        final data = doc.data();
        final menuItemId = data['menuItemId']?.toString() ?? '';
        final cost = (data['costPerServing'] as num?)?.toDouble() ?? 0;
        if (menuItemId.isNotEmpty && cost > 0) {
          recipeCostMap[menuItemId] = cost;
        }
      }

      double totalMargin = 0;
      int itemsWithCost = 0;

      for (final doc in menuSnap.docs) {
        final data = doc.data();
        final price = (data['price'] as num?)?.toDouble() ?? 0;
        final cost = recipeCostMap[doc.id] ?? 0;
        
        if (price > 0 && cost > 0) {
          final margin = (price - cost) / price * 100;
          totalMargin += margin;
          itemsWithCost++;
        }
      }

      return itemsWithCost > 0 ? (totalMargin / itemsWithCost) : 0.0;
    } catch (_) {
      return 0.0;
    }
  }
}
