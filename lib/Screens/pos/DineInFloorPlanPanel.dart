import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../main.dart';
import '../../../../constants.dart';
import '../../../../Widgets/BranchFilterService.dart';
import '../../../../services/pos/pos_service.dart';
import 'TableOrdersDialog.dart';
import '../../../../Widgets/PrintingService.dart';
import '../management/TableManagement.dart';

class DineInFloorPlanPanel extends StatefulWidget {
  final VoidCallback onSwitchToPos;

  const DineInFloorPlanPanel({
    super.key,
    required this.onSwitchToPos,
  });

  @override
  State<DineInFloorPlanPanel> createState() => _DineInFloorPlanPanelState();
}

class _DineInFloorPlanPanelState extends State<DineInFloorPlanPanel> {
  static final Map<String, String> _floorPreferences = {};
  String get _selectedFloor {
    final branchId = _currentBranchId;
    return _floorPreferences[branchId] ?? 'All';
  }
  set _selectedFloor(String value) {
    final branchId = _currentBranchId;
    if (branchId.isNotEmpty) {
      _floorPreferences[branchId] = value;
    }
  }

  String get _currentBranchId {
    try {
      final pos = Provider.of<PosService>(context, listen: false);
      final branchFilter = Provider.of<BranchFilterService>(context, listen: false);
      final userScope = Provider.of<UserScopeService>(context, listen: false);
      return pos.activeBranchId ??
          (branchFilter.getFilterBranchIds(userScope.branchIds).isNotEmpty
              ? branchFilter.getFilterBranchIds(userScope.branchIds).first
              : '');
    } catch (_) {
      return '';
    }
  }

  bool _isEditMode = false;

