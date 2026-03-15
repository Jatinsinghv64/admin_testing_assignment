import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../Widgets/BranchFilterService.dart';
import '../Widgets/ProfessionalErrorWidget.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../main.dart'; // UserScopeService
import 'BranchManagement.dart'; // For MultiBranchSelector

class RidersScreenLarge extends StatefulWidget {
  const RidersScreenLarge({super.key});

  @override
  State<RidersScreenLarge> createState() => _RidersScreenLargeState();
}

class _RidersScreenLargeState extends State<RidersScreenLarge> {
  String _filterStatus = 'all';
  String _searchQuery = '';
  String? _selectedDriverId;
  DocumentSnapshot? _selectedDriverDoc;

  @override
  Widget build(BuildContext context) {
    final userScope = context.watch<UserScopeService>();
    final branchFilter = context.watch<BranchFilterService>();

    // Build Query
    Query<Map<String, dynamic>> query =
        FirebaseFirestore.instance.collection('Drivers').orderBy('name');

    // Branch Filtering
    final filterBranchIds =
        branchFilter.getFilterBranchIds(userScope.branchIds);

    if (filterBranchIds.isNotEmpty) {
      if (filterBranchIds.length == 1) {
        query = query.where('branchIds', arrayContains: filterBranchIds.first);
      } else {
        query = query.where('branchIds',
            arrayContainsAny: filterBranchIds.take(10).toList());
      }
    } else if (userScope.branchIds.isNotEmpty) {
      if (userScope.branchIds.length == 1) {
        query = query.where('branchIds', arrayContainsAny: userScope.branchIds);
      } else {
        query = query.where('branchIds',
            arrayContainsAny: userScope.branchIds.take(10).toList());
      }
    }

    // Status Filtering
    if (_filterStatus == 'online') {
      query = query.where('status', isEqualTo: 'online');
    } else if (_filterStatus == 'offline') {
      query = query.where('status', isEqualTo: 'offline');
    } else if (_filterStatus == 'available') {
      query = query.where('isAvailable', isEqualTo: true);
    } else if (_filterStatus == 'busy') {
      query = query.where('isAvailable', isEqualTo: false);
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Row(
        children: [
          // LEFT PANE: Driver List
          Container(
            width: 380,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(right: BorderSide(color: Colors.grey[200]!)),
            ),
            child: Column(
              children: [
                _buildSidebarHeader(context, userScope, branchFilter),
                _buildFilterBar(),
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: query.snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return ProfessionalErrorWidget(
                          title: 'Error',
                          message: snapshot.error.toString(),
                          icon: Icons.error_outline,
                        );
                      }
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      var docs = snapshot.data!.docs;

                      // Client Search
                      if (_searchQuery.isNotEmpty) {
                        final q = _searchQuery.toLowerCase();
                        docs = docs.where((doc) {
                          final data = doc.data();
                          final name =
                              (data['name'] as String? ?? '').toLowerCase();
                          final email =
                              (data['email'] as String? ?? '').toLowerCase();
                          return name.contains(q) || email.contains(q);
                        }).toList();
                      }

                      if (docs.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.person_outline,
                                  size: 48, color: Colors.grey[300]),
                              const SizedBox(height: 16),
                              Text('No drivers found',
                                  style: TextStyle(color: Colors.grey[600])),
                            ],
                          ),
                        );
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: docs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final doc = docs[index];
                          final isSelected = doc.id == _selectedDriverId;
                          return _DriverListTile(
                            doc: doc,
                            isSelected: isSelected,
                            onTap: () {
                              setState(() {
                                _selectedDriverId = doc.id;
                                _selectedDriverDoc = doc;
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

          // RIGHT PANE: Driver Details
          Expanded(
            child: _selectedDriverDoc != null
                ? _DriverDetailPane(
                    driverDoc: _selectedDriverDoc!,
                    userScope: userScope,
                    onClose: () => setState(() {
                      _selectedDriverId = null;
                      _selectedDriverDoc = null;
                    }),
                  )
                : const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.two_wheeler, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('Select a driver to view details',
                            style: TextStyle(color: Colors.grey, fontSize: 18)),
                      ],
                    ),
                  ),
          )
        ],
      ),
    );
  }

  Widget _buildSidebarHeader(BuildContext context, UserScopeService userScope,
      BranchFilterService branchFilter) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey[100]!)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Drivers',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              IconButton(
                  onPressed: () {
                    _showDriverDialog(context, userScope);
                  },
                  icon: const Icon(Icons.add_circle, color: Colors.deepPurple)),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: InputDecoration(
              hintText: 'Search...',
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              contentPadding: const EdgeInsets.all(10),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none),
              filled: true,
              fillColor: Colors.grey[100],
            ),
            onChanged: (val) => setState(() => _searchQuery = val),
          ),
          // Branch selector removed in favor of global BranchFilterService
        ],
      ),
    );
  }

  void _showDriverDialog(BuildContext context, UserScopeService userScope,
      {DocumentSnapshot<Map<String, dynamic>>? driverDoc}) {
    showDialog(
      context: context,
      builder: (context) =>
          _DriverDialog(userScope: userScope, driverDoc: driverDoc),
    );
  }

  Widget _buildFilterBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _FilterChip(
              label: 'All',
              selected: _filterStatus == 'all',
              onTap: () => setState(() => _filterStatus = 'all')),
          _FilterChip(
              label: 'Online',
              selected: _filterStatus == 'online',
              onTap: () => setState(() => _filterStatus = 'online')),
          _FilterChip(
              label: 'Offline',
              selected: _filterStatus == 'offline',
              onTap: () => setState(() => _filterStatus = 'offline')),
          _FilterChip(
              label: 'Busy',
              selected: _filterStatus == 'busy',
              onTap: () => setState(() => _filterStatus = 'busy')),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? Colors.deepPurple
                : Colors.deepPurple.withOpacity(0.05),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(label,
              style: TextStyle(
                  color: selected ? Colors.white : Colors.deepPurple,
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}

class _DriverListTile extends StatelessWidget {
  final DocumentSnapshot doc;
  final bool isSelected;
  final VoidCallback onTap;

  const _DriverListTile(
      {required this.doc, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final data = doc.data() as Map<String, dynamic>;
    final name = data['name'] ?? 'Unknown';
    final status = data['status'] ?? 'offline';
    final isAvailable = data['isAvailable'] ?? false;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: isSelected ? Colors.deepPurple.shade50 : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: isSelected ? Colors.deepPurple : Colors.transparent),
            boxShadow: isSelected
                ? []
                : [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.02),
                        blurRadius: 4,
                        offset: const Offset(0, 2))
                  ]),
        child: Row(
          children: [
            Stack(
              children: [
                ClipOval(
                  child: Container(
                    width: 40,
                    height: 40,
                    color: Colors.grey[200],
                    child: data['profileImageUrl'] != null
                        ? Image.network(
                            data['profileImageUrl'],
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(Icons.person, color: Colors.grey),
                          )
                        : const Icon(Icons.person, color: Colors.grey),
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: status == 'online' ? Colors.green : Colors.grey,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                )
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color:
                              isSelected ? Colors.deepPurple : Colors.black87)),
                  Text(status.toString().toUpperCase(),
                      style: TextStyle(
                          fontSize: 10,
                          color:
                              status == 'online' ? Colors.green : Colors.grey)),
                ],
              ),
            ),
            if (!isAvailable && status == 'online')
              const Icon(Icons.access_time_filled,
                  size: 16, color: Colors.orange)
          ],
        ),
      ),
    );
  }
}

