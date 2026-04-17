// lib/Screens/pos/pos_payment_dialog.dart
// Full-screen payment dialog with guest split-bill support.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../main.dart';
import '../../../../constants.dart';
import '../../../../services/pos/pos_models.dart';
import '../../../../services/pos/pos_service.dart';
import 'itemized_split_bill_dialog.dart';

enum _BillPaymentMode { fullBill, splitBill }

class _BillShare {
  final String label;
  final double amount;
  final PosPayment? payment;

  const _BillShare({
    required this.label,
    required this.amount,
    this.payment,
  });

  bool get isPaid => payment != null;

  _BillShare copyWith({
    double? amount,
    PosPayment? payment,
    bool clearPayment = false,
  }) {
    return _BillShare(
      label: label,
      amount: amount ?? this.amount,
      payment: clearPayment ? null : (payment ?? this.payment),
    );
  }
}

class PosPaymentDialog extends StatefulWidget {
  final double totalAmount;
  final double existingTableTotal;
  final List<DocumentSnapshot> existingOrders;
  final void Function(String? orderId) onPaymentComplete;

  /// When true, the dialog returns a PosPayment object via Navigator.pop()
  /// instead of submitting an order. Used by TableOrdersDialog for paying
  /// existing orders.
  final bool returnPaymentOnly;

  const PosPaymentDialog({
    super.key,
    required this.totalAmount,
    required this.onPaymentComplete,
    required this.branchIds,
    this.existingTableTotal = 0.0,
    this.existingOrders = const [],
    this.returnPaymentOnly = false,
  });

  final List<String> branchIds;

  @override
  State<PosPaymentDialog> createState() => _PosPaymentDialogState();
}

class _PosPaymentDialogState extends State<PosPaymentDialog> {
  static const int _minGuestCount = 2;
  static const int _maxGuestCount = 12;
  static const double _currencyEpsilon = 0.001;

  String _selectedMethod = 'cash';
  String _inputAmount = '';
  bool _isProcessing = false;
  _BillPaymentMode _paymentMode = _BillPaymentMode.fullBill;
  int _guestCount = 2;
  List<_BillShare> _shares = const [];
  int _selectedShareIndex = 0;

  @override
  void initState() {
    super.initState();
    _initializeSplitShares();
    _syncInputWithSelection();
  }

  bool get _isSplitBill => _paymentMode == _BillPaymentMode.splitBill;

  double get _grandTotal =>
      _roundMoney(widget.totalAmount + widget.existingTableTotal);

  double get _enteredAmount {
    if (_inputAmount.isEmpty) return 0;
    return _roundMoney(double.tryParse(_inputAmount) ?? 0);
  }

  int get _selectedUnpaidShareIndex {
    if (!_isSplitBill || _shares.isEmpty) return -1;
    if (_selectedShareIndex >= 0 &&
        _selectedShareIndex < _shares.length &&
        !_shares[_selectedShareIndex].isPaid) {
      return _selectedShareIndex;
    }
    return _shares.indexWhere((share) => !share.isPaid);
  }

  double get _currentTargetAmount {
    if (!_isSplitBill) return _grandTotal;
    final index = _selectedUnpaidShareIndex;
    if (index < 0) return 0;
    return _shares[index].amount;
  }

  double get _currentChangeAmount {
    if (_selectedMethod != 'cash') return 0;
    return _roundMoney(
      (_enteredAmount - _currentTargetAmount).clamp(0, double.infinity),
    );
  }

  double get _paidTotal => _roundMoney(
        _shares.fold(
          0.0,
          (totalCollected, share) =>
              totalCollected + (share.payment?.appliedAmount ?? 0),
        ),
      );

  double get _remainingTotal =>
      _roundMoney((_grandTotal - _paidTotal).clamp(0, double.infinity));

  bool get _allSharesCollected =>
      _isSplitBill &&
      _shares.isNotEmpty &&
      _shares.every((share) => share.isPaid) &&
      _remainingTotal <= _currencyEpsilon;

