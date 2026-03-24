import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart'; // UserScopeService
import '../Widgets/BranchFilterService.dart';
import '../utils/responsive_helper.dart'; // ✅ Added

class TableManagementScreen extends StatefulWidget {
  const TableManagementScreen({super.key});

  @override
  State<TableManagementScreen> createState() => _TableManagementScreenState();
}

class _TableManagementScreenState extends State<TableManagementScreen> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final userScope = context.watch<UserScopeService>();
    final branchFilter = context.watch<BranchFilterService>();

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        centerTitle: true,
        title: const Text(
          'Table Management',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.deepPurple,
            fontSize: 24,
          ),
        ),
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
                hintText: 'Search branches...',
                prefixIcon: const Icon(Icons.search, color: Colors.deepPurple),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.grey),
                        onPressed: () => setState(() => _searchQuery = ''),
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
              ),
              onChanged: (query) {
                setState(() => _searchQuery = query.toLowerCase().trim());
              },
            ),
          ),

          // Enhanced Branch List
          Expanded(
            child: _buildBranchList(context, userScope, branchFilter),
          ),
        ],
      ),
    );
  }

  Widget _buildBranchList(BuildContext context, UserScopeService userScope,
      BranchFilterService branchFilter) {
    // Determine which branches to show based on role
    Stream<QuerySnapshot> branchStream;

    final filterBranchIds = branchFilter.getFilterBranchIds(userScope.branchIds);

    if (filterBranchIds.isNotEmpty) {
      // Use filtered branches
      branchStream = FirebaseFirestore.instance
          .collection('Branch')
          .where(FieldPath.documentId, whereIn: filterBranchIds.take(10).toList())
          .snapshots();
    } else {
      // SuperAdmins see ALL branches if no specific branch is selected
      branchStream =
          FirebaseFirestore.instance.collection('Branch').snapshots();
    }

    return StreamBuilder<QuerySnapshot>(
      stream: branchStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(Colors.deepPurple),
                ),
                const SizedBox(height: 16),
                Text(
                  'Loading branches...',
                  style: TextStyle(color: Colors.grey[600], fontSize: 16),
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
                Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
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
                Icon(Icons.business_outlined,
                    size: 64, color: Colors.grey[400]),
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
                  'Add a branch to get started.',
                  style: TextStyle(color: Colors.grey[500], fontSize: 14),
                ),
              ],
            ),
          );
        }

        final allBranches = snapshot.data!.docs;

        // Apply client-side search filtering
        final branches = _searchQuery.isEmpty
            ? allBranches
            : allBranches.where((doc) {
                final branchData = doc.data() as Map<String, dynamic>;
                final name =
                    (branchData['name'] ?? '').toString().toLowerCase();
                final branchId = doc.id.toLowerCase();
                return name.contains(_searchQuery) ||
                    branchId.contains(_searchQuery);
              }).toList();

        if (branches.isEmpty && _searchQuery.isNotEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.search_off_rounded,
                    size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No branches match "$_searchQuery"',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Try a different search term.',
                  style: TextStyle(color: Colors.grey[500], fontSize: 14),
                ),
              ],
            ),
          );
        }

        // Use ListView for all screen sizes to allow ExpansionTile to grow
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: branches.length,
          itemBuilder: (context, index) {
            final branchDoc = branches[index];
            final branchData = branchDoc.data() as Map<String, dynamic>;
            final name = branchData['name'] ?? 'Unnamed Branch';
            final Map<String, dynamic> tables = Map<String, dynamic>.from(
                branchData['Tables'] as Map<String, dynamic>? ?? {});

            return _BranchTableCard(
              branchId: branchDoc.id,
              branchName: name,
              tables: tables,
            );
          },
        );
      },
    );
  }
}

class _BranchTableCard extends StatelessWidget {
  final String branchId;
  final String branchName;
  final Map<String, dynamic> tables;

