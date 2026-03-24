import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../Widgets/BranchFilterService.dart';
import '../Widgets/RiderAssignment.dart';
import '../Widgets/CancellationDialog.dart'; // Ensure this exists or use the dialog code
import '../constants.dart';
import '../main.dart'; // UserScopeService

class ManualAssignmentScreenLarge extends StatefulWidget {
  const ManualAssignmentScreenLarge({super.key});

  @override
  State<ManualAssignmentScreenLarge> createState() =>
      _ManualAssignmentScreenLargeState();
}

class _ManualAssignmentScreenLargeState
    extends State<ManualAssignmentScreenLarge> {
  String? _selectedOrderId;
  DocumentSnapshot? _selectedOrderDoc;

  @override
  Widget build(BuildContext context) {
    final userScope = context.watch<UserScopeService>();
    final branchFilter = context.watch<BranchFilterService>();

    // Load branch names if needed (similar to mobile)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (userScope.branchIds.length > 1 && !branchFilter.isLoaded) {
        branchFilter.loadBranchNames(userScope.branchIds);
      }
    });

    // Query for "needs_rider_assignment"
    Query query = FirebaseFirestore.instance
        .collection('Orders')
        .where('status', isEqualTo: 'needs_rider_assignment')
        .where('Order_type', isEqualTo: 'delivery')
        .orderBy('timestamp', descending: true);

    final filterBranchIds =
        branchFilter.getFilterBranchIds(userScope.branchIds);

    if (userScope.isSuperAdmin && userScope.branchIds.isEmpty) {
      // Show all
    } else if (filterBranchIds.isNotEmpty) {
      query = query.where('branchIds', arrayContainsAny: filterBranchIds);
    } else if (!userScope.isSuperAdmin && userScope.branchIds.isNotEmpty) {
      query = query.where('branchIds', arrayContainsAny: userScope.branchIds);
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Row(
        children: [
          // LEFT PANE: Orders List
          Container(
            width: 400,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(right: BorderSide(color: Colors.grey[200]!)),
            ),
            child: Column(
              children: [
                _buildHeader(userScope, branchFilter),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: query.snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(child: Text('Error: ${snapshot.error}'));
                      }
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final allDocs = snapshot.data!.docs;
                      // Filter for TODAY logic (same as mobile)
                      final now = DateTime.now();
                      final startOfDay = DateTime(now.year, now.month, now.day);
                      final docs = allDocs.where((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final timestamp = data['timestamp'] as Timestamp?;
                        if (timestamp == null) return false;
                        return timestamp.toDate().isAfter(startOfDay) ||
                            timestamp.toDate().isAtSameMomentAs(startOfDay);
                      }).toList();

                      // Sort Newest First (locally if needed, though query sets it)
                      // Ideally keep query order if possible, but local sort is safer for filtered list.
                      docs.sort((a, b) {
                        final tA = (a['timestamp'] as Timestamp?)?.toDate();
                        final tB = (b['timestamp'] as Timestamp?)?.toDate();
                        if (tA == null) return 1;
                        if (tB == null) return -1;
                        return tB.compareTo(tA);
                      });

                      if (docs.isEmpty) {
                        return const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_circle_outline,
                                  size: 48, color: Colors.green),
                              SizedBox(height: 16),
                              Text('No pending assignments'),
                            ],
                          ),
                        );
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: docs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final doc = docs[index];
                          final isSelected = doc.id == _selectedOrderId;
                          return _OrderListTile(
                            doc: doc,
                            isSelected: isSelected,
                            onTap: () {
                              setState(() {
                                _selectedOrderId = doc.id;
                                _selectedOrderDoc = doc;
                              });
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // RIGHT PANE: Details & Assignment
          Expanded(
            child: _selectedOrderDoc != null
                ? _AssignmentDetailPane(
                    orderDoc: _selectedOrderDoc!,
                    onClose: () => setState(() {
                      _selectedOrderId = null;
                      _selectedOrderDoc = null;
                    }),
                    userScope: userScope,
                  )
                : const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.touch_app_outlined,
                            size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('Select an order to assign a rider',
                            style: TextStyle(color: Colors.grey, fontSize: 18)),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
      UserScopeService userScope, BranchFilterService branchFilter) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pending Assignments',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          // Branch selector removed in favor of global BranchFilterService
        ],
      ),
    );
  }
}

class _OrderListTile extends StatelessWidget {
  final DocumentSnapshot doc;
  final bool isSelected;
  final VoidCallback onTap;

