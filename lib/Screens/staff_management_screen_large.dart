import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../Widgets/BranchFilterService.dart';
import '../Widgets/BranchFilterSelector.dart';
import '../main.dart';
import '../services/staff/staff_service.dart';
import '../Widgets/ExportReportDialog.dart';

class StaffManagementScreenLarge extends StatefulWidget {
  const StaffManagementScreenLarge({super.key});
  @override
  State<StaffManagementScreenLarge> createState() => _StaffManagementScreenLargeState();
}

class _StaffManagementScreenLargeState extends State<StaffManagementScreenLarge> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Stable stream references
  Stream<int>? _activeStaffStream;
  Stream<int>? _totalStaffStream;
  Stream<int>? _clockedInTodayStream;
  Stream<int>? _shiftsTodayStream;
  Stream<QuerySnapshot>? _staffStream;
  Stream<QuerySnapshot>? _shiftsStream;
  Stream<QuerySnapshot>? _attendanceStream;
  // Driver streams
  Stream<QuerySnapshot>? _driversStream;
  Stream<int>? _activeDriverStream;
  Stream<int>? _totalDriverStream;

  List<String>? _lastFilterBranchIds;
  String? _lastSelectedBranchId;

  void _updateStreams(List<String> filterBranchIds, String? selectedBranchId, StaffService staffService) {
    final bool branchIdsChanged = _lastFilterBranchIds == null || 
        _lastFilterBranchIds!.length != filterBranchIds.length ||
        !_lastFilterBranchIds!.every((id) => filterBranchIds.contains(id));
    
    final bool selectionChanged = _lastSelectedBranchId != selectedBranchId;

    if (branchIdsChanged || selectionChanged) {
      _activeStaffStream = staffService.getTotalActiveStaffCount(filterBranchIds);
      _totalStaffStream = staffService.getTotalStaffCount(filterBranchIds);
      _clockedInTodayStream = staffService.getClockedInTodayCount(selectedBranchId: selectedBranchId, branchIds: filterBranchIds);
      _shiftsTodayStream = staffService.getTodayShiftCount(selectedBranchId: selectedBranchId, branchIds: filterBranchIds);
      _staffStream = staffService.getStaffStream(branchIds: filterBranchIds, selectedBranchId: selectedBranchId);
      _shiftsStream = staffService.getShiftsStream(selectedBranchId: selectedBranchId, branchIds: filterBranchIds);
      _attendanceStream = staffService.getTodayAttendanceStream(selectedBranchId: selectedBranchId, branchIds: filterBranchIds);
      // Driver streams
      _driversStream = staffService.getDriversStream(branchIds: filterBranchIds, selectedBranchId: selectedBranchId);
      _activeDriverStream = staffService.getActiveDriverCount(filterBranchIds);
      _totalDriverStream = staffService.getTotalDriverCount(filterBranchIds);

      _lastFilterBranchIds = List.from(filterBranchIds);
      _lastSelectedBranchId = selectedBranchId;
    }
  }

  @override
  Widget build(BuildContext context) {
    final userScope = context.watch<UserScopeService>();
    final branchFilter = context.watch<BranchFilterService>();
    final staffService = context.read<StaffService>();
    final textTheme = Theme.of(context).textTheme;
    const primaryColor = Colors.deepPurple;
    final filterBranchIds = branchFilter.getFilterBranchIds(userScope.branchIds);

    // Initialize/Update stable streams
    _updateStreams(filterBranchIds, branchFilter.selectedBranchId, staffService);

    return Container(
      color: Colors.grey[50],
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeaderSection(textTheme, primaryColor, staffService, userScope),
            const SizedBox(height: 32),
            _MetricBentoGrid(
              primaryColor: primaryColor, 
              activeStaffStream: _activeStaffStream!,
              totalStaffStream: _totalStaffStream!,
              clockedInTodayStream: _clockedInTodayStream!,
              shiftsTodayStream: _shiftsTodayStream!,
            ),
            const SizedBox(height: 32),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 8,
                  child: Column(
                    children: [
                      _StaffDirectoryTable(
                        userScope: userScope,
                        branchFilter: branchFilter,
                        searchQuery: _searchQuery,
                        primaryColor: primaryColor,
                        staffService: staffService,
                        staffStream: _staffStream!,
                        driversStream: _driversStream!,
                        attendanceStream: _attendanceStream!,
                        activeDriverStream: _activeDriverStream!,
                        totalDriverStream: _totalDriverStream!,
                        onSearchChanged: (q) => setState(() => _searchQuery = q),
                      ),
                      const SizedBox(height: 32),
                      _ShiftSchedulingSection(
                        primaryColor: primaryColor, 
                        staffService: staffService, 
                        shiftsStream: _shiftsStream!,
                        userEmail: userScope.userEmail
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 32),
                Expanded(
                  flex: 4,
                  child: _AttendanceSidebar(
                    primaryColor: primaryColor, 
                    attendanceStream: _attendanceStream!,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderSection(TextTheme textTheme, Color primaryColor, StaffService staffService, UserScopeService userScope) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('STAFF HUB', style: textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w900, color: Colors.black87, letterSpacing: -1, fontSize: 36)),
            Text('Manage your team, shifts, and attendance across all branches.', style: textTheme.bodyMedium?.copyWith(color: Colors.grey[600], fontWeight: FontWeight.w500)),
          ],
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const BranchFilterSelector(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
            const SizedBox(width: 16),
            ElevatedButton.icon(
              onPressed: () {
                ExportReportDialog.show(context, preSelectedSections: {'staff_summary'});
              },
              icon: const Icon(Icons.download_rounded, size: 16),
              label: const Text('EXPORT REPORT'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white, foregroundColor: primaryColor,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey[300]!),
                ),
                elevation: 0,
                textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1),
              ),
            ),
            const SizedBox(width: 16),
            ElevatedButton.icon(
              onPressed: () => _showAddStaffDialog(context, staffService, userScope),
              icon: const Icon(Icons.person_add, size: 16),
              label: const Text('ADD STAFF'),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 2,
                textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showAddStaffDialog(BuildContext context, StaffService staffService, UserScopeService userScope) {
    showDialog(context: context, barrierDismissible: false, builder: (ctx) => _StaffFormDialog(
      staffService: staffService, currentUserEmail: userScope.userEmail,
    ));
  }
}

// =============================================================================
// METRIC BENTO GRID — Live from Firestore
// =============================================================================
class _MetricBentoGrid extends StatelessWidget {
  final Color primaryColor;
  final Stream<int> activeStaffStream;
  final Stream<int> totalStaffStream;
  final Stream<int> clockedInTodayStream;
  final Stream<int> shiftsTodayStream;

  const _MetricBentoGrid({
    required this.primaryColor, 
    required this.activeStaffStream,
    required this.totalStaffStream,
    required this.clockedInTodayStream,
    required this.shiftsTodayStream,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      crossAxisCount: 4, crossAxisSpacing: 16, mainAxisSpacing: 16, childAspectRatio: 2.1,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _StreamMetricCard(
          stream: activeStaffStream,
          totalStream: totalStaffStream,
          label: 'Active Staff', icon: Icons.groups, primaryColor: primaryColor,
          formatValue: (active, total) => '$active',
          formatSub: (active, total) => ' / $total',
        ),
        _StreamMetricCard(
          stream: clockedInTodayStream,
          label: 'Clocked In Today', icon: Icons.login, primaryColor: primaryColor,
          formatValue: (v, _) => '$v', statusLabel: 'LIVE', statusColor: Colors.green,
        ),
        _StreamMetricCard(
          stream: shiftsTodayStream,
          label: 'Shifts Today', icon: Icons.schedule, primaryColor: primaryColor,
          formatValue: (v, _) => '$v', statusLabel: 'SCHEDULED', statusColor: Colors.blue,
        ),
        _buildStaticCard('Shift System', 'ACTIVE', Icons.verified, Colors.green),
      ],
    );
  }

  Widget _buildStaticCard(String label, String value, IconData icon, Color statusColor) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey[200]!),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))]),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.grey, letterSpacing: 1.5)),
        Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.black87)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
          child: Text('OPERATIONAL', style: TextStyle(color: statusColor, fontSize: 9, fontWeight: FontWeight.w900)),
        ),
      ]),
    );
  }
}

