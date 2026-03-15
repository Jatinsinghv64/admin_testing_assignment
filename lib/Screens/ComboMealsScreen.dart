import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../Models/promo_models.dart';
import '../utils/responsive_helper.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../Widgets/BranchFilterService.dart';
import '../Widgets/BranchSelectorDialog.dart';

class ComboMealsScreen extends StatelessWidget {
  const ComboMealsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final comboCollection = FirebaseFirestore.instance.collection('combos');
    final userScope = Provider.of<UserScopeService>(context);
    final branchFilter = Provider.of<BranchFilterService>(context);
    final effectiveBranchIds =
        branchFilter.getFilterBranchIds(userScope.branchIds);

    Query query = comboCollection.orderBy('sortOrder');

    if (effectiveBranchIds.isNotEmpty) {
      query = query.where('branchIds', arrayContainsAny: effectiveBranchIds);
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.deepPurple),
        title: const Text(
          'Manage Combo Deals',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.deepPurple,
            fontSize: 24,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.add, color: Colors.deepPurple),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ComboMealAddEditScreen(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      body: StreamBuilder(
        stream: query.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.fastfood_outlined,
                    size: 80,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No combo meals found',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Create your first combo deal to boost sales',
                    style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                  ),
                ],
              ),
            );
          }

          final docs = snapshot.data!.docs;

          if (ResponsiveHelper.isTablet(context) ||
              ResponsiveHelper.isDesktop(context)) {
            return GridView.builder(
              padding: const EdgeInsets.all(20),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: ResponsiveHelper.isDesktop(context) ? 3 : 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 0.85,
              ),
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final doc = docs[index];
                return _ComboCard(doc: doc, comboCollection: comboCollection);
              },
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              return _ComboCard(doc: doc, comboCollection: comboCollection);
            },
          );
        },
      ),
    );
  }
}

class _ComboCard extends StatelessWidget {
  final DocumentSnapshot doc;
  final CollectionReference comboCollection;

  const _ComboCard({required this.doc, required this.comboCollection});

