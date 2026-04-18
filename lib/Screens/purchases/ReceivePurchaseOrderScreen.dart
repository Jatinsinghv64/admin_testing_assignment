import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../main.dart';
import '../../services/inventory/PurchaseOrderService.dart';
import '../../services/ingredients/IngredientService.dart';
import '../../Widgets/BarcodeScannerListener.dart';

class ReceivePurchaseOrderScreen extends StatefulWidget {
  final Map<String, dynamic> purchaseOrder;
  const ReceivePurchaseOrderScreen({super.key, required this.purchaseOrder});

  @override
  State<ReceivePurchaseOrderScreen> createState() =>
      _ReceivePurchaseOrderScreenState();
}

class _ReceivePurchaseOrderScreenState
    extends State<ReceivePurchaseOrderScreen> {
  late final PurchaseOrderService _service;
  bool _serviceInitialized = false;
  final TextEditingController _notesCtrl = TextEditingController();
  final Map<int, TextEditingController> _receivedQtyCtrls = {};
  final Map<int, FocusNode> _receivedQtyFocusNodes = {};
  final Map<int, TextEditingController> _discrepancyNoteCtrls = {};
  final Map<int, Set<String>> _discrepancyFlags = {};
  bool _isSaving = false;
  bool _fullReceipt = true;
  DateTime _receivedDate = DateTime.now();

  List<Map<String, dynamic>> get _lineItems => List<Map<String, dynamic>>.from(
      widget.purchaseOrder['lineItems'] as List? ?? []);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_serviceInitialized) {
      _serviceInitialized = true;
      _service = Provider.of<PurchaseOrderService>(context, listen: false);
    }
  }

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < _lineItems.length; i++) {
      final ordered = (_lineItems[i]['orderedQty'] as num?)?.toDouble() ?? 0.0;
      _receivedQtyCtrls[i] = TextEditingController(text: ordered.toString());
      _receivedQtyFocusNodes[i] = FocusNode();
      _discrepancyNoteCtrls[i] = TextEditingController(
        text: (_lineItems[i]['discrepancyNote'] ?? '').toString(),
      );
      _discrepancyFlags[i] = Set<String>.from(
        _lineItems[i]['discrepancyFlags'] as List? ?? const [],
      );
    }
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    for (final c in _receivedQtyCtrls.values) {
      c.dispose();
    }
    for (final f in _receivedQtyFocusNodes.values) {
      f.dispose();
    }
    for (final c in _discrepancyNoteCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _buildTextInput({
    required TextEditingController controller,
    FocusNode? focusNode,
    required String label,
    IconData? icon,
    TextInputType? keyboardType,
    int maxLines = 1,
    bool required = false,
    ValueChanged<String>? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.inter(
            color: Colors.grey.shade600, fontSize: 13, fontWeight: FontWeight.w400),
        prefixIcon: icon != null
            ? Icon(icon, color: Colors.deepPurple.shade300, size: 18)
            : null,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.deepPurple, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1),
        ),
        hintStyle: GoogleFonts.inter(color: Colors.grey.shade400, fontSize: 13),
      ),
      validator: required
          ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
          : null,
    );
  }

  void _handleBarcodeScanned(String barcode) async {
    final ingService = Provider.of<IngredientService>(context, listen: false);
    final userScope = Provider.of<UserScopeService>(context, listen: false);
    
    final ingredient = await ingService.findByBarcode(barcode, userScope.branchIds);
    if (!mounted) return;
    
    if (ingredient == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Scanned barcode not found in inventory'), backgroundColor: Colors.red));
      return;
    }
    
    // Find in line items
    final index = _lineItems.indexWhere((item) => item['ingredientId'] == ingredient.id);
    if (index != -1) {
      final focusNode = _receivedQtyFocusNodes[index]!;
      final ctrl = _receivedQtyCtrls[index]!;
      
      focusNode.requestFocus();
      ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
      
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Matched: ${ingredient.name}'), backgroundColor: Colors.green));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${ingredient.name} is not in this Purchase Order!'), backgroundColor: Colors.orange));
    }
  }

  @override
  Widget build(BuildContext context) {
    return BarcodeScannerListener(
      onBarcodeScanned: _handleBarcodeScanned,
      child: Scaffold(
        backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text('Receive Purchase Order',
            style: GoogleFonts.outfit(
                fontWeight: FontWeight.w600, color: Colors.black87)),
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black87, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 950;
          
          if (isWide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left Column: Scrollable Line Items
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 800),
                        child: _buildLineItemsSection(),
                      ),
                    ),
                  ),
                ),
                // Right Column: Fixed Sidebar
                Container(
                  width: 380,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(left: BorderSide(color: Colors.grey.shade200)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.02),
                        blurRadius: 10,
                        offset: const Offset(-4, 0),
                      ),
                    ],
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        _buildOrderSummaryCard(),
                        const SizedBox(height: 24),
                        _buildReceiptSettingsCard(),
                        const SizedBox(height: 32),
                        _buildActionArea(),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }

          // Mobile/Narrow Layout (Existing)
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 850),
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                children: [
                  _buildOrderSummaryCard(),
                  const SizedBox(height: 24),
                  _buildLineItemsSection(),
                  const SizedBox(height: 24),
                  _buildReceiptSettingsCard(),
                  const SizedBox(height: 32),
                  _buildActionArea(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          );
        },
      ),
    ),
    );
  }

  Widget _card({required Widget child, Color? color, EdgeInsets? padding}) {
    return Container(
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color ?? Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _kv(String k, String v, {bool isStatus = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text('$k: ',
              style: GoogleFonts.inter(
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade600,
                  fontSize: 13)),
          const SizedBox(width: 4),
          if (isStatus)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                v.toUpperCase(),
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade800,
                    fontSize: 11,
                    letterSpacing: 0.5),
              ),
            )
          else
            Expanded(
              child: Text(v,
                  style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                      fontSize: 14)),
            ),
        ],
      ),
    );
  }

  Widget _buildOrderSummaryCard() {
    return _card(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.description_outlined,
                    color: Colors.deepPurple, size: 24),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Order Details',
                      style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87)),
                  Text('Purchase Order Information',
                      style: GoogleFonts.inter(
                          fontSize: 12, color: Colors.grey.shade500)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                  child: _kv('PO Number',
                      (widget.purchaseOrder['poNumber'] ?? '').toString())),
              Expanded(
                  child: _kv('Status',
                      (widget.purchaseOrder['status'] ?? '').toString(),
                      isStatus: true)),
            ],
          ),
          const SizedBox(height: 8),
          _kv('Supplier',
              (widget.purchaseOrder['supplierName'] ?? '').toString()),
        ],
      ),
    );
  }

  Widget _buildLineItemsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text('Line Items',
              style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87)),
        ),
        ..._lineItems.asMap().entries.map((entry) {
          final index = entry.key;
          final row = entry.value;
          final orderedQty = (row['orderedQty'] as num?)?.toDouble() ?? 0.0;
          final receivedQty = double.tryParse(
                _receivedQtyCtrls[index]!.text.trim(),
              ) ??
              0.0;
          final hasDiscrepancy = (orderedQty - receivedQty).abs() > 0.0001;

          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            child: _card(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child: Text('${index + 1}',
                                style: GoogleFonts.inter(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey.shade400)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text((row['ingredientName'] ?? '').toString(),
                                  style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                      color: Colors.black87)),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Text('Ordered: ',
                                      style: GoogleFonts.inter(
                                          fontSize: 12,
                                          color: Colors.grey.shade500)),
                                  Text('${orderedQty.toStringAsFixed(2)} ${row['unit'] ?? ''}',
                                      style: GoogleFonts.inter(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.grey.shade700)),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 110,
                          child: _buildTextInput(
                            controller: _receivedQtyCtrls[index]!,
                            focusNode: _receivedQtyFocusNodes[index],
                            label: 'Received',
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (hasDiscrepancy)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50.withOpacity(0.3),
                        border: Border(
                            top: BorderSide(color: Colors.orange.shade100)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.warning_amber_rounded,
                                  color: Colors.orange.shade800, size: 16),
                              const SizedBox(width: 6),
                              Text('Quantity Discrepancy Found',
                                  style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w600,
                                      color: Colors.orange.shade900,
                                      fontSize: 12)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _flagChip(
                                  index, 'Short Delivery', 'short_delivery'),
                              _flagChip(index, 'Damaged', 'damaged'),
                              _flagChip(index, 'Wrong Item', 'wrong_item'),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _buildTextInput(
                            controller: _discrepancyNoteCtrls[index]!,
                            label: 'Discrepancy notes',
                            maxLines: 2,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildReceiptSettingsCard() {
    return _card(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          SwitchListTile(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: Text('Full receipt',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600, fontSize: 14)),
            subtitle: Text('Turn off for partial receiving',
                style: GoogleFonts.inter(fontSize: 12)),
            value: _fullReceipt,
            onChanged: (v) => setState(() => _fullReceipt = v),
            secondary: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _fullReceipt
                    ? Colors.green.shade50
                    : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _fullReceipt ? Icons.inventory : Icons.inventory_2_outlined,
                color: _fullReceipt ? Colors.green : Colors.orange,
                size: 20,
              ),
            ),
            activeColor: Colors.deepPurple,
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.deepPurple.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.calendar_today,
                  color: Colors.deepPurple, size: 20),
            ),
            title: Text('Received date',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600, fontSize: 13)),
            subtitle: Text(
              DateFormat('dd MMM, yyyy').format(_receivedDate),
              style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87),
            ),
            trailing: const Icon(Icons.edit_calendar_outlined, size: 20),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _receivedDate,
                firstDate: DateTime.now().subtract(const Duration(days: 365)),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (picked != null) setState(() => _receivedDate = picked);
            },
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: _buildTextInput(
              controller: _notesCtrl,
              label: 'Overall Receiving Notes',
              icon: Icons.notes_outlined,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionArea() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: _isSaving ? null : _confirmReceive,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                : Text(
                    _fullReceipt ? 'Confirm Full Receipt' : 'Partial Receive',
                    style: GoogleFonts.outfit(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
          ),
        ),
        if (!_fullReceipt)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.info_outline, color: Colors.grey.shade400, size: 14),
                const SizedBox(width: 4),
                Text('Partial receipt will keep this PO open',
                    style: GoogleFonts.inter(
                        fontSize: 12, color: Colors.grey.shade500)),
              ],
            ),
          ),
      ],
    );
  }


  Widget _flagChip(int index, String label, String value) {
    final selected = _discrepancyFlags[index]!.contains(value);
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (isSelected) {
        setState(() {
          if (isSelected) {
            _discrepancyFlags[index]!.add(value);
          } else {
            _discrepancyFlags[index]!.remove(value);
          }
        });
      },
      selectedColor: Colors.orange.shade100,
      checkmarkColor: Colors.orange.shade800,
      backgroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: selected ? Colors.orange.shade300 : Colors.grey.shade300,
          width: 1,
        ),
      ),
      labelStyle: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: selected ? FontWeight.bold : FontWeight.w500,
        color: selected ? Colors.orange.shade900 : Colors.grey.shade700,
      ),
    );
  }

  Future<void> _confirmReceive() async {
    setState(() => _isSaving = true);
    try {
      final rows = _lineItems.asMap().entries.map((entry) {
        final i = entry.key;
        final r = entry.value;
        final orderedQty = (r['orderedQty'] as num?)?.toDouble() ?? 0.0;
        final receivedQty =
            double.tryParse(_receivedQtyCtrls[i]!.text.trim()) ?? 0.0;
        final hasDiscrepancy = (orderedQty - receivedQty).abs() > 0.0001;
        return {
          ...r,
          'receivedQty': receivedQty,
          'discrepancyFlags':
              hasDiscrepancy ? _discrepancyFlags[i]!.toList() : <String>[],
          'discrepancyNote': hasDiscrepancy
              ? _discrepancyNoteCtrls[i]!.text.trim()
              : '',
        };
      }).toList();
      final user = context.read<UserScopeService>();
      await _service.receivePurchaseOrder(
        poId: widget.purchaseOrder['id'].toString(),
        userId: user.userIdentifier,
        userName: user.userEmail,
        receivedDate: _receivedDate,
        receivedItems: rows,
        fullReceipt: _fullReceipt,
        notes: _notesCtrl.text.trim(),
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_fullReceipt
                ? 'PO marked as received'
                : 'PO marked as partial'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Receive failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