class _StreamMetricCard extends StatelessWidget {
  final Stream<int> stream;
  final Stream<int>? totalStream;
  final String label;
  final IconData icon;
  final Color primaryColor;
  final String Function(int value, int? total) formatValue;
  final String Function(int value, int? total)? formatSub;
  final String? statusLabel;
  final Color? statusColor;

  const _StreamMetricCard({required this.stream, this.totalStream, required this.label, required this.icon, required this.primaryColor, required this.formatValue, this.formatSub, this.statusLabel, this.statusColor});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: stream,
      builder: (context, snap) {
        final value = snap.data ?? 0;
        if (totalStream != null) {
          return StreamBuilder<int>(stream: totalStream, builder: (ctx, totalSnap) {
            final total = totalSnap.data ?? 0;
            return _card(value, total);
          });
        }
        return _card(value, null);
      },
    );
  }

  Widget _card(int value, int? total) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey[200]!),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))]),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Stack(children: [
        Positioned(top: 0, right: 0, child: Icon(icon, color: primaryColor.withValues(alpha: 0.05), size: 48)),
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.grey, letterSpacing: 1.5)),
          RichText(text: TextSpan(children: [
            TextSpan(text: formatValue(value, total), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.black87)),
            if (formatSub != null) TextSpan(text: formatSub!(value, total), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.grey)),
          ])),
          if (statusLabel != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: (statusColor ?? Colors.green).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
              child: Text(statusLabel!, style: TextStyle(color: statusColor ?? Colors.green, fontSize: 9, fontWeight: FontWeight.w900)),
            ),
        ]),
      ]),
    );
  }
}

// =============================================================================
// STAFF DIRECTORY TABLE — Live from Firestore with search, edit, delete
// =============================================================================
class _StaffDirectoryTable extends StatelessWidget {
  final UserScopeService userScope;
  final BranchFilterService branchFilter;
  final String searchQuery;
  final Color primaryColor;
  final StaffService staffService;
  final Stream<QuerySnapshot> staffStream;
  final Stream<QuerySnapshot> driversStream;
  final Stream<QuerySnapshot> attendanceStream;
  final Stream<int> activeDriverStream;
  final Stream<int> totalDriverStream;
  final ValueChanged<String> onSearchChanged;

