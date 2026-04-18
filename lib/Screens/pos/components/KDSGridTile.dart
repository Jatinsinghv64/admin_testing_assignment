// lib/Screens/pos/components/KDSGridTile.dart
// Compact grid tile for KDS Grid View (Odoo Kitchen Display style)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../../../../constants.dart';
import 'kds_constants.dart';

class KDSGridTile extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> orderDoc;
  final bool isDark;
  final bool isProcessing;
  final ValueChanged<String> onStatusUpdate;
  final VoidCallback onTap;

  const KDSGridTile({
    super.key,
    required this.orderDoc,
    required this.isDark,
    required this.isProcessing,
    required this.onStatusUpdate,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final data = orderDoc.data();
    final status = data['status']?.toString() ?? 'pending';
    final items = (data['items'] ?? []) as List<dynamic>;
    final timestamp = data['timestamp'] as Timestamp?;
    final elapsed = timestamp != null
        ? DateTime.now().difference(timestamp.toDate()).inMinutes
        : 0;

    final orderNum = OrderNumberHelper.getDisplayNumber(
      data,
      orderId: orderDoc.id,
    );
    final orderNumLabel =
        orderNum == OrderNumberHelper.loadingText || orderNum.startsWith('#')
            ? orderNum
            : '#$orderNum';
    final tableName = data['tableName']?.toString();
    final customerName = data['customerName']?.toString() ?? 'Guest';
    final orderType =
        (data['Order_type'] ?? data['orderType'] ?? 'delivery').toString();
    final addOnRound = (data['addOnRound'] as int?) ?? 0;
    final hasActiveAddOns = data['hasActiveAddOns'] == true;

    final tileColor = KDSConfig.getGridTileColor(elapsed);
    final statusLabel = _statusLabel(status);
    final statusColor = _statusAccentColor(status);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: elapsed >= KDSConfig.gridWarningMinutes
                ? Colors.red.withValues(alpha: 0.7)
                : (isDark ? const Color(0xFF333355) : Colors.grey.shade300),
            width: elapsed >= KDSConfig.gridWarningMinutes ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ─── COLOR BAR (top) ────────────────────
            Container(
              height: 6,
              decoration: BoxDecoration(
                color: tileColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(9),
                  topRight: Radius.circular(9),
                ),
              ),
            ),

            // ─── TILE CONTENT ───────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Order number + table
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            orderNumLabel,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: tileColor,
                            ),
                          ),
                        ),
                        // Add-on badge
                        if (hasActiveAddOns)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.15),
                              border: Border.all(
                                  color: Colors.orange.withValues(alpha: 0.5)),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'R$addOnRound',
                              style: const TextStyle(
                                color: Colors.orange,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // Table / Customer
                    Text(
                      tableName ?? customerName,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),

                    const SizedBox(height: 2),

                    // Order type
                    Text(
                      orderType.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        color: isDark ? Colors.white30 : Colors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),

                    const Spacer(),

                    // Items count + timer row
                    Row(
                      children: [
                        Icon(
                          Icons.restaurant_menu,
                          size: 14,
                          color: isDark ? Colors.white30 : Colors.grey,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${items.length} items',
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                isDark ? Colors.white54 : Colors.grey.shade600,
                          ),
                        ),
                        const Spacer(),
                        // Timer badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: tileColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.timer_outlined,
                                  size: 11, color: Theme.of(context).cardColor),
                              const SizedBox(width: 2),
                              Text(
                                '${elapsed}m',
                                style: TextStyle(
                                color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Theme.of(context).cardColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
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

            // ─── STATUS / ACTION BAR ────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.03)
                    : Colors.grey.shade50,
                border: Border(
                  top: BorderSide(
                    color: isDark ? Colors.white10 : Colors.grey.shade200,
                  ),
                ),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(9),
                  bottomRight: Radius.circular(9),
                ),
              ),
              child: Row(
                children: [
                  // Status label
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Quick action button
                  _buildQuickAction(status),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickAction(String status) {
    String? nextStatus;
    IconData icon;
    Color color;

    if (status == AppConstants.statusPending ||
        status == AppConstants.statusNeedsAssignment) {
      nextStatus = AppConstants.statusPreparing;
      icon = Icons.play_arrow_rounded;
      color = const Color(0xFF2196F3);
    } else if (status == AppConstants.statusPreparing) {
      nextStatus = AppConstants.statusPrepared;
      icon = Icons.check_rounded;
      color = const Color(0xFF4CAF50);
    } else if (status == AppConstants.statusPrepared) {
      nextStatus = AppConstants.statusServed;
      icon = Icons.room_service_rounded;
      color = const Color(0xFF7C4DFF);
    } else {
      return const SizedBox.shrink();
    }

    return SizedBox(
      width: 28,
      height: 28,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: isProcessing ? null : () => onStatusUpdate(nextStatus!),
          child: isProcessing
              ? const Padding(
                  padding: EdgeInsets.all(6),
                  child: CircularProgressIndicator(
                      color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Theme.of(context).cardColor, strokeWidth: 2),
                )
              : Icon(icon, color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Theme.of(context).cardColor, size: 18),
        ),
      ),
    );
  }

  String _statusLabel(String status) {
    if (status == AppConstants.statusPending ||
        status == AppConstants.statusNeedsAssignment) return 'WAITING';
    if (status == AppConstants.statusPreparing) return 'COOKING';
    if (status == AppConstants.statusPrepared) return 'READY';
    if (status == AppConstants.statusServed) return 'SERVED';
    return status.toUpperCase();
  }

  Color _statusAccentColor(String status) {
    if (status == AppConstants.statusPending ||
        status == AppConstants.statusNeedsAssignment)
      return const Color(0xFF2196F3);
    if (status == AppConstants.statusPreparing) return const Color(0xFFF57C00);
    if (status == AppConstants.statusPrepared) return const Color(0xFF4CAF50);
    if (status == AppConstants.statusServed) return const Color(0xFF7C4DFF);
    return Colors.grey;
  }
}
