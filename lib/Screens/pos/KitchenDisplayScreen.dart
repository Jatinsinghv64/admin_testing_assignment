// lib/Screens/pos/KitchenDisplayScreen.dart
// Odoo-style KDS — Exact Odoo Kitchen Display replica
// Tabs: All | To Cook | Ready | Completed | Recall | Close
// Grid: 3-col responsive, color-coded cards, add-on pink border, green = fresh

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../main.dart';
import '../../constants.dart';
import '../../Widgets/BranchFilterService.dart';
import '../../Widgets/CancellationDialog.dart';
import 'components/kds_constants.dart';
import '../../services/pos/pos_service.dart';

// KDS Tab definition
enum _KdsTab { all, toCook, ready, recall }

const String _kdsRejectPendingAction = '__kds_reject_pending__';

class KitchenDisplayScreen extends StatefulWidget {
  const KitchenDisplayScreen({super.key});

  @override
  State<KitchenDisplayScreen> createState() => _KitchenDisplayScreenState();
}

class _KitchenDisplayScreenState extends State<KitchenDisplayScreen>
    with WidgetsBindingObserver {
  final AudioPlayer _audioPlayer = AudioPlayer();
  Timer? _refreshTimer;
  int _previousOrderCount = -1;
  bool _isAudioEnabled = true;
  String _dateRange = 'today';
  final Map<String, bool> _processingOrders = {};
  final Set<String> _processedOrderIds = {};
  final Set<String> _alertedOrderIds = {};

  // Active top tab
  _KdsTab _activeTab = _KdsTab.toCook;

  // ── View mode: false = grid (Odoo), true = list (kanban columns) ──
  bool _isListView = false;

  // Cached stream
  Stream<QuerySnapshot<Map<String, dynamic>>>? _ordersStream;
  String _lastCacheKey = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) {
        if (mounted) setState(() {});
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateStream();
  }

  void _updateStream() {
    final userScope = context.read<UserScopeService>();
    final branchFilter = context.read<BranchFilterService>();
    final selectedBranchId = branchFilter.selectedBranchId;
    if (selectedBranchId == null ||
        selectedBranchId == BranchFilterService.allBranchesValue) {
      _ordersStream = null;
      _lastCacheKey = '';
      _processedOrderIds.clear();
      _alertedOrderIds.clear();
      _previousOrderCount = -1;
      return;
    }

    final branchIds = branchFilter.getFilterBranchIds(userScope.branchIds);
    if (branchIds.isEmpty) {
      _ordersStream = const Stream.empty();
      _lastCacheKey = '';
      _processedOrderIds.clear();
      _alertedOrderIds.clear();
      _previousOrderCount = -1;
      return;
    }

    final cacheKey = '${branchIds.join(',')}_$_dateRange';
    if (cacheKey != _lastCacheKey) {
      _lastCacheKey = cacheKey;
      _ordersStream = _buildOrdersStream(branchIds);
      _processedOrderIds.clear();
      _alertedOrderIds.clear();
      _previousOrderCount = -1;
    }
  }

  DateTime get _dateStart {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_dateRange) {
      case 'yesterday':
        return today.subtract(const Duration(days: 1));
      case 'week':
        return today.subtract(const Duration(days: 7));
      default:
        return today;
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _buildOrdersStream(
      List<String> branchIds) {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection(AppConstants.collectionOrders)
        .where('status', whereIn: [
      AppConstants.statusPending,
      AppConstants.statusPreparing,
      AppConstants.statusPrepared,
      AppConstants.statusServed,
      AppConstants.statusCancelled,
      AppConstants.statusNeedsAssignment,
      'placed',
    ]).where('timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(_dateStart));

    if (branchIds.length == 1) {
      query = query.where('branchIds', arrayContains: branchIds.first);
    } else if (branchIds.length <= 10) {
      query = query.where('branchIds', arrayContainsAny: branchIds);
    }
    return query
        .orderBy('timestamp', descending: false)
        .snapshots();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _audioPlayer.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _playNewOrderSound() async {
    if (!_isAudioEnabled) return;
    try {
      await _audioPlayer.play(AssetSource('notification.mp3'));
    } catch (_) {}
  }

  /// Find table IDs that appear more than once (add-on scenario → pink border)
  Set<String> _findDuplicateTableIds(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final seen = <String>{};
    final dups = <String>{};
    for (final doc in docs) {
      final tableId = doc.data()['tableId']?.toString() ?? '';
      if (tableId.isNotEmpty) {
        if (!seen.add(tableId)) dups.add(tableId);
      }
    }
    return dups;
  }

  bool _shouldShowCancelledTicket(Map<String, dynamic> data) {
    if (data['isKdsDismissed'] == true) return false;
    final cancelledAt = (data['cancelledAt'] as Timestamp?)?.toDate() ??
        (data['timestamp'] as Timestamp?)?.toDate();
    if (cancelledAt == null) return true;
    return DateTime.now().difference(cancelledAt).inMinutes < 10;
  }

  void _handleSnapshotEffects(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> allDocs,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> toCookDocs,
  ) {
    final currentIds = allDocs.map((doc) => doc.id).toSet();
    _processedOrderIds.removeWhere((id) => !currentIds.contains(id));
    _alertedOrderIds.removeWhere((id) => !currentIds.contains(id));

    if (_previousOrderCount >= 0 && allDocs.length > _previousOrderCount) {
      final newIds = currentIds.difference(_processedOrderIds);
      if (newIds.isNotEmpty) {
        _playNewOrderSound();
      }
    }

    _processedOrderIds.addAll(currentIds);
    _previousOrderCount = allDocs.length;
    _checkDelayedAlerts(toCookDocs);
  }

  @override
  Widget build(BuildContext context) {
    final branchFilter = context.watch<BranchFilterService>();
    final globalBranchId = branchFilter.selectedBranchId;

    if (globalBranchId == null ||
        globalBranchId == BranchFilterService.allBranchesValue) {
      return Scaffold(
        backgroundColor: Colors.grey[100],
        body: Center(
          child: Container(
            width: 480,
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child:
                      const Icon(Icons.kitchen, size: 56, color: Colors.orange),
                ),
                const SizedBox(height: 32),
                const Text(
                  'Branch Selection Required',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Text(
                  'Kitchen Display operations must be tied to a specific location to display correct orders.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.grey[600], fontSize: 16, height: 1.4),
                ),
                const SizedBox(height: 32),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(16),
                    border:
                        Border.all(color: Colors.deepPurple.withValues(alpha: 0.15)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.arrow_upward,
                          color: Colors.deepPurple[700], size: 28),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          'Please select a specific branch from the dropdown in the top App Bar.',
                          style: TextStyle(
                              color: Colors.deepPurple[800],
                              fontWeight: FontWeight.w600,
                              fontSize: 15),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF888888), // Odoo medium grey background
      body: _ordersStream == null
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _ordersStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _buildStreamError(snapshot.error);
                }
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  );
                }

                final allDocs = snapshot.data?.docs ?? [];

                // Bucket orders
                final toCookDocs = allDocs.where((d) {
                  final data = d.data();
                  final os = PosService.getOrderStatus(data);
                  if (os == AppConstants.statusCancelled) {
                    return _shouldShowCancelledTicket(data);
                  }
                  if (os == AppConstants.statusPending ||
                      os == AppConstants.statusPreparing ||
                      data['status'] == AppConstants.statusPending ||
                      data['status'] == AppConstants.statusNeedsAssignment) {
                    return true;
                  }
                  return false;
                }).toList();

                final readyDocs = allDocs
                    .where((d) =>
                        PosService.getOrderStatus(d.data()) ==
                        AppConstants.statusPrepared)
                    .toList();

                final servedDocs = allDocs
                    .where((d) =>
                        PosService.getOrderStatus(d.data()) ==
                        AppConstants.statusServed)
                    .toList();

                final duplicateTableIds = _findDuplicateTableIds(allDocs);
                _handleSnapshotEffects(allDocs, toCookDocs);

                // Which docs to show
                List<QueryDocumentSnapshot<Map<String, dynamic>>> visibleDocs;
                switch (_activeTab) {
                  case _KdsTab.toCook:
                    visibleDocs = toCookDocs;
                    break;
                  case _KdsTab.ready:
                    visibleDocs = readyDocs;
                    break;
                  case _KdsTab.recall:
                    visibleDocs = servedDocs;
                    break;
                  case _KdsTab.all:
                    visibleDocs = allDocs.where((d) {
                      final data = d.data();
                      final os = PosService.getOrderStatus(data);

                      if (os == 'served') return false;
                      if (os == 'cancelled') {
                        return _shouldShowCancelledTicket(data);
                      }
                      return os != 'completed';
                    }).toList();
                    break;
                }

                // Sort: oldest first (most urgent → top-left)
                visibleDocs.sort((a, b) {
                  final ta = (a.data()['timestamp'] as Timestamp?)?.toDate() ??
                      DateTime.now();
                  final tb = (b.data()['timestamp'] as Timestamp?)?.toDate() ??
                      DateTime.now();
                  return ta.compareTo(tb);
                });

                return Column(
                  children: [
                    _buildHeader(
                      toCookCount: toCookDocs.length,
                      readyCount: readyDocs.length,
                      totalCount: allDocs.length,
                    ),
                    Expanded(
                      child: _activeTab == _KdsTab.recall
                          ? _buildRecallGrid(servedDocs)
                          : _isListView
                              ? _buildListView(
                                  visibleDocs,
                                  _activeTab,
                                  duplicateTableIds,
                                )
                              : _buildMainGrid(
                                  visibleDocs,
                                  duplicateTableIds,
                                ),
                    ),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildStreamError(Object? error) {
    return Center(
      child: Container(
        width: 420,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded,
                size: 52, color: Colors.redAccent),
            const SizedBox(height: 16),
            const Text(
              'Kitchen Display Lost Sync',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(
              PosService.displayError(error),
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[700], height: 1.4),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => setState(_updateStream),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry Stream'),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // ODOO-STYLE HEADER BAR
  // ═══════════════════════════════════════════════════════════════
  Widget _buildHeader({
    required int toCookCount,
    required int readyCount,
    required int totalCount,
  }) {
    return Container(
      height: 52,
      color: Colors.white,
      child: Row(
        children: [
          const SizedBox(width: 12),
          // ── KDS icon / title ──────────────────────────
          const Icon(Icons.restaurant, size: 20, color: Color(0xFF888888)),
          const SizedBox(width: 8),
          // ── Tabs ──────────────────────────────────────
          _buildTab(
              label: 'All',
              tab: _KdsTab.all,
              count: totalCount,
              countColor: null),
          _buildTab(
              label: 'To Cook',
              tab: _KdsTab.toCook,
              count: toCookCount,
              countColor: const Color(0xFF888888)),
          _buildTab(
              label: 'Ready',
              tab: _KdsTab.ready,
              count: readyCount,
              countColor: const Color(0xFF0099CC)),
          const Spacer(),
          // ── Recall button ─────────────────────────────
          _buildRecallButton(),
          // ── List / Grid view toggle ───────────────────
          Tooltip(
            message:
                _isListView ? 'Switch to Grid View' : 'Switch to List View',
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => setState(() => _isListView = !_isListView),
              child: Container(
                height: 32,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F0F0),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFDDDDDD)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                        _isListView
                            ? Icons.grid_view_rounded
                            : Icons.view_column_rounded,
                        size: 16,
                        color: const Color(0xFF555555)),
                    const SizedBox(width: 5),
                    Text(_isListView ? 'Grid' : 'List',
                        style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF555555),
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ),
          // ── Date filter ───────────────────────────────
          _buildDateDropdown(),
          // ── Sound toggle ──────────────────────────────
          IconButton(
            icon: Icon(
              _isAudioEnabled ? Icons.volume_up : Icons.volume_off,
              size: 18,
              color: _isAudioEnabled
                  ? const Color(0xFF0099CC)
                  : const Color(0xFF888888),
            ),
            onPressed: () => setState(() => _isAudioEnabled = !_isAudioEnabled),
            tooltip: 'Sound',
          ),
          // ── Close/back button ─────────────────────────
          _buildCloseButton(),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _buildTab({
    required String label,
    required _KdsTab tab,
    required int count,
    required Color? countColor,
  }) {
    final isActive = _activeTab == tab;
    return GestureDetector(
      onTap: () => setState(() => _activeTab = tab),
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFFE8E8E8) : Colors.white,
          border: Border(
            bottom: BorderSide(
              color: isActive ? const Color(0xFF555555) : Colors.transparent,
              width: 2.5,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive
                    ? const Color(0xFF222222)
                    : const Color(0xFF666666),
              ),
            ),
            if (countColor != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: countColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  count.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRecallButton() {
    final isActive = _activeTab == _KdsTab.recall;
    return GestureDetector(
      onTap: () => setState(() => _activeTab = _KdsTab.recall),
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFFE8E8E8) : Colors.white,
          border: Border(
            bottom: BorderSide(
              color: isActive ? const Color(0xFF555555) : Colors.transparent,
              width: 2.5,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.history, size: 18, color: Color(0xFF666666)),
            const SizedBox(width: 6),
            Text(
              'Recall',
              style: TextStyle(
                fontSize: 14,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive
                    ? const Color(0xFF222222)
                    : const Color(0xFF666666),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateDropdown() {
    return Container(
      height: 32,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFDDDDDD)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _dateRange,
          isDense: true,
          style: const TextStyle(fontSize: 12, color: Color(0xFF555555)),
          dropdownColor: Colors.white,
          icon: const Icon(Icons.keyboard_arrow_down,
              size: 16, color: Color(0xFF888888)),
          items: const [
            DropdownMenuItem(value: 'today', child: Text('Today')),
            DropdownMenuItem(value: 'yesterday', child: Text('Yesterday')),
            DropdownMenuItem(value: 'week', child: Text('Last 7 Days')),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() => _dateRange = v);
            _updateStream();
          },
        ),
      ),
    );
  }

  Widget _buildCloseButton() {
    return Tooltip(
      message: 'Close KDS',
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => Navigator.of(context).maybePop(),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFFDDDDDD)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Close',
                  style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF555555),
                      fontWeight: FontWeight.w500)),
              SizedBox(width: 6),
              Icon(Icons.logout, size: 16, color: Color(0xFF555555)),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // MAIN GRID
  // ═══════════════════════════════════════════════════════════════
  Widget _buildMainGrid(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    Set<String> duplicateTableIds,
  ) {
    if (docs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.restaurant_menu, size: 64, color: Colors.white54),
            const SizedBox(height: 16),
            Text(
              _activeTab == _KdsTab.all
                  ? 'No active orders'
                  : 'Nothing to show',
              style: const TextStyle(
                  fontSize: 18,
                  color: Colors.white70,
                  fontWeight: FontWeight.w500),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        int crossAxisCount = 3;
        if (constraints.maxWidth > 1400) {
          crossAxisCount = 4;
        } else if (constraints.maxWidth < 700) {
          crossAxisCount = 2;
        }

        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.0, // Force square KDS tickets
          ),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final tableId = doc.data()['tableId']?.toString() ?? '';
            final isDuplicate =
                tableId.isNotEmpty && duplicateTableIds.contains(tableId);
            return OdooKdsCard(
              key: ValueKey(doc.id),
              orderDoc: doc,
              isDuplicate: isDuplicate,
              isProcessing: _processingOrders[doc.id] ?? false,
              onStatusUpdate: (newStatus) =>
                  _updateOrderStatus(doc.id, newStatus, orderData: doc.data()),
              onTap: () => _showDetailDialog(doc),
            );
          },
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // LIST VIEW — 3-column kanban (New Orders / Preparing / Ready)
  // ═══════════════════════════════════════════════════════════════
  Widget _buildListView(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    _KdsTab activeTab,
    Set<String> duplicateTableIds,
  ) {
    final newOrders = docs.where((d) {
      final data = d.data();
      final os = PosService.getOrderStatus(data);
      final isDismissed = data['isKdsDismissed'] == true;

      if (os == AppConstants.statusCancelled) return !isDismissed;

      if (os == AppConstants.statusPending ||
          data['status'] == AppConstants.statusNeedsAssignment ||
          data['status'] == AppConstants.statusPending) {
        return true;
      }

      return false;
    }).toList();

    final preparing = docs.where((d) {
      final data = d.data();
      final os = PosService.getOrderStatus(data);
      return os == AppConstants.statusPreparing;
    }).toList();

    final ready = docs
        .where((d) =>
            PosService.getOrderStatus(d.data()) == AppConstants.statusPrepared)
        .toList();
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // If "Ready" tab is active, only show the Ready column
          if (activeTab == _KdsTab.all || activeTab == _KdsTab.toCook) ...[
            _listColumn('New Orders', newOrders, const Color(0xFF2196F3),
                Icons.pending_actions, duplicateTableIds),
            const SizedBox(width: 12),
            _listColumn('Preparing', preparing, const Color(0xFFF57C00),
                Icons.local_fire_department, duplicateTableIds),
          ],
          if (activeTab == _KdsTab.all) const SizedBox(width: 12),
          if (activeTab == _KdsTab.all || activeTab == _KdsTab.ready)
            _listColumn('Ready to Serve', ready, const Color(0xFF4CAF50),
                Icons.check_circle_outline, duplicateTableIds),
        ],
      ),
    );
  }

  Widget _listColumn(
    String title,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    Color color,
    IconData icon,
    Set<String> duplicateTableIds,
  ) {
    return Expanded(
      child: Column(
        children: [
          // Column header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFDDDDDD)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 8),
                Text(title,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: color)),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: color, borderRadius: BorderRadius.circular(12)),
                  child: Text(docs.length.toString(),
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Orders
          Expanded(
            child: docs.isEmpty
                ? Center(child: Icon(icon, size: 48, color: Colors.white24))
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 20),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      final tableId = doc.data()['tableId']?.toString() ?? '';
                      final isDup = tableId.isNotEmpty &&
                          duplicateTableIds.contains(tableId);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: OdooKdsCard(
                          key: ValueKey('list_${doc.id}'),
                          orderDoc: doc,
                          isDuplicate: isDup,
                          isProcessing: _processingOrders[doc.id] ?? false,
                          isGrid:
                              false, // Fix RenderFlex: let the card shrink-wrap its items
                          onStatusUpdate: (s) => _updateOrderStatus(doc.id, s,
                              orderData: doc.data()),
                          onTap: () => _showDetailDialog(doc),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // RECALL GRID (read-only)
  // ═══════════════════════════════════════════════════════════════
  Widget _buildRecallGrid(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    if (docs.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 64, color: Colors.white54),
            SizedBox(height: 16),
            Text('No completed orders to recall',
                style: TextStyle(fontSize: 18, color: Colors.white70)),
          ],
        ),
      );
    }

    return Column(
      children: [
        Container(
          color: Colors.white.withValues(alpha: 0.1),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.info_outline, size: 16, color: Colors.white70),
              const SizedBox(width: 8),
              Text(
                  '${docs.length} served order${docs.length == 1 ? '' : 's'} — tap RECALL TO COOK to send back',
                  style: const TextStyle(fontSize: 13, color: Colors.white70)),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(builder: (context, constraints) {
            int cols = 3;
            if (constraints.maxWidth < 700) cols = 2;
            return GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1.0, // Square tickets
              ),
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final doc = docs[index];
                return OdooKdsCard(
                  key: ValueKey('recall_${doc.id}'),
                  orderDoc: doc,
                  isDuplicate: false,
                  isProcessing: _processingOrders[doc.id] ?? false,
                  onStatusUpdate: (newStatus) => _updateOrderStatus(
                      doc.id, newStatus,
                      orderData: doc.data()),
                  onTap: () => _showDetailDialog(doc),
                  isRecall: true,
                );
              },
            );
          }),
        ),
      ],
    );
  }

  void _showDetailDialog(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 450, maxHeight: 600),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Color(0xFF888888)),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                  child: OdooKdsCard(
                    key: ValueKey('detail_${doc.id}'),
                    orderDoc: doc,
                    isDuplicate: false,
                    isProcessing: _processingOrders[doc.id] ?? false,
                    onStatusUpdate: (newStatus) {
                      _updateOrderStatus(doc.id, newStatus,
                          orderData: doc.data());
                      Navigator.of(ctx).pop();
                    },
                    onTap: () {},
                    isGrid: false,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _checkDelayedAlerts(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    for (final doc in docs) {
      final ts = doc.data()['timestamp'] as Timestamp?;
      if (ts == null) continue;
      final elapsed = DateTime.now().difference(ts.toDate()).inMinutes;
      if (elapsed >= KDSConfig.delayedAlertMinutes &&
          !_alertedOrderIds.contains(doc.id)) {
        _alertedOrderIds.add(doc.id);
        _playNewOrderSound();
        break;
      }
    }
  }

  Future<String?> _promptKitchenCancellationReason() {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => const CancellationReasonDialog(
        title: 'Cancel Order?',
        confirmText: 'Cancel Order',
        cancelText: 'Keep Order',
        reasons: CancellationReasons.orderReasons,
      ),
    );
  }

  Future<void> _updateOrderStatus(
    String orderId,
    String newStatus, {
    Map<String, dynamic>? orderData,
  }) async {
    if (_processingOrders[orderId] == true) return;
    setState(() => _processingOrders[orderId] = true);
    try {
      final posService = context.read<PosService>();
      final userScope = context.read<UserScopeService>();
      String successMessage;
      if (newStatus == 'dismiss_cancelled') {
        await FirebaseFirestore.instance
            .collection(AppConstants.collectionOrders)
            .doc(orderId)
            .update({'isKdsDismissed': true});
        successMessage = 'Cancelled ticket dismissed';
      } else {
        final data = orderData != null
            ? Map<String, dynamic>.from(orderData)
            : (await FirebaseFirestore.instance
                        .collection(AppConstants.collectionOrders)
                        .doc(orderId)
                        .get())
                    .data() ??
                <String, dynamic>{};
        if (data.isEmpty) {
          throw Exception('Order not found');
        }
        final currentOS = PosService.getOrderStatus(data);

        if (newStatus == _kdsRejectPendingAction) {
          final reason = await _promptKitchenCancellationReason();
          if (!mounted) return;
          if (reason == null || reason.trim().isEmpty) return;
          final branchIds = (data['branchIds'] as List<dynamic>? ?? [])
              .map((id) => id.toString())
              .toList();
          await posService.rejectKitchenPendingOrder(
            orderId: orderId,
            reason: reason,
            userScope: userScope,
            tableId: data['tableId']?.toString(),
            branchIds: branchIds,
          );
          successMessage = 'Order cancelled';
        } else if (newStatus == AppConstants.statusPreparing &&
            PosService.requiresKitchenDecision(data)) {
          await posService.acceptKitchenPendingOrder(
            orderId: orderId,
            userScope: userScope,
          );
          successMessage = 'Order -> PREPARING';
        } else if ((newStatus == AppConstants.statusPreparing ||
                newStatus == AppConstants.statusPending) &&
            (currentOS == AppConstants.statusPrepared ||
                currentOS == AppConstants.statusServed)) {
          await posService.recallOrder(orderId, 'Recalled from KDS');
          successMessage = 'Order recalled to kitchen';
        } else {
          await posService.updateOrderStatus(
            orderId,
            newStatus,
            currentData: data,
          );
          successMessage = 'Order -> ${newStatus.toUpperCase()}';
        }
      }

      debugPrint('KDS: Updated $orderId -> $newStatus');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(successMessage),
          backgroundColor: newStatus == _kdsRejectPendingAction
              ? Colors.red.shade700
              : Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 1),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(PosService.displayError(e)),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _processingOrders.remove(orderId));
    }
  }
}