  @override
  Widget build(BuildContext context) {
    final userScope = context.watch<UserScopeService>();
    final pos = context.watch<PosService>();
    final branchFilter = context.watch<BranchFilterService>();

    final isSuperAdmin = userScope.isSuperAdmin;

    // Prioritize the explicitly selected POS branch for the floor plan
    final currentBranchId = pos.activeBranchId ??
        (branchFilter.getFilterBranchIds(userScope.branchIds).isNotEmpty
            ? branchFilter.getFilterBranchIds(userScope.branchIds).first
            : '');

    final effectiveBranchIds = currentBranchId.isNotEmpty
        ? [currentBranchId]
        : branchFilter.getFilterBranchIds(userScope.branchIds);

    return Container(
      color: Colors.grey[100],
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.table_bar,
                    color: Colors.deepPurple, size: 28),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Floor Plan',
                      style:
                          TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  Text(
                    _isEditMode
                        ? 'Edit mode: Tap tables to modify or add new ones'
                        : 'Select a table to manage orders',
                    style: TextStyle(
                        fontSize: 14,
                        color: _isEditMode ? Colors.orange[800] : Colors.grey),
                  ),
                ],
              ),
              const Spacer(),
              // Super Admin Controls
              if (isSuperAdmin) ...[
                if (_isEditMode)
                  ElevatedButton.icon(
                    onPressed: () =>
                        _showAddTableDialog(context, currentBranchId),
                    icon: const Icon(Icons.add),
                    label: const Text('Add Table'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                    ),
                  ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _isEditMode = !_isEditMode;
                    });
                  },
                  icon: Icon(_isEditMode ? Icons.check : Icons.edit),
                  label: Text(_isEditMode ? 'Done Editing' : 'Edit Floor Plan'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isEditMode ? Colors.green : Colors.white,
                    foregroundColor:
                        _isEditMode ? Colors.white : Colors.deepPurple,
                  ),
                ),
                const SizedBox(width: 24),
              ],
              // Legend
              _buildLegendDot(Colors.green, 'Available'),
              const SizedBox(width: 16),
              _buildLegendDot(Colors.red, 'Occupied'),
              const SizedBox(width: 16),
              _buildLegendDot(Colors.orange, 'Reserved'),
            ],
          ),
          const SizedBox(height: 24),

          // ── Floor Plan Grid ──
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _getActiveTableOrdersStream(context, effectiveBranchIds),
              builder: (context, ordersSnapshot) {
                final occupiedTableIds = <String>{};
                if (ordersSnapshot.hasData) {
                  for (final doc in ordersSnapshot.data!.docs) {
                    final data = doc.data();
                    final tid = data['tableId']?.toString();
                    if (tid != null && tid.isNotEmpty) {
                      occupiedTableIds.add(tid);
                    }
                  }
                }

                return StreamBuilder(
                  stream: _getTablesStream(context, effectiveBranchIds),
                  builder: (context, AsyncSnapshot snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting &&
                        !snapshot.hasData) {
                      return const Center(
                          child: CircularProgressIndicator(
                              color: Colors.deepPurple));
                    }

                    if (!snapshot.hasData || snapshot.data == null) {
                      return _buildEmptyState('No tables configured',
                          'Set up tables to start managing dine-in orders');
                    }

                    final branchData =
                        snapshot.data!.data() as Map<String, dynamic>?;
                    final tables = (branchData?['Tables'] ??
                            branchData?['tables']) as Map<String, dynamic>? ??
                        {};

                    if (tables.isEmpty) {
                      return _buildEmptyState('No tables found',
                          'Use the Edit Floor Plan button to add tables');
                    }

                    final tableEntries = tables.entries.toList()
                      ..sort((a, b) => (a.value['name'] ?? a.key)
                          .toString()
                          .compareTo((b.value['name'] ?? b.key).toString()));

                    // Extract unique zones/floors
                    final zones = <String>{'All'};
                    for (final entry in tableEntries) {
                      final zone = (entry.value as Map<String, dynamic>)['zone']
                              ?.toString() ??
                          (entry.value as Map<String, dynamic>)['floor']
                              ?.toString() ??
                          '';
                      if (zone.isNotEmpty) zones.add(zone);
                    }

                    // Filter by selected floor/zone
                    final filtered = _selectedFloor == 'All'
                        ? tableEntries
                        : tableEntries.where((e) {
                            final data = e.value as Map<String, dynamic>;
                            final zone = data['zone']?.toString() ??
                                data['floor']?.toString() ??
                                '';
                            return zone == _selectedFloor;
                          }).toList();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Zone/Floor tabs
                        if (zones.length > 1)
                          SizedBox(
                            height: 44,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: zones.map((zone) {
                                final isSelected = _selectedFloor == zone;
                                return Padding(
                                  padding: const EdgeInsets.only(right: 12),
                                  child: FilterChip(
                                    showCheckmark: false,
                                    label: Text(zone),
                                    selected: isSelected,
                                    selectedColor: Colors.deepPurple,
                                    backgroundColor: Colors.white,
                                    labelStyle: TextStyle(
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.grey[700],
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.w500,
                                      fontSize: 14,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 10),
                                    onSelected: (_) =>
                                        setState(() => _selectedFloor = zone),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(24),
                                        side: BorderSide(
                                          color: isSelected
                                              ? Colors.deepPurple
                                              : Colors.grey[300]!,
                                        )),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        if (zones.length > 1) const SizedBox(height: 20),

                        // Tables grid
                        Expanded(
                          child: GridView.builder(
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 180,
                              crossAxisSpacing: 20,
                              mainAxisSpacing: 20,
                              childAspectRatio: 1.0,
                            ),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final entry = filtered[index];
                              final tableData =
                                  entry.value as Map<String, dynamic>;
                              return _FullScreenFloorPlanTable(
                                tableId: entry.key,
                                tableData: tableData,
                                occupiedTableIds: occupiedTableIds,
                                isEditMode: _isEditMode,
                                onSelect: (tableId, tableName) {
                                  if (_isEditMode) {
                                    _showEditTableDialog(
                                        context,
                                        currentBranchId,
                                        tableId,
                                        tableData,
                                        tables);
                                  } else {
                                    _handleTableSelect(context, tableId,
                                        tableName, currentBranchId,
                                        maxSeats: tableData['seats'] != null ? int.tryParse(tableData['seats'].toString()) : null);
                                  }
                                },
                                onOccupiedTap: (tableId, tableName) {
                                  if (_isEditMode) {
                                    _showEditTableDialog(
                                        context,
                                        currentBranchId,
                                        tableId,
                                        tableData,
                                        tables);
                                  } else {
                                    _handleOccupiedTableTap(context, tableId,
                                        tableName, currentBranchId);
                                  }
                                },
                              );
                            },
                          ),
                        ),
                      ],
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

  Widget _buildEmptyState(String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.table_bar, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 24),
          Text(title,
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[600])),
          const SizedBox(height: 8),
          Text(subtitle,
              style: TextStyle(fontSize: 15, color: Colors.grey[500])),
        ],
      ),
    );
  }

  Widget _buildLegendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.grey[700])),
      ],
    );
  }

  Stream? _getTablesStream(BuildContext context, List<String> branchIds) {
    try {
      if (branchIds.isEmpty) return null;
      return FirebaseFirestore.instance
          .collection('Branch')
          .doc(branchIds.first)
          .snapshots();
    } catch (e) {
      return null;
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>>? _getActiveTableOrdersStream(
      BuildContext context, List<String> branchIds) {
    try {
      if (branchIds.isEmpty) return null;

      return FirebaseFirestore.instance
          .collection(AppConstants.collectionOrders)
          .where('branchIds', arrayContainsAny: branchIds)
          .where('Order_type', isEqualTo: 'dine_in')
          .where('status', whereIn: [
        AppConstants.statusPending,
        AppConstants.statusPreparing,
        AppConstants.statusPrepared,
        AppConstants.statusServed,
      ]).snapshots();
    } catch (e) {
      return null;
    }
  }

  Future<void> _handleTableSelect(
      BuildContext context, String tableId, String tableName, String branchId, {int? maxSeats}) async {
    int guestCount = 1;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('Table $tableName'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Enter number of guests:'),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: guestCount > 1
                          ? () => setDialogState(() => guestCount--)
                          : null,
                    ),
                    Text('$guestCount', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: () => setDialogState(() => guestCount++),
                    ),
                  ],
                ),
                if (maxSeats != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('Capacity: $maxSeats', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Proceed'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed == true && context.mounted) {
      final pos = context.read<PosService>();
      pos.clearCart();
      pos.loadTableContext(tableId, tableName, guestCount: guestCount, branchIds: [branchId]);
      widget.onSwitchToPos();
    }
  }

  void _handleOccupiedTableTap(
      BuildContext context, String tableId, String tableName, String branchId) {
    final pos = context.read<PosService>();
    pos.clearCart();
    pos.loadTableContext(tableId, tableName, branchIds: [branchId]);
    widget.onSwitchToPos();
  }

  // ── Super Admin Editing Methods ──

  void _showAddTableDialog(BuildContext context, String branchId) {
    _showTableEditorDialog(context, branchId, null, null, {});
  }

  void _showEditTableDialog(
      BuildContext context,
      String branchId,
      String tableId,
      Map<String, dynamic> tableData,
      Map<String, dynamic> allTables) {
    _showTableEditorDialog(context, branchId, tableId, tableData, allTables);
  }

  void _showTableEditorDialog(
      BuildContext context,
      String branchId,
      String? tableId,
      Map<String, dynamic>? initialData,
      Map<String, dynamic> allTables) {
    final isEdit = tableId != null;
    final nameController =
        TextEditingController(text: initialData?['name']?.toString() ?? '');
    final seatsController =
        TextEditingController(text: initialData?['seats']?.toString() ?? '4');
    final zoneController = TextEditingController(
        text: initialData?['zone']?.toString() ??
            initialData?['floor']?.toString() ??
            'Main');
    String shape = initialData?['shape']?.toString() ?? 'rectangle';
    String status = initialData?['status']?.toString() ?? 'available';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(isEdit ? 'Edit Table' : 'Add New Table'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Display Name',
                      hintText: 'Table 1, Window Seat, etc.',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: seatsController,
                    decoration: const InputDecoration(
                      labelText: 'Number of Seats',
                      hintText: 'Enter seat capacity',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: zoneController,
                    decoration: const InputDecoration(
                      labelText: 'Zone / Floor',
                      hintText: 'Main Floor, Rooftop, etc.',
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: shape,
                    decoration: const InputDecoration(labelText: 'Shape'),
                    items: const [
                      DropdownMenuItem(
                          value: 'rectangle', child: Text('Rectangle')),
                      DropdownMenuItem(value: 'circle', child: Text('Circle')),
                    ],
                    onChanged: (val) {
                      if (val != null) setDialogState(() => shape = val);
                    },
                  ),
                  if (isEdit) ...[
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: status,
                      decoration: const InputDecoration(labelText: 'Status'),
                      items: const [
                        DropdownMenuItem(
                            value: 'available', child: Text('Available')),
                        DropdownMenuItem(
                            value: 'reserved', child: Text('Reserved')),
                        DropdownMenuItem(
                            value: 'occupied', child: Text('Occupied')),
                      ],
                      onChanged: (val) {
                        if (val != null) setDialogState(() => status = val);
                      },
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              if (isEdit)
                TextButton(
                  onPressed: () async {
                    // Delete table
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('Delete Table?'),
                        content: const Text(
                            'Are you sure you want to delete this table?'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(c, false),
                              child: const Text('Cancel')),
                          TextButton(
                              onPressed: () => Navigator.pop(c, true),
                              child: const Text('Delete',
                                  style: TextStyle(color: Colors.red))),
                        ],
                      ),
                    );

                    if (confirm == true) {
                      try {
                        await FirebaseFirestore.instance
                            .collection('Branch')
                            .doc(branchId)
                            .set({
                          'Tables': {
                            tableId: FieldValue.delete(),
                          }
                        }, SetOptions(merge: true));
                        if (context.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Table deleted')));
                        }
                      } catch (e) {
                        if (context.mounted)
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error: $e')));
                      }
                    }
                  },
                  child:
                      const Text('Delete', style: TextStyle(color: Colors.red)),
                ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (nameController.text.trim().isEmpty) return;

                  final newTableId = isEdit
                      ? tableId
                      : 'T${DateTime.now().millisecondsSinceEpoch}';
                  final seats = int.tryParse(seatsController.text) ?? 4;

                  try {
                    await FirebaseFirestore.instance
                        .collection('Branch')
                        .doc(branchId)
                        .set({
                      'Tables': {
                        newTableId: {
                          'name': nameController.text.trim(),
                          'seats': seats,
                          'zone': zoneController.text.trim(),
                          'shape': shape,
                          'status': status,
                          'updatedAt': FieldValue.serverTimestamp(),
                          if (!isEdit)
                            'createdAt': FieldValue.serverTimestamp(),
                        }
                      }
                    }, SetOptions(merge: true));

                    if (context.mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Table saved')));
                    }
                  } catch (e) {
                    if (context.mounted)
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FullScreenFloorPlanTable extends StatelessWidget {
  final String tableId;
  final Map<String, dynamic> tableData;
  final Set<String> occupiedTableIds;
  final bool isEditMode;
  final void Function(String tableId, String tableName) onSelect;
  final void Function(String tableId, String tableName) onOccupiedTap;

  const _FullScreenFloorPlanTable({
    required this.tableId,
    required this.tableData,
    required this.occupiedTableIds,
    required this.isEditMode,
    required this.onSelect,
    required this.onOccupiedTap,
  });

  @override
  Widget build(BuildContext context) {
    final tableName = tableData['name']?.toString() ?? tableId;
    final seatsRaw = tableData['seats'];
    final int? seats = seatsRaw != null ? int.tryParse(seatsRaw.toString()) : null;
    final shape = (tableData['shape'] ?? 'rectangle').toString().toLowerCase();

    // Determine real-time status by checking active orders
    final bool isOccupiedByOrder = occupiedTableIds.contains(tableId);
    final staticStatus =
        (tableData['status'] ?? 'available').toString().toLowerCase();
    final isReserved = staticStatus == 'reserved';
    final isAvailable =
        !isOccupiedByOrder && !isReserved && staticStatus != 'occupied';

    // Color coding
    Color borderColor;
    Color bgColor;
    Color textColor;

    if (isEditMode) {
      borderColor = Colors.blue;
      bgColor = Colors.blue.withValues(alpha: 0.08);
      textColor = Colors.blue[800]!;
    } else if (isAvailable) {
      borderColor = Colors.green;
      bgColor = Colors.green.withValues(alpha: 0.08);
      textColor = Colors.green[800]!;
    } else if (isReserved) {
      borderColor = Colors.orange;
      bgColor = Colors.orange.withValues(alpha: 0.08);
      textColor = Colors.orange[800]!;
    } else {
      borderColor = Colors.red;
      bgColor = Colors.red.withValues(alpha: 0.08);
      textColor = Colors.red[800]!;
    }

    final isRound = shape == 'circle' || shape == 'round';

    return Tooltip(
      message: isEditMode
          ? 'Tap to edit'
          : isAvailable
              ? 'Tap to select'
              : isReserved
                  ? 'Reserved'
                  : 'Occupied',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            if (isEditMode) {
              onSelect(tableId, tableName);
            } else if (isAvailable) {
              onSelect(tableId, tableName);
            } else if (isReserved) {
              final proceed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.orange[800]),
                      const SizedBox(width: 8),
                      const Text('Table Reserved'),
                    ],
                  ),
                  content: Text('Table $tableName is currently marked as reserved.\n\nDo you want to use it anyway?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Use Table'),
                    ),
                  ],
                ),
              );
              if (proceed == true) {
                if (isOccupiedByOrder) {
                  onOccupiedTap(tableId, tableName);
                } else {
                  onSelect(tableId, tableName);
                }
              }
            } else if (isOccupiedByOrder) {
              onOccupiedTap(tableId, tableName);
            }
          },
          borderRadius: BorderRadius.circular(isRound ? 200 : 20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(isRound ? 200 : 20),
              border: Border.all(color: borderColor, width: 2),
              boxShadow: (isAvailable || isEditMode)
                  ? [
                      BoxShadow(
                        color: borderColor.withValues(alpha: 0.2),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      )
                    ]
                  : null,
            ),
            child: Stack(
              children: [
                if (isEditMode)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child:
                          const Icon(Icons.edit, size: 14, color: Colors.blue),
                    ),
                  )
                else if (isOccupiedByOrder && !isReserved)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Material(
                      color: Colors.transparent,
                      child: IconButton(
                        icon: const Icon(Icons.print, size: 18),
                        color: textColor,
                        tooltip: 'Print Invoice',
                        onPressed: () async {
                          // Find active order for this table
                          final userScope = context.read<UserScopeService>();
                          final branchFilter =
                              context.read<BranchFilterService>();
                          final effectiveBranchIds = branchFilter
                              .getFilterBranchIds(userScope.branchIds);
                          try {
                            final snapshot = await FirebaseFirestore.instance
                                .collection(AppConstants.collectionOrders)
                                .where('branchIds',
                                    arrayContainsAny: effectiveBranchIds)
                                .where('tableId', isEqualTo: tableId)
                                .where('Order_type', isEqualTo: 'dine_in')
                                .where('status', whereIn: [
                                  AppConstants.statusPending,
                                  AppConstants.statusPreparing,
                                  AppConstants.statusPrepared,
                                  AppConstants.statusServed,
                                ])
                                .limit(1)
                                .get();

                            if (snapshot.docs.isNotEmpty && context.mounted) {
                              PrintingService.printReceipt(
                                  context, snapshot.docs.first);
                            } else if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'No active orders found to print.')),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error printing: $e')),
                              );
                            }
                          }
                        },
                      ),
                    ),
                  ),
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isRound ? Icons.circle_outlined : Icons.table_bar,
                        color: borderColor,
                        size: 40,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        tableName,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (seats != null) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 2,
                          runSpacing: 2,
                          children: [
                            for (int i = 0; i < (seats > 6 ? 6 : seats); i++)
                              Icon(Icons.chair, size: 14, color: textColor),
                            if (seats > 6)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                decoration: BoxDecoration(
                                  color: textColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '+${seats - 6}',
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: textColor,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: borderColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          isEditMode
                              ? 'Edit'
                              : isAvailable
                                  ? 'Available'
                                  : isReserved
                                      ? 'Reserved'
                                      : 'View Orders',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
