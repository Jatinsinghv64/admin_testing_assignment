import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../Widgets/BranchFilterService.dart';
import '../../main.dart';
import '../../services/inventory/PurchaseOrderService.dart';

class SuppliersScreen extends StatefulWidget {
  const SuppliersScreen({super.key});

  @override
  State<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends State<SuppliersScreen> {
  late final PurchaseOrderService _service;
  bool _serviceInitialized = false;
  String _filter = 'all'; 
  String _categoryFilter = 'All';
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  final List<String> availableCategories = [
    'Produce',
    'Dairy',
    'Meat',
    'Poultry',
    'Seafood',
    'Spices',
    'Dry Goods',
    'Beverages',
    'Packaging',
    'Other'
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_serviceInitialized) {
      _serviceInitialized = true;
      _service = Provider.of<PurchaseOrderService>(context, listen: false);
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userScope = context.watch<UserScopeService>();
    final branchFilter = context.watch<BranchFilterService>();
    final branchIds = branchFilter.getFilterBranchIds(userScope.branchIds);

    bool? streamIsActive;
    if (_filter == 'active') {
      streamIsActive = true;
    } else if (_filter == 'inactive') {
      streamIsActive = false;
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Column(
        children: [
          // Header Section
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Suppliers', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black87)),
                    Text('Manage supplier relationships and contact information.', style: TextStyle(color: Colors.grey[600])),
                  ],
                ),
                Row(
                  children: [
                    Container(
                      width: 280,
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: InputDecoration(
                          hintText: 'Search suppliers...',
                          hintStyle: TextStyle(color: Colors.grey[500], fontSize: 14),
                          prefixIcon: Icon(Icons.search, color: Colors.grey[500], size: 20),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          isDense: true,
                        ),
                        onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
                      ),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: () => _openSupplierForm(context, userScope, branchIds),
                      icon: const Icon(Icons.add, size: 20),
                      label: const Text('Add New Supplier', style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Filter Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Supplier Directory', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)),
                      Row(
                        children: [
                          _statusFilterButton('All', 'all'),
                          const SizedBox(width: 8),
                          _statusFilterButton('Active', 'active'),
                          const SizedBox(width: 8),
                          _statusFilterButton('Inactive', 'inactive'),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _categoryFilterChip('All'),
                        ...availableCategories.map((c) => Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: _categoryFilterChip(c),
                            )),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  Expanded(
                    child: StreamBuilder<List<Map<String, dynamic>>>(
                      stream: _service.streamSuppliers(
                        branchIds,
                        isActive: streamIsActive,
                      ),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(color: Colors.deepPurple),
                          );
                        }
                        if (snapshot.hasError) {
                          return Center(
                            child: Text(
                              'Failed to load suppliers: ${snapshot.error}',
                              style: const TextStyle(color: Colors.red),
                            ),
                          );
                        }
                        var suppliers = snapshot.data ?? [];

                        // Apply Search Filter
                        if (_searchQuery.isNotEmpty) {
                          suppliers = suppliers.where((s) {
                            final name = (s['companyName'] ?? '').toString().toLowerCase();
                            final contact = (s['contactPerson'] ?? '').toString().toLowerCase();
                            final email = (s['email'] ?? '').toString().toLowerCase();
                            return name.contains(_searchQuery) || contact.contains(_searchQuery) || email.contains(_searchQuery);
                          }).toList();
                        }

                        // Apply Category Filter
                        if (_categoryFilter != 'All') {
                          suppliers = suppliers.where((s) {
                            final cats = List<String>.from(s['supplierCategories'] as List? ?? []);
                            return cats.contains(_categoryFilter);
                          }).toList();
                        }

                        if (suppliers.isEmpty) {
                          return const Center(child: Text('No suppliers found.', style: TextStyle(fontSize: 16, color: Colors.grey)));
                        }
                        
                        return LayoutBuilder(
                          builder: (context, constraints) {
                            int crossAxisCount = 1;
                            if (constraints.maxWidth >= 1200) {
                              crossAxisCount = 3;
                            } else if (constraints.maxWidth >= 800) {
                              crossAxisCount = 2;
                            }
                            
                            return GridView.builder(
                              padding: const EdgeInsets.only(bottom: 32),
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: crossAxisCount,
                                mainAxisExtent: 340,
                                crossAxisSpacing: 24,
                                mainAxisSpacing: 24,
                              ),
                              itemCount: suppliers.length,
                              itemBuilder: (_, i) {
                                final s = suppliers[i];
                                return _supplierCard(
                                  context: context,
                                  data: s,
                                  onEdit: () => _openSupplierForm(
                                    context,
                                    userScope,
                                    branchIds,
                                    existing: s,
                                  ),
                                );
                              },
                            );
                          }
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusFilterButton(String label, String value) {
    final isSelected = _filter == value;
    return InkWell(
      onTap: () => setState(() => _filter = value),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.deepPurple.shade50 : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.deepPurple : Colors.grey.shade600,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _categoryFilterChip(String label) {
    final selected = _categoryFilter == label;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => setState(() => _categoryFilter = label),
      color: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? Colors.deepPurple
            : Colors.white;
      }),
      side: BorderSide(
        color: selected ? Colors.deepPurple : Colors.grey.shade300,
      ),
      labelStyle: TextStyle(
        color: selected ? Colors.white : Colors.grey[700],
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  Widget _supplierCard({
    required BuildContext context,
    required Map<String, dynamic> data,
    required VoidCallback onEdit,
  }) {
    final isActive = data['isActive'] == true;
    final companyName = (data['companyName'] ?? '').toString();
    final initials = companyName.isNotEmpty 
        ? companyName.substring(0, companyName.length > 1 ? 2 : 1).toUpperCase() 
        : 'S';
    final contactPerson = (data['contactPerson']?.toString().trim().isEmpty ?? true) ? '-' : data['contactPerson'].toString();
    final phone = (data['phone']?.toString().trim().isEmpty ?? true) ? '-' : data['phone'].toString();
    final email = (data['email']?.toString().trim().isEmpty ?? true) ? '-' : data['email'].toString();
    final paymentTerms = (data['paymentTerms'] ?? 'Net 30').toString();
    final List cats = data['supplierCategories'] as List? ?? [];
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.deepPurple.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.deepPurple.shade100),
                ),
                child: Center(
                  child: Text(
                    initials, 
                    style: TextStyle(
                      color: Colors.deepPurple.shade700, 
                      fontWeight: FontWeight.bold, 
                      fontSize: 20
                    )
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      companyName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black87),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          width: 8, height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isActive ? Colors.green : Colors.grey,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isActive ? 'Active' : 'Inactive',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.grey.shade600),
                        ),
                      ],
                    )
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.more_vert, color: Colors.grey.shade400),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: onEdit, 
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          const Divider(height: 1, color: Color(0xFFEEEEEE)),
          const SizedBox(height: 16),
          
          _infoRow(Icons.person_outline, contactPerson),
          const SizedBox(height: 10),
          _infoRow(Icons.phone_outlined, phone, isPhone: true, phoneValue: data['phone']?.toString()),
          const SizedBox(height: 10),
          _infoRow(Icons.email_outlined, email, isEmail: true, emailValue: data['email']?.toString()),
          
          const Spacer(),
          
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('TOP SUPPLIED', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade400, letterSpacing: 0.5)),
                    const SizedBox(height: 8),
                    cats.isEmpty 
                      ? Text('-', style: TextStyle(color: Colors.grey.shade500, fontSize: 12))
                      : Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: cats.take(3).map((cat) => 
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(cat.toString(), style: TextStyle(fontSize: 10, color: Colors.grey.shade700)),
                            )
                          ).toList(),
                        ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('PAYMENT TERMS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade400, letterSpacing: 0.5)),
                  const SizedBox(height: 8),
                  Text(
                    paymentTerms, 
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.black87),
                  ),
                ],
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.person_outline, size: 18),
              label: const Text('View Profile'),
              style: TextButton.styleFrom(
                backgroundColor: Colors.grey.shade50,
                foregroundColor: Colors.deepPurple,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String text, {bool isPhone = false, bool isEmail = false, String? phoneValue, String? emailValue}) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade400),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (isPhone && (phoneValue?.trim().isNotEmpty ?? false))
          InkWell(
            onTap: () async {
              final uri = Uri.parse('tel:${phoneValue!.trim()}');
              if (await canLaunchUrl(uri)) await launchUrl(uri);
            },
            child: const Icon(Icons.call, size: 16, color: Colors.green),
          ),
        if (isEmail && (emailValue?.trim().isNotEmpty ?? false))
          Padding(
            padding: const EdgeInsets.only(left: 8.0),
            child: InkWell(
              onTap: () async {
                final uri = Uri.parse('mailto:${emailValue!.trim()}');
                if (await canLaunchUrl(uri)) await launchUrl(uri);
              },
              child: const Icon(Icons.email, size: 16, color: Colors.deepPurple),
            ),
          ),
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
                                  ? Colors.deepPurple.withValues(alpha: 0.3)
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

  Future<void> _openSupplierForm(
    BuildContext context,
    UserScopeService userScope,
    List<String> branchIds, {
    Map<String, dynamic>? existing,
  }) async {
    final isEdit = existing != null;
    final companyCtrl = TextEditingController(
        text: (existing?['companyName'] ?? '').toString());
    final contactCtrl = TextEditingController(
        text: (existing?['contactPerson'] ?? '').toString());
    final phoneCtrl =
        TextEditingController(text: (existing?['phone'] ?? '').toString());
    final emailCtrl =
        TextEditingController(text: (existing?['email'] ?? '').toString());
    final addressCtrl =
        TextEditingController(text: (existing?['address'] ?? '').toString());
    final notesCtrl =
        TextEditingController(text: (existing?['notes'] ?? '').toString());
    final ingredientIds =
        List<String>.from(existing?['ingredientIds'] as List? ?? []);
    final supplierCategories =
        List<String>.from(existing?['supplierCategories'] as List? ?? []);
    String paymentTerms = (existing?['paymentTerms'] ?? 'Net 30').toString();
    bool isActive = existing?['isActive'] != false;
    int rating = (existing?['rating'] as num?)?.toInt() ?? 0;
    final formKey = GlobalKey<FormState>();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheet) {
          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isEdit ? 'Edit Supplier' : 'Add Supplier',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.deepPurple,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildTextInput(
                      controller: companyCtrl,
                      label: 'Company name *',
                      icon: Icons.business_outlined,
                      required: true,
                    ),
                    const SizedBox(height: 10),
                    _buildTextInput(
                      controller: contactCtrl,
                      label: 'Contact person',
                      icon: Icons.person_outline,
                    ),
                    const SizedBox(height: 10),
                    _buildTextInput(
                      controller: phoneCtrl,
                      label: 'Phone',
                      icon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 10),
                    _buildTextInput(
                      controller: emailCtrl,
                      label: 'Email',
                      icon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 10),
                    _buildTextInput(
                      controller: addressCtrl,
                      label: 'Address',
                      icon: Icons.location_on_outlined,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 10),
                    _buildSelector(
                      label: 'Payment terms',
                      value: paymentTerms,
                      items: const ['Net 15', 'Net 30', 'COD', 'Prepaid'],
                      onChanged: (v) => setSheet(() => paymentTerms = v),
                      icon: Icons.payments_outlined,
                    ),
                    const SizedBox(height: 12),
                    const Text('Categories',
                        style: TextStyle(
                            fontSize: 14,
                            color: Colors.black87,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: availableCategories.map((cat) {
                        final isSelected = supplierCategories.contains(cat);
                        return FilterChip(
                          label: Text(cat),
                          selected: isSelected,
                          onSelected: (selected) {
                            setSheet(() {
                              if (selected) {
                                supplierCategories.add(cat);
                              } else {
                                supplierCategories.remove(cat);
                              }
                            });
                          },
                          selectedColor: Colors.deepPurple.shade100,
                          checkmarkColor: Colors.deepPurple,
                          labelStyle: TextStyle(
                            color: isSelected
                                ? Colors.deepPurple.shade900
                                : Colors.black87,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(left: 12),
                          child: Icon(Icons.star_outline,
                              size: 20, color: Colors.deepPurple),
                        ),
                        const SizedBox(width: 12),
                        Wrap(
                          spacing: 6,
                          children: List.generate(
                            5,
                            (i) => IconButton(
                              onPressed: () => setSheet(() => rating = i + 1),
                              icon: Icon(
                                i < rating ? Icons.star : Icons.star_border,
                                color: Colors.amber,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
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
                        title: const Text('Active',
                            style: TextStyle(fontSize: 14)),
                        value: isActive,
                        onChanged: (v) => setSheet(() => isActive = v),
                        secondary: Icon(Icons.check_circle_outline,
                            color: isActive ? Colors.green : Colors.grey),
                        activeColor: Colors.deepPurple,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildTextInput(
                      controller: notesCtrl,
                      label: 'Notes',
                      icon: Icons.notes_outlined,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          if (!formKey.currentState!.validate()) return;
                          try {
                            await _service.saveSupplier(
                              supplierId: existing?['id']?.toString(),
                              branchIds: branchIds,
                              data: {
                                'companyName': companyCtrl.text.trim(),
                                'contactPerson': contactCtrl.text.trim(),
                                'phone': phoneCtrl.text.trim(),
                                'email': emailCtrl.text.trim(),
                                'address': addressCtrl.text.trim(),
                                'paymentTerms': paymentTerms,
                                'notes': notesCtrl.text.trim(),
                                'ingredientIds': ingredientIds,
                                'supplierCategories': supplierCategories,
                                'rating': rating,
                                'isActive': isActive,
                              },
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(isEdit
                                      ? 'Supplier updated'
                                      : 'Supplier added'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Save failed: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(isEdit ? 'Save Changes' : 'Add Supplier'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        });
      },
    );
  }
}
