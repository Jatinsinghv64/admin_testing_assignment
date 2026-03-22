import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../Models/promo_models.dart';
import '../main.dart';
import '../Widgets/BranchFilterService.dart';
import 'ComboMealsScreen.dart'; // For ComboMealAddEditScreen
import 'PromoSalesScreen.dart'; // For PromoSaleAddEditScreen
import 'CouponsScreen.dart'; // For CouponDialog

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
    Query orderQuery = FirebaseFirestore.instance.collection('orders').orderBy('timestamp', descending: true).limit(500);
    if (filterBranchIds.isNotEmpty) {
      orderQuery = orderQuery.where('branchId', whereIn: filterBranchIds);
    }

    return StreamBuilder(
      stream: orderQuery.snapshots(),
      builder: (context, orderSnapshot) {
        return StreamBuilder(
          stream: FirebaseFirestore.instance.collection('combos').where('isActive', isEqualTo: true).snapshots(),
          builder: (context, comboSnapshot) {
            return StreamBuilder(
              stream: FirebaseFirestore.instance.collection('promoSales').where('isActive', isEqualTo: true).snapshots(),
              builder: (context, salesSnapshot) {
                return StreamBuilder(
                  stream: FirebaseFirestore.instance.collection('coupons').where('active', isEqualTo: true).snapshots(),
                  builder: (context, couponSnapshot) {
                    int activePromos = (comboSnapshot.data?.docs.length ?? 0) +
                        (salesSnapshot.data?.docs.length ?? 0) +
                        (couponSnapshot.data?.docs.length ?? 0);

                    double totalRevenue = 0;
                    int ordersWithDiscount = 0;
                    int totalOrders = (orderSnapshot.data?.docs.length ?? 0).clamp(1, 999999);
                    Set<String> uniqueCustomers = {};

                    if (orderSnapshot.hasData) {
                      for (var doc in orderSnapshot.data!.docs) {
                        final data = doc.data() as Map<String, dynamic>;
                        double discount = (data['discount'] as num?)?.toDouble() ?? 0;
                        if (discount > 0) {
                          totalRevenue += (data['totalAmount'] as num?)?.toDouble() ?? 0;
                          ordersWithDiscount++;
                          uniqueCustomers.add(data['customerName'] ?? data['customerPhone'] ?? 'Guest');
                        }
                      }
                    }

                    double redemptionRate = (ordersWithDiscount / totalOrders) * 100;

                    return GridView.count(
                      crossAxisCount: 4,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 24,
                      childAspectRatio: 1.3,
                      children: [
                        _buildKPICard('Deal Revenue', 'QAR ${totalRevenue.toStringAsFixed(2)}', '+12.4%', Icons.monetization_on, textTheme),
                        _buildKPICard('Active Campaigns', activePromos.toString(), 'In Market', Icons.campaign, textTheme),
                        _buildKPICard('Redemption Rate', '${redemptionRate.toStringAsFixed(1)}%', '${ordersWithDiscount} Uses', Icons.confirmation_number, textTheme, isProgress: true, progress: ordersWithDiscount / totalOrders),
                        _buildKPICard('Customer Reach', uniqueCustomers.length.toString(), 'Unique users', Icons.groups, textTheme),
                      ],
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
          const SizedBox(width: 24),
          _buildLaunchBtn(),
        ],
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
              Text(value, style: const TextStyle(color: appText, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: -1), overflow: TextOverflow.ellipsis),
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
    String collection = 'combos';
    if (_selectedCategory == 'sales') collection = 'promoSales';
    if (_selectedCategory == 'coupons') collection = 'coupons';

    Query query = FirebaseFirestore.instance.collection(collection);

    // Filter by branch
    if (filterBranchIds.isNotEmpty) {
      if (collection == 'coupons') {
        if (filterBranchIds.length == 1) {
          query = query.where('branchIds', arrayContains: filterBranchIds.first);
        } else {
          query = query.where('branchIds', arrayContainsAny: filterBranchIds);
        }
      } else {
        query = query.where('branchIds', arrayContainsAny: filterBranchIds);
      }
    }

    // Filter by status (Active/Archived/Scheduled)
    String statusField = collection == 'coupons' ? 'active' : 'isActive';
    if (_selectedFilter == 'Active') {
      query = query.where(statusField, isEqualTo: true);
    } else if (_selectedFilter == 'Archived') {
      query = query.where(statusField, isEqualTo: false);
    }

    return StreamBuilder(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyState();
        }

        var docs = snapshot.data!.docs;

        // Functional Search Filtering (Client-side for flexibility)
        if (_searchController.text.isNotEmpty) {
          final keyword = _searchController.text.toLowerCase();
          docs = docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final name = (data['name'] ?? data['title'] ?? data['code'] ?? '').toString().toLowerCase();
            return name.contains(keyword);
          }).toList();
        }

        if (docs.isEmpty) return _buildEmptyState();

        return Column(
          children: [
            _buildTableHeaderUI(),
            ...docs.map((doc) => _buildTableRowUI(doc)).toList(),
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
        padding: const EdgeInsets.symmetric(horizontal: 24),
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
          _selectedPromoData = data;
          _editingBranchIds = List<String>.from(data['branchIds'] ?? data['branchids'] ?? []);
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
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
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
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
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
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
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
            height: 4, width: 96,
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
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Text(text, style: const TextStyle(color: appTextVariant, fontSize: 12, fontWeight: FontWeight.w500)),
    );
  }

  Widget _buildStatusCell(bool active, QueryDocumentSnapshot doc) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
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
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
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
    Query orderQuery = FirebaseFirestore.instance.collection('orders').orderBy('timestamp', descending: true).limit(500);
    
    return StreamBuilder(
      stream: orderQuery.snapshots(),
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

        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: appSurface, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey[200]!)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Daily Redemption Trends', style: TextStyle(color: appText, fontSize: 18, fontWeight: FontWeight.bold)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: appPrimary.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                    child: const Text('LAST 7 DAYS', style: TextStyle(color: appPrimary, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              SizedBox(
                height: 200,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: last7Days.map((key) {
                    int count = dailyRedemptions[key] ?? 0;
                    double heightFactor = (count / 10).clamp(0.05, 1.0); // Normalized to 10 redemptions max for visual
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Tooltip(
                          message: '$count redemptions',
                          child: Container(
                            height: 200 * heightFactor,
                            decoration: BoxDecoration(
                              color: appPrimary.withOpacity(0.4 + (heightFactor * 0.6)),
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: last7Days
                    .map((d) => Expanded(child: Text(d, textAlign: TextAlign.center, style: const TextStyle(color: appTextVariant, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.5))))
                    .toList(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildChartTab(String label, bool isSelected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isSelected ? appPrimary : Colors.grey[100],
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label.toUpperCase(), style: TextStyle(color: isSelected ? Colors.white : appTextVariant, fontSize: 10, fontWeight: FontWeight.bold)),
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
                      _buildInputField('Title (EN)', _selectedPromoData['title'] ?? ''),
                      _buildInputField('Title (AR)', _selectedPromoData['title_ar'] ?? ''),
                      _buildInputField('Coupon Code', _selectedPromoData['code'] ?? '', isHighlight: true),
                      _buildInputField('Description (EN)', _selectedPromoData['description'] ?? ''),
                      _buildInputField('Description (AR)', _selectedPromoData['description_ar'] ?? ''),
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
                          Expanded(child: _buildInputField('Type', _selectedPromoData['type'] ?? 'percentage')),
                          const SizedBox(width: 12),
                          Expanded(child: _buildPricingField('Value', _selectedPromoData['value'] ?? 0)),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(child: _buildPricingField('Min Subtotal', _selectedPromoData['min_subtotal'] ?? 0)),
                          const SizedBox(width: 12),
                          Expanded(child: _buildPricingField('Max Discount', _selectedPromoData['max_discount'] ?? 0)),
                        ],
                      ),
                    ]),
                    const SizedBox(height: 32),
                    _buildEditorSection('Usage & Status', [
                      _buildInputField('Max Uses Per User', _selectedPromoData['maxUsesPerUser']?.toString() ?? '∞'),
                      _buildToggleField('Active Status', _selectedPromoData['active'] ?? true),
                    ]),
                    const SizedBox(height: 32),
                    _buildEditorSection('Validity Period', [
                      _buildInputField('Valid From', _formatTs(_selectedPromoData['valid_from'])),
                      _buildInputField('Valid Until', _formatTs(_selectedPromoData['valid_until'])),
                      _buildInputField('Created At', _formatTs(_selectedPromoData['created_at'])),
                    ]),
                  ] else if (_selectedCategory == 'combos') ...[
                    _buildEditorSection('Combo Identity', [
                      _buildInputField('Combo Name (EN)', _selectedPromoData['name'] ?? ''),
                      _buildInputField('Combo Name (AR)', _selectedPromoData['nameAr'] ?? ''),
                      _buildInputField('Description (EN)', _selectedPromoData['description'] ?? ''),
                      _buildInputField('Description (AR)', _selectedPromoData['descriptionAr'] ?? ''),
                    ]),
                    const SizedBox(height: 32),
                    _buildEditorSection('Bundle Components', [
                      ...(_selectedPromoData['itemIds'] as List? ?? []).map((id) => _buildRemovableItem(id)).toList(),
                      _buildAddBtn('+ ADD MENU ITEM'),
                    ]),
                    const SizedBox(height: 32),
                    _buildEditorSection('Pricing & Availability', [
                      _buildPricingField('Combo Price', _selectedPromoData['comboPrice'] ?? 0),
                      _buildInputField('Max Qty Per Order', _selectedPromoData['maxQuantityPerOrder']?.toString() ?? '5'),
                      _buildToggleField('Active Status', _selectedPromoData['isActive'] ?? true),
                      _buildToggleField('Limited Time', _selectedPromoData['isLimitedTime'] ?? false),
                    ]),
                    const SizedBox(height: 32),
                    if (userScope.isSuperAdmin) 
                      _buildEditorSection('Branch Control (Super Admin)', [
                        _buildBranchMultiSelector(userScope.branchIds),
                      ]),
                  ] else if (_selectedCategory == 'sales') ...[
                    _buildEditorSection('Sale Identity', [
                      _buildInputField('Sale Name (EN)', _selectedPromoData['name'] ?? ''),
                      _buildInputField('Sale Name (AR)', _selectedPromoData['nameAr'] ?? ''),
                      _buildInputField('Description (EN)', _selectedPromoData['description'] ?? ''),
                    ]),
                    const SizedBox(height: 32),
                    _buildEditorSection('Discount Config', [
                      Row(
                        children: [
                          Expanded(child: _buildInputField('Type', _selectedPromoData['discountType'] ?? 'percentage')),
                          const SizedBox(width: 12),
                          Expanded(child: _buildPricingField('Value', _selectedPromoData['discountValue'] ?? 0)),
                        ],
                      ),
                      _buildInputField('Target Type', _selectedPromoData['targetType'] ?? 'all'),
                    ]),
                    const SizedBox(height: 32),
                    _buildEditorSection('Rules & Constraints', [
                      _buildPricingField('Min Order Value', _selectedPromoData['minOrderValue'] ?? 0),
                      _buildPricingField('Max Discount Cap', _selectedPromoData['maxDiscountCap'] ?? 0),
                      _buildToggleField('Stackable with Coupons', _selectedPromoData['stackableWithCoupons'] ?? false),
                      _buildInputField('Priority', _selectedPromoData['priority']?.toString() ?? '0'),
                    ]),
                    const SizedBox(height: 32),
                    if (userScope.isSuperAdmin) 
                      _buildEditorSection('Branch Control (Super Admin)', [
                        _buildBranchMultiSelector(userScope.branchIds),
                      ]),
                  ],
                  const SizedBox(height: 48),
                  _buildEditorFooter(userScope.isSuperAdmin, filterBranchIds),
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

  Widget _buildInputField(String label, String value, {bool isHighlight = false}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
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
          const SizedBox(height: 8),
          Text(value, style: TextStyle(color: isHighlight ? appPrimary : appText, fontSize: 14, fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal)),
        ],
      ),
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
      children: tags.map((t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.grey[200]!)),
        child: Text(t.toString(), style: const TextStyle(color: appTextVariant, fontSize: 10, fontWeight: FontWeight.bold)),
      )).toList(),
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
          Text(name, style: const TextStyle(color: appText, fontSize: 12)),
          const Icon(Icons.delete_outline, color: appTextVariant, size: 16),
        ],
      ),
    );
  }

  Widget _buildAddBtn(String label) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: appPrimary.withOpacity(0.3)), borderRadius: BorderRadius.circular(8)),
      child: Text(label, textAlign: TextAlign.center, style: const TextStyle(color: appPrimary, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildPricingField(String label, dynamic value) {
    return Container(
      padding: const EdgeInsets.all(16),
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
              Text(value.toString(), style: const TextStyle(color: appText, fontSize: 24, fontWeight: FontWeight.w900)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildToggleField(String label, bool value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: appText, fontSize: 13, fontWeight: FontWeight.w500)),
          Container(
            width: 32, height: 16,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(color: appPrimary, borderRadius: BorderRadius.circular(8)),
            child: Align(alignment: Alignment.centerRight, child: Container(width: 12, height: 12, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle))),
          ),
        ],
      ),
    );
  }

  Widget _buildEditorFooter(bool isSuperAdmin, List<String> currentBranches) {
    return Column(
      children: [
        ElevatedButton(
          onPressed: () async {
            if (_selectedPromoId == null) return;
            String collection = _selectedCategory == 'combos' ? 'combos' : (_selectedCategory == 'sales' ? 'promoSales' : 'coupons');
            String nameField = _selectedCategory == 'coupons' ? 'title' : 'name';
            
            Map<String, dynamic> updates = {
              nameField: _selectedPromoData[nameField],
              if (_selectedPromoData['description'] != null) 'description': _selectedPromoData['description'],
              if (_selectedCategory == 'combos' && _selectedPromoData['comboPrice'] != null) 'comboPrice': _selectedPromoData['comboPrice'],
            };

            // RBAC Branch Selection
            if (isSuperAdmin) {
              updates['branchIds'] = _editingBranchIds;
            } else {
              // Non-super-admins can only save to their currently filtered branch (if single) or existing branches
              // For simplicity, we use the active branch filter
              if (currentBranches.isNotEmpty) {
                updates['branchIds'] = currentBranches;
              }
            }
            
            await FirebaseFirestore.instance.collection(collection).doc(_selectedPromoId).update(updates);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Campaign synchronized with localized settings')));
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: appPrimary,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 0,
          ),
          child: const Text('Save Bundle Updates', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 12),
        _buildSecondaryBtn('Archive Campaign', () async {
          if (_selectedPromoId == null) return;
          String collection = _selectedCategory == 'combos' ? 'combos' : (_selectedCategory == 'sales' ? 'promoSales' : 'coupons');
          String field = _selectedCategory == 'coupons' ? 'active' : 'isActive';
          await FirebaseFirestore.instance.collection(collection).doc(_selectedPromoId).update({field: false});
          setState(() {
            _selectedPromoId = null;
          });
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Campaign archived successfully')));
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

  Widget _buildBranchMultiSelector(List<String> allBranches) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: allBranches.map((id) {
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
      }).toList(),
    );
  }
}
