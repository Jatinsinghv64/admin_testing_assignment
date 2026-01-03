import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../main.dart'; // For UserScopeService
import '../Widgets/PrintingService.dart'; // ✅ Functional Printing
import '../Widgets/TimeUtils.dart'; // ✅ Timezone Consistency

class DashboardScreen extends StatelessWidget {
  final Function(int) onTabChange;

  const DashboardScreen({super.key, required this.onTabChange});

  /// ✅ ROBUSTNESS: Calculates the start of the "Business Day" (6:00 AM)
  /// This ensures that orders placed at 1 AM count towards the "previous" day's shift.
  Timestamp _getBusinessStartTimestamp() {
    // 1. Get current time (Preferably from TimeUtils if available, else local safe fallback)
    final now = DateTime.now();

    // 2. Shift logic: If it's before 6:00 AM, subtract a day.
    DateTime effectiveDate = now;
    if (now.hour < 6) {
      effectiveDate = now.subtract(const Duration(days: 1));
    }

    // 3. Create the 6:00 AM cutoff time
    final startOfBusinessDay = DateTime(
        effectiveDate.year,
        effectiveDate.month,
        effectiveDate.day,
        6, 0, 0
    );

    return Timestamp.fromDate(startOfBusinessDay);
  }

  /// ✅ SECURITY: Filters queries by Branch ID (unless Super Admin)
  Query<Map<String, dynamic>> _applyBranchFilter(Query<Map<String, dynamic>> query, BuildContext context) {
    final userScope = context.read<UserScopeService>();
    if (userScope.isSuperAdmin) {
      return query; // Super Admin sees all data
    }
    // Standard Admin: Only see data containing their assigned branchId
    return query.where('branchIds', arrayContains: userScope.branchId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        centerTitle: true,
        title: const Text(
          'Dashboard',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.deepPurple,
            fontSize: 24,
          ),
        ),
      ),
      // ✅ UX: RefreshIndicator allows recovering from network glitches
      body: RefreshIndicator(
        onRefresh: () async {
          // Add a slight delay to simulate/allow stream reconnection
          await Future.delayed(const Duration(milliseconds: 500));
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildEnhancedStatCardsGrid(context),
              const SizedBox(height: 32),
              _buildSectionHeader(
                  'Recent Orders (Current Shift)', Icons.receipt_long_outlined),
              const SizedBox(height: 16),
              _buildEnhancedRecentOrdersSection(context),
              const SizedBox(height: 40), // Extra scrolling space
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.deepPurple.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: Colors.deepPurple, size: 20),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.deepPurple,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // STATS GRID
  // ---------------------------------------------------------------------------
  Widget _buildEnhancedStatCardsGrid(BuildContext context) {
    final Timestamp startOfShift = _getBusinessStartTimestamp();

    // 1. Prepare Base Queries
    Query<Map<String, dynamic>> ordersQuery = FirebaseFirestore.instance
        .collection('Orders')
        .where('timestamp', isGreaterThanOrEqualTo: startOfShift);

    Query<Map<String, dynamic>> driversQuery = FirebaseFirestore.instance
        .collection('Drivers')
        .where('isAvailable', isEqualTo: true)
        .where('status', isEqualTo: 'online'); // Only show ONLINE drivers

    Query<Map<String, dynamic>> menuQuery = FirebaseFirestore.instance
        .collection('menu_items'); // Assuming global menu, modify if branch-specific

    // 2. Apply Branch Security
    ordersQuery = _applyBranchFilter(ordersQuery, context);
    driversQuery = _applyBranchFilter(driversQuery, context);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            children: [
              // --- STAT 1: TODAY'S ORDERS ---
              Expanded(
                child: _buildStatCardWrapper(
                  stream: ordersQuery.snapshots(),
                  builder: (context, snapshot) {
                    final count = snapshot.hasData ? snapshot.data!.docs.length : 0;
                    return _EnhancedStatCard(
                      title: "Today's Orders",
                      value: count.toString(),
                      icon: Icons.shopping_bag_outlined,
                      color: Colors.blueAccent,
                      onTap: () => onTabChange(2), // Navigate to Orders Tab
                    );
                  },
                ),
              ),
              const SizedBox(width: 16),

              // --- STAT 2: ACTIVE RIDERS ---
              Expanded(
                child: _buildStatCardWrapper(
                  stream: driversQuery.snapshots(),
                  builder: (context, snapshot) {
                    final count = snapshot.hasData ? snapshot.data!.docs.length : 0;
                    return _EnhancedStatCard(
                      title: 'Active Riders',
                      value: count.toString(),
                      icon: Icons.delivery_dining_outlined,
                      color: Colors.green,
                      onTap: () => onTabChange(3), // Navigate to Riders Tab
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              // --- STAT 3: REVENUE ---
              Expanded(
                child: _buildStatCardWrapper(
                  stream: ordersQuery.snapshots(), // Reuse orders query for revenue
                  builder: (context, snapshot) {
                    double totalRevenue = 0;
                    if (snapshot.hasData) {
                      // Statuses that count as "Money Earned"
                      final billableStatuses = {
                        'delivered',
                        'pickedup',
                        'completed',
                        'paid',
                        'prepared' // Includes served items in dine-in
                      };

                      for (var doc in snapshot.data!.docs) {
                        final data = doc.data();
                        final status = (data['status'] ?? '').toString();

                        // Safe Calculation
                        if (billableStatuses.contains(status.toLowerCase()) ||
                            (status == 'served' && data['Order_type'] == 'dine_in')
                        ) {
                          totalRevenue += (data['totalAmount'] as num? ?? 0).toDouble();
                        }
                      }
                    }
                    return _EnhancedStatCard(
                      title: 'Revenue',
                      value: 'QAR ${totalRevenue.toStringAsFixed(0)}',
                      icon: Icons.attach_money_outlined,
                      color: Colors.orangeAccent,
                      onTap: () => onTabChange(2),
                    );
                  },
                ),
              ),
              const SizedBox(width: 16),

              // --- STAT 4: MENU ITEMS ---
              Expanded(
                child: _buildStatCardWrapper(
                  stream: menuQuery.snapshots(),
                  builder: (context, snapshot) {
                    final count = snapshot.hasData ? snapshot.data!.docs.length : 0;
                    return _EnhancedStatCard(
                      title: 'Menu Items',
                      value: count.toString(),
                      icon: Icons.restaurant_menu,
                      color: Colors.purpleAccent,
                      onTap: () => onTabChange(1), // Navigate to Menu Tab
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCardWrapper({
    required Stream<QuerySnapshot<Map<String, dynamic>>> stream,
    required Widget Function(BuildContext, AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>>) builder,
  }) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _EnhancedLoadingStatCard();
        }
        if (snapshot.hasError) {
          // Log error but don't crash UI
          debugPrint("Dashboard Stream Error: ${snapshot.error}");
          return const _EnhancedErrorStatCard(errorMessage: 'Data Error');
        }
        return builder(context, snapshot);
      },
    );
  }

  // ---------------------------------------------------------------------------
  // RECENT ORDERS LIST
  // ---------------------------------------------------------------------------
  Widget _buildEnhancedRecentOrdersSection(BuildContext context) {
    final Timestamp startOfShift = _getBusinessStartTimestamp();

    // 1. Base Query
    Query<Map<String, dynamic>> recentOrdersQuery = FirebaseFirestore.instance
        .collection('Orders')
        .where('timestamp', isGreaterThanOrEqualTo: startOfShift);

    // 2. Apply Branch Filter
    recentOrdersQuery = _applyBranchFilter(recentOrdersQuery, context);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Icon(Icons.access_time_rounded, color: Colors.deepPurple.shade400, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Latest Activity',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87),
                  ),
                ),
                TextButton(
                  onPressed: () => onTabChange(2),
                  child: const Text('View All'),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.grey[200]),

          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 400, minHeight: 100),
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: recentOrdersQuery
                  .orderBy('timestamp', descending: true)
                  .limit(5)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text("Error: ${snapshot.error}", style: const TextStyle(color: Colors.red)));
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return _buildEmptyState();
                }

                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(), // Let parent scroll
                  padding: const EdgeInsets.all(16),
                  itemCount: snapshot.data!.docs.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    return _EnhancedOrderListItem(order: snapshot.data!.docs[index]);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text(
            'No orders yet today',
            style: TextStyle(color: Colors.grey[500], fontSize: 16),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SUB-WIDGETS (UI Components)
// ---------------------------------------------------------------------------

class _EnhancedStatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _EnhancedStatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 130,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.85), color],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(8)),
                      child: Icon(icon, size: 20, color: Colors.white),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        value,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.9)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
}

class _EnhancedLoadingStatCard extends StatelessWidget {
  const _EnhancedLoadingStatCard();
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 130,
      decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(16)),
      child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }
}