  const _OrderListTile({
    required this.doc,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final data = doc.data() as Map<String, dynamic>;
    // Using OrderNumberHelper logic roughly
    final orderIdShort =
        '#${(data['dailyOrderNumber'] ?? doc.id.substring(0, 8)).toString().toUpperCase()}';
    final timestamp = (data['timestamp'] as Timestamp?)?.toDate();
    final timeStr =
        timestamp != null ? DateFormat('hh:mm a').format(timestamp) : '--:--';
    final customer = data['customerName'] ?? 'Unknown';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: isSelected ? Colors.deepPurple.shade50 : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? Colors.deepPurple : Colors.grey[200]!,
              width: isSelected ? 2 : 1,
            ),
            boxShadow: isSelected
                ? []
                : [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.02),
                        blurRadius: 4,
                        offset: const Offset(0, 2))
                  ]),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(orderIdShort,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color:
                            isSelected ? Colors.deepPurple : Colors.black87)),
                Text(timeStr,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
            ),
            const SizedBox(height: 4),
            Text(customer, style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('NEEDS ASSIGN',
                  style: TextStyle(
                      fontSize: 10,
                      color: Colors.orange,
                      fontWeight: FontWeight.bold)),
            )
          ],
        ),
      ),
    );
  }
}

class _AssignmentDetailPane extends StatefulWidget {
  final DocumentSnapshot orderDoc;
  final VoidCallback onClose;
  final UserScopeService userScope;

  const _AssignmentDetailPane({
    required this.orderDoc,
    required this.onClose,
    required this.userScope,
  });

  @override
  State<_AssignmentDetailPane> createState() => _AssignmentDetailPaneState();
}