class _DriverDetailPane extends StatefulWidget {
  final DocumentSnapshot driverDoc;
  final UserScopeService userScope;
  final VoidCallback onClose;

  const _DriverDetailPane({
    required this.driverDoc,
    required this.userScope,
    required this.onClose,
  });

  @override
  State<_DriverDetailPane> createState() => _DriverDetailPaneState();
}

class _DriverDetailPaneState extends State<_DriverDetailPane> {
  int? _realDeliveryCount;
  double? _realAverageRating;
  bool _isLoadingStats = true;

  @override
  void initState() {
    super.initState();
    _fetchRealStats();
  }

  @override
  void didUpdateWidget(covariant _DriverDetailPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.driverDoc.id != widget.driverDoc.id) {
      _fetchRealStats();
    }
  }

  Future<void> _fetchRealStats() async {
    setState(() => _isLoadingStats = true);
    try {
      final ordersSnapshot = await FirebaseFirestore.instance
          .collection('Orders')
          .where('riderId', isEqualTo: widget.driverDoc.id)
          .where('status', isEqualTo: 'delivered')
          .get();

      double totalRating = 0.0;
      int ratedOrdersCount = 0;

      for (final doc in ordersSnapshot.docs) {
        final data = doc.data();
        final rawRating = data['riderRating'];
        double? ratingVal;

        if (rawRating is num) {
          ratingVal = rawRating.toDouble();
        } else if (rawRating is String) {
          ratingVal = double.tryParse(rawRating);
        }

        if (ratingVal != null && ratingVal > 0) {
          totalRating += ratingVal;
          ratedOrdersCount++;
        }
      }

      if (mounted) {
        setState(() {
          _realDeliveryCount = ordersSnapshot.docs.length;
          _realAverageRating =
              ratedOrdersCount > 0 ? totalRating / ratedOrdersCount : 0.0;
          _isLoadingStats = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching real driver stats: $e');
      if (mounted) {
        setState(() {
          _isLoadingStats = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.driverDoc.data() as Map<String, dynamic>;
    final name = data['name'] ?? 'Unknown';
    final vehicle = data['vehicle'] ?? {};

    return Column(
      children: [
        // Header
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              Colors.deepPurple.shade400,
              Colors.deepPurple.shade700
            ]),
          ),
          child: Column(
            children: [
              // Top Bar with Close
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
              // Profile Section
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                child: Row(
                  children: [
                    ClipOval(
                      child: Container(
                        width: 90,
                        height: 90,
                        color: Colors.white,
                        child: data['profileImageUrl'] != null
                            ? Image.network(
                                data['profileImageUrl'],
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    const Icon(Icons.person,
                                        size: 45, color: Colors.grey),
                              )
                            : const Icon(Icons.person,
                                size: 45, color: Colors.grey),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold)),
                          Text(data['email'] ?? '',
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.8),
                                  fontSize: 14)),
                          const SizedBox(height: 8),
                          _buildStatusIndicator(data['status'] ?? 'offline'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Actions Section
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildHeaderAction(
                        icon: Icons.map_outlined,
                        label: 'Track',
                        color: Colors.green,
                        onTap: () =>
                            _showTrackingDialog(context, widget.driverDoc),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildHeaderAction(
                        icon: data['isAvailable'] == true
                            ? Icons.pause_circle_outline
                            : Icons.play_circle_outline,
                        label:
                            data['isAvailable'] == true ? 'Pause' : 'Activate',
                        color: data['isAvailable'] == true
                            ? Colors.orange
                            : Colors.blue,
                        onTap: () => _toggleAvailability(data),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildHeaderAction(
                        icon: Icons.edit_outlined,
                        label: 'Edit',
                        color: Colors.amber,
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (context) => _DriverDialog(
                              userScope: widget.userScope,
                              driverDoc: widget.driverDoc
                                  as DocumentSnapshot<Map<String, dynamic>>,
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildHeaderAction(
                        icon: Icons.history,
                        label: 'History',
                        color: Colors.blueAccent,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => _DriverOrderHistoryScreen(
                                driverId: widget.driverDoc.id,
                                driverName: data['name'] ?? 'Rider',
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildHeaderAction(
                        icon: Icons.delete_outline,
                        label: 'Delete',
                        color: Colors.red,
                        onTap: () => _confirmDelete(data),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStatsRow(data),
                const SizedBox(height: 32),
                const Text('Vehicle Information',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Card(
                  elevation: 0,
                  color: Colors.grey[50],
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.grey[200]!)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _buildDetailRow(Icons.directions_car, 'Vehicle Type',
                            vehicle['type'] ?? 'N/A'),
                        const Divider(),
                        _buildDetailRow(Icons.confirmation_number,
                            'Plate Number', vehicle['number'] ?? 'N/A'),
                        const Divider(),
                        _buildDetailRow(
                            Icons.palette, 'Color', vehicle['color'] ?? 'N/A'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                const Text('Contact Information',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Card(
                  elevation: 0,
                  color: Colors.grey[50],
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.grey[200]!)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _buildDetailRow(Icons.phone, 'Phone',
                            data['phone']?.toString() ?? 'N/A'),
                        const Divider(),
                        _buildDetailRow(Icons.email_outlined, 'Email',
                            data['email']?.toString() ?? 'N/A'),
                      ],
                    ),
                  ),
                )
              ],
            ),
          ),
        )
      ],
    );
  }

  Widget _buildStatsRow(Map<String, dynamic> data) {
    return Row(
      children: [
        _buildStatCard(
            'Total Deliveries',
            _isLoadingStats ? '...' : '${_realDeliveryCount ?? 0}',
            Icons.local_shipping,
            Colors.blue),
        const SizedBox(width: 16),
        _buildStatCard(
            'Rating',
            _isLoadingStats
                ? '...'
                : (_realAverageRating?.toStringAsFixed(1) ?? '0.0'),
            Icons.star,
            Colors.amber), // Replace with real rating logic if needed
        const SizedBox(width: 16),
        _buildStatCard(
            'Status',
            (data['status'] ?? '').toString().toUpperCase(),
            Icons.info,
            data['status'] == 'online' ? Colors.green : Colors.grey),
      ],
    );
  }

  Widget _buildStatCard(
      String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4))
            ]),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(value,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Text(label,
                style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              Text(value,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w500)),
            ],
          ),
        )
      ],
    );
  }

  Widget _buildHeaderAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withOpacity(0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIndicator(String status) {
    Color color;
    switch (status.toLowerCase()) {
      case 'online':
        color = Colors.green;
        break;
      case 'on_delivery':
        color = Colors.orange;
        break;
      case 'busy':
        color = Colors.red;
        break;
      default:
        color = Colors.grey;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 8),
        Text(
          status.toUpperCase(),
          style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 12,
              fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  void _toggleAvailability(Map<String, dynamic> data) async {
    try {
      final isAvailable = data['isAvailable'] ?? false;
      await widget.driverDoc.reference.update({'isAvailable': !isAvailable});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('Rider is now ${!isAvailable ? 'Activated' : 'Paused'}')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _confirmDelete(Map<String, dynamic> data) {
    if ((data['assignedOrderId'] ?? '').isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Cannot delete rider with an active order!'),
            backgroundColor: Colors.orange),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Rider?'),
        content: Text(
            'Are you sure you want to delete ${data['name']}? This action cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              await widget.driverDoc.reference.delete();
              if (mounted) {
                Navigator.pop(context);
                widget.onClose();
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // Placeholder if needed for future extensions

  void _showTrackingDialog(BuildContext context, DocumentSnapshot driverDoc) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800, maxHeight: 600),
            child: Column(
              children: [
                AppBar(
                  title: Text(
                      'Live Tracking: ${(driverDoc.data() as Map)['name'] ?? 'Driver'}'),
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  shape: const RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  leading: const Icon(Icons.location_on),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                Expanded(
                  child: StreamBuilder<DocumentSnapshot>(
                    stream: driverDoc.reference.snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final data =
                          snapshot.data!.data() as Map<String, dynamic>? ?? {};
                      final geoPoint = data['currentLocation'] as GeoPoint?;
                      final status = data['status'] ?? 'offline';

                      if (geoPoint == null ||
                          (geoPoint.latitude == 0 && geoPoint.longitude == 0)) {
                        return const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.location_off,
                                  size: 64, color: Colors.grey),
                              SizedBox(height: 16),
                              Text('No GPS data available for this driver'),
                            ],
                          ),
                        );
                      }

                      final position =
                          LatLng(geoPoint.latitude, geoPoint.longitude);

                      return FlutterMap(
                        options: MapOptions(
                          initialCenter: position,
                          initialZoom: 15,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.example.app',
                          ),
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: position,
                                width: 80,
                                height: 80,
                                child: Column(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(8),
                                        boxShadow: [
                                          BoxShadow(
                                            color:
                                                Colors.black.withOpacity(0.1),
                                            blurRadius: 4,
                                          )
                                        ],
                                      ),
                                      child: Text(
                                        data['name'] ?? 'Driver',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    Icon(
                                      Icons.location_on,
                                      color: status == 'online'
                                          ? Colors.green
                                          : Colors.red,
                                      size: 40,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.grey[50],
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: Colors.grey),
                      SizedBox(width: 8),
                      Text(
                        'Updates live as the driver moves.',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DriverOrderHistoryScreen extends StatefulWidget {
  final String driverId;
  final String driverName;

  const _DriverOrderHistoryScreen({
    required this.driverId,
    required this.driverName,
  });

  @override
  State<_DriverOrderHistoryScreen> createState() =>
      _DriverOrderHistoryScreenState();
}

class _DriverOrderHistoryScreenState extends State<_DriverOrderHistoryScreen> {
  String _filterStatus = 'all';
  final List<String> _statusFilters = ['all', 'delivered', 'cancelled'];
  final int _ordersPerPage = 6;
  List<DocumentSnapshot> _orders = [];
  bool _isLoading = false;
  bool _hasMore = true;
  DocumentSnapshot? _lastDocument;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchOrders();
  }

  Future<void> _fetchOrders() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      Query query = FirebaseFirestore.instance.collection('Orders');
      query = query.where('riderId', isEqualTo: widget.driverId);
      query = query.orderBy('timestamp', descending: true);
      if (_filterStatus != 'all') {
        query = query.where('status', isEqualTo: _filterStatus);
      }
      query = query.limit(_ordersPerPage);
      if (_lastDocument != null) {
        query = query.startAfterDocument(_lastDocument!);
      }
      final snapshot = await query.get();
      setState(() {
        if (snapshot.docs.isNotEmpty) {
          _orders.addAll(snapshot.docs);
          _lastDocument = snapshot.docs.last;
        }
        if (snapshot.docs.length < _ordersPerPage) {
          _hasMore = false;
        }
      });
    } catch (e) {
      debugPrint("Error fetching history: $e");
      setState(() => _errorMessage = "Could not load orders. Check indexes.");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _onFilterChanged(String selected) {
    if (_filterStatus == selected) return;
    setState(() {
      _filterStatus = selected;
      _orders.clear();
      _lastDocument = null;
      _hasMore = true;
    });
    _fetchOrders();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Order History',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple,
                  fontSize: 20),
            ),
            Text(
              widget.driverName,
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.deepPurple),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          _buildStatusFilter(),
          const SizedBox(height: 8),
          Expanded(child: _buildOrderList()),
        ],
      ),
    );
  }

  Widget _buildStatusFilter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _statusFilters.map((status) {
            final isSelected = _filterStatus == status;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(status.toUpperCase()),
                selected: isSelected,
                onSelected: (val) => _onFilterChanged(val ? status : 'all'),
                selectedColor: Colors.deepPurple,
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : Colors.deepPurple,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
                backgroundColor: Colors.deepPurple.withOpacity(0.1),
                checkmarkColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildOrderList() {
    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 10),
            Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
            TextButton(
              onPressed: () {
                setState(() {
                  _orders.clear();
                  _lastDocument = null;
                  _hasMore = true;
                });
                _fetchOrders();
              },
              child: const Text("Retry"),
            )
          ],
        ),
      );
    }
    if (_orders.isEmpty && _isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_orders.isEmpty && !_isLoading) {
      return const Center(
        child: Text("No orders found.",
            style: TextStyle(color: Colors.grey, fontSize: 16)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _orders.length + 1,
      itemBuilder: (context, index) {
        if (index == _orders.length) {
          if (_hasMore) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: ElevatedButton(
                  onPressed: _fetchOrders,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Text("Load More (6 Orders)"),
                ),
              ),
            );
          } else {
            return const Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                  child: Text("No more orders",
                      style: TextStyle(color: Colors.grey))),
            );
          }
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _OrderHistoryCard(order: _orders[index]),
        );
      },
    );
  }
}

