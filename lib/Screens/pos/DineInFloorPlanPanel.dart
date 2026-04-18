import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../../main.dart';
import '../../../../constants.dart';
import '../../../../Widgets/BranchFilterService.dart';
import '../../../../services/pos/pos_service.dart';
import 'TableOrdersDialog.dart';
import '../../../../Widgets/PrintingService.dart';
import '../management/TableManagement.dart';
import '../management/TableDialogHelper.dart';

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
      color: Theme.of(context).scaffoldBackgroundColor,
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
              const SizedBox(width: 16),
              _buildLegendDot(Colors.brown, 'Needs Bussing'),
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
                                    backgroundColor: Theme.of(context).brightness == Brightness.dark ? Colors.white.withOpacity(0.02) : Theme.of(context).cardColor,
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
    TableDialogHelper.showTableDialog(context, branchId: branchId, existingTableData: null, isEdit: false);
  }

  void _showEditTableDialog(
      BuildContext context,
      String branchId,
      String tableId,
      Map<String, dynamic> tableData,
      Map<String, dynamic> allTables) {
    TableDialogHelper.showTableDialog(context, branchId: branchId, existingTableId: tableId, existingTableData: tableData, isEdit: true);
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

    final String tableStatus = (tableData['status'] ?? 'available').toString().toLowerCase();
    final bool isOccupiedByOrder = occupiedTableIds.contains(tableId);
    final bool isReserved = tableStatus == 'reserved';
    final bool isDirty   = tableStatus == 'dirty';
    final bool isOccupied = isOccupiedByOrder && !isReserved && !isDirty;
    final bool isAvailable = !isOccupiedByOrder && !isReserved && !isDirty
        && tableStatus != 'occupied';

    DateTime? occupiedAt;
    if (tableData['occupiedAt'] is Timestamp) {
      occupiedAt = (tableData['occupiedAt'] as Timestamp).toDate();
    }

    // Color coding
    Color borderColor;
    Color bgColor;
    Color textColor;

    if (isEditMode) {
      borderColor = Colors.blue;
      bgColor = Colors.blue.withValues(alpha: 0.08);
      textColor = Colors.blue[800]!;
    } else if (isDirty) {
      borderColor = Colors.brown;
      bgColor = Colors.brown.withValues(alpha: 0.08);
      textColor = Colors.brown[800]!;
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
    final isSofa = shape == 'corner_sofa' || shape == 'sofa';
    final isStool = shape == 'bar_stool' || shape == 'stool';

    IconData tableIcon;
    if (isSofa) {
      tableIcon = Icons.weekend_rounded;
    } else if (shape == 'booth' || shape == 'sofa') {
      tableIcon = Icons.event_seat_outlined;
    } else if (isStool) {
      tableIcon = Icons.chair_alt_rounded;
    } else if (isRound) {
      tableIcon = Icons.circle_outlined;
    } else if (shape == 'square') {
      tableIcon = Icons.crop_square_rounded;
    } else if (shape == 'oval') {
      tableIcon = Icons.vignette_outlined;
    } else {
      tableIcon = Icons.table_bar_rounded;
    }

    return Tooltip(
      message: isEditMode
          ? 'Tap to edit'
          : isDirty
              ? 'Needs Bussing — tap Mark Clean when ready'
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
            } else if (isDirty) {
              final clean = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  title: Row(
                    children: [
                      Icon(Icons.cleaning_services_rounded, color: Colors.brown[800]),
                      const SizedBox(width: 8),
                      Text('Table Needs Cleaning', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  content: Text('Table $tableName needs bussing.\n\nMark it as clean and make it available?',
                    style: GoogleFonts.inter()),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text('No', style: TextStyle(color: Colors.grey[600])),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.brown, foregroundColor: Colors.white),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Yes, Mark Clean'),
                    ),
                  ],
                ),
              );
              if (clean == true && context.mounted) {
                final pos = context.read<PosService>();
                final userScope = context.read<UserScopeService>();
                final branchFilter = context.read<BranchFilterService>();
                final effectiveBranchIds = branchFilter.getFilterBranchIds(userScope.branchIds);
                await pos.markTableClean(
                  branchIds: effectiveBranchIds,
                  tableId: tableId,
                );
              }
            } else if (isAvailable) {
              onSelect(tableId, tableName);
            } else if (isReserved) {
              final proceed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  title: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.orange[800]),
                      const SizedBox(width: 8),
                      Text('Table Reserved', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  content: Text('Table $tableName is currently marked as reserved.\n\nDo you want to use it anyway?',
                    style: GoogleFonts.inter()),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
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
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(isRound ? 200 : 20),
              border: Border.all(color: borderColor.withValues(alpha: 0.5), width: 2.5),
              boxShadow: (isAvailable || isEditMode)
                  ? [
                      BoxShadow(
                        color: borderColor.withValues(alpha: 0.15),
                        blurRadius: 15,
                        spreadRadius: 2,
                        offset: const Offset(0, 6),
                      )
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      )
                    ],
            ),
            child: Stack(
              children: [
                if (isEditMode)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                      ),
                      child: const Icon(Icons.settings_outlined, size: 14, color: Colors.blue),
                    ),
                  )
                else if (isDirty)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Material(
                      color: Colors.transparent,
                      child: Tooltip(
                        message: 'Mark Table Clean',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () async {
                            final pos = context.read<PosService>();
                            final userScope = context.read<UserScopeService>();
                            final branchFilter = context.read<BranchFilterService>();
                            final effectiveBranchIds = branchFilter
                                .getFilterBranchIds(userScope.branchIds);
                            await pos.markTableClean(
                              branchIds: effectiveBranchIds,
                              tableId: tableId,
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.brown.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.brown.withValues(alpha: 0.4),
                                width: 1.5,
                              ),
                            ),
                            child: const Icon(
                              Icons.cleaning_services_rounded,
                              size: 18,
                              color: Colors.brown,
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                else if (isOccupied)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Material(
                      color: Colors.transparent,
                      child: Container(
                        decoration: BoxDecoration(
                          color: textColor.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.receipt_long_rounded, size: 18),
                          color: textColor,
                          tooltip: 'Print Invoice',
                          onPressed: () async {
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
                  ),
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: borderColor.withValues(alpha: 0.1),
                          shape: isRound ? BoxShape.circle : BoxShape.rectangle,
                          borderRadius: isRound ? null : BorderRadius.circular(15),
                        ),
                        child: Icon(
                          tableIcon,
                          color: borderColor,
                          size: 36,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        tableName,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (seats != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.people_outline_rounded, size: 14, color: textColor.withValues(alpha: 0.7)),
                            const SizedBox(width: 4),
                            Text(
                              '$seats Seats',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: textColor.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: borderColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: borderColor.withValues(alpha: 0.2)),
                        ),
                        child: Text(
                          isEditMode
                              ? 'Tap to Edit'
                              : isDirty
                                  ? 'NEEDS CLEANING'
                                  : isAvailable
                                      ? 'AVAILABLE'
                                      : isReserved
                                          ? 'RESERVED'
                                          : 'ACTIVE ORDER',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: textColor,
                            letterSpacing: 0.5,
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