  @override
  Widget build(BuildContext context) {
    final combo = ComboModel.fromMap(
      doc.data() as Map<String, dynamic>,
      doc.id,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status and Sort Order
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: combo.isActive
                        ? Colors.green.withValues(alpha: 0.1)
                        : Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        combo.isActive ? Icons.check_circle : Icons.cancel,
                        size: 14,
                        color: combo.isActive ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        combo.isActive ? 'ACTIVE' : 'INACTIVE',
                        style: TextStyle(
                          color: combo.isActive ? Colors.green : Colors.red,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Order: ${combo.sortOrder}',
                    style: const TextStyle(
                      color: Colors.orange,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Title & Items count
            Text(
              combo.name,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Colors.black87,
              ),
            ),
            if (combo.nameAr != null && combo.nameAr!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                combo.nameAr!,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 15,
                  color: Colors.black54,
                ),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              '${combo.itemIds.length} items included',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),

            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // Pricing
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Combo Price',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.deepPurple[300],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'QAR ${combo.comboPrice.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                        color: Colors.deepPurple,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Original Value',
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                    Text(
                      'QAR ${combo.originalTotalPrice.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: Colors.grey[600],
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            if (combo.isLimitedTime) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.timer_outlined,
                      size: 16,
                      color: Colors.blue,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Limited Time Offer',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.blue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const Spacer(),

            // Actions
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ComboMealAddEditScreen(
                            docId: combo.comboId,
                            comboModel: combo,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Edit'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.deepPurple,
                      side: const BorderSide(color: Colors.deepPurple),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _confirmDelete(context),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('Delete'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[50],
                      foregroundColor: Colors.red,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final res = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Combo?'),
        content: const Text(
          'Are you sure you want to delete this combo? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (res == true) {
      await comboCollection.doc(doc.id).delete();
    }
  }
}

// --------------------------------------------------------------------------
// ADD / EDIT SCREEN
// --------------------------------------------------------------------------

class ComboMealAddEditScreen extends StatefulWidget {
  final String? docId;
  final ComboModel? comboModel;

  const ComboMealAddEditScreen({super.key, this.docId, this.comboModel});

  @override
  State<ComboMealAddEditScreen> createState() => _ComboMealAddEditScreenState();
}

class _ComboMealAddEditScreenState extends State<ComboMealAddEditScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameCtrl;
  late TextEditingController _nameArCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _descArCtrl;
  late TextEditingController _comboPriceCtrl;
  late TextEditingController _sortOrderCtrl;

  bool _isActive = true;
  bool _isLimitedTime = false;
  DateTime? _startDate;
  DateTime? _endDate;

  List<String> _selectedItemIds = [];
  List<String> _selectedBranchIds = [];
  double _calculatedOriginalPrice = 0.0;
  bool _isLoading = false;

  Map<String, Map<String, dynamic>> _menuItemsCache = {}; // id -> data

  @override
  void initState() {
    super.initState();
    final combo = widget.comboModel;

    _nameCtrl = TextEditingController(text: combo?.name ?? '');
    _nameArCtrl = TextEditingController(text: combo?.nameAr ?? '');
    _descCtrl = TextEditingController(text: combo?.description ?? '');
    _descArCtrl = TextEditingController(text: combo?.descriptionAr ?? '');
    _comboPriceCtrl = TextEditingController(
      text: combo?.comboPrice.toString() ?? '',
    );
    _sortOrderCtrl = TextEditingController(
      text: combo?.sortOrder.toString() ?? '0',
    );

    _isActive = combo?.isActive ?? true;
    _isLimitedTime = combo?.isLimitedTime ?? false;
    _startDate = combo?.startDate;
    _endDate = combo?.endDate;

    if (combo != null) {
      _selectedItemIds = List<String>.from(combo.itemIds);
      _selectedBranchIds = List<String>.from(combo.branchIds);
    }

    _fetchMenuItems();
  }

  Future<void> _fetchMenuItems() async {
    setState(() => _isLoading = true);
    try {
      final snap =
          await FirebaseFirestore.instance.collection('menu_items').get();
      final Map<String, Map<String, dynamic>> items = {};

      for (var doc in snap.docs) {
        items[doc.id] = doc.data();
      }

      if (mounted) {
        setState(() {
          _menuItemsCache = items;
          _isLoading = false;
          _recalculateOriginalPrice();
        });
      }
    } catch (e) {
      debugPrint("Error fetching menu items: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _recalculateOriginalPrice() {
    double total = 0;
    for (String id in _selectedItemIds) {
      if (_menuItemsCache.containsKey(id)) {
        final data = _menuItemsCache[id]!;
        final price = (data['price'] as num?)?.toDouble() ?? 0.0;
        // final discount = (data['discountedPrice'] as num?)?.toDouble();

        // Use regular price for original price baseline
        total += price;
      }
    }
    setState(() {
      _calculatedOriginalPrice = total;
    });
  }

  Future<void> _saveCombo() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedItemIds.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A combo must contain at least 2 items.')),
      );
      return;
    }

    final price = double.tryParse(_comboPriceCtrl.text) ?? 0.0;

    if (price > _calculatedOriginalPrice) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Warning'),
          content: Text(
            'The combo price (QAR $price) is HIGHER than the original total price (QAR $_calculatedOriginalPrice). Customers will not save money. Are you sure?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Adjust Price'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text(
                'Save Anyway',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    setState(() => _isLoading = true);

    try {
      final db = FirebaseFirestore.instance;

      final comboId =
          widget.docId ?? _nameCtrl.text.replaceAll(' ', '_').toLowerCase();

      final combo = ComboModel(
        comboId: comboId,
        name: _nameCtrl.text,
        nameAr:
            _nameArCtrl.text.trim().isEmpty ? null : _nameArCtrl.text.trim(),
        description: _descCtrl.text,
        descriptionAr:
            _descArCtrl.text.trim().isEmpty ? null : _descArCtrl.text.trim(),
        itemIds: _selectedItemIds,
        originalTotalPrice: _calculatedOriginalPrice,
        comboPrice: price,
        isActive: _isActive,
        isLimitedTime: _isLimitedTime,
        startDate: _isLimitedTime ? _startDate : null,
        endDate: _isLimitedTime ? _endDate : null,
        sortOrder: int.tryParse(_sortOrderCtrl.text) ?? 0,
        orderCount: widget.comboModel?.orderCount ?? 0,
        branchIds: _selectedBranchIds,
      );

      await db.collection('combos').doc(comboId).set(combo.toMap());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Combo saved successfully')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint("Error saving combo: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to save combo')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showItemSelectionDialog() {
    // A simple dialog containing a checklist of all menu items grouped by category (or just a flat list for simplicity here)
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.8,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Select Items',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  const Divider(),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _menuItemsCache.length,
                      itemBuilder: (context, index) {
                        final entry = _menuItemsCache.entries.elementAt(index);
                        final id = entry.key;
                        final data = entry.value;
                        final name = data['name'] ?? 'Unknown';
                        final price = data['price'] ?? 0;

                        final isSelected = _selectedItemIds.contains(id);

                        return CheckboxListTile(
                          title: Text(name),
                          subtitle: Text('QAR $price'),
                          value: isSelected,
                          onChanged: (bool? val) {
                            setModalState(() {
                              if (val == true) {
                                _selectedItemIds.add(id);
                              } else {
                                _selectedItemIds.remove(id);
                              }
                            });
                            setState(() {
                              // Ensure main screen state is updated too
                              if (val == true &&
                                  !_selectedItemIds.contains(id)) {
                                _selectedItemIds.add(id);
                              } else if (val == false) {
                                _selectedItemIds.remove(id);
                              }
                              _recalculateOriginalPrice();
                            });
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        centerTitle: true,
        title: Text(
          widget.docId == null ? 'Create Combo' : 'Edit Combo',
          style: const TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
      body: _isLoading && _menuItemsCache.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Status Card
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: Colors.grey[200]!),
                      ),
                      child: SwitchListTile(
                        title: const Text(
                          'Combo Active',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: const Text('Visible to customers in the app'),
                        value: _isActive,
                        onChanged: (v) => setState(() => _isActive = v),
                        activeColor: Colors.deepPurple,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Basics
                    const Text(
                      'Basic Info',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _nameCtrl,
                      decoration: InputDecoration(
                        labelText: 'Combo Name (English)',
                        hintText: 'e.g. Family Feast',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      validator: (v) => v!.isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _nameArCtrl,
                      textDirection: TextDirection.rtl,
                      decoration: InputDecoration(
                        labelText: 'Combo Name (Arabic) — اسم الكومبو',
                        hintText: 'e.g. وجبة العائلة',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _descCtrl,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: 'Description (English)',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _descArCtrl,
                      maxLines: 3,
                      textDirection: TextDirection.rtl,
                      decoration: InputDecoration(
                        labelText: 'Description (Arabic) — الوصف',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _sortOrderCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Sort Order (0 = highest)',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Branch Selection
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Applicable Branches',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            final branches = await showDialog<List<String>>(
                              context: context,
                              builder: (context) => BranchSelectorDialog(
                                initialSelectedBranchIds: _selectedBranchIds,
                                isMultiSelect: true,
                              ),
                            );
                            if (branches != null) {
                              setState(() => _selectedBranchIds = branches);
                            }
                          },
                          icon: const Icon(Icons.add_location_alt_outlined),
                          label: const Text('Select Branches'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_selectedBranchIds.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.error_outline, color: Colors.red),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Please select at least one branch.',
                                style: TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _selectedBranchIds.map((id) {
                          return Chip(
                            label: Text(
                              'Branch ID: $id',
                              style: const TextStyle(fontSize: 12),
                            ),
                            onDeleted: () {
                              setState(() => _selectedBranchIds.remove(id));
                            },
                          );
                        }).toList(),
                      ),
                    const SizedBox(height: 32),

                    // Item Selection
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Included Items',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _showItemSelectionDialog,
                          icon: const Icon(Icons.add),
                          label: const Text('Add Items'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_selectedItemIds.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.warning, color: Colors.orange),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Please select at least 2 items for this combo.',
                                style: TextStyle(color: Colors.deepOrange),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[200]!),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: _selectedItemIds.map((id) {
                            final item = _menuItemsCache[id];
                            if (item == null) {
                              return ListTile(
                                leading: const Icon(
                                  Icons.error,
                                  color: Colors.red,
                                ),
                                title: const Text(
                                  'Deleted Item',
                                  style: TextStyle(color: Colors.red),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.close),
                                  onPressed: () {
                                    setState(() {
                                      _selectedItemIds.remove(id);
                                      _recalculateOriginalPrice();
                                    });
                                  },
                                ),
                              );
                            }
                            return ListTile(
                              leading: item['imageUrl'] != null
                                  ? Image.network(
                                      item['imageUrl'],
                                      width: 40,
                                      height: 40,
                                      fit: BoxFit.cover,
                                    )
                                  : const Icon(Icons.fastfood),
                              title: Text(item['name']),
                              subtitle: Text('QAR ${item['price']}'),
                              trailing: IconButton(
                                icon: const Icon(
                                  Icons.close,
                                  color: Colors.red,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _selectedItemIds.remove(id);
                                    _recalculateOriginalPrice();
                                  });
                                },
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    const SizedBox(height: 32),

                    // Pricing
                    const Text(
                      'Pricing',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Original Total',
                                  style: TextStyle(color: Colors.grey),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'QAR ${_calculatedOriginalPrice.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _comboPriceCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Combo Price (QAR)',
                              labelStyle: const TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: Colors.green,
                                  width: 2,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: Colors.green.withValues(alpha: 0.5),
                                  width: 2,
                                ),
                              ),
                            ),
                            validator: (v) => v!.isEmpty ? 'Required' : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),

                    // Time Windows
                    const Text(
                      'Time Limits',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: Colors.grey[200]!),
                      ),
                      child: Column(
                        children: [
                          SwitchListTile(
                            title: const Text('Limited Time Offer'),
                            value: _isLimitedTime,
                            onChanged: (v) =>
                                setState(() => _isLimitedTime = v),
                          ),
                          if (_isLimitedTime)
                            Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () async {
                                        final d = await showDatePicker(
                                          context: context,
                                          initialDate:
                                              _startDate ?? DateTime.now(),
                                          firstDate: DateTime(2020),
                                          lastDate: DateTime(2030),
                                        );
                                        if (d != null) {
                                          setState(() => _startDate = d);
                                        }
                                      },
                                      icon: const Icon(
                                        Icons.calendar_today,
                                        size: 16,
                                      ),
                                      label: Text(
                                        _startDate != null
                                            ? _startDate!.toString().split(
                                                  ' ',
                                                )[0]
                                            : 'Start Date',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () async {
                                        final d = await showDatePicker(
                                          context: context,
                                          initialDate: _endDate ??
                                              DateTime.now().add(
                                                const Duration(days: 7),
                                              ),
                                          firstDate: DateTime(2020),
                                          lastDate: DateTime(2030),
                                        );
                                        if (d != null) {
                                          setState(() => _endDate = d);
                                        }
                                      },
                                      icon: const Icon(Icons.event, size: 16),
                                      label: Text(
                                        _endDate != null
                                            ? _endDate!.toString().split(' ')[0]
                                            : 'End Date',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 48),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _saveCombo,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          'Save Combo',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