class _OrderHistoryCard extends StatelessWidget {
  final DocumentSnapshot order;
  const _OrderHistoryCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final data = order.data() as Map<String, dynamic>? ?? {};
    final orderId = order.id;
    final status = data['status']?.toString() ?? 'unknown';
    final timestamp = data['timestamp'] as Timestamp?;
    final totalAmount =
        double.tryParse(data['totalAmount']?.toString() ?? '0') ?? 0.0;
    final orderType = data['Order_type']?.toString() ?? 'delivery';
    double rating = 0.0;
    final rawRating = data['rating'] ?? data['riderRating'];
    if (rawRating is num) {
      rating = rawRating.toDouble();
    } else if (rawRating is String) {
      rating = double.tryParse(rawRating) ?? 0.0;
    }
    String address = 'No address';
    final addrRaw = data['deliveryAddress'];
    if (addrRaw is String) {
      address = addrRaw;
    } else if (addrRaw is Map) {
      address = addrRaw['street']?.toString() ?? 'No address';
    }
    final dateStr = timestamp != null
        ? "${timestamp.toDate().day}/${timestamp.toDate().month}/${timestamp.toDate().year}"
        : "N/A";
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Order Number',
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500)),
                      const SizedBox(height: 2),
                      SelectableText('#$orderId',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              fontFamily: 'monospace',
                              color: Colors.deepPurple)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                          color: _getStatusColor(status).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8)),
                      child: Text(status.toUpperCase(),
                          style: TextStyle(
                              color: _getStatusColor(status),
                              fontSize: 10,
                              fontWeight: FontWeight.bold)),
                    ),
                    if (rating > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star_rounded,
                                color: Colors.amber, size: 16),
                            const SizedBox(width: 4),
                            Text(rating.toStringAsFixed(1),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: Colors.amber)),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6)),
              child: Text(orderType.toUpperCase().replaceAll('_', ' '),
                  style: const TextStyle(
                      fontSize: 10,
                      color: Colors.blue,
                      fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 8),
            Text('📅 $dateStr', style: const TextStyle(fontSize: 12)),
            if (address != 'No address')
              Text('📍 $address',
                  style: const TextStyle(fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            Text('QAR ${totalAmount.toStringAsFixed(2)}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.deepPurple,
                    fontSize: 16)),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    if (status == 'delivered') return Colors.green;
    if (status == 'cancelled') return Colors.red;
    return Colors.grey;
  }
}

