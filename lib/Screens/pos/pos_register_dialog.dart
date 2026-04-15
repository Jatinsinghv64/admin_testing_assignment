// lib/Screens/pos/pos_register_dialog.dart
// Odoo-style Register Opening / Closing Dialog for POS

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../services/pos/pos_register_service.dart';

/// Dialog shown when POS starts for the day — cashier enters opening balance
class PosRegisterOpeningDialog extends StatefulWidget {
  final String branchId;
  final String branchName;
  final String userEmail;
  final PosRegisterService registerService;
  final PosRegisterSession? staleSession;

  const PosRegisterOpeningDialog({
    super.key,
    required this.branchId,
    required this.branchName,
    required this.userEmail,
    required this.registerService,
    this.staleSession,
  });

  @override
  State<PosRegisterOpeningDialog> createState() =>
      _PosRegisterOpeningDialogState();
}

class _PosRegisterOpeningDialogState extends State<PosRegisterOpeningDialog>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _balanceController = TextEditingController(text: '0.00');
  final _notesController = TextEditingController();
  bool _isOpening = false;
  bool _succeeded = false;
  PosRegisterSession? _resultSession;
  late final AnimationController _successAnim;

  PosRegisterSession? _staleSession;
  bool _isForceClosingStale = false;

  @override
  void initState() {
    super.initState();
    _staleSession = widget.staleSession;
    _successAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
  }

  @override
  void dispose() {
    _successAnim.dispose();
    _balanceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ── Success state: show brief checkmark then auto-dismiss ──
    if (_succeeded) {
      return PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Container(
            width: 400,
            padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ScaleTransition(
                  scale: CurvedAnimation(
                    parent: _successAnim,
                    curve: Curves.elasticOut,
                  ),
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.green.shade400, Colors.green.shade700],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_rounded,
                        color: Colors.white, size: 48),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Register Opened!',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Colors.black87),
                ),
                const SizedBox(height: 8),
                Text(
                  'POS is ready for business.',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: true, // Allow dismissal to return to branch selection
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
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.deepPurple.shade400,
                            Colors.deepPurple.shade700
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.point_of_sale,
                          color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Open Register',
                            style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                color: Colors.black87),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.branchName,
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[500],
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Info banner (or Stale Session banner)
                if (_staleSession != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.warning_amber_rounded, size: 20, color: Colors.red[800]),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'A register from ${_staleSession!.openedAt.toLocal().toString().split(' ')[0]} was never closed. Force-close it now to ensure session analytics remain accurate.',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.red[900],
                                    height: 1.3),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _isForceClosingStale ? null : _forceCloseStale,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red[700],
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              elevation: 0,
                            ),
                            icon: _isForceClosingStale
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.close, size: 16),
                            label: Text(_isForceClosingStale ? 'Force Closing...' : 'FORCE CLOSE PREVIOUS REGISTER',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: Colors.blue.withValues(alpha: 0.15)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: 18, color: Colors.blue[600]),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Count the cash in your register and enter the opening balance to start the day.',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue[800],
                                fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 24),
                // Cashier
                _buildReadonlyField(
                    'Cashier', widget.userEmail, Icons.person_outline),
                const SizedBox(height: 16),
                // Opening Balance
                Text(
                  'OPENING CASH BALANCE',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: Colors.grey[500],
                      letterSpacing: 1),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _balanceController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'^\d+\.?\d{0,2}')),
                  ],
                  style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87),
                  decoration: InputDecoration(
                    prefixText: 'QAR ',
                    prefixStyle: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[600]),
                    filled: true,
                    fillColor: Colors.grey[50],
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey[300]!)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey[300]!)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                            color: Colors.deepPurple, width: 2)),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Enter opening balance';
                    final amount = double.tryParse(v);
                    if (amount == null || amount < 0) return 'Amount cannot be negative';
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
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey[300]!)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey[300]!)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                            color: Colors.deepPurple, width: 2)),
                  ),
                ),
                const SizedBox(height: 24),
                // Actions
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: (_isOpening || _isForceClosingStale)
                            ? null
                            : () => Navigator.pop(context, 'cancel'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.grey[700],
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          side: BorderSide(color: Colors.grey[300]!),
                        ),
                        icon: const Icon(Icons.arrow_back, size: 18),
                        label: const Text('Cancel',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: (_isOpening || _isForceClosingStale || _staleSession != null) ? null : _openRegister,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                          disabledBackgroundColor: Colors.grey[300],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        icon: _isOpening
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.lock_open, size: 18),
                        label: Text(
                          _isOpening ? 'Opening...' : 'OPEN REGISTER',
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, letterSpacing: 1),
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
              Text(label.toUpperCase(),
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      color: Colors.grey[400],
                      letterSpacing: 1)),
              const SizedBox(height: 2),
              Text(value,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87)),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _forceCloseStale() async {
    if (_staleSession == null) return;
    setState(() => _isForceClosingStale = true);
    
    try {
      await widget.registerService.forceCloseStaleSession(_staleSession!);
      if (mounted) {
        setState(() {
          _staleSession = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Previous register session was successfully force-closed.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final errorMessage = PosRegisterService.displayError(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to force close: $errorMessage'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isForceClosingStale = false);
      }
    }
  }

  Future<void> _openRegister() async {
    if (!_formKey.currentState!.validate()) return;

    final balance = double.parse(_balanceController.text);
    if (balance == 0.0 && _staleSession == null) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Text('Confirm Zero Balance'),
            ],
          ),
          content: const Text(
            'Are you sure the starting cash balance is exactly QAR 0.00?\n\n'
            'Usually a register has a starting float for making change.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Go Back'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
              child: const Text('Yes, start with 0.00'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    setState(() => _isOpening = true);
    try {
      final session = await widget.registerService.openRegister(
        branchId: widget.branchId,
        openedBy: widget.userEmail,
        openingBalance: balance,
        notes: _notesController.text.trim(),
      );
      if (mounted) {
        // Show success animation, then dismiss after a short delay
        _resultSession = session;
        setState(() => _succeeded = true);
        _successAnim.forward();
        await Future.delayed(const Duration(milliseconds: 900));
        if (mounted) Navigator.pop(context, _resultSession);
      }
    } catch (e) {
      if (mounted) {
        final errorMessage = PosRegisterService.displayError(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted && !_succeeded) setState(() => _isOpening = false);
    }
  }
}

/// Closing dialog — summarize the day and enter closing balance
class PosRegisterClosingDialog extends StatefulWidget {
  final PosRegisterSession session;
  final String userEmail;
  final PosRegisterService registerService;
  final double totalSales;
  final RegisterSessionMetrics? metrics;
  final bool isForceClosed;
  final int activeOrderCount;
  final bool isSuperAdmin;

  const PosRegisterClosingDialog({
    super.key,
    required this.session,
    required this.userEmail,
    required this.registerService,
    required this.totalSales,
    this.metrics,
    this.isForceClosed = false,
    this.activeOrderCount = 0,
    this.isSuperAdmin = false,
  });

  @override
  State<PosRegisterClosingDialog> createState() =>
      _PosRegisterClosingDialogState();
}

class _PosRegisterClosingDialogState extends State<PosRegisterClosingDialog>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _closingBalanceController = TextEditingController();
  final _notesController = TextEditingController();
  bool _isClosing = false;
  bool _succeeded = false;
  late final AnimationController _successAnim;

  double get _expectedBalance =>
      widget.session.openingBalance + widget.totalSales;

  /// INDUSTRY GRADE: Expected amount of cash physically in the register drawer.
  /// Card and online payments never enter the till, so only cash sales are added.
  double get _expectedCashBalance {
    final cashSales = widget.metrics?.totalCashSales ?? widget.totalSales;
    return widget.session.openingBalance + cashSales;
  }

  double get _variance {
    final closing =
        double.tryParse(_closingBalanceController.text) ?? _expectedCashBalance;
    return closing - _expectedCashBalance;
  }

  bool get _hasLargeVariance {
    final absVariance = _variance.abs();
    if (_expectedBalance > 0 && (absVariance / _expectedBalance) > 0.05)
      return true;
    if (absVariance > 50) return true;
    return false;
  }

  @override
  void initState() {
    super.initState();
    _closingBalanceController.text = _expectedCashBalance.toStringAsFixed(2);
    _closingBalanceController.addListener(() {
      if (mounted) setState(() {});
    });
    _successAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
  }

  @override
  void dispose() {
    _successAnim.dispose();
    _closingBalanceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ── Success state: show brief confirmation then auto-dismiss ──
    if (_succeeded) {
      return PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Container(
            width: 400,
            padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ScaleTransition(
                  scale: CurvedAnimation(
                    parent: _successAnim,
                    curve: Curves.elasticOut,
                  ),
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: widget.isForceClosed
                            ? [Colors.orange.shade400, Colors.orange.shade700]
                            : [Colors.red.shade400, Colors.red.shade700],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      widget.isForceClosed
                          ? Icons.warning_amber_rounded
                          : Icons.lock_rounded,
                      color: Colors.white,
                      size: 48,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  widget.isForceClosed
                      ? 'Register Force-Closed'
                      : 'Register Closed',
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Colors.black87),
                ),
                const SizedBox(height: 8),
                Text(
                  'Session ended. Have a good day!',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final openedAt = widget.session.openedAt;
    final duration = DateTime.now().difference(openedAt);
    final hoursOpen =
        '${duration.inHours}h ${duration.inMinutes.remainder(60)}m';
    final m = widget.metrics ?? RegisterSessionMetrics.empty();

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 520,
        constraints: const BoxConstraints(maxHeight: 700),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: widget.isForceClosed
                              ? [Colors.orange.shade400, Colors.orange.shade700]
                              : [Colors.red.shade400, Colors.red.shade700],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        widget.isForceClosed
                            ? Icons.warning_amber_rounded
                            : Icons.lock,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.isForceClosed
                                ? 'Force Close Register'
                                : 'Close Register',
                            style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                color: Colors.black87),
                          ),
                          const SizedBox(height: 2),
                          const Text('End of day cash reconciliation',
                              style:
                                  TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Force close warning
                if (widget.isForceClosed) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Colors.orange.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            size: 20, color: Colors.orange[800]),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${widget.activeOrderCount} active order(s) found. Force closing will NOT cancel them — they will carry over to the next session.',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.orange[900]),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Summary row 1: Opening, Sales, Duration
                Row(
                  children: [
                    _buildSummaryCard(
                        'Opening Balance',
                        'QAR ${widget.session.openingBalance.toStringAsFixed(2)}',
                        Colors.deepPurple),
                    const SizedBox(width: 10),
                    _buildSummaryCard(
                        'Total Sales',
                        'QAR ${widget.totalSales.toStringAsFixed(2)}',
                        Colors.green),
                    const SizedBox(width: 10),
                    _buildSummaryCard('Duration', hoursOpen, Colors.orange),
                  ],
                ),
                const SizedBox(height: 10),

                // Summary row 2: Payment breakdown
                if (m.totalOrders > 0) ...[
                  Row(
                    children: [
                      _buildSummaryCard(
                          'Orders', '${m.totalOrders}', Colors.blue),
                      const SizedBox(width: 10),
                      _buildSummaryCard(
                          'Cash Sales',
                          'QAR ${m.totalCashSales.toStringAsFixed(2)}',
                          Colors.teal),
                      const SizedBox(width: 10),
                      _buildSummaryCard(
                          'Card Sales',
                          'QAR ${m.totalCardSales.toStringAsFixed(2)}',
                          Colors.indigo),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (m.totalOnlineSales > 0 || m.totalCancelled > 0)
                    Row(
                      children: [
                        if (m.totalOnlineSales > 0) ...[
                          _buildSummaryCard(
                              'Online Sales',
                              'QAR ${m.totalOnlineSales.toStringAsFixed(2)}',
                              Colors.cyan),
                          const SizedBox(width: 10),
                        ],
                        if (m.totalCancelled > 0) ...[
                          _buildSummaryCard(
                              'Cancelled', '${m.totalCancelled}', Colors.red),
                          const SizedBox(width: 10),
                        ],
                        const Expanded(child: SizedBox()),
                      ],
                    ),
                  const SizedBox(height: 6),
                ],

                // Expected balance — INDUSTRY GRADE: Show cash-only total
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: Colors.green.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.calculate,
                              size: 18, color: Colors.green[700]),
                          const SizedBox(width: 10),
                          Text('Expected Cash in Drawer: ',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey[700])),
                          Text(
                              'QAR ${_expectedCashBalance.toStringAsFixed(2)}',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.green[700])),
                        ],
                      ),
                      if ((widget.metrics?.totalCardSales ?? 0) > 0 ||
                          (widget.metrics?.totalOnlineSales ?? 0) > 0) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Card: QAR ${(widget.metrics?.totalCardSales ?? 0).toStringAsFixed(2)}'
                          '${(widget.metrics?.totalOnlineSales ?? 0) > 0 ? " • Online: QAR ${(widget.metrics?.totalOnlineSales ?? 0).toStringAsFixed(2)}" : ""}'
                          ' (not included — these don\'t enter the till)',
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[500],
                              fontStyle: FontStyle.italic),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Closing balance
                Text(
                  'ACTUAL CLOSING BALANCE',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: Colors.grey[500],
                      letterSpacing: 1),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _closingBalanceController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'^\d+\.?\d{0,2}')),
                  ],
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    prefixText: 'QAR ',
                    prefixStyle: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[600]),
                    filled: true,
                    fillColor: Colors.grey[50],
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey[300]!)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                            color: Colors.deepPurple, width: 2)),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Enter closing balance';
                    if (double.tryParse(v) == null) return 'Invalid amount';
                    return null;
                  },
                ),

                // Variance warning
                if (_hasLargeVariance) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _variance < 0
                          ? Colors.red.withValues(alpha: 0.08)
                          : Colors.amber.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _variance < 0
                            ? Colors.red.withValues(alpha: 0.3)
                            : Colors.amber.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _variance < 0
                              ? Icons.trending_down
                              : Icons.trending_up,
                          size: 20,
                          color: _variance < 0
                              ? Colors.red[700]
                              : Colors.amber[800],
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _variance < 0
                                ? 'Cash short by QAR ${_variance.abs().toStringAsFixed(2)}. Please verify your count.'
                                : 'Cash over by QAR ${_variance.abs().toStringAsFixed(2)}. Please verify your count.',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _variance < 0
                                  ? Colors.red[900]
                                  : Colors.amber[900],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 16),
                TextFormField(
                  controller: _notesController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Notes (optional)',
                    filled: true,
                    fillColor: Colors.grey[50],
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey[300]!)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                            color: Colors.deepPurple, width: 2)),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: _isClosing
                            ? null
                            : () => Navigator.pop(context, false),
                        child: const Text('Cancel',
                            style: TextStyle(color: Colors.grey)),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: _isClosing ? null : _closeRegister,
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              widget.isForceClosed ? Colors.orange : Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        icon: _isClosing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.lock, size: 18),
                        label: Text(
                          _isClosing
                              ? 'Closing...'
                              : widget.isForceClosed
                                  ? 'FORCE CLOSE'
                                  : 'CLOSE REGISTER',
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, letterSpacing: 1),
                        ),
                      ),
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
            Text(label.toUpperCase(),
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    color: color.withValues(alpha: 0.7),
                    letterSpacing: 0.5)),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w800, color: color)),
          ],
        ),
      ),
    );
  }

  Future<void> _closeRegister() async {
    if (!_formKey.currentState!.validate()) return;

    if (_hasLargeVariance) {
      if (_notesController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please add a note explaining the large cash variance.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange[700]),
              const SizedBox(width: 10),
              const Text('Large Variance Detected'),
            ],
          ),
          content: Text(
            'The variance is QAR ${_variance.abs().toStringAsFixed(2)} (${_variance < 0 ? "short" : "over"}). Are you sure you want to close the register?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Go Back'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: const Text('Close Anyway'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    setState(() => _isClosing = true);
    final durationMinutes =
        DateTime.now().difference(widget.session.openedAt).inMinutes;

    try {
      await widget.registerService.closeRegister(
        sessionId: widget.session.id,
        closingBalance: double.parse(_closingBalanceController.text),
        expectedBalance: _expectedBalance,
        closedBy: widget.userEmail,
        notes: _notesController.text.trim(),
        metrics: widget.metrics,
        isForceClosed: widget.isForceClosed,
        overriddenBy: widget.isForceClosed ? widget.userEmail : null,
        activeOrdersAtClose: widget.activeOrderCount,
        sessionDurationMinutes: durationMinutes,
      );
      if (mounted) {
        // Show success animation, then dismiss after a short delay
        setState(() => _succeeded = true);
        _successAnim.forward();
        await Future.delayed(const Duration(milliseconds: 900));
        if (mounted) Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        final errorMessage = PosRegisterService.displayError(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted && !_succeeded) setState(() => _isClosing = false);
    }
  }
}