  const _BranchTableCard({
    required this.branchId,
    required this.branchName,
    required this.tables,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
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
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          childrenPadding:
              const EdgeInsets.only(left: 16, right: 16, bottom: 16),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.business_rounded,
                  color: Colors.deepPurple,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      branchName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.table_restaurant_rounded,
                            size: 16, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          '${tables.length} tables',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          initiallyExpanded: tables.isNotEmpty,
          trailing: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.deepPurple,
              borderRadius: BorderRadius.circular(10),
            ),
            child: IconButton(
              icon:
                  const Icon(Icons.add_rounded, color: Colors.white, size: 20),
              onPressed: () => _showAddTableDialog(context, branchId, tables),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: 'Add Table',
            ),
          ),
          children: tables.isEmpty
              ? [
                  Container(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Icon(Icons.table_restaurant_outlined,
                            size: 48, color: Colors.grey[400]),
                        const SizedBox(height: 12),
                        Text(
                          'No tables in this branch',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tap the + button to add your first table',
                          style:
                              TextStyle(color: Colors.grey[500], fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ]
              : [
                  // ✅ RESPONSIVE TABLE GRID OR LIST
                  if (ResponsiveHelper.isTablet(context) ||
                      ResponsiveHelper.isDesktop(context))
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: GridView.builder(
                        physics: const NeverScrollableScrollPhysics(),
                        shrinkWrap: true,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount:
                              ResponsiveHelper.isDesktop(context) ? 2 : 2,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: 2.2,
                        ),
                        itemCount: tables.length,
                        itemBuilder: (context, index) {
                          final entry = tables.entries.elementAt(index);
                          final tableId = entry.key;
                          final Map<String, dynamic> tableData =
                              Map<String, dynamic>.from(
                                  entry.value as Map<String, dynamic>);
                          return _TableCardLarge(
                            branchId: branchId,
                            tableId: tableId,
                            tableData: tableData,
                            allTables: tables,
                          );
                        },
                      ),
                    )
                  else
                    ...tables.entries.map((entry) {
                      final tableId = entry.key;
                      final Map<String, dynamic> tableData =
                          Map<String, dynamic>.from(
                              entry.value as Map<String, dynamic>);
                      return _TableListItem(
                        branchId: branchId,
                        tableId: tableId,
                        tableData: tableData,
                        allTables: tables,
                      );
                    }).toList(),
                ],
        ),
      ),
    );
  }

  void _showAddTableDialog(BuildContext context, String branchId,
      Map<String, dynamic> currentTables) {
    _showStandardTableDialog(
      context,
      branchId: branchId,
      existingTableData: const {},
      isEdit: false,
    );
  }
}

