import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../Widgets/RiderAssignment.dart';
import '../main.dart'; // Assuming UserScopeService is here

class ManualAssignmentScreen extends StatefulWidget {
  const ManualAssignmentScreen({Key? key}) : super(key: key);

  @override
  State<ManualAssignmentScreen> createState() => _ManualAssignmentScreenState();
}

class _ManualAssignmentScreenState extends State<ManualAssignmentScreen> {

  Future<void> _assignRider(String orderId) async {
    final scope = Provider.of<UserScopeService>(context, listen: false);

    final String? riderId = await showDialog<String>(
      context: context,
      builder: (ctx) => _RiderSelectionDialog(branchId: scope.branchId),
    );

    if (riderId != null && mounted) {
      try {
        final db = FirebaseFirestore.instance;
        final batch = db.batch();

        // Update Order
        batch.update(db.collection('Orders').doc(orderId), {
          'riderId': riderId,
          'status': 'rider_assigned',
          'timestamps.riderAssigned': FieldValue.serverTimestamp(),
          'autoAssignStarted': FieldValue.delete(),
          'assignmentNotes': 'Manually assigned from Manual Screen',
        });

        // Update Driver
        batch.update(db.collection('Drivers').doc(riderId), {
          'assignedOrderId': orderId,
          'isAvailable': false,
        });

        await batch.commit();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rider assigned successfully!'), backgroundColor: Colors.green),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = Provider.of<UserScopeService>(context);

    Query query = FirebaseFirestore.instance
        .collection('Orders')
        .where('status', isEqualTo: 'needs_rider_assignment');

    if (!scope.isSuperAdmin) {
      query = query.where('branchIds', arrayContains: scope.branchId);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Manual Assignment"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.deepPurple,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: query.orderBy('timestamp', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle, size: 64, color: Colors.green.withOpacity(0.5)),
                  const SizedBox(height: 16),
                  const Text("No pending manual assignments", style: TextStyle(color: Colors.grey, fontSize: 16)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final orderId = docs[index].id;
              final timestamp = (data['timestamp'] as Timestamp?)?.toDate();

              return Card(
                elevation: 3,
                margin: const EdgeInsets.only(bottom: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "Order #${data['dailyOrderNumber'] ?? '---'}",
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                                color: Colors.red.shade100,
                                borderRadius: BorderRadius.circular(8)
                            ),
                            child: const Text("Needs Assignment", style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold)),
                          )
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text("Customer: ${data['customerName'] ?? 'N/A'}"),
                      Text("Time: ${timestamp != null ? DateFormat('hh:mm a').format(timestamp) : '--:--'}"),
                      if(data['assignmentNotes'] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text("Note: ${data['assignmentNotes']}", style: const TextStyle(color: Colors.red, fontSize: 12, fontStyle: FontStyle.italic)),
                        ),
                      const Divider(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.person_add),
                          label: const Text("Assign Rider Now"),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepPurple,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12)
                          ),
                          onPressed: () => _assignRider(orderId),
                        ),
                      )
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
}

// ✅ FIXED: REPLACED ROW WITH WRAP TO FIX OVERFLOW
class _RiderSelectionDialog extends StatelessWidget {
  final String branchId;
  const _RiderSelectionDialog({required this.branchId});

  @override
  Widget build(BuildContext context) {
    Query query = FirebaseFirestore.instance.collection('Drivers')
        .where('isAvailable', isEqualTo: true)
        .where('status', isEqualTo: 'online');

    if (branchId.isNotEmpty) {
      query = query.where('branchIds', arrayContains: branchId);
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 10,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 500, maxWidth: 400),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ✅ FIXED HEADER ROW
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.delivery_dining, color: Colors.deepPurple, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: const Text(
                    "Select Delivery Rider",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                )
              ],
            ),
            const SizedBox(height: 4),
            const Divider(),
            const SizedBox(height: 8),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: query.snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.data!.docs.isEmpty) {
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.person_off_outlined, size: 48, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        const Text("No riders available online", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500)),
                      ],
                    );
                  }

                  return ListView.separated(
                    itemCount: snapshot.data!.docs.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final driver = snapshot.data!.docs[index];
                      final data = driver.data() as Map<String, dynamic>;
                      // Safe parsing
                      final name = data['name']?.toString() ?? 'Unknown Driver';
                      final phone = data['phone']?.toString() ?? 'No Phone';
                      final vehicle = data['vehicle']?['type']?.toString() ?? 'Bike';

                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => Navigator.of(context).pop(driver.id),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade200),
                              borderRadius: BorderRadius.circular(12),
                              color: Colors.grey.shade50,
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: Colors.deepPurple.shade100,
                                  child: Text(
                                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                                    style: const TextStyle(color: Colors.deepPurple, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                      const SizedBox(height: 4),
                                      // ✅ FIXED: Using Wrap instead of Row
                                      Wrap(
                                        spacing: 12,
                                        runSpacing: 4,
                                        children: [
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.phone, size: 12, color: Colors.grey.shade600),
                                              const SizedBox(width: 4),
                                              Text(phone, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                                            ],
                                          ),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.directions_bike, size: 12, color: Colors.grey.shade600),
                                              const SizedBox(width: 4),
                                              Text(vehicle, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade50,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(Icons.check, color: Colors.green.shade600, size: 18),
                                )
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}