// ═══════════════════════════════════════════════════════════════
// ODOO KDS CARD — exact replica of the Odoo Kitchen Display card
// ═══════════════════════════════════════════════════════════════
enum _KdsCardStatus { toCook, ready, completed, cancelled }

class OdooKdsCard extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> orderDoc;
  final bool isDuplicate; // Pink border for same-table add-on
  final bool isProcessing;
  final bool isRecall;
  final bool isGrid;
  final ValueChanged<String> onStatusUpdate;
  final VoidCallback onTap;

  const OdooKdsCard({
    super.key,
    required this.orderDoc,
    required this.isDuplicate,
    required this.isProcessing,
    required this.onStatusUpdate,
    required this.onTap,
    this.isRecall = false,
    this.isGrid = true,
  });

  @override
  State<OdooKdsCard> createState() => _OdooKdsCardState();
}

class _OdooKdsCardState extends State<OdooKdsCard> {
  late Map<String, dynamic> _data;
  final Set<int> _bumpedItems = {};
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _data = widget.orderDoc.data();
    _loadBumpedItems();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(OdooKdsCard old) {
    super.didUpdateWidget(old);
    _data = widget.orderDoc.data();
    if (widget.orderDoc.id != old.orderDoc.id) _loadBumpedItems();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _loadBumpedItems() {
    _bumpedItems.clear();
    final completed = _data['completedItems'] as List<dynamic>? ?? [];
    for (final idx in completed) {
      if (idx is int) _bumpedItems.add(idx);
    }
  }

  Future<void> _bumpItem(int index) async {
    final bool wasBumped = _bumpedItems.contains(index);

    // Optimistic UI update
    setState(() {
      wasBumped ? _bumpedItems.remove(index) : _bumpedItems.add(index);
    });

    try {
      // Industry Grade: Atomic array operations
      await widget.orderDoc.reference.update({
        'completedItems': wasBumped
            ? FieldValue.arrayRemove([index])
            : FieldValue.arrayUnion([index])
      });
    } catch (e) {
      // Revert on failure
      if (mounted) {
        setState(() {
          _loadBumpedItems();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final rawStatus = _data['status']?.toString() ?? 'pending';
    final stage = PosService.getOrderStatus(_data);
    final items = (_data['items'] ?? []) as List<dynamic>;
    final cancelledItems = (_data['cancelledItems'] ?? []) as List<dynamic>;
    final timestamp = _data['timestamp'] as Timestamp?;
    final servedAt = _data['servedAt'] as Timestamp?;

    int elapsed;
    if (widget.isRecall && servedAt != null) {
      elapsed = DateTime.now().difference(servedAt.toDate()).inMinutes;
    } else {
      elapsed = timestamp != null
          ? DateTime.now().difference(timestamp.toDate()).inMinutes
          : 0;
    }

    // Order metadata
    final orderNum = OrderNumberHelper.getDisplayNumber(
      _data,
      orderId: widget.orderDoc.id,
    );
    final orderNumLabel =
        orderNum == OrderNumberHelper.loadingText || orderNum.startsWith('#')
            ? orderNum
            : '#$orderNum';
    final tableName = _data['tableName']?.toString() ?? '';
    final tablePrefix = tableName.isNotEmpty ? tableName : 'Order';
    // Display name: prefer displayName > name split, never show email
    final rawCreatedBy =
        _data['createdBy']?.toString() ?? _data['staffName']?.toString() ?? '';
    final createdBy = _cleanName(rawCreatedBy);
    final guestCount =
        (_data['guestCount'] as int?) ?? (_data['numberOfGuests'] as int?) ?? 1;
    // Order type + source
    final orderType =
        (_data['Order_type'] ?? _data['orderType'] ?? '').toString();
    final source = _data['source']?.toString();
    final hasActiveAddOns = _data['hasActiveAddOns'] == true;
    final addOnRound = (_data['addOnRound'] as int?) ?? 0;
    final previousItemCount =
        (_data['previousItemCount'] as int?) ?? items.length;

    // Card visual state
    final isCancelled = stage == AppConstants.statusCancelled;
    final cardStatus = _cardStatus(stage);
    final awaitingChefDecision = PosService.requiresKitchenDecision(_data);
    final decisionSecondsRemaining =
        PosService.getKitchenDecisionSecondsRemaining(_data);

    final isNew = cardStatus == _KdsCardStatus.toCook &&
        (stage == AppConstants.statusPending ||
            rawStatus == AppConstants.statusNeedsAssignment ||
            rawStatus == 'placed' ||
            rawStatus == 'ready');

    final isFresh = elapsed < 5 &&
        !hasActiveAddOns &&
        !widget.isDuplicate &&
        !isCancelled &&
        !isNew;

    // Border color
    final Color borderColor;
    final double borderWidth;
    if (isCancelled) {
      borderColor = Colors.red;
      borderWidth = 3.0;
    } else if (isNew) {
      borderColor = const Color(0xFF2196F3); // Blue — New order
      borderWidth = 2.5; // Slightly thicker to stand out
    } else if (widget.isDuplicate || hasActiveAddOns) {
      borderColor = const Color(0xFFE91E8C); // Magenta/Pink — add-on
      borderWidth = 2.5;
    } else {
      borderColor = const Color(0xFFDDDDDD);
      borderWidth = 1;
    }

    // Header BG color
    final Color headerBg;
    if (isCancelled) {
      headerBg = Colors.red.shade50;
    } else if (isNew) {
      headerBg = const Color(0xFFE3F2FD); // Light blue tint for new
    } else if (widget.isDuplicate || hasActiveAddOns) {
      headerBg = const Color(0xFFFCE4F0); // light pink tint
    } else if (isFresh) {
      headerBg = const Color(0xFFE6F4EA); // light green tint
    } else {
      headerBg = const Color(0xFFF8F8F8);
    }

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor, width: borderWidth),
          boxShadow: const [
            BoxShadow(
                color: Color(0x18000000), blurRadius: 4, offset: Offset(0, 2))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ─── CARD HEADER (row 1): Table · Staff · Guests ─────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: headerBg,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(7),
                  topRight: Radius.circular(7),
                ),
                border: Border(
                    bottom: BorderSide(
                        color: borderColor.withValues(alpha: 0.4), width: 0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Row 1: Table + order number + source badge + guest count
                  Row(
                    children: [
                      // Table + order number (bold)
                      Expanded(
                        child: Text(
                          isCancelled
                              ? '$tablePrefix ($orderNumLabel) CANCELLED'
                              : '$tablePrefix ($orderNumLabel)',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: isCancelled
                                ? Colors.red
                                : (isNew
                                    ? const Color(0xFF1976D2)
                                    : const Color(0xFF222222)),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // NEW Order Badge
                      if (isNew)
                        Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2196F3).withValues(alpha: 0.15),
                            border: Border.all(
                                color: const Color(0xFF2196F3), width: 1.5),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'NEW ORDER',
                            style: TextStyle(
                              color: Color(0xFF1976D2),
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      // Source badge (Talabat / Keta / POS / etc)
                      if (source != null && source.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(left: 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: KDSConfig.getSourceColor(source)
                                .withValues(alpha: 0.12),
                            border: Border.all(
                                color: KDSConfig.getSourceColor(source),
                                width: 1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            KDSConfig.getSourceLabel(source),
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: KDSConfig.getSourceColor(source),
                            ),
                          ),
                        ),
                      const SizedBox(width: 6),
                      // Guest count
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.group_outlined,
                              size: 14, color: Color(0xFF888888)),
                          const SizedBox(width: 2),
                          Text('$guestCount',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF666666),
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  // Row 2: Staff name + order type
                  Row(
                    children: [
                      const Icon(Icons.person_outline,
                          size: 12, color: Color(0xFF999999)),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          createdBy,
                          style: const TextStyle(
                              fontSize: 11, color: Color(0xFF777777)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (orderType.isNotEmpty)
                        Text(
                          _orderTypeLabel(orderType),
                          style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFF999999),
                              fontWeight: FontWeight.w500),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            // ─── SUB-HEADER (row 2): Status badge + Timer ────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  // Status badge + add-on badge
                  _buildStatusBadge(cardStatus),
                  if (awaitingChefDecision) ...[
                    const SizedBox(width: 6),
                    _buildChefDecisionBadge(decisionSecondsRemaining),
                  ],
                  if (hasActiveAddOns && addOnRound > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE91E8C).withValues(alpha: 0.12),
                        border: Border.all(color: const Color(0xFFE91E8C)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '+R$addOnRound',
                        style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFFE91E8C),
                            fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                  const Spacer(),
                  _buildTimerBadge(elapsed),
                ],
              ),
            ),

            // ─── DIVIDER ─────────────────────────────────────────────
            const Divider(height: 1, thickness: 1, color: Color(0xFFEEEEEE)),

            // ─── ITEMS LIST ──────────────────────────────────────────
            if (widget.isGrid)
              Expanded(
                child: _buildItemsList(items, cancelledItems, hasActiveAddOns,
                    previousItemCount, stage),
              )
            else
              _buildItemsList(items, cancelledItems, hasActiveAddOns,
                  previousItemCount, stage),

            // ─── ACTION BUTTON ───────────────────────────────────────
            GestureDetector(
              onTap: () {}, // Prevent tap from reaching card's detail tap
              child: _buildActionButton(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemsList(List<dynamic> items, List<dynamic> cancelledItems,
      bool hasActiveAddOns, int previousItemCount, String status) {
    final isCancelled = status == AppConstants.statusCancelled;
    final isOrderServed = status == AppConstants.statusServed ||
        status == AppConstants.statusPrepared;

    // Combine active and cancelled items for display
    final allItems = [...items, ...cancelledItems];

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shrinkWrap: !widget.isGrid,
      physics: widget.isGrid ? null : const NeverScrollableScrollPhysics(),
      itemCount: allItems.length,
      itemBuilder: (context, idx) {
        final item = allItems[idx] as Map<String, dynamic>;
        final name = item['name']?.toString() ?? 'Item';
        final qty = (item['quantity'] ?? 1).toString();
        final bool isItemCancelled = item['isCancelled'] == true;

        final isBumped = _bumpedItems.contains(idx);
        final isCurrentAddOn =
            !isItemCancelled && hasActiveAddOns && idx >= previousItemCount;
        final isOldItem =
            !isItemCancelled && hasActiveAddOns && idx < previousItemCount;
        final isCut = isBumped || isOrderServed || isItemCancelled;
        final canBumpItem = !isItemCancelled && !isCancelled && !isOrderServed;

        return GestureDetector(
          onTap: canBumpItem ? () => _bumpItem(idx) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Qty — bigger, bolder
                SizedBox(
                  width: 32,
                  child: Text(
                    '${qty}x',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isCut
                          ? const Color(0xFFBBBBBB)
                          : const Color(0xFF444444),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isItemCancelled ? '$name (CANCELLED)' : name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: isCurrentAddOn
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: (isCancelled || isItemCancelled)
                              ? Colors.red.shade400
                              : isCut
                                  ? const Color(0xFFBBBBBB)
                                  : isCurrentAddOn
                                      ? const Color(0xFFE91E8C)
                                      : const Color(0xFF333333),
                          decoration: (isCut || isCancelled || isItemCancelled)
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      // ── Kitchen Notes ──
                      if (item['notes'] != null &&
                          item['notes'].toString().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            '⚠ ${item['notes']}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFFFF8F00),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      // ── Add-ons Display ──
                      if (item['addons'] != null &&
                          (item['addons'] as List).isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4, left: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: (item['addons'] as List).map((addon) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 3,
                                      height: 3,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF666666),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        addon['name']?.toString() ?? '',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF555555),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                    ],
                  ),
                ),
                // Bumped checkmark
                if (isBumped) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.check_circle,
                      size: 16, color: Color(0xFF4CAF50)),
                ],
                // NEW badge for add-on items
                if (isCurrentAddOn && !isBumped)
                  Container(
                    margin: const EdgeInsets.only(left: 4, top: 2),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE91E8C).withValues(alpha: 0.1),
                      border: Border.all(color: const Color(0xFFE91E8C)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('NEW',
                        style: TextStyle(
                            fontSize: 9,
                            color: Color(0xFFE91E8C),
                            fontWeight: FontWeight.w800)),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusBadge(_KdsCardStatus cs) {
    String label;
    Color bg;
    switch (cs) {
      case _KdsCardStatus.toCook:
        label = 'To cook';
        bg = const Color(0xFFE0E0E0);
        break;
      case _KdsCardStatus.ready:
        label = 'Ready';
        bg = const Color(0xFFBBDEFB);
        break;
      case _KdsCardStatus.completed:
        label = 'Served';
        bg = const Color(0xFFC8E6C9);
        break;
      case _KdsCardStatus.cancelled:
        label = 'CANCELLED';
        bg = Colors.red.shade200;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(label,
          style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF444444),
              fontWeight: FontWeight.w500)),
    );
  }

  Widget _buildTimerBadge(int elapsed) {
    if (elapsed >= 10) {
      // Red urgent pill
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
            color: Colors.red, borderRadius: BorderRadius.circular(12)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.schedule, size: 12, color: Colors.white),
            const SizedBox(width: 4),
            Text("$elapsed'",
                style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      );
    } else {
      // Normal clock icon + text
      final Color iconColor =
          elapsed >= 5 ? const Color(0xFFF57C00) : const Color(0xFF888888);
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule, size: 14, color: iconColor),
          const SizedBox(width: 4),
          Text(
            "$elapsed'",
            style: TextStyle(
                fontSize: 13, color: iconColor, fontWeight: FontWeight.w500),
          ),
        ],
      );
    }
  }

  Widget _buildChefDecisionBadge(int? secondsRemaining) {
    final label = secondsRemaining == null
        ? 'AWAITING CHEF'
        : 'AUTO IN ${secondsRemaining.clamp(0, 999)}s';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF2196F3).withValues(alpha: 0.12),
        border: Border.all(color: const Color(0xFF2196F3)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          color: Color(0xFF1976D2),
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildActionButton() {
    if (!widget.isRecall && PosService.requiresKitchenDecision(_data)) {
      return _buildPendingDecisionActions();
    }

    final action = PosService.getKdsPrimaryAction(
      _data,
      isRecall: widget.isRecall,
    );
    if (action == null) {
      return const SizedBox.shrink();
    }

    final actionState = action['state'] ?? 'primary';
    final isDisabled = actionState == 'disabled';
    Color color;
    switch (actionState) {
      case 'danger':
        color = Colors.red.shade700;
        break;
      case 'warning':
        color = const Color(0xFFF57C00);
        break;
      case 'success':
        color = const Color(0xFF28A745);
        break;
      case 'disabled':
        color = const Color(0xFF9E9E9E);
        break;
      default:
        color = const Color(0xFF0099CC);
        break;
    }

    return _actionBtn(
      action['label'] ?? '',
      color,
      action['nextStatus'] ?? '',
      enabled: !isDisabled,
    );
  }

  Widget _buildPendingDecisionActions() {
    return Container(
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(7),
          bottomRight: Radius.circular(7),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _decisionBtn(
              label: 'Reject',
              icon: Icons.close_rounded,
              color: Colors.red.shade700,
              action: _kdsRejectPendingAction,
            ),
          ),
          Expanded(
            child: _decisionBtn(
              label: 'Accept',
              icon: Icons.check_rounded,
              color: const Color(0xFF2E7D32),
              action: AppConstants.statusPreparing,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBtn(
    String label,
    Color color,
    String nextStatus, {
    bool enabled = true,
  }) {
    return Material(
      color: color,
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(7),
        bottomRight: Radius.circular(7),
      ),
      child: InkWell(
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(7),
          bottomRight: Radius.circular(7),
        ),
        onTap: (!enabled || widget.isProcessing)
            ? null
            : () => widget.onStatusUpdate(nextStatus),
        child: Container(
          width: double.infinity,
          height: 38,
          alignment: Alignment.center,
          child: widget.isProcessing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      letterSpacing: 0.5)),
        ),
      ),
    );
  }

  Widget _decisionBtn({
    required String label,
    required IconData icon,
    required Color color,
    required String action,
  }) {
    return Material(
      color: color,
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(7),
        bottomRight: Radius.circular(7),
      ),
      child: InkWell(
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(7),
          bottomRight: Radius.circular(7),
        ),
        onTap: widget.isProcessing ? null : () => widget.onStatusUpdate(action),
        child: SizedBox(
          height: 42,
          child: Center(
            child: widget.isProcessing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, size: 18, color: Colors.white),
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  _KdsCardStatus _cardStatus(String stage) {
    if (stage == 'cancelled') return _KdsCardStatus.cancelled;
    if (stage == AppConstants.statusServed || stage == 'completed') {
      return _KdsCardStatus.completed;
    }
    if (stage == AppConstants.statusPrepared) return _KdsCardStatus.ready;
    return _KdsCardStatus.toCook;
  }

  /// Clean staff name — strips email addresses, shortens to first name + last initial
  String _cleanName(String raw) {
    if (raw.isEmpty) return 'Staff';
    // If it's an email, extract the part before @
    if (raw.contains('@')) {
      raw = raw.split('@').first.replaceAll(RegExp(r'[._]'), ' ').trim();
    }
    // H7 FIX: Correct regex — was double-escaped, matching literal backslash-s instead of whitespace
    final parts =
        raw.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'Staff';
    final first =
        parts[0][0].toUpperCase() + parts[0].substring(1).toLowerCase();
    if (parts.length >= 2) {
      return '$first ${parts[1][0].toUpperCase()}.';
    }
    return first.length > 16 ? '${first.substring(0, 14)}…' : first;
  }

  /// Human-readable label for order type
  String _orderTypeLabel(String raw) {
    switch (raw.toLowerCase().trim()) {
      case 'dine_in':
      case 'dinein':
      case 'dine in':
        return 'Dine-In';
      case 'takeaway':
      case 'take_away':
      case 'take away':
        return 'Takeaway';
      case 'delivery':
        return 'Delivery';
      case 'talabat':
        return 'Talabat';
      case 'keta':
        return 'Keta';
      case 'snoonu':
        return 'Snoonu';
      default:
        if (raw.isEmpty) return '';
        return raw[0].toUpperCase() + raw.substring(1).toLowerCase();
    }
  }
}