// ── Shared Table Dialog ───────────────────────────────────────────
void _showStandardTableDialog(
  BuildContext context, {
  required String branchId,
  bool isEdit = false,
  String? existingTableId,
  Map<String, dynamic>? existingTableData,
}) {
  final nameController =
      TextEditingController(text: existingTableData?['name']?.toString() ?? '');
  final zoneController = TextEditingController(
      text: (existingTableData?['zone'] ?? existingTableData?['floor'] ?? '')
          .toString());
  final seatsController = TextEditingController(
      text: (existingTableData?['seats'] ?? '4').toString());
  String selectedShape =
      (existingTableData?['shape'] ?? 'square').toString().toLowerCase();
  if (selectedShape != 'round' && selectedShape != 'square') {
    selectedShape = 'square';
  }

  showDialog(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            titlePadding: EdgeInsets.zero,
            title: Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Colors.deepPurple,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  Icon(isEdit ? Icons.edit_rounded : Icons.add_rounded,
                      color: Colors.white),
                  const SizedBox(width: 12),
                  Text(
                    isEdit ? 'Edit Table' : 'Add New Table',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 8),
                    _buildDialogField(
                      label: 'Table Name / Number',
                      controller: nameController,
                      icon: Icons.badge_outlined,
                      hint: 'e.g. Table 1 or T-1',
                    ),
                    const SizedBox(height: 16),
                    _buildDialogField(
                      label: 'Zone / Floor',
                      controller: zoneController,
                      icon: Icons.layers_outlined,
                      hint: 'e.g. Ground Floor, VIP, Terrace',
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildDialogField(
                            label: 'Seats',
                            controller: seatsController,
                            icon: Icons.person_outline,
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Shape',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                decoration: BoxDecoration(
                                  color: Colors.grey[50],
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.grey[200]!),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: selectedShape,
                                    isExpanded: true,
                                    items: ['square', 'round']
                                        .map((shape) => DropdownMenuItem(
                                              value: shape,
                                              child: Text(shape[0]
                                                      .toUpperCase() +
                                                  shape.substring(1)),
                                            ))
                                        .toList(),
                                    onChanged: (val) {
                                      if (val != null) {
                                        setDialogState(() {
                                          selectedShape = val;
                                        });
                                      }
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
              ),
              ElevatedButton(
                onPressed: () async {
                  final name = nameController.text.trim();
                  if (name.isEmpty) return;

                  final zone = zoneController.text.trim();
                  final seats = int.tryParse(seatsController.text) ?? 4;

                  final tableMap = {
                    'name': name,
                    'zone': zone,
                    'seats': seats,
                    'shape': selectedShape,
                    'status': existingTableData?['status'] ?? 'available',
                    'updatedAt': FieldValue.serverTimestamp(),
                    if (!isEdit) 'createdAt': FieldValue.serverTimestamp(),
                  };

                  try {
                    final branchRef = FirebaseFirestore.instance
                        .collection('Branch')
                        .doc(branchId);
                    final snap = await branchRef.get();
                    final Map<String, dynamic> allTables =
                        Map<String, dynamic>.from(snap.data()?['Tables']
                                as Map<String, dynamic>? ??
                            {});

                    if (isEdit && existingTableId != null) {
                      allTables[existingTableId] = tableMap;
                    } else {
                      final newId =
                          DateTime.now().millisecondsSinceEpoch.toString();
                      allTables[newId] = tableMap;
                    }

                    await branchRef.update({'Tables': allTables});

                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(isEdit
                            ? 'Table updated successfully'
                            : 'Table added successfully'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e')),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: Text(isEdit ? 'Save Changes' : 'Add Table'),
              ),
            ],
          );
        },
      );
    },
  );
}

Widget _buildDialogField({
  required String label,
  required TextEditingController controller,
  required IconData icon,
  String? hint,
  TextInputType keyboardType = TextInputType.text,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.grey[600],
        ),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(icon, size: 20, color: Colors.deepPurple),
          filled: true,
          fillColor: Colors.grey[50],
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey[200]!),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey[200]!),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.deepPurple.withOpacity(0.5)),
          ),
        ),
      ),
    ],
  );
}

class _TableListItem extends StatelessWidget {
  final String branchId;
  final String tableId;
  final Map<String, dynamic> tableData;
  final Map<String, dynamic> allTables;

  const _TableListItem({
    required this.branchId,
    required this.tableId,
    required this.tableData,
    required this.allTables,
  });

