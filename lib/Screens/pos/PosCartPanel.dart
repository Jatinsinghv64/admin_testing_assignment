// lib/Screens/pos/PosCartPanel.dart
// Cart panel widget for the POS screen (right side)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../main.dart';
import '../../constants.dart';
import '../../services/pos/pos_service.dart';
import '../../services/pos/pos_models.dart';
import '../../Widgets/PrintingService.dart';
import 'TableOrdersDialog.dart';
import 'PosPaymentDialog.dart';

class PosCartPanel extends StatefulWidget {
  final VoidCallback onOrderSubmit;
  final VoidCallback onPaymentTap;
  final bool isSubmittingOrder;

  const PosCartPanel({
    super.key,
    required this.onOrderSubmit,
    required this.onPaymentTap,
    this.isSubmittingOrder = false,
  });

  @override
  State<PosCartPanel> createState() => _PosCartPanelState();
}

class _PosCartPanelState extends State<PosCartPanel> {
  bool _isProcessingDeletion = false;

  void _setLoading(bool loading) {
    if (mounted) setState(() => _isProcessingDeletion = loading);
  }

  @override
  Widget build(BuildContext context) {
    final pos = context.watch<PosService>();

    return Stack(
      children: [
        Container(
          color: Colors.white,
          child: Column(
            children: [
              // ── Order Type Selector ──
              _buildOrderTypeSelector(context, pos),
              const Divider(height: 1),

              // ── Table / Customer Info + Clear Cart ──
              _buildCustomerInfo(context, pos),
              const Divider(height: 1),

              // ── Cart Header with item count ──
              if (!pos.isEmpty || pos.isAppendMode)
                _buildCartHeader(context, pos),

              // ── Cart Items List (Partitioned) ──
              Expanded(
                child: (pos.isEmpty && !pos.isAppendMode)
                    ? _buildEmptyCart()
                    : _buildPartitionedCartList(context, pos),
              ),

              // ── Order Summary ──
              if (!pos.isEmpty || pos.isAppendMode) _buildOrderSummary(pos),

              // ── Action Buttons ──
              _buildActionButtons(context, pos),
            ],
          ),
        ),
        if (widget.isSubmittingOrder || _isProcessingDeletion)
          Positioned.fill(
            child: Container(
              color: Colors.white.withOpacity(0.7),
              child: Center(
                child: CircularProgressIndicator(
                  color: widget.isSubmittingOrder ? Colors.deepPurple : Colors.red,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildOrderTypeSelector(BuildContext context, PosService pos) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Order Type',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: PosOrderType.values.map((type) {
              final isSelected = pos.orderType == type;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: _OrderTypeChip(
                    label: type.displayName,
                    isSelected: isSelected,
                    onTap: () => pos.setOrderType(type),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ── Cart Header with item count and clear button ──
  Widget _buildCartHeader(BuildContext context, PosService pos) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Append mode banner
        if (pos.isAppendMode)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.amber.withOpacity(0.15),
            child: Row(
              children: [
                Icon(Icons.playlist_add, size: 16, color: Colors.amber[800]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Adding to existing order on ${pos.selectedTableName ?? 'table'}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.amber[900],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                // Cancel Order button for append mode
                TextButton.icon(
                  onPressed: () => _confirmCancelOngoingOrder(context, pos),
                  icon: const Icon(Icons.cancel_outlined, size: 14, color: Colors.red),
                  label: const Text(
                    'Cancel Order',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    backgroundColor: Colors.red.withOpacity(0.1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                ),
              ],
            ),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.grey[50],
          child: Row(
            children: [
              Text(
                'Cart',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${pos.itemCount} items',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.deepPurple,
                  ),
                ),
              ),
              const Spacer(),
              // Clear cart button with confirmation
              InkWell(
                onTap: () => _showClearCartConfirmation(context, pos),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.delete_sweep, size: 14, color: Colors.red[400]),
                      const SizedBox(width: 4),
                      Text(
                        'Clear',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.red[400],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showClearCartConfirmation(BuildContext context, PosService pos) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.delete_sweep, color: Colors.red),
            ),
            const SizedBox(width: 12),
            const Text('Clear Cart?'),
          ],
        ),
        content: Text(
          'Remove all ${pos.itemCount} items from the cart? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              pos.clearCart();
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Clear All', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerInfo(BuildContext context, PosService pos) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          if (pos.orderType != PosOrderType.dineIn) ...[
            Icon(Icons.person_outline, size: 18, color: Colors.grey[600]),
            const SizedBox(width: 8),
            Expanded(
              child: GestureDetector(
                onTap: () => _showCustomerDialog(context, pos),
                child: Text(
                  pos.customerName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[800],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
          if (pos.orderType == PosOrderType.dineIn) ...[
            const SizedBox(width: 8),
            InkWell(
              onTap: () => _showTableSelector(context, pos),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: pos.selectedTableId != null
                      ? Colors.deepPurple.withOpacity(0.1)
                      : Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: pos.selectedTableId != null
                        ? Colors.deepPurple.withOpacity(0.3)
                        : Colors.orange.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.table_bar,
                      size: 14,
                      color: pos.selectedTableId != null
                          ? Colors.deepPurple
                          : Colors.orange,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      pos.selectedTableName ?? 'Select Table',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: pos.selectedTableId != null
                            ? Colors.deepPurple
                            : Colors.orange,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyCart() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.shopping_cart_outlined,
            size: 64,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            'Cart is empty',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.grey[400],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap products to add them',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[350],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPartitionedCartList(BuildContext context, PosService pos) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 0),
      children: [
        if (pos.isAppendMode) ...[
          _buildSectionHeader('Ongoing Order', Icons.hourglass_top_rounded, Colors.amber[800]!),
          ...pos.ongoingOrders.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final items = List<Map<String, dynamic>>.from(data['items'] ?? []);
            final orderStatus = data['status']?.toString() ?? AppConstants.statusPending;
            return Column(
              children: items.asMap().entries.map((entry) {
                return _OngoingOrderItemTile(
                  item: entry.value,
                  orderId: doc.id,
                  itemIndex: entry.key,
                  orderStatus: orderStatus,
                  onLoadingChanged: _setLoading,
                );
              }).toList(),
            );
          }).toList(),
          const Divider(height: 24, indent: 16, endIndent: 16),
        ],
        if (!pos.isEmpty) ...[
          _buildSectionHeader('In Cart (New Items)', Icons.shopping_cart_outlined, Colors.deepPurple),
          _buildCartItemsList(context, pos),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: color.withOpacity(0.05),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 8),
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartItemsList(BuildContext context, PosService pos) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: pos.cartItems.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        color: Colors.grey[100],
        indent: 16,
        endIndent: 16,
      ),
      itemBuilder: (context, index) {
        final item = pos.cartItems[index];
        return _CartItemTile(
          item: item,
          onIncrement: () => pos.updateQuantity(index, item.quantity + 1),
          onDecrement: () => pos.updateQuantity(index, item.quantity - 1),
          onRemove: () => pos.removeItem(index),
          onNotesChanged: (notes) => pos.updateItemNotes(index, notes),
        );
      },
    );
  }

  Widget _buildOrderSummary(PosService pos) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        border: Border(
          top: BorderSide(color: Colors.grey[200]!),
        ),
      ),
      child: Column(
        children: [
          if (!pos.isEmpty) _buildSummaryRow('Subtotal', pos.subtotal),
          if (pos.isAppendMode) 
            _buildSummaryRow('Ongoing Total', pos.ongoingTotal, color: Colors.amber[900]),
          if (!pos.isEmpty && pos.orderDiscount > 0)
            _buildSummaryRow(
              'Discount (${pos.orderDiscount.toStringAsFixed(0)}%)',
              -pos.discountAmount,
              color: Colors.red,
            ),
          if (!pos.isEmpty && pos.taxAmount > 0)
            _buildSummaryRow('Tax', pos.taxAmount),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              Text(
                '${AppConstants.currencySymbol}${pos.grandTotal.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, double amount, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: color ?? Colors.grey[600],
            ),
          ),
          Text(
            '${AppConstants.currencySymbol}${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color ?? Colors.grey[800],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, PosService pos) {
    final needsTable = pos.orderType == PosOrderType.dineIn && pos.selectedTableId == null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Warning banner when dine-in but no table
          if (needsTable && !pos.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, size: 16, color: Colors.orange[700]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Select a table before placing a dine-in order',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.orange[800]),
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              // Order button — becomes "Select Table" when dine-in + no table
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: (pos.isEmpty || widget.isSubmittingOrder)
                        ? null
                        : needsTable
                            ? () => _showTableSelector(context, pos)
                            : widget.onOrderSubmit,
                    icon: widget.isSubmittingOrder 
                        ? const SizedBox(
                            width: 20, 
                            height: 20, 
                            child: CircularProgressIndicator(
                              strokeWidth: 2, 
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white)
                            )
                          )
                        : Icon(
                            needsTable ? Icons.table_bar : Icons.restaurant_menu,
                            size: 20,
                          ),
                    label: Text(
                      widget.isSubmittingOrder
                          ? 'Sending...'
                          : needsTable
                              ? 'Select Table'
                              : pos.isAppendMode
                                  ? 'Add to Order'
                                  : 'Order',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: needsTable ? Colors.orange : Colors.deepPurple,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey[300],
                      disabledForegroundColor: Colors.grey[600],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Payment button — disabled if dine-in + no table OR (empty cart AND no existing orders)
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: (needsTable || (pos.isEmpty && !pos.isAppendMode)) ? null : widget.onPaymentTap,
                    icon: const Icon(Icons.payments_rounded, size: 20),
                    label: const Text(
                      'Payment',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[600],
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey[200],
                      disabledForegroundColor: Colors.grey[400],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showCustomerDialog(BuildContext context, PosService pos) {
    final nameController = TextEditingController(text: pos.customerName);
    final phoneController = TextEditingController(text: pos.customerPhone ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.deepPurple.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.person, color: Colors.deepPurple),
            ),
            const SizedBox(width: 12),
            const Text('Customer Info'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: 'Customer Name',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneController,
              decoration: InputDecoration(
                labelText: 'Phone (optional)',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(Icons.phone_outlined),
              ),
              keyboardType: TextInputType.phone,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              pos.setCustomer(
                nameController.text.isEmpty
                    ? 'Walk-in Customer'
                    : nameController.text,
                phone: phoneController.text.isEmpty
                    ? null
                    : phoneController.text,
              );
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showTableSelector(BuildContext context, PosService pos) {
    final activeBranchId = pos.activeBranchId ?? '';
    showDialog(
      context: context,
      builder: (dialogContext) => ChangeNotifierProvider.value(
        value: pos,
        child: _FloorPlanDialog(
        onSelect: (tableId, tableName) {
          pos.loadTableContext(tableId, tableName, branchIds: [activeBranchId]);
          Navigator.pop(dialogContext);
        },
        onOccupiedTableTap: (tableId, tableName) {
          // Close the floor plan dialog first
          Navigator.pop(dialogContext);
          // Open the Table Orders Dialog
          showDialog(
            context: context,
            builder: (_) => ChangeNotifierProvider.value(
              value: pos,
              child: TableOrdersDialog(
                tableId: tableId,
                tableName: tableName,
                branchIds: [activeBranchId],
                onAddItems: () {
                },
              ),
            ),
          );
        },
      ),
      ),
    );
  }

  Future<void> _confirmCancelOngoingOrder(BuildContext context, PosService pos) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Order?'),
        content: const Text('Are you sure you want to cancel this entire order? This will restore ingredient stock.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep Order')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // Local status check to avoid masked exception issues on Web
      for (final doc in pos.ongoingOrders) {
        final data = doc.data() as Map<String, dynamic>;
        final status = data['status']?.toString() ?? '';
        if (status == AppConstants.statusPrepared || status == AppConstants.statusServed) {
          _showRestrictedActionDialog(
            context, 
            "Cannot cancel because part of this order is already ${status.toUpperCase()}.",
          );
          return;
        }
      }

      _setLoading(true);
      try {
        final userScope = context.read<UserScopeService>();
        // Cancel all ongoing orders associated with this table/session
        for (final doc in pos.ongoingOrders) {
          await pos.cancelOrder(
            orderId: doc.id,
            userScope: userScope,
            tableId: pos.selectedTableId!,
            branchIds: [pos.activeBranchId!],
          );
        }
        pos.clearCart();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Order cancelled successfully'), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to cancel order: $e'), backgroundColor: Colors.red),
          );
        }
      } finally {
        _setLoading(false);
      }
    }
  }

  static void _showRestrictedActionDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('OK', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// ── Order Type Chip ───────────────────────────────────────────
class _OrderTypeChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _OrderTypeChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.deepPurple
              : Colors.deepPurple.withOpacity(0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? Colors.deepPurple
                : Colors.deepPurple.withOpacity(0.15),
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isSelected ? Colors.white : Colors.deepPurple,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Ongoing Order Item Tile ────────────────────────────────────
class _OngoingOrderItemTile extends StatelessWidget {
  final Map<String, dynamic> item;
  final String orderId;
  final int itemIndex;
  final String orderStatus;
  final ValueChanged<bool> onLoadingChanged;

  const _OngoingOrderItemTile({
    required this.item,
    required this.orderId,
    required this.itemIndex,
    required this.orderStatus,
    required this.onLoadingChanged,
  });

  @override
  Widget build(BuildContext context) {
    final pos = context.read<PosService>();
    final userScope = context.read<UserScopeService>();
    final name = item['name']?.toString() ?? 'Item';
    final qty = (item['quantity'] as num? ?? 1).toInt();
    final price = (item['price'] as num? ?? 0).toDouble();
    final subtotal = (item['total'] as num? ?? (price * qty)).toDouble();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${qty}x',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
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
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (item['notes'] != null && item['notes'].toString().isNotEmpty)
                  Text(
                    item['notes'].toString(),
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey[400],
                      fontStyle: FontStyle.italic,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          Text(
            '${AppConstants.currencySymbol}${subtotal.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.grey[500],
            ),
          ),
          IconButton(
            onPressed: () => _confirmRemoveOngoingItem(context, pos, userScope),
            icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
            tooltip: 'Remove Item',
            constraints: const BoxConstraints(),
            padding: const EdgeInsets.all(4),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRemoveOngoingItem(BuildContext context, PosService pos, UserScopeService userScope) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Item?'),
        content: const Text('Are you sure you want to remove this item from the order?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep Item')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // Local status check to avoid masked exception issues on Web
      if (orderStatus == AppConstants.statusPrepared || orderStatus == AppConstants.statusServed) {
        _PosCartPanelState._showRestrictedActionDialog(
          context, 
          "Cannot remove items from an order that is already ${orderStatus.toUpperCase()}.",
        );
        return;
      }

      onLoadingChanged(true);
      try {
        await pos.removeItemFromOrder(
          orderId: orderId,
          itemIndex: itemIndex,
          userScope: userScope,
          branchIds: [pos.activeBranchId!],
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Item removed successfully'), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to remove item: $e'), backgroundColor: Colors.red),
          );
        }
      } finally {
        onLoadingChanged(false);
      }
    }
  }
}

// ── Cart Item Tile ────────────────────────────────────────────
class _CartItemTile extends StatelessWidget {
  final PosCartItem item;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onRemove;
  final ValueChanged<String> onNotesChanged;

  const _CartItemTile({
    required this.item,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRemove,
    required this.onNotesChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(item.productId),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onRemove(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red,
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Item details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${AppConstants.currencySymbol}${item.price.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                      // ── Add-ons Display ──
                      if (item.addons.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: item.addons.map((addon) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 4,
                                      height: 4,
                                      decoration: const BoxDecoration(
                                        color: Colors.deepPurple,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        '${addon.name} (+${AppConstants.currencySymbol}${addon.price.toStringAsFixed(2)})',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.deepPurple[700],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      if (item.notes.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.notes, size: 12, color: Colors.orange[700]),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                item.notes,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.orange[700],
                                  fontStyle: FontStyle.italic,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                // Quantity controls
                Row(
                  children: [
                    _QuantityButton(
                      icon: Icons.remove,
                      onTap: onDecrement,
                      color: Colors.red,
                    ),
                    Container(
                      constraints: const BoxConstraints(minWidth: 36),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        '${item.quantity}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    _QuantityButton(
                      icon: Icons.add,
                      onTap: onIncrement,
                      color: Colors.green,
                    ),
                  ],
                ),
                // Subtotal
                SizedBox(
                  width: 72,
                  child: Text(
                    '${AppConstants.currencySymbol}${item.subtotal.toStringAsFixed(2)}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.deepPurple,
                    ),
                  ),
                ),
              ],
            ),
            // Add note button
            if (item.notes.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: InkWell(
                  onTap: () => _showNotesDialog(context),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit_note, size: 14, color: Colors.grey[400]),
                      const SizedBox(width: 4),
                      Text(
                        'Add note',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[400],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showNotesDialog(BuildContext context) {
    final controller = TextEditingController(text: item.notes);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.notes, color: Colors.orange),
            const SizedBox(width: 8),
            Text('Note for ${item.name}'),
          ],
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'E.g. No onions, Extra spicy...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              onNotesChanged(controller.text);
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// ── Quantity Button ────────────────────────────────────────────
class _QuantityButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  const _QuantityButton({
    required this.icon,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Icon(icon, size: 16, color: color),
      ),
    );
  }
}

// ── Floor Plan Dialog ───────────────────────────────────────
class _FloorPlanDialog extends StatefulWidget {
  final void Function(String tableId, String tableName) onSelect;
  final void Function(String tableId, String tableName) onOccupiedTableTap;

  const _FloorPlanDialog({
    required this.onSelect,
    required this.onOccupiedTableTap,
  });

  @override
  State<_FloorPlanDialog> createState() => _FloorPlanDialogState();
}

class _FloorPlanDialogState extends State<_FloorPlanDialog> {
  String _selectedFloor = 'All';

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 700,
        height: 520,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.map_outlined,
                      color: Colors.deepPurple, size: 24),
                ),
                const SizedBox(width: 14),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Floor Plan',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold)),
                    Text('Tap an available table to select',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
                const Spacer(),
                // Legend
                _buildLegendDot(Colors.green, 'Available'),
                const SizedBox(width: 12),
                _buildLegendDot(Colors.red, 'Occupied'),
                const SizedBox(width: 12),
                _buildLegendDot(Colors.orange, 'Reserved'),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // ── Floor Plan Grid (cross-reference active orders) ──
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                // Stream of active dine-in orders that have a tableId
                stream: _getActiveTableOrdersStream(context),
                builder: (context, ordersSnapshot) {
                  // Build set of occupied table IDs from active orders
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
                    stream: _getTablesStream(context),
                    builder: (context, AsyncSnapshot snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting &&
                          !snapshot.hasData) {
                        return const Center(
                            child: CircularProgressIndicator(
                                color: Colors.deepPurple));
                      }

                      if (!snapshot.hasData || snapshot.data == null) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.table_bar,
                                  size: 64, color: Colors.grey[300]),
                              const SizedBox(height: 16),
                              const Text('No tables configured',
                                  style: TextStyle(
                                      fontSize: 16, color: Colors.grey)),
                              const SizedBox(height: 8),
                              Text('Set up tables in Settings',
                                  style: TextStyle(
                                      fontSize: 13, color: Colors.grey[400])),
                            ],
                          ),
                        );
                      }

                      final branchData =
                          snapshot.data!.data() as Map<String, dynamic>?;
                      final tables =
                          (branchData?['Tables'] ?? branchData?['tables'])
                                  as Map<String, dynamic>? ??
                              {};

                      if (tables.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.table_bar,
                                  size: 64, color: Colors.grey[300]),
                              const SizedBox(height: 16),
                              const Text('No tables found',
                                  style: TextStyle(
                                      fontSize: 16, color: Colors.grey)),
                            ],
                          ),
                        );
                      }

                      final tableEntries = tables.entries.toList()
                        ..sort((a, b) => (a.value['name'] ?? a.key)
                            .toString()
                            .compareTo(
                                (b.value['name'] ?? b.key).toString()));

                      // Extract unique zones/floors
                      final zones = <String>{'All'};
                      for (final entry in tableEntries) {
                        final zone =
                            (entry.value as Map<String, dynamic>)['zone']
                                    ?.toString() ??
                                (entry.value
                                        as Map<String, dynamic>)['floor']
                                    ?.toString() ??
                                '';
                        if (zone.isNotEmpty) zones.add(zone);
                      }

                      // Filter by selected floor/zone
                      final filtered = _selectedFloor == 'All'
                          ? tableEntries
                          : tableEntries.where((e) {
                              final data =
                                  e.value as Map<String, dynamic>;
                              final zone = data['zone']?.toString() ??
                                  data['floor']?.toString() ??
                                  '';
                              return zone == _selectedFloor;
                            }).toList();

                      return Column(
                        children: [
                          // Zone/Floor tabs
                          if (zones.length > 1)
                            SizedBox(
                              height: 38,
                              child: ListView(
                                scrollDirection: Axis.horizontal,
                                children: zones.map((zone) {
                                  final isSelected =
                                      _selectedFloor == zone;
                                  return Padding(
                                    padding:
                                        const EdgeInsets.only(right: 8),
                                    child: FilterChip(
                                      showCheckmark: false,
                                      label: Text(zone),
                                      selected: isSelected,
                                      selectedColor: Colors.deepPurple,
                                      labelStyle: TextStyle(
                                        color: isSelected
                                            ? Colors.white
                                            : Colors.grey[700],
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.w500,
                                        fontSize: 12,
                                      ),
                                      onSelected: (_) => setState(
                                          () => _selectedFloor = zone),
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(20),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          if (zones.length > 1)
                            const SizedBox(height: 12),
                          // Tables grid
                          Expanded(
                            child: GridView.builder(
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 4,
                                crossAxisSpacing: 14,
                                mainAxisSpacing: 14,
                                childAspectRatio: 1.1,
                              ),
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final entry = filtered[index];
                                final tableData =
                                    entry.value as Map<String, dynamic>;
                                return _FloorPlanTable(
                                  tableId: entry.key,
                                  tableData: tableData,
                                  occupiedTableIds: occupiedTableIds,
                                  onSelect: widget.onSelect,
                                  onOccupiedTap: widget.onOccupiedTableTap,
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
      ),
    );
  }

  Widget _buildLegendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(fontSize: 11, color: Colors.grey[600])),
      ],
    );
  }

  Stream? _getTablesStream(BuildContext context) {
    try {
      final pos = context.read<PosService>();
      final branchId = pos.activeBranchId ?? '';
      if (branchId.isEmpty) return null;
      return FirebaseFirestore.instance
          .collection('Branch')
          .doc(branchId)
          .snapshots();
    } catch (e) {
      return null;
    }
  }

  /// Query active orders that occupy tables (dine-in orders that are not yet
  /// paid/collected/delivered/cancelled).
  Stream<QuerySnapshot<Map<String, dynamic>>>? _getActiveTableOrdersStream(
      BuildContext context) {
    try {
      final pos = context.read<PosService>();
      final branchId = pos.activeBranchId ?? '';
      if (branchId.isEmpty) return null;
      return FirebaseFirestore.instance
          .collection(AppConstants.collectionOrders)
          .where('branchIds', arrayContains: branchId)
          .where('Order_type', isEqualTo: 'dine_in')
          .where('status', whereIn: [
            AppConstants.statusPending,
            AppConstants.statusPreparing,
            AppConstants.statusPrepared,
            AppConstants.statusServed,
          ])
          .snapshots();
    } catch (e) {
      return null;
    }
  }
}

// ── Individual Floor Plan Table Shape ───────────────────────────
class _FloorPlanTable extends StatelessWidget {
  final String tableId;
  final Map<String, dynamic> tableData;
  final Set<String> occupiedTableIds;
  final void Function(String tableId, String tableName) onSelect;
  final void Function(String tableId, String tableName) onOccupiedTap;

  const _FloorPlanTable({
    required this.tableId,
    required this.tableData,
    required this.occupiedTableIds,
    required this.onSelect,
    required this.onOccupiedTap,
  });

  @override
  Widget build(BuildContext context) {
    final tableName = tableData['name']?.toString() ?? tableId;
    final seats = tableData['seats'];
    final shape = (tableData['shape'] ?? 'rectangle').toString().toLowerCase();

    // Determine real-time status by checking active orders
    final bool isOccupiedByOrder = occupiedTableIds.contains(tableId);
    final staticStatus =
        (tableData['status'] ?? 'available').toString().toLowerCase();
    final isReserved = staticStatus == 'reserved';
    final isAvailable = !isOccupiedByOrder && !isReserved && staticStatus != 'occupied';

    // Color coding
    Color borderColor;
    Color bgColor;
    Color textColor;
    if (isAvailable) {
      borderColor = Colors.green;
      bgColor = Colors.green.withOpacity(0.08);
      textColor = Colors.green[800]!;
    } else if (isReserved) {
      borderColor = Colors.orange;
      bgColor = Colors.orange.withOpacity(0.08);
      textColor = Colors.orange[800]!;
    } else {
      borderColor = Colors.red;
      bgColor = Colors.red.withOpacity(0.08);
      textColor = Colors.red[800]!;
    }

    final isRound = shape == 'circle' || shape == 'round';

    return Tooltip(
      message: isAvailable
          ? 'Tap to select'
          : isReserved
              ? 'Reserved'
              : 'Occupied',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isAvailable
              ? () => onSelect(tableId, tableName)
              : (isOccupiedByOrder && !isReserved)
                  ? () => onSelect(tableId, tableName)
                  : null,
          borderRadius: BorderRadius.circular(isRound ? 100 : 16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius:
                  BorderRadius.circular(isRound ? 100 : 16),
              border: Border.all(color: borderColor, width: 2),
              boxShadow: isAvailable
                  ? [
                      BoxShadow(
                        color: Colors.green.withOpacity(0.15),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      )
                    ]
                : null,
            ),
            child: Stack(
              children: [
                if (isOccupiedByOrder && !isReserved) ...[
                  // ── Pay Now Button ──
                  Positioned(
                    top: 2,
                    left: 2,
                    child: Material(
                      color: Colors.transparent,
                      child: IconButton(
                        icon: const Icon(Icons.payment, size: 16),
                        color: Colors.green[700],
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                        tooltip: 'Pay Now',
                        onPressed: () async {
                          final userScope = context.read<UserScopeService>();
                          double existingTableTotal = 0.0;
                          List<QueryDocumentSnapshot> existingOrders = [];

                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) => const Center(
                              child: CircularProgressIndicator(color: Colors.deepPurple),
                            ),
                          );

                          try {
                            final pos = context.read<PosService>();
                            final snapshot = await FirebaseFirestore.instance
                                .collection(AppConstants.collectionOrders)
                                .where('branchIds', arrayContains: pos.activeBranchId ?? '')
                                .where('tableId', isEqualTo: tableId)
                                .where('Order_type', isEqualTo: 'dine_in')
                                .where('status', whereIn: [
                                  AppConstants.statusPending,
                                  AppConstants.statusPreparing,
                                  AppConstants.statusPrepared,
                                  AppConstants.statusServed,
                                ])
                                .get();

                            existingOrders = snapshot.docs;
                            for (final doc in existingOrders) {
                              final data = doc.data() as Map<String, dynamic>;
                              existingTableTotal += (data['totalAmount'] ?? 0).toDouble();
                            }
                          } catch (e) {
                            debugPrint('Error fetching orders for quick pay: $e');
                          } finally {
                            if (context.mounted) Navigator.pop(context); // Close loading
                          }

                          if (existingOrders.isEmpty || !context.mounted) return;

                          // Close Floor Plan Dialog before opening Payment Dialog
                          Navigator.pop(context);

                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (ctx) => ChangeNotifierProvider.value(
                              value: context.read<PosService>(),
                              child: PosPaymentDialog(
                                totalAmount: 0.0,
                                branchIds: [existingOrders.first.get('branchIds')[0] ?? ''],
                                existingTableTotal: existingTableTotal,
                                existingOrders: existingOrders,
                                returnPaymentOnly: false,
                                onPaymentComplete: (orderId) {
                                  if (orderId != null) {
                                    // Let print button handle printing now
                                    showDialog(
                                      context: context,
                                      barrierDismissible: false,
                                      builder: (promptCtx) => AlertDialog(
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                        title: Row(
                                          children: [
                                            Icon(Icons.check_circle, color: Colors.green[600]),
                                            const SizedBox(width: 10),
                                            const Text('Payment Successful'),
                                          ],
                                        ),
                                        content: const Text('Do you want to print the receipt?'),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(promptCtx),
                                            child: const Text('No'),
                                          ),
                                          ElevatedButton.icon(
                                            onPressed: () {
                                              Navigator.pop(promptCtx);
                                              PrintingService.printReceipt(context, existingOrders.first);
                                            },
                                            icon: const Icon(Icons.print, size: 18),
                                            label: const Text('Print Receipt'),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.deepPurple,
                                              foregroundColor: Colors.white,
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                },
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  // ── Print Now Button ──
                  Positioned(
                    top: 2,
                    right: 2,
                    child: Material(
                      color: Colors.transparent,
                      child: IconButton(
                        icon: const Icon(Icons.print, size: 16),
                        color: Colors.blue[700],
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                        tooltip: 'Print Invoice',
                        onPressed: () async {
                          final userScope = context.read<UserScopeService>();
                          try {
                            final pos = context.read<PosService>();
                            final snapshot = await FirebaseFirestore.instance
                                .collection(AppConstants.collectionOrders)
                                .where('branchIds', arrayContains: pos.activeBranchId ?? '')
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
                              PrintingService.printReceipt(context, snapshot.docs.first);
                            } else if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('No active orders found to print.')),
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
                ],
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                // Table icon
                Icon(
                  isRound
                      ? Icons.circle_outlined
                      : Icons.table_bar,
                  color: borderColor,
                  size: 30,
                ),
                const SizedBox(height: 6),
                // Table name
                Text(
                  tableName,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                // Seat count
                if (seats != null) ...[
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.person, size: 12, color: textColor),
                      const SizedBox(width: 2),
                      Text(
                        '$seats',
                        style: TextStyle(fontSize: 11, color: textColor),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 2),
                // Status label
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: borderColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isAvailable
                        ? 'Available'
                        : isReserved
                            ? 'Reserved'
                            : 'Occupied',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
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
