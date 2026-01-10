import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data'; // Required for Uint8List
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class MultiBranchSelector extends StatefulWidget {
  final List<String> selectedIds;
  final ValueChanged<List<String>> onChanged;

  const MultiBranchSelector({
    Key? key,
    required this.selectedIds,
    required this.onChanged,
  }) : super(key: key);

  @override
  State<MultiBranchSelector> createState() => _MultiBranchSelectorState();
}

class _MultiBranchSelectorState extends State<MultiBranchSelector> {
  late List<String> _selectedIds;

  @override
  void initState() {
    super.initState();
    _selectedIds = List.from(widget.selectedIds);
  }

  void _handleSelectionChange(String branchId, bool selected) {
    if (!mounted) return; // ADD THIS CHECK

    setState(() {
      if (selected) {
        _selectedIds.add(branchId);
      } else {
        _selectedIds.remove(branchId);
      }
    });

    if (mounted) { // ADD THIS CHECK
      widget.onChanged(_selectedIds);
    }
  }

  void _handleSelectAll(List<QueryDocumentSnapshot> branches) {
    if (!mounted) return; // ADD THIS CHECK

    setState(() {
      _selectedIds = branches.map((doc) => doc.id).toList();
    });

    if (mounted) { // ADD THIS CHECK
      widget.onChanged(_selectedIds);
    }
  }

