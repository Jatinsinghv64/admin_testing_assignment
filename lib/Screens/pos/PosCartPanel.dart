// lib/Screens/pos/PosCartPanel.dart
// Cart panel widget for the POS screen (right side)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../main.dart';
import '../../constants.dart';
import '../../Widgets/BranchFilterService.dart';
import '../../services/pos/pos_service.dart';
import '../../services/pos/pos_models.dart';
import '../../Widgets/PrintingService.dart';
import 'TableOrdersDialog.dart';
import 'pos_payment_dialog.dart';

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
          color: Theme.of(context).brightness == Brightness.dark ? Colors.white.withOpacity(0.02) : Theme.of(context).cardColor,
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
              color: Theme.of(context).cardColor.withValues(alpha: 0.7),
              child: Center(
                child: CircularProgressIndicator(
                  color:
                      widget.isSubmittingOrder ? Colors.deepPurple : Colors.red,
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
            color: Colors.amber.withValues(alpha: 0.15),
            child: Row(
              children: [
                Icon(Icons.playlist_add, size: 16, color: Colors.amber[800]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Adding to existing order on ${pos.selectedTableName ?? 'Table'}',
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
                  icon: const Icon(Icons.cancel_outlined,
                      size: 14, color: Colors.red),
                  label: const Text(
                    'Cancel Order',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.red),
                  ),
                  style: TextButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    backgroundColor: Colors.red.withValues(alpha: 0.1),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6)),
                  ),
                ),
              ],
            ),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Theme.of(context).scaffoldBackgroundColor,
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
                  color: Colors.deepPurple.withValues(alpha: 0.1),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.delete_sweep,
                          size: 14, color: Colors.red[400]),
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
                color: Colors.red.withValues(alpha: 0.1),
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
            child:
                Text('Clear All', style: TextStyle(color: Theme.of(context).cardColor)),
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
            Flexible(
              child: InkWell(
                onTap: () => _showTableSelector(context, pos),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: pos.selectedTableId != null
                        ? Colors.red.withValues(alpha: 0.1)
                        : Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: pos.selectedTableId != null
                          ? Colors.red.withValues(alpha: 0.3)
                          : Colors.orange.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.table_bar,
                        size: pos.selectedTableId != null ? 18 : 14,
                        color: pos.selectedTableId != null
                            ? Colors.red
                            : Colors.orange,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                pos.selectedTableName != null
                                    ? 'Taking Order for ${pos.selectedTableName}${pos.guestCount != null && pos.guestCount! > 0 ? ' (${pos.guestCount} Guests)' : ''}'
                                    : 'Select Table',
                                style: TextStyle(
                                  fontSize: pos.selectedTableId != null ? 14 : 12,
                                  fontWeight: FontWeight.bold,
                                  color: pos.selectedTableId != null
                                      ? Colors.red
                                      : Colors.orange,
                                ),
                                overflow: TextOverflow.ellipsis,
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
            // ── Table Change Button (only when table is active) ──
            if (pos.selectedTableId != null) ...[
              const SizedBox(width: 8),
              Tooltip(
                message: 'Change Table',
                child: InkWell(
                  onTap: () => _showTableChangeDialog(context, pos),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: Colors.blueGrey.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.swap_horiz,
                            size: 18, color: Colors.blueGrey),
                        SizedBox(width: 4),
                        Text(
                          'Table Change',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.blueGrey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
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
          _buildSectionHeader(
              'Ongoing Order', Icons.hourglass_top_rounded, Colors.amber[800]!),
          ...pos.ongoingOrders.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final items = List<Map<String, dynamic>>.from(data['items'] ?? []);
            final orderStatus =
                data['status']?.toString() ?? AppConstants.statusPending;
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
          _buildSectionHeader('In Cart (New Items)',
              Icons.shopping_cart_outlined, Colors.deepPurple),
          _buildCartItemsList(context, pos),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: color.withValues(alpha: 0.05),
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
        color: Theme.of(context).scaffoldBackgroundColor,
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
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        children: [
          if (!pos.isEmpty) _buildSummaryRow('Subtotal', pos.subtotal),
          if (pos.isAppendMode)
            _buildSummaryRow('Ongoing Total', pos.ongoingTotal,
                color: Colors.amber[900]),
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
              Text(
                'Total',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).textTheme.bodyLarge?.color?.withOpacity(0.87),
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
    final needsTable =
        pos.orderType == PosOrderType.dineIn && pos.selectedTableId == null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark ? Colors.white.withOpacity(0.02) : Theme.of(context).cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
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
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 16, color: Colors.orange[700]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Select a Table before placing a dine-in order',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.orange[800]),
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
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white)))
                        : Icon(
                            needsTable
                                ? Icons.table_bar
                                : Icons.restaurant_menu,
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
                      backgroundColor:
                          needsTable ? Colors.orange : Colors.deepPurple,
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
                    onPressed:
                        (needsTable || (pos.isEmpty && !pos.isAppendMode))
                            ? null
                            : widget.onPaymentTap,
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
    final phoneController =
        TextEditingController(text: pos.customerPhone ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.deepPurple.withValues(alpha: 0.1),
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
                phone:
                    phoneController.text.isEmpty ? null : phoneController.text,
              );
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Save', style: TextStyle(color: Theme.of(context).cardColor)),
          ),
        ],
      ),
    );
  }

  Future<void> _showTableSelector(BuildContext context, PosService pos) async {
    final userScope = context.read<UserScopeService>();
    final branchFilter = context.read<BranchFilterService>();
    final visibleBranchIds =
        branchFilter.getFilterBranchIds(userScope.branchIds);
    String? activeBranchId = pos.activeBranchId;

    if (activeBranchId == null || activeBranchId.isEmpty) {
      if (visibleBranchIds.length == 1) {
        activeBranchId = visibleBranchIds.first;
      } else if (visibleBranchIds.length > 1) {
        activeBranchId = await _pickPosBranch(context, visibleBranchIds);
      }
    }

    if (!context.mounted) return;
    if (activeBranchId == null || activeBranchId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select a branch before choosing a Table.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final resolvedBranchId = activeBranchId;

    if (pos.activeBranchId != resolvedBranchId) {
      pos.setActiveBranch(resolvedBranchId);
    }

    showDialog(
      context: context,
      builder: (dialogContext) => ChangeNotifierProvider.value(
        value: pos,
        child: _FloorPlanDialog(
          onSelect: (tableId, tableName) async {
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
                            Text('$guestCount',
                                style: const TextStyle(
                                    fontSize: 24, fontWeight: FontWeight.bold)),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: () =>
                                  setDialogState(() => guestCount++),
                            ),
                          ],
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel')),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepPurple,
                            foregroundColor: Colors.white),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Proceed'),
                      ),
                    ],
                  );
                },
              ),
            );

            if (confirmed == true && context.mounted) {
              pos.loadTableContext(tableId, tableName,
                  guestCount: guestCount, branchIds: [resolvedBranchId]);
              if (dialogContext.mounted) {
                Navigator.pop(dialogContext);
              }
            }
          },
          onOccupiedTableTap: (tableId, tableName) {
            // Directly load table context — no redundant dialog
            pos.loadTableContext(tableId, tableName,
                branchIds: [resolvedBranchId]).catchError((e) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Could not load Table order: $e'),
                  backgroundColor: Colors.red,
                ),
              );
            });
            if (dialogContext.mounted) Navigator.pop(dialogContext);
          },
        ),
      ),
    );
  }

  /// Transfer active orders from the currently selected table to a different
  /// available table. Stores `previousTableName`/`previousTableId` for KDS
  /// audit trail and updates branch floor plan statuses atomically.
  Future<void> _showTableChangeDialog(
      BuildContext context, PosService pos) async {
    final currentTableId = pos.selectedTableId;
    final currentTableName = pos.selectedTableName ?? 'Current';
    final branchId = pos.activeBranchId;
    if (currentTableId == null || branchId == null) return;

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Colors.deepPurple),
      ),
    );

    try {
      final branchSnap = await FirebaseFirestore.instance
          .collection('Branch')
          .doc(branchId)
          .get()
          .timeout(AppConstants.firestoreTimeout);

      if (!context.mounted) return;
      Navigator.pop(context); // close loading

      final tablesMap =
          branchSnap.data()?['Tables'] as Map<String, dynamic>? ?? {};

      // Get available tables (exclude current)
      final availableTables = tablesMap.entries.where((e) {
        final status =
            (e.value['status'] ?? 'available').toString().toLowerCase();
        return status == 'available' && e.key != currentTableId;
      }).toList();

      if (availableTables.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No available tables to transfer to.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      if (!context.mounted) return;

      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child:
                    const Icon(Icons.swap_horiz, color: Colors.blueGrey),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Transfer Table',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    Text('From $currentTableName',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey[600])),
                  ],
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 340,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: availableTables.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: Theme.of(context).dividerColor),
              itemBuilder: (ctx, i) {
                final t = availableTables[i];
                final tName =
                    t.value['name']?.toString() ?? 'Table ${t.key}';
                final seats = t.value['seats']?.toString();
                return ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.table_bar,
                        color: Colors.green, size: 20),
                  ),
                  title: Text(tName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600)),
                  subtitle: seats != null
                      ? Text('$seats seats',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[500]))
                      : null,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  onTap: () async {
                    // Show transferring indicator
                    Navigator.pop(ctx);
                    if (!context.mounted) return;

                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => const Center(
                        child: CircularProgressIndicator(
                            color: Colors.deepPurple),
                      ),
                    );

                    try {
                      // Fetch active orders for current table
                      final ordersSnap = await FirebaseFirestore.instance
                          .collection(AppConstants.collectionOrders)
                          .where('branchIds',
                              arrayContains: branchId)
                          .where('tableId',
                              isEqualTo: currentTableId)
                          .where('Order_type',
                              isEqualTo: 'dine_in')
                          .where('status', whereIn: [
                            AppConstants.statusPending,
                            AppConstants.statusPreparing,
                            AppConstants.statusPrepared,
                            AppConstants.statusServed,
                          ])
                          .get()
                          .timeout(AppConstants.firestoreTimeout);

                      if (ordersSnap.docs.isEmpty) {
                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                  'No active orders to transfer.'),
                              backgroundColor: Colors.orange,
                            ),
                          );
                        }
                        return;
                      }

                      // Batch: update orders + floor plan statuses
                      final batch =
                          FirebaseFirestore.instance.batch();
                      for (final doc in ordersSnap.docs) {
                        batch.update(doc.reference, {
                          'tableId': t.key,
                          'tableName': tName,
                          'previousTableId': currentTableId,
                          'previousTableName': currentTableName,
                          'tableTransferredAt':
                              FieldValue.serverTimestamp(),
                        });
                      }

                      // Update floor plan statuses
                      batch.update(branchSnap.reference, {
                        'Tables.${t.key}.status': 'occupied',
                        'Tables.$currentTableId.status':
                            'available',
                      });

                      await batch.commit();

                      // Update POS context to new table
                      await pos.loadTableContext(
                        t.key,
                        tName,
                        branchIds: [branchId],
                      );

                      if (context.mounted) {
                        Navigator.pop(context); // close loading
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                                'Transferred to $tName'),
                            backgroundColor: Colors.green,
                            duration:
                                const Duration(seconds: 2),
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        Navigator.pop(context); // close loading
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content:
                                Text('Transfer failed: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.grey)),
            ),
          ],
        ),
      );
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // close loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<String?> _pickPosBranch(BuildContext context, List<String> branchIds) {
    final branchFilter = context.read<BranchFilterService>();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Choose branch'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: branchIds.map((branchId) {
              return ListTile(
                leading: const Icon(Icons.storefront_outlined,
                    color: Colors.deepPurple),
                title: Text(branchFilter.getBranchName(branchId)),
                onTap: () => Navigator.pop(dialogContext, branchId),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmCancelOngoingOrder(
      BuildContext context, PosService pos) async {
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

    if (confirmed == true) {
      if (!context.mounted) return;
      // Local status check to avoid masked exception issues on Web
      for (final doc in pos.ongoingOrders) {
        final data = doc.data() as Map<String, dynamic>;
        final status = data['status']?.toString() ?? '';
        if (status == AppConstants.statusPrepared ||
            status == AppConstants.statusServed) {
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
            const SnackBar(
                content: Text('Order cancelled successfully'),
                backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Failed to cancel order: $e'),
                backgroundColor: Colors.red),
          );
        }
      } finally {
        _setLoading(false);
      }
    }
  }

  static void _showRestrictedActionDialog(
      BuildContext context, String message) {
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
            child: Text('OK', style: TextStyle(color: Theme.of(context).cardColor)),
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
              : Colors.deepPurple.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? Colors.deepPurple
                : Colors.deepPurple.withValues(alpha: 0.15),
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
              color: Theme.of(context).scaffoldBackgroundColor,
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
                if (item['notes'] != null &&
                    item['notes'].toString().isNotEmpty)
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
            icon: const Icon(Icons.delete_outline,
                size: 16, color: Colors.redAccent),
            tooltip: 'Remove Item',
            constraints: const BoxConstraints(),
            padding: const EdgeInsets.all(4),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRemoveOngoingItem(
      BuildContext context, PosService pos, UserScopeService userScope) async {
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

    if (confirmed == true) {
      if (!context.mounted) return;
      // Local status check to avoid masked exception issues on Web
      if (orderStatus == AppConstants.statusPrepared ||
          orderStatus == AppConstants.statusServed) {
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
            const SnackBar(
                content: Text('Item removed successfully'),
                backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Failed to remove item: $e'),
                backgroundColor: Colors.red),
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
        child: Icon(Icons.delete_outline, color: Theme.of(context).cardColor),
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
                            Icon(Icons.notes,
                                size: 12, color: Colors.orange[700]),
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
            child: Text('Save', style: TextStyle(color: Theme.of(context).cardColor)),
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
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
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
                    color: Colors.deepPurple.withValues(alpha: 0.1),
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
                      final tables = (branchData?['Tables'] ??
                              branchData?['tables']) as Map<String, dynamic>? ??
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
                            .compareTo((b.value['name'] ?? b.key).toString()));

                      // Extract unique zones/floors
                      final zones = <String>{'All'};
                      for (final entry in tableEntries) {
                        final zone =
                            (entry.value as Map<String, dynamic>)['zone']
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
                        children: [
                          // Zone/Floor tabs
                          if (zones.length > 1)
                            SizedBox(
                              height: 38,
                              child: ListView(
                                scrollDirection: Axis.horizontal,
                                children: zones.map((zone) {
                                  final isSelected = _selectedFloor == zone;
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8),
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
                                      onSelected: (_) =>
                                          setState(() => _selectedFloor = zone),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          if (zones.length > 1) const SizedBox(height: 12),
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
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
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
      ]).snapshots();
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
    final seatsRaw = tableData['seats'];
    final int? seats =
        seatsRaw != null ? int.tryParse(seatsRaw.toString()) : null;
    final shape = (tableData['shape'] ?? 'rectangle').toString().toLowerCase();

    final tableStatus = (tableData['status'] ?? 'available').toString().toLowerCase();
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

    if (isDirty) {
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

    return Tooltip(
      message: isDirty
          ? 'Needs Bussing — tap to clean'
          : isAvailable
              ? 'Tap to select'
              : isReserved
                  ? 'Reserved'
                  : 'Occupied',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            if (isDirty) {
              final clean = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Row(
                    children: [
                      Icon(Icons.cleaning_services, color: Colors.brown[800]),
                      const SizedBox(width: 8),
                      const Text('Table Needs Cleaning'),
                    ],
                  ),
                  content: Text('Table $tableName needs bussing.\n\nMark it as clean and make it available?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('No'),
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
                  title: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: Colors.orange[800]),
                      const SizedBox(width: 8),
                      const Text('Table Reserved'),
                    ],
                  ),
                  content: Text(
                      'Table $tableName is marked as reserved.\n\nUse anyway?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white),
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
          borderRadius: BorderRadius.circular(isRound ? 100 : 16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(isRound ? 100 : 16),
              border: Border.all(color: borderColor, width: 2),
              boxShadow: isAvailable
                  ? [
                      BoxShadow(
                        color: Colors.green.withValues(alpha: 0.15),
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
                        constraints:
                            const BoxConstraints(minWidth: 24, minHeight: 24),
                        tooltip: 'Pay Now',
                        onPressed: () async {
                          double existingTableTotal = 0.0;
                          List<QueryDocumentSnapshot> existingOrders = [];

                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) => const Center(
                              child: CircularProgressIndicator(
                                  color: Colors.deepPurple),
                            ),
                          );

                          try {
                            final pos = context.read<PosService>();
                            final snapshot = await FirebaseFirestore.instance
                                .collection(AppConstants.collectionOrders)
                                .where('branchIds',
                                    arrayContains: pos.activeBranchId ?? '')
                                .where('tableId', isEqualTo: tableId)
                                .where('Order_type', isEqualTo: 'dine_in')
                                .where('status', whereIn: [
                              AppConstants.statusPending,
                              AppConstants.statusPreparing,
                              AppConstants.statusPrepared,
                              AppConstants.statusServed,
                            ]).get();

                            existingOrders = snapshot.docs;
                            for (final doc in existingOrders) {
                              final data = doc.data() as Map<String, dynamic>;
                              existingTableTotal +=
                                  PosService.getOutstandingAmount(data);
                            }
                          } catch (e) {
                            debugPrint(
                                'Error fetching orders for quick pay: $e');
                          } finally {
                            if (context.mounted)
                              Navigator.pop(context); // Close loading
                          }

                          if (existingOrders.isEmpty || !context.mounted)
                            return;
                          if (existingTableTotal <= 0.001) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'All active orders on this table are already prepaid.'),
                                backgroundColor: Colors.orange,
                              ),
                            );
                            return;
                          }

                          // 🛠️ FIX: Capture root navigator context BEFORE popping the Floor Plan dialog
                          final navContext =
                              Navigator.of(context, rootNavigator: true)
                                  .context;
                          final posService = context.read<PosService>();

                          // Close Floor Plan Dialog before opening Payment Dialog
                          Navigator.pop(context);

                          showDialog(
                            context: navContext,
                            barrierDismissible: false,
                            builder: (ctx) => ChangeNotifierProvider.value(
                              value: posService,
                              child: PosPaymentDialog(
                                totalAmount: 0.0,
                                branchIds: [
                                  existingOrders.first.get('branchIds')[0] ?? ''
                                ],
                                existingTableTotal: existingTableTotal,
                                existingOrders: existingOrders,
                                returnPaymentOnly: false,
                                onPaymentComplete: (orderId) {
                                  if (orderId != null) {
                                    // Let print button handle printing now
                                    showDialog(
                                      context: navContext,
                                      barrierDismissible: false,
                                      builder: (promptCtx) => AlertDialog(
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(20)),
                                        title: Row(
                                          children: [
                                            Icon(Icons.check_circle,
                                                color: Colors.green[600]),
                                            const SizedBox(width: 10),
                                            const Text('Payment Successful'),
                                          ],
                                        ),
                                        content: const Text(
                                            'Do you want to print the receipt?'),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(promptCtx),
                                            child: const Text('No'),
                                          ),
                                          ElevatedButton.icon(
                                            onPressed: () {
                                              Navigator.pop(promptCtx);
                                              PrintingService.printReceipt(
                                                  context,
                                                  existingOrders.first);
                                            },
                                            icon: const Icon(Icons.print,
                                                size: 18),
                                            label: const Text('Print Receipt'),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  Colors.deepPurple,
                                              foregroundColor: Colors.white,
                                              shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          10)),
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
                        constraints:
                            const BoxConstraints(minWidth: 24, minHeight: 24),
                        tooltip: 'Print Invoice',
                        onPressed: () async {
                          try {
                            final pos = context.read<PosService>();
                            final snapshot = await FirebaseFirestore.instance
                                .collection(AppConstants.collectionOrders)
                                .where('branchIds',
                                    arrayContains: pos.activeBranchId ?? '')
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
                ],
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Table icon
                      Icon(
                        isRound ? Icons.circle_outlined : Icons.table_bar,
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
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 1,
                          runSpacing: 1,
                          children: [
                            for (int i = 0; i < (seats > 6 ? 6 : seats); i++)
                              Icon(Icons.chair, size: 12, color: textColor),
                            if (seats > 6)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 2, vertical: 1),
                                decoration: BoxDecoration(
                                  color: textColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '+${seats - 6}',
                                  style: TextStyle(
                                      fontSize: 9,
                                      color: textColor,
                                      fontWeight: FontWeight.bold),
                                ),
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
                          color: borderColor.withValues(alpha: 0.15),
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