class _AssignmentDetailPaneState extends State<_AssignmentDetailPane> {
  bool _isCancelling = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('Orders')
          .doc(widget.orderDoc.id)
          .snapshots(),
      builder: (context, snapshot) {
        final doc = snapshot.data ?? widget.orderDoc;
        final data = doc.data() as Map<String, dynamic>? ?? {};
        final orderIdShort =
            '#${(data['dailyOrderNumber'] ?? doc.id.substring(0, 8)).toString().toUpperCase()}';

        // Determine branch for rider query
        String? orderBranchId;
        if (data['branchIds'] is List &&
            (data['branchIds'] as List).isNotEmpty) {
          orderBranchId = data['branchIds'][0].toString();
        }
        final targetBranchId = orderBranchId ??
            (widget.userScope.branchIds.isNotEmpty
                ? widget.userScope.branchIds.first
                : '');

        return Column(
          children: [
            // Top Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
              ),
              child: Row(
                children: [
                  IconButton(
                      onPressed: widget.onClose, icon: const Icon(Icons.close)),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Order $orderIdShort',
                          style: const TextStyle(
                              fontSize: 24, fontWeight: FontWeight.bold)),
                      Text('Manual Assignment Mode',
                          style:
                              TextStyle(fontSize: 14, color: Colors.grey[600])),
                    ],
                  ),
                  const Spacer(),
                  if (_isCancelling)
                    const CircularProgressIndicator()
                  else
                    OutlinedButton.icon(
                      onPressed: _handleCancelOrder,
                      icon: const Icon(Icons.cancel, size: 18),
                      label: const Text('Cancel Order'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                      ),
                    ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Order Info Column
                  Expanded(
                    flex: 2,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildInfoSection('Customer Details', [
                            _buildInfoRow(Icons.person, 'Name',
                                data['customerName'] ?? 'N/A'),
                            _buildInfoRow(Icons.phone, 'Phone',
                                data['customerPhone'] ?? 'N/A'),
                            _buildInfoRow(Icons.location_on, 'Address',
                                _formatAddress(data['deliveryAddress'])),
                          ]),
                          const SizedBox(height: 24),
                          _buildInfoSection('Order Details', [
                            _buildInfoRow(Icons.receipt, 'Total Amount',
                                'QAR ${(data['totalAmount'] as num?)?.toStringAsFixed(2) ?? "0.00"}'),
                            _buildInfoRow(Icons.payment, 'Payment',
                                data['paymentMethod'] ?? 'N/A'),
                            _buildInfoRow(Icons.note, 'Notes',
                                data['orderNotes'] ?? 'None'),
                          ]),
                          const SizedBox(height: 24),
                          // Reason Box
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.orange.shade200),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Why Manual Assignment?',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.orange.shade900)),
                                const SizedBox(height: 4),
                                Text(
                                    data['assignmentNotes'] ??
                                        'No specific reason provided.',
                                    style: TextStyle(
                                        color: Colors.orange.shade900)),
                              ],
                            ),
                          )
                        ],
                      ),
                    ),
                  ),

                  // Rider Selection Column (The "meat" of this screen)
                  Container(width: 1, color: Colors.grey[200]),
                  Expanded(
                    flex: 3,
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          color: Colors.grey[50],
                          child: const Row(
                            children: [
                              Icon(Icons.sports_motorsports,
                                  color: Colors.deepPurple),
                              SizedBox(width: 12),
                              Text('Available Riders',
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        Expanded(
                          child: _RiderSelectionList(
                            branchId: targetBranchId ?? '',
                            onAssign: (riderId) =>
                                _handleAssign(riderId, targetBranchId),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  String _formatAddress(dynamic addressData) {
    if (addressData == null) return 'No address provided';
    if (addressData is String) return addressData;
    if (addressData is Map) {
      // Try to construct a readable string
      final building = addressData['buildingName'] ?? '';
      final street = addressData['street'] ?? '';
      final zone = addressData['zone'] ?? '';
      return [building, street, zone]
          .where((s) => s.toString().isNotEmpty)
          .join(', ');
    }
    return 'Invalid address format';
  }

  Widget _buildInfoSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.deepPurple)),
        const SizedBox(height: 12),
        ...children,
      ],
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          SizedBox(
              width: 100,
              child: Text(label,
                  style: TextStyle(color: Colors.grey[600], fontSize: 13))),
          Expanded(
              child: Text(value,
                  style: const TextStyle(fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  Future<void> _handleCancelOrder() async {
    // Reusing the dialog logic from original screen, but we need to import or implement CancellationReasonDialog
    // Assuming it's available or we make a simple one.
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => const CancellationReasonDialog(
        title: 'Cancel Order?',
        confirmText: 'Confirm Cancel',
        reasons: CancellationReasons.orderReasons,
      ),
    );

    if (reason != null && reason.isNotEmpty) {
      setState(() => _isCancelling = true);
      try {
        await FirebaseFirestore.instance
            .collection('Orders')
            .doc(widget.orderDoc.id)
            .update({
          'status': 'cancelled',
          'cancellationReason': reason,
          'cancelledAt': FieldValue.serverTimestamp(),
          'cancelledBy': 'Admin Integration',
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Order Cancelled'), backgroundColor: Colors.green));
          widget.onClose(); // Close details
        }
      } catch (e) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Error: $e'), backgroundColor: Colors.red));
      } finally {
        if (mounted) setState(() => _isCancelling = false);
      }
    }
  }

  Future<void> _handleAssign(String riderId, String? currentBranchId) async {
    // Show loading or optimistic update?
    // For now, simple dialog or overlay
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    final result = await RiderAssignmentService.manualAssignRider(
      orderId: widget.orderDoc.id,
      riderId: riderId,
    );

    if (mounted) {
      Navigator.pop(context); // Pop loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: result.backgroundColor,
        ),
      );
      if (result.isSuccess) {
        widget.onClose();
      }
    }
  }
}

class _RiderSelectionList extends StatelessWidget {
  final String branchId;
  final ValueChanged<String> onAssign;

  const _RiderSelectionList({required this.branchId, required this.onAssign});

  @override
  Widget build(BuildContext context) {
    Query query = FirebaseFirestore.instance
        .collection('Drivers')
        .where('isAvailable', isEqualTo: true)
        .where('status', isEqualTo: 'online');

    if (branchId.isNotEmpty) {
      query = query.where('branchIds', arrayContains: branchId);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return Center(child: Text('Error: ${snapshot.error}'));
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());

        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.moped, size: 48, color: Colors.grey[300]),
                const SizedBox(height: 16),
                Text('No available riders online',
                    style: TextStyle(color: Colors.grey[600])),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            // Add safety checks
            final name = data['name'] ?? 'Unknown';
            final vehicle = data['vehicle'] is Map
                ? (data['vehicle']['type'] ?? 'Unknown Vehicle')
                : 'Unknown Vehicle';

            return Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey[200]!),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Colors.deepPurple.withOpacity(0.1),
                      child: const Icon(Icons.person, color: Colors.deepPurple),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16)),
                          Text(vehicle,
                              style: TextStyle(
                                  color: Colors.grey[600], fontSize: 13)),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () => onAssign(doc.id),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('Assign'),
                    )
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