class _EnhancedErrorStatCard extends StatelessWidget {
  final String errorMessage;
  const _EnhancedErrorStatCard({required this.errorMessage});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 130,
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red[100]!),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red[300]),
            Text(errorMessage, style: TextStyle(color: Colors.red[400], fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

class _EnhancedOrderListItem extends StatelessWidget {
  final DocumentSnapshot order;
  const _EnhancedOrderListItem({required this.order});

  void _showOrderPopup(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => _OrderPopupDialog(order: order),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ✅ ROBUSTNESS: Safe parsing of optional fields
    final data = order.data() as Map<String, dynamic>? ?? {};

    final String displayId = data['dailyOrderNumber']?.toString() ?? order.id.substring(0, 4).toUpperCase();
    final String status = data['status']?.toString() ?? 'unknown';
    final double amount = (data['totalAmount'] as num? ?? 0.0).toDouble();
    final String type = (data['Order_type'] as String?)?.toUpperCase().replaceAll('_', ' ') ?? 'ORDER';

    String timeString = "Just now";
    if (data['timestamp'] != null) {
      final date = (data['timestamp'] as Timestamp).toDate();
      timeString = DateFormat('hh:mm a').format(date);
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showOrderPopup(context),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _getStatusColor(status),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text("#$displayId", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(4)),
                            child: Text(type, style: const TextStyle(fontSize: 9, color: Colors.black54)),
                          )
                        ],
                      ),
                      Text(timeString, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    ],
                  ),
                ),

                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text("QAR ${amount.toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                    Text(
                      status.toUpperCase(),
                      style: TextStyle(fontSize: 10, color: _getStatusColor(status), fontWeight: FontWeight.bold),
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

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending': return Colors.orange;
      case 'preparing': return Colors.teal;
      case 'prepared': return Colors.blue;
      case 'delivered': return Colors.green;
      case 'pickedup': return Colors.green;
      case 'cancelled': return Colors.red;
      default: return Colors.grey;
    }
  }
}

