import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../Models/promo_models.dart';
import '../utils/responsive_helper.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../Widgets/BranchFilterService.dart';
import '../Widgets/BranchSelectorDialog.dart';

class PromoSalesScreen extends StatelessWidget {
  const PromoSalesScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final salesCollection = FirebaseFirestore.instance.collection('promoSales');
    final userScope = Provider.of<UserScopeService>(context);
    final branchFilter = Provider.of<BranchFilterService>(context);
    final effectiveBranchIds =
        branchFilter.getFilterBranchIds(userScope.branchIds);

    Query query = salesCollection.orderBy('priority', descending: true);

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
          'Manage Promo Sales',
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
                  color: Colors.deepPurple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.add, color: Colors.deepPurple),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const PromoSaleAddEditScreen(),
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
                    Icons.campaign_outlined,
                    size: 80,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No promo sales found',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Create your first sale event (e.g. Eid Discount)',
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
                return _PromoSaleCard(
                  doc: doc,
                  salesCollection: salesCollection,
                );
              },
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              return _PromoSaleCard(doc: doc, salesCollection: salesCollection);
            },
          );
        },
      ),
    );
  }
}

class _PromoSaleCard extends StatelessWidget {
  final DocumentSnapshot doc;
  final CollectionReference salesCollection;

  const _PromoSaleCard({required this.doc, required this.salesCollection});

  @override
  Widget build(BuildContext context) {
    final sale = PromoSaleModel.fromMap(
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
            color: Colors.black.withOpacity(0.05),
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
            // Status and Priority
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: sale.isActive
                        ? Colors.green.withOpacity(0.1)
                        : Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        sale.isActive ? Icons.check_circle : Icons.cancel,
                        size: 14,
                        color: sale.isActive ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        sale.isActive ? 'ACTIVE' : 'INACTIVE',
                        style: TextStyle(
                          color: sale.isActive ? Colors.green : Colors.red,
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
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Priority: ${sale.priority}',
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

            // Title
            Text(
              sale.name,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Colors.black87,
              ),
            ),
            if (sale.nameAr != null && sale.nameAr!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                sale.nameAr!,
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
              'Scope: ${sale.targetType.toUpperCase()}',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),

            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // Discount
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.pink.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    sale.discountType == "percentage"
                        ? Icons.percent
                        : Icons.attach_money,
                    color: Colors.pink,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Discount',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sale.discountType == "percentage"
                          ? '${sale.discountValue}% off'
                          : 'QAR ${sale.discountValue} off',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 12),
            Text(
              'Expires: ${sale.endDate.toString().split(' ')[0]}',
              style: TextStyle(fontSize: 13, color: Colors.grey[500]),
            ),

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
                          builder: (context) => PromoSaleAddEditScreen(
                            docId: sale.saleId,
                            saleModel: sale,
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
        title: const Text('Delete Sale?'),
        content: const Text('Are you sure you want to delete this sale?'),
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
      await salesCollection.doc(doc.id).delete();
    }
  }
}

// --------------------------------------------------------------------------
// ADD / EDIT SCREEN
// --------------------------------------------------------------------------

class PromoSaleAddEditScreen extends StatefulWidget {
  final String? docId;
  final PromoSaleModel? saleModel;

  const PromoSaleAddEditScreen({Key? key, this.docId, this.saleModel})
      : super(key: key);

  @override
  State<PromoSaleAddEditScreen> createState() => _PromoSaleAddEditScreenState();
}