/// Add/Edit Driver Dialog (Ported from RidersScreen.dart)
class _DriverDialog extends StatefulWidget {
  final UserScopeService userScope;
  final DocumentSnapshot<Map<String, dynamic>>? driverDoc;

  const _DriverDialog({required this.userScope, this.driverDoc});

  @override
  State<_DriverDialog> createState() => _DriverDialogState();
}

class _DriverDialogState extends State<_DriverDialog> {
  final _formKey = GlobalKey<FormState>();
  late bool _isEdit;
  bool _isLoading = false;

  // Form Controllers
  late TextEditingController _nameCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _profileImgCtrl;
  late TextEditingController _vehicleTypeCtrl;
  late TextEditingController _vehicleNumCtrl;
  String _status = 'offline';
  bool _isAvailable = false;
  List<String> _selectedBranchIds = [];

  @override
  void initState() {
    super.initState();
    _isEdit = widget.driverDoc != null;
    final data = widget.driverDoc?.data();

    // Controllers
    _nameCtrl = TextEditingController(text: data?['name']?.toString() ?? '');
    _emailCtrl = TextEditingController(text: data?['email']?.toString() ?? '');
    _phoneCtrl = TextEditingController(text: data?['phone']?.toString() ?? '');
    _profileImgCtrl =
        TextEditingController(text: data?['profileImageUrl']?.toString() ?? '');
    _status = data?['status']?.toString() ?? 'offline';
    _isAvailable = data?['isAvailable'] ?? false;
    _selectedBranchIds = List<String>.from(data?['branchIds'] ?? []);

    // Robust vehicle parsing
    String vType = 'Motorcycle';
    String vNum = '';
    try {
      if (data?['vehicle'] is Map) {
        final v = data!['vehicle'] as Map<String, dynamic>;
        vType = v['type']?.toString() ?? 'Motorcycle';
        vNum = v['number']?.toString() ?? '';
      } else if (data?['vehicle'] != null) {
        vType = data?['vehicle'].toString() ?? 'Motorcycle';
      }
    } catch (e) {
      debugPrint('Error parsing vehicle data: $e');
    }
    _vehicleTypeCtrl = TextEditingController(text: vType);
    _vehicleNumCtrl = TextEditingController(text: vNum);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _profileImgCtrl.dispose();
    _vehicleTypeCtrl.dispose();
    _vehicleNumCtrl.dispose();
    super.dispose();
  }

