// lib/Screens/pos/pos_register_dialog.dart
// Odoo-style Register Opening / Closing Dialog for POS

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/pos/pos_register_service.dart';

/// Dialog shown when POS starts for the day — cashier enters opening balance
class PosRegisterOpeningDialog extends StatefulWidget {
  final String branchId;
  final String branchName;
  final String userEmail;
  final PosRegisterService registerService;

  const PosRegisterOpeningDialog({
    super.key,
    required this.branchId,
    required this.branchName,
    required this.userEmail,
    required this.registerService,
  });

  @override
  State<PosRegisterOpeningDialog> createState() =>
      _PosRegisterOpeningDialogState();
}

class _PosRegisterOpeningDialogState extends State<PosRegisterOpeningDialog> {
  final _formKey = GlobalKey<FormState>();
  final _balanceController = TextEditingController(text: '0.00');
  final _notesController = TextEditingController();
  bool _isOpening = false;

  @override
  void dispose() {
    _balanceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 460,
        padding: const EdgeInsets.all(32),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.deepPurple.shade400, Colors.deepPurple.shade700],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.point_of_sale, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Open Register',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.black87),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.branchName,
                          style: TextStyle(fontSize: 12, color: Colors.grey[500], fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Info banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.15)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 18, color: Colors.blue[600]),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Count the cash in your register and enter the opening balance to start the day.',
                        style: TextStyle(fontSize: 12, color: Colors.blue[800], fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // Cashier
              _buildReadonlyField('Cashier', widget.userEmail, Icons.person_outline),
              const SizedBox(height: 16),
              // Opening Balance
              Text(
                'OPENING CASH BALANCE',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.grey[500], letterSpacing: 1),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _balanceController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                ],
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87),
                decoration: InputDecoration(
                  prefixText: 'QAR ',
                  prefixStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey[600]),
                  filled: true,
                  fillColor: Colors.grey[50],
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[300]!)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[300]!)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.deepPurple, width: 2)),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Enter opening balance';
                  final amount = double.tryParse(v);
                  if (amount == null || amount < 0) return 'Invalid amount';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              // Notes
              TextFormField(
                controller: _notesController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Notes (optional)',
                  hintText: 'Any observations about the register...',
                  filled: true,
                  fillColor: Colors.grey[50],
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[300]!)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[300]!)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.deepPurple, width: 2)),
                ),
              ),
              const SizedBox(height: 24),
              // Actions
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isOpening ? null : () => Navigator.pop(context, 'cancel'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey[700],
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        side: BorderSide(color: Colors.grey[300]!),
                      ),
                      icon: const Icon(Icons.arrow_back, size: 18),
                      label: const Text('Return', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isOpening ? null : _openRegister,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      icon: _isOpening
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.lock_open, size: 18),
                      label: Text(
                        _isOpening ? 'Opening...' : 'OPEN REGISTER',
                        style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      ), // PopScope
    );
  }

  Widget _buildReadonlyField(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey[500]),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label.toUpperCase(), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.grey[400], letterSpacing: 1)),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openRegister() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isOpening = true);
    try {
      final session = await widget.registerService.openRegister(
        branchId: widget.branchId,
        openedBy: widget.userEmail,
        openingBalance: double.parse(_balanceController.text),
        notes: _notesController.text.trim(),
      );
      if (mounted) {
        Navigator.pop(context, session);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isOpening = false);
    }
  }
}

/// Closing dialog — summarize the day and enter closing balance
class PosRegisterClosingDialog extends StatefulWidget {
  final PosRegisterSession session;
  final String userEmail;
  final PosRegisterService registerService;
  final double totalSales;

  const PosRegisterClosingDialog({
    super.key,
    required this.session,
    required this.userEmail,
    required this.registerService,
    required this.totalSales,
  });

  @override
  State<PosRegisterClosingDialog> createState() =>
      _PosRegisterClosingDialogState();
}

class _PosRegisterClosingDialogState extends State<PosRegisterClosingDialog> {
  final _formKey = GlobalKey<FormState>();
  final _closingBalanceController = TextEditingController();
  final _notesController = TextEditingController();
  bool _isClosing = false;

  double get _expectedBalance => widget.session.openingBalance + widget.totalSales;

  @override
  void initState() {
    super.initState();
    _closingBalanceController.text = _expectedBalance.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _closingBalanceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final openedAt = widget.session.openedAt;
    final duration = DateTime.now().difference(openedAt);
    final hoursOpen = '${duration.inHours}h ${duration.inMinutes.remainder(60)}m';

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 480,
        padding: const EdgeInsets.all(32),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.red.shade400, Colors.red.shade700],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.lock, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Close Register', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.black87)),
                        SizedBox(height: 2),
                        Text('End of day cash reconciliation', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Summary cards
              Row(
                children: [
                  _buildSummaryCard('Opening Balance', 'QAR ${widget.session.openingBalance.toStringAsFixed(2)}', Colors.deepPurple),
                  const SizedBox(width: 12),
                  _buildSummaryCard('Total Sales', 'QAR ${widget.totalSales.toStringAsFixed(2)}', Colors.green),
                  const SizedBox(width: 12),
                  _buildSummaryCard('Duration', hoursOpen, Colors.orange),
                ],
              ),
              const SizedBox(height: 16),
              // Expected balance
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calculate, size: 18, color: Colors.green[700]),
                    const SizedBox(width: 10),
                    Text('Expected Balance: ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey[700])),
                    Text('QAR ${_expectedBalance.toStringAsFixed(2)}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.green[700])),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // Closing balance
              Text(
                'ACTUAL CLOSING BALANCE',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.grey[500], letterSpacing: 1),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _closingBalanceController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                ],
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  prefixText: 'QAR ',
                  prefixStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey[600]),
                  filled: true,
                  fillColor: Colors.grey[50],
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[300]!)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.deepPurple, width: 2)),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Enter closing balance';
                  if (double.tryParse(v) == null) return 'Invalid amount';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _notesController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Notes (optional)',
                  filled: true,
                  fillColor: Colors.grey[50],
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[300]!)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.deepPurple, width: 2)),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _isClosing ? null : () => Navigator.pop(context, false),
                      child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _isClosing ? null : _closeRegister,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      icon: _isClosing
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.lock, size: 18),
                      label: Text(
                        _isClosing ? 'Closing...' : 'CLOSE REGISTER',
                        style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: color.withValues(alpha: 0.7), letterSpacing: 0.5)),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color)),
          ],
        ),
      ),
    );
  }

  Future<void> _closeRegister() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isClosing = true);
    try {
      await widget.registerService.closeRegister(
        sessionId: widget.session.id,
        closingBalance: double.parse(_closingBalanceController.text),
        expectedBalance: _expectedBalance,
        closedBy: widget.userEmail,
        notes: _notesController.text.trim(),
      );
      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Register closed successfully'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isClosing = false);
    }
  }
}