  const _StaffDirectoryTable({
    required this.userScope, 
    required this.branchFilter, 
    required this.searchQuery, 
    required this.primaryColor, 
    required this.staffService, 
    required this.staffStream,
    required this.driversStream,
    required this.attendanceStream,
    required this.activeDriverStream,
    required this.totalDriverStream,
    required this.onSearchChanged
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey[200]!)),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Row(children: [
            const Text('TEAM DIRECTORY', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: -0.5, color: Colors.black87)),
            const SizedBox(width: 16),
            StreamBuilder<int>(
              stream: activeDriverStream,
              builder: (context, activeSnap) {
                return StreamBuilder<int>(
                  stream: totalDriverStream,
                  builder: (context, totalSnap) {
                    final active = activeSnap.data ?? 0;
                    final total = totalSnap.data ?? 0;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.delivery_dining, color: Colors.orange, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          '$active/$total drivers',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.orange),
                        ),
                      ]),
                    );
                  },
                );
              },
            ),
            const Spacer(),
            SizedBox(
              width: 240,
              child: TextField(
                onChanged: onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Search team...', prefixIcon: const Icon(Icons.search, size: 18),
                  isDense: true, contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey[300]!)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey[300]!)),
                ),
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ]),
        ),
        StreamBuilder<QuerySnapshot>(
          stream: staffStream,
          builder: (context, staffSnapshot) {
            return StreamBuilder<QuerySnapshot>(
              stream: driversStream,
              builder: (context, driverSnapshot) {
                if (staffSnapshot.hasError) return Padding(padding: const EdgeInsets.all(24), child: Text('Error: ${staffSnapshot.error}'));
                if (!staffSnapshot.hasData) return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));

                // Build unified list: staff entries + driver entries
                final List<_TeamEntry> entries = [];

                for (var doc in staffSnapshot.data!.docs) {
                  entries.add(_TeamEntry(data: doc.data() as Map<String, dynamic>, id: doc.id, isDriver: false));
                }

                if (driverSnapshot.hasData) {
                  for (var doc in driverSnapshot.data!.docs) {
                    entries.add(_TeamEntry(data: doc.data() as Map<String, dynamic>, id: doc.id, isDriver: true));
                  }
                }

                // Apply search
                var filtered = entries;
                if (searchQuery.isNotEmpty) {
                  final q = searchQuery.toLowerCase();
                  filtered = entries.where((entry) {
                    final name = (entry.data['name'] ?? '').toString().toLowerCase();
                    final email = (entry.data['email'] ?? '').toString().toLowerCase();
                    final role = (entry.data['role'] ?? '').toString().toLowerCase();
                    return name.contains(q) || email.contains(q) || role.contains(q);
                  }).toList();
                }

                if (filtered.isEmpty) {
                  return const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No team members found.', style: TextStyle(color: Colors.grey))));
                }

                return StreamBuilder<QuerySnapshot>(
                  stream: attendanceStream,
                  builder: (context, attendanceSnapshot) {
                    final Map<String, Map<String, dynamic>> attendanceDataMap = {};
                    if (attendanceSnapshot.hasData) {
                      for (var doc in attendanceSnapshot.data!.docs) {
                        final data = doc.data() as Map<String, dynamic>;
                        final sId = data['staffId'] as String? ?? data['staffEmail'] as String? ?? '';
                        if (sId.isNotEmpty && !attendanceDataMap.containsKey(sId)) {
                          attendanceDataMap[sId] = data;
                        }
                      }
                    }

                    return Table(
                      columnWidths: const {
                        0: FlexColumnWidth(2.5),
                        1: FlexColumnWidth(1),
                        2: FlexColumnWidth(1.8),
                        3: FlexColumnWidth(1.5),
                        4: FlexColumnWidth(1.5),
                        5: FlexColumnWidth(1.2)
                      },
                      children: [
                        _buildTableHeader(),
                        ...filtered.map((entry) => _buildTableRow(
                            context,
                            entry.data,
                            entry.id,
                            attendanceDataMap[entry.id],
                            entry.isDriver)),
                      ],
                    );
                  });
              },
            );
          },
        ),
      ]),
    );
  }

  TableRow _buildTableHeader() {
    return TableRow(
      decoration: BoxDecoration(color: Colors.grey[50]),
      children: ['Employee', 'Type', 'Role & Branch', 'Salary', 'Status', 'Actions'].map((label) {
        return Padding(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Text(label.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1)));
      }).toList(),
    );
  }

  TableRow _buildTableRow(BuildContext context, Map<String, dynamic> data,
      String id, [Map<String, dynamic>? attData, bool isDriver = false]) {
    final role = isDriver ? (data['vehicleType'] ?? 'Driver') : (data['role'] ?? 'Staff');
    final branches = (data['branchIds'] as List?)?.join(', ') ?? '-';
    final phone = data['phone'] ?? '-';
    
    final isClockedIn = attData != null && attData['clockOut'] == null;
    final clockIn = attData?['clockIn'] as Timestamp?;
    final clockOut = attData?['clockOut'] as Timestamp?;

    final Color avatarColor = isDriver ? Colors.orange : primaryColor;

    return TableRow(
      decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.grey[100]!))),
      children: [
        Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                    color: avatarColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: Center(
                    child: Text(
                        (data['name'] ?? 'U')
                            .toString()
                            .substring(0, 1)
                            .toUpperCase(),
                        style: TextStyle(
                            color: avatarColor, fontWeight: FontWeight.bold))),
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(data['name'] ?? 'Unknown',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Colors.black87),
                        overflow: TextOverflow.ellipsis),
                    Text(data['email'] ?? id,
                        style: const TextStyle(fontSize: 10, color: Colors.grey),
                        overflow: TextOverflow.ellipsis),
                  ])),
            ])),
        // Type badge column
        Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isDriver ? Colors.orange.withValues(alpha: 0.1) : primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(isDriver ? Icons.delivery_dining : Icons.person, size: 12, color: isDriver ? Colors.orange : primaryColor),
              const SizedBox(width: 4),
              Flexible(
                child: Text(isDriver ? 'DRIVER' : _formatRole(data['role'] ?? 'Staff').toUpperCase(),
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: isDriver ? Colors.orange : primaryColor),
                    overflow: TextOverflow.ellipsis),
              ),
            ]),
          ),
        ),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_formatRole(role),
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Colors.black87),
                      overflow: TextOverflow.ellipsis),
                  Text(branches.toUpperCase(),
                      style: TextStyle(
                          fontSize: 9,
                          color: primaryColor,
                          fontWeight: FontWeight.w900),
                      overflow: TextOverflow.ellipsis),
                ])),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Text(
              'QAR ${((data['salary'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
              overflow: TextOverflow.ellipsis,
            )),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                            color: isClockedIn ? Colors.green : Colors.grey[400],
                            shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(isClockedIn ? 'CLOCKED IN' : 'CLOCKED OUT',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: isClockedIn ? Colors.green : Colors.grey),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ]),
                  if (clockIn != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'IN: ${_formatTime(clockIn.toDate())}',
                      style: TextStyle(fontSize: 9, color: Colors.green[700], fontWeight: FontWeight.w600),
                    ),
                  ],
                  if (clockOut != null) ...[
                    Text(
                      'OUT: ${_formatTime(clockOut.toDate())}',
                      style: TextStyle(fontSize: 9, color: Colors.red[700], fontWeight: FontWeight.w600),
                    ),
                  ],
                ])),

        Padding(padding: const EdgeInsets.all(8), child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.access_time, size: 18, color: Colors.blue), 
            onPressed: () => _showManualClockInOutDialog(context, data, id)
          ),
          if (!isDriver) ...[
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.edit_square, size: 18, color: Colors.grey[400]), 
              onPressed: () => _showEditDialog(context, data, id)
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.delete_outline, size: 18, color: Colors.red[300]), 
              onPressed: () => _confirmDelete(context, id, data['name'] ?? 'this staff member')
            ),
          ],
        ]))),
      ],
    );
  }

  String _formatRole(String role) {
    final r = role.toLowerCase().replaceAll('_', ' ');
    return r.split(' ').map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '').join(' ');
  }

  void _showEditDialog(BuildContext context, Map<String, dynamic> data, String staffId) {
    showDialog(context: context, barrierDismissible: false, builder: (ctx) => _StaffFormDialog(
      staffService: staffService, currentUserEmail: userScope.userEmail, existingData: data, staffId: staffId,
    ));
  }

  void _confirmDelete(BuildContext context, String staffId, String name) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Deactivate Staff'),
      content: Text('Are you sure you want to deactivate "$name"? They will no longer be able to sign in.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
        ElevatedButton(
          onPressed: () async {
            Navigator.pop(ctx);
            try {
              await staffService.deactivateStaff(staffId, userScope.userEmail);
              if (ctx.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ $name has been deactivated'), backgroundColor: Colors.green));
            } catch (e) {
              if (ctx.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
            }
          },
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          child: const Text('Deactivate'),
        ),
      ],
    ));
  }

  void _showManualClockInOutDialog(BuildContext context, Map<String, dynamic> staffData, String staffId) {
    final name = staffData['name'] ?? 'Staff Member';
    final branchIds = List<String>.from(staffData['branchIds'] ?? []);
    showDialog(
      context: context,
      builder: (ctx) {
        return StreamBuilder<QuerySnapshot>(
          stream: staffService.getTodayAttendanceStream(
            branchIds: branchIds,
            staffId: staffId,
          ),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const AlertDialog(
                content: SizedBox(height: 100, child: Center(child: CircularProgressIndicator())),
              );
            }

            DocumentSnapshot? activeRecord;
            for (var doc in snapshot.data!.docs) {
              final data = doc.data() as Map<String, dynamic>;
              if (data['clockOut'] == null) {
                activeRecord = doc;
                break;
              }
            }

            final isClockedIn = activeRecord != null;

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text(isClockedIn ? 'Clock OUT $name' : 'Clock IN $name'),
              content: Text(
                isClockedIn
                    ? 'This staff member is currently clocked in. Do you want to manually clock them out?'
                    : 'This staff member is not currently clocked in. Do you want to manually clock them in?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    try {
                      if (isClockedIn) {
                        await staffService.clockOut(activeRecord!.id, notes: 'Manually clocked out by manager');
                      } else {
                        await staffService.clockIn(
                          staffId: staffId,
                          staffEmail: staffData['email'] ?? '',
                          staffName: name,
                          branchIds: branchIds,
                        );
                      }
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(isClockedIn ? '✅ $name clocked out' : '✅ $name clocked in'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: isClockedIn ? Colors.red : Colors.green),
                  child: Text(isClockedIn ? 'Clock Out' : 'Clock In'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

// =============================================================================
// SHIFT SCHEDULING — Live from Firestore
// =============================================================================
class _ShiftSchedulingSection extends StatelessWidget {
  final Color primaryColor;
  final StaffService staffService;
  final Stream<QuerySnapshot> shiftsStream;
  final String userEmail;
  const _ShiftSchedulingSection({
    required this.primaryColor, 
    required this.staffService, 
    required this.shiftsStream,
    required this.userEmail
  });

  static const _days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey[200]!)),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('SHIFT SCHEDULING', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: -0.5, color: Colors.black87)),
            Row(children: [
              _legendItem('Scheduled', primaryColor),
              const SizedBox(width: 16),
              _legendItem('Day Off', Colors.grey),
              const SizedBox(width: 24),
              TextButton.icon(
                onPressed: () => _showAddShiftDialog(context),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('ADD SHIFT'),
                style: TextButton.styleFrom(foregroundColor: primaryColor, textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
              ),
            ]),
          ]),
        ),
        const Divider(height: 1),
        StreamBuilder<QuerySnapshot>(
          stream: shiftsStream,
          builder: (context, snapshot) {
            if (snapshot.hasError) return Padding(padding: const EdgeInsets.all(24), child: Text('Error: ${snapshot.error}'));
            if (!snapshot.hasData) return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));

            final shifts = snapshot.data!.docs;
            if (shifts.isEmpty) {
              return const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No shifts scheduled for these branches.', style: TextStyle(color: Colors.grey))));
            }

            // Group shifts by staffId
            final Map<String, Map<int, Map<String, dynamic>>> grouped = {};
            final Map<String, String> staffNames = {};
            final Map<String, String> staffEmails = {};
            final Map<String, List<String>> staffBranches = {};
            for (final doc in shifts) {
              final data = doc.data() as Map<String, dynamic>;
              final sId = data['staffId'] as String? ?? data['staffEmail'] as String? ?? 'unknown';
              final email = data['staffEmail'] as String? ?? '';
              final day = data['dayOfWeek'] as int? ?? 1;
              staffNames[sId] = data['staffName'] as String? ?? email;
              staffEmails[sId] = email;
              staffBranches[sId] = List<String>.from(data['branchIds'] ?? []);
              grouped.putIfAbsent(sId, () => {});
              grouped[sId]![day] = {...data, '_docId': doc.id};
            }

            return Table(children: [
              TableRow(
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey[100]!))),
                children: [
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16), child: Text('STAFF', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.grey))),
                  ...List.generate(7, (i) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: Text(_days[i], style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: (i + 1) == DateTime.now().weekday ? primaryColor : Colors.grey))),
                  )),
                ],
              ),
              ...grouped.entries.map((entry) => TableRow(
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey[100]!))),
                children: [
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                    child: Text(staffNames[entry.key] ?? entry.key, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black87))),
                  ...List.generate(7, (i) {
                    final dayData = entry.value[i + 1];
                    return _shiftCell(context, dayData, entry.key, staffNames[entry.key] ?? '', staffEmails[entry.key] ?? '', staffBranches[entry.key] ?? [], i + 1);
                  }),
                ],
              )),
            ]);
          },
        ),
      ]),
    );
  }

  Widget _legendItem(String label, Color color) {
    return Row(children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 8),
      Text(label.toUpperCase(), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.grey)),
    ]);
  }

  Widget _shiftCell(BuildContext context, Map<String, dynamic>? data, String staffId, String staffName, String staffEmail, List<String> staffBranches, int dayOfWeek) {
    final isOff = data?['isOff'] == true;
    final hasShift = data != null;
    final label = !hasShift ? '—' : isOff ? 'OFF' : '${data['startTime'] ?? ''} - ${data['endTime'] ?? ''}';
    final cellColor = !hasShift ? Colors.transparent : isOff ? Colors.grey[50]! : primaryColor.withValues(alpha: 0.1);
    final borderColor = !hasShift ? Colors.grey[200]! : isOff ? Colors.grey[200]! : primaryColor.withValues(alpha: 0.2);
    final textColor = !hasShift ? Colors.grey[300]! : isOff ? Colors.grey : primaryColor;

    return Padding(padding: const EdgeInsets.all(4), child: InkWell(
      onTap: () {
        if (hasShift) {
          _showEditShiftDialog(context, data!, data['_docId'], staffService, userEmail);
        } else {
          _showAddShiftDialogForCell(context, staffId, staffEmail, staffName, staffBranches, dayOfWeek);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(color: cellColor, borderRadius: BorderRadius.circular(8), border: Border.all(color: borderColor)),
        child: Center(child: Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: textColor))),
      ),
    ));
  }

  void _showAddShiftDialog(BuildContext context) {
    // Note: This dialog might need its own stable stream if it gets complex,
    // but usually, a one-off dialog opening is fine. 
    // For now, keeping it simple as it doesn't use snapshots() in its build.
    final branchFilter = context.read<BranchFilterService>();
    final userScope = context.read<UserScopeService>();
    final filterBranchIds = branchFilter.getFilterBranchIds(userScope.branchIds);
    showDialog(context: context, builder: (ctx) => _ShiftFormDialog(staffService: staffService, branchIds: filterBranchIds, userEmail: userEmail));
  }

  void _showAddShiftDialogForCell(BuildContext context, String staffId, String staffEmail, String staffName, List<String> staffBranches, int dayOfWeek) {
    showDialog(context: context, builder: (ctx) => _ShiftFormDialog(
      staffService: staffService, branchIds: staffBranches, userEmail: userEmail,
      staffId: staffId, prefilledEmail: staffEmail, prefilledName: staffName, prefilledDay: dayOfWeek,
    ));
  }

  void _showEditShiftDialog(BuildContext context, Map<String, dynamic> data, String docId, StaffService staffService, String userEmail) {
    showDialog(context: context, builder: (ctx) => _ShiftFormDialog(
      staffService: staffService, branchIds: List<String>.from(data['branchIds'] ?? []), userEmail: userEmail,
      staffId: data['staffId'], // Ensure staffId was stored in the shift doc
      existingShift: data, shiftDocId: docId,
    ));
  }
}

