import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../Widgets/BranchFilterService.dart';
import '../../main.dart';
import '../../services/inventory/InventoryService.dart';
import '../../services/inventory/PurchaseOrderService.dart';
import '../../services/SinglePurchaseOrderPdfService.dart';

class CreatePurchaseOrderScreen extends StatefulWidget {
  final bool isDrawer;
  final String? initialSupplierId;
  final String initialSupplierName;
  final String initialSupplierEmail;
  final Map<String, dynamic>? editingPo;

  // AI Feature Pre-fills
  final String? prefilledIngredient;
  final String? prefilledIngredientName;
  final String? prefilledUnit;
  final double? prefilledCost;
  final double? prefilledQty;
  final String? prefilledSupplierId;
  final List<String>? branchIdsOverride;

  const CreatePurchaseOrderScreen({
    super.key,
    this.isDrawer = false,
    this.initialSupplierId,
    this.initialSupplierName = '',
    this.initialSupplierEmail = '',
    this.editingPo,
    this.prefilledIngredient,
    this.prefilledIngredientName,
    this.prefilledUnit,
    this.prefilledCost,
    this.prefilledQty,
    this.prefilledSupplierId,
    this.branchIdsOverride,
  });

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
  final DateTime _orderDate = DateTime.now();
  DateTime? _expectedDate;
  bool _isSaving = false;

  UserScopeService get userScope =>
      Provider.of<UserScopeService>(context, listen: false);
  BranchFilterService get branchFilter =>
      Provider.of<BranchFilterService>(context, listen: false);

  List<String> _effectiveBranchIds(
    UserScopeService userScope,
    BranchFilterService branchFilter,
  ) {
    final override = widget.branchIdsOverride
        ?.where((id) => id.trim().isNotEmpty)
        .toSet()
        .toList();
    if (override != null && override.isNotEmpty) {
      return override;
    }
    return branchFilter.getFilterBranchIds(userScope.branchIds);
  }

