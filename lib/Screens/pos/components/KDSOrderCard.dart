// lib/Screens/pos/components/KDSOrderCard.dart
// Odoo-style KDS order card — functional, PC-optimized

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../../constants.dart';
import '../../../services/pos/pos_service.dart';
import 'kds_constants.dart';

class KDSOrderCard extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> orderDoc;
  final bool isRecall;
  final bool isDark;
  final bool isProcessing;
  final ValueChanged<String> onStatusUpdate;
  final bool showBranchName;

  const KDSOrderCard({
    super.key,
    required this.orderDoc,
    this.isRecall = false,
    this.isDark = true,
    this.isProcessing = false,
    required this.onStatusUpdate,
    this.showBranchName = false,
  });

  @override
  State<KDSOrderCard> createState() => _KDSOrderCardState();
}

class _KDSOrderCardState extends State<KDSOrderCard> {
  final Set<int> _crossedItems = {};
  late Map<String, dynamic> _data;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _data = widget.orderDoc.data();
    _loadCompletedItems();
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(KDSOrderCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Always update data to catch Firestore real-time changes
    _data = widget.orderDoc.data();
    
    // Only reset crossed items state if we are tracking a completely different order
    if (widget.orderDoc.id != oldWidget.orderDoc.id) {
      _loadCompletedItems();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _loadCompletedItems() {
    _crossedItems.clear();
    final completedItems = _data['completedItems'] as List<dynamic>? ?? [];
    for (final idx in completedItems) {
      if (idx is int) _crossedItems.add(idx);
    }
  }

  Future<void> _toggleItemCrossed(int index) async {
    setState(() {
      _crossedItems.contains(index)
          ? _crossedItems.remove(index)
          : _crossedItems.add(index);
    });
    try {
      await widget.orderDoc.reference.update({
        'completedItems': _crossedItems.toList(),
      });
    } catch (e) {
      debugPrint('Error saving crossed items: $e');
      _loadCompletedItems();
    }
  }

  // Status → left border color
  Color _statusColor() {
    final os = PosService.getOrderStatus(_data);
    if (os == 'cancelled') return Colors.red;
    if (os == 'placed') return const Color(0xFF2196F3);
    if (os == 'preparing') return const Color(0xFFF57C00);
    if (os == 'ready') return const Color(0xFF4CAF50);
    if (os == 'served') return const Color(0xFF7C4DFF);
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    final status = _data['status']?.toString() ?? 'pending';
    final items = (_data['items'] ?? []) as List<dynamic>;
    final cancelledItems = (_data['cancelledItems'] ?? []) as List<dynamic>;
    final isCancelled = status == AppConstants.statusCancelled;
    final timestamp = _data['timestamp'] as Timestamp?;
    final elapsed = timestamp != null
        ? DateTime.now().difference(timestamp.toDate()).inMinutes
        : 0;
    final isLate = elapsed >= KDSConfig.lateMinutes;

    final orderNum = _data['dailyOrderNumber']?.toString() ?? '?';
    final customerName = _data['customerName']?.toString() ?? 'Guest';
    final tableName = _data['tableName']?.toString();
    final orderType = (_data['Order_type'] ?? _data['orderType'] ?? 'delivery').toString();
    final source = _data['source']?.toString();
    final sourceLabel = KDSConfig.getSourceLabel(source);

    // Add-on tracking
    final addOnRound = (_data['addOnRound'] as int?) ?? 0;
    final previousItemCount = (_data['previousItemCount'] as int?) ?? items.length;
    final hasActiveAddOns = _data['hasActiveAddOns'] == true;

    final branchIds = _data['branchIds'] as List<dynamic>?;
    final branchName = (branchIds != null && branchIds.isNotEmpty)
        ? branchIds.first.toString().replaceAll('_', ' ')
        : null;

    final bg = widget.isDark ? const Color(0xFF1E1E2E) : Colors.white;
    final statusCol = _statusColor();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isLate ? Colors.red : (widget.isDark ? const Color(0xFF333355) : Colors.grey.shade300),
          width: isLate ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(widget.isDark ? 0.3 : 0.08),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left color bar (Odoo style)
            Container(
              width: 6,
              decoration: BoxDecoration(
                color: statusCol,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(7),
                  bottomLeft: Radius.circular(7),
                ),
              ),
            ),
            // Card content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ─── HEADER ────────────────────────
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: widget.isDark
                          ? Colors.white.withOpacity(0.03)
                          : Colors.grey.shade50,
                      border: Border(
                        bottom: BorderSide(
                          color: widget.isDark ? Colors.white10 : Colors.grey.shade200,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        // Order number (large, Odoo style)
                        Text(
                          isCancelled ? '#$orderNum CANCELLED' : '#$orderNum',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: isCancelled ? Colors.red : statusCol,
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Customer / Table
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tableName ?? customerName,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: widget.isDark ? Colors.white : Colors.black87,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Row(
                                children: [
                                  Text(
                                    orderType.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: widget.isDark ? Colors.white38 : Colors.grey,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  if (widget.showBranchName && branchName != null) ...[
                                    Text(' · ', style: TextStyle(color: widget.isDark ? Colors.white24 : Colors.grey)),
                                    Flexible(
                                      child: Text(
                                        branchName,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: widget.isDark ? Colors.white24 : Colors.grey,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                        // Add-on round badge
                        if (hasActiveAddOns && addOnRound > 0)
                          Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.15),
                              border: Border.all(color: Colors.orange, width: 1.5),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'ADD-ON \u2014 Round $addOnRound',
                              style: const TextStyle(
                                color: Colors.orange,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        // Source badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: KDSConfig.getSourceColor(source).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            sourceLabel,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: KDSConfig.getSourceColor(source),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // ── DUAL STATUS: PAID BADGE ──
                        if (PosService.getPaymentStatus(_data) == 'paid')
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.green, width: 1),
                            ),
                            child: const Text(
                              'PAID',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: Colors.green,
                              ),
                            ),
                          ),
                        if (PosService.getPaymentStatus(_data) == 'paid') const SizedBox(width: 8),
                        // Timer badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: KDSConfig.getTimerColor(elapsed),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.timer_outlined, size: 12, color: Colors.white),
                              const SizedBox(width: 3),
                              Text(
                                '${elapsed}m',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ─── ITEMS ─────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Column(
                      children: List.generate(items.length + cancelledItems.length, (idx) {
                        final bool isItemFromCancelledList = idx >= items.length;
                        final item = isItemFromCancelledList 
                            ? cancelledItems[idx - items.length] as Map<String, dynamic>
                            : items[idx] as Map<String, dynamic>;
                        
                        final name = item['name']?.toString() ?? 'Unknown';
                        final qty = (item['quantity'] ?? 1);
                        final notes = item['notes']?.toString() ?? '';
                        final isItemCancelled = item['isCancelled'] == true;
                        
                        final isCrossed = !isItemFromCancelledList && _crossedItems.contains(idx);
                        // Determine if this is a NEW add-on for the CURRENT round
                        final bool isCurrentAddOn = !isItemCancelled && hasActiveAddOns && idx >= previousItemCount;
 
                        // Determine if this is an OLD item in a re-opened order
                        final bool isOldServedItem = !isItemCancelled && hasActiveAddOns && idx < previousItemCount;
 
                        // Visual state
                        final bool showGrey = isOldServedItem || isCrossed;
                        final bool showStrikethrough = isOldServedItem || isCrossed || isItemCancelled || isCancelled;
                        final bool isActuallyCancelled = isItemCancelled || isCancelled;

                        return InkWell(
                          onTap: isItemFromCancelledList ? null : () => _toggleItemCrossed(idx),
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 2),
                            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                            decoration: isCurrentAddOn
                                ? BoxDecoration(
                                    color: Colors.orange.withOpacity(widget.isDark ? 0.08 : 0.05),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                                  )
                                : null,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Quantity badge
                                Container(
                                  width: 28,
                                  height: 28,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: (showGrey || isActuallyCancelled)
                                        ? (isActuallyCancelled ? Colors.red.withOpacity(0.1) : Colors.green.withOpacity(0.15))
                                        : isCurrentAddOn
                                            ? Colors.orange.withOpacity(0.15)
                                            : (widget.isDark ? Colors.white.withOpacity(0.06) : Colors.grey.shade100),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: (showGrey || isActuallyCancelled)
                                      ? Icon(
                                          isActuallyCancelled ? Icons.close : (isOldServedItem ? Icons.done_all : Icons.check),
                                          size: 16,
                                          color: isActuallyCancelled ? Colors.red : (isOldServedItem ? Colors.grey : Colors.green),
                                        )
                                      : Text(
                                          '$qty',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: isActuallyCancelled
                                                ? Colors.red
                                                : isCurrentAddOn
                                                    ? Colors.orange
                                                    : (widget.isDark ? Colors.white : Colors.black87),
                                          ),
                                        ),
                                ),
                                const SizedBox(width: 10),
                                // Item name + notes
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              isActuallyCancelled ? '$name (CANCELLED)' : name,
                                              style: TextStyle(
                                                fontSize: isCurrentAddOn ? 15 : 14,
                                                fontWeight: isCurrentAddOn
                                                    ? FontWeight.w700
                                                    : FontWeight.w500,
                                                color: isActuallyCancelled
                                                    ? Colors.red.shade400
                                                    : showGrey
                                                        ? (widget.isDark ? Colors.white30 : Colors.grey)
                                                        : isCurrentAddOn
                                                            ? Colors.orange
                                                            : (widget.isDark ? Colors.white : Colors.black87),
                                                decoration: showStrikethrough ? TextDecoration.lineThrough : null,
                                              ),
                                            ),
                                          ),
                                          // Old served item badge
                                          if (isOldServedItem)
                                            Container(
                                              margin: const EdgeInsets.only(left: 6),
                                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.grey.withOpacity(0.15),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                'DONE',
                                                style: TextStyle(
                                                  color: widget.isDark ? Colors.white30 : Colors.grey,
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          // New add-on badge
                                          if (isCurrentAddOn)
                                            Container(
                                              margin: const EdgeInsets.only(left: 6),
                                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.orange.withOpacity(0.15),
                                                border: Border.all(color: Colors.orange, width: 1),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: const Text(
                                                'NEW',
                                                style: TextStyle(
                                                  color: Colors.orange,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      if (notes.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 2),
                                          child: Text(
                                            '⚠ $notes',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFFFF8F00),
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      // ── Add-ons Display ──
                                      if (item['addons'] != null && (item['addons'] as List).isNotEmpty)
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
                                                      decoration: BoxDecoration(
                                                        color: widget.isDark ? Colors.white70 : Colors.black54,
                                                        shape: BoxShape.circle,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Expanded(
                                                      child: Text(
                                                        addon['name']?.toString() ?? '',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.w600,
                                                          color: widget.isDark ? Colors.white70 : Colors.black87,
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
                              ],
                            ),
                          ),
                        );
                      }),
                    ),
                  ),

                  // ─── ACTION BUTTON ─────────────────
                  _buildAction(status),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAction(String status) {
    String? label;
    Color? color;
    String? nextStatus;

    if (widget.isRecall) {
      label = 'RECALL TO KITCHEN';
      color = Colors.orange;
      nextStatus = AppConstants.statusPreparing;
    } else if (status == AppConstants.statusPending) {
      label = '▶  START PREPARING';
      color = const Color(0xFF2196F3);
      nextStatus = AppConstants.statusPreparing;
    } else if (status == AppConstants.statusPreparing) {
      label = '✓  MARK READY';
      color = const Color(0xFF4CAF50);
      nextStatus = AppConstants.statusPrepared;
    } else if (status == AppConstants.statusPrepared) {
      label = '🍽  SERVE ORDER';
      color = const Color(0xFF7C4DFF);
      nextStatus = AppConstants.statusServed;
    } else if (status == AppConstants.statusCancelled) {
      label = '🗑  DISMISS CANCELLED';
      color = Colors.red.shade700;
      nextStatus = 'dismiss_cancelled';
    }

    if (label == null || color == null || nextStatus == null) {
      return const SizedBox.shrink();
    }

    return Material(
      color: color,
      borderRadius: const BorderRadius.only(
        bottomRight: Radius.circular(7),
      ),
      child: InkWell(
        onTap: widget.isProcessing ? null : () => widget.onStatusUpdate(nextStatus!),
        borderRadius: const BorderRadius.only(
          bottomRight: Radius.circular(7),
        ),
        child: Container(
          width: double.infinity,
          height: 44, // Fixed height to prevent bottom RenderFlex overflow
          alignment: Alignment.center,
          child: widget.isProcessing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    letterSpacing: 0.5,
                  ),
                ),
        ),
      ),
    );
  }
}
