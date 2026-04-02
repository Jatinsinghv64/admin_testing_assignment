import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../Models/promo_models.dart';
import '../main.dart';
import '../Widgets/BranchFilterService.dart';
import '../Widgets/BranchFilterSelector.dart';
import 'ComboMealsScreen.dart'; // For ComboMealAddEditScreen
import 'PromoSalesScreen.dart'; // For PromoSaleAddEditScreen
import 'CouponsScreen.dart'; // For CouponDialog
import '../constants.dart';
import '../Widgets/ExportReportDialog.dart';

class PromotionsScreenLarge extends StatefulWidget {
  const PromotionsScreenLarge({super.key});

  @override
  State<PromotionsScreenLarge> createState() => _PromotionsScreenLargeState();
}

class _PromotionsScreenLargeState extends State<PromotionsScreenLarge> {
  String _selectedCategory = 'combos'; // combos, sales, coupons
  String _selectedFilter = 'Active'; // Active, Scheduled, Archived
  String? _selectedPromoId;
  dynamic _selectedPromoData;
  List<String> _editingBranchIds = [];
  final TextEditingController _searchController = TextEditingController();
  
  // Editor Controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _nameArController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _descArController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _valueController = TextEditingController();
  final TextEditingController _minSubtotalController = TextEditingController();
  final TextEditingController _maxDiscountController = TextEditingController();
  final TextEditingController _maxUsesController = TextEditingController();
  final TextEditingController _priorityController = TextEditingController();
  final TextEditingController _targetTypeController = TextEditingController();
  final TextEditingController _imageUrlController = TextEditingController();

  bool _isSaving = false;
  final Set<String> _processingExpirations = {};

  // Stable stream references
  Stream<QuerySnapshot>? _orderKPIStream;
  Stream<QuerySnapshot>? _comboKPIStream;
  Stream<QuerySnapshot>? _saleKPIStream;
  Stream<QuerySnapshot>? _couponKPIStream;
  Stream<QuerySnapshot>? _inventoryStream;

  List<String>? _lastKPIBranchIds;
  List<String>? _lastInventoryBranchIds;
  String? _lastInventoryCategory;
  String? _lastInventoryFilter;

  @override
  void dispose() {
    _searchController.dispose();
    _nameController.dispose();
    _nameArController.dispose();
    _descController.dispose();
    _descArController.dispose();
    _imageUrlController.dispose();
    _codeController.dispose();
    _valueController.dispose();
    _minSubtotalController.dispose();
    _maxDiscountController.dispose();
    _maxUsesController.dispose();
    _priorityController.dispose();
    _targetTypeController.dispose();
    super.dispose();
  }

  void _loadPromoData(Map<String, dynamic> data) {
    _selectedPromoData = data;
    _nameController.text = (data['name'] ?? data['title'] ?? '').toString();
    _nameArController.text = (data['nameAr'] ?? data['title_ar'] ?? '').toString();
    _descController.text = (data['description'] ?? '').toString();
    _descArController.text = (data['description_ar'] ?? data['descriptionAr'] ?? '').toString();
    _codeController.text = (data['code'] ?? '').toString();
    _valueController.text = (data['value'] ?? data['discountValue'] ?? data['comboPrice'] ?? 0).toString();
    _minSubtotalController.text = (data['min_subtotal'] ?? data['minOrderValue'] ?? 0).toString();
    _maxDiscountController.text = (data['max_discount'] ?? data['maxDiscountCap'] ?? 0).toString();
    _maxUsesController.text = (data['maxUsesPerUser']?.toString() ?? '');
    _priorityController.text = (data['priority']?.toString() ?? '0');
    _targetTypeController.text = (data['targetType'] ?? 'all').toString();
    _imageUrlController.text = (data['imageUrl'] ?? '').toString();
    _editingBranchIds = List<String>.from(data['branchIds'] ?? data['branchids'] ?? []);
  }