  Future<void> _onSave() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isLoading) return;

    setState(() => _isLoading = true);

    if (!widget.userScope.isSuperAdmin) {
      _selectedBranchIds = widget.userScope.branchIds;
    }

    if (_selectedBranchIds.isEmpty && !widget.userScope.isSuperAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Error: You are not assigned to any branch.'),
            backgroundColor: Colors.red),
      );
      setState(() => _isLoading = false);
      return;
    }

    try {
      final driverData = {
        'name': _nameCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'profileImageUrl': _profileImgCtrl.text.trim(),
        'status': _status,
        'isAvailable': _isAvailable,
        'branchIds': _selectedBranchIds,
        'vehicle': {
          'type': _vehicleTypeCtrl.text.trim(),
          'number': _vehicleNumCtrl.text.trim(),
        },
        'assignedOrderId':
            _isEdit ? widget.driverDoc!.data()!['assignedOrderId'] ?? '' : '',
        'fcmToken': _isEdit ? widget.driverDoc!.data()!['fcmToken'] ?? '' : '',
        'rating': _isEdit ? widget.driverDoc!.data()!['rating'] ?? '0' : '0',
        'totalDeliveries':
            _isEdit ? widget.driverDoc!.data()!['totalDeliveries'] ?? 0 : 0,
        'currentLocation': _isEdit
            ? widget.driverDoc!.data()!['currentLocation'] ??
                const GeoPoint(0, 0)
            : const GeoPoint(0, 0),
      };

      if (_isEdit) {
        await widget.driverDoc!.reference.update(driverData);
      } else {
        final docId = _emailCtrl.text.trim();
        if (docId.isEmpty) {
          throw Exception('Email is required to create a new driver.');
        }
        await FirebaseFirestore.instance
            .collection('Drivers')
            .doc(docId)
            .set(driverData);
      }

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Driver ${_isEdit ? 'updated' : 'added'} successfully!'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error saving driver: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final inputDecoration = InputDecoration(
      filled: true,
      fillColor: Colors.grey[50],
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.deepPurple, width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.deepPurple,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.delivery_dining,
                        color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isEdit ? 'Edit Driver' : 'Add New Driver',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold),
                      ),
                      Text(
                        _isEdit
                            ? 'Update driver information'
                            : 'Fill in driver details below',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.8), fontSize: 13),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Personal Information',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Colors.grey[700])),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _nameCtrl,
                        decoration: inputDecoration.copyWith(
                          labelText: 'Full Name',
                          prefixIcon: const Icon(Icons.person_outline,
                              color: Colors.deepPurple),
                        ),
                        validator: (v) =>
                            v!.isEmpty ? 'Name is required' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _emailCtrl,
                        enabled: !_isEdit,
                        decoration: inputDecoration.copyWith(
                          labelText: 'Email (Login ID)',
                          prefixIcon: const Icon(Icons.email_outlined,
                              color: Colors.deepPurple),
                          helperText:
                              _isEdit ? 'Email cannot be changed' : null,
                        ),
                        validator: (v) =>
                            v!.isEmpty ? 'Email is required' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _phoneCtrl,
                        decoration: inputDecoration.copyWith(
                          labelText: 'Phone Number',
                          prefixIcon: const Icon(Icons.phone_outlined,
                              color: Colors.deepPurple),
                        ),
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 20),
                      Text('Vehicle Information',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Colors.grey[700])),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _vehicleTypeCtrl,
                              decoration: inputDecoration.copyWith(
                                labelText: 'Vehicle Type',
                                prefixIcon: const Icon(Icons.two_wheeler,
                                    color: Colors.deepPurple),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _vehicleNumCtrl,
                              decoration: inputDecoration.copyWith(
                                labelText: 'Plate Number',
                                prefixIcon: const Icon(Icons.pin,
                                    color: Colors.deepPurple),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text('Status & Availability',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Colors.grey[700])),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _status,
                        decoration: inputDecoration.copyWith(
                          labelText: 'Status',
                          prefixIcon: const Icon(Icons.signal_wifi_4_bar,
                              color: Colors.deepPurple),
                        ),
                        items: ['online', 'offline', 'on_delivery'].map((s) {
                          IconData icon;
                          Color color;
                          switch (s) {
                            case 'online':
                              icon = Icons.check_circle;
                              color = Colors.green;
                              break;
                            case 'offline':
                              icon = Icons.cancel;
                              color = Colors.red;
                              break;
                            default:
                              icon = Icons.delivery_dining;
                              color = Colors.orange;
                          }
                          return DropdownMenuItem(
                              value: s,
                              child: Row(
                                children: [
                                  Icon(icon, color: color, size: 18),
                                  const SizedBox(width: 8),
                                  Text(s.replaceAll('_', ' ').toUpperCase()),
                                ],
                              ));
                        }).toList(),
                        onChanged: (v) => setState(() => _status = v!),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Available for Orders'),
                          subtitle: Text(
                              _isAvailable
                                  ? 'Can receive new orders'
                                  : 'Not accepting orders',
                              style: TextStyle(
                                  color: Colors.grey[600], fontSize: 12)),
                          value: _isAvailable,
                          activeColor: Colors.deepPurple,
                          onChanged: (v) => setState(() => _isAvailable = v),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (widget.userScope.isSuperAdmin) ...[
                        Text('Branch Assignment',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: Colors.grey[700])),
                        const SizedBox(height: 12),
                        MultiBranchSelector(
                          selectedIds: _selectedBranchIds,
                          onChanged: (selected) =>
                              setState(() => _selectedBranchIds = selected),
                        ),
                      ] else ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12)),
                          child: Row(
                            children: [
                              const Icon(Icons.store, color: Colors.blue),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Branch Assignment',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold)),
                                    Text(
                                        '${widget.userScope.branchIds.length} branch(es) assigned',
                                        style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 12)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        side: BorderSide(color: Colors.grey[400]!),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _onSave,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : Text(_isEdit ? 'Update Driver' : 'Add Driver'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
