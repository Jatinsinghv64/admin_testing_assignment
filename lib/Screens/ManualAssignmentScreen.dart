import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../Widgets/RiderAssignment.dart';
import '../Widgets/BranchFilterService.dart'; // ✅ Added for filtering
import '../main.dart'; // Assuming UserScopeService is here
import '../constants.dart'; // For OrderNumberHelper

class ManualAssignmentScreen extends StatefulWidget {
  const ManualAssignmentScreen({super.key});

  @override
  State<ManualAssignmentScreen> createState() => _ManualAssignmentScreenState();
}

class _ManualAssignmentScreenState extends State<ManualAssignmentScreen> {
  Future<void> _promptAssignRider(
      BuildContext context, String orderId, String currentBranchId) async {
    if (!mounted) return;
    
    // Capture ScaffoldMessengerState BEFORE async operations
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    final riderId = await showDialog<String>(
      context: context,
      builder: (dialogContext) =>
          RiderSelectionDialog(currentBranchId: currentBranchId),
    );

    if (riderId != null && riderId.isNotEmpty) {
      if (!mounted) return;
      
      final result = await RiderAssignmentService.manualAssignRider(
        orderId: orderId,
        riderId: riderId,
      );
      
      // Use pre-captured ScaffoldMessengerState (safe across async gaps)
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: result.backgroundColor,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final userScope = context.watch<UserScopeService>(); // ✅ Added userScope
    final branchFilter = context.watch<BranchFilterService>();

    // Load branch names if needed
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (userScope.branchIds.length > 1 && !branchFilter.isLoaded) {
        branchFilter.loadBranchNames(userScope.branchIds);
      }
    });

    // ✅ FIX: REMOVED DATE FILTER
    // This ensures the screen displays ALL orders that need assignment,
    // matching the Badge Count and preventing hidden tasks.
    // ✅ FIX: Added Order_type filter - only delivery orders need rider assignment
    Query query = FirebaseFirestore.instance
        .collection('Orders')
        .where('status', isEqualTo: 'needs_rider_assignment')
        .where('Order_type', isEqualTo: 'delivery');

    // Filter by branch logic (BranchAdmin OR SuperAdmin with selection)
    final filterBranchIds = branchFilter.getFilterBranchIds(userScope.branchIds);
    
    if (userScope.isSuperAdmin && userScope.branchIds.isEmpty) {
       // Show all
    } else if (filterBranchIds.isNotEmpty) {
      query = query.where('branchIds', arrayContainsAny: filterBranchIds);
    } else if (!userScope.isSuperAdmin) {
       // Should be covered above, but safe fallback
       query = query.where('branchIds', arrayContains: userScope.branchId);
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 1,
        shadowColor: Colors.deepPurple.withOpacity(0.1),
        backgroundColor: Colors.white,
        centerTitle: !(userScope.branchIds.length > 1), // Center if no selector
        actions: [
          if (userScope.branchIds.length > 1)
             _buildBranchSelector(userScope, branchFilter),
        ],
        title: const Text(
          'Manual Rider Assignment',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.deepPurple,
            fontSize: 22,
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: query.snapshots()
        as Stream<QuerySnapshot<Map<String, dynamic>>>,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(Colors.deepPurple),
                ));
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline,
                        size: 48, color: Colors.red[300]),
                    const SizedBox(height: 16),
                    const Text(
                      'An Error Occurred',
                      style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${snapshot.error}',
                      style: TextStyle(color: Colors.red[700]),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_outline,
                      size: 64, color: Colors.green[400]),
                  const SizedBox(height: 16),
                  Text(
                    'All Caught Up!',
                    style: TextStyle(
                      color: Colors.grey[800],
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "No orders need manual assignment.",
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            );
          }

          final docs = snapshot.data!.docs;

          // Sort in-memory (Newest first)
          try {
            docs.sort((a, b) {
              final aData = a.data();
              final bData = b.data();
              final aTimestamp = (aData['timestamp'] as Timestamp?)?.toDate();
              final bTimestamp = (bData['timestamp'] as Timestamp?)?.toDate();
              if (aTimestamp == null && bTimestamp == null) return 0;
              if (aTimestamp == null) return 1;
              if (bTimestamp == null) return -1;
              return bTimestamp.compareTo(aTimestamp);
            });
          } catch (e) {
            debugPrint("Error sorting documents: $e");
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 16),
            itemBuilder: (context, index) {
              final orderDoc = docs[index];
              final data = orderDoc.data();
              final orderNumber = OrderNumberHelper.getDisplayNumber(data, orderId: orderDoc.id);
              final timestamp = (data['timestamp'] as Timestamp?)?.toDate();
              final reason = data['assignmentNotes'] ?? 'No reason provided';
              final customerName = data['customerName'] ?? 'N/A';
              final totalAmount =
                  (data['totalAmount'] as num?)?.toDouble() ?? 0.0;

              return Card(
                elevation: 2,
                shadowColor: Colors.deepPurple.withOpacity(0.05),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Order #$orderNumber',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 17,
                              color: Colors.deepPurple,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: Colors.orange.withOpacity(0.5)),
                            ),
                            child: const Text(
                              'NEEDS ASSIGN',
                              style: TextStyle(
                                color: Colors.orange,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        timestamp != null
                            ? DateFormat('MMM dd, yyyy hh:mm a')
                            .format(timestamp)
                            : 'No date',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                      const Divider(height: 24),
                      _buildDetailRow(Icons.person_outline, 'Customer:',
                          customerName,
                          valueColor: Colors.black87),
                      _buildDetailRow(Icons.account_balance_wallet_outlined,
                          'Total:', 'QAR ${totalAmount.toStringAsFixed(2)}',
                          valueColor: Colors.green.shade700),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(12),
                          border:
                          Border.all(color: Colors.red.withOpacity(0.1)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'REASON FOR MANUAL ASSIGNMENT:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                                color: Colors.red,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              reason,
                              style: const TextStyle(
                                  fontSize: 13, color: Colors.black87),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.delivery_dining, size: 18),
                          label: const Text('Assign Rider Manually'),
                          onPressed: () {
                            // Fix: Use order's branch ID, not user's current branch
                            final orderBranchId = data['branchId']?.toString() ?? 
                                (data['branchIds'] is List && (data['branchIds'] as List).isNotEmpty 
                                    ? data['branchIds'][0].toString() 
                                    : null);
                            
                            _promptAssignRider(
                              context,
                              orderDoc.id,
                              orderBranchId ?? userScope.branchId ?? '',
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepPurple,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value,
      {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.deepPurple.shade300),
          const SizedBox(width: 10),
          Text(
            label,
            style:
            TextStyle(fontSize: 13, color: Colors.grey[700], height: 1.4),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: valueColor ?? Colors.black87,
                  height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  // Same branch selector logic
  Widget _buildBranchSelector(UserScopeService userScope, BranchFilterService branchFilter) {
    return Container(
      margin: const EdgeInsets.only(right: 12),
      child: PopupMenuButton<String>(
        offset: const Offset(0, 45),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.deepPurple.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.deepPurple.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.store, size: 18, color: Colors.deepPurple),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 100),
                child: Text(
                  branchFilter.selectedBranchId == null
                      ? 'All Branches'
                      : branchFilter.getBranchName(branchFilter.selectedBranchId!),
                  style: const TextStyle(
                    color: Colors.deepPurple,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.arrow_drop_down, color: Colors.deepPurple, size: 20),
            ],
          ),
        ),
        itemBuilder: (context) => [
          PopupMenuItem<String>(
            value: BranchFilterService.allBranchesValue,
            child: Row(children: [
               Icon(branchFilter.selectedBranchId == null ? Icons.check_circle : Icons.circle_outlined, size:18, color: branchFilter.selectedBranchId == null ? Colors.deepPurple : Colors.grey),
               const SizedBox(width: 10),
               const Text('All Branches'),
            ]),
          ),
          const PopupMenuDivider(),
          ...userScope.branchIds.map((branchId) => PopupMenuItem<String>(
            value: branchId,
            child: Row(children: [
               Icon(branchFilter.selectedBranchId == branchId ? Icons.check_circle : Icons.circle_outlined, size:18, color: branchFilter.selectedBranchId == branchId ? Colors.deepPurple : Colors.grey),
               const SizedBox(width: 10),
               Flexible(child: Text(branchFilter.getBranchName(branchId), overflow: TextOverflow.ellipsis)),
            ]),
          )),
        ],
        onSelected: (value) => branchFilter.selectBranch(value),
      ),
    );
  } 
}