  Future<void> _updateProperty(String field, dynamic value) async {
    if (_selectedPromoId == null) return;
    String collection = _selectedCategory == 'combos' ? 'combos' : (_selectedCategory == 'sales' ? 'promoSales' : AppConstants.collectionCoupons);
    
    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance.collection(collection).doc(_selectedPromoId).update({
        field: value,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
      // Update local state to keep UI in sync without waiting for stream
      setState(() {
        _selectedPromoData[field] = value;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error updating $field: $e')));
    } finally {
      setState(() => _isSaving = false);
    }
  }

  void _updateKPIStreams(List<String> filterBranchIds) {
    final bool branchIdsChanged = _lastKPIBranchIds == null || 
        _lastKPIBranchIds!.length != filterBranchIds.length ||
        !_lastKPIBranchIds!.every((id) => filterBranchIds.contains(id));

    if (branchIdsChanged) {
      Query orderQuery = FirebaseFirestore.instance.collection(AppConstants.collectionOrders).orderBy('timestamp', descending: true).limit(500);
      if (filterBranchIds.isNotEmpty) {
        orderQuery = orderQuery.where('branchIds', arrayContainsAny: filterBranchIds);
      }
      _orderKPIStream = orderQuery.snapshots();
      _comboKPIStream = FirebaseFirestore.instance.collection('combos').where('isActive', isEqualTo: true).snapshots();
      _saleKPIStream = FirebaseFirestore.instance.collection('promoSales').where('isActive', isEqualTo: true).snapshots();
      _couponKPIStream = FirebaseFirestore.instance.collection(AppConstants.collectionCoupons).where('active', isEqualTo: true).snapshots();
      
      _lastKPIBranchIds = List.from(filterBranchIds);
    }
  }

  void _updateInventoryStream(List<String> filterBranchIds) {
    final bool branchIdsChanged = _lastInventoryBranchIds == null || 
        _lastInventoryBranchIds!.length != filterBranchIds.length ||
        !_lastInventoryBranchIds!.every((id) => filterBranchIds.contains(id));
    
    final bool categoryChanged = _lastInventoryCategory != _selectedCategory;
    final bool filterChanged = _lastInventoryFilter != _selectedFilter;

    if (branchIdsChanged || categoryChanged || filterChanged) {
      String collection = 'combos';
      if (_selectedCategory == 'sales') collection = 'promoSales';
      if (_selectedCategory == 'coupons') collection = AppConstants.collectionCoupons;

      Query query = FirebaseFirestore.instance.collection(collection);

      if (filterBranchIds.isNotEmpty) {
        // Industry Grade: All promotion types now use branchIds array
        // NOTE: We move this to client-side filtering to handle both 'branchIds' and 'branchids' variations
        // query = query.where('branchIds', arrayContainsAny: filterBranchIds);
      }

      // Query simplified: Combine branch filter only (to avoid composite index requirements)
      // Status filtering (Active/Scheduled/Archived) is moved entirely to client-side
      _inventoryStream = query.snapshots();

      _lastInventoryBranchIds = List.from(filterBranchIds);
      _lastInventoryCategory = _selectedCategory;
      _lastInventoryFilter = _selectedFilter;
    }
  }

  void _launchCampaign() {
    if (_selectedCategory == 'combos') {
      Navigator.push(context, MaterialPageRoute(builder: (context) => const ComboMealAddEditScreen()));
    } else if (_selectedCategory == 'sales') {
      Navigator.push(context, MaterialPageRoute(builder: (context) => const PromoSaleAddEditScreen()));
    } else {
      showDialog(context: context, builder: (_) => const CouponDialog());
    }
  }

  void _editPromo(String id, Map<String, dynamic> data) {
    if (_selectedCategory == 'combos') {
      final combo = ComboModel.fromMap(data, id);
      Navigator.push(context, MaterialPageRoute(builder: (context) => ComboMealAddEditScreen(comboModel: combo, docId: id)));
    } else if (_selectedCategory == 'sales') {
      final sale = PromoSaleModel.fromMap(data, id);
      Navigator.push(context, MaterialPageRoute(builder: (context) => PromoSaleAddEditScreen(saleModel: sale, docId: id)));
    } else {
      showDialog(context: context, builder: (_) => CouponDialog(initialData: data, docId: id));
    }
  }

  // App Palette COLORS
  static const Color appBackground = Color(0xFFF9FAFB);
  static const Color appPrimary = Colors.deepPurple;
  static const Color appSurface = Colors.white;
  static const Color appText = Colors.black87;
  static const Color appTextVariant = Colors.grey;
  static const Color appBorder = Color(0xFFEEEEEE);

  @override
  Widget build(BuildContext context) {
    final userScope = context.watch<UserScopeService>();
    final branchFilter = context.watch<BranchFilterService>();
    final filterBranchIds = branchFilter.getFilterBranchIds(userScope.branchIds);
    final textTheme = Theme.of(context).textTheme;

    _updateKPIStreams(filterBranchIds);
    _updateInventoryStream(filterBranchIds);

    return Scaffold(
      backgroundColor: appBackground,
      body: Column(
        children: [
          _buildHeader(textTheme),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildKPISection(filterBranchIds, textTheme),
                        const SizedBox(height: 32),
                        _buildMainWorkspace(filterBranchIds, textTheme),
                      ],
                    ),
                  ),
                ),
                _buildEditorSidebar(textTheme, userScope, filterBranchIds),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKPISection(List<String> filterBranchIds, TextTheme textTheme) {
    return StreamBuilder<QuerySnapshot>(
      stream: _orderKPIStream,
      builder: (context, orderSnapshot) {
        return StreamBuilder<QuerySnapshot>(
          stream: _comboKPIStream,
          builder: (context, comboSnapshot) {
            return StreamBuilder<QuerySnapshot>(
              stream: _saleKPIStream,
              builder: (context, salesSnapshot) {
                return StreamBuilder<QuerySnapshot>(
                  stream: _couponKPIStream,
                  builder: (context, couponSnapshot) {
                    bool hasBranch(Map<String, dynamic> docData) {
                      if (filterBranchIds.isEmpty) return true;
                      List<dynamic> bIds = docData['branchIds'] is List ? docData['branchIds'] : [];
                      if (bIds.isEmpty) return true;
                      return filterBranchIds.any((id) => bIds.contains(id));
                    }

                    int activePromos = 0;
                    activePromos += (comboSnapshot.data?.docs.where((d) => hasBranch(d.data() as Map<String, dynamic>)).length ?? 0);
                    activePromos += (salesSnapshot.data?.docs.where((d) => hasBranch(d.data() as Map<String, dynamic>)).length ?? 0);
                    activePromos += (couponSnapshot.data?.docs.where((d) => hasBranch(d.data() as Map<String, dynamic>)).length ?? 0);

                    double totalRevenue = 0;
                    int ordersWithDiscount = 0;
                    int totalOrders = 0;
                    Set<String> uniqueCustomers = {};

                    final billableStatuses = {
                      AppConstants.statusDelivered,
                      'completed',
                      AppConstants.statusPaid,
                      AppConstants.statusCollected,
                    };

                    if (orderSnapshot.hasData) {
                      final validOrders = orderSnapshot.data!.docs.where((doc) {
                         final data = doc.data() as Map<String, dynamic>;
                         final status = (data['status'] ?? '').toString().toLowerCase();
                         return billableStatuses.contains(status);
                      }).toList();
                      
                      totalOrders = validOrders.length;

                      for (var doc in validOrders) {
                        final data = doc.data() as Map<String, dynamic>;
                        double discount = (data['discountAmount'] as num?)?.toDouble() ?? 
                                          (data['discount'] as num?)?.toDouble() ?? 0;
                        if (discount > 0) {
                          totalRevenue += (data['totalAmount'] as num?)?.toDouble() ?? 0;
                          ordersWithDiscount++;
                          uniqueCustomers.add(data['customerName']?.toString() ?? data['customerPhone']?.toString() ?? 'Guest');
                        }
                      }
                    }
                    
                    totalOrders = totalOrders.clamp(1, 999999);

                    double redemptionRate = (ordersWithDiscount / totalOrders) * 100;

                    return IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: _buildKPICard('Deal Revenue', 'QAR ${totalRevenue.toStringAsFixed(2)}', '+12.4%', Icons.monetization_on, textTheme)),
                          const SizedBox(width: 24),
                          Expanded(child: _buildKPICard('Active Campaigns', activePromos.toString(), 'In Market', Icons.campaign, textTheme)),
                          const SizedBox(width: 24),
                          Expanded(child: _buildKPICard('Redemption Rate', '${redemptionRate.toStringAsFixed(1)}%', '${ordersWithDiscount} Uses', Icons.confirmation_number, textTheme, isProgress: true, progress: totalOrders > 0 ? ordersWithDiscount / totalOrders : 0)),
                          const SizedBox(width: 24),
                          Expanded(child: _buildKPICard('Customer Reach', uniqueCustomers.length.toString(), 'Unique users', Icons.groups, textTheme)),
                        ],
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildHeader(TextTheme textTheme) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: BoxDecoration(
        color: appSurface,
        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Row(
        children: [
          _buildHeaderTab('Active'),
          const SizedBox(width: 24),
          _buildHeaderTab('Scheduled'),
          const SizedBox(width: 24),
          _buildHeaderTab('Archived'),
          const Spacer(),
          _buildSearchBar(),
          const BranchFilterSelector(),
          const SizedBox(width: 16),
          _buildExportBtn(),
          const SizedBox(width: 16),
          _buildLaunchBtn(),
        ],
      ),
    );
  }

  Widget _buildExportBtn() {
    return ElevatedButton.icon(
      onPressed: () {
        ExportReportDialog.show(context, preSelectedSections: {
          'promotions_performance',
          'sales_summary',
        });
      },
      icon: const Icon(Icons.download_rounded, size: 16),
      label: const Text('Export Report', style: TextStyle(fontWeight: FontWeight.bold)),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: appPrimary,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey[200]!),
        ),
      ),
    );
  }

  Widget _buildHeaderTab(String label) {
    bool isSelected = _selectedFilter == label;
    return InkWell(
      onTap: () => setState(() => _selectedFilter = label),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          border: isSelected ? const Border(bottom: BorderSide(color: appPrimary, width: 2)) : null,
        ),
        child: Text(
          label.toUpperCase(),
          style: TextStyle(
            color: isSelected ? appPrimary : appTextVariant,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      width: 280,
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.search, color: appTextVariant, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() {}),
              style: const TextStyle(color: appText, fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'Search campaigns...',
                hintStyle: TextStyle(color: appTextVariant, fontSize: 13),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLaunchBtn() {
    return ElevatedButton(
      onPressed: _launchCampaign,
      style: ElevatedButton.styleFrom(
        backgroundColor: appPrimary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: 0,
      ),
      child: const Text('Launch Campaign', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
    );
  }

  Widget _buildKPICard(String label, String value, String subtext, IconData icon, TextTheme textTheme, {bool isProgress = false, double progress = 0}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: appSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: appPrimary.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: appPrimary, size: 16),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label.toUpperCase(),
                  style: const TextStyle(color: appTextVariant, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 1),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: const TextStyle(color: appText, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: -1), overflow: TextOverflow.ellipsis, maxLines: 1),
              if (isProgress) ...[
                const SizedBox(height: 8),
                Container(
                  height: 4, width: double.infinity,
                  decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(2)),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft, widthFactor: progress.clamp(0.0, 1.0),
                    child: Container(decoration: BoxDecoration(color: appPrimary, borderRadius: BorderRadius.circular(2))),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (subtext.contains('%')) const Icon(Icons.trending_up, color: appPrimary, size: 10),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        subtext,
                        style: TextStyle(
                          color: subtext.contains('%') ? appPrimary : appTextVariant,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMainWorkspace(List<String> filterBranchIds, TextTheme textTheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCategoryTabs(),
        const SizedBox(height: 24),
        _buildInventoryTableContainer(filterBranchIds, textTheme),
        const SizedBox(height: 32),
        _buildPerformanceChart(),
      ],
    );
  }

  Widget _buildCategoryTabs() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: appSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildCatBtn('Combo Meals', 'combos'),
          _buildCatBtn('Promo Sales', 'sales'),
          _buildCatBtn('Coupon Codes', 'coupons'),
        ],
      ),
    );
  }

  Widget _buildCatBtn(String label, String id) {
    bool isSelected = _selectedCategory == id;
    return InkWell(
      onTap: () => setState(() => _selectedCategory = id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? appPrimary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : appTextVariant,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildInventoryTableContainer(List<String> filterBranchIds, TextTheme textTheme) {
    return Container(
      decoration: BoxDecoration(
        color: appSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Campaign Inventory', style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: appText)),
                    const SizedBox(height: 4),
                    Text('Managing Active ${_selectedCategory.replaceAll('_', ' ')} Bundles', style: TextStyle(color: appTextVariant, fontSize: 12)),
                  ],
                ),
                Row(
                  children: [
                    _buildTableAction('FILTER', Icons.filter_list),
                    const SizedBox(width: 16),
                    _buildTableAction('SORT', Icons.sort),
                  ],
                ),
              ],
            ),
          ),
          _buildStreamedTable(filterBranchIds),
          _buildTableFooter(),
        ],
      ),
    );
  }

  Widget _buildTableAction(String label, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: appTextVariant, size: 14),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: appTextVariant, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1)),
      ],
    );
  }

  Widget _buildStreamedTable(List<String> filterBranchIds) {
    return StreamBuilder<QuerySnapshot>(
      stream: _inventoryStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyState();
        }

        var docs = snapshot.data!.docs;

        // Auto-cleanup worker function
        Future<void> autoDeactivateExpiredPromo(QueryDocumentSnapshot doc, String statusField) async {
          if (_processingExpirations.contains(doc.id)) return;
          _processingExpirations.add(doc.id);

          try {
            String collection = _selectedCategory == 'sales' ? 'promoSales' : (_selectedCategory == 'combos' ? 'combos' : 'coupons');
            await FirebaseFirestore.instance.collection(collection).doc(doc.id).update({
              statusField: false,
            });

            final data = doc.data() as Map<String, dynamic>;
            if (collection == 'promoSales' && data['targetType'] == 'specific_items') {
              final itemNames = List<String>.from(data['itemNames'] ?? data['targetItemIds'] ?? []);
              if (itemNames.isNotEmpty) {
                // Remove FieldValue.delete() due to some flutter web conflicts and instead set to null
                final itemsQuery = await FirebaseFirestore.instance
                    .collection('menuItems')
                    .where('name', whereIn: itemNames.take(10).toList())
                    .get();
                
                final batch = FirebaseFirestore.instance.batch();
                for (var itemDoc in itemsQuery.docs) {
                  batch.update(itemDoc.reference, {
                    'discountedPrice': FieldValue.delete(),
                  });
                }
                await batch.commit();
              }
            }
          } catch (e) {
            debugPrint('Error auto-deactivating promo ${doc.id}: $e');
          } finally {
            _processingExpirations.remove(doc.id);
          }
        }

        // Functional Search Filtering (Client-side for flexibility)
        if (_searchController.text.isNotEmpty) {
          final keyword = _searchController.text.toLowerCase();
          docs = docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final name = (data['name'] ?? data['title'] ?? '').toString().toLowerCase();
            final code = (data['code'] ?? '').toString().toLowerCase();
            final desc = (data['description'] ?? '').toString().toLowerCase();
            return name.contains(keyword) || code.contains(keyword) || desc.contains(keyword);
          }).toList();
        }

        if (docs.isEmpty) return _buildEmptyState();

        // --- Industry Grade Status Filtering (Client-side) ---
        final now = DateTime.now();
        final isCoupon = _selectedCategory == 'coupons';
        final statusField = isCoupon ? 'active' : 'isActive';

        docs = docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final bool isFieldActive = data[statusField] ?? false;
          final start = data['valid_from'] ?? data['startDate'];
          final end = data['valid_until'] ?? data['endDate'];
          
          DateTime? startTime;
          if (start is Timestamp) startTime = start.toDate();
          
          DateTime? endTime;
          if (end is Timestamp) endTime = end.toDate();

          // --- Branch Filtering ---
          if (filterBranchIds.isNotEmpty) {
            final List bIds = data['branchIds'] as List? ?? [];
            if (!bIds.any((id) => filterBranchIds.contains(id.toString()))) {
              return false;
            }
          }

          // --- Expiry Sync Check ---
          bool isExpired = endTime != null && endTime.isBefore(now);
          if (isFieldActive && isExpired) {
            // Trigger background cleanup and treat it as inactive for this render cycle
            WidgetsBinding.instance.addPostFrameCallback((_) {
              autoDeactivateExpiredPromo(doc, statusField);
            });
            // Act like it's inactive so it moves to Archived immediately for the user
            if (_selectedFilter == 'Archived') return true;
            if (_selectedFilter == 'Active' || _selectedFilter == 'Scheduled') return false;
          }

          if (_selectedFilter == 'Scheduled') {
            // Scheduled: Field must be active AND start date must be in future
            return isFieldActive && startTime != null && startTime.isAfter(now);
          } else if (_selectedFilter == 'Active') {
            // Active: Field must be active AND (no dates OR current time is within range)
            bool isStarted = startTime == null || startTime.isBefore(now);
            bool isNotEnded = endTime == null || endTime.isAfter(now);
            return isFieldActive && isStarted && isNotEnded;
          } else if (_selectedFilter == 'Archived') {
            // Archived: Field is inactive OR end date has passed
            bool isInactive = !isFieldActive;
            bool isExpired = endTime != null && endTime.isBefore(now);
            return isInactive || isExpired;
          }
          return true;
        }).toList();

        if (docs.isEmpty) return _buildEmptyState();

        return Column(
          children: [
            _buildTableHeaderUI(),
            ...docs.map((doc) => _buildTableRowUI(doc)),
          ],
        );
      },
    );
  }

  Widget _buildTableHeaderUI() {
    return Container(
      color: Colors.grey[50],
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          _buildHeaderCellUI('Offer / Bundle Details', flex: 25),
          _buildHeaderCellUI('Pricing Dynamics', flex: 18),
          _buildHeaderCellUI('Impact Metrics', flex: 15),
          _buildHeaderCellUI('Duration', flex: 12),
          _buildHeaderCellUI('Status', flex: 10),
          _buildHeaderCellUI('Edit', flex: 6, align: TextAlign.right),
        ],
      ),
    );
  }

  Widget _buildHeaderCellUI(String label, {int flex = 1, TextAlign align = TextAlign.left}) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(label.toUpperCase(), textAlign: align, style: const TextStyle(color: appTextVariant, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
      ),
    );
  }

  Widget _buildTableRowUI(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    bool isActive = false;
    String title = '';
    String sub = '';
    String pricing = '';
    String savings = '';
    double progress = 0.5;
    String impactLabel = '';
    String impactVal = '';
    String duration = 'Permanent';

    if (_selectedCategory == 'combos') {
      final combo = ComboModel.fromMap(data, doc.id);
      isActive = combo.isActive;
      title = combo.name;
      sub = combo.description.length > 40 ? '${combo.description.substring(0, 40)}...' : combo.description;
      pricing = 'QAR ${combo.comboPrice.toStringAsFixed(2)}';
      double saved = combo.originalTotalPrice - combo.comboPrice;
      if (combo.originalTotalPrice > 0) {
        savings = '${(saved / combo.originalTotalPrice * 100).toStringAsFixed(0)}% BUNDLE SAVINGS';
      }
      impactLabel = 'REDEMPTIONS';
      impactVal = combo.orderCount.toString();
      progress = 0.8;
      if (combo.isLimitedTime && combo.startDate != null && combo.endDate != null) {
        duration = '${combo.startDate!.month}/${combo.startDate!.day} - ${combo.endDate!.month}/${combo.endDate!.day}';
      }
    } else if (_selectedCategory == 'sales') {
      final sale = PromoSaleModel.fromMap(data, doc.id);
      isActive = sale.isActive;
      title = sale.name;
      sub = 'Scope: ${sale.targetType}';
      pricing = sale.discountType == 'percentage' ? '${sale.discountValue}% OFF' : 'QAR ${sale.discountValue} OFF';
      savings = 'MIN. QAR ${sale.minOrderValue ?? 0} ORDER';
      impactLabel = 'SALES VOL';
      impactVal = 'QAR 4.2k';
      progress = 0.45;
      duration = '${sale.startDate.month}/${sale.startDate.day} - ${sale.endDate.month}/${sale.endDate.day}';
    } else {
      isActive = data['active'] ?? false;
      title = data['code'] ?? '';
      sub = data['title'] ?? 'New User Welcome';
      pricing = data['type'] == 'percentage' ? '${data['value']}% OFF' : 'QAR ${data['value']} FLAT';
      savings = 'LIMIT ${data['maxUsesPerUser'] ?? 1} PER USER';
      impactLabel = 'REACH';
      impactVal = '8.5k';
      progress = 0.95;
    }

    bool isSelected = _selectedPromoId == doc.id;

    return InkWell(
      onTap: () {
        setState(() {
          _selectedPromoId = doc.id;
          _loadPromoData(data);
        });
      },
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? appPrimary.withOpacity(0.05) : Colors.transparent,
          border: const Border(bottom: BorderSide(color: appBorder)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(flex: 25, child: _buildDetailsCell(title, sub, isSelected)),
            Expanded(flex: 18, child: _buildPricingCell(pricing, savings)),
            Expanded(flex: 15, child: _buildImpactCell(impactLabel, impactVal, progress)),
            Expanded(flex: 12, child: _buildTextCell(duration)),
            Expanded(flex: 10, child: _buildStatusCell(isActive, doc)),
            Expanded(flex: 6, child: _buildEditCell(doc)),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailsCell(String title, String sub, bool selected) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: selected ? appPrimary : appText, fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(sub.toUpperCase(), style: const TextStyle(color: appTextVariant, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
        ],
      ),
    );
  }

  Widget _buildPricingCell(String price, String savings) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(price, style: const TextStyle(color: appPrimary, fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(savings, style: const TextStyle(color: appTextVariant, fontSize: 9, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _buildImpactCell(String label, String value, double progress) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(color: appTextVariant, fontSize: 9, fontWeight: FontWeight.w900)),
              Text(value, style: const TextStyle(color: appText, fontSize: 10, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            height: 4, width: double.infinity,
            decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(2)),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft, widthFactor: progress,
              child: Container(decoration: BoxDecoration(color: appPrimary, borderRadius: BorderRadius.circular(2))),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextCell(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      child: Text(text, style: const TextStyle(color: appTextVariant, fontSize: 12, fontWeight: FontWeight.w500)),
    );
  }

  Widget _buildStatusCell(bool active, QueryDocumentSnapshot doc) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      child: InkWell(
        onTap: () {
          String collection = _selectedCategory == 'sales' ? 'promoSales' : (_selectedCategory == 'combos' ? 'combos' : 'coupons');
          String field = _selectedCategory == 'coupons' ? 'active' : 'isActive';
          FirebaseFirestore.instance.collection(collection).doc(doc.id).update({field: !active});
        },
        child: Container(
          width: 36, height: 20,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: active ? appPrimary.withOpacity(0.2) : Colors.grey[200],
            borderRadius: BorderRadius.circular(10),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 200),
            alignment: active ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 16, height: 16,
              decoration: BoxDecoration(
                color: active ? appPrimary : Colors.white,
                shape: BoxShape.circle,
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2)],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEditCell(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      child: IconButton(
        icon: const Icon(Icons.edit_outlined, color: appTextVariant, size: 18),
        onPressed: () => _editPromo(doc.id, data),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(48),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text('No campaigns found', style: TextStyle(color: appTextVariant, fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildTableFooter() {
    return InkWell(
      onTap: () {},
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(color: Colors.grey[50], border: const Border(top: BorderSide(color: appBorder))),
        child: const Text('LOAD MORE CAMPAIGNS', textAlign: TextAlign.center, style: TextStyle(color: appTextVariant, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
      ),
    );
  }

  Widget _buildPerformanceChart() {
    return StreamBuilder<QuerySnapshot>(
      stream: _orderKPIStream,
      builder: (context, snapshot) {
        Map<String, int> dailyRedemptions = {};
        List<String> last7Days = [];
        for (int i = 6; i >= 0; i--) {
          final date = DateTime.now().subtract(Duration(days: i));
          final key = '${date.day}/${date.month}';
          last7Days.add(key);
          dailyRedemptions[key] = 0;
        }

        if (snapshot.hasData) {
          for (var doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final ts = data['timestamp'] as Timestamp?;
            if (ts != null) {
              final date = ts.toDate();
              final key = '${date.day}/${date.month}';
              if (dailyRedemptions.containsKey(key)) {
                if (((data['discount'] as num?)?.toDouble() ?? 0) > 0) {
                  dailyRedemptions[key] = (dailyRedemptions[key] ?? 0) + 1;
                }
              }
            }
          }
        }

        final maxCount = dailyRedemptions.values.isEmpty ? 1 : dailyRedemptions.values.reduce((a, b) => a > b ? a : b);
        final displayMax = maxCount < 5 ? 5 : maxCount;

        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: appSurface, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey[200]!)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                   Text('Daily Redemption Trends', style: const TextStyle(color: appText, fontSize: 18, fontWeight: FontWeight.bold)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: appPrimary.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                    child: Text('PEAK: $maxCount', style: const TextStyle(color: appPrimary, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              SizedBox(
                height: 200,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    ...last7Days.map((key) {
                      int count = dailyRedemptions[key] ?? 0;
                      double heightFactor = (count / displayMax).clamp(0.01, 1.0);
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Tooltip(
                            message: '$count redemptions on $key',
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (count > 0) Text(count.toString(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: appPrimary)),
                                const SizedBox(height: 4),
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 500),
                                  height: 180 * heightFactor,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [appPrimary.withOpacity(0.8), appPrimary.withOpacity(0.4)],
                                    ),
                                    borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                                    boxShadow: [
                                      BoxShadow(color: appPrimary.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ...last7Days.map((d) => Expanded(
                        child: Text(d.split(' ')[0], textAlign: TextAlign.center, style: const TextStyle(color: appTextVariant, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                      )),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEditorSidebar(TextTheme textTheme, UserScopeService userScope, List<String> filterBranchIds) {
    if (_selectedPromoId == null) {
      return Container(
        width: 380,
        decoration: BoxDecoration(
          color: appSurface,
          border: Border(left: BorderSide(color: Colors.grey[200]!)),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.edit_note_outlined, size: 64, color: Colors.grey[200]),
              const SizedBox(height: 16),
              const Text('Select a campaign to edit', style: TextStyle(color: appTextVariant, fontSize: 14)),
            ],
          ),
        ),
      );
    }

    return Container(
      width: 380,
      decoration: BoxDecoration(
        color: appSurface,
        border: Border(left: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(32),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Campaign Editor', style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: appText)),
                    const SizedBox(height: 4),
                    Text('Configuring ${_selectedCategory.replaceAll('_', ' ')}', style: const TextStyle(color: appTextVariant, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  ],
                ),
                IconButton(icon: const Icon(Icons.close, color: appTextVariant), onPressed: () => setState(() => _selectedPromoId = null)),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_selectedCategory == 'coupons') ...[
                    _buildEditorSection('Coupon Identity', [
                      _buildEditableField('Title (EN)', _nameController, onSaved: (v) => _updateProperty('title', v)),
                      _buildEditableField('Title (AR)', _nameArController, onSaved: (v) => _updateProperty('title_ar', v)),
                      _buildEditableField('Coupon Code', _codeController, isHighlight: true, onSaved: (v) => _updateProperty('code', v)),
                      _buildEditableField('Description (EN)', _descController, maxLines: 3, onSaved: (v) => _updateProperty('description', v)),
                      _buildEditableField('Description (AR)', _descArController, maxLines: 3, onSaved: (v) => _updateProperty('description_ar', v)),
                    ]),
                    const SizedBox(height: 32),
                    _buildEditorSection('Applicable Branches', [
                      if (userScope.isSuperAdmin) 
                        _buildBranchMultiSelector(userScope.branchIds)
                      else 
                        _buildTagList(_selectedPromoData['branchIds'] as List? ?? []),
                    ]),
                    const SizedBox(height: 32),
                    _buildEditorSection('Discount Configuration', [
                      Row(
                        children: [
                          Expanded(child: _buildDropdownField('Type', _selectedPromoData['type'] ?? 'percentage', ['percentage', 'flat'], (v) => _updateProperty('type', v))),
                          const SizedBox(width: 12),
                          Expanded(child: _buildPricingField('Value', _valueController, onSaved: (v) => _updateProperty('value', double.tryParse(v) ?? 0))),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(child: _buildPricingField('Min Subtotal', _minSubtotalController, onSaved: (v) => _updateProperty('min_subtotal', double.tryParse(v) ?? 0))),
                          const SizedBox(width: 12),
                          Expanded(child: _buildPricingField('Max Discount', _maxDiscountController, onSaved: (v) => _updateProperty('max_discount', double.tryParse(v) ?? 0))),
                        ],
                      ),
                    ]),
                    const SizedBox(height: 32),
                    _buildEditorSection('Usage & Status', [
                      _buildEditableField('Max Uses Per User', _maxUsesController, onSaved: (v) => _updateProperty('maxUsesPerUser', int.tryParse(v))),
                      _buildToggleField('Active Status', _selectedPromoData['active'] ?? true, (v) => _updateProperty('active', v)),
                    ]),
                    const SizedBox(height: 32),
                    _buildEditorSection('Validity Period', [
                      _buildDatePickerField('Valid From', _selectedPromoData['valid_from'] ?? _selectedPromoData['startDate'], (v) {
                        final field = _selectedCategory == 'sales' ? 'startDate' : 'valid_from';
                        _updateProperty(field, v);
                      }),
                      _buildDatePickerField('Valid Until', _selectedPromoData['valid_until'] ?? _selectedPromoData['endDate'], (v) {
                        final field = _selectedCategory == 'sales' ? 'endDate' : 'valid_until';
                        _updateProperty(field, v);
                      }),
                    ]),
                  ] else if (_selectedCategory == 'combos') ...[
                    _buildEditorSection('Combo Identity', [
                      _buildEditableField('Combo Name (EN)', _nameController, onSaved: (v) => _updateProperty('name', v)),
                      _buildEditableField('Combo Name (AR)', _nameArController, onSaved: (v) => _updateProperty('nameAr', v)),
                      _buildEditableField('Description (EN)', _descController, maxLines: 3, onSaved: (v) => _updateProperty('description', v)),
                      _buildEditableField('Description (AR)', _descArController, maxLines: 3, onSaved: (v) => _updateProperty('descriptionAr', v)),
                    ]),
                    const SizedBox(height: 32),
                    _buildEditorSection('Bundle Components', [
                      ...(_selectedPromoData['itemNames'] as List? ?? _selectedPromoData['itemIds'] as List? ?? _selectedPromoData['targetItemIds'] as List? ?? []).map((name) => _buildRemovableItem(name.toString())).toList(),
                      _buildAddBtn('+ ADD MENU ITEM'),
                    ]),
                    const SizedBox(height: 32),
                    _buildEditorSection('Pricing & Availability', [
                      _buildPricingField('Combo Price', _valueController, onSaved: (v) => _updateProperty('comboPrice', double.tryParse(v) ?? 0)),
                      _buildEditableField('Max Qty Per Order', _maxUsesController, onSaved: (v) => _updateProperty('maxQuantityPerOrder', int.tryParse(v))),
                      _buildToggleField('Active Status', _selectedPromoData['isActive'] ?? true, (v) => _updateProperty('isActive', v)),
                      _buildToggleField('Limited Time', _selectedPromoData['isLimitedTime'] ?? false, (v) => _updateProperty('isLimitedTime', v)),
                    ]),
                    const SizedBox(height: 32),
                    if (userScope.isSuperAdmin) 
                      _buildEditorSection('Branch Control (Super Admin)', [
                        _buildBranchMultiSelector(userScope.branchIds),
                      ]),
                    if (_selectedPromoData['isLimitedTime'] == true) ...[
                      const SizedBox(height: 32),
                      _buildEditorSection('Combo Validity', [
                        _buildDatePickerField('Start Date', _selectedPromoData['startDate'], (v) => _updateProperty('startDate', v)),
                        _buildDatePickerField('End Date', _selectedPromoData['endDate'], (v) => _updateProperty('endDate', v)),
                      ]),
                    ],
                  ] else if (_selectedCategory == 'sales') ...[
                    _buildEditorSection('Sale Identity', [
                      _buildEditableField('Sale Name (EN)', _nameController, onSaved: (v) => _updateProperty('name', v)),
                      _buildEditableField('Sale Name (AR)', _nameArController, onSaved: (v) => _updateProperty('nameAr', v)),
                      _buildEditableField('Description (EN)', _descController, maxLines: 3, onSaved: (v) => _updateProperty('description', v)),
                      _buildEditableField('Description (AR)', _descArController, maxLines: 3, onSaved: (v) => _updateProperty('descriptionAr', v)),
                      _buildEditableField('Banner Image URL', _imageUrlController, onSaved: (v) => _updateProperty('imageUrl', v)),
                    ]),
                    const SizedBox(height: 32),
                    _buildEditorSection('Discount Config', [
                      Row(
                        children: [
                          Expanded(child: _buildDropdownField('Type', _selectedPromoData['discountType'] ?? 'percentage', ['percentage', 'flat'], (v) => _updateProperty('discountType', v))),
                          const SizedBox(width: 12),
                          Expanded(child: _buildPricingField('Value', _valueController, onSaved: (v) => _updateProperty('discountValue', double.tryParse(v) ?? 0))),
                        ],
                      ),
                      _buildDropdownField('Target Type', _selectedPromoData['targetType'] ?? 'all', ['all', 'category', 'specific_items'], (v) => _updateProperty('targetType', v)),
                    ]),
                    if (_selectedPromoData['targetType'] == 'specific_items') ...[
                      const SizedBox(height: 32),
                      _buildEditorSection('Bundle Components', [
                        ...(_selectedPromoData['itemNames'] as List? ?? _selectedPromoData['itemIds'] as List? ?? _selectedPromoData['targetItemIds'] as List? ?? []).map((name) => _buildRemovableItem(name.toString())).toList(),
                        _buildAddBtn('+ ADD MENU ITEM'),
                      ]),
                    ] else if (_selectedPromoData['targetType'] == 'category') ...[
                      const SizedBox(height: 32),
                      _buildEditorSection('Target Categories', [
                        ...(_selectedPromoData['targetCategoryIds'] as List? ?? []).map((id) => _buildRemovableCategory(id.toString())).toList(),
                        _buildAddCategoryBtn('+ ADD CATEGORY'),
                      ]),
                    ],
                    const SizedBox(height: 32),
                    _buildEditorSection('Sale Period', [
                      _buildDatePickerField('Start Date', _selectedPromoData['startDate'] ?? _selectedPromoData['valid_from'], (v) => _updateProperty('startDate', v)),
                      _buildDatePickerField('End Date', _selectedPromoData['endDate'] ?? _selectedPromoData['valid_until'], (v) => _updateProperty('endDate', v)),
                    ]),
                    const SizedBox(height: 32),
                    _buildEditorSection('Rules & Constraints', [
                      _buildPricingField('Min Order Value', _minSubtotalController, onSaved: (v) => _updateProperty('minOrderValue', double.tryParse(v) ?? 0)),
                      _buildPricingField('Max Discount Cap', _maxDiscountController, onSaved: (v) => _updateProperty('maxDiscountCap', double.tryParse(v) ?? 0)),
                      _buildToggleField('Active Status', _selectedPromoData['isActive'] ?? true, (v) => _updateProperty('isActive', v)),
                      _buildToggleField('Stackable with Coupons', _selectedPromoData['stackableWithCoupons'] ?? false, (v) => _updateProperty('stackableWithCoupons', v)),
                      _buildEditableField('Priority', _priorityController, onSaved: (v) => _updateProperty('priority', int.tryParse(v))),
                    ]),
                    const SizedBox(height: 32),
                    if (userScope.isSuperAdmin) 
                      _buildEditorSection('Branch Control (Super Admin)', [
                        _buildBranchMultiSelector(userScope.branchIds),
                      ]),
                  ],
                  const SizedBox(height: 48),
                  if (_isSaving) const Center(child: CircularProgressIndicator()) 
                  else _buildEditorFooter(userScope.isSuperAdmin, filterBranchIds),
                  const SizedBox(height: 48),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditorSection(String label, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: const TextStyle(color: appTextVariant, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
        const SizedBox(height: 16),
        ...children,
      ],
    );
  }

  Widget _buildEditableField(String label, TextEditingController controller, {bool isHighlight = false, int maxLines = 1, bool readOnly = false, required Function(String) onSaved}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isHighlight ? appPrimary.withOpacity(0.05) : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isHighlight ? appPrimary.withOpacity(0.2) : Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(color: appTextVariant, fontSize: 10, fontWeight: FontWeight.bold)),
              if (isHighlight) const Icon(Icons.verified, color: appPrimary, size: 14),
            ],
          ),
           IgnorePointer(
            ignoring: readOnly,
            child: TextField(
              controller: controller,
              maxLines: maxLines,
              readOnly: readOnly,
              style: TextStyle(color: isHighlight ? appPrimary : appText, fontSize: 14, fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal),
              decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 8)),
              onSubmitted: onSaved,
              onEditingComplete: () => onSaved(controller.text),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownField(String label, String value, List<String> options, Function(String) onChanged) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey[200]!)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: appTextVariant, fontSize: 10, fontWeight: FontWeight.bold)),
          DropdownButton<String>(
            value: options.contains(value) ? value : options.first,
            items: options.map((o) => DropdownMenuItem(value: o, child: Text(o, style: const TextStyle(fontSize: 13)))).toList(),
            onChanged: (v) => onChanged(v!),
            isExpanded: true,
            underline: const SizedBox(),
          ),
        ],
      ),
    );
  }

  Widget _buildDatePickerField(String label, dynamic value, Function(Timestamp) onSelected) {
    final DateTime date = (value is Timestamp) ? value.toDate() : DateTime.now();
    return InkWell(
      onTap: () async {
        final pickedDate = await showDatePicker(context: context, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime(2030));
        if (pickedDate != null) {
          final pickedTime = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(date));
          if (pickedTime != null) {
            final finalDate = DateTime(pickedDate.year, pickedDate.month, pickedDate.day, pickedTime.hour, pickedTime.minute);
            onSelected(Timestamp.fromDate(finalDate));
          }
        }
      },
      child: _buildEditableField(label, TextEditingController(text: _formatTs(value)), readOnly: true, onSaved: (_) {}),
    );
  }

  String _formatTs(dynamic ts) {
    if (ts is Timestamp) {
      final date = ts.toDate();
      return '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }
    return ts?.toString() ?? 'N/A';
  }

  Widget _buildTagList(List tags) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ...tags.map((t) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.grey[200]!)),
          child: Text(t.toString(), style: const TextStyle(color: appTextVariant, fontSize: 10, fontWeight: FontWeight.bold)),
        )),
      ],
    );
  }

  Widget _buildRemovableItem(String name) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[200]!)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(name, style: const TextStyle(color: appText, fontSize: 12), overflow: TextOverflow.ellipsis)),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: appTextVariant, size: 16),
            onPressed: () {
              final items = List<String>.from(_selectedPromoData['itemNames'] ?? _selectedPromoData['itemIds'] ?? _selectedPromoData['targetItemIds'] ?? []);
              items.remove(name);
              String field = _selectedPromoData.containsKey('itemNames') ? 'itemNames' : (_selectedPromoData.containsKey('itemIds') ? 'itemIds' : 'targetItemIds');
              _updateProperty(field, items);
            },
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildAddBtn(String label) {
    return InkWell(
      onTap: _showItemPicker,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(border: Border.all(color: appPrimary.withOpacity(0.3)), borderRadius: BorderRadius.circular(8)),
        child: Text(label, textAlign: TextAlign.center, style: const TextStyle(color: appPrimary, fontSize: 10, fontWeight: FontWeight.bold)),
      ),
    );
  }

  void _showItemPicker() async {
    // Basic item picker for this demo/upgrade. In a full app, this would be a search dialog.
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Menu Item'),
        content: SizedBox(
          width: 300,
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection(AppConstants.collectionMenuItems).limit(20).snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const CircularProgressIndicator();
              return ListView.builder(
                shrinkWrap: true,
                itemCount: snapshot.data!.docs.length,
                itemBuilder: (context, i) {
                  final name = snapshot.data!.docs[i]['name'].toString();
                  return ListTile(
                    title: Text(name),
                    onTap: () => Navigator.pop(context, name),
                  );
                },
              );
            },
          ),
        ),
      ),
    );

    if (result != null && _selectedPromoId != null) {
      final items = List<String>.from(_selectedPromoData['itemNames'] ?? _selectedPromoData['itemIds'] ?? _selectedPromoData['targetItemIds'] ?? []);
      if (!items.contains(result)) {
        items.add(result);
        String field = _selectedPromoData.containsKey('itemNames') ? 'itemNames' : (_selectedPromoData.containsKey('itemIds') ? 'itemIds' : 'targetItemIds');
        _updateProperty(field, items);
      }
    }
  }

  Widget _buildRemovableCategory(String categoryId) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[200]!)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text('Category ID: $categoryId', style: const TextStyle(color: appText, fontSize: 12), overflow: TextOverflow.ellipsis)),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: appTextVariant, size: 16),
            onPressed: () {
              final cats = List<String>.from(_selectedPromoData['targetCategoryIds'] ?? []);
              cats.remove(categoryId);
              _updateProperty('targetCategoryIds', cats);
            },
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildAddCategoryBtn(String label) {
    return InkWell(
      onTap: _showCategoryPicker,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(border: Border.all(color: appPrimary.withOpacity(0.3)), borderRadius: BorderRadius.circular(8)),
        child: Text(label, textAlign: TextAlign.center, style: const TextStyle(color: appPrimary, fontSize: 10, fontWeight: FontWeight.bold)),
      ),
    );
  }

  void _showCategoryPicker() async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Category'),
        content: SizedBox(
          width: 300,
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection(AppConstants.collectionMenuCategories).snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const CircularProgressIndicator();
              return ListView.builder(
                shrinkWrap: true,
                itemCount: snapshot.data!.docs.length,
                itemBuilder: (context, i) {
                  final name = snapshot.data!.docs[i]['name'].toString();
                  final id = snapshot.data!.docs[i].id;
                  return ListTile(
                    title: Text(name),
                    subtitle: Text(id),
                    onTap: () => Navigator.pop(context, id),
                  );
                },
              );
            },
          ),
        ),
      ),
    );

    if (result != null && _selectedPromoId != null) {
      final cats = List<String>.from(_selectedPromoData['targetCategoryIds'] ?? []);
      if (!cats.contains(result)) {
        cats.add(result);
        _updateProperty('targetCategoryIds', cats);
      }
    }
  }

  Widget _buildPricingField(String label, TextEditingController controller, {required Function(String) onSaved}) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: appTextVariant, fontSize: 10)),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('QAR', style: TextStyle(color: appPrimary, fontSize: 14, fontWeight: FontWeight.w900)),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: appText, fontSize: 24, fontWeight: FontWeight.w900),
                  decoration: const InputDecoration(border: InputBorder.none, isDense: true),
                  onSubmitted: onSaved,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildToggleField(String label, bool value, Function(bool) onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: appText, fontSize: 13, fontWeight: FontWeight.w500)),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: appPrimary,
          ),
        ],
      ),
    );
  }

  Widget _buildEditorFooter(bool isSuperAdmin, List<String> userAssignedBranches) {
    return Column(
      children: [
        ElevatedButton(
          onPressed: () async {
            if (_selectedPromoId == null) return;
            
            // Build the update map by collecting values from controllers
            final nameField = _selectedCategory == 'coupons' ? 'title' : 'name';
            final Map<String, dynamic> updates = {
              nameField: _nameController.text,
              if (_selectedCategory == 'coupons') 'title_ar': _nameArController.text,
              if (_selectedCategory != 'coupons') 'nameAr': _nameArController.text,
              'description': _descController.text,
              // Description Arabic has different names in different models
              if (_selectedCategory == 'coupons') 'description_ar': _descArController.text,
              if (_selectedCategory != 'coupons') 'descriptionAr': _descArController.text,
              if (_selectedCategory == 'coupons') 'code': _codeController.text,
              if (_selectedCategory == 'combos') 'comboPrice': double.tryParse(_valueController.text) ?? 0.0,
              if (_selectedCategory == 'sales') 'discountValue': double.tryParse(_valueController.text) ?? 0.0,
              if (_selectedCategory == 'coupons') 'value': double.tryParse(_valueController.text) ?? 0.0,
              
              // ✅ ADDED MISSING FIELDS FOR SAVING
              if (_selectedCategory == 'coupons') 'min_subtotal': double.tryParse(_minSubtotalController.text) ?? 0.0,
              if (_selectedCategory != 'coupons') 'minOrderValue': double.tryParse(_minSubtotalController.text) ?? 0.0,
              if (_selectedCategory == 'coupons') 'max_discount': double.tryParse(_maxDiscountController.text) ?? 0.0,
              if (_selectedCategory != 'coupons') 'maxDiscountCap': double.tryParse(_maxDiscountController.text) ?? 0.0,
              'maxUsesPerUser': int.tryParse(_maxUsesController.text) ?? 0,
              'priority': int.tryParse(_priorityController.text) ?? 0,
              'active': _selectedPromoData['active'] ?? true, // For coupons
              'isActive': _selectedPromoData['isActive'] ?? true, // For combos/sales

              // ✅ CATEGORY SPECIFIC FIELDS
              if (_selectedCategory == 'sales') 'discountType': _selectedPromoData['discountType'] ?? 'percentage',
              if (_selectedCategory == 'sales') 'targetType': _targetTypeController.text,
              if (_selectedCategory == 'sales') 'imageUrl': _imageUrlController.text,
              if (_selectedCategory == 'sales') 'stackableWithCoupons': _selectedPromoData['stackableWithCoupons'] ?? false,
              if (_selectedCategory == 'combos') 'isLimitedTime': _selectedPromoData['isLimitedTime'] ?? false,
              if (_selectedCategory == 'coupons') 'type': _selectedPromoData['type'] ?? 'percentage',

              // ✅ HANDLE DATE FIELD VARIATIONS
              if (_selectedCategory == 'sales' || _selectedCategory == 'combos') 'startDate': _selectedPromoData['startDate'] ?? _selectedPromoData['valid_from'],
              if (_selectedCategory == 'sales' || _selectedCategory == 'combos') 'endDate': _selectedPromoData['endDate'] ?? _selectedPromoData['valid_until'],
              if (_selectedCategory == 'coupons') 'valid_from': _selectedPromoData['valid_from'] ?? _selectedPromoData['startDate'],
              if (_selectedCategory == 'coupons') 'valid_until': _selectedPromoData['valid_until'] ?? _selectedPromoData['endDate'],
              
              // ✅ HANDLE BRANCH FIELD VARIATIONS
              if (_selectedCategory == 'sales' || _selectedCategory == 'combos') 'branchids': _editingBranchIds,
              'branchIds': _editingBranchIds,
              
              'lastUpdated': FieldValue.serverTimestamp(),
            };

            // Branch Assignment RBAC
            if (isSuperAdmin) {
              updates['branchIds'] = _editingBranchIds;
            } else {
              // Non-super-admins enforce their assigned branches for consistency
              if (userAssignedBranches.isNotEmpty && (_editingBranchIds.isEmpty)) {
                 updates['branchIds'] = userAssignedBranches;
              } else {
                 updates['branchIds'] = _editingBranchIds;
              }
            }
            
            setState(() => _isSaving = true);
            try {
              String collection = _selectedCategory == 'combos' ? 'combos' : (_selectedCategory == 'sales' ? 'promoSales' : AppConstants.collectionCoupons);
              await FirebaseFirestore.instance.collection(collection).doc(_selectedPromoId).update(updates);
              
              // Sync local state
              setState(() {
                updates.forEach((key, value) {
                   _selectedPromoData[key] = value;
                });
              });
              
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Campaign updates saved successfully')));
            } catch (e) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
            } finally {
              setState(() => _isSaving = false);
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: appPrimary,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 0,
          ),
          child: const Text('Save Campaign Updates', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 12),
        _buildSecondaryBtn('Archive Campaign', () async {
          if (_selectedPromoId == null) return;
          String field = _selectedCategory == 'coupons' ? 'active' : 'isActive';
          
          final confirm = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Archive Campaign?'),
              content: const Text('This will hide the campaign from customers and move it to the Archived tab.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCEL')),
                ElevatedButton(onPressed: () => Navigator.pop(context, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('ARCHIVE')),
              ],
            ),
          );

          if (confirm == true) {
            await _updateProperty(field, false);
            setState(() => _selectedPromoId = null);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Campaign archived successfully')));
          }
        }),
      ],
    );
  }

  Widget _buildSecondaryBtn(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 50,
        decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12)),
        alignment: Alignment.center,
        child: Text(label, style: const TextStyle(color: appTextVariant, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildBranchMultiSelector(List<String> userAssignedBranches) {
    final bool allSelected = userAssignedBranches.isNotEmpty && userAssignedBranches.every((id) => _editingBranchIds.contains(id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Assigned Branches', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: appTextVariant)),
            TextButton(
              onPressed: () {
                setState(() {
                  if (allSelected) {
                    _editingBranchIds.clear();
                  } else {
                    _editingBranchIds = List.from(userAssignedBranches);
                  }
                });
              },
              child: Text(allSelected ? 'CLEAR ALL' : 'SELECT ALL', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: appPrimary)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ...userAssignedBranches.map((id) {
              final isSelected = _editingBranchIds.contains(id);
              return FilterChip(
                label: Text(id, style: TextStyle(fontSize: 10, color: isSelected ? Colors.white : appText, fontWeight: FontWeight.bold)),
                selected: isSelected,
                onSelected: (val) {
                  setState(() {
                    if (val) {
                      _editingBranchIds.add(id);
                    } else {
                      _editingBranchIds.remove(id);
                    }
                  });
                },
                selectedColor: appPrimary,
                checkmarkColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              );
            }),
          ],
        ),
      ],
    );
  }
}
