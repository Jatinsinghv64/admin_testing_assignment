import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../Widgets/RiderAssignment.dart';
import '../main.dart'; // Assuming UserScopeService is here

/// A dedicated screen for manually assigning riders to orders that
/// failed auto-assignment (status 'needs_rider_assignment').
class ManualAssignmentScreen extends StatefulWidget {
  const ManualAssignmentScreen({super.key});

  @override
  State<ManualAssignmentScreen> createState() => _ManualAssignmentScreenState();
}

class _ManualAssignmentScreenState extends State<ManualAssignmentScreen> {
  /// Opens the rider selection dialog and assigns the chosen rider.
  Future<void> _promptAssignRider(
      BuildContext context, String orderId, String currentBranchId) async {
    if (!mounted) return;

    final riderId = await showDialog<String>(
      context: context,
      // Use the beautiful, professional, and fixed dialog
      builder: (context) =>
          RiderSelectionDialog(currentBranchId: currentBranchId),
    );

    if (riderId != null && riderId.isNotEmpty) {
      if (!mounted) return;
      // Use the static method from RiderAssignmentService
      await RiderAssignmentService.manualAssignRider(
        orderId: orderId,
        riderId: riderId,
        context: context, // Pass the context for SnackBars
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final userScope = context.read<UserScopeService>();

    // --- Add date filter for "current day" ---
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final endOfToday = startOfToday.add(const Duration(days: 1));

    // Base query for orders needing assignment
    Query query = FirebaseFirestore.instance
        .collection('Orders')
        .where('status', isEqualTo: 'needs_rider_assignment')
    // --- FIX: Query on 'timestamp' instead of 'needsAssignmentAt' ---
        .where('timestamp', isGreaterThanOrEqualTo: startOfToday)
        .where('timestamp', isLessThan: endOfToday);

    // Filter by branch for non-super admins
    if (!userScope.isSuperAdmin) {
      query = query.where('branchIds', arrayContains: userScope.branchId);
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 1,
        shadowColor: Colors.deepPurple.withOpacity(0.1),
        backgroundColor: Colors.white,
        centerTitle: true,
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
        // --- FIX: Removed the .orderBy() to avoid needing a composite index ---
        // We will sort the results manually in the builder.
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
                    const SizedBox(height: 8),
                    const Text(
                      'This might be due to a missing Firestore index. Please check your debug console for a link to create it.',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
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
                    "No orders need manual assignment for today.",
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

          // --- FIX: Sort the documents in-memory ---
          // This avoids the complex Firestore index requirement
          // by sorting after the data is fetched.
          try {
            docs.sort((a, b) {
              final aData = a.data();
              final bData = b.data();

              // --- FIX: Sort by 'timestamp' ---
              final aTimestamp =
              (aData['timestamp'] as Timestamp?)?.toDate();
              final bTimestamp =
              (bData['timestamp'] as Timestamp?)?.toDate();

              // Handle nulls
              if (aTimestamp == null && bTimestamp == null) return 0;
              if (aTimestamp == null) return 1; // Put nulls at the end
              if (bTimestamp == null) return -1; // Keep non-nulls at the start

              // Sort descending (newest first)
              return bTimestamp.compareTo(aTimestamp);
            });
          } catch (e) {
            // Handle potential sort error (e.g., bad data)
            debugPrint("Error sorting documents: $e");
          }
          // --- End of FIX ---

          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 16),
            itemBuilder: (context, index) {
              final orderDoc = docs[index];
              final data = orderDoc.data();
              final orderNumber = data['dailyOrderNumber']?.toString() ??
                  orderDoc.id.substring(0, 6).toUpperCase();
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
                    crossAxisAlignment:
                    CrossAxisAlignment.start, // Fixed typo here
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
                          onPressed: () => _promptAssignRider(
                            context,
                            orderDoc.id,
                            userScope.branchId,
                          ),
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
}

// -----------------------------------------------------------------------------
// Professional Rider Selection Dialog
// -----------------------------------------------------------------------------

class RiderSelectionDialog extends StatelessWidget {
  final String currentBranchId;

  const RiderSelectionDialog({super.key, required this.currentBranchId});

  @override
  Widget build(BuildContext context) {
    // Build the branch-aware query for available drivers
    Query query = FirebaseFirestore.instance
        .collection('Drivers')
        .where('isAvailable', isEqualTo: true)
        .where('status', isEqualTo: 'online');

    // Filter by branch
    if (currentBranchId.isNotEmpty) {
      query = query.where('branchIds', arrayContains: currentBranchId);
    }

    return AlertDialog(
      // --- FIX: Add shape for professional look ---
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
      // --- FIX: Add fixed height container to prevent overflow ---
      Container(
        width: double.maxFinite,
        height: 300, // Set a fixed height for the list
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
            // Use ListView instead of ListView.builder for smaller lists
            // to avoid potential layout issues with constraints.
            return ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              // shrinkWrap: true, // Not needed with fixed height
              children: drivers.map((driverDoc) {
                final data = driverDoc.data() as Map<String, dynamic>;
                final String name = data['name'] ?? 'Unnamed Driver';
                // --- FIX: Handle int or String for phone ---
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
                      CrossAxisAlignment.start, // Fixed typo here
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