class RiderSelectionDialog extends StatelessWidget {
  final String currentBranchId;

  const RiderSelectionDialog({super.key, required this.currentBranchId});

  @override
  Widget build(BuildContext context) {
    Query query = FirebaseFirestore.instance
        .collection('Drivers')
        .where('isAvailable', isEqualTo: true)
        .where('status', isEqualTo: 'online');

    if (currentBranchId.isNotEmpty) {
      query = query.where('branchIds', arrayContains: currentBranchId);
    }

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(0, 16, 0, 16),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      title: const Row(
        children: [
          Icon(Icons.delivery_dining_outlined, color: Colors.deepPurple),
          SizedBox(width: 10),
          Text(
            'Select Available Rider',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content:
      Container(
        width: double.maxFinite,
        height: 300,
        child: StreamBuilder<QuerySnapshot>(
          stream: query.snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(Colors.deepPurple),
                ),
              );
            }
            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline,
                        size: 48, color: Colors.red[300]),
                    const SizedBox(height: 16),
                    Text(
                      'Error loading riders: ${snapshot.error}',
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            }
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.person_off_outlined,
                        size: 48, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    const Text(
                      'No available riders found',
                      style: TextStyle(
                          color: Colors.grey,
                          fontSize: 15,
                          fontWeight: FontWeight.w500),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'All riders are currently busy or offline.',
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            }

            final drivers = snapshot.data!.docs;
            return ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: drivers.map((driverDoc) {
                final data = driverDoc.data() as Map<String, dynamic>;
                final String name = data['name'] ?? 'Unnamed Driver';
                final String phone = data['phone']?.toString() ?? 'No phone';
                final String vehicle =
                    data['vehicle']?['type'] ?? 'No vehicle';

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 5),
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey[200]!),
                  ),
                  child: ListTile(
                    contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: CircleAvatar(
                      backgroundColor: Colors.deepPurple.withOpacity(0.1),
                      child: const Icon(
                        Icons.person,
                        color: Colors.deepPurple,
                      ),
                    ),
                    title: Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,
                      children: [
                        Text(
                          phone,
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey.shade700),
                        ),
                        Text(
                          vehicle,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Available',
                        style: TextStyle(
                          color: Colors.green,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    onTap: () {
                      Navigator.of(context).pop(driverDoc.id);
                    },
                  ),
                );
              }).toList(),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            'Cancel',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      ],
    );
  }
}