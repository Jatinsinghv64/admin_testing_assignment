// lib/Screens/pos/PosPaymentDialog.dart
// Full-screen payment dialog with numpad (Odoo-style)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../main.dart';
import '../../constants.dart';
import '../../services/pos/pos_service.dart';
import '../../services/pos/pos_models.dart';

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
  String _selectedMethod = 'cash';
  String _inputAmount = '';
  bool _isProcessing = false;

  double get _enteredAmount {
    if (_inputAmount.isEmpty) return 0;
    return double.tryParse(_inputAmount) ?? 0;
  }

  double get _grandTotal => widget.totalAmount + widget.existingTableTotal;

  double get _changeAmount {
    if (_selectedMethod != 'cash') return 0;
    return (_enteredAmount - _grandTotal).clamp(0, double.infinity);
  }

  bool get _canValidate {
    if (_selectedMethod == 'cash') {
      // Use a small epsilon to allow for minor floating point inaccuracies
      return _enteredAmount >= (_grandTotal - 0.001);
    }
    return true; // Card payments are always the exact amount
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: Container(
        width: 750,
        height: 650,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 30,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Row(
          children: [
            // ── Left Panel: Payment Info ──
            Expanded(
              flex: 5,
              child: _buildPaymentInfoPanel(),
            ),
            // ── Right Panel: Numpad ──
            if (_selectedMethod == 'cash')
              Expanded(
                flex: 4,
                child: _buildNumpadPanel(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentInfoPanel() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.horizontal(
          left: const Radius.circular(24),
          right: _selectedMethod != 'cash'
              ? const Radius.circular(24)
              : Radius.zero,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.payments_rounded,
                    color: Colors.deepPurple, size: 28),
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
          ),
          const SizedBox(height: 32),
          // Total Amount Breakdown (if existing orders)
          if (widget.existingTableTotal > 0) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.deepPurple.withOpacity(0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.deepPurple.withOpacity(0.1)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Current Cart', style: TextStyle(color: Colors.black54)),
                      Text('${AppConstants.currencySymbol}${widget.totalAmount.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Previous Orders', style: TextStyle(color: Colors.black54)),
                      Text('${AppConstants.currencySymbol}${widget.existingTableTotal.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Total Amount Display
          Container(
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
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total Due',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                Text(
                  '${AppConstants.currencySymbol}${_grandTotal.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Payment Method Tabs
          const Text(
            'Payment Method',
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
              _buildMethodButton('cash', Icons.money, 'Cash'),
              const SizedBox(width: 12),
              _buildMethodButton('card', Icons.credit_card, 'Card'),
            ],
          ),
          const Spacer(),

          // Change display (cash only)
          if (_selectedMethod == 'cash' && _enteredAmount > 0)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _canValidate
                    ? Colors.green.withOpacity(0.08)
                    : Colors.orange.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _canValidate
                      ? Colors.green.withOpacity(0.3)
                      : Colors.orange.withOpacity(0.3),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _canValidate ? 'Change' : 'Remaining',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _canValidate ? Colors.green[700] : Colors.orange[700],
                    ),
                  ),
                  Text(
                    _canValidate
                        ? '${AppConstants.currencySymbol}${_changeAmount.toStringAsFixed(2)}'
                        : '${AppConstants.currencySymbol}${(_grandTotal - _enteredAmount).toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: _canValidate ? Colors.green[700] : Colors.orange[700],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),

          // Validate Button
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
                  : const Text(
                      'Validate Payment',
                      style: TextStyle(
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

  Widget _buildMethodButton(String method, IconData icon, String label) {
    final isSelected = _selectedMethod == method;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            setState(() {
              _selectedMethod = method;
              if (method != 'cash') {
                _inputAmount = _grandTotal.toStringAsFixed(2);
              } else {
                _inputAmount = '';
              }
            });
          },
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: isSelected
                  ? Colors.deepPurple.withOpacity(0.1)
                  : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected
                    ? Colors.deepPurple
                    : Colors.grey.withOpacity(0.2),
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
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.w500,
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

  Widget _buildNumpadPanel() {
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
        children: [
          // Amount Display
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

          // Quick amounts
          Row(
            children: [
              _buildQuickAmount(_grandTotal, 'Exact'),
              const SizedBox(width: 8),
              _buildQuickAmount(
                _roundUp(_grandTotal, 10),
                '${AppConstants.currencySymbol}${_roundUp(_grandTotal, 10).toStringAsFixed(0)}',
              ),
              const SizedBox(width: 8),
              _buildQuickAmount(
                _roundUp(_grandTotal, 100),
                '${AppConstants.currencySymbol}${_roundUp(_grandTotal, 100).toStringAsFixed(0)}',
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Numpad Grid
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
              _inputAmount = amount.toStringAsFixed(2);
            });
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: Colors.deepPurple.withOpacity(0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Colors.deepPurple.withOpacity(0.15),
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
      '1', '2', '3',
      '4', '5', '6',
      '7', '8', '9',
      '.', '0', '⌫',
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
                    ? Colors.red.withOpacity(0.08)
                    : Colors.grey[100],
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: key == '⌫'
                      ? Colors.red.withOpacity(0.2)
                      : Colors.grey.withOpacity(0.15),
                ),
              ),
              child: Center(
                child: key == '⌫'
                    ? Icon(Icons.backspace_outlined,
                        size: 22, color: Colors.red[400])
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

  void _onNumpadTap(String key) {
    setState(() {
      if (key == '⌫') {
        if (_inputAmount.isNotEmpty) {
          _inputAmount = _inputAmount.substring(0, _inputAmount.length - 1);
        }
      } else if (key == '.') {
        if (!_inputAmount.contains('.')) {
          _inputAmount += _inputAmount.isEmpty ? '0.' : '.';
        }
      } else {
        // Limit decimal places to 2
        if (_inputAmount.contains('.')) {
          final parts = _inputAmount.split('.');
          if (parts.length > 1 && parts[1].length >= 2) return;
        }
        // Prevent leading zeros (e.g. "007")
        if (_inputAmount == '0' && key != '.') {
          _inputAmount = key;
        } else {
          final candidate = _inputAmount + key;
          // Max amount guard: prevent absurdly large amounts
          final parsed = double.tryParse(candidate) ?? 0;
          if (parsed > AppConstants.maxOrderTotal) return;
          _inputAmount = candidate;
        }
      }
    });
  }

  double _roundUp(double value, int to) {
    return (value / to).ceil() * to.toDouble();
  }

  Future<void> _processPayment() async {
    if (_isProcessing) return; // Extra debounce guard
    setState(() => _isProcessing = true);

    try {
      final payment = PosPayment(
        method: _selectedMethod,
        amount: _selectedMethod == 'cash'
            ? _enteredAmount
            : _grandTotal,
        change: _changeAmount,
      );

      // If returnPaymentOnly, just pop with the payment object
      if (widget.returnPaymentOnly) {
        if (mounted) Navigator.pop(context, payment);
        return;
      }

      final pos = context.read<PosService>();

      // Access UserScopeService
      final userScope = context.read<UserScopeService>();

      final orderId = await pos.submitOrderWithPayment(
        userScope: userScope,
        branchIds: widget.branchIds,
        payment: payment,
        existingOrders: widget.existingOrders,
      );

      if (mounted) {
        Navigator.pop(context);
        // Show success feedback
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Payment of ${AppConstants.currencySymbol}${_grandTotal.toStringAsFixed(2)} completed',
                ),
              ],
            ),
            backgroundColor: Colors.green[600],
            duration: const Duration(seconds: 3),
          ),
        );
        widget.onPaymentComplete(orderId);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isProcessing = false);
      }
    }
  }
}