// ---------------------------------------------------------------------------
// ORDER DETAILS POPUP (With Functional Print)
// ---------------------------------------------------------------------------

class _OrderPopupDialog extends StatelessWidget {
  final DocumentSnapshot order;
  const _OrderPopupDialog({required this.order});

  @override
  Widget build(BuildContext context) {
    final data = order.data() as Map<String, dynamic>? ?? {};
    final double total = (data['totalAmount'] as num? ?? 0).toDouble();
    final items = List.from(data['items'] ?? []);
    final String orderId = data['dailyOrderNumber']?.toString() ?? order.id.substring(0, 6);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Order #$orderId", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                ],
              ),
              const Divider(),

              // Items List
              if (items.isEmpty)
                const Padding(padding: EdgeInsets.all(8), child: Text("No items found.")),

              ...items.map((item) {
                final i = item as Map<String, dynamic>;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(child: Text("${i['name']} x${i['quantity'] ?? 1}", style: const TextStyle(fontSize: 14))),
                      Text("QAR ${((i['price'] ?? 0) * (i['quantity'] ?? 1)).toStringAsFixed(2)}", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                    ],
                  ),
                );
              }),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Total", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  Text("QAR ${total.toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              const SizedBox(height: 24),

              // ✅ FUNCTIONAL PRINT BUTTON
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.print, size: 18),
                  label: const Text("Print Receipt"),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () async {
                    // Call the Printing Service safely
                    Navigator.pop(context); // Close popup first
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Preparing Receipt..."), duration: Duration(seconds: 1)));
                    await PrintingService.printReceipt(context, order);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}




