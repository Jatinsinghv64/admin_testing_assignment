import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../Widgets/BranchFilterService.dart';
import '../Widgets/CancellationDialog.dart';
import '../Widgets/RiderAssignment.dart';
import '../constants.dart';
import '../main.dart';

enum _AssignmentDatePreset {
  today,
  yesterday,
  last7Days,
  last30Days,
  allTime,
  custom,
}

class ManualAssignmentScreenLarge extends StatefulWidget {
  const ManualAssignmentScreenLarge({super.key});

  @override
  State<ManualAssignmentScreenLarge> createState() =>
      _ManualAssignmentScreenLargeState();
}

class _ManualAssignmentScreenLargeState
    extends State<ManualAssignmentScreenLarge> {
  String? _selectedOrderId;
  bool _selectionDismissed = false;
  String _searchQuery = '';
  _AssignmentDatePreset _datePreset = _AssignmentDatePreset.today;
  late DateTimeRange _customDateRange;

  @override
  void initState() {
    super.initState();
    _customDateRange = _buildTodayRange();
  }

  @override
  Widget build(BuildContext context) {
    final userScope = context.watch<UserScopeService>();
    final branchFilter = context.watch<BranchFilterService>();
    final theme = Theme.of(context);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (userScope.branchIds.length > 1 && !branchFilter.isLoaded) {
        branchFilter.loadBranchNames(userScope.branchIds);
      }
    });

    final query = _buildOrdersQuery(userScope, branchFilter);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, viewport) {
            final horizontalPadding = viewport.maxWidth < 1440 ? 16.0 : 24.0;
            final useStackedLayout = viewport.maxWidth < 1280;
            final contentHeight = math.max(
              viewport.maxHeight - (useStackedLayout ? 250 : 190),
              useStackedLayout ? 840.0 : 560.0,
            );

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: query.snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _buildFullscreenState(
                    icon: Icons.error_outline_rounded,
                    title: 'Unable to load manual assignments',
                    subtitle: '${snapshot.error}',
                    accentColor: theme.colorScheme.error,
                  );
                }

                if (!snapshot.hasData) {
                  return Center(
                    child: CircularProgressIndicator(
                      color: theme.colorScheme.primary,
                    ),
                  );
                }

                final allDocs = snapshot.data!.docs;
                final filteredDocs = allDocs.where((doc) {
                  final data = doc.data();
                  final timestamp = (data['timestamp'] as Timestamp?)?.toDate();

                  if (!_matchesDateRange(timestamp)) {
                    return false;
                  }

                  if (!_matchesSearch(data, doc.id, branchFilter)) {
                    return false;
                  }

                  return true;
                }).toList()
                  ..sort((a, b) {
                    final aTime =
                        (a.data()['timestamp'] as Timestamp?)?.toDate() ??
                            DateTime.fromMillisecondsSinceEpoch(0);
                    final bTime =
                        (b.data()['timestamp'] as Timestamp?)?.toDate() ??
                            DateTime.fromMillisecondsSinceEpoch(0);
                    return bTime.compareTo(aTime);
                  });

                _syncSelectedOrder(filteredDocs);

                final selectedDoc = _selectionDismissed &&
                        _selectedOrderId == null
                    ? null
                    : (_resolveSelectedDoc(filteredDocs) ??
                        (filteredDocs.isNotEmpty ? filteredDocs.first : null));
                final overdueCount = filteredDocs.where((doc) {
                  final timestamp =
                      (doc.data()['timestamp'] as Timestamp?)?.toDate();
                  if (timestamp == null) {
                    return false;
                  }
                  return DateTime.now().difference(timestamp).inMinutes >= 25;
                }).length;

                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    16,
                    horizontalPadding,
                    16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _AssignmentHeader(
                        totalCount: allDocs.length,
                        visibleCount: filteredDocs.length,
                        overdueCount: overdueCount,
                        branchLabel:
                            _buildBranchScopeLabel(userScope, branchFilter),
                        rangeLabel: _buildRangeLabel(),
                      ),
                      const SizedBox(height: 12),
                      _buildFilterBar(context, branchFilter),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: contentHeight,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final useStackedLayout =
                                constraints.maxWidth < 1280;

                            if (useStackedLayout) {
                              final queueHeight = math.min(
                                320.0,
                                math.max(260.0, constraints.maxHeight * 0.32),
                              );

                              return Column(
                                children: [
                                  SizedBox(
                                    height: queueHeight,
                                    child: _buildOrdersPane(
                                      docs: filteredDocs,
                                      branchFilter: branchFilter,
                                      selectedOrderId: selectedDoc?.id,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Expanded(
                                    child: selectedDoc != null
                                        ? _AssignmentDetailPane(
                                            orderId: selectedDoc.id,
                                            initialOrderDoc: selectedDoc,
                                            userScope: userScope,
                                            branchFilter: branchFilter,
                                            onClose: _clearSelection,
                                          )
                                        : _buildEmptySelectionState(),
                                  ),
                                ],
                              );
                            }

                            final listPaneWidth = math.min(
                              380.0,
                              math.max(330.0, constraints.maxWidth * 0.32),
                            );

                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SizedBox(
                                  width: listPaneWidth,
                                  child: _buildOrdersPane(
                                    docs: filteredDocs,
                                    branchFilter: branchFilter,
                                    selectedOrderId: selectedDoc?.id,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: selectedDoc != null
                                      ? _AssignmentDetailPane(
                                          orderId: selectedDoc.id,
                                          initialOrderDoc: selectedDoc,
                                          userScope: userScope,
                                          branchFilter: branchFilter,
                                          onClose: _clearSelection,
                                        )
                                      : _buildEmptySelectionState(),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Query<Map<String, dynamic>> _buildOrdersQuery(
    UserScopeService userScope,
    BranchFilterService branchFilter,
  ) {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('Orders')
        .where('status', isEqualTo: 'needs_rider_assignment')
        .where('Order_type', isEqualTo: 'delivery')
        .orderBy('timestamp', descending: true);

    final filterBranchIds =
        branchFilter.getFilterBranchIds(userScope.branchIds);

    if (userScope.isSuperAdmin &&
        (branchFilter.selectedBranchId == null ||
            filterBranchIds.length > 10)) {
      return query;
    }

    if (filterBranchIds.isNotEmpty) {
      if (filterBranchIds.length == 1) {
        return query.where(
          'branchIds',
          arrayContains: filterBranchIds.first,
        );
      }
      return query.where(
        'branchIds',
        arrayContainsAny: filterBranchIds.take(10).toList(),
      );
    }

    if (!userScope.isSuperAdmin && userScope.branchIds.isNotEmpty) {
      if (userScope.branchIds.length == 1) {
        return query.where(
          'branchIds',
          arrayContains: userScope.branchIds.first,
        );
      }
      return query.where(
        'branchIds',
        arrayContainsAny: userScope.branchIds.take(10).toList(),
      );
    }

    if (!userScope.isSuperAdmin && userScope.branchIds.isEmpty) {
      return query.where(FieldPath.documentId, isEqualTo: '__no_orders__');
    }

    return query;
  }

  void _syncSelectedOrder(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final currentSelection = _resolveSelectedDoc(docs);
    final shouldKeepDismissedSelection =
        _selectionDismissed && _selectedOrderId == null && docs.isNotEmpty;
    final nextSelected = shouldKeepDismissedSelection
        ? null
        : (currentSelection ?? (docs.isNotEmpty ? docs.first : null));

    if (nextSelected == null) {
      if (_selectedOrderId == null && docs.isNotEmpty) {
        return;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        setState(() {
          _selectedOrderId = null;
          if (docs.isEmpty) {
            _selectionDismissed = false;
          }
        });
      });
      return;
    }

    if (_selectedOrderId == nextSelected.id) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _selectedOrderId == nextSelected.id) {
        return;
      }
      setState(() {
        _selectedOrderId = nextSelected.id;
      });
    });
  }

  QueryDocumentSnapshot<Map<String, dynamic>>? _resolveSelectedDoc(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    for (final doc in docs) {
      if (doc.id == _selectedOrderId) {
        return doc;
      }
    }
    return null;
  }

  void _clearSelection() {
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedOrderId = null;
      _selectionDismissed = true;
    });
  }

  bool _matchesSearch(
    Map<String, dynamic> data,
    String orderId,
    BranchFilterService branchFilter,
  ) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return true;
    }

    final branchIds =
        (data['branchIds'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final branchNames = branchIds
        .map((id) => branchFilter.getBranchName(id))
        .join(' ')
        .toLowerCase();
    final values = [
      orderId,
      OrderNumberHelper.getDisplayNumber(data, orderId: orderId),
      data['customerName']?.toString() ?? '',
      data['customerPhone']?.toString() ?? '',
      data['assignmentNotes']?.toString() ?? '',
      branchNames,
    ];

    return values.any((value) => value.toLowerCase().contains(query));
  }

  bool _matchesDateRange(DateTime? timestamp) {
    final activeRange = _activeDateRange;
    if (timestamp == null) {
      return false;
    }

    return !timestamp.isBefore(activeRange.start) &&
        !timestamp.isAfter(activeRange.end);
  }

  DateTimeRange get _activeDateRange {
    switch (_datePreset) {
      case _AssignmentDatePreset.today:
        return _buildTodayRange();
      case _AssignmentDatePreset.yesterday:
        final now = DateTime.now();
        final start = DateTime(now.year, now.month, now.day)
            .subtract(const Duration(days: 1));
        final end = DateTime(
          start.year,
          start.month,
          start.day,
          23,
          59,
          59,
          999,
        );
        return DateTimeRange(start: start, end: end);
      case _AssignmentDatePreset.last7Days:
        final now = DateTime.now();
        final start = DateTime(now.year, now.month, now.day)
            .subtract(const Duration(days: 6));
        final end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
        return DateTimeRange(start: start, end: end);
      case _AssignmentDatePreset.last30Days:
        final now = DateTime.now();
        final start = DateTime(now.year, now.month, now.day)
            .subtract(const Duration(days: 29));
        final end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
        return DateTimeRange(start: start, end: end);
      case _AssignmentDatePreset.custom:
        return _customDateRange;
      case _AssignmentDatePreset.allTime:
        return DateTimeRange(
          start: DateTime.fromMillisecondsSinceEpoch(0),
          end: DateTime(9999, 12, 31, 23, 59, 59, 999),
        );
    }
  }

  DateTimeRange _buildTodayRange() {
    final now = DateTime.now();
    return DateTimeRange(
      start: DateTime(now.year, now.month, now.day),
      end: DateTime(now.year, now.month, now.day, 23, 59, 59, 999),
    );
  }

  String _buildRangeLabel() {
    switch (_datePreset) {
      case _AssignmentDatePreset.today:
        return 'Today';
      case _AssignmentDatePreset.yesterday:
        return 'Yesterday';
      case _AssignmentDatePreset.last7Days:
        return 'Last 7 Days';
      case _AssignmentDatePreset.last30Days:
        return 'Last 30 Days';
      case _AssignmentDatePreset.allTime:
        return 'All Time';
      case _AssignmentDatePreset.custom:
        return '${DateFormat('MMM d').format(_customDateRange.start)} - ${DateFormat('MMM d, yyyy').format(_customDateRange.end)}';
    }
  }

  String _buildBranchScopeLabel(
    UserScopeService userScope,
    BranchFilterService branchFilter,
  ) {
    if (branchFilter.selectedBranchId != null) {
      return branchFilter.getBranchName(branchFilter.selectedBranchId!);
    }
    if (userScope.isSuperAdmin) {
      return 'All Branches';
    }
    if (userScope.branchIds.length == 1) {
      return branchFilter.getBranchName(userScope.branchIds.first);
    }
    return '${userScope.branchIds.length} Branches';
  }

  Future<void> _pickCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _customDateRange,
      helpText: 'Select Assignment Date Range',
    );

    if (picked == null || !mounted) {
      return;
    }

    setState(() {
      _customDateRange = DateTimeRange(
        start: DateTime(
          picked.start.year,
          picked.start.month,
          picked.start.day,
        ),
        end: DateTime(
          picked.end.year,
          picked.end.month,
          picked.end.day,
          23,
          59,
          59,
          999,
        ),
      );
      _datePreset = _AssignmentDatePreset.custom;
    });
  }

  Widget _buildFilterBar(
    BuildContext context,
    BranchFilterService branchFilter,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 280,
            child: TextField(
              onChanged: (value) => setState(() {
                _searchQuery = value;
              }),
              decoration: InputDecoration(
                hintText: 'Search by order, customer, phone...',
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: colorScheme.onSurfaceVariant,
                ),
                filled: true,
                fillColor: colorScheme.surface.withValues(alpha: 0.85),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),
          _DatePresetChip(
            label: 'Today',
            isSelected: _datePreset == _AssignmentDatePreset.today,
            onTap: () => setState(() {
              _datePreset = _AssignmentDatePreset.today;
            }),
          ),
          _DatePresetChip(
            label: 'Yesterday',
            isSelected: _datePreset == _AssignmentDatePreset.yesterday,
            onTap: () => setState(() {
              _datePreset = _AssignmentDatePreset.yesterday;
            }),
          ),
          _DatePresetChip(
            label: '7 Days',
            isSelected: _datePreset == _AssignmentDatePreset.last7Days,
            onTap: () => setState(() {
              _datePreset = _AssignmentDatePreset.last7Days;
            }),
          ),
          _DatePresetChip(
            label: '30 Days',
            isSelected: _datePreset == _AssignmentDatePreset.last30Days,
            onTap: () => setState(() {
              _datePreset = _AssignmentDatePreset.last30Days;
            }),
          ),
          _DatePresetChip(
            label: 'All Time',
            isSelected: _datePreset == _AssignmentDatePreset.allTime,
            onTap: () => setState(() {
              _datePreset = _AssignmentDatePreset.allTime;
            }),
          ),
          OutlinedButton.icon(
            onPressed: _pickCustomRange,
            icon: const Icon(Icons.calendar_month_rounded, size: 18),
            label: Text(
              _datePreset == _AssignmentDatePreset.custom
                  ? _buildRangeLabel()
                  : 'Custom Range',
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: colorScheme.primary,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              side: BorderSide(
                color: colorScheme.primary.withValues(alpha: 0.2),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: colorScheme.primary.withValues(alpha: 0.14),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.storefront_rounded,
                  size: 18,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: Text(
                    _buildBranchScopeLabel(
                      context.read<UserScopeService>(),
                      branchFilter,
                    ),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrdersPane({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    required BranchFilterService branchFilter,
    required String? selectedOrderId,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 220),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pending Assignments',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${docs.length} orders waiting for rider dispatch',
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: colorScheme.tertiary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _buildRangeLabel(),
                    style: TextStyle(
                      color: colorScheme.tertiary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: colorScheme.outlineVariant),
          Expanded(
            child: docs.isEmpty
                ? _buildPaneState(
                    icon: Icons.assignment_turned_in_outlined,
                    title: 'No matching assignments',
                    subtitle:
                        'Adjust the date range or search term to review more orders.',
                    accentColor: colorScheme.primary,
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(14),
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      return _OrderListTile(
                        doc: doc,
                        isSelected: doc.id == selectedOrderId,
                        branchFilter: branchFilter,
                        onTap: () {
                          setState(() {
                            _selectedOrderId = doc.id;
                            _selectionDismissed = false;
                          });
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptySelectionState() {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: _buildPaneState(
        icon: Icons.touch_app_rounded,
        title: 'Select an order to continue',
        subtitle:
            'Order details, customer information, and available riders will appear here.',
        accentColor: colorScheme.primary,
      ),
    );
  }

  Widget _buildFullscreenState({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color accentColor,
  }) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: _buildPaneState(
          icon: icon,
          title: title,
          subtitle: subtitle,
          accentColor: accentColor,
        ),
      ),
    );
  }

  Widget _buildPaneState({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color accentColor,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, size: 30, color: accentColor),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssignmentHeader extends StatelessWidget {
  final int totalCount;
  final int visibleCount;
  final int overdueCount;
  final String branchLabel;
  final String rangeLabel;

  const _AssignmentHeader({
    required this.totalCount,
    required this.visibleCount,
    required this.overdueCount,
    required this.branchLabel,
    required this.rangeLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final overdueRatio = visibleCount == 0 ? 0.0 : overdueCount / visibleCount;
    final visibleRatio = totalCount == 0 ? 0.0 : visibleCount / totalCount;
    final queueStatus =
        overdueCount > 0 ? '$overdueCount overdue' : 'Queue stable';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: theme.appBarTheme.backgroundColor ?? colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Wrap(
            spacing: 14,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.assignment_ind_rounded,
                          color: colorScheme.primary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Manual Assignment',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Dispatch pending delivery orders from the current branch scope.',
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  branchLabel,
                  style: TextStyle(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.tertiary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  rangeLabel,
                  style: TextStyle(
                    color: colorScheme.tertiary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: overdueCount > 0
                      ? colorScheme.error.withValues(alpha: 0.1)
                      : colorScheme.secondary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  queueStatus,
                  style: TextStyle(
                    color: overdueCount > 0
                        ? colorScheme.error
                        : colorScheme.secondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _HeaderMetricCard(
                title: 'Visible Orders',
                value: visibleCount.toString(),
                change: 'Live',
                progress: visibleRatio,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 12),
              _HeaderMetricCard(
                title: 'Overdue',
                value: overdueCount.toString(),
                change: overdueCount > 0 ? 'Attention' : 'Stable',
                progress: overdueRatio,
                color: colorScheme.error,
                emphasizeAlert: overdueCount > 0,
              ),
              const SizedBox(width: 12),
              _HeaderMetricCard(
                title: 'Active Scope',
                value: branchLabel,
                change: 'Branch',
                progress: 1,
                color: colorScheme.secondary,
              ),
              const SizedBox(width: 12),
              _HeaderMetricCard(
                title: 'Queue Total',
                value: totalCount.toString(),
                change: 'Open',
                progress: visibleRatio,
                color: colorScheme.primary,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeaderMetricCard extends StatelessWidget {
  final String title;
  final String value;
  final String change;
  final double progress;
  final Color color;
  final bool emphasizeAlert;

  const _HeaderMetricCard({
    required this.title,
    required this.value,
    required this.change,
    required this.progress,
    required this.color,
    this.emphasizeAlert = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: 196,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  change,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: emphasizeAlert ? colorScheme.error : color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: progress.clamp(0.0, 1.0),
              backgroundColor:
                  colorScheme.outlineVariant.withValues(alpha: 0.8),
              valueColor: AlwaysStoppedAnimation<Color>(
                emphasizeAlert ? colorScheme.error : color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DatePresetChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _DatePresetChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primary
              : colorScheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? colorScheme.primary
                : colorScheme.primary.withValues(alpha: 0.2),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? colorScheme.onPrimary : colorScheme.primary,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _OrderListTile extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final bool isSelected;
  final BranchFilterService branchFilter;
  final VoidCallback onTap;

  const _OrderListTile({
    required this.doc,
    required this.isSelected,
    required this.branchFilter,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final data = doc.data();
    final timestamp = (data['timestamp'] as Timestamp?)?.toDate();
    final totalAmount = (data['totalAmount'] as num? ?? 0).toDouble();
    final customerName =
        (data['customerName'] ?? 'Unknown Customer').toString();
    final manualNote = (data['assignmentNotes'] ?? '').toString().trim();
    final orderNumber =
        OrderNumberHelper.getDisplayNumber(data, orderId: doc.id);
    final branchLabel = _branchLabel(data, branchFilter);
    final address = _formatAddress(data['deliveryAddress']);
    final waitDuration =
        timestamp != null ? DateTime.now().difference(timestamp) : null;
    final waitColor = _waitColor(waitDuration);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isSelected
                ? colorScheme.primary.withValues(alpha: 0.06)
                : colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary.withValues(alpha: 0.24)
                  : colorScheme.outlineVariant,
              width: isSelected ? 1.2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Order #$orderNumber',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: isSelected
                                ? colorScheme.primary
                                : colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          customerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: waitColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      waitDuration == null
                          ? '--'
                          : _formatWaitDuration(waitDuration),
                      style: TextStyle(
                        color: waitColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _InfoPill(
                    icon: Icons.schedule_rounded,
                    label: timestamp == null
                        ? 'No time'
                        : DateFormat('MMM d, hh:mm a').format(timestamp),
                  ),
                  _InfoPill(
                    icon: Icons.storefront_rounded,
                    label: branchLabel,
                  ),
                  _InfoPill(
                    icon: Icons.payments_outlined,
                    label: 'QAR ${totalAmount.toStringAsFixed(2)}',
                  ),
                ],
              ),
              if (address.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  address,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
              if (manualNote.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.orange.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Text(
                    manualNote,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.orange.shade900,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _branchLabel(
    Map<String, dynamic> data,
    BranchFilterService branchFilter,
  ) {
    final branchIds =
        (data['branchIds'] as List?)?.map((e) => e.toString()).toList() ?? [];
    if (branchIds.isEmpty) {
      return 'No Branch';
    }

    final first = branchFilter.getBranchName(branchIds.first);
    if (branchIds.length == 1) {
      return first;
    }
    return '$first +${branchIds.length - 1}';
  }

  static String _formatAddress(dynamic addressData) {
    if (addressData == null) {
      return '';
    }
    if (addressData is String) {
      return addressData.trim();
    }
    if (addressData is Map) {
      final building = addressData['buildingName']?.toString() ?? '';
      final street = addressData['street']?.toString() ?? '';
      final area = addressData['area']?.toString() ?? '';
      final zone = addressData['zone']?.toString() ?? '';

      return [building, street, area, zone]
          .where((value) => value.trim().isNotEmpty)
          .join(', ');
    }
    return addressData.toString();
  }

  static Color _waitColor(Duration? duration) {
    if (duration == null) {
      return Colors.grey;
    }
    if (duration.inMinutes >= 25) {
      return Colors.red;
    }
    if (duration.inMinutes >= 12) {
      return Colors.orange;
    }
    return Colors.green;
  }
}

class _AssignmentDetailPane extends StatefulWidget {
  final String orderId;
  final QueryDocumentSnapshot<Map<String, dynamic>> initialOrderDoc;
  final UserScopeService userScope;
  final BranchFilterService branchFilter;
  final VoidCallback onClose;

  const _AssignmentDetailPane({
    required this.orderId,
    required this.initialOrderDoc,
    required this.userScope,
    required this.branchFilter,
    required this.onClose,
  });

  @override
  State<_AssignmentDetailPane> createState() => _AssignmentDetailPaneState();
}

class _AssignmentDetailPaneState extends State<_AssignmentDetailPane> {
  bool _isCancelling = false;
  String? _assigningRiderId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('Orders')
            .doc(widget.orderId)
            .snapshots(),
        builder: (context, snapshot) {
          final doc = snapshot.data;
          final fallbackData = widget.initialOrderDoc.data();
          final data = doc?.data() ?? fallbackData;

          if (snapshot.hasError) {
            return _InlineStateCard(
              icon: Icons.error_outline_rounded,
              title: 'Unable to open order details',
              subtitle: '${snapshot.error}',
              accentColor: Colors.red,
              actionLabel: 'Close',
              onAction: widget.onClose,
            );
          }

          if (!snapshot.hasData && data.isEmpty) {
            return Center(
              child: CircularProgressIndicator(color: colorScheme.primary),
            );
          }

          if (doc != null && !doc.exists) {
            return _InlineStateCard(
              icon: Icons.inventory_2_outlined,
              title: 'Order no longer available',
              subtitle:
                  'This assignment was removed or completed from another screen.',
              accentColor: colorScheme.outline,
              actionLabel: 'Close',
              onAction: widget.onClose,
            );
          }

          final status = (data['status'] ?? '').toString();
          if (status.isNotEmpty && status != 'needs_rider_assignment') {
            return _InlineStateCard(
              icon: Icons.check_circle_outline_rounded,
              title: 'Assignment no longer required',
              subtitle:
                  'This order is now in "$status" status and has left the manual assignment queue.',
              accentColor: Colors.green,
              actionLabel: 'Back to Queue',
              onAction: widget.onClose,
            );
          }

          final orderNumber =
              OrderNumberHelper.getDisplayNumber(data, orderId: widget.orderId);
          final timestamp = (data['timestamp'] as Timestamp?)?.toDate();
          final items = List<Map<String, dynamic>>.from(data['items'] ?? []);
          final targetBranchId = _resolveTargetBranchId(data);
          final branchLabel = _resolveBranchLabel(data);
          final waitDuration =
              timestamp != null ? DateTime.now().difference(timestamp) : null;

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compactHeader = constraints.maxWidth < 760;

                    return Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              onPressed: widget.onClose,
                              icon: const Icon(Icons.arrow_back_rounded),
                              tooltip: 'Back to queue',
                            ),
                            const SizedBox(width: 8),
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: compactHeader
                                    ? math.max(
                                        constraints.maxWidth - 72,
                                        180.0,
                                      )
                                    : math.max(
                                        constraints.maxWidth - 260,
                                        260.0,
                                      ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Order #$orderNumber',
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: colorScheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      _InfoPill(
                                        icon: Icons.schedule_rounded,
                                        label: timestamp == null
                                            ? 'No timestamp'
                                            : DateFormat('MMM d, hh:mm a')
                                                .format(timestamp),
                                      ),
                                      _InfoPill(
                                        icon: Icons.timer_rounded,
                                        label: waitDuration == null
                                            ? '--'
                                            : _formatWaitDuration(
                                                waitDuration,
                                              ),
                                      ),
                                      _InfoPill(
                                        icon: Icons.storefront_rounded,
                                        label: branchLabel,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        OutlinedButton.icon(
                          onPressed: _isCancelling ? null : _handleCancelOrder,
                          icon: _isCancelling
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.cancel_outlined, size: 18),
                          label:
                              Text(_isCancelling ? 'Cancelling...' : 'Cancel'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: colorScheme.error,
                            side: BorderSide(
                              color: colorScheme.error.withValues(alpha: 0.3),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              Divider(height: 1, color: colorScheme.outlineVariant),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final stacked = constraints.maxWidth < 960;

                    if (stacked) {
                      return Column(
                        children: [
                          Expanded(
                            flex: 4,
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(16),
                              child: _AssignmentOverview(
                                data: data,
                                branchLabel: branchLabel,
                                timestamp: timestamp,
                                items: items,
                              ),
                            ),
                          ),
                          Divider(height: 1, color: colorScheme.outlineVariant),
                          Expanded(
                            flex: 3,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: _RiderSelectionPanel(
                                branchId: targetBranchId,
                                branchLabel: branchLabel,
                                assigningRiderId: _assigningRiderId,
                                onAssign: _handleAssign,
                              ),
                            ),
                          ),
                        ],
                      );
                    }

                    return Row(
                      children: [
                        Expanded(
                          flex: 5,
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: _AssignmentOverview(
                              data: data,
                              branchLabel: branchLabel,
                              timestamp: timestamp,
                              items: items,
                            ),
                          ),
                        ),
                        VerticalDivider(
                          width: 1,
                          color: colorScheme.outlineVariant,
                        ),
                        SizedBox(
                          width: math.min(380, constraints.maxWidth * 0.36),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: _RiderSelectionPanel(
                              branchId: targetBranchId,
                              branchLabel: branchLabel,
                              assigningRiderId: _assigningRiderId,
                              onAssign: _handleAssign,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _resolveTargetBranchId(Map<String, dynamic> data) {
    final branchIds =
        (data['branchIds'] as List?)?.map((e) => e.toString()).toList() ?? [];
    if (branchIds.isNotEmpty) {
      return branchIds.first;
    }
    if (widget.userScope.branchIds.isNotEmpty) {
      return widget.userScope.branchIds.first;
    }
    return '';
  }

  String _resolveBranchLabel(Map<String, dynamic> data) {
    final branchIds =
        (data['branchIds'] as List?)?.map((e) => e.toString()).toList() ?? [];
    if (branchIds.isEmpty) {
      return 'Unassigned Branch';
    }
    final firstName = widget.branchFilter.getBranchName(branchIds.first);
    if (branchIds.length == 1) {
      return firstName;
    }
    return '$firstName +${branchIds.length - 1}';
  }

  Future<void> _handleCancelOrder() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => const CancellationReasonDialog(
        title: 'Cancel Order?',
        confirmText: 'Confirm Cancel',
        reasons: CancellationReasons.orderReasons,
      ),
    );

    if (reason == null || reason.trim().isEmpty) {
      return;
    }

    setState(() {
      _isCancelling = true;
    });

    try {
      await FirebaseFirestore.instance
          .collection('Orders')
          .doc(widget.orderId)
          .update({
        'status': 'cancelled',
        'cancellationReason': reason.trim(),
        'cancelledAt': FieldValue.serverTimestamp(),
        'cancelledBy': 'Admin Integration',
      });

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Order cancelled successfully'),
          backgroundColor: Colors.green,
        ),
      );
      widget.onClose();
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to cancel order: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isCancelling = false;
        });
      }
    }
  }

  Future<void> _handleAssign(String riderId) async {
    setState(() {
      _assigningRiderId = riderId;
    });

    final result = await RiderAssignmentService.manualAssignRider(
      orderId: widget.orderId,
      riderId: riderId,
    );

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.backgroundColor,
      ),
    );

    if (result.isSuccess) {
      widget.onClose();
      return;
    }

    setState(() {
      _assigningRiderId = null;
    });
  }
}

class _AssignmentOverview extends StatelessWidget {
  final Map<String, dynamic> data;
  final String branchLabel;
  final DateTime? timestamp;
  final List<Map<String, dynamic>> items;

  const _AssignmentOverview({
    required this.data,
    required this.branchLabel,
    required this.timestamp,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final customerName =
        (data['customerName'] ?? 'Unknown Customer').toString();
    final customerPhone = (data['customerPhone'] ?? 'No phone').toString();
    final paymentMethod = (data['paymentMethod'] ?? 'Not specified').toString();
    final manualNote = (data['assignmentNotes'] ?? '').toString().trim();
    final orderNotes = (data['orderNotes'] ?? '').toString().trim();
    final totalAmount = (data['totalAmount'] as num? ?? 0).toDouble();
    final subtotal = (data['subtotal'] as num? ?? 0).toDouble();
    final deliveryCharge = (data['riderPaymentAmount'] as num? ??
            data['deliveryFee'] as num? ??
            data['deliveryCharge'] as num? ??
            0)
        .toDouble();
    final waitDuration =
        timestamp != null ? DateTime.now().difference(timestamp!) : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionCard(
          title: 'Assignment Summary',
          icon: Icons.assignment_late_outlined,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final tileWidth = constraints.maxWidth < 520
                  ? constraints.maxWidth
                  : math.min((constraints.maxWidth - 12) / 2, 200.0);

              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: tileWidth,
                    child: _SummaryTile(
                      label: 'Placed At',
                      value: timestamp == null
                          ? 'Unavailable'
                          : DateFormat('MMM d, yyyy hh:mm a')
                              .format(timestamp!),
                    ),
                  ),
                  SizedBox(
                    width: tileWidth,
                    child: _SummaryTile(
                      label: 'Wait Time',
                      value: waitDuration == null
                          ? '--'
                          : _formatWaitDuration(waitDuration),
                    ),
                  ),
                  SizedBox(
                    width: tileWidth,
                    child: _SummaryTile(
                      label: 'Branch',
                      value: branchLabel,
                    ),
                  ),
                  SizedBox(
                    width: tileWidth,
                    child: _SummaryTile(
                      label: 'Payment',
                      value: paymentMethod,
                    ),
                  ),
                  SizedBox(
                    width: tileWidth,
                    child: _SummaryTile(
                      label: 'Order Type',
                      value: (data['Order_type'] ?? 'delivery').toString(),
                    ),
                  ),
                  SizedBox(
                    width: tileWidth,
                    child: _SummaryTile(
                      label: 'Items',
                      value: '${items.length}',
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 14),
        _SectionCard(
          title: 'Customer Details',
          icon: Icons.person_outline_rounded,
          child: Column(
            children: [
              _DetailRow(
                icon: Icons.badge_outlined,
                label: 'Customer',
                value: customerName,
              ),
              const SizedBox(height: 12),
              _DetailRow(
                icon: Icons.phone_outlined,
                label: 'Phone',
                value: customerPhone,
              ),
              const SizedBox(height: 12),
              _DetailRow(
                icon: Icons.location_on_outlined,
                label: 'Address',
                value: _formatAddress(data['deliveryAddress']),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _SectionCard(
          title: 'Items & Notes',
          icon: Icons.receipt_long_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (items.isEmpty)
                Text(
                  'No line items available for this order.',
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                )
              else
                ...items.take(8).map((item) => _buildItemRow(context, item)),
              if (items.length > 8) ...[
                const SizedBox(height: 10),
                Text(
                  '+${items.length - 8} more items',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (orderNotes.isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    orderNotes,
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        _SectionCard(
          title: 'Billing',
          icon: Icons.payments_outlined,
          child: Column(
            children: [
              _AmountRow(label: 'Subtotal', amount: subtotal),
              if (deliveryCharge > 0) ...[
                const SizedBox(height: 10),
                _AmountRow(label: 'Delivery Fee', amount: deliveryCharge),
              ],
              const SizedBox(height: 10),
              Divider(height: 1, color: colorScheme.outlineVariant),
              const SizedBox(height: 10),
              _AmountRow(
                label: 'Total',
                amount: totalAmount,
                emphasize: true,
              ),
            ],
          ),
        ),
        if (manualNote.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.orange.withValues(alpha: 0.15),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Manual Assignment Reason',
                  style: TextStyle(
                    color: Colors.orange.shade900,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  manualNote,
                  style: TextStyle(
                    color: Colors.orange.shade900,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildItemRow(BuildContext context, Map<String, dynamic> item) {
    final name = (item['name'] ?? item['title'] ?? 'Unknown Item').toString();
    final qty = item['quantity'] ?? item['qty'] ?? 1;
    final note = (item['note'] ?? '').toString();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                '$qty',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (note.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      note,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _formatAddress(dynamic addressData) {
    if (addressData == null) {
      return 'No address provided';
    }
    if (addressData is String) {
      final value = addressData.trim();
      return value.isEmpty ? 'No address provided' : value;
    }
    if (addressData is Map) {
      final parts = [
        addressData['buildingName']?.toString() ?? '',
        addressData['street']?.toString() ?? '',
        addressData['area']?.toString() ?? '',
        addressData['zone']?.toString() ?? '',
        addressData['landmark']?.toString() ?? '',
      ].where((part) => part.trim().isNotEmpty).toList();
      return parts.isEmpty ? 'No address provided' : parts.join(', ');
    }
    return addressData.toString();
  }
}

class _RiderSelectionPanel extends StatefulWidget {
  final String branchId;
  final String branchLabel;
  final String? assigningRiderId;
  final ValueChanged<String> onAssign;

  const _RiderSelectionPanel({
    required this.branchId,
    required this.branchLabel,
    required this.assigningRiderId,
    required this.onAssign,
  });

  @override
  State<_RiderSelectionPanel> createState() => _RiderSelectionPanelState();
}

class _RiderSelectionPanelState extends State<_RiderSelectionPanel> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (widget.branchId.isEmpty) {
      return _InlineStateCard(
        icon: Icons.storefront_outlined,
        title: 'Branch missing on order',
        subtitle:
            'This order has no branch assigned, so rider availability cannot be scoped correctly.',
        accentColor: Colors.orange,
      );
    }

    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('staff')
        .where('staffType', isEqualTo: 'driver')
        .where('isAvailable', isEqualTo: true)
        .where('status', isEqualTo: 'online');

    query = query.where('branchIds', arrayContains: widget.branchId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Available Riders',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Only online, available riders from ${widget.branchLabel} are shown here.',
          style: TextStyle(
            color: colorScheme.onSurfaceVariant,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          onChanged: (value) => setState(() {
            _searchQuery = value.trim().toLowerCase();
          }),
          decoration: InputDecoration(
            hintText: 'Search rider by name or phone...',
            prefixIcon: Icon(
              Icons.search_rounded,
              color: colorScheme.onSurfaceVariant,
            ),
            filled: true,
            fillColor: colorScheme.surface.withValues(alpha: 0.85),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: query.snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _InlineStateCard(
                  icon: Icons.error_outline_rounded,
                  title: 'Rider feed unavailable',
                  subtitle: '${snapshot.error}',
                  accentColor: Colors.red,
                );
              }

              if (!snapshot.hasData) {
                return Center(
                  child: CircularProgressIndicator(color: colorScheme.primary),
                );
              }

              final docs = snapshot.data!.docs.where((doc) {
                final data = doc.data();
                if (_searchQuery.isEmpty) {
                  return true;
                }
                final name = (data['name'] ?? '').toString().toLowerCase();
                final phone = (data['phone'] ?? '').toString().toLowerCase();
                return name.contains(_searchQuery) ||
                    phone.contains(_searchQuery);
              }).toList()
                ..sort((a, b) {
                  final aName = (a.data()['name'] ?? '').toString();
                  final bName = (b.data()['name'] ?? '').toString();
                  return aName.toLowerCase().compareTo(bName.toLowerCase());
                });

              if (docs.isEmpty) {
                return _InlineStateCard(
                  icon: Icons.delivery_dining_rounded,
                  title: 'No riders ready right now',
                  subtitle:
                      'There are no online and available riders for this branch under the current search.',
                  accentColor: colorScheme.primary,
                );
              }

              return ListView.separated(
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  final data = doc.data();
                  final vehicleMap =
                      (data['vehicle'] as Map?)?.cast<String, dynamic>() ??
                          <String, dynamic>{};
                  final isAssigning = widget.assigningRiderId == doc.id;
                  final name = (data['name'] ?? 'Unknown Rider').toString();
                  final phone = (data['phone'] ?? 'No phone').toString();
                  final rating =
                      (data['rating'] ?? data['riderRating'] ?? '0').toString();
                  final totalDeliveries =
                      (data['totalDeliveries'] as num?)?.toInt() ?? 0;
                  final vehicleType =
                      (vehicleMap['type'] ?? 'Vehicle').toString();
                  final vehicleNumber =
                      (vehicleMap['number'] ?? '').toString().trim();

                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colorScheme.outlineVariant),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundColor:
                                  colorScheme.primary.withValues(alpha: 0.1),
                              child: Icon(
                                Icons.person_outline_rounded,
                                color: colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: colorScheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    phone,
                                    style: TextStyle(
                                      color: colorScheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text(
                                'ONLINE',
                                style: TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _InfoPill(
                              icon: Icons.two_wheeler_rounded,
                              label: vehicleNumber.isEmpty
                                  ? vehicleType
                                  : '$vehicleType • $vehicleNumber',
                            ),
                            _InfoPill(
                              icon: Icons.star_rounded,
                              label: rating,
                            ),
                            _InfoPill(
                              icon: Icons.local_shipping_outlined,
                              label: '$totalDeliveries deliveries',
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: widget.assigningRiderId == null
                                ? () => widget.onAssign(doc.id)
                                : null,
                            icon: isAssigning
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(
                                    Icons.check_circle_outline_rounded),
                            label: Text(
                              isAssigning ? 'Assigning...' : 'Assign Rider',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colorScheme.primary,
                              foregroundColor: colorScheme.onPrimary,
                              disabledBackgroundColor:
                                  colorScheme.primary.withValues(alpha: 0.5),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: colorScheme.onSurface,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryTile({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              height: 1.35,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 72, maxWidth: 110),
          child: Text(
            label,
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value.isEmpty ? '-' : value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}

class _AmountRow extends StatelessWidget {
  final String label;
  final double amount;
  final bool emphasize;

  const _AmountRow({
    required this.label,
    required this.amount,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: emphasize
                ? colorScheme.onSurface
                : colorScheme.onSurfaceVariant,
            fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        Text(
          'QAR ${amount.toStringAsFixed(2)}',
          style: TextStyle(
            color: emphasize ? colorScheme.primary : colorScheme.onSurface,
            fontWeight: emphasize ? FontWeight.w800 : FontWeight.w700,
            fontSize: emphasize ? 16 : 14,
          ),
        ),
      ],
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoPill({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineStateCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accentColor;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _InlineStateCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, size: 30, color: accentColor),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              FilledButton.tonalIcon(
                onPressed: onAction,
                icon: const Icon(Icons.arrow_back_rounded),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _formatWaitDuration(Duration duration) {
  if (duration.inMinutes < 1) {
    return '< 1m';
  }
  if (duration.inHours < 1) {
    return '${duration.inMinutes}m waiting';
  }
  final hours = duration.inHours;
  final minutes = duration.inMinutes % 60;
  return '${hours}h ${minutes}m waiting';
}