class _PromoSaleAddEditScreenState extends State<PromoSaleAddEditScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameCtrl;
  late TextEditingController _nameArCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _descArCtrl;
  late TextEditingController _discountValueCtrl;
  late TextEditingController _priorityCtrl;
  late TextEditingController _maxDiscountCapCtrl;
  late TextEditingController _minOrderValueCtrl;
  late TextEditingController _imageUrlCtrl;

  bool _isActive = true;
  bool _stackableWithCoupons = false;
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now().add(const Duration(days: 7));

  String _discountType = 'percentage';
  String _targetType = 'all';

  List<String> _selectedItemIds = [];
  List<String> _selectedCategoryIds = [];
  List<String> _selectedBranchIds = [];

  bool _isLoading = false;

  Map<String, String> _menuCategoriesCache = {};
  Map<String, Map<String, dynamic>> _menuItemsCache = {};

  @override
  void initState() {
    super.initState();
    final sale = widget.saleModel;

    _nameCtrl = TextEditingController(text: sale?.name ?? '');
    _nameArCtrl = TextEditingController(text: sale?.nameAr ?? '');
    _descCtrl = TextEditingController(text: sale?.description ?? '');
    _descArCtrl = TextEditingController(text: sale?.descriptionAr ?? '');
    _discountValueCtrl = TextEditingController(
      text: sale?.discountValue.toString() ?? '',
    );
    _priorityCtrl = TextEditingController(
      text: sale?.priority.toString() ?? '0',
    );
    _maxDiscountCapCtrl = TextEditingController(
      text: sale?.maxDiscountCap?.toString() ?? '',
    );
    _minOrderValueCtrl = TextEditingController(
      text: sale?.minOrderValue?.toString() ?? '',
    );
    _imageUrlCtrl = TextEditingController(text: sale?.imageUrl ?? '');

    _isActive = sale?.isActive ?? true;
    _stackableWithCoupons = sale?.stackableWithCoupons ?? false;

    if (sale != null) {
      _startDate = sale.startDate;
      _endDate = sale.endDate;
      _discountType = sale.discountType;
      _targetType = sale.targetType;

      if (sale.targetItemIds != null)
        _selectedItemIds = List<String>.from(sale.targetItemIds!);
      if (sale.targetCategoryIds != null)
        _selectedCategoryIds = List<String>.from(sale.targetCategoryIds!);
      _selectedBranchIds = List<String>.from(sale.branchIds);
    }

    _fetchLookups();
  }

  Future<void> _fetchLookups() async {
    setState(() => _isLoading = true);
    try {
      final db = FirebaseFirestore.instance;

      // Fetch categories
      final catSnap = await db.collection('menu_categories').get();
      final Map<String, String> cats = {};
      for (var doc in catSnap.docs) {
        final d = doc.data();
        final nameEn = (d['name'] ?? doc.id).toString();
        final nameAr = (d['name_ar'] ?? '').toString();
        cats[doc.id] = nameAr.isNotEmpty ? '$nameEn / $nameAr' : nameEn;
      }

      // Fetch items
      final itemSnap = await db.collection('menu_items').get();
      final Map<String, Map<String, dynamic>> items = {};
      for (var doc in itemSnap.docs) {
        items[doc.id] = doc.data();
      }

      if (mounted) {
        setState(() {
          _menuCategoriesCache = cats;
          _menuItemsCache = items;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching lookups: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSale() async {
    if (!_formKey.currentState!.validate()) return;

    if (_targetType == 'category' && _selectedCategoryIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least 1 category.')),
      );
      return;
    }
    if (_targetType == 'specific_items' && _selectedItemIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least 1 item.')),
      );
      return;
    }

    if (_endDate.isBefore(_startDate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End Date must be after Start Date.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final db = FirebaseFirestore.instance;

      final saleId =
          widget.docId ?? _nameCtrl.text.replaceAll(' ', '_').toLowerCase();
      final discountValue = double.tryParse(_discountValueCtrl.text) ?? 0.0;

      final sale = PromoSaleModel(
        saleId: saleId,
        name: _nameCtrl.text,
        nameAr:
            _nameArCtrl.text.trim().isEmpty ? null : _nameArCtrl.text.trim(),
        description: _descCtrl.text,
        descriptionAr:
            _descArCtrl.text.trim().isEmpty ? null : _descArCtrl.text.trim(),
        imageUrl: _imageUrlCtrl.text,
        discountType: _discountType,
        discountValue: discountValue,
        targetType: _targetType,
        targetItemIds:
            _targetType == 'specific_items' ? _selectedItemIds : null,
        targetCategoryIds:
            _targetType == 'category' ? _selectedCategoryIds : null,
        startDate: _startDate,
        endDate: _endDate,
        isActive: _isActive,
        stackableWithCoupons: _stackableWithCoupons,
        minOrderValue: double.tryParse(_minOrderValueCtrl.text),
        maxDiscountCap: double.tryParse(_maxDiscountCapCtrl.text),
        priority: int.tryParse(_priorityCtrl.text) ?? 0,
        branchIds: _selectedBranchIds,
      );

      await db.collection('promoSales').doc(saleId).set(sale.toMap());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Promo Sale saved successfully')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save promo sale')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showMultiSelectDialog(
    String title,
    Map<String, String> lookupMap,
    List<String> selectedList,
  ) {
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
                        Text(
                          title,
                          style: const TextStyle(
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
                      itemCount: lookupMap.length,
                      itemBuilder: (context, index) {
                        final id = lookupMap.keys.elementAt(index);
                        final name = lookupMap[id]!;
                        final isSelected = selectedList.contains(id);

                        return CheckboxListTile(
                          title: Text(name),
                          value: isSelected,
                          onChanged: (bool? val) {
                            setModalState(() {
                              if (val == true)
                                selectedList.add(id);
                              else
                                selectedList.remove(id);
                            });
                            setState(() {}); // trigger main UI reload
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

  Future<void> _selectDateTime(BuildContext context, bool isStart) async {
    final DateTime initialDate = isStart ? _startDate : _endDate;
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.deepPurple,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (pickedDate != null) {
      final TimeOfDay? pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(initialDate),
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: const ColorScheme.light(
                primary: Colors.deepPurple,
                onPrimary: Colors.white,
                onSurface: Colors.black,
              ),
            ),
            child: child!,
          );
        },
      );

      if (pickedTime != null) {
        setState(() {
          final newDateTime = DateTime(
            pickedDate.year,
            pickedDate.month,
            pickedDate.day,
            pickedTime.hour,
            pickedTime.minute,
          );
          if (isStart) {
            _startDate = newDateTime;
          } else {
            _endDate = newDateTime;
          }
        });
      }
    }
  }

  Widget _buildDateTimePickerField(String label, DateTime value, bool isStart) {
    final String formattedDate =
        '${value.day}/${value.month}/${value.year} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

    return InkWell(
      onTap: () => _selectDateTime(context, isStart),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  isStart ? Icons.calendar_today : Icons.event,
                  size: 16,
                  color: Colors.deepPurple,
                ),
                const SizedBox(width: 8),
                Text(
                  formattedDate,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
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
          widget.docId == null ? 'Create Promo Sale' : 'Edit Promo Sale',
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
      body: _isLoading && _menuCategoriesCache.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Status
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: Colors.grey[200]!),
                      ),
                      child: SwitchListTile(
                        title: const Text(
                          'Sale Active',
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
                        labelText: 'Sale Name (English)',
                        hintText: 'e.g. Eid Mega Sale',
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
                        labelText: 'Sale Name (Arabic) — اسم العرض',
                        hintText: 'e.g. تخفيضات العيد',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _descCtrl,
                      maxLines: 2,
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
                      maxLines: 2,
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
                      controller: _imageUrlCtrl,
                      decoration: InputDecoration(
                        labelText: 'Banner Image URL (Optional)',
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

                    // Discount Scope
                    const Text(
                      'Discount Scope',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _targetType,
                      decoration: InputDecoration(
                        labelText: 'Apply Discount To',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'all',
                          child: Text('Entire Store'),
                        ),
                        DropdownMenuItem(
                          value: 'category',
                          child: Text('Specific Categories'),
                        ),
                        DropdownMenuItem(
                          value: 'specific_items',
                          child: Text('Specific Menu Items'),
                        ),
                      ],
                      onChanged: (v) => setState(() => _targetType = v!),
                    ),
                    const SizedBox(height: 16),

                    if (_targetType == 'category') ...[
                      OutlinedButton.icon(
                        onPressed: () => _showMultiSelectDialog(
                          'Select Categories',
                          _menuCategoriesCache,
                          _selectedCategoryIds,
                        ),
                        icon: const Icon(Icons.list),
                        label: Text(
                          'Select Categories (${_selectedCategoryIds.length} chosen)',
                        ),
                      ),
                    ] else if (_targetType == 'specific_items') ...[
                      OutlinedButton.icon(
                        onPressed: () {
                          // Build flat map of items for multi-select
                          Map<String, String> itemLookup = {};
                          _menuItemsCache.forEach(
                            (k, v) => itemLookup[k] = v['name'],
                          );
                          _showMultiSelectDialog(
                            'Select Items',
                            itemLookup,
                            _selectedItemIds,
                          );
                        },
                        icon: const Icon(Icons.fastfood),
                        label: Text(
                          'Select Items (${_selectedItemIds.length} chosen)',
                        ),
                      ),
                    ],
                    const SizedBox(height: 32),

                    // Discount
                    const Text(
                      'Discount Setup',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _discountType,
                            decoration: InputDecoration(
                              labelText: 'Type',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'percentage',
                                child: Text('Percentage (%)'),
                              ),
                              DropdownMenuItem(
                                value: 'fixed',
                                child: Text('Fixed Amount (QAR)'),
                              ),
                            ],
                            onChanged: (v) =>
                                setState(() => _discountType = v!),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _discountValueCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Value',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            validator: (v) => v!.isEmpty ? 'Required' : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_discountType == 'percentage')
                      TextFormField(
                        controller: _maxDiscountCapCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Max Discount Cap (QAR) - Optional',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    const SizedBox(height: 32),

                    // Dates and Extras
                    const Text(
                      'Duration & Priority',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildDateTimePickerField(
                            'Start Date & Time',
                            _startDate,
                            true,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildDateTimePickerField(
                            'End Date & Time',
                            _endDate,
                            false,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _priorityCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Priority (Higher = applied first)',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      title: const Text('Stackable with Coupons'),
                      subtitle: const Text(
                        'Allow user to apply a code on top of this sale',
                      ),
                      value: _stackableWithCoupons,
                      onChanged: (v) =>
                          setState(() => _stackableWithCoupons = v),
                      contentPadding: EdgeInsets.zero,
                    ),

                    const SizedBox(height: 48),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _saveSale,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          'Save Promo Sale',
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