// =============================================================================
// TEAM ENTRY — Data class for unified Staff + Driver directory
// =============================================================================
class _TeamEntry {
  final Map<String, dynamic> data;
  final String id;
  final bool isDriver;

  const _TeamEntry({required this.data, required this.id, required this.isDriver});
}


// =============================================================================
// ATTENDANCE SIDEBAR — Live from Firestore
// =============================================================================
class _AttendanceSidebar extends StatelessWidget {
  final Color primaryColor;
  final Stream<QuerySnapshot> attendanceStream;
  const _AttendanceSidebar({required this.primaryColor, required this.attendanceStream});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey[200]!)),
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('ATTENDANCE TODAY', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1, color: Colors.black87)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
            child: Row(children: [
              Container(width: 6, height: 6, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
              const SizedBox(width: 4),
              const Text('LIVE', style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.w900)),
            ]),
          ),
        ]),
        const SizedBox(height: 24),
        StreamBuilder<QuerySnapshot>(
          stream: attendanceStream,
          builder: (context, snapshot) {
            if (snapshot.hasError) return Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red, fontSize: 12));
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

            final docs = snapshot.data!.docs;
            if (docs.isEmpty) {
              return const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: Text('No attendance records today.', style: TextStyle(color: Colors.grey, fontSize: 12))));
            }

            return Column(children: docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final name = data['staffName'] ?? 'Unknown';
              final status = data['status'] ?? 'on_time';
              final clockIn = data['clockIn'] as Timestamp?;
              final clockOut = data['clockOut'] as Timestamp?;
              final isLate = status == 'late';
              final isClockedOut = clockOut != null;
              final clockInStr = clockIn != null ? _formatTime(clockIn.toDate()) : '—';
              final clockOutStr = isClockedOut ? _formatTime(clockOut.toDate()) : '—';
              final statusLabel = isClockedOut ? 'DONE' : isLate ? 'LATE' : 'ON TIME';
              final statusColor = isClockedOut ? Colors.grey : isLate ? Colors.red : Colors.green;
              final icon = isClockedOut ? Icons.logout : isLate ? Icons.alarm_off : Icons.alarm_on;

              return Padding(padding: const EdgeInsets.only(bottom: 12), child: InkWell(
                onTap: () => _showAttendanceDetailDialog(context, data, doc.id),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey[100]!)),
                  child: Row(children: [
                    Container(width: 32, height: 32,
                      decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                      child: Icon(icon, color: statusColor, size: 16),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black87)),
                      const SizedBox(height: 2),
                      Row(children: [
                        Icon(Icons.login, size: 10, color: Colors.green[400]),
                        const SizedBox(width: 3),
                        Text(clockInStr, style: TextStyle(fontSize: 10, color: Colors.green[700], fontWeight: FontWeight.w600)),
                        const SizedBox(width: 8),
                        Icon(Icons.logout, size: 10, color: isClockedOut ? Colors.red[400] : Colors.grey[400]),
                        const SizedBox(width: 3),
                        Text(clockOutStr, style: TextStyle(fontSize: 10, color: isClockedOut ? Colors.red[700] : Colors.grey[400], fontWeight: FontWeight.w600)),
                      ]),
                    ])),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(statusLabel, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: statusColor)),
                      const SizedBox(height: 2),
                      Icon(Icons.chevron_right, size: 14, color: Colors.grey[400]),
                    ]),
                  ]),
                ),
              ));
            }).toList());
          },
        ),
      ]),
    );
  }

  void _showAttendanceDetailDialog(BuildContext context, Map<String, dynamic> data, String docId) {
    final branchFilter = context.read<BranchFilterService>();
    final name = data['staffName'] ?? 'Unknown';
    final staffEmail = data['staffEmail'] ?? '';
    final status = data['status'] ?? 'on_time';
    final clockIn = data['clockIn'] as Timestamp?;
    final clockOut = data['clockOut'] as Timestamp?;
    final scheduledStart = data['scheduledStart'] ?? '';
    final notes = data['notes'] ?? '';
    final date = data['date'] ?? '';
    final branchIds = List<String>.from(data['branchIds'] ?? []);
    
    // Resolve branch names
    final List<String> branchNames = branchIds.map((id) => branchFilter.branchNames[id] ?? id).toList();
    
    final isLate = status == 'late';
    final isClockedOut = clockOut != null;

    // Calculate hours worked
    String hoursWorked = '—';
    Duration? duration;
    if (clockIn != null) {
      final clockInDt = clockIn.toDate();
      final clockOutDt = isClockedOut ? clockOut.toDate() : DateTime.now();
      duration = clockOutDt.difference(clockInDt);
      final h = duration.inHours;
      final m = duration.inMinutes.remainder(60);
      hoursWorked = '${h}h ${m}m';
    }

    final statusColor = isClockedOut ? Colors.grey : isLate ? Colors.red : Colors.green;
    final statusLabel = isClockedOut ? 'Shift Complete' : isLate ? 'Punctuation Alert: Late' : 'Punctuation: On Time';

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Container(
          width: 520,
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with Profile & Status
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 56, height: 56,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [primaryColor, primaryColor.withValues(alpha: 0.8)]),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: primaryColor.withValues(alpha: 0.2), blurRadius: 12, offset: const Offset(0, 4))],
                    ),
                    child: Center(child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : 'U',
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                    )),
                  ),
                  const SizedBox(width: 20),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.black87, letterSpacing: -0.5)),
                    const SizedBox(height: 4),
                    Text(staffEmail, style: TextStyle(fontSize: 13, color: Colors.grey[500], fontWeight: FontWeight.w500)),
                  ])),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: statusColor.withValues(alpha: 0.2)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 8, height: 8, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Text(statusLabel.toUpperCase(), style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                    ]),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              
              // Date & Assignments
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.grey[100]!),
                ),
                child: Column(children: [
                  Row(children: [
                    Icon(Icons.calendar_month, size: 18, color: primaryColor),
                    const SizedBox(width: 12),
                    Text('Record Date', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[600])),
                    const Spacer(),
                    Text(date.isNotEmpty ? date : 'Today', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.black87)),
                  ]),
                  const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider()),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.storefront, size: 18, color: primaryColor),
                    const SizedBox(width: 12),
                    Text('Assigned Branches', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[600])),
                    const Spacer(),
                    Expanded(child: Text(branchNames.join(', '), textAlign: TextAlign.right, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: primaryColor))),
                  ]),
                ]),
              ),
              const SizedBox(height: 32),

              // Timeline
              Row(
                children: [
                  _buildTimeBlock(
                    label: 'SHIFT START',
                    time: clockIn != null ? _formatTime(clockIn.toDate()) : '—',
                    icon: Icons.login_rounded,
                    color: Colors.green,
                    isActive: clockIn != null,
                  ),
                  Expanded(
                    child: Column(children: [
                      Container(
                        height: 4,
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: isClockedOut ? 1.0 : 0.6,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: [Colors.green, isClockedOut ? Colors.red : Colors.blue]),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(hoursWorked, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.black87)),
                      Text(isClockedOut ? 'TOTAL DURATION' : 'ACTIVE DURATION', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.grey[500], letterSpacing: 1)),
                    ]),
                  ),
                  _buildTimeBlock(
                    label: 'SHIFT END',
                    time: isClockedOut ? _formatTime(clockOut.toDate()) : 'PENDING',
                    icon: Icons.logout_rounded,
                    color: isClockedOut ? Colors.red : Colors.grey,
                    isActive: isClockedOut,
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // KPI Grid
              GridView.count(
                shrinkWrap: true,
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 3.5,
                children: [
                  _kpiCard('Scheduled', scheduledStart.isNotEmpty ? scheduledStart : 'Open', Icons.history),
                  _kpiCard('Punctuality', isLate ? 'Late' : 'On Time', Icons.timer_outlined, color: isLate ? Colors.red : Colors.green),
                  _kpiCard('Overtime', duration != null && duration.inHours >= 8 ? '${duration.inHours - 8}h ${duration.inMinutes.remainder(60)}m' : 'Standard', Icons.more_time),
                  _kpiCard('System ID', docId.substring(0, 8).toUpperCase(), Icons.qr_code, isFaded: true),
                ],
              ),

              if (notes.isNotEmpty) ...[
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.amber.withValues(alpha: 0.2))),
                  child: Row(children: [
                    const Icon(Icons.note_alt_outlined, color: Colors.amber, size: 20),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('MANAGER NOTES', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.amber, letterSpacing: 1)),
                      const SizedBox(height: 4),
                      Text(notes, style: TextStyle(fontSize: 13, color: Colors.amber.shade900, fontWeight: FontWeight.w600, height: 1.4)),
                    ])),
                  ]),
                ),
              ],
              
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: const Text('ACKNOWLEDGE & CLOSE', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1, fontSize: 12)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kpiCard(String label, String value, IconData icon, {Color? color, bool isFaded = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(children: [
        Icon(icon, size: 16, color: color ?? Colors.grey[400]),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(label.toUpperCase(), style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Colors.grey[400], letterSpacing: 1)),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: isFaded ? Colors.grey : (color ?? Colors.black87))),
        ]),
      ]),
    );
  }

  Widget _buildTimeBlock({required String label, required String time, required IconData icon, required Color color, required bool isActive}) {
    return Column(children: [
      Container(
        width: 48, height: 48,
        decoration: BoxDecoration(
          color: isActive ? color.withValues(alpha: 0.08) : Colors.grey[100],
          shape: BoxShape.circle,
          border: Border.all(color: isActive ? color.withValues(alpha: 0.2) : Colors.grey[300]!, width: 2),
        ),
        child: Icon(icon, color: isActive ? color : Colors.grey[400], size: 22),
      ),
      const SizedBox(height: 12),
      Text(time, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: isActive ? Colors.black87 : Colors.grey[400])),
      const SizedBox(height: 4),
      Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.grey[500], letterSpacing: 1)),
    ]);
  }

  Widget _buildDetailRow(String label, String value, IconData icon, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Icon(icon, size: 16, color: Colors.grey[400]),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[600])),
        const Spacer(),
        Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: valueColor ?? Colors.black87)),
      ]),
    );
  }

  Widget _buildDivider() => Divider(height: 1, color: Colors.grey[200]);
}