  @override
  void initState() {
    super.initState();
    if (widget.editingPo != null) {
      final po = widget.editingPo!;
      _supplierId = (po['supplierId'] ?? '').toString();
      _supplierName = (po['supplierName'] ?? '').toString();
      _poNumber = (po['poNumber'] ?? '').toString();
      _notesCtrl.text = (po['notes'] ?? '').toString();

      final expected = po['expectedDeliveryDate'] as Timestamp?;
      if (expected != null) _expectedDate = expected.toDate();

      final lineItems = po['lineItems'] as List? ?? [];
      if (lineItems.isNotEmpty) {
        _lines.clear();
        for (final item in lineItems) {
          final line = _PoLine();
          line.ingredientIdCtrl.text = (item['ingredientId'] ?? '').toString();
          line.ingredientNameCtrl.text =
              (item['ingredientName'] ?? '').toString();
          line.qtyCtrl.text = (item['orderedQty'] ?? '').toString();
          line.unitCtrl.text = (item['unit'] ?? 'pieces').toString();
          line.costCtrl.text = (item['unitCost'] ?? '').toString();
          _lines.add(line);
        }
      }
    } else {
      _supplierId = widget.prefilledSupplierId ?? widget.initialSupplierId;
      _supplierName = widget.initialSupplierName;
      _supplierEmail = widget.initialSupplierEmail;

      if (widget.prefilledIngredient != null) {
        _lines.first.ingredientIdCtrl.text = widget.prefilledIngredient!;
        _lines.first.ingredientNameCtrl.text =
            widget.prefilledIngredientName ?? '';
        _lines.first.unitCtrl.text = widget.prefilledUnit ?? 'pieces';
        _lines.first.costCtrl.text = widget.prefilledCost?.toString() ?? '';

        if (widget.prefilledQty != null) {
          _lines.first.qtyCtrl.text = widget.prefilledQty.toString();
        }
      }
    }
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
  void didUpdateWidget(covariant CreatePurchaseOrderScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialSupplierId != oldWidget.initialSupplierId ||
        widget.initialSupplierName != oldWidget.initialSupplierName ||
        widget.initialSupplierEmail != oldWidget.initialSupplierEmail) {
      setState(() {
        _supplierId = widget.initialSupplierId;
        _supplierName = widget.initialSupplierName;
        _supplierEmail = widget.initialSupplierEmail;
      });
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
    final branchIds = _effectiveBranchIds(userScope, branchFilter);

    // If branchIds is empty, we still try to generate,
    // but we'll try again if it's still generating.
    final po = await _service.generatePoNumber(branchIds);
    if (mounted) {
      setState(() => _poNumber = po);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userScope = context.watch<UserScopeService>();
    final branchFilter = context.watch<BranchFilterService>();
    final branchIds = _effectiveBranchIds(userScope, branchFilter);

    // ✅ RE-TRIGGER GENERATION IF IT FAILED DURING DIDCHANGEDEPENDENCIES
    if (_poNumber.isEmpty && branchIds.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _preparePoNumber());
    }

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
                  Text(
                    widget.editingPo != null
                        ? 'Edit Purchase Order'
                        : 'New Purchase Order',
                    style: const TextStyle(
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
                if (_supplierId != null &&
                    _supplierName.isEmpty &&
                    selectedSupplier.isNotEmpty) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    setState(() {
                      _supplierName =
                          (selectedSupplier['companyName'] ?? '').toString();
                      _supplierEmail =
                          (selectedSupplier['email'] ?? '').toString();
                    });
                  });
                }
                final supplierIngredientIds = List<String>.from(
                  selectedSupplier['ingredientIds'] as List? ?? [],
                );
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 850),
                    child: ListView(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 32),
                      children: [
                        // Header text for non-drawer view
                        if (!widget.isDrawer) ...[
                          Text(
                            widget.editingPo != null
                                ? 'Edit Purchase Order'
                                : 'New Purchase Order',
                            style: GoogleFonts.outfit(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: Colors.deepPurple.shade800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Fill in the details below to generate a new PO.',
                            style: TextStyle(
                                fontSize: 14, color: Colors.grey.shade600),
                          ),
                          const SizedBox(height: 24),
                        ],
                        _card(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Order Details',
                                style: GoogleFonts.outfit(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.deepPurple.shade800,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: Colors.deepPurple.shade50
                                      .withOpacity(0.5),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: Colors.deepPurple.shade100),
                                ),
                                child: _kv(
                                  'PO Number',
                                  _poNumber.isNotEmpty
                                      ? _poNumber
                                      : 'Generating...',
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: _buildSelector(
                                      label: 'Supplier *',
                                      value: _supplierName.isEmpty
                                          ? 'Select Supplier'
                                          : _supplierName,
                                      items: suppliers
                                          .map((s) => (s['companyName'] ?? '')
                                              .toString())
                                          .toList(),
                                      onChanged: (selectedName) {
                                        final hit = suppliers.firstWhere(
                                          (s) =>
                                              (s['companyName'] ?? '')
                                                  .toString() ==
                                              selectedName,
                                          orElse: () => {},
                                        );
                                        setState(() {
                                          _supplierId = hit['id']?.toString();
                                          _supplierName = selectedName;
                                          _supplierEmail =
                                              (hit['email'] ?? '').toString();
                                        });
                                      },
                                      icon: Icons.business_outlined,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                            color: Colors.grey.shade300),
                                      ),
                                      child: ListTile(
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(14)),
                                        leading: const Icon(
                                            Icons.event_outlined,
                                            color: Colors.deepPurple),
                                        title: const Text('Expected delivery',
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
                                            fontWeight: _expectedDate == null
                                                ? FontWeight.normal
                                                : FontWeight.w600,
                                          ),
                                        ),
                                        trailing: IconButton(
                                          icon: const Icon(
                                              Icons.calendar_today_outlined,
                                              color: Colors.deepPurple),
                                          onPressed: () async {
                                            final picked = await showDatePicker(
                                              context: context,
                                              initialDate: DateTime.now(),
                                              firstDate: DateTime.now()
                                                  .subtract(
                                                      const Duration(days: 1)),
                                              lastDate: DateTime.now().add(
                                                  const Duration(days: 365)),
                                            );
                                            if (picked != null) {
                                              setState(
                                                  () => _expectedDate = picked);
                                            }
                                          },
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        StreamBuilder<List<dynamic>>(
                          stream:
                              _inventoryService.streamIngredients(branchIds),
                          builder: (context, invSnapshot) {
                            final ingredients =
                                (invSnapshot.data ?? []).map((i) {
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
                                  Row(
                                    children: [
                                      Text(
                                        'Line Items',
                                        style: GoogleFonts.outfit(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.deepPurple.shade800,
                                        ),
                                      ),
                                      const Spacer(),
                                      TextButton.icon(
                                        onPressed: () => setState(
                                            () => _lines.add(_PoLine())),
                                        icon: const Icon(Icons.add, size: 18),
                                        label: const Text('Add Row'),
                                        style: TextButton.styleFrom(
                                          foregroundColor: Colors.deepPurple,
                                          backgroundColor:
                                              Colors.deepPurple.shade50,
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 16, vertical: 8),
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8)),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  ..._lines.asMap().entries.map((entry) {
                                    final index = entry.key;
                                    final line = entry.value;
                                    return StatefulBuilder(
                                      key: ObjectKey(line),
                                      builder: (ctx, setLineState) {
                                        // Listen to changes in qty/cost to recompute total
                                        line.qtyCtrl.addListener(
                                            () => setLineState(() {}));
                                        line.costCtrl.addListener(
                                            () => setLineState(() {}));
                                        final qty = double.tryParse(
                                                line.qtyCtrl.text.trim()) ??
                                            0.0;
                                        final cost = double.tryParse(
                                                line.costCtrl.text.trim()) ??
                                            0.0;
                                        final lineTotal = qty * cost;
                                        final hasTotal = qty > 0 && cost > 0;
                                        return Container(
                                          margin:
                                              const EdgeInsets.only(bottom: 12),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            border: Border.all(
                                                color: Colors.grey.shade200),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.deepPurple
                                                    .withOpacity(0.03),
                                                blurRadius: 8,
                                                offset: const Offset(0, 2),
                                              )
                                            ],
                                          ),
                                          child: Column(
                                            children: [
                                              Padding(
                                                padding:
                                                    const EdgeInsets.all(16),
                                                child: Row(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.all(
                                                              8),
                                                      decoration: BoxDecoration(
                                                        color: Colors
                                                            .deepPurple.shade50,
                                                        shape: BoxShape.circle,
                                                      ),
                                                      child: Text(
                                                          '${index + 1}',
                                                          style: TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              color: Colors
                                                                  .deepPurple
                                                                  .shade600)),
                                                    ),
                                                    const SizedBox(width: 12),
                                                    Expanded(
                                                      child: Column(
                                                        children: [
                                                          _buildItemSelector(
                                                              line,
                                                              ingredients,
                                                              supplierIngredientIds),
                                                          const SizedBox(
                                                              height: 12),
                                                          Row(
                                                            children: [
                                                              Expanded(
                                                                  child: _buildTextInput(
                                                                      controller:
                                                                          line
                                                                              .qtyCtrl,
                                                                      label:
                                                                          'Qty',
                                                                      keyboardType: const TextInputType
                                                                          .numberWithOptions(
                                                                          decimal:
                                                                              true))),
                                                              const SizedBox(
                                                                  width: 12),
                                                              Expanded(
                                                                  child: _buildTextInput(
                                                                      controller:
                                                                          line
                                                                              .unitCtrl,
                                                                      label:
                                                                          'Unit')),
                                                              const SizedBox(
                                                                  width: 12),
                                                              Expanded(
                                                                  child: _buildTextInput(
                                                                      controller:
                                                                          line
                                                                              .costCtrl,
                                                                      label:
                                                                          'Cost / Unit',
                                                                      keyboardType: const TextInputType
                                                                          .numberWithOptions(
                                                                          decimal:
                                                                              true))),
                                                            ],
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    const SizedBox(width: 12),
                                                    IconButton(
                                                      onPressed: _lines
                                                                  .length ==
                                                              1
                                                          ? null
                                                          : () {
                                                              setState(() {
                                                                _garbageLines
                                                                    .add(line);
                                                                _lines.removeAt(
                                                                    index);
                                                              });
                                                            },
                                                      icon: const Icon(
                                                          Icons.delete_outline,
                                                          color: Colors.red),
                                                      tooltip: 'Remove Item',
                                                      padding: EdgeInsets.zero,
                                                      constraints:
                                                          const BoxConstraints(),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              // ── Total Value row ──────────────────────────────
                                              if (hasTotal)
                                                Container(
                                                  width: double.infinity,
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 16,
                                                      vertical: 10),
                                                  decoration: BoxDecoration(
                                                    color: Colors
                                                        .deepPurple.shade50,
                                                    borderRadius:
                                                        const BorderRadius
                                                            .vertical(
                                                            bottom:
                                                                Radius.circular(
                                                                    12)),
                                                    border: Border(
                                                        top: BorderSide(
                                                            color: Colors
                                                                .deepPurple
                                                                .shade100)),
                                                  ),
                                                  child: Row(
                                                    children: [
                                                      Icon(
                                                          Icons
                                                              .calculate_outlined,
                                                          size: 14,
                                                          color: Colors
                                                              .deepPurple
                                                              .shade400),
                                                      const SizedBox(width: 8),
                                                      Text(
                                                        '${qty.toStringAsFixed(qty.truncateToDouble() == qty ? 0 : 2)} ${line.unitCtrl.text.trim().isNotEmpty ? line.unitCtrl.text.trim() : 'units'}  ×  QAR ${cost.toStringAsFixed(2)}  =',
                                                        style: TextStyle(
                                                            fontSize: 12,
                                                            color: Colors
                                                                .deepPurple
                                                                .shade500),
                                                      ),
                                                      const Spacer(),
                                                      Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                                horizontal: 12,
                                                                vertical: 4),
                                                        decoration:
                                                            BoxDecoration(
                                                          color:
                                                              Colors.deepPurple,
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(8),
                                                        ),
                                                        child: Text(
                                                          'Total  QAR ${lineTotal.toStringAsFixed(2)}',
                                                          style:
                                                              const TextStyle(
                                                                  fontSize: 13,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                  color: Colors
                                                                      .white),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                )
                                              else
                                                Container(
                                                  width: double.infinity,
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 16,
                                                      vertical: 8),
                                                  decoration: BoxDecoration(
                                                    color: Colors.grey.shade50,
                                                    borderRadius:
                                                        const BorderRadius
                                                            .vertical(
                                                            bottom:
                                                                Radius.circular(
                                                                    12)),
                                                    border: Border(
                                                        top: BorderSide(
                                                            color: Colors.grey
                                                                .shade200)),
                                                  ),
                                                  child: Text(
                                                    'Enter qty & cost to see Total Value',
                                                    style: TextStyle(
                                                        fontSize: 11,
                                                        color: Colors
                                                            .grey.shade400),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        );
                                      },
                                    );
                                  }),
                                ],
                              ),
                            );
                          },
                        ),
                        // ── Grand Total Card ──────────────────────────────────
                        StatefulBuilder(
                          builder: (ctx, setGrandState) {
                            for (final l in _lines) {
                              l.qtyCtrl.addListener(() => setGrandState(() {}));
                              l.costCtrl
                                  .addListener(() => setGrandState(() {}));
                            }
                            final grandTotal =
                                _lines.fold<double>(0.0, (sum, l) {
                              final q =
                                  double.tryParse(l.qtyCtrl.text.trim()) ?? 0.0;
                              final c =
                                  double.tryParse(l.costCtrl.text.trim()) ??
                                      0.0;
                              return sum + (q * c);
                            });
                            return Container(
                              margin: const EdgeInsets.only(top: 8),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 18),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.deepPurple.shade700,
                                    Colors.deepPurple.shade500,
                                  ],
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                ),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.receipt_long,
                                      color: Colors.white70, size: 22),
                                  const SizedBox(width: 12),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'GRAND TOTAL',
                                        style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.white70,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 1.5),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${_lines.where((l) => l.ingredientNameCtrl.text.isNotEmpty).length} line item(s)',
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.white60),
                                      ),
                                    ],
                                  ),
                                  const Spacer(),
                                  Text(
                                    'QAR ${grandTotal.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                        fontSize: 28,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        _card(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Additional Information',
                                style: GoogleFonts.outfit(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.deepPurple.shade800,
                                ),
                              ),
                              const SizedBox(height: 16),
                              _buildTextInput(
                                controller: _notesCtrl,
                                label:
                                    'Notes or special instructions for supplier',
                                icon: Icons.notes_outlined,
                                maxLines: 3,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => _downloadCurrentPo(),
                              icon: const Icon(Icons.download_outlined, size: 18),
                              label: const Text('Download LPO'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                            const Spacer(),
                            OutlinedButton(
                              onPressed: _isSaving
                                  ? null
                                  : () => _save(branchIds, status: 'draft'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 32, vertical: 16),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              child: const Text('Save as Draft',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600)),
                            ),
                            const SizedBox(width: 16),
                            ElevatedButton(
                              onPressed: _isSaving
                                  ? null
                                  : () => _save(branchIds, status: 'submitted'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 32, vertical: 16),
                                backgroundColor: Colors.deepPurple,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              child: _isSaving
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          color: Colors.white, strokeWidth: 2))
                                  : const Text('Submit Order',
                                      style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
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

  Future<void> _downloadCurrentPo() async {
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

    final total = rows.fold<double>(0.0, (acc, r) => acc + ((r['lineTotal'] as num).toDouble()));

    final poData = {
      'poNumber': _poNumber.isNotEmpty ? _poNumber : 'DRAFT',
      'supplierName': _supplierName,
      'supplierId': _supplierId,
      'orderDate': Timestamp.fromDate(_orderDate),
      'expectedDeliveryDate': _expectedDate != null ? Timestamp.fromDate(_expectedDate!) : null,
      'totalAmount': total,
      'notes': _notesCtrl.text.trim(),
      'lineItems': rows,
    };
    
    try {
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Generating PDF...'), backgroundColor: Colors.blue));
      }
      await SinglePurchaseOrderPdfService.downloadPoPdf(poData);
    } catch(e) {
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to download PDF: $e'), backgroundColor: Colors.red));
      }
    }
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

    if (_poNumber.isEmpty || _poNumber == 'Generating...') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Purchase order number is still generating. Please wait.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (branchIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select a branch before creating a purchase order.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() => _isSaving = true);
    try {
      if (widget.editingPo != null) {
        await _service.updatePurchaseOrder(
          id: widget.editingPo!['id'].toString(),
          updates: {
            'supplierId': _supplierId,
            'supplierName': _supplierName,
            'lineItems': rows,
            'totalAmount': total,
            'status': status,
            'expectedDeliveryDate': _expectedDate != null
                ? Timestamp.fromDate(_expectedDate!)
                : null,
            'notes': _notesCtrl.text.trim(),
          },
          userId: userScope.userIdentifier,
          userName: userScope.userEmail,
        );
      } else {
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
            'expectedDeliveryDate': _expectedDate != null
                ? Timestamp.fromDate(_expectedDate!)
                : null,
            'receivedDate': null,
            'notes': _notesCtrl.text.trim(),
          },
          userId: userScope.userIdentifier,
          userName: userScope.userEmail,
        );
      }
      if (status == 'submitted') {
        try {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Generating PDF for Email Attachment...'),
              backgroundColor: Colors.blue,
            ));
          }
          final poData = {
            'poNumber': _poNumber,
            'supplierName': _supplierName,
            'supplierId': _supplierId,
            'orderDate': Timestamp.fromDate(_orderDate),
            'expectedDeliveryDate': _expectedDate != null ? Timestamp.fromDate(_expectedDate!) : null,
            'totalAmount': total,
            'notes': _notesCtrl.text.trim(),
            'lineItems': rows,
          };
          await SinglePurchaseOrderPdfService.downloadPoPdf(poData);
        } catch (e) {
          debugPrint('Failed to download PDF before email: $e');
        }
        await _openSupplierEmail(rows, total);
      }
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(status == 'submitted'
                ? 'Purchase order $_poNumber submitted'
                : widget.editingPo != null
                    ? 'Purchase order $_poNumber updated'
                    : 'Purchase order $_poNumber saved as draft'),
            backgroundColor: Colors.green,
            action: SnackBarAction(
              label: 'COPY ID',
              textColor: Colors.white,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _poNumber));
              },
            ),
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

    final emailUri = Uri.parse(
        'mailto:${_supplierEmail.trim()}?subject=$subject&body=$body');
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
