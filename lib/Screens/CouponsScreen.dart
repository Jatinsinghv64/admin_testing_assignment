import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class CouponManagementScreen extends StatelessWidget {
  const CouponManagementScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final couponCollection = FirebaseFirestore.instance.collection('coupons');

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.deepPurple),
        title: const Text(
          'Manage Coupons',
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
                showDialog(
                  context: context,
                  builder: (_) => const CouponDialog(),
                );
              },
            ),
          ),
        ],
      ),
      body: StreamBuilder(
        stream: couponCollection.orderBy('created_at', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.card_giftcard_outlined, size: 80, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No coupons found',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add your first coupon',
                    style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                  ),
                ],
              ),
            );
          }

          final docs = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map;
              final docId = docs[index].id;

              return _CouponCard(
                docId: docId,
                data: data,
                couponCollection: couponCollection,
              );
            },
          );
        },
      ),
    );
  }
}

class _CouponCard extends StatelessWidget {
  final String docId;
  final Map data;
  final CollectionReference couponCollection;

  const _CouponCard({
    required this.docId,
    required this.data,
    required this.couponCollection,
  });

  @override
  Widget build(BuildContext context) {
    // Basic Info
    final code = data['code'] ?? '';
    final titleEn = data['title'] ?? '';
    final titleAr = data['title_ar'] ?? '';

    // Display Title logic: Show Title (EN) if exists, else Code.
    final displayTitle = (titleEn != null && titleEn.isNotEmpty) ? titleEn : code;

    final value = data['value'] ?? 0;
    final type = data['type'] ?? 'fixed';
    final minSubtotal = data['min_subtotal'];
    final isActive = data['active'] ?? false;

    final branchIds = data['branchIds'] is List ? List.from(data['branchIds']) : [];
    final branchesText = branchIds.isNotEmpty ? branchIds.join(', ') : 'All Branches';

    final valueLabel = type == "percentage" ? "$value% off" : "QAR $value off";
    final restriction = (minSubtotal != null && minSubtotal > 0)
        ? "Min. order: QAR $minSubtotal"
        : "No minimum";

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
            // Header Row - Status and Code/Title
            Row(
              children: [
                // Status Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isActive ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isActive ? Icons.check_circle : Icons.cancel,
                        size: 14,
                        color: isActive ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isActive ? 'ACTIVE' : 'INACTIVE',
                        style: TextStyle(
                          color: isActive ? Colors.green : Colors.red,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                // Coupon Code Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.deepPurple, Colors.deepPurple.shade300],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    code,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                      color: Colors.white,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Display Titles if available
            if (titleEn.isNotEmpty || titleAr.isNotEmpty) ...[
              Text(
                titleEn,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87),
              ),
              if (titleAr.isNotEmpty)
                Text(
                  titleAr,
                  style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14, color: Colors.grey[700], fontFamily: 'NotoSansArabic'),
                  textDirection: TextDirection.rtl,
                ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 16),
            ] else ...[
              const Divider(height: 1),
              const SizedBox(height: 16),
            ],

            // Discount Value
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    type == "percentage" ? Icons.percent : Icons.attach_money,
                    color: Colors.orange,
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
                      valueLabel,
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

            // Info Chips Row
            Row(
              children: [
                Expanded(
                  child: _InfoChip(
                    icon: Icons.shopping_cart_outlined,
                    label: restriction,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _InfoChip(
                    icon: Icons.business_outlined,
                    label: '${branchIds.length} branches',
                    color: Colors.teal,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Branches Detail
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.location_on_outlined, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      branchesText,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.deepPurple.withOpacity(0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Edit', style: TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (_) => CouponDialog(
                            docId: docId,
                            initialData: data,
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.red.withOpacity(0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: () async {
                        final shouldDelete = await _confirmDelete(context);
                        if (shouldDelete) {
                          await couponCollection.doc(docId).delete();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Coupon deleted successfully')),
                            );
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
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

  static Future<bool> _confirmDelete(BuildContext context) async {
    final res = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.warning_amber_rounded, color: Colors.red),
            ),
            const SizedBox(width: 12),
            const Text('Delete Coupon?', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text('Are you sure you want to delete this coupon? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    return res ?? false;
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// Dialog remains mostly the same with slight styling updates
class CouponDialog extends StatefulWidget {
  final String? docId;
  final Map? initialData;

  const CouponDialog({this.docId, this.initialData, Key? key}) : super(key: key);

  @override
  State<CouponDialog> createState() => _CouponDialogState();
}

class _CouponDialogState extends State<CouponDialog> {
  final _formKey = GlobalKey<FormState>();

  // Existing Controllers
  late TextEditingController _codeCtrl, _typeCtrl, _valueCtrl;
  late TextEditingController _minSubtotalCtrl, _maxDiscountCtrl;

  // New Localized Controllers
  late TextEditingController _titleEnCtrl, _titleArCtrl;
  late TextEditingController _descEnCtrl, _descArCtrl;

  DateTime? _validFrom, _validUntil;
  bool _loading = false;
  bool _isActive = true;

  List<String> _selectedBranchIds = [];
  Map<String, String> _allBranches = {};
  bool _branchesLoading = true;

  @override
  void initState() {
    super.initState();
    final data = widget.initialData ?? {};

    // Initialize existing fields
    _codeCtrl = TextEditingController(text: data['code'] ?? '');
    _typeCtrl = TextEditingController(text: data['type'] ?? 'percentage');
    _valueCtrl = TextEditingController(text: data['value']?.toString() ?? '');
    _minSubtotalCtrl = TextEditingController(text: data['min_subtotal']?.toString() ?? '');
    _maxDiscountCtrl = TextEditingController(text: data['max_discount']?.toString() ?? '0');
    _isActive = data['active'] ?? true;

    // Initialize New Arabic/English fields
    _titleEnCtrl = TextEditingController(text: data['title'] ?? '');
    _titleArCtrl = TextEditingController(text: data['title_ar'] ?? '');
    _descEnCtrl = TextEditingController(text: data['description'] ?? '');
    _descArCtrl = TextEditingController(text: data['description_ar'] ?? '');

    _validFrom = (data['valid_from'] is Timestamp)
        ? (data['valid_from'] as Timestamp).toDate()
        : DateTime.now();
    _validUntil = (data['valid_until'] is Timestamp)
        ? (data['valid_until'] as Timestamp).toDate()
        : DateTime.now().add(const Duration(days: 7));

    if (data['branchIds'] is List) {
      _selectedBranchIds = List<String>.from(data['branchIds']);
    }

    _fetchBranches();
  }

  Future<void> _fetchBranches() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('Branch').get();
      final branches = {
        for (var doc in snapshot.docs) doc.id: doc.data()['name'] as String? ?? doc.id
      };
      if (mounted) {
        setState(() {
          _allBranches = branches;
          _branchesLoading = false;
        });
      }
    } catch (e) {
      setState(() => _branchesLoading = false);
    }
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _typeCtrl.dispose();
    _valueCtrl.dispose();
    _minSubtotalCtrl.dispose();
    _maxDiscountCtrl.dispose();
    _titleEnCtrl.dispose();
    _titleArCtrl.dispose();
    _descEnCtrl.dispose();
    _descArCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.docId != null;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
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
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.deepPurple.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isEdit ? Icons.edit : Icons.card_giftcard,
                          color: Colors.deepPurple,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          isEdit ? 'Edit Coupon' : 'Add Coupon',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.deepPurple,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Status Toggle
                  _formSectionHeader('Status'),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: SwitchListTile(
                      title: const Text('Active Coupon', style: TextStyle(fontWeight: FontWeight.w500)),
                      subtitle: Text(_isActive ? 'Coupon is currently active' : 'Coupon is inactive'),
                      value: _isActive,
                      onChanged: (val) => setState(() => _isActive = val),
                      activeColor: Colors.deepPurple,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // --- NEW SECTION: Display Info (Localized) ---
                  _formSectionHeader('Display Info'),
                  Row(
                    children: [
                      Expanded(
                        child: _roundedInput(_titleEnCtrl, 'Title (English)', Icons.title,
                            validator: (v) => v!.isEmpty ? 'Required' : null),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _roundedInput(_titleArCtrl, 'Title (Arabic)', Icons.translate, textDirection: TextDirection.rtl),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _roundedInput(_descEnCtrl, 'Description (English)', Icons.description),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _roundedInput(_descArCtrl, 'Description (Arabic)', Icons.description, textDirection: TextDirection.rtl),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  _formSectionHeader('Coupon Logic'),
                  _roundedInput(_codeCtrl, 'Code (Unique)', Icons.card_giftcard_rounded,
                      validator: (v) => v == null || v.isEmpty ? 'Code required' : null),
                  const SizedBox(height: 16),

                  _roundedInput(_typeCtrl, 'Type (percentage/fixed)', Icons.category,
                      validator: (v) => v == null || v.isEmpty ? 'Type required' : null),
                  const SizedBox(height: 16),

                  _roundedInput(_valueCtrl, 'Value', Icons.percent,
                      type: TextInputType.number,
                      validator: (v) => v == null || v.isEmpty ? 'Value required' : null),
                  const SizedBox(height: 24),

                  // Branches
                  _formSectionHeader('Applicable Branches'),
                  _buildBranchSelector(),
                  const SizedBox(height: 24),

                  _formSectionHeader('Restrictions'),
                  _roundedInput(_minSubtotalCtrl, 'Minimum Subtotal', Icons.attach_money,
                      type: TextInputType.number),
                  const SizedBox(height: 16),

                  _roundedInput(_maxDiscountCtrl, 'Maximum Discount', Icons.money_off,
                      type: TextInputType.number),
                  const SizedBox(height: 24),

                  _formSectionHeader('Validity Period'),
                  _dateRow('Valid From', _validFrom, (date) => setState(() => _validFrom = date)),
                  const SizedBox(height: 12),
                  _dateRow('Valid Until', _validUntil, (date) => setState(() => _validUntil = date)),
                  const SizedBox(height: 32),

                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _loading ? null : () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.deepPurple, width: 1.5),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text('Cancel',
                              style: TextStyle(color: Colors.deepPurple, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _loading ? null : (isEdit ? _editCoupon : _addCoupon),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepPurple,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: _loading
                              ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : Text(isEdit ? 'Update' : 'Add',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBranchSelector() {
    if (_branchesLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_allBranches.isEmpty) {
      return const Text('No branches found.');
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Select branches where this coupon will be available:',
            style: TextStyle(fontSize: 13, color: Colors.grey[700], fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8.0,
            runSpacing: 8.0,
            children: _allBranches.entries.map((entry) {
              final branchId = entry.key;
              final branchName = entry.value;
              final isSelected = _selectedBranchIds.contains(branchId);

              return FilterChip(
                label: Text(branchName),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    if (isSelected) {
                      _selectedBranchIds.remove(branchId);
                    } else {
                      _selectedBranchIds.add(branchId);
                    }
                  });
                },
                backgroundColor: Colors.white,
                selectedColor: Colors.deepPurple.withOpacity(0.2),
                checkmarkColor: Colors.deepPurple,
                labelStyle: TextStyle(
                  color: isSelected ? Colors.deepPurple : Colors.black87,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: isSelected ? Colors.deepPurple : Colors.grey.shade300,
                    width: isSelected ? 2 : 1,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _formSectionHeader(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8.0),
    child: Row(
      children: [
        Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(
            color: Colors.deepPurple,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Colors.deepPurple,
          ),
        ),
      ],
    ),
  );

  Widget _roundedInput(TextEditingController c, String label, IconData icon,
      {String? Function(String?)? validator, TextInputType? type, TextDirection? textDirection}) {
    return TextFormField(
      controller: c,
      keyboardType: type,
      validator: validator,
      textDirection: textDirection,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.deepPurple),
        filled: true,
        fillColor: Colors.grey[50],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.deepPurple, width: 2),
        ),
      ),
    );
  }

  Widget _dateRow(String label, DateTime? date, ValueChanged<DateTime> onPick) {
    return GestureDetector(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date ?? DateTime.now(),
          firstDate: DateTime(2022),
          lastDate: DateTime(2100),
        );
        if (picked != null) onPick(picked);
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[300]!),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.calendar_today_rounded, color: Colors.deepPurple, size: 20),
            const SizedBox(width: 12),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15)),
            const Spacer(),
            Text(
              date != null
                  ? '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}'
                  : 'Select Date',
              style: const TextStyle(
                color: Colors.deepPurple,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.deepPurple),
          ],
        ),
      ),
    );
  }

  Future<void> _addCoupon() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _loading = true);
    final data = _formData(newCoupon: true);
    await FirebaseFirestore.instance.collection('coupons').add(data);
    setState(() => _loading = false);
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Coupon added successfully')),
      );
    }
  }

  Future<void> _editCoupon() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _loading = true);
    final data = _formData(newCoupon: false);
    await FirebaseFirestore.instance.collection('coupons').doc(widget.docId).update(data);
    setState(() => _loading = false);
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Coupon updated successfully')),
      );
    }
  }

  Map<String, dynamic> _formData({bool newCoupon = false}) {
    final data = {
      // New Fields
      'title': _titleEnCtrl.text.trim(),
      'title_ar': _titleArCtrl.text.trim(),
      'description': _descEnCtrl.text.trim(),
      'description_ar': _descArCtrl.text.trim(),

      // Existing Fields
      'code': _codeCtrl.text.trim(),
      'type': _typeCtrl.text.trim(),
      'value': num.tryParse(_valueCtrl.text) ?? 0,
      'min_subtotal': num.tryParse(_minSubtotalCtrl.text) ?? 0,
      'max_discount': num.tryParse(_maxDiscountCtrl.text) ?? 0,
      'valid_from': _validFrom ?? DateTime.now(),
      'valid_until': _validUntil ?? DateTime.now(),
      'active': _isActive,
      'branchIds': _selectedBranchIds,
    };
    if (newCoupon) {
      data['created_at'] = FieldValue.serverTimestamp();
    }
    return data;
  }
}