class _RiderSelectionDialog extends StatelessWidget {
  final String? currentBranchId;

  const _RiderSelectionDialog({required this.currentBranchId});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'Select Driver',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('Drivers')
              .where('isAvailable', isEqualTo: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }

            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return const Center(child: Text('No available drivers found.'));
            }

            final filteredDrivers = snapshot.data!.docs.where((driver) {
              final data = driver.data() as Map<String, dynamic>;
              final driverBranchIds =
              List<String>.from(data['branchIds'] ?? []);
              if (currentBranchId == null) return true;
              return driverBranchIds.contains(currentBranchId);
            }).toList();

            if (filteredDrivers.isEmpty) {
              return const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.person_off, size: 48, color: Colors.grey),
                    SizedBox(height: 8),
                    Text('No drivers available\nfor your branch',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey)),
                  ],
                ),
              );
            }

            return ListView.separated(
              shrinkWrap: true,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemCount: filteredDrivers.length,
              itemBuilder: (context, index) {
                var driver = filteredDrivers[index];
                var data = driver.data() as Map<String, dynamic>;
                final driverId = driver.id;
                final String name = data['name'] ?? 'Unnamed Driver';
                final String status = data['status'] ?? 'offline';

                return Card(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                  color: Colors.grey.shade50,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    leading: CircleAvatar(child: Icon(Icons.person)),
                    title: Text(name,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(status),
                    onTap: () => Navigator.pop(context, driverId),
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.red))),
      ],
    );
  }
}

class _CancellationReasonDialog extends StatefulWidget {
  const _CancellationReasonDialog();

  @override
  State<_CancellationReasonDialog> createState() =>
      _CancellationReasonDialogState();
}

class _CancellationReasonDialogState extends State<_CancellationReasonDialog> {
  String? _selectedReason;
  final TextEditingController _otherReasonController = TextEditingController();
  final List<String> _reasons = [
    'Items Out of Stock',
    'Kitchen Too Busy',
    'Closing Soon / Closed',
    'Invalid Address',
    'Customer Request',
    'Other'
  ];

  @override
  void dispose() {
    _otherReasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isOther = _selectedReason == 'Other';
    final bool isValid = _selectedReason != null &&
        (!isOther || _otherReasonController.text.trim().isNotEmpty);

    return AlertDialog(
      title: const Text('Cancel Order',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Please select a reason for cancellation:'),
            const SizedBox(height: 10),
            ..._reasons.map((reason) => RadioListTile<String>(
              title: Text(reason),
              value: reason,
              groupValue: _selectedReason,
              onChanged: (value) {
                setState(() {
                  _selectedReason = value;
                });
              },
              contentPadding: EdgeInsets.zero,
              activeColor: Colors.red,
            )),
            if (isOther)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: TextField(
                  controller: _otherReasonController,
                  decoration: const InputDecoration(
                    labelText: 'Enter reason',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Close', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: isValid
              ? () {
            String finalReason = _selectedReason!;
            if (finalReason == 'Other') {
              finalReason = _otherReasonController.text.trim();
            }
            Navigator.pop(context, finalReason);
          }
              : null,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          child: const Text('Confirm Cancel'),
        ),
      ],
    );
  }
}