  @override
  Widget build(BuildContext context) {
    final seats = tableData['seats'] ?? 0;
    final status = (tableData['status'] ?? 'available').toString();

    Color statusColor;
    Color statusBgColor;
    IconData statusIcon;

    switch (status) {
      case 'available':
        statusColor = Colors.green;
        statusBgColor = Colors.green.withOpacity(0.1);
        statusIcon = Icons.check_circle_rounded;
        break;
      case 'occupied':
        statusColor = Colors.orange;
        statusBgColor = Colors.orange.withOpacity(0.1);
        statusIcon = Icons.people_rounded;
        break;
      case 'reserved':
        statusColor = Colors.blue;
        statusBgColor = Colors.blue.withOpacity(0.1);
        statusIcon = Icons.bookmark_rounded;
        break;
      case 'ordered':
        statusColor = Colors.purple;
        statusBgColor = Colors.purple.withOpacity(0.1);
        statusIcon = Icons.restaurant_menu_rounded;
        break;
      default:
        statusColor = Colors.grey;
        statusBgColor = Colors.grey.withOpacity(0.1);
        statusIcon = Icons.help_rounded;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!, width: 1),
      ),
      // ✅ REPLACED ListTile with custom Row for proper large screen layout
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Leading status icon
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: statusBgColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(statusIcon, color: statusColor, size: 24),
            ),
            const SizedBox(width: 16),
            // Title and subtitle - takes remaining space
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      'Table $tableId',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.black87,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // ✅ Use Wrap to prevent overflow on small screens
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.chair_rounded,
                              size: 16, color: Colors.grey[600]),
                          const SizedBox(width: 4),
                          Text(
                            '$seats seats',
                            style: TextStyle(
                                color: Colors.grey[600], fontSize: 14),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: statusBgColor,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          status.toUpperCase(),
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            // Action buttons - fixed size, won't squish
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Material(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => _showEditTableDialog(context),
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(Icons.edit_rounded,
                          color: Colors.blue, size: 20),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => _confirmDelete(context),
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(Icons.delete_rounded,
                          color: Colors.red, size: 20),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showEditTableDialog(BuildContext context) {
    _showStandardTableDialog(
      context,
      branchId: branchId,
      existingTableData: tableData,
      isEdit: true,
      existingTableId: tableId,
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_rounded, color: Colors.red, size: 28),
            const SizedBox(width: 12),
            const Text('Confirm Delete',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
            'Are you sure you want to delete this table? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
            child: Text('Cancel',
                style: TextStyle(
                    color: Colors.grey[600], fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Delete',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final updatedTables = Map<String, dynamic>.from(allTables);
      updatedTables.remove(tableId);
      await FirebaseFirestore.instance
          .collection('Branch')
          .doc(branchId)
          .update({'Tables': updatedTables});
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Table deleted successfully'),
              backgroundColor: Colors.green),
        );
      }
    }
  }

}

class _TableCardLarge extends StatelessWidget {
  final String branchId;
  final String tableId;
  final Map<String, dynamic> tableData;
  final Map<String, dynamic> allTables;

  const _TableCardLarge({
    required this.branchId,
    required this.tableId,
    required this.tableData,
    required this.allTables,
  });

  @override
  Widget build(BuildContext context) {
    final seats = tableData['seats'] ?? 0;
    final status = (tableData['status'] ?? 'available').toString();

    Color statusColor;
    Color statusBgColor;
    IconData statusIcon;

    switch (status) {
      case 'available':
        statusColor = Colors.green;
        statusBgColor = Colors.green.withOpacity(0.1);
        statusIcon = Icons.check_circle_rounded;
        break;
      case 'occupied':
        statusColor = Colors.orange;
        statusBgColor = Colors.orange.withOpacity(0.1);
        statusIcon = Icons.people_rounded;
        break;
      case 'reserved':
        statusColor = Colors.blue;
        statusBgColor = Colors.blue.withOpacity(0.1);
        statusIcon = Icons.bookmark_rounded;
        break;
      case 'ordered':
        statusColor = Colors.purple;
        statusBgColor = Colors.purple.withOpacity(0.1);
        statusIcon = Icons.restaurant_menu_rounded;
        break;
      default:
        statusColor = Colors.grey;
        statusBgColor = Colors.grey.withOpacity(0.1);
        statusIcon = Icons.help_rounded;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Status Indicator (Left Bar)
          Container(
            width: 4,
            height: 40,
            decoration: BoxDecoration(
              color: statusColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),

          // Main Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Table $tableId',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.chair_rounded,
                        size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      '$seats Seats',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusBgColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        status.toUpperCase(),
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Actions
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit_rounded,
                    color: Colors.blue, size: 20),
                onPressed: () => _TableListItem(
                        branchId: branchId,
                        tableId: tableId,
                        tableData: tableData,
                        allTables: allTables)
                    ._showEditTableDialog(context),
                tooltip: 'Edit',
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(8),
              ),
              IconButton(
                icon: const Icon(Icons.delete_rounded,
                    color: Colors.red, size: 20),
                onPressed: () => _TableListItem(
                        branchId: branchId,
                        tableId: tableId,
                        tableData: tableData,
                        allTables: allTables)
                    ._confirmDelete(context),
                tooltip: 'Delete',
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(8),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
