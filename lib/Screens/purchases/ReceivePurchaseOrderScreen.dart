import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: icon != null
            ? Icon(icon, color: Colors.deepPurple.shade300, size: 20)
            : null,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.deepPurple, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        labelStyle: TextStyle(color: Colors.grey[700], fontSize: 14),
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
        title: const Text('Receive Purchase Order'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _kv('PO Number',
                    (widget.purchaseOrder['poNumber'] ?? '').toString()),
                _kv('Supplier',
                    (widget.purchaseOrder['supplierName'] ?? '').toString()),
                _kv('Status',
                    (widget.purchaseOrder['status'] ?? '').toString()),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Received quantities',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.deepPurple,
                        fontSize: 16)),
                const SizedBox(height: 12),
                ..._lineItems.asMap().entries.map((entry) {
                  final index = entry.key;
                  final row = entry.value;
                  final orderedQty =
                      (row['orderedQty'] as num?)?.toDouble() ?? 0.0;
                  final receivedQty = double.tryParse(
                        _receivedQtyCtrls[index]!.text.trim(),
                      ) ??
                      0.0;
                  final hasDiscrepancy =
                      (orderedQty - receivedQty).abs() > 0.0001;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text((row['ingredientName'] ?? '').toString(),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Expected: ${orderedQty.toStringAsFixed(2)}',
                                    style: TextStyle(
                                        color: Colors.grey[700], fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: 100,
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
                        if (hasDiscrepancy) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _flagChip(index, 'Short Delivery', 'short_delivery'),
                              _flagChip(index, 'Damaged', 'damaged'),
                              _flagChip(index, 'Wrong Item', 'wrong_item'),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _buildTextInput(
                            controller: _discrepancyNoteCtrls[index]!,
                            label: 'Discrepancy notes (optional)',
                            maxLines: 2,
                          ),
                        ],
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _card(
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: SwitchListTile(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    title: const Text('Full receipt'),
                    subtitle: const Text('Turn off for partial receiving'),
                    value: _fullReceipt,
                    onChanged: (v) => setState(() => _fullReceipt = v),
                    secondary: Icon(Icons.inventory_outlined,
                        color: _fullReceipt ? Colors.green : Colors.orange),
                    activeColor: Colors.deepPurple,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    leading: const Icon(Icons.event_outlined,
                        color: Colors.deepPurple),
                    title: const Text('Received date',
                        style: TextStyle(fontSize: 14)),
                    subtitle: Text(
                        _receivedDate.toLocal().toString().split(' ').first),
                    trailing: IconButton(
                      icon: const Icon(Icons.calendar_today_outlined,
                          color: Colors.deepPurple),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _receivedDate,
                          firstDate: DateTime.now()
                              .subtract(const Duration(days: 365)),
                          lastDate:
                              DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null)
                          setState(() => _receivedDate = picked);
                      },
                    ),
                  ),
                ),
                _buildTextInput(
                  controller: _notesCtrl,
                  label: 'Notes',
                  icon: Icons.notes_outlined,
                  maxLines: 2,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _confirmReceive,
              child: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : Text(_fullReceipt
                      ? 'Confirm Full Receipt'
                      : 'Partial Receive'),
            ),
          ),
        ],
      ),
    ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.deepPurple.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text('$k: ', style: const TextStyle(fontWeight: FontWeight.w600)),
          Expanded(child: Text(v)),
        ],
      ),
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
      labelStyle: TextStyle(
        color: selected ? Colors.orange.shade900 : Colors.grey[700],
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