String _formatTime(DateTime dt) {
  final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
  final m = dt.minute.toString().padLeft(2, '0');
  final ampm = dt.hour >= 12 ? 'PM' : 'AM';
  return '$h:$m $ampm';
}

// =============================================================================
// STAFF FORM DIALOG — Add / Edit (shared)
// =============================================================================
class _StaffFormDialog extends StatefulWidget {
  final StaffService staffService;
  final String currentUserEmail;
  final Map<String, dynamic>? existingData;
  final String? staffId;

  const _StaffFormDialog({required this.staffService, required this.currentUserEmail, this.existingData, this.staffId});

  @override
  State<_StaffFormDialog> createState() => _StaffFormDialogState();
}

class _StaffFormDialogState extends State<_StaffFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameC = TextEditingController();
  final _emailC = TextEditingController();
  final _phoneC = TextEditingController();
  final _qidC = TextEditingController();
  final _passportC = TextEditingController();
  final _salaryC = TextEditingController();
  // Driver-specific controllers
  final _licenseC = TextEditingController();
  final _vehiclePlateC = TextEditingController();
  String _vehicleType = 'car';
  String _role = 'branch_admin';
  bool _isActive = true;
  List<String> _selectedBranches = [];
  bool _saving = false;

  bool get isEditing => widget.existingData != null;

  @override
  void initState() {
    super.initState();
    if (isEditing) {
      final d = widget.existingData!;
      _nameC.text = d['name'] ?? '';
      _emailC.text = d['email'] ?? widget.staffId ?? '';
      _phoneC.text = d['phone'] ?? '';
      _qidC.text = d['qid'] ?? '';
      _passportC.text = d['passportNumber'] ?? '';
      final sal = d['salary'];
      _salaryC.text = (sal != null && sal != 0) ? sal.toString() : '';
      String rawRole = d['role'] ?? 'branch_admin';
      if (rawRole == 'superadmin') rawRole = 'super_admin';
      if (rawRole == 'branchadmin') rawRole = 'branch_admin';
      _role = rawRole;
      _isActive = d['isActive'] ?? true;
      _selectedBranches = List<String>.from(d['branchIds'] ?? []);
      // Load role-specific fields
      final rf = d['roleFields'] as Map<String, dynamic>? ?? {};
      if (_role == 'driver') {
        _licenseC.text = rf['licenseNumber'] ?? '';
        _vehicleType = rf['vehicleType'] ?? 'car';
        _vehiclePlateC.text = rf['vehiclePlateNumber'] ?? '';
      }
    }
  }

  @override
  void dispose() {
    _nameC.dispose(); _emailC.dispose(); _phoneC.dispose();
    _qidC.dispose(); _passportC.dispose(); _salaryC.dispose();
    _licenseC.dispose(); _vehiclePlateC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(isEditing ? 'Edit Staff Member' : 'Add New Staff'),
      content: SizedBox(width: 560, child: SingleChildScrollView(child: Form(key: _formKey, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        // --- Basic Info ---
        Row(children: [
          Expanded(child: TextFormField(controller: _nameC, decoration: _dec('Full Name', Icons.badge), validator: (v) => v!.isEmpty ? 'Required' : null)),
          const SizedBox(width: 16),
          Expanded(child: TextFormField(controller: _emailC, decoration: _dec('Email', Icons.email), enabled: !isEditing, validator: (v) => v!.isEmpty ? 'Required' : !v.contains('@') ? 'Invalid' : null)),
        ]),
        const SizedBox(height: 16),
        TextFormField(controller: _phoneC, decoration: _dec('Phone', Icons.phone), keyboardType: TextInputType.phone),
        const SizedBox(height: 16),
        // --- Identity & Compensation ---
        const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('Identity & Compensation', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.deepPurple))),
        Row(children: [
          Expanded(child: TextFormField(controller: _qidC, decoration: _dec('QID', Icons.credit_card))),
          const SizedBox(width: 16),
          Expanded(child: TextFormField(controller: _passportC, decoration: _dec('Passport Number', Icons.book))),
        ]),
        const SizedBox(height: 16),
        TextFormField(controller: _salaryC, decoration: _dec('Salary (QAR)', Icons.payments), keyboardType: const TextInputType.numberWithOptions(decimal: true)),
        const SizedBox(height: 16),
        // --- Role ---
        DropdownButtonFormField<String>(value: _role, decoration: _dec('Role', Icons.work), items: const [
          DropdownMenuItem(value: 'super_admin', child: Text('Super Admin')),
          DropdownMenuItem(value: 'branch_admin', child: Text('Branch Admin')),
          DropdownMenuItem(value: 'manager', child: Text('Manager')),
          DropdownMenuItem(value: 'server', child: Text('Server')),
          DropdownMenuItem(value: 'driver', child: Text('Driver')),
        ], onChanged: (v) => setState(() => _role = v!)),
        // --- Driver-specific fields ---
        if (_role == 'driver') ...[
          const SizedBox(height: 16),
          const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('Driver Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.orange))),
          Row(children: [
            Expanded(child: TextFormField(controller: _licenseC, decoration: _dec('License Number', Icons.directions_car), validator: (v) => v!.isEmpty ? 'Required for drivers' : null)),
            const SizedBox(width: 16),
            Expanded(child: DropdownButtonFormField<String>(value: _vehicleType, decoration: _dec('Vehicle Type', Icons.local_shipping), items: const [
              DropdownMenuItem(value: 'car', child: Text('Car')),
              DropdownMenuItem(value: 'bike', child: Text('Bike')),
              DropdownMenuItem(value: 'van', child: Text('Van')),
            ], onChanged: (v) => setState(() => _vehicleType = v!))),
          ]),
          const SizedBox(height: 16),
          TextFormField(controller: _vehiclePlateC, decoration: _dec('Vehicle Plate Number', Icons.confirmation_number), validator: (v) => v!.isEmpty ? 'Required for drivers' : null),
        ],
        if (isEditing) ...[
          const SizedBox(height: 8),
          SwitchListTile(title: const Text('Active'), value: _isActive, activeColor: Colors.deepPurple, contentPadding: EdgeInsets.zero, onChanged: (v) => setState(() => _isActive = v)),
        ],
        const SizedBox(height: 16),
        const Text('Branch Assignment', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.deepPurple)),
        const SizedBox(height: 8),
        Container(
          height: 150,
          decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(12)),
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('Branch').snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              return ListView(children: snapshot.data!.docs.map((doc) {
                final name = doc['name'];
                final id = doc.id;
                return CheckboxListTile(title: Text(name), value: _selectedBranches.contains(id), activeColor: Colors.deepPurple, dense: true, onChanged: (v) {
                  setState(() { if (v == true) _selectedBranches.add(id); else _selectedBranches.remove(id); });
                });
              }).toList());
            },
          ),
        ),
      ])))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
          child: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(isEditing ? 'Update' : 'Add Staff'),
        ),
      ],
    );
  }

  InputDecoration _dec(String label, IconData icon) => InputDecoration(
    labelText: label, prefixIcon: Icon(icon, size: 20, color: Colors.grey[600]),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), filled: true, fillColor: Colors.grey[50], isDense: true,
  );

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedBranches.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select at least one branch'))); return; }
    setState(() => _saving = true);
    try {
      final Map<String, dynamic> roleFields = {};
      if (_role == 'driver') {
        roleFields['licenseNumber'] = _licenseC.text.trim();
        roleFields['vehicleType'] = _vehicleType;
        roleFields['vehiclePlateNumber'] = _vehiclePlateC.text.trim();
      }
      final data = {
        'name': _nameC.text.trim(), 'email': _emailC.text.trim(), 'phone': _phoneC.text.trim(),
        'qid': _qidC.text.trim(), 'passportNumber': _passportC.text.trim(),
        'salary': double.tryParse(_salaryC.text.trim()) ?? 0,
        'role': _role, 'roleFields': roleFields,
        'isActive': _isActive, 'branchIds': _selectedBranches, 'permissions': {},
      };
      if (isEditing) {
        await widget.staffService.updateStaff(widget.staffId!, data, widget.currentUserEmail);
      } else {
        await widget.staffService.addStaff(data, widget.currentUserEmail);
      }
      if (mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isEditing ? '✅ Staff updated' : '✅ Staff added'), backgroundColor: Colors.green)); }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    } finally { if (mounted) setState(() => _saving = false); }
  }
}