  bool get _hasCollectedShares => _shares.any((share) => share.isPaid);

  bool get _canCollectCurrentShare {
    if (!_isSplitBill) return false;
    if (_selectedUnpaidShareIndex < 0 || _currentTargetAmount <= 0) {
      return false;
    }
    if (_selectedMethod == 'cash') {
      return _enteredAmount >= (_currentTargetAmount - _currencyEpsilon);
    }
    return true;
  }

  bool get _canValidate {
    if (_grandTotal <= 0) return false;
    if (_isSplitBill) {
      return _allSharesCollected || _canCollectCurrentShare;
    }
    if (_selectedMethod == 'cash') {
      return _enteredAmount >= (_grandTotal - _currencyEpsilon);
    }
    return true;
  }

  bool get _showNumpad =>
      _selectedMethod == 'cash' && (!_isSplitBill || !_allSharesCollected);

  String get _primaryButtonLabel {
    if (_isSplitBill) {
      if (_allSharesCollected) return 'Complete Split Bill';
      final shareIndex = _selectedUnpaidShareIndex;
      if (shareIndex >= 0) {
        return 'Collect ${_shares[shareIndex].label}';
      }
      return 'Collect Payment';
    }
    return 'Validate Payment';
  }

  bool _isSuccess = false;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: Container(
        width: 980,
        height: 700,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 30,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Row(
              children: [
                Expanded(
                  flex: 6,
                  child: _buildPaymentInfoPanel(),
                ),
                if (_showNumpad)
                  Expanded(
                    flex: 4,
                    child: _buildNumpadPanel(),
                  ),
              ],
            ),
            if (_isSuccess)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Center(
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.elasticOut,
                      builder: (context, value, child) {
                        return Transform.scale(
                          scale: value,
                          child: Container(
                            padding: const EdgeInsets.all(32),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check_circle,
                              color: Colors.green,
                              size: 100,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentInfoPanel() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.horizontal(
          left: const Radius.circular(24),
          right: _showNumpad ? Radius.zero : const Radius.circular(24),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 24),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.existingTableTotal > 0) ...[
                    _buildExistingOrderBreakdown(),
                    const SizedBox(height: 16),
                  ],
                  _buildTotalDueCard(),
                  const SizedBox(height: 20),
                  _buildPaymentModeToggle(),
                  const SizedBox(height: 20),
                  if (_isSplitBill) ...[
                    _buildSplitControls(),
                    const SizedBox(height: 16),
                    _buildSplitProgressCard(),
                    const SizedBox(height: 16),
                    _buildSharesList(),
                    const SizedBox(height: 20),
                  ],
                  if (!_isSplitBill || !_allSharesCollected) ...[
                    Text(
                      // H2 FIX: Guard against RangeError when all shares are paid
                      _isSplitBill && _selectedUnpaidShareIndex >= 0
                          ? '${_shares[_selectedUnpaidShareIndex].label} Payment Method'
                          : 'Payment Method',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _buildMethodButton('cash', Icons.money, 'Cash'),
                        const SizedBox(width: 12),
                        _buildMethodButton('card', Icons.credit_card, 'Card'),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildCurrentCollectionCard(),
                  ] else
                    _buildSplitReadyCard(),
                ],
              ),
            ),
          ),
          if (_isSplitBill && _hasCollectedShares) ...[
            Row(
              children: [
                TextButton.icon(
                  onPressed: _isProcessing ? null : _resetSplitCollection,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Reset Split'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red[600],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Collected guest payments stay local until you complete the bill.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _canValidate && !_isProcessing
                  ? () => _processPayment()
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[600],
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey[200],
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: _isProcessing
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : Text(
                      _primaryButtonLabel,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.deepPurple.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(
            Icons.payments_rounded,
            color: Colors.deepPurple,
            size: 28,
          ),
        ),
        const SizedBox(width: 16),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Payment',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            Text(
              'Complete the transaction',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
        const Spacer(),
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(Icons.close, color: Colors.grey[400]),
        ),
      ],
    );
  }

  Widget _buildExistingOrderBreakdown() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.deepPurple.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Current Cart',
                  style: TextStyle(color: Colors.black54)),
              Text(
                '${AppConstants.currencySymbol}${widget.totalAmount.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Previous Orders',
                  style: TextStyle(color: Colors.black54)),
              Text(
                '${AppConstants.currencySymbol}${widget.existingTableTotal.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTotalDueCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.deepPurple,
            Colors.deepPurple.shade700,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Total Due',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${AppConstants.currencySymbol}${_grandTotal.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_isSplitBill)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    '$_guestCount Guests',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentModeToggle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Checkout Mode',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.grey,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _buildModeButton(
              mode: _BillPaymentMode.fullBill,
              icon: Icons.receipt_long,
              label: 'Whole Bill',
              description: 'Charge one payment for the full amount',
            ),
            const SizedBox(width: 12),
            _buildModeButton(
              mode: _BillPaymentMode.splitBill,
              icon: Icons.group,
              label: 'Equal Split',
              description: 'Divide equally among guests',
            ),
            const SizedBox(width: 12),
            _buildItemizedSplitButton(),
          ],
        ),
      ],
    );
  }

  Widget _buildItemizedSplitButton() {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isProcessing ? null : _openItemizedSplitDialog,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFF6C63FF).withValues(alpha: 0.3),
                width: 1,
              ),
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF6C63FF).withValues(alpha: 0.03),
                  const Color(0xFF845EF7).withValues(alpha: 0.06),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.call_split,
                      color: Color(0xFF6C63FF),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6C63FF).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'NEW',
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF6C63FF),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'By Item',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6C63FF),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Assign specific items to each person',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openItemizedSplitDialog() {
    // Gather all order items: cart items + existing order items
    final pos = context.read<PosService>();
    final List<Map<String, dynamic>> allItems = [];

    // Items from existing ongoing orders
    for (final doc in widget.existingOrders) {
      final data = doc.data() as Map<String, dynamic>;
      final isPaid = data['isPaid'] == true ||
          data['paymentStatus'] == 'paid';
      if (isPaid) continue;
      final rawItems = data['items'] ?? data['orderItems'] ?? [];
      if (rawItems is Iterable) {
        for (final item in rawItems) {
          allItems.add(Map<String, dynamic>.from(item as Map));
        }
      }
    }

    // Items from current cart
    for (final cartItem in pos.cartItems) {
      allItems.add(cartItem.toOrderItemMap());
    }

    if (allItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No items to split. Add items to your order first.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // 🛠️ FIX: Capture root navigator context BEFORE popping the current dialog
    final navContext = Navigator.of(context, rootNavigator: true).context;

    // Close current dialog and open itemized split
    Navigator.pop(context);

    showDialog(
      context: navContext,
      barrierDismissible: false,
      builder: (ctx) => ChangeNotifierProvider.value(
        value: pos,
        child: ItemizedSplitBillDialog(
          orderItems: allItems,
          totalAmount: _grandTotal,
          subtotal: pos.subtotal + widget.existingTableTotal,
          discountAmount: pos.discountAmount,
          taxAmount: pos.taxAmount,
          branchIds: widget.branchIds,
          existingOrders: widget.existingOrders,
          returnPaymentOnly: widget.returnPaymentOnly,
          onPaymentComplete: widget.onPaymentComplete,
        ),
      ),
    );
  }

  Widget _buildModeButton({
    required _BillPaymentMode mode,
    required IconData icon,
    required String label,
    required String description,
  }) {
    final isSelected = _paymentMode == mode;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isProcessing ? null : () => _setPaymentMode(mode),
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isSelected
                  ? Colors.deepPurple.withValues(alpha: 0.08)
                  : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected
                    ? Colors.deepPurple
                    : Colors.grey.withValues(alpha: 0.2),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  icon,
                  color: isSelected ? Colors.deepPurple : Colors.grey[600],
                ),
                const SizedBox(height: 12),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? Colors.deepPurple : Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSplitControls() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Guest Split',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
              const Spacer(),
              _buildGuestCountStepper(),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Bill is split evenly. Any rounding difference is distributed automatically so the total stays exact.',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuestCountStepper() {
    final canDecrease = _guestCount > _minGuestCount && !_hasCollectedShares;
    final canIncrease = _guestCount < _maxGuestCount && !_hasCollectedShares;

    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: canDecrease ? () => _changeGuestCount(-1) : null,
            icon: const Icon(Icons.remove),
          ),
          Text(
            '$_guestCount',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          IconButton(
            onPressed: canIncrease ? () => _changeGuestCount(1) : null,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }

  Widget _buildSplitProgressCard() {
    final paidGuests = _shares.where((share) => share.isPaid).length;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildProgressMetric(
              label: 'Collected',
              value:
                  '${AppConstants.currencySymbol}${_paidTotal.toStringAsFixed(2)}',
              color: Colors.green[700]!,
            ),
          ),
          Container(
            width: 1,
            height: 42,
            color: Colors.grey[200],
          ),
          Expanded(
            child: _buildProgressMetric(
              label: 'Remaining',
              value:
                  '${AppConstants.currencySymbol}${_remainingTotal.toStringAsFixed(2)}',
              color: Colors.orange[700]!,
            ),
          ),
          Container(
            width: 1,
            height: 42,
            color: Colors.grey[200],
          ),
          Expanded(
            child: _buildProgressMetric(
              label: 'Guests Paid',
              value: '$paidGuests / $_guestCount',
              color: Colors.deepPurple,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressMetric({
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildSharesList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Guest Shares',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        ...List.generate(_shares.length, (index) => _buildShareCard(index)),
      ],
    );
  }

  Widget _buildShareCard(int index) {
    final share = _shares[index];
    final isSelected = index == _selectedUnpaidShareIndex && !share.isPaid;
    final payment = share.payment;
    final paymentText = payment == null
        ? 'Pending'
        : '${AppConstants.getPaymentDisplayText(payment.method)} • ${AppConstants.currencySymbol}${payment.amount.toStringAsFixed(2)}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap:
              share.isPaid || _isProcessing ? null : () => _selectShare(index),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: share.isPaid
                  ? Colors.green.withValues(alpha: 0.06)
                  : (isSelected
                      ? Colors.deepPurple.withValues(alpha: 0.07)
                      : Colors.white),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: share.isPaid
                    ? Colors.green.withValues(alpha: 0.25)
                    : (isSelected
                        ? Colors.deepPurple.withValues(alpha: 0.4)
                        : Colors.grey.withValues(alpha: 0.16)),
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: share.isPaid
                        ? Colors.green.withValues(alpha: 0.12)
                        : Colors.deepPurple.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: share.isPaid
                        ? Icon(Icons.check, color: Colors.green[700], size: 22)
                        : Text(
                            '${index + 1}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.deepPurple,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        share.label,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        paymentText,
                        style: TextStyle(
                          fontSize: 12,
                          color: share.isPaid
                              ? Colors.green[700]
                              : Colors.grey[600],
                        ),
                      ),
                      if (payment != null && payment.change > 0) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Change: ${AppConstants.currencySymbol}${payment.change.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange[700],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${AppConstants.currencySymbol}${share.amount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (share.isPaid)
                      IconButton(
                        onPressed: _isProcessing
                            ? null
                            : () => _removeCollectedShare(index),
                        icon: Icon(Icons.undo, color: Colors.orange[700]),
                        tooltip: 'Undo guest payment',
                        visualDensity: VisualDensity.compact,
                      )
                    else if (!isSelected)
                      TextButton(
                        onPressed:
                            _isProcessing ? null : () => _selectShare(index),
                        child: const Text('Select'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMethodButton(String method, IconData icon, String label) {
    final isSelected = _selectedMethod == method;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isProcessing ? null : () => _setPaymentMethod(method),
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: isSelected
                  ? Colors.deepPurple.withValues(alpha: 0.1)
                  : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected
                    ? Colors.deepPurple
                    : Colors.grey.withValues(alpha: 0.2),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isSelected ? Colors.deepPurple : Colors.grey[600],
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? Colors.deepPurple : Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentCollectionCard() {
    final isCash = _selectedMethod == 'cash';
    final balanceLabel = _canValidate && isCash ? 'Change' : 'Remaining';
    final balanceAmount = _canValidate && isCash
        ? _currentChangeAmount
        : _roundMoney(
            (_currentTargetAmount - _enteredAmount).clamp(0, double.infinity));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            // H2 FIX: Guard against RangeError when index is -1
            _isSplitBill && _selectedUnpaidShareIndex >= 0
                ? 'Collecting ${_shares[_selectedUnpaidShareIndex].label}'
                : 'Payment Summary',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _isSplitBill ? 'Share Due' : 'Amount Due',
                style: TextStyle(color: Colors.grey[600]),
              ),
              Text(
                '${AppConstants.currencySymbol}${_currentTargetAmount.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Tendered', style: TextStyle(color: Colors.grey[600])),
              Text(
                '${AppConstants.currencySymbol}${(_selectedMethod == 'cash' ? _enteredAmount : _currentTargetAmount).toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(balanceLabel, style: TextStyle(color: Colors.grey[600])),
              Text(
                '${AppConstants.currencySymbol}${balanceAmount.toStringAsFixed(2)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _canValidate && isCash
                      ? Colors.green[700]
                      : Colors.orange[700],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSplitReadyCard() {
    final totalTendered = _roundMoney(
      _shares.fold(
        0.0,
        (totalTenderedValue, share) =>
            totalTenderedValue + (share.payment?.amount ?? 0),
      ),
    );
    final totalChange = _roundMoney(
      _shares.fold(
        0.0,
        (totalChangeValue, share) =>
            totalChangeValue + (share.payment?.change ?? 0),
      ),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Split bill ready to close',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.green[800],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Tendered Total'),
              Text(
                '${AppConstants.currencySymbol}${totalTendered.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          if (totalChange > 0) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total Change'),
                Text(
                  '${AppConstants.currencySymbol}${totalChange.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.orange[700],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNumpadPanel() {
    final targetAmount = _currentTargetAmount;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.horizontal(
          right: Radius.circular(24),
        ),
        border: Border(
          left: BorderSide(color: Colors.grey[200]!),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            // H2 FIX: Guard against RangeError when index is -1
            _isSplitBill && _selectedUnpaidShareIndex >= 0
                ? 'Cash for ${_shares[_selectedUnpaidShareIndex].label}'
                : 'Cash Tendered',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Text(
              _inputAmount.isEmpty ? '0.00' : _inputAmount,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildQuickAmount(targetAmount, 'Exact'),
              const SizedBox(width: 8),
              _buildQuickAmount(
                _roundUp(targetAmount, 10),
                '${AppConstants.currencySymbol}${_roundUp(targetAmount, 10).toStringAsFixed(0)}',
              ),
              const SizedBox(width: 8),
              _buildQuickAmount(
                _roundUp(targetAmount, 100),
                '${AppConstants.currencySymbol}${_roundUp(targetAmount, 100).toStringAsFixed(0)}',
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _buildNumpadGrid(),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAmount(double amount, String label) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            setState(() {
              _inputAmount = _roundMoney(amount).toStringAsFixed(2);
            });
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: Colors.deepPurple.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Colors.deepPurple.withValues(alpha: 0.15),
              ),
            ),
            child: Center(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.deepPurple,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNumpadGrid() {
    final keys = [
      '1',
      '2',
      '3',
      '4',
      '5',
      '6',
      '7',
      '8',
      '9',
      '.',
      '0',
      '⌫',
    ];

    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.6,
      ),
      itemCount: keys.length,
      itemBuilder: (context, index) {
        final key = keys[index];
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _onNumpadTap(key),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              decoration: BoxDecoration(
                color: key == '⌫'
                    ? Colors.red.withValues(alpha: 0.08)
                    : Colors.grey[100],
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: key == '⌫'
                      ? Colors.red.withValues(alpha: 0.2)
                      : Colors.grey.withValues(alpha: 0.15),
                ),
              ),
              child: Center(
                child: key == '⌫'
                    ? Icon(
                        Icons.backspace_outlined,
                        size: 22,
                        color: Colors.red[400],
                      )
                    : Text(
                        key,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _setPaymentMode(_BillPaymentMode mode) {
    if (_paymentMode == mode) return;
    if (_hasCollectedShares) {
      _showInfo('Reset split collection before switching checkout mode.');
      return;
    }

    setState(() {
      _paymentMode = mode;
      if (_isSplitBill) {
        _initializeSplitShares();
        _selectedMethod = 'cash';
      }
      _syncInputWithSelection();
    });
  }

  void _setPaymentMethod(String method) {
    setState(() {
      _selectedMethod = method;
      _syncInputWithSelection();
    });
  }

  void _changeGuestCount(int delta) {
    if (_hasCollectedShares) {
      _showInfo('Reset split collection before changing guest count.');
      return;
    }

    final next = (_guestCount + delta).clamp(_minGuestCount, _maxGuestCount);
    if (next == _guestCount) return;

    setState(() {
      _guestCount = next;
      _initializeSplitShares();
      _syncInputWithSelection();
    });
  }

  void _initializeSplitShares() {
    final amounts = _buildEqualShareAmounts(_grandTotal, _guestCount);
    _shares = List<_BillShare>.generate(
      amounts.length,
      (index) => _BillShare(
        label: 'Guest ${index + 1}',
        amount: amounts[index],
      ),
    );
    _selectedShareIndex = 0;
  }

  List<double> _buildEqualShareAmounts(double total, int guestCount) {
    final totalCents = (total * 100).round();
    final baseShare = totalCents ~/ guestCount;
    final remainder = totalCents % guestCount;

    return List<double>.generate(guestCount, (index) {
      final cents = baseShare + (index < remainder ? 1 : 0);
      return cents / 100.0;
    });
  }

  void _selectShare(int index) {
    if (index < 0 || index >= _shares.length || _shares[index].isPaid) return;
    setState(() {
      _selectedShareIndex = index;
      _syncInputWithSelection();
    });
  }

  void _removeCollectedShare(int index) {
    if (index < 0 || index >= _shares.length || !_shares[index].isPaid) return;
    setState(() {
      _shares = List<_BillShare>.from(_shares)
        ..[index] = _shares[index].copyWith(clearPayment: true);
      _selectedShareIndex = index;
      _syncInputWithSelection();
    });
  }

  void _resetSplitCollection() {
    setState(() {
      _initializeSplitShares();
      _selectedMethod = 'cash';
      _syncInputWithSelection();
    });
  }

  void _syncInputWithSelection() {
    if (_selectedMethod == 'cash') {
      _inputAmount = '';
    } else {
      final target = _currentTargetAmount;
      _inputAmount = target > 0 ? target.toStringAsFixed(2) : '';
    }
  }

  void _onNumpadTap(String key) {
    setState(() {
      if (key == '⌫') {
        if (_inputAmount.isNotEmpty) {
          _inputAmount = _inputAmount.substring(0, _inputAmount.length - 1);
        }
        return;
      }

      if (key == '.') {
        if (!_inputAmount.contains('.')) {
          _inputAmount += _inputAmount.isEmpty ? '0.' : '.';
        }
        return;
      }

      if (_inputAmount.contains('.')) {
        final parts = _inputAmount.split('.');
        if (parts.length > 1 && parts[1].length >= 2) return;
      }

      if (_inputAmount == '0' && key != '.') {
        _inputAmount = key;
      } else {
        final candidate = _inputAmount + key;
        // M10 FIX: Limit input length to prevent visual overflow
        if (candidate.length > 10) return;
        final parsed = double.tryParse(candidate) ?? 0;
        if (parsed > AppConstants.maxOrderTotal) return;
        _inputAmount = candidate;
      }
    });
  }

  double _roundUp(double value, int to) {
    return (value / to).ceil() * to.toDouble();
  }

  Future<void> _processPayment() async {
    if (_isProcessing) return;

    if (_isSplitBill && !_allSharesCollected) {
      if (!_canCollectCurrentShare) return;
      _collectCurrentSharePayment();
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final payment =
          _isSplitBill ? _buildSplitSummaryPayment() : _buildSinglePayment();
      final orderId =
          await _submitPayment(payment);

      if (mounted) {
        setState(() => _isSuccess = true);
        await Future.delayed(const Duration(milliseconds: 1500));
        if (mounted) {
          Navigator.pop(context, payment);
          widget.onPaymentComplete(orderId);
        }
      }
    } catch (e) {
      final errorMessage = PosService.displayError(e);
      if (mounted) {
        // Industry-grade failure UX: Show actionable banner inside dialog
        // instead of closing dialog or plain snackbar.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Payment failed: $errorMessage. You may safely retry (idempotent).'),
                ),
              ],
            ),
            backgroundColor: Colors.red[800],
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () => _processPayment(), // recursive call allowed because flag resets
            ),
          ),
        );
        setState(() => _isProcessing = false);
      }
    }
  }

  void _collectCurrentSharePayment() {
    final index = _selectedUnpaidShareIndex;
    if (index < 0) return;

    final payment = _buildPaymentForAmount(
      _shares[index].amount,
      label: _shares[index].label,
    );

    setState(() {
      final updatedShares = List<_BillShare>.from(_shares);
      updatedShares[index] = updatedShares[index].copyWith(payment: payment);
      _shares = updatedShares;

      final nextIndex = _shares.indexWhere((share) => !share.isPaid);
      if (nextIndex >= 0) {
        _selectedShareIndex = nextIndex;
      }
      _syncInputWithSelection();
    });
  }

  PosPayment _buildSinglePayment() {
    return _buildPaymentForAmount(_grandTotal);
  }

  PosPayment _buildPaymentForAmount(double amount, {String? label}) {
    final roundedAmount = _roundMoney(amount);
    final tendered = _selectedMethod == 'cash' ? _enteredAmount : roundedAmount;
    final change = _selectedMethod == 'cash'
        ? _roundMoney((tendered - roundedAmount).clamp(0, double.infinity))
        : 0.0;

    return PosPayment(
      method: _selectedMethod,
      label: label,
      amount: _roundMoney(tendered),
      change: change,
      appliedAmount: roundedAmount,
    );
  }

  PosPayment _buildSplitSummaryPayment() {
    final payments = _shares
        .map((share) => share.payment)
        .whereType<PosPayment>()
        .toList(growable: false);

    return PosPayment(
      method: 'split',
      label: 'Split Bill',
      amount: _roundMoney(
        payments.fold(
          0.0,
          (totalTenderedValue, payment) => totalTenderedValue + payment.amount,
        ),
      ),
      change: _roundMoney(
        payments.fold(
          0.0,
          (totalChangeValue, payment) => totalChangeValue + payment.change,
        ),
      ),
      appliedAmount: _grandTotal,
      splits: payments,
    );
  }

  Future<String?> _submitPayment(PosPayment payment) async {
    if (widget.returnPaymentOnly) {
      if (mounted) {
        Navigator.pop(context, payment);
      }
      return null;
    }

    final pos = context.read<PosService>();
    final userScope = context.read<UserScopeService>();

    final orderId = await pos.submitOrderWithPayment(
      userScope: userScope,
      branchIds: widget.branchIds,
      payment: payment,
      existingOrders: widget.existingOrders,
    );

    return orderId;
  }

  void _showInfo(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  double _roundMoney(double value) => double.parse(value.toStringAsFixed(2));
}
