import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../Widgets/BranchFilterService.dart';
import '../../main.dart';
import '../../services/inventory/InventoryService.dart';
import '../../services/inventory/PurchaseOrderService.dart';

class CreatePurchaseOrderScreen extends StatefulWidget {
  final bool isDrawer;
  const CreatePurchaseOrderScreen({super.key, this.isDrawer = false});

  @override
  State<CreatePurchaseOrderScreen> createState() =>
      _CreatePurchaseOrderScreenState();
}

class _CreatePurchaseOrderScreenState extends State<CreatePurchaseOrderScreen> {
  late final PurchaseOrderService _service;
  late final InventoryService _inventoryService;
  bool _servicesInitialized = false;
  final TextEditingController _notesCtrl = TextEditingController();
  final List<_PoLine> _lines = [_PoLine()];
  final List<_PoLine> _garbageLines = [];
  String? _supplierId;
  String _supplierName = '';
  String _supplierEmail = '';
  String _poNumber = '';
  DateTime _orderDate = DateTime.now();
  DateTime? _expectedDate;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_servicesInitialized) {
      _servicesInitialized = true;
      _service = Provider.of<PurchaseOrderService>(context, listen: false);
      _inventoryService = Provider.of<InventoryService>(context, listen: false);
      _preparePoNumber();
    }
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    for (final l in _garbageLines) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _preparePoNumber() async {
    final userScope = context.read<UserScopeService>();
    final branchFilter = context.read<BranchFilterService>();
    final branchIds = branchFilter.getFilterBranchIds(userScope.branchIds);
    final branchId = userScope.branchIds.isNotEmpty
        ? userScope.branchIds.first
        : (branchIds.firstOrNull ?? '');
    final po = await _service.generatePoNumber(branchIds);
    if (mounted) setState(() => _poNumber = po);
  }

  @override
  Widget build(BuildContext context) {
    final userScope = context.watch<UserScopeService>();
    final branchFilter = context.watch<BranchFilterService>();
    final branchIds = branchFilter.getFilterBranchIds(userScope.branchIds);
    final branchId = userScope.branchIds.isNotEmpty
        ? userScope.branchIds.first
        : (branchIds.firstOrNull ?? '');

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: widget.isDrawer 
          ? null 
          : AppBar(
              title: const Text('Create Purchase Order'),
              backgroundColor: Colors.white,
              elevation: 0,
            ),
      body: Column(
        children: [
          if (widget.isDrawer)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                   const Text(
                    'New Purchase Order',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.deepPurple,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _service.streamSuppliers(branchIds, isActive: true),
        builder: (context, snapshot) {
          final suppliers = snapshot.data ?? [];
          final selectedSupplier = suppliers.firstWhere(
            (s) => (s['id']?.toString() ?? '') == (_supplierId ?? ''),
            orElse: () => <String, dynamic>{},
          );
          final supplierIngredientIds = List<String>.from(
            selectedSupplier['ingredientIds'] as List? ?? [],
          );
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _card(
                child: Column(
                  children: [
                    _kv('PO Number',
                        _poNumber.isNotEmpty ? _poNumber : 'Generating...'),
                    const SizedBox(height: 12),
                    _buildSelector(
                      label: 'Supplier *',
                      value: _supplierName.isEmpty
                          ? 'Select Supplier'
                          : _supplierName,
                      items: suppliers
                          .map((s) => (s['companyName'] ?? '').toString())
                          .toList(),
                      onChanged: (selectedName) {
                        final hit = suppliers.firstWhere(
                          (s) =>
                              (s['companyName'] ?? '').toString() ==
                              selectedName,
                          orElse: () => {},
                        );
                        setState(() {
                          _supplierId = hit['id']?.toString();
                          _supplierName = selectedName;
                          _supplierEmail = (hit['email'] ?? '').toString();
                        });
                      },
                      icon: Icons.business_outlined,
                    ),
                    const SizedBox(height: 12),
                    Container(
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
                        title: const Text('Expected delivery date',
                            style: TextStyle(fontSize: 14)),
                        subtitle: Text(
                          _expectedDate == null
                              ? 'Select date'
                              : _expectedDate!
                                  .toLocal()
                                  .toString()
                                  .split(' ')
                                  .first,
                          style: TextStyle(
                            color: _expectedDate == null
                                ? Colors.grey[500]
                                : Colors.black87,
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.calendar_today_outlined,
                              color: Colors.deepPurple),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: DateTime.now(),
                              firstDate: DateTime.now()
                                  .subtract(const Duration(days: 1)),
                              lastDate:
                                  DateTime.now().add(const Duration(days: 365)),
                            );
                            if (picked != null)
                              setState(() => _expectedDate = picked);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              StreamBuilder<List<dynamic>>(
                stream: _inventoryService.streamIngredients(branchIds),
                builder: (context, invSnapshot) {
                  final ingredients = (invSnapshot.data ?? []).map((i) {
                    return {
                      'id': i.id,
                      'name': i.name,
                      'unit': i.unit,
                      'costPerUnit': i.costPerUnit,
                      'category': i.category,
                    };
                  }).toList();
                  return _card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Line Items',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.deepPurple,
                              fontSize: 16),
                        ),
                        const SizedBox(height: 12),
                        ..._lines.asMap().entries.map((entry) {
                          final index = entry.key;
                          final line = entry.value;
                          return Container(
                            key: ObjectKey(line),
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
                                      child:
                                          _buildItemSelector(
                                        line,
                                        ingredients,
                                        supplierIngredientIds,
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: _lines.length == 1
                                          ? null
                                          : () {
                                              setState(() {
                                                _garbageLines.add(line);
                                                _lines.removeAt(index);
                                              });
                                            },
                                      icon: const Icon(Icons.delete_outline,
                                          color: Colors.red),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildTextInput(
                                        controller: line.qtyCtrl,
                                        label: 'Qty',
                                        keyboardType: const TextInputType
                                            .numberWithOptions(decimal: true),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _buildTextInput(
                                        controller: line.unitCtrl,
                                        label: 'Unit',
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _buildTextInput(
                                        controller: line.costCtrl,
                                        label: 'Cost',
                                        keyboardType: const TextInputType
                                            .numberWithOptions(decimal: true),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }),
                        TextButton.icon(
                          onPressed: () =>
                              setState(() => _lines.add(_PoLine())),
                          icon: const Icon(Icons.add, color: Colors.deepPurple),
                          label: const Text('Add line item',
                              style: TextStyle(color: Colors.deepPurple)),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              _card(
                child: _buildTextInput(
                  controller: _notesCtrl,
                  label: 'Notes / special instructions',
                  icon: Icons.notes_outlined,
                  maxLines: 3,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSaving
                          ? null
                          : () => _save(branchIds, status: 'draft'),
                      child: const Text('Save as Draft'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isSaving
                          ? null
                          : () => _save(branchIds, status: 'submitted'),
                      child: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            )
                          : const Text('Submit to Supplier'),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
      ),
      ],
      ),
    );
  }

  Widget _buildItemSelector(
    _PoLine line,
    List<Map<String, dynamic>> items,
    List<String> supplierIngredientIds,
  ) {
    final hasSelection = line.ingredientIdCtrl.text.isNotEmpty;
    return InkWell(
      onTap: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (ctx) => _ItemPickerSheet(
            items: items,
            prioritizedIds: supplierIngredientIds,
            currentId: line.ingredientIdCtrl.text.isEmpty
                ? null
                : line.ingredientIdCtrl.text,
            onSelect: (id, name, item) {
              setState(() {
                line.ingredientIdCtrl.text = id;
                line.ingredientNameCtrl.text = name;
                line.unitCtrl.text = (item['unit'] ?? '').toString();
                line.costCtrl.text = (item['costPerUnit'] ?? '').toString();
              });
            },
          ),
        );
      },
      borderRadius: BorderRadius.circular(14),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Ingredient *',
          filled: true,
          fillColor: Colors.white,
          prefixIcon: Icon(Icons.inventory_2_outlined,
              size: 20, color: Colors.deepPurple.shade300),
          suffixIcon:
              Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey[400]),
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
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
        child: Text(
          hasSelection ? line.ingredientNameCtrl.text : 'Tap to select...',
          style: TextStyle(
              fontSize: 14,
              color: hasSelection ? Colors.black87 : Colors.grey[600]),
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
    return Row(
      children: [
        Text('$k: ', style: const TextStyle(fontWeight: FontWeight.w600)),
        Expanded(child: Text(v)),
      ],
    );
  }

  Widget _buildTextInput({
    required TextEditingController controller,
    required String label,
    IconData? icon,
    TextInputType? keyboardType,
    int maxLines = 1,
    bool required = false,
  }) {
    return TextFormField(
      controller: controller,
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

  Widget _buildSelector({
    required String label,
    required String value,
    required List<String> items,
    required void Function(String) onChanged,
    IconData? icon,
  }) {
    return InkWell(
      onTap: () {
        showModalBottomSheet(
          context: context,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          builder: (ctx) => Container(
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text(label,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: items.length,
                    itemBuilder: (ctx, i) {
                      final item = items[i];
                      final selected = item == value;
                      return ListTile(
                        onTap: () {
                          onChanged(item);
                          Navigator.pop(ctx);
                        },
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: selected
                                  ? Colors.deepPurple.withOpacity(0.3)
                                  : Colors.grey.shade200,
                            ),
                          ),
                          child: Icon(icon ?? Icons.label_outline,
                              size: 18,
                              color: selected
                                  ? Colors.deepPurple
                                  : Colors.grey[600]),
                        ),
                        title: Text(item,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: selected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color:
                                  selected ? Colors.deepPurple : Colors.black87,
                            )),
                        trailing: selected
                            ? const Icon(Icons.check_circle,
                                color: Colors.deepPurple, size: 20)
                            : null,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(14),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.white,
          prefixIcon: Icon(icon ?? Icons.label_outline,
              size: 20, color: Colors.deepPurple.shade300),
          suffixIcon:
              Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey[400]),
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
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
        child: Text(
          value,
          style: const TextStyle(fontSize: 14, color: Colors.black87),
        ),
      ),
    );
  }

  Future<void> _save(List<String> branchIds, {required String status}) async {
    if (_supplierId == null || _supplierId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select supplier'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final rows = _lines
        .map((l) {
          final qty = double.tryParse(l.qtyCtrl.text.trim()) ?? 0.0;
          final cost = double.tryParse(l.costCtrl.text.trim()) ?? 0.0;
          return {
            'ingredientId': l.ingredientIdCtrl.text.trim(),
            'ingredientName': l.ingredientNameCtrl.text.trim(),
            'unit': l.unitCtrl.text.trim(),
            'orderedQty': qty,
            'receivedQty': 0.0,
            'unitCost': cost,
            'lineTotal': qty * cost,
          };
        })
        .where((r) => (r['ingredientName'] as String).isNotEmpty)
        .toList();

    if (rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add at least one line item'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final total = rows.fold<double>(
      0.0,
      (acc, r) => acc + ((r['lineTotal'] as num).toDouble()),
    );

    setState(() => _isSaving = true);
    try {
      await _service.createPurchaseOrder(
        branchIds: branchIds,
        data: {
          'poNumber': _poNumber,
          'supplierId': _supplierId,
          'supplierName': _supplierName,
          'lineItems': rows,
          'totalAmount': total,
          'status': status,
          'orderDate': Timestamp.fromDate(_orderDate),
          'expectedDeliveryDate':
              _expectedDate != null ? Timestamp.fromDate(_expectedDate!) : null,
          'receivedDate': null,
          'notes': _notesCtrl.text.trim(),
          'createdBy': context.read<UserScopeService>().userIdentifier,
        },
      );
      if (status == 'submitted') {
        await _openSupplierEmail(rows, total);
      }
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(status == 'submitted'
                ? 'Purchase order submitted'
                : 'Purchase order saved as draft'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Save failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _openSupplierEmail(
    List<Map<String, dynamic>> rows,
    double totalAmount,
  ) async {
    if (_supplierEmail.trim().isEmpty) return;
    final subject = Uri.encodeComponent('Purchase Order - $_poNumber');
    final itemLines = rows
        .map((item) =>
            '${item['ingredientName']}: ${item['orderedQty']} ${item['unit']} @ ${item['unitCost']} = ${item['lineTotal']}')
        .join('\n');
    final body = Uri.encodeComponent(
      'Purchase Order: $_poNumber\n'
      'Date: ${DateFormat('dd/MM/yyyy').format(DateTime.now())}\n'
      'Expected Delivery: ${_expectedDate != null ? DateFormat('dd/MM/yyyy').format(_expectedDate!) : "TBD"}\n\n'
      'Items:\n$itemLines\n\n'
      'Total: $totalAmount\n\n'
      'Notes: ${_notesCtrl.text.trim().isEmpty ? "None" : _notesCtrl.text.trim()}\n',
    );

    final emailUri =
        Uri.parse('mailto:${_supplierEmail.trim()}?subject=$subject&body=$body');
    if (await canLaunchUrl(emailUri)) {
      await launchUrl(emailUri);
    }
  }
}

class _PoLine {
  final TextEditingController ingredientIdCtrl = TextEditingController();
  final TextEditingController ingredientNameCtrl = TextEditingController();
  final TextEditingController qtyCtrl = TextEditingController();
  final TextEditingController unitCtrl = TextEditingController(text: 'pieces');
  final TextEditingController costCtrl = TextEditingController();

  void dispose() {
    ingredientIdCtrl.dispose();
    ingredientNameCtrl.dispose();
    qtyCtrl.dispose();
    unitCtrl.dispose();
    costCtrl.dispose();
  }
}

class _ItemPickerSheet extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  final List<String> prioritizedIds;
  final String? currentId;
  final Function(String, String, Map<String, dynamic>) onSelect;

  const _ItemPickerSheet({
    required this.items,
    required this.prioritizedIds,
    required this.currentId,
    required this.onSelect,
  });

  @override
  State<_ItemPickerSheet> createState() => _ItemPickerSheetState();
}

class _ItemPickerSheetState extends State<_ItemPickerSheet> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.items.where((m) {
      final name = m['name']?.toString().toLowerCase() ?? '';
      return _search.isEmpty || name.contains(_search);
    }).toList();
    final prioritized = filtered
        .where((m) => widget.prioritizedIds.contains(m['id']?.toString()))
        .toList();
    final others = filtered
        .where((m) => !widget.prioritizedIds.contains(m['id']?.toString()))
        .toList();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Text('Select Ingredient',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search ingredients…',
                prefixIcon:
                    Icon(Icons.search, color: Colors.deepPurple.shade300),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              onChanged: (v) => setState(() => _search = v.toLowerCase()),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: filtered.isEmpty
                ? const Center(
                    child: Text('No items found',
                        style: TextStyle(color: Colors.grey)))
                : ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    children: [
                      if (prioritized.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
                          child: Text(
                            'Supplier Ingredients',
                            style: TextStyle(
                              color: Colors.deepPurple.shade700,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        ...prioritized.map((item) => _itemTile(item)),
                      ],
                      if (others.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                          child: Text(
                            prioritized.isEmpty
                                ? 'Ingredients'
                                : 'Other Ingredients',
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        ...others.map((item) => _itemTile(item)),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _itemTile(Map<String, dynamic> item) {
    final id = item['id'].toString();
    final name = (item['name'] ?? '').toString();
    final selected = id == widget.currentId;

    return ListTile(
      onTap: () {
        widget.onSelect(id, name, item);
        Navigator.pop(context);
      },
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? Colors.deepPurple.withOpacity(0.3)
                : Colors.grey.shade200,
          ),
        ),
        child: Icon(
          Icons.eco_outlined,
          size: 18,
          color: selected ? Colors.deepPurple : Colors.grey[500],
        ),
      ),
      title: Text(
        name,
        style: TextStyle(
          fontSize: 15,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          color: selected ? Colors.deepPurple : Colors.black87,
        ),
      ),
      subtitle: item['category'] != null
          ? Text(item['category'], style: const TextStyle(fontSize: 12))
          : null,
      trailing: selected
          ? const Icon(Icons.check_circle, color: Colors.deepPurple, size: 20)
          : null,
    );
  }
}