// =============================================================================
// SHIFT FORM DIALOG
// =============================================================================
class _ShiftFormDialog extends StatefulWidget {
  final StaffService staffService;
  final List<String> branchIds;
  final String userEmail;
  final String? staffId; // The staff identifier (doc ID)
  final String? prefilledEmail;
  final String? prefilledName;
  final int? prefilledDay;
  final Map<String, dynamic>? existingShift;
  final String? shiftDocId;

  const _ShiftFormDialog({
    required this.staffService, 
    required this.branchIds, 
    required this.userEmail, 
    this.staffId,
    this.prefilledEmail, 
    this.prefilledName, 
    this.prefilledDay, 
    this.existingShift, 
    this.shiftDocId,
  });

  @override State<_ShiftFormDialog> createState() => _ShiftFormDialogState();
}

class _ShiftFormDialogState extends State<_ShiftFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailC = TextEditingController();
  final _nameC = TextEditingController();
  String? _selectedStaffId;
  int _dayOfWeek = 1;
  String _startTime = '08:00';
  String _endTime = '16:00';
  String _shiftType = 'morning';
  bool _isOff = false;
  bool _saving = false;
  List<String> _selectedBranches = [];

  bool get isEditing => widget.existingShift != null;

  static const _dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  static const _shiftTypes = ['morning', 'afternoon', 'evening', 'night', 'split'];

  @override
  void initState() {
    super.initState();
    if (isEditing) {
      final d = widget.existingShift!;
      _selectedStaffId = d['staffId'];
      _emailC.text = d['staffEmail'] ?? '';
      _nameC.text = d['staffName'] ?? '';
      _dayOfWeek = d['dayOfWeek'] ?? 1;
      _startTime = d['startTime'] ?? '08:00';
      _endTime = d['endTime'] ?? '16:00';
      _shiftType = d['shiftType'] ?? 'morning';
      _isOff = d['isOff'] ?? false;
      _selectedBranches = List<String>.from(d['branchIds'] ?? []);
    } else {
      _selectedStaffId = widget.staffId; 
      _emailC.text = widget.prefilledEmail ?? '';
      _nameC.text = widget.prefilledName ?? '';
      _dayOfWeek = widget.prefilledDay ?? 1;
      _selectedBranches = List<String>.from(widget.branchIds);
    }
  }

  @override void dispose() { _emailC.dispose(); _nameC.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(isEditing ? 'Edit Shift' : 'Add Shift'),
      content: SizedBox(width: 400, child: SingleChildScrollView(child: Form(key: _formKey, child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (!isEditing && widget.prefilledEmail == null) ...[
          StreamBuilder<QuerySnapshot>(
            stream: widget.staffService.getStaffStream(branchIds: widget.branchIds),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator());
              final staffList = snapshot.data!.docs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return {...data, 'id': doc.id};
              }).toList();
              final selectedEmail = _emailC.text.isEmpty ? null : _emailC.text;
              return DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Select Staff Member', isDense: true),
                value: staffList.any((s) => s['id'] == _selectedStaffId) ? _selectedStaffId : null,
                items: staffList.map((s) => DropdownMenuItem(
                  value: s['id'] as String,
                  child: Text('${s['name']} (${s['email']})'),
                )).toList(),
                onChanged: (val) {
                  if (val != null) {
                    final selected = staffList.firstWhere((s) => s['id'] == val);
                    setState(() {
                      _selectedStaffId = val;
                      _emailC.text = selected['email'] ?? '';
                      _nameC.text = selected['name'] ?? 'Unknown';
                    });
                  }
                },
                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
              );
            },
          ),
          const SizedBox(height: 12),
        ],
        DropdownButtonFormField<int>(value: _dayOfWeek, decoration: const InputDecoration(labelText: 'Day of Week', isDense: true),
          items: List.generate(7, (i) => DropdownMenuItem(value: i + 1, child: Text(_dayNames[i]))),
          onChanged: isEditing ? null : (v) => setState(() => _dayOfWeek = v!),
        ),
        const SizedBox(height: 12),
        SwitchListTile(title: const Text('Day Off'), value: _isOff, activeColor: Colors.deepPurple, contentPadding: EdgeInsets.zero, onChanged: (v) => setState(() => _isOff = v)),
        if (!_isOff) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextFormField(initialValue: _startTime, decoration: const InputDecoration(labelText: 'Start (HH:MM)', isDense: true),
              onChanged: (v) => _startTime = v, validator: (v) => v!.isEmpty ? 'Required' : null)),
            const SizedBox(width: 12),
            Expanded(child: TextFormField(initialValue: _endTime, decoration: const InputDecoration(labelText: 'End (HH:MM)', isDense: true),
              onChanged: (v) => _endTime = v, validator: (v) => v!.isEmpty ? 'Required' : null)),
          ]),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(value: _shiftType, decoration: const InputDecoration(labelText: 'Shift Type', isDense: true),
            items: _shiftTypes.map((t) => DropdownMenuItem(value: t, child: Text(t[0].toUpperCase() + t.substring(1)))).toList(),
            onChanged: (v) => setState(() => _shiftType = v!)),
        ],
        const SizedBox(height: 16),
        const Align(alignment: Alignment.centerLeft, child: Text('Shift Branch', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.deepPurple))),
        const SizedBox(height: 8),
        Container(
          height: 150,
          decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(12)),
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('Branch').snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              return ListView(children: snapshot.data!.docs.map((doc) {
                final name = doc['name'];
                final id = doc.id;
                return CheckboxListTile(title: Text(name), value: _selectedBranches.contains(id), activeColor: Colors.deepPurple, dense: true, onChanged: (v) {
                  setState(() { if (v == true) _selectedBranches.add(id); else _selectedBranches.remove(id); });
                });
              }).toList());
            },
          ),
        ),
      ])))),
      actions: [
        if (isEditing) TextButton(onPressed: () async {
          Navigator.pop(context);
          await widget.staffService.deleteShift(widget.shiftDocId!);
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Shift deleted'), backgroundColor: Colors.orange));
        }, child: const Text('Delete', style: TextStyle(color: Colors.red))),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
          child: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(isEditing ? 'Update' : 'Add'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedBranches.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select at least one branch for this shift'))); return; }
    setState(() => _saving = true);
    try {
      if (isEditing) {
        await widget.staffService.updateShift(widget.shiftDocId!, {
          'startTime': _startTime, 
          'endTime': _endTime, 
          'shiftType': _shiftType, 
          'isOff': _isOff, 
          'branchIds': _selectedBranches,
          // If we allow changing staff during edit, we'd add staffId/staffEmail here
        });
      } else {
        await widget.staffService.addShift(
          staffId: _selectedStaffId!,
          staffEmail: _emailC.text.trim(), 
          staffName: _nameC.text.trim(), 
          branchIds: _selectedBranches,
          dayOfWeek: _dayOfWeek, 
          startTime: _startTime, 
          endTime: _endTime, 
          shiftType: _shiftType, 
          isOff: _isOff, 
          createdBy: widget.userEmail,
        );
      }
      if (mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isEditing ? '✅ Shift updated' : '✅ Shift added'), backgroundColor: Colors.green)); }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    } finally { if (mounted) setState(() => _saving = false); }
  }
}