  void _handleClearAll() {
    if (!mounted) return; // ADD THIS CHECK

    setState(() {
      _selectedIds = [];
    });

    if (mounted) { // ADD THIS CHECK
      widget.onChanged(_selectedIds);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('Branch').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Text(
              'Error loading branches: ${snapshot.error}',
              style: TextStyle(color: Colors.red[700]),
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: const Center(
              child: Text(
                'No branches available',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          );
        }

        final branches = snapshot.data!.docs;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with selection count
              Row(
                children: [
                  const Icon(Icons.business, color: Colors.deepPurple, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'Select Branches',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_selectedIds.length} selected',
                      style: const TextStyle(
                        color: Colors.deepPurple,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Select All / None buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _handleSelectAll(branches),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.deepPurple,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      child: const Text('Select All'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _handleClearAll,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      child: const Text('Clear All'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Branches list
              Container(
                height: 200,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.white,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    children: branches.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final branchName = data['name']?.toString() ?? doc.id;
                      final isSelected = _selectedIds.contains(doc.id);

                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.deepPurple.withOpacity(0.05) : null,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isSelected ? Colors.deepPurple.withOpacity(0.3) : Colors.transparent,
                          ),
                        ),
                        child: CheckboxListTile(
                          dense: true,
                          title: Text(
                            branchName,
                            style: TextStyle(
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                              color: isSelected ? Colors.deepPurple : Colors.black87,
                            ),
                          ),
                          value: isSelected,
                          onChanged: (bool? selected) {
                            if (selected != null) {
                              _handleSelectionChange(doc.id, selected);
                            }
                          },
                          activeColor: Colors.deepPurple,
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class BranchManagementScreen extends StatefulWidget {
  const BranchManagementScreen({super.key});

  @override
  State<BranchManagementScreen> createState() => _BranchManagementScreenState();
}

class _BranchManagementScreenState extends State<BranchManagementScreen> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final branchCollection = FirebaseFirestore.instance.collection('Branch');

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        centerTitle: true,
        title: const Text(
          'Branch Management',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.deepPurple,
            fontSize: 24,
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: Colors.deepPurple,
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.add, color: Colors.white),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => const BranchDialog(),
                );
              },
              tooltip: 'Add New Branch',
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Enhanced Search Section
          Container(
            margin: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.deepPurple.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search branches by name or city...',
                hintStyle: TextStyle(color: Colors.grey[400]),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.white,
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: Colors.deepPurple.shade300,
                  size: 24,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
              ),
              onChanged: (query) {
                setState(() {
                  _searchQuery = query.toLowerCase();
                });
              },
            ),
          ),
          // Enhanced Branch List
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: branchCollection.orderBy('name').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation(
                            Colors.deepPurple,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Loading branches...',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 64,
                          color: Colors.red[300],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Error: ${snapshot.error}',
                          style: const TextStyle(color: Colors.red, fontSize: 16),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.business_outlined,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No branches found.',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Add your first branch to get started.',
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final docs = snapshot.data!.docs;

                // Filter branches based on search query
                final filteredDocs = docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final name = (data['name'] ?? '').toString().toLowerCase();
                  final address = data['address'] as Map? ?? {};
                  final city = (address['city'] ?? '').toString().toLowerCase();

                  return name.contains(_searchQuery) || city.contains(_searchQuery);
                }).toList();

                if (filteredDocs.isEmpty && _searchQuery.isNotEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search_off,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No branches match your search.',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Try a different search term.',
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  itemCount: filteredDocs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 16),
                  itemBuilder: (context, index) {
                    final doc = filteredDocs[index];
                    return _BranchCard(
                      doc: doc,
                      onEdit: () {
                        final data = doc.data() as Map<String, dynamic>;
                        showDialog(
                          context: context,
                          builder: (_) => BranchDialog(
                            docId: doc.id,
                            initialData: data,
                          ),
                        );
                      },
                      onDelete: () async {
                        final shouldDelete = await _confirmDelete(context);
                        if (shouldDelete) {
                          await branchCollection.doc(doc.id).delete();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Branch deleted successfully.'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        }
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static Future<bool> _confirmDelete(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            const SizedBox(width: 12),
            const Text('Delete Branch?', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          'Are you sure you want to delete this branch? This action cannot be undone. All associated tables and data will be lost.',
          style: TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              foregroundColor: Colors.grey[600],
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w500)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

class _BranchCard extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _BranchCard({
    required this.doc,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final data = doc.data() as Map<String, dynamic>;
    final name = data['name'] ?? 'Unnamed Branch';
    final email = data['email'] ?? '';
    final phone = data['phone']?.toString() ?? '';
    final address = data['address'] as Map? ?? {};
    final city = address['city'] ?? '';
    final street = address['street'] ?? '';
    final isOpen = data['isOpen'] ?? false;
    final logoUrl = data['logoUrl'] as String? ?? '';
    final estimatedTime = data['estimatedTime'] ?? '';
    final deliveryFee = (data['deliveryFee'] as num?)?.toDouble() ?? 0.0;
    final freeDeliveryRange = (data['freeDeliveryRange'] as num?)?.toDouble() ?? 0.0;
    final noDeliveryRange = (data['noDeliveryRange'] as num?)?.toDouble() ?? 0.0;
    final tables = data['Tables'] as Map? ?? {};

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
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _showBranchDetails(context),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row
              Row(
                children: [
                  // Branch Logo/Icon
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: Colors.deepPurple.withOpacity(0.1),
                    ),
                    child: logoUrl.isNotEmpty
                        ? ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.network(
                        logoUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Icon(
                          Icons.business_rounded,
                          color: Colors.deepPurple,
                          size: 32,
                        ),
                      ),
                    )
                        : Icon(
                      Icons.business_rounded,
                      color: Colors.deepPurple,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Branch Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: Colors.black87,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            // Status Switch
                            Transform.scale(
                              scale: 0.8,
                              child: Switch(
                                value: isOpen,
                                onChanged: (value) async {
                                  await FirebaseFirestore.instance
                                      .collection('Branch')
                                      .doc(doc.id)
                                      .update({
                                        'isOpen': value,
                                        'manuallyClosed': !value, // Set when closing
                                        'manuallyOpened': value,   // Set when opening
                                        'lastStatusUpdate': FieldValue.serverTimestamp(),
                                      });

                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Branch status updated to ${value ? "Open" : "Closed"}!',
                                        ),
                                        backgroundColor: Colors.green,
                                      ),
                                    );
                                  }
                                },
                                activeColor: Colors.green,
                                inactiveThumbColor: Colors.red,
                                inactiveTrackColor: Colors.red.withOpacity(0.5),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        if (city.isNotEmpty)
                          Row(
                            children: [
                              Icon(
                                Icons.location_on_rounded,
                                size: 16,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  city,
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Status Badge
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isOpen
                          ? Colors.green.withOpacity(0.1)
                          : Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isOpen
                            ? Colors.green.withOpacity(0.3)
                            : Colors.red.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isOpen ? Icons.radio_button_checked : Icons.radio_button_off,
                          size: 16,
                          color: isOpen ? Colors.green : Colors.red,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isOpen ? 'OPEN' : 'CLOSED',
                          style: TextStyle(
                            color: isOpen ? Colors.green : Colors.red,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (tables.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.table_restaurant_rounded,
                            size: 14,
                            color: Colors.blue,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${tables.length}',
                            style: const TextStyle(
                              color: Colors.blue,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 16),

              // Quick Info Row
              if (estimatedTime.isNotEmpty || deliveryFee > 0 || freeDeliveryRange > 0)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Row(
                    children: [
                      if (estimatedTime.isNotEmpty) ...[
                        Icon(
                          Icons.timer_outlined,
                          size: 16,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$estimatedTime min',
                          style: TextStyle(
                            color: Colors.grey[700],
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 16),
                      ],
                      if (deliveryFee > 0) ...[
                        Icon(
                          Icons.delivery_dining_outlined,
                          size: 16,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'QAR ${deliveryFee.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: Colors.grey[700],
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 16),
                      ],
                      if (freeDeliveryRange > 0) ...[
                        Icon(
                          Icons.local_shipping_outlined,
                          size: 16,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Free: ${freeDeliveryRange.toStringAsFixed(1)}km',
                          style: TextStyle(
                            color: Colors.grey[700],
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

              const SizedBox(height: 16),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.visibility_outlined, size: 18),
                      label: const Text('View Details'),
                      onPressed: () => _showBranchDetails(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.deepPurple,
                        side: BorderSide(color: Colors.deepPurple.withOpacity(0.5)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Edit'),
                    onPressed: onEdit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                      onPressed: onDelete,
                      tooltip: 'Delete Branch',
                      padding: const EdgeInsets.all(12),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showBranchDetails(BuildContext context) {
    final data = doc.data() as Map<String, dynamic>;
    final name = data['name'] ?? 'Unnamed Branch';
    final email = data['email'] ?? 'Not provided';
    final phone = data['phone']?.toString() ?? 'Not provided';
    final address = data['address'] as Map? ?? {};
    final estimatedTime = data['estimatedTime'] ?? 'Not set';
    final deliveryFee = (data['deliveryFee'] as num?)?.toDouble() ?? 0.0;
    final freeDeliveryRange = (data['freeDeliveryRange'] as num?)?.toDouble() ?? 0.0;
    final noDeliveryRange = (data['noDeliveryRange'] as num?)?.toDouble() ?? 0.0;
    final logoUrl = data['logoUrl'] as String? ?? '';
    final isOpen = data['isOpen'] ?? false;
    final offerCarousel = List.from(data['offer_carousel'] ?? []);
    final tables = data['Tables'] as Map? ?? {};

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            if (logoUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  logoUrl,
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.deepPurple.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.business, color: Colors.deepPurple),
                  ),
                ),
              )
            else
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.business, color: Colors.deepPurple),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                name,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDetailSection('Contact Information', [
                  _buildDetailRow(Icons.email_outlined, 'Email', email),
                  _buildDetailRow(Icons.phone_outlined, 'Phone', phone),
                ]),

                const SizedBox(height: 16),

                _buildDetailSection('Address', [
                  _buildDetailRow(Icons.location_city_outlined, 'City', address['city'] ?? 'Not provided'),
                  _buildDetailRow(Icons.location_city_outlined, 'City (Arabic)', address['city_ar'] ?? 'Not provided'), // Added Arabic
                  _buildDetailRow(Icons.location_on_outlined, 'Street', address['street'] ?? 'Not provided'),
                  _buildDetailRow(Icons.location_on_outlined, 'Street (Arabic)', address['street_ar'] ?? 'Not provided'), // Added Arabic
                ]),

                const SizedBox(height: 16),

                _buildDetailSection('Business Details', [
                  _buildDetailRow(Icons.timer_outlined, 'Estimated Time', estimatedTime),
                  _buildDetailRow(Icons.delivery_dining_outlined, 'Delivery Fee', 'QAR ${deliveryFee.toStringAsFixed(2)}'),
                  _buildDetailRow(
                    Icons.local_shipping_outlined,
                    'Free Delivery Range',
                    freeDeliveryRange > 0 ? '${freeDeliveryRange.toStringAsFixed(1)} km' : 'Not set',
                  ),
                  _buildDetailRow(
                    Icons.do_not_disturb_outlined,
                    'No Delivery Range',
                    noDeliveryRange > 0 ? '${noDeliveryRange.toStringAsFixed(1)} km' : 'Not set',
                  ),
                  _buildDetailRow(
                    isOpen ? Icons.radio_button_checked : Icons.radio_button_off,
                    'Status',
                    isOpen ? 'Open' : 'Closed',
                    color: isOpen ? Colors.green : Colors.red,
                  ),
                  _buildDetailRow(Icons.table_restaurant_outlined, 'Tables', '${tables.length} configured'),
                ]),

                // AFTER
                if (offerCarousel.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  // --- New Image Carousel Section ---
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Offer Carousel',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.deepPurple,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 150, // Or any height you prefer for the carousel
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: offerCarousel.length,
                          itemBuilder: (context, index) {
                            final imageUrl = offerCarousel[index];
                            return Padding(
                              padding: const EdgeInsets.only(right: 10.0),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12.0),
                                child: Image.network(
                                  imageUrl,
                                  width: 250, // Width for each image in the carousel
                                  fit: BoxFit.cover,
                                  // Shows a loading indicator while the image loads
                                  loadingBuilder: (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return Container(
                                      width: 250,
                                      color: Colors.grey[200],
                                      child: Center(
                                        child: CircularProgressIndicator(
                                          color: Colors.deepPurple,
                                          value: loadingProgress.expectedTotalBytes != null
                                              ? loadingProgress.cumulativeBytesLoaded /
                                              loadingProgress.expectedTotalBytes!
                                              : null,
                                        ),
                                      ),
                                    );
                                  },
                                  // Shows a placeholder if an image fails to load
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      width: 250,
                                      color: Colors.grey[200],
                                      child: const Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.broken_image, color: Colors.grey, size: 40),
                                          SizedBox(height: 4),
                                          Text('Image failed', style: TextStyle(color: Colors.grey)),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(foregroundColor: Colors.grey[600]),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Colors.deepPurple,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Column(
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value, {Color? color}) {
    // This helper function also needs to be updated to show Arabic in detail view if it was passed.
    // However, since the branch address fetching logic is outside this file, we can leave this as-is
    // since the Arabic fields are now added to the DB and will be available for the receipt (OrdersScreen.dart).
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color ?? Colors.deepPurple.shade400),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: TextStyle(fontSize: 14, color: color ?? Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}

class BranchDialog extends StatefulWidget {
  final String? docId;
  final Map? initialData;
  const BranchDialog({this.docId, this.initialData, Key? key}) : super(key: key);

  @override
  State<BranchDialog> createState() => _BranchDialogState();
}

class _BranchDialogState extends State<BranchDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl, _emailCtrl, _phoneCtrl, _estimatedTimeCtrl, _logoUrlCtrl, _deliveryFeeCtrl;
  late TextEditingController _cityCtrl, _streetCtrl, _latCtrl, _lngCtrl;
  late TextEditingController _cityArCtrl, _streetArCtrl; // <-- ADDED ARABIC CONTROLLERS
  late TextEditingController _freeDeliveryRangeCtrl, _noDeliveryRangeCtrl;
  late List<String> _offerCarousel;
  bool _isOpen = true;
  bool _isLoading = false;
  bool _isUploading = false;

  late MapController mapController;
  GeoPoint? selectedGeoPoint;
  LatLng? initialCenter;
  final TextEditingController searchController = TextEditingController();
  bool isMapLoading = true;

  @override
  void initState() {
    super.initState();

    mapController = MapController();

    final data = widget.initialData ?? {};

    _nameCtrl = TextEditingController(text: data['name'] ?? '');
    _emailCtrl = TextEditingController(text: data['email'] ?? '');
    _phoneCtrl = TextEditingController(text: data['phone']?.toString() ?? '');
    _estimatedTimeCtrl = TextEditingController(text: data['estimatedTime'] ?? '');
    _logoUrlCtrl = TextEditingController(text: data['logoUrl'] ?? '');
    _deliveryFeeCtrl = TextEditingController(text: (data['deliveryFee'] as num?)?.toString() ?? '0');
    _freeDeliveryRangeCtrl = TextEditingController(text: (data['freeDeliveryRange'] as num?)?.toString() ?? '0');
    _noDeliveryRangeCtrl = TextEditingController(text: (data['noDeliveryRange'] as num?)?.toString() ?? '0');

    final address = data['address'] as Map<String, dynamic>? ?? {};
    _cityCtrl = TextEditingController(text: address['city'] ?? '');
    _streetCtrl = TextEditingController(text: address['street'] ?? '');

    // <-- INITIALIZE NEW ARABIC CONTROLLERS
    _cityArCtrl = TextEditingController(text: address['city_ar'] ?? '');
    _streetArCtrl = TextEditingController(text: address['street_ar'] ?? '');

    final geo = address['geolocation'] as GeoPoint?;

    if (geo != null && (geo.latitude != 0 || geo.longitude != 0)) {
      selectedGeoPoint = geo;
      initialCenter = LatLng(geo.latitude, geo.longitude);
      isMapLoading = false;
    } else {
      _initializeMapToCurrentUserLocation();
    }

    _latCtrl = TextEditingController(text: selectedGeoPoint?.latitude.toString() ?? '0');
    _lngCtrl = TextEditingController(text: selectedGeoPoint?.longitude.toString() ?? '0');

    _offerCarousel = List<String>.from(data['offer_carousel'] ?? []);
    _isOpen = data['isOpen'] ?? true;
  }

  Future<void> _initializeMapToCurrentUserLocation() async {
    try {
      Position position = await _determinePosition();
      if (mounted) {
        setState(() {
          initialCenter = LatLng(position.latitude, position.longitude);
          selectedGeoPoint = GeoPoint(position.latitude, position.longitude);
          _latCtrl.text = position.latitude.toString();
          _lngCtrl.text = position.longitude.toString();
          isMapLoading = false;
        });
        mapController.move(initialCenter!, 15.0);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          initialCenter = LatLng(25.276987, 51.52002); // Default location (Doha)
          isMapLoading = false;
        });
      }
    }
  }

  Future<Position> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services are disabled.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return Future.error('Location permissions are permanently denied.');
    }

    return await Geolocator.getCurrentPosition();
  }

  Future<void> reverseGeocode(LatLng point) async {
    final url = 'https://nominatim.openstreetmap.org/reverse'
        '?format=json&lat=${point.latitude}&lon=${point.longitude}&addressdetails=1';
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'YourAppName/1.0',
          'Accept-Language': 'en', // Force English
        },
      );
      if (response.statusCode == 200 && mounted) {
        final data = json.decode(response.body);
        final address = data['address'];
        setState(() {
          _streetCtrl.text = address['road'] ?? data['display_name'] ?? '';
          _cityCtrl.text = address['city'] ?? address['town'] ?? address['village'] ?? '';

          // NOTE: Nominatim doesn't provide automatic Arabic reverse geocoding here,
          // so these fields will need to be manually entered by the user or
          // an additional call to a translation service would be needed.
          // We leave them empty on auto-update.
        });
      }
    } catch (e) {
      // Fail silently
    }
  }


  Future<void> forwardGeocode(String query) async {
    if (query.isEmpty) return;
    final url = 'https://nominatim.openstreetmap.org/search'
        '?format=json&q=$query&addressdetails=1&limit=1';
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'YourAppName/1.0',
          'Accept-Language': 'en', // Force English
        },
      );
      if (response.statusCode == 200 && mounted) {
        final data = json.decode(response.body);
        if (data.isNotEmpty) {
          final result = data[0];
          final lat = double.parse(result['lat']);
          final lon = double.parse(result['lon']);
          final point = LatLng(lat, lon);
          setState(() {
            selectedGeoPoint = GeoPoint(lat, lon);
            _latCtrl.text = lat.toString();
            _lngCtrl.text = lon.toString();
            mapController.move(point, 15.0);
          });
          await reverseGeocode(point); // Will fill English city/street
        }
      }
    } catch (e) {
      // Fail silently
    }
  }


  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _estimatedTimeCtrl.dispose();
    _logoUrlCtrl.dispose();
    _deliveryFeeCtrl.dispose();
    _freeDeliveryRangeCtrl.dispose();
    _noDeliveryRangeCtrl.dispose();
    _cityCtrl.dispose();
    _streetCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();

    // <-- DISPOSE NEW ARABIC CONTROLLERS
    _cityArCtrl.dispose();
    _streetArCtrl.dispose();

    searchController.dispose();
    super.dispose();
  }

  Future<void> _saveBranch() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final name = _nameCtrl.text.trim();
      final newDocId = name.replaceAll(RegExp(r'\s+'), '_');
      final isEdit = widget.docId != null;
      final docRef = FirebaseFirestore.instance.collection('Branch').doc(isEdit ? widget.docId : newDocId);

      if (isEdit && newDocId != widget.docId) {
        final exists = await FirebaseFirestore.instance.collection('Branch').doc(newDocId).get();
        if (exists.exists) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Branch name already exists.')));
          }
          return;
        }
        await docRef.set(await FirebaseFirestore.instance.collection('Branch').doc(widget.docId!).get().then((doc) => doc.data() ?? {}));
        await FirebaseFirestore.instance.collection('Branch').doc(widget.docId!).delete();
      }

      await docRef.set({
        'name': name,
        'email': _emailCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'estimatedTime': _estimatedTimeCtrl.text.trim(),
        'logoUrl': _logoUrlCtrl.text.trim(),
        'deliveryFee': double.tryParse(_deliveryFeeCtrl.text) ?? 0,
        'freeDeliveryRange': double.tryParse(_freeDeliveryRangeCtrl.text) ?? 0,
        'noDeliveryRange': double.tryParse(_noDeliveryRangeCtrl.text) ?? 0,
        'isOpen': _isOpen,
        'address': {
          'city': _cityCtrl.text.trim(),
          'street': _streetCtrl.text.trim(),
          'city_ar': _cityArCtrl.text.trim(), // <-- SAVING ARABIC CITY
          'street_ar': _streetArCtrl.text.trim(), // <-- SAVING ARABIC STREET
          'geolocation': GeoPoint(double.tryParse(_latCtrl.text) ?? 0, double.tryParse(_lngCtrl.text) ?? 0),
        },
        'offer_carousel': _offerCarousel,
        'Tables': {},
      }, SetOptions(merge: true));

      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Branch "$name" ${isEdit ? 'updated' : 'added'} successfully!'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> pickAndUploadImage() async {
    setState(() {
      _isUploading = true;
    });

    final picker = ImagePicker();

    try {
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
      if (image == null) {
        setState(() {
          _isUploading = false;
        });
        return;
      }

      final Uint8List imageBytes = await image.readAsBytes();
      final Uint8List webpBytes = await FlutterImageCompress.compressWithList(imageBytes, minHeight: 1080, minWidth: 1080, quality: 80, format: CompressFormat.webp);
      String fileName = 'promo_ ${DateTime.now().millisecondsSinceEpoch}.webp';

      Reference storageRef = FirebaseStorage.instance.ref().child('promotions/ $fileName');
      UploadTask uploadTask = storageRef.putData(webpBytes);
      TaskSnapshot taskSnapshot = await uploadTask;
      String downloadUrl = await taskSnapshot.ref.getDownloadURL();

      setState(() {
        _offerCarousel.add(downloadUrl);
        _isUploading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Offer image added successfully as WebP!'), backgroundColor: Colors.green));
      }
    } catch (e) {
      setState(() {
        _isUploading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to upload image: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> deleteImageFromStorage(String imageUrl) async {
    try {
      Reference storageRef = FirebaseStorage.instance.refFromURL(imageUrl);
      await storageRef.delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Image successfully deleted from storage.'), backgroundColor: Colors.orange));
      }
    } on FirebaseException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete image: ${e.message}'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.docId != null;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.95, maxWidth: MediaQuery.of(context).size.width * 0.95),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(isEdit ? 'Edit Branch' : 'Add New Branch', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
              const Divider(),
              const SizedBox(height: 10),
              Expanded(
                child: SingleChildScrollView(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Basic Information Card
                        Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Basic Information', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _nameCtrl,
                                  decoration: InputDecoration(
                                    labelText: 'Branch Name *',
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0)),
                                    prefixIcon: const Icon(Icons.business_outlined, color: Colors.deepPurple),
                                  ),
                                  validator: (v) => v?.isEmpty ?? true ? 'Branch name is required' : null,
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _emailCtrl,
                                  decoration: InputDecoration(
                                    labelText: 'Email',
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0)),
                                    prefixIcon: const Icon(Icons.email_outlined, color: Colors.deepPurple),
                                  ),
                                  keyboardType: TextInputType.emailAddress,
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _phoneCtrl,
                                  decoration: InputDecoration(
                                    labelText: 'Phone',
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0)),
                                    prefixIcon: const Icon(Icons.phone_outlined, color: Colors.deepPurple),
                                  ),
                                  keyboardType: TextInputType.phone,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Business Details Card
                        Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Business Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _estimatedTimeCtrl,
                                  decoration: InputDecoration(
                                    labelText: 'Estimated Time (minutes)',
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0)),
                                    prefixIcon: const Icon(Icons.timer_outlined, color: Colors.deepPurple),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _deliveryFeeCtrl,
                                  decoration: InputDecoration(
                                    labelText: 'Delivery Fee',
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0)),
                                    prefixIcon: const Icon(Icons.attach_money, color: Colors.deepPurple),
                                  ),
                                  keyboardType: TextInputType.number,
                                ),
                                const SizedBox(height: 16),
                                // NEW: Free Delivery Range Field
                                TextFormField(
                                  controller: _freeDeliveryRangeCtrl,
                                  decoration: InputDecoration(
                                    labelText: 'Free Delivery Range (km)',
                                    hintText: 'e.g., 10',
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0)),
                                    prefixIcon: const Icon(Icons.local_shipping_outlined, color: Colors.deepPurple),
                                  ),
                                  keyboardType: TextInputType.number,
                                  validator: (value) {
                                    if (value != null && value.isNotEmpty) {
                                      final numValue = double.tryParse(value);
                                      if (numValue == null || numValue < 0) {
                                        return 'Please enter a valid positive number';
                                      }
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                // NEW: No Delivery Range Field
                                TextFormField(
                                  controller: _noDeliveryRangeCtrl,
                                  decoration: InputDecoration(
                                    labelText: 'No Delivery Range (km)',
                                    hintText: 'e.g., 15',
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0)),
                                    prefixIcon: const Icon(Icons.do_not_disturb_outlined, color: Colors.deepPurple),
                                  ),
                                  keyboardType: TextInputType.number,
                                  validator: (value) {
                                    if (value != null && value.isNotEmpty) {
                                      final numValue = double.tryParse(value);
                                      if (numValue == null || numValue < 0) {
                                        return 'Please enter a valid positive number';
                                      }
                                      // Validate that noDeliveryRange is greater than freeDeliveryRange
                                      final freeRange = double.tryParse(_freeDeliveryRangeCtrl.text) ?? 0;
                                      if (numValue <= freeRange) {
                                        return 'No delivery range must be greater than free delivery range';
                                      }
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _logoUrlCtrl,
                                  decoration: InputDecoration(
                                    labelText: 'Logo URL',
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0)),
                                    prefixIcon: const Icon(Icons.image_outlined, color: Colors.deepPurple),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Address Card with Map
                        Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Address Information', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _cityCtrl,
                                  decoration: InputDecoration(
                                    labelText: 'City (English)',
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0)),
                                    prefixIcon: const Icon(Icons.location_city_outlined, color: Colors.deepPurple),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _cityArCtrl, // <-- ADDED ARABIC CITY FIELD
                                  textDirection: TextDirection.rtl,
                                  textAlign: TextAlign.right,
                                  decoration: InputDecoration(
                                    labelText: 'City (Arabic)',
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0)),
                                    prefixIcon: const Icon(Icons.location_city_outlined, color: Colors.deepPurple),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _streetCtrl,
                                  decoration: InputDecoration(
                                    labelText: 'Street (English)',
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0)),
                                    prefixIcon: const Icon(Icons.location_on_outlined, color: Colors.deepPurple),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _streetArCtrl, // <-- ADDED ARABIC STREET FIELD
                                  textDirection: TextDirection.rtl,
                                  textAlign: TextAlign.right,
                                  decoration: InputDecoration(
                                    labelText: 'Street (Arabic)',
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0)),
                                    prefixIcon: const Icon(Icons.location_on_outlined, color: Colors.deepPurple),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Location on Map', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.deepPurple)),
                                    const SizedBox(height: 8),
                                    TextFormField(
                                      controller: searchController,
                                      decoration: InputDecoration(
                                        labelText: 'Search for a location',
                                        prefixIcon: const Icon(Icons.search, color: Colors.deepPurple),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0)),
                                      ),
                                      onFieldSubmitted: (value) {
                                        forwardGeocode(value);
                                      },
                                    ),
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      height: 250,
                                      child: isMapLoading
                                          ? Center(child: CircularProgressIndicator(color: Colors.deepPurple))
                                          : ClipRRect(
                                        borderRadius: BorderRadius.circular(12.0),
                                        child: FlutterMap(
                                          mapController: mapController,
                                          options: MapOptions(
                                            center: initialCenter ?? LatLng(0, 0),
                                            zoom: 15.0,
                                            onTap: (tapPosition, point) {
                                              setState(() {
                                                selectedGeoPoint = GeoPoint(point.latitude, point.longitude);
                                                _latCtrl.text = point.latitude.toString();
                                                _lngCtrl.text = point.longitude.toString();

                                                // Clear Arabic fields on map interaction, as reverse geocoding only provides English.
                                                _cityArCtrl.clear();
                                                _streetArCtrl.clear();
                                              });
                                              reverseGeocode(point);
                                            },
                                          ),
                                          children: [
                                            TileLayer(
                                              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                              userAgentPackageName: 'com.example.mdd',
                                            ),
                                            if (selectedGeoPoint != null)
                                              MarkerLayer(
                                                markers: [
                                                  Marker(
                                                    point: LatLng(selectedGeoPoint!.latitude, selectedGeoPoint!.longitude),
                                                    width: 80,
                                                    height: 80,
                                                    child: const Icon(Icons.location_pin, color: Colors.red, size: 40), // Use 'child' instead of 'builder'
                                                  ),
                                                ],
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text('Tap on the map to select the exact location.', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                                    const SizedBox(height: 16),
                                    // Row(
                                    //   children: [
                                    //     Expanded(
                                    //       child: TextFormField(
                                    //         controller: _latCtrl,
                                    //         readOnly: true,
                                    //         decoration: InputDecoration(
                                    //           labelText: 'Latitude',
                                    //           border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0)),
                                    //           prefixIcon: const Icon(Icons.my_location_outlined, color: Colors.deepPurple),
                                    //         ),
                                    //       ),
                                    //     ),
                                    //     const SizedBox(width: 8),
                                    //     Expanded(
                                    //       child: TextFormField(
                                    //         controller: _lngCtrl,
                                    //         readOnly: true,
                                    //         decoration: InputDecoration(
                                    //           labelText: 'Longitude',
                                    //           border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0)),
                                    //           prefixIcon: const Icon(Icons.place_outlined, color: Colors.deepPurple),
                                    //         ),
                                    //       ),
                                    //     ),
                                    //   ],
                                    // ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Offers Card
                        Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Offer Carousel', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                                    _isUploading
                                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.deepPurple))
                                        : IconButton(
                                      icon: const Icon(Icons.add_photo_alternate_outlined),
                                      color: Colors.deepPurple,
                                      onPressed: pickAndUploadImage,
                                      tooltip: 'Add Offer Image',
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                if (_offerCarousel.isEmpty)
                                  const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(16.0),
                                      child: Text('No offers added yet.', style: TextStyle(color: Colors.grey)),
                                    ),
                                  )
                                else
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: _offerCarousel.map((url) {
                                      return Chip(
                                        avatar: CircleAvatar(backgroundImage: NetworkImage(url), backgroundColor: Colors.grey.shade200),
                                        label: const Text('Image', overflow: TextOverflow.ellipsis),
                                        deleteIcon: const Icon(Icons.close, size: 18),
                                        onDeleted: () async {
                                          await deleteImageFromStorage(url);
                                          setState(() {
                                            _offerCarousel.remove(url);
                                          });
                                        },
                                        backgroundColor: Colors.deepPurple.withOpacity(0.1),
                                        deleteIconColor: Colors.deepPurple,
                                      );
                                    }).toList(),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Status Card
                        Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Branch Status', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                                const SizedBox(height: 12),
                                SwitchListTile(
                                  title: const Text('Is Open'),
                                  subtitle: Text(_isOpen ? 'Branch is currently open' : 'Branch is currently closed'),
                                  value: _isOpen,
                                  onChanged: (value) => setState(() => _isOpen = value),
                                  activeColor: Colors.green,
                                  inactiveTrackColor: Colors.red.withOpacity(0.5),
                                  inactiveThumbColor: Colors.red,
                                  secondary: Icon(_isOpen ? Icons.radio_button_checked : Icons.radio_button_off, color: _isOpen ? Colors.green : Colors.red),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isLoading ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), side: const BorderSide(color: Colors.deepPurple)),
                      child: const Text('Cancel', style: TextStyle(color: Colors.deepPurple, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _saveBranch,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      child: _isLoading
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(isEdit ? 'Update Branch' : 'Add Branch', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}