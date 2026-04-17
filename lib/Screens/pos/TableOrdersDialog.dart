// lib/Screens/pos/TableOrdersDialog.dart
// Odoo-style dialog — shows all active orders for a specific table
// Allows: Pay individual order, Pay All, Add more items

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../main.dart';
import '../../../../constants.dart';
import '../../../../services/pos/pos_service.dart';
import '../../../../services/pos/pos_models.dart';
import '../../../../Widgets/PrintingService.dart';
import 'pos_payment_dialog.dart';

class TableOrdersDialog extends StatelessWidget {
  final String tableId;
  final String tableName;
  final List<String> branchIds;

  /// Called when user taps "Add Items" — caller should
  /// select this table in PosService and close the floor plan.
  final VoidCallback onAddItems;

  const TableOrdersDialog({
    super.key,
    required this.tableId,
    required this.tableName,
    required this.branchIds,
    required this.onAddItems,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 580,
        constraints: const BoxConstraints(maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(context),
            const Divider(height: 1),
            Flexible(child: _buildOrdersList(context)),
          ],
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────
  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.deepPurple.withValues(alpha: 0.04),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.deepPurple.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child:
                const Icon(Icons.table_bar, color: Colors.deepPurple, size: 22),
          ),
          const SizedBox(width: 12),
          // Table name + status — constrained so buttons can't push it off
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tableName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'OCCUPIED',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Colors.red,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Guest Count display
                    Consumer<PosService>(
                      builder: (context, pos, _) {
                        final count = pos.guestCount;
                        if (count == null) return const SizedBox.shrink();
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.people_alt, size: 10, color: Colors.blue),
                              const SizedBox(width: 4),
                              Text(
                                '$count Guests',
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.blue,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Active orders',
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // ── Compact action buttons that won't overflow ──
          // Transfer (icon + label on wider screens)
          Tooltip(
            message: 'Transfer Table',
            child: OutlinedButton.icon(
              onPressed: () => _showTransferDialog(context),
              icon: const Icon(Icons.swap_horiz, size: 18, color: Colors.blueGrey),
              label: const Text('Transfer',
                  style: TextStyle(color: Colors.blueGrey, fontSize: 14, fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                side: BorderSide(color: Colors.blueGrey.shade200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Add Items
          Tooltip(
            message: 'Add Items to table',
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context); // close this dialog
                onAddItems();
              },
              icon: const Icon(Icons.add_circle_outline, size: 18),
              label: const Text('Add Items',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Close
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close, color: Colors.grey, size: 20),
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  // ── Orders List (real-time) ────────────────────────────────────
  Widget _buildOrdersList(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection(AppConstants.collectionOrders)
          .where('branchIds', arrayContains: branchIds.first)
          .where('tableId', isEqualTo: tableId)
          .where('Order_type', isEqualTo: 'dine_in')
          .where('status', whereIn: [
            AppConstants.statusPending,
            AppConstants.statusPreparing,
            AppConstants.statusPrepared,
            AppConstants.statusServed,
          ])
          .orderBy('timestamp', descending: false)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(40),
            child: Center(
                child: CircularProgressIndicator(color: Colors.deepPurple)),
          );
        }

        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: Text(
                'Error loading orders: ${snapshot.error}',
                style: TextStyle(color: Colors.red[400], fontSize: 13),
              ),
            ),
          );
        }

        final orders = snapshot.data?.docs ?? [];

        if (orders.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(40),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_outline,
                      size: 48, color: Colors.green[300]),
                  const SizedBox(height: 12),
                  Text(
                    'No active orders',
                    style: TextStyle(fontSize: 15, color: Colors.grey[500]),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Table is clear',
                    style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                  ),
                ],
              ),
            ),
          );
        }

        double outstandingTotal = 0;
        bool allServedAndPaid = orders.isNotEmpty;
        final payableOrders = <DocumentSnapshot>[];
        for (final doc in orders) {
          final data = doc.data() as Map<String, dynamic>;
          final outstanding = PosService.getOutstandingAmount(data);
          outstandingTotal += outstanding;
          if (outstanding > 0.001) {
            payableOrders.add(doc);
          }
          if (PosService.getOrderStatus(data) != AppConstants.statusServed ||
              PosService.getPaymentStatus(data) != 'paid') {
            allServedAndPaid = false;
          }
        }
        outstandingTotal = double.parse(outstandingTotal.toStringAsFixed(2));

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Orders
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.all(16),
                itemCount: orders.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final doc = orders[index];
                  final data = doc.data() as Map<String, dynamic>;
                  return _TableOrderCard(
                    orderId: doc.id,
                    data: data,
                    branchIds: branchIds,
                    tableId: tableId,
                    orderIndex: index + 1,
                    totalOrders: orders.length,
                  );
                },
              ),
            ),
            _buildPayAllFooter(
              context,
              orders,
              payableOrders,
              outstandingTotal,
              allServedAndPaid,
            ),
          ],
        );
      },
    );
  }

  // ── Pay All Footer ─────────────────────────────────────────────
  Widget _buildPayAllFooter(
    BuildContext context,
    List<DocumentSnapshot> orders,
    List<DocumentSnapshot> payableOrders,
    double outstandingTotal,
    bool allServedAndPaid,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        border: Border(top: BorderSide(color: Colors.grey[200]!)),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
      ),
      child: Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 12,
        children: [
          SizedBox(
            width: 140,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${orders.length} orders',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
                Text(
                  '${AppConstants.currencySymbol}${outstandingTotal.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  outstandingTotal > 0.001
                      ? 'Outstanding balance'
                      : 'No payment due',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
          const Spacer(),
          // Print Button
          if (orders.isNotEmpty)
            SizedBox(
              height: 46,
              child: OutlinedButton.icon(
                onPressed: () =>
                    PrintingService.printReceipt(context, orders.first),
                icon: const Icon(Icons.print, size: 20),
                label: const Text('Print',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.deepPurple,
                  side: const BorderSide(color: Colors.deepPurple),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
              ),
            ),
          if (payableOrders.isNotEmpty)
            SizedBox(
              height: 46,
              child: ElevatedButton.icon(
                onPressed: () =>
                    _payAllOrders(context, payableOrders, outstandingTotal),
                icon: const Icon(Icons.payments, size: 20),
                label: const Text(
                  'Collect Payment',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[600],
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                ),
              ),
            ),
          // Complete Order & Free Table Button
          SizedBox(
            height: 46,
            child: ElevatedButton.icon(
              onPressed: !allServedAndPaid
                  ? null
                  : () async {
                      final pos = context.read<PosService>();

                      // This method handles the dual-check internally
                      final success = await pos.completeOrderWithDualCheck(
                        tableId: tableId,
                        branchIds: branchIds,
                      );

                      if (!success && context.mounted) {
                        _showCompletionErrorDialog(context);
                      } else if (context.mounted) {
                        Navigator.pop(context); // Close dialog on success
                      }
                    },
              icon: const Icon(Icons.check_circle, size: 20),
              label: const Text(
                'Complete Table',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showCompletionErrorDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cannot Complete Order'),
        content: const Text(
          'A table can only be freed when ALL orders are both SERVED and PAID.\n\n'
          'Please ensure kitchen has served all items and payment is collected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _payAllOrders(
    BuildContext context,
    List<DocumentSnapshot> orders,
    double grandTotal,
  ) async {
    final posService = context.read<PosService>();

    if (posService.cartItems.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot proceed with Pay All. Please clear your current POS cart first to avoid mixing items.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final result = await showDialog<PosPayment>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ChangeNotifierProvider.value(
        value: posService,
        child: PosPaymentDialog(
          totalAmount: grandTotal,
          branchIds: branchIds,
          onPaymentComplete: (_) {},
          returnPaymentOnly: true,
        ),
      ),
    );

    if (result == null || !context.mounted)
      return; // User cancelled or unmounted

    late final OverlayEntry loadingOverlay;
    loadingOverlay = OverlayEntry(
      builder: (_) => Container(
        color: Colors.black54,
        child: const Center(child: CircularProgressIndicator(color: Colors.deepPurple)),
      ),
    );
    Overlay.of(context).insert(loadingOverlay);

    try {
      final userScope = context.read<UserScopeService>();

      await posService.submitOrderWithPayment(
        userScope: userScope,
        branchIds: branchIds,
        payment: result,
        existingOrders: orders,
      );

      if (context.mounted) {
        Navigator.pop(context); // close table orders dialog
      }
    } catch (e) {
      final errorMessage = PosService.displayError(e);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment failed: $errorMessage'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (loadingOverlay.mounted) {
        loadingOverlay.remove();
      }
    }
  }

  Future<void> _showTransferDialog(BuildContext context) async {
    final snap = await FirebaseFirestore.instance.collection('Branch').doc(branchIds.first).get();
    final tablesMap = snap.data()?['Tables'] as Map<String, dynamic>? ?? {};
    final availableTables = tablesMap.entries.where((e) {
      final status = e.value['status'] ?? 'available';
      return status == 'available' && e.key != tableId;
    }).toList();

    if (availableTables.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No available tables to transfer to.'), backgroundColor: Colors.orange),
        );
      }
      return;
    }

    if (!context.mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Transfer to Table'),
        content: SizedBox(
          width: 300,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: availableTables.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (ctx, i) {
              final t = availableTables[i];
              return ListTile(
                title: Text(t.value['name'] ?? 'Unknown'),
                onTap: () async {
                  // Fetch all active orders for current table
                  final ordersSnap = await FirebaseFirestore.instance
                      .collection(AppConstants.collectionOrders)
                      .where('branchIds', arrayContains: branchIds.first)
                      .where('tableId', isEqualTo: tableId)
                      .where('Order_type', isEqualTo: 'dine_in')
                      .where('status', whereIn: [
                        AppConstants.statusPending,
                        AppConstants.statusPreparing,
                        AppConstants.statusPrepared,
                        AppConstants.statusServed,
                      ])
                      .get();

                  final batch = FirebaseFirestore.instance.batch();
                  for (final doc in ordersSnap.docs) {
                    batch.update(doc.reference, {
                      'tableId': t.key,
                      'tableName': t.value['name'],
                      'previousTableId': tableId,
                      'previousTableName': tableName,
                      'tableTransferredAt': FieldValue.serverTimestamp(),
                    });
                  }

                  // Update floor plan statuses
                  batch.update(snap.reference, {
                    'Tables.${t.key}.status': 'occupied',
                    'Tables.$tableId.status': 'available', // old table goes back
                  });

                  await batch.commit();

                  if (ctx.mounted) {
                    // Pop the transfer picker dialog
                    Navigator.pop(ctx);
                    // Use microtask so the Navigator is fully unlocked before
                    // popping the parent TableOrdersDialog — prevents
                    // the `!_debugLocked` assertion crash on web/desktop.
                    if (context.mounted) {
                      Future.microtask(() {
                        if (context.mounted) Navigator.pop(context);
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Transferred to ${t.value['name']}'),
                          backgroundColor: Colors.green,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  }
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Individual Table Order Card
// ═══════════════════════════════════════════════════════════════════
class _TableOrderCard extends StatefulWidget {
  final String orderId;
  final Map<String, dynamic> data;
  final List<String> branchIds;
  final String tableId;
  final int orderIndex;
  final int totalOrders;

  const _TableOrderCard({
    required this.orderId,
    required this.data,
    required this.branchIds,
    required this.tableId,
    required this.orderIndex,
    required this.totalOrders,
  });

  @override
  State<_TableOrderCard> createState() => _TableOrderCardState();
}

class _TableOrderCardState extends State<_TableOrderCard> {
  bool _isDeleting = false;

  String get _status => AppConstants.normalizeStatus(
      widget.data['status']?.toString() ?? AppConstants.statusPending);

  @override
  Widget build(BuildContext context) {
    final orderNumber = OrderNumberHelper.getDisplayNumber(
      widget.data,
      orderId: widget.orderId,
    );
    final items = widget.data['items'] as List<dynamic>? ?? [];
    final totalAmount = (widget.data['totalAmount'] ?? 0).toDouble();
    final timestamp = widget.data['timestamp'];

    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.12)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Card Header ──
              _buildCardHeader(orderNumber, timestamp),
              // ── Items ──
              _buildItems(items),
              // ── Footer ──
              _buildCardFooter(context, totalAmount),
            ],
          ),
        ),
        if (_isDeleting)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Center(
                child: CircularProgressIndicator(color: Colors.red),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCardHeader(String orderNumber, dynamic timestamp) {
    Color statusColor;
    switch (_status) {
      case AppConstants.statusPending:
        statusColor = Colors.orange;
        break;
      case AppConstants.statusPreparing:
        statusColor = Colors.blue;
        break;
      case AppConstants.statusPrepared:
        statusColor = Colors.green;
        break;
      case AppConstants.statusServed:
        statusColor = Colors.teal;
        break;
      case AppConstants.statusCancelled:
        statusColor = Colors.red;
        break;
      default:
        statusColor = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.04),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
      ),
      child: Row(
        children: [
          // Order number
          Text(
            'Order #$orderNumber',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const Spacer(),
          // ── DUAL STATUS BADGES ──
          _buildStatusBadge(PosService.getOrderStatus(widget.data)),
          const SizedBox(width: 8),
          _buildPaymentBadge(PosService.getPaymentStatus(widget.data)),
          const SizedBox(width: 8),
          // Cancel Order button
          IconButton(
            onPressed: () => _confirmCancelOrder(context),
            icon: const Icon(Icons.cancel_outlined,
                color: Colors.redAccent, size: 20),
            tooltip: 'Cancel Order',
            constraints: const BoxConstraints(),
            padding: EdgeInsets.zero,
          ),
          // Time
          if (timestamp != null) ...[
            const SizedBox(width: 8),
            _buildTimeBadge(timestamp),
          ],
        ],
      ),
    );
  }

  Widget _buildTimeBadge(dynamic timestamp) {
    try {
      final orderTime = (timestamp as Timestamp).toDate();
      final elapsed = DateTime.now().difference(orderTime);
      final minutes = elapsed.inMinutes;
      final color = minutes < 10
          ? Colors.green
          : minutes < 30
              ? Colors.orange
              : Colors.red;

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timer_outlined, size: 11, color: color),
            const SizedBox(width: 3),
            Text(
              '${minutes}m',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  Widget _buildItems(List<dynamic> items) {
    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Text('No items',
            style: TextStyle(color: Colors.grey, fontSize: 12)),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: items.asMap().entries.take(6).map((entry) {
          final index = entry.key;
          final item = entry.value;
          final itemMap = item as Map<String, dynamic>;
          final name = itemMap['name']?.toString() ?? 'Item';
          final qty = itemMap['quantity'] ?? 1;
          final price = (itemMap['price'] ?? 0).toDouble();
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Center(
                    child: Text(
                      '${qty}x',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[700],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${AppConstants.currencySymbol}${(price * qty).toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: () => _confirmRemoveItem(context, index),
                  icon: const Icon(Icons.delete_outline,
                      size: 16, color: Colors.redAccent),
                  tooltip: 'Remove Item',
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(4),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color statusColor;
    final s = AppConstants.normalizeStatus(status);
    switch (s) {
      case AppConstants.statusPending:
        statusColor = Colors.blue;
        break;
      case AppConstants.statusPreparing:
        statusColor = Colors.orange;
        break;
      case AppConstants.statusPrepared:
        statusColor = Colors.green;
        break;
      case AppConstants.statusServed:
        statusColor = Colors.deepPurple;
        break;
      case AppConstants.statusCancelled:
        statusColor = Colors.red;
        break;
      default:
        statusColor = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: statusColor, width: 0.5),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
            fontSize: 9, fontWeight: FontWeight.w800, color: statusColor),
      ),
    );
  }

  Widget _buildPaymentBadge(String status) {
    final isPaid = status == 'paid';
    final color = isPaid ? Colors.green : Colors.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color, width: 0.5),
      ),
      child: Text(
        isPaid ? 'PAID' : 'UNPAID',
        style:
            TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: color),
      ),
    );
  }

  Widget _buildCardFooter(BuildContext context, double totalAmount) {
    final normalized =
        AppConstants.normalizeStatus(widget.data['status']?.toString() ?? '');
    final statusColors = {
      AppConstants.statusPending: Colors.orange,
      AppConstants.statusPreparing: Colors.blue,
      AppConstants.statusPrepared: Colors.teal,
      AppConstants.statusServed: Colors.green,
      AppConstants.statusCancelled: Colors.red,
    };
    final statusColor = statusColors[normalized] ?? Colors.grey;
    final statusLabel = AppConstants.getStatusDisplayText(normalized);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
        border: Border(top: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Row(
        children: [
          Text(
            '${AppConstants.currencySymbol}${totalAmount.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: statusColor.withValues(alpha: 0.3)),
            ),
            child: Text(
              statusLabel,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: statusColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmCancelOrder(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Order?'),
        content: const Text(
            'Are you sure you want to cancel this entire order? This will restore ingredient stock.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep Order')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      // Local status check to avoid masked exception issues on Web
      if (_status == AppConstants.statusPrepared ||
          _status == AppConstants.statusServed) {
        _showRestrictedActionDialog(
          context,
          "Cannot cancel an order that is already ${_status.toUpperCase()}.",
        );
        return;
      }

      setState(() => _isDeleting = true);
      try {
        final posService = context.read<PosService>();
        final userScope = context.read<UserScopeService>();
        await posService.cancelOrder(
          orderId: widget.orderId,
          userScope: userScope,
          tableId: widget.tableId,
          branchIds: widget.branchIds,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Order cancelled successfully'),
                backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Failed to cancel order: $e'),
                backgroundColor: Colors.red),
          );
        }
      } finally {
        if (mounted) setState(() => _isDeleting = false);
      }
    }
  }

  Future<void> _confirmRemoveItem(BuildContext context, int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Item?'),
        content: const Text(
            'Are you sure you want to remove this item from the order?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep Item')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      // Local status check to avoid masked exception issues on Web
      if (_status == AppConstants.statusPrepared ||
          _status == AppConstants.statusServed) {
        _showRestrictedActionDialog(
          context,
          "Cannot remove items from an order that is already ${_status.toUpperCase()}.",
        );
        return;
      }

      setState(() => _isDeleting = true);
      try {
        final posService = context.read<PosService>();
        final userScope = context.read<UserScopeService>();
        await posService.removeItemFromOrder(
          orderId: widget.orderId,
          itemIndex: index,
          userScope: userScope,
          branchIds: widget.branchIds,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Item removed successfully'),
                backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Failed to remove item: $e'),
                backgroundColor: Colors.red),
          );
        }
      } finally {
        if (mounted) setState(() => _isDeleting = false);
      }
    }
  }

  void _showRestrictedActionDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.warning_amber_rounded, color: Colors.red),
            ),
            const SizedBox(width: 12),
            const Text('Action Blocked'),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('OK', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
