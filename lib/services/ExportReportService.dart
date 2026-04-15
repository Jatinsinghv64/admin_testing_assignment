// lib/services/ExportReportService.dart
// Generates PDF and Excel reports with multi-section support

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:excel/excel.dart' as xl;
import 'package:flutter/services.dart';
import 'package:file_saver/file_saver.dart';
import '../constants.dart';
import '../main.dart';
import '../Widgets/BranchFilterService.dart';

class ExportReportService {
  static Future<void> generateReport({
    required BuildContext context,
    required DateTimeRange dateRange,
    required String format,
    required Set<String> selectedSections,
    required List<String> branchIds,
    required BranchFilterService branchFilter,
    required UserScopeService userScope,
  }) async {
    // Fetch orders (needed for most sections)
    final orders = await _fetchOrders(dateRange, branchIds, userScope);
    final stats = _computeStats(orders);

    // Fetch additional data based on selected sections
    List<Map<String, dynamic>> marginData = [];
    List<Map<String, dynamic>> inventoryData = [];
    List<Map<String, dynamic>> staffData = [];
    Map<String, dynamic> promoData = {};
    List<Map<String, dynamic>> expenseData = [];

    if (selectedSections.contains('profit_margin')) {
      marginData = await _fetchMenuItemsWithMargin(branchIds);
    }
    if (selectedSections.contains('inventory_stock')) {
      inventoryData = await _fetchInventoryData(branchIds);
    }
    if (selectedSections.contains('staff_summary')) {
      staffData = await _fetchStaffData(branchIds);
    }
    if (selectedSections.contains('promotions_performance')) {
      promoData = await _fetchPromotionsData(branchIds);
    }
    if (selectedSections.contains('expense_summary')) {
      expenseData = await _fetchExpenseData(dateRange, branchIds);
    }

    if (format == 'pdf') {
      await _generatePdf(context, orders, dateRange, selectedSections, branchFilter, branchIds, stats, marginData, inventoryData, staffData, promoData, expenseData);
    } else {
      await _generateExcel(orders, dateRange, selectedSections, branchFilter, branchIds, stats, marginData, inventoryData, staffData, promoData, expenseData);
    }
  }

  // ─── Data Fetching ──────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> _fetchOrders(
    DateTimeRange dateRange,
    List<String> branchIds,
    UserScopeService userScope,
  ) async {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection(AppConstants.collectionOrders)
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(dateRange.start))
        .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(
            dateRange.end.add(const Duration(days: 1)).subtract(const Duration(seconds: 1))))
        .orderBy('timestamp', descending: true);

    if (branchIds.isNotEmpty) {
      query = query.where('branchIds', arrayContainsAny: branchIds);
    }

    final snapshot = await query.limit(2000).get();
    return snapshot.docs.map((d) {
      final data = d.data();
      data['docId'] = d.id;
      return data;
    }).toList();
  }

  static Future<List<Map<String, dynamic>>> _fetchExpenseData(DateTimeRange dateRange, List<String> branchIds) async {
    try {
      Query<Map<String, dynamic>> query = FirebaseFirestore.instance.collection(AppConstants.collectionExpenses);
      
      if (branchIds.isNotEmpty) {
        query = query.where('branchIds', arrayContainsAny: branchIds);
      }

      final snap = await query.get();
      final List<Map<String, dynamic>> result = [];

      for (var doc in snap.docs) {
        final data = doc.data();
        final payments = data['paymentHistory'] as List? ?? [];
        
        for (var p in payments) {
          if (p is Map<String, dynamic>) {
            final ts = p['paidAt'] as Timestamp?;
            if (ts != null) {
              final paidAt = ts.toDate();
              if (paidAt.isAfter(dateRange.start) && paidAt.isBefore(dateRange.end.add(const Duration(days: 1)))) {
                result.add({
                  'title': data['title'] ?? 'Unknown',
                  'category': data['category'] ?? '-',
                  'amount': (p['amount'] as num?)?.toDouble() ?? 0,
                  'date': paidAt,
                  'vendor': data['vendorName'] ?? '-',
                });
              }
            }
          }
        }
      }
      return result;
    } catch (e) {
      debugPrint('Error fetching expenses: $e');
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> _fetchMenuItemsWithMargin(List<String> branchIds) async {
    try {
      // Fetch menu items
      final menuSnap = await FirebaseFirestore.instance.collection('menu_items').get();
      // Fetch recipes for cost data
      final recipeSnap = await FirebaseFirestore.instance.collection(AppConstants.collectionRecipes).get();

      // Build recipe cost map: menuItemId -> costPerServing
      final Map<String, double> recipeCostMap = {};
      for (final doc in recipeSnap.docs) {
        final data = doc.data();
        final menuItemId = data['menuItemId']?.toString() ?? '';
        final cost = (data['costPerServing'] as num?)?.toDouble() ?? 0;
        if (menuItemId.isNotEmpty && cost > 0) {
          recipeCostMap[menuItemId] = cost;
        }
      }

      final List<Map<String, dynamic>> result = [];
      for (final doc in menuSnap.docs) {
        final data = doc.data();
        final price = (data['price'] as num?)?.toDouble() ?? 0;
        final cost = recipeCostMap[doc.id] ?? 0;
        final margin = price > 0 ? ((price - cost) / price * 100) : 0.0;
        final profit = price - cost;

        result.add({
          'name': data['name'] ?? 'Unknown',
          'price': price,
          'cost': cost,
          'margin': margin,
          'profit': profit,
          'category': data['category'] ?? '-',
        });
      }

      // Sort by margin ascending (worst margin first)
      result.sort((a, b) => (a['margin'] as double).compareTo(b['margin'] as double));
      return result;
    } catch (e) {
      debugPrint('Error fetching margin data: $e');
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> _fetchInventoryData(List<String> branchIds) async {
    try {
      final snap = await FirebaseFirestore.instance.collection(AppConstants.collectionIngredients).get();
      final branchId = branchIds.isNotEmpty ? branchIds.first : 'default';

      final List<Map<String, dynamic>> result = [];
      for (final doc in snap.docs) {
        final data = doc.data();
        // Branch-specific stock
        final stockMap = data['stock'] as Map<String, dynamic>? ?? {};
        final stock = (stockMap[branchId] as num?)?.toDouble() ?? (data['currentStock'] as num?)?.toDouble() ?? 0;
        final unit = data['unit']?.toString() ?? '-';
        final costPerUnit = (data['costPerUnit'] as num?)?.toDouble() ?? 0;
        final value = stock * costPerUnit;

        final minThresholdMap = data['minThreshold'] as Map<String, dynamic>? ?? {};
        final minThreshold = (minThresholdMap[branchId] as num?)?.toDouble() ?? (data['minThreshold'] as num?)?.toDouble() ?? 0;

        final bool isLow = minThreshold > 0 && stock <= minThreshold;
        final bool isOut = stock <= 0;

        result.add({
          'name': data['name'] ?? 'Unknown',
          'stock': stock,
          'unit': unit,
          'costPerUnit': costPerUnit,
          'value': value,
          'minThreshold': minThreshold,
          'isLow': isLow,
          'isOut': isOut,
          'status': isOut ? 'Out of Stock' : (isLow ? 'Low Stock' : 'In Stock'),
        });
      }

      result.sort((a, b) => (a['stock'] as double).compareTo(b['stock'] as double));
      return result;
    } catch (e) {
      debugPrint('Error fetching inventory data: $e');
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> _fetchStaffData(List<String> branchIds) async {
    try {
      Query<Map<String, dynamic>> query = FirebaseFirestore.instance.collection(AppConstants.collectionStaff);
      if (branchIds.isNotEmpty) {
        query = query.where('branchIds', arrayContainsAny: branchIds);
      }
      final snap = await query.get();

      return snap.docs.map((doc) {
        final data = doc.data();
        return {
          'name': data['name'] ?? 'Unknown',
          'email': data['email'] ?? '-',
          'role': data['role'] ?? 'Staff',
          'salary': double.tryParse(data['salary']?.toString() ?? '0') ?? 0.0,
          'isActive': data['isActive'] ?? true,
          'branches': (data['branchIds'] as List?)?.join(', ') ?? '-',
        };
      }).toList();
    } catch (e) {
      debugPrint('Error fetching staff data: $e');
      return [];
    }
  }

  static Future<Map<String, dynamic>> _fetchPromotionsData(List<String> branchIds) async {
    try {
      final comboSnap = await FirebaseFirestore.instance.collection('combos').where('isActive', isEqualTo: true).get();
      final saleSnap = await FirebaseFirestore.instance.collection('promoSales').where('isActive', isEqualTo: true).get();
      final couponSnap = await FirebaseFirestore.instance.collection(AppConstants.collectionCoupons).where('active', isEqualTo: true).get();

      final combos = comboSnap.docs.map((d) {
        final data = d.data();
        return {
          'type': 'Combo',
          'name': data['name'] ?? '-',
          'price': (data['comboPrice'] as num?)?.toDouble() ?? 0,
          'orders': (data['orderCount'] as num?)?.toInt() ?? 0,
          'active': data['isActive'] ?? false,
        };
      }).toList();

      final sales = saleSnap.docs.map((d) {
        final data = d.data();
        return {
          'type': 'Sale',
          'name': data['name'] ?? '-',
          'discount': '${data['discountValue'] ?? 0}${data['discountType'] == 'percentage' ? '%' : ' QAR'}',
          'active': data['isActive'] ?? false,
        };
      }).toList();

      final coupons = couponSnap.docs.map((d) {
        final data = d.data();
        return {
          'type': 'Coupon',
          'code': data['code'] ?? '-',
          'value': '${data['value'] ?? 0}${data['type'] == 'percentage' ? '%' : ' QAR'}',
          'uses': (data['usageCount'] as num?)?.toInt() ?? 0,
          'active': data['active'] ?? false,
        };
      }).toList();

      return {
        'activeCombos': combos.length,
        'activeSales': sales.length,
        'activeCoupons': coupons.length,
        'totalActive': combos.length + sales.length + coupons.length,
        'combos': combos,
        'sales': sales,
        'coupons': coupons,
      };
    } catch (e) {
      debugPrint('Error fetching promotions data: $e');
      return {'totalActive': 0, 'combos': [], 'sales': [], 'coupons': []};
    }
  }

  // ─── Report Computation ─────────────────────────────────────
  static Map<String, dynamic> _computeStats(List<Map<String, dynamic>> orders) {
    double totalRevenue = 0;
    int completedOrders = 0;
    int cancelledOrders = 0;
    final Map<String, double> revenueBySource = {};
    final Map<String, double> revenueByBranch = {};
    final Map<String, int> countBySource = {};
    final Map<String, int> countByBranch = {};
    final Map<String, Map<String, dynamic>> itemSales = {};
    final Map<int, double> revenueByHour = {};
    final Map<int, int> ordersByHour = {};
    final Map<String, int> ordersByType = {};
    double totalTax = 0;
    double totalDiscount = 0;

    for (final order in orders) {
      final amount = (order['totalAmount'] as num?)?.toDouble() ?? 0;
      final status = order['status']?.toString() ?? '';
      final source = (order['source']?.toString() ?? order['Order_source']?.toString() ?? 'app').toUpperCase();
      final branchList = order['branchIds'] as List<dynamic>? ?? [];
      final branch = branchList.isNotEmpty ? branchList.first.toString() : 'Unknown';
      final orderType = AppConstants.normalizeOrderType(order['Order_type']?.toString());
      final ts = order['timestamp'] as Timestamp?;

      if (!['cancelled', 'refunded'].contains(status.toLowerCase())) {
        totalRevenue += amount;
        completedOrders++;
      } else {
        cancelledOrders++;
      }

      // Hourly breakdown
      if (ts != null) {
        final hour = ts.toDate().hour;
        revenueByHour[hour] = (revenueByHour[hour] ?? 0) + amount;
        ordersByHour[hour] = (ordersByHour[hour] ?? 0) + 1;
      }

      // Order type breakdown
      ordersByType[orderType] = (ordersByType[orderType] ?? 0) + 1;

      // Tax & discount
      totalTax += (order['tax'] as num?)?.toDouble() ?? 0;
      totalDiscount += (order['discountAmount'] as num?)?.toDouble() ?? (order['discount'] as num?)?.toDouble() ?? 0;

      revenueBySource[source] = (revenueBySource[source] ?? 0) + amount;
      countBySource[source] = (countBySource[source] ?? 0) + 1;
      revenueByBranch[branch] = (revenueByBranch[branch] ?? 0) + amount;
      countByBranch[branch] = (countByBranch[branch] ?? 0) + 1;

      // Item-level aggregation
      final items = order['items'] as List<dynamic>? ?? [];
      for (final item in items) {
        if (item is Map<String, dynamic>) {
          final name = item['name']?.toString() ?? 'Unknown';
          final qty = (item['quantity'] as num?)?.toInt() ?? 1;
          final price = (item['price'] as num?)?.toDouble() ?? 0;
          if (!itemSales.containsKey(name)) {
            itemSales[name] = {'name': name, 'quantity': 0, 'revenue': 0.0};
          }
          itemSales[name]!['quantity'] = (itemSales[name]!['quantity'] as int) + qty;
          itemSales[name]!['revenue'] = (itemSales[name]!['revenue'] as double) + (price * qty);
        }
      }
    }

    final avgOrderValue = completedOrders > 0 ? totalRevenue / completedOrders : 0.0;

    // Peak hour
    int peakHour = 0;
    int peakOrders = 0;
    ordersByHour.forEach((hour, count) {
      if (count > peakOrders) {
        peakHour = hour;
        peakOrders = count;
      }
    });

    // Items per order
    int totalItems = 0;
    for (final item in itemSales.values) {
      totalItems += item['quantity'] as int;
    }
    final avgItemsPerOrder = completedOrders > 0 ? totalItems / completedOrders : 0.0;

    return {
      'totalOrders': orders.length,
      'completedOrders': completedOrders,
      'cancelledOrders': cancelledOrders,
      'cancellationRate': orders.isNotEmpty ? (cancelledOrders / orders.length * 100) : 0.0,
      'totalRevenue': totalRevenue,
      'avgOrderValue': avgOrderValue,
      'totalTax': totalTax,
      'totalDiscount': totalDiscount,
      'revenueBySource': revenueBySource,
      'revenueByBranch': revenueByBranch,
      'countBySource': countBySource,
      'countByBranch': countByBranch,
      'ordersByType': ordersByType,
      'peakHour': peakHour,
      'peakHourOrders': peakOrders,
      'avgItemsPerOrder': avgItemsPerOrder,
      'itemSales': itemSales.values.toList()..sort((a, b) => (b['quantity'] as int).compareTo(a['quantity'] as int)),
    };
  }

  // ─── PDF Generation ─────────────────────────────────────────
  static Future<void> _generatePdf(
    BuildContext context,
    List<Map<String, dynamic>> orders,
    DateTimeRange dateRange,
    Set<String> selectedSections,
    BranchFilterService branchFilter,
    List<String> branchIds,
    Map<String, dynamic> stats,
    List<Map<String, dynamic>> marginData,
    List<Map<String, dynamic>> inventoryData,
    List<Map<String, dynamic>> staffData,
    Map<String, dynamic> promoData,
    List<Map<String, dynamic>> expenseData,
  ) async {
    final pdf = pw.Document();
    final dateFmt = DateFormat('MMM dd, yyyy');
    final dateStr = '${dateFmt.format(dateRange.start)} – ${dateFmt.format(dateRange.end)}';
    final branchLabel = branchFilter.selectedBranchId == null
        ? 'All Branches'
        : branchFilter.getBranchName(branchFilter.selectedBranchId!);

    // Load logo
    Uint8List? logoBytes;
    try {
      final data = await rootBundle.load('assets/mitranlogo.jpg');
      logoBytes = data.buffer.asUint8List();
    } catch (_) {}

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        header: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                if (logoBytes != null)
                  pw.Image(pw.MemoryImage(logoBytes), width: 50, height: 50)
                else
                  pw.Container(width: 50),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Business Report', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfColors.deepPurple)),
                    pw.SizedBox(height: 4),
                    pw.Text(dateStr, style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
                    pw.Text('Branch: $branchLabel', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
                  ],
                ),
              ],
            ),
            pw.Divider(color: PdfColors.deepPurple, thickness: 2),
            pw.SizedBox(height: 8),
          ],
        ),
        footer: (ctx) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 10),
          child: pw.Text(
            'Page ${ctx.pageNumber}/${ctx.pagesCount} | Generated: ${DateFormat('MMM dd, yyyy HH:mm').format(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey),
          ),
        ),
        build: (ctx) => _buildPdfContent(selectedSections, stats, orders, branchFilter, marginData, inventoryData, staffData, promoData, expenseData),
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
      name: 'Business_Report_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }

  static List<pw.Widget> _buildPdfContent(
    Set<String> selectedSections,
    Map<String, dynamic> stats,
    List<Map<String, dynamic>> orders,
    BranchFilterService branchFilter,
    List<Map<String, dynamic>> marginData,
    List<Map<String, dynamic>> inventoryData,
    List<Map<String, dynamic>> staffData,
    Map<String, dynamic> promoData,
    List<Map<String, dynamic>> expenseData,
  ) {
    final widgets = <pw.Widget>[];

    // Always show summary KPIs
    widgets.add(pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(color: PdfColors.grey100, borderRadius: pw.BorderRadius.circular(8)),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: [
          _pdfKpi('Total Orders', '${stats['totalOrders']}', PdfColors.blue),
          _pdfKpi('Revenue', 'QAR ${(stats['totalRevenue'] as double).toStringAsFixed(0)}', PdfColors.green),
          _pdfKpi('Avg Order', 'QAR ${(stats['avgOrderValue'] as double).toStringAsFixed(0)}', PdfColors.orange),
          _pdfKpi('Cancel Rate', '${(stats['cancellationRate'] as double).toStringAsFixed(1)}%', PdfColors.red),
        ],
      ),
    ));
    widgets.add(pw.SizedBox(height: 20));

    // Build sections based on selection
    if (selectedSections.contains('sales_summary')) {
      widgets.addAll(_buildSalesSummarySection(stats));
      widgets.add(pw.SizedBox(height: 16));
    }

    if (selectedSections.contains('order_details')) {
      widgets.addAll(_buildOrderDetailsTable(orders));
      widgets.add(pw.SizedBox(height: 16));
    }

    if (selectedSections.contains('revenue_by_source')) {
      widgets.addAll(_buildRevenueBySource(stats));
      widgets.add(pw.SizedBox(height: 16));
    }

    if (selectedSections.contains('revenue_by_branch')) {
      widgets.addAll(_buildRevenueByBranch(stats, branchFilter));
      widgets.add(pw.SizedBox(height: 16));
    }

    if (selectedSections.contains('item_wise_sales')) {
      widgets.addAll(_buildItemWiseSales(stats));
      widgets.add(pw.SizedBox(height: 16));
    }

    if (selectedSections.contains('profit_margin')) {
      widgets.addAll(_buildProfitMarginSection(marginData));
      widgets.add(pw.SizedBox(height: 16));
    }

    if (selectedSections.contains('inventory_stock')) {
      widgets.addAll(_buildInventorySection(inventoryData));
      widgets.add(pw.SizedBox(height: 16));
    }

    if (selectedSections.contains('staff_summary')) {
      widgets.addAll(_buildStaffSection(staffData));
      widgets.add(pw.SizedBox(height: 16));
    }

    if (selectedSections.contains('promotions_performance')) {
      widgets.addAll(_buildPromotionsSection(promoData));
      widgets.add(pw.SizedBox(height: 16));
    }

    if (selectedSections.contains('expense_summary')) {
      widgets.addAll(_buildExpenseSection(expenseData));
      widgets.add(pw.SizedBox(height: 16));
    }

    return widgets;
  }

  // ─── PDF Section Builders ───────────────────────────────────

  static List<pw.Widget> _buildSalesSummarySection(Map<String, dynamic> stats) {
    final ordersByType = stats['ordersByType'] as Map<String, int>;
    return [
      _pdfSection('Sales Summary'),
      pw.SizedBox(height: 8),
      pw.Table.fromTextArray(
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.deepPurple),
        cellPadding: const pw.EdgeInsets.all(8),
        headers: ['Metric', 'Value'],
        data: [
          ['Total Orders', '${stats['totalOrders']}'],
          ['Completed Orders', '${stats['completedOrders']}'],
          ['Cancelled Orders', '${stats['cancelledOrders']}'],
          ['Cancellation Rate', '${(stats['cancellationRate'] as double).toStringAsFixed(1)}%'],
          ['Total Revenue', 'QAR ${(stats['totalRevenue'] as double).toStringAsFixed(2)}'],
          ['Avg Order Value', 'QAR ${(stats['avgOrderValue'] as double).toStringAsFixed(2)}'],
          ['Total Tax', 'QAR ${(stats['totalTax'] as double).toStringAsFixed(2)}'],
          ['Total Discounts', 'QAR ${(stats['totalDiscount'] as double).toStringAsFixed(2)}'],
          ['Peak Hour', '${stats['peakHour']}:00 (${stats['peakHourOrders']} orders)'],
          ['Avg Items/Order', '${(stats['avgItemsPerOrder'] as double).toStringAsFixed(1)}'],
          ...ordersByType.entries.map((e) => ['Orders: ${_formatOrderType(e.key)}', '${e.value}']),
        ],
      ),
    ];
  }

  static List<pw.Widget> _buildOrderDetailsTable(List<Map<String, dynamic>> orders) {
    final dateFmt = DateFormat('dd/MM HH:mm');
    return [
      _pdfSection('Order Details'),
      pw.SizedBox(height: 8),
      pw.Table.fromTextArray(
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 9),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.deepPurple),
        cellPadding: const pw.EdgeInsets.all(6),
        cellStyle: const pw.TextStyle(fontSize: 9),
        headers: ['#', 'Date', 'Customer', 'Source', 'Items', 'Total', 'Status'],
        data: orders.take(100).toList().asMap().entries.map((e) {
          final o = e.value;
          final ts = o['timestamp'] as Timestamp?;
          final date = ts != null ? dateFmt.format(ts.toDate()) : '-';
          final items = (o['items'] as List?)?.length ?? 0;
          final amount = (o['totalAmount'] as num?)?.toDouble() ?? 0;
          return [
            '${e.key + 1}',
            date,
            o['customerName'] ?? 'Guest',
            (o['source'] ?? o['Order_source'] ?? 'App').toString().toUpperCase(),
            '$items',
            'QAR ${amount.toStringAsFixed(2)}',
            (o['status'] ?? '-').toString(),
          ];
        }).toList(),
      ),
    ];
  }

  static List<pw.Widget> _buildRevenueBySource(Map<String, dynamic> stats) {
    final revenueBySource = stats['revenueBySource'] as Map<String, double>;
    final countBySource = stats['countBySource'] as Map<String, int>;
    if (revenueBySource.isEmpty) return [];
    return [
      _pdfSection('Revenue by Source'),
      pw.SizedBox(height: 8),
      pw.Table.fromTextArray(
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.deepPurple),
        cellPadding: const pw.EdgeInsets.all(8),
        headers: ['Source', 'Orders', 'Revenue', '% of Total'],
        data: revenueBySource.entries.map((e) {
          final total = stats['totalRevenue'] as double;
          final pct = total > 0 ? (e.value / total * 100).toStringAsFixed(1) : '0';
          return [e.key, '${countBySource[e.key] ?? 0}', 'QAR ${e.value.toStringAsFixed(2)}', '$pct%'];
        }).toList(),
      ),
    ];
  }

  static List<pw.Widget> _buildRevenueByBranch(Map<String, dynamic> stats, BranchFilterService branchFilter) {
    final revenueByBranch = stats['revenueByBranch'] as Map<String, double>;
    final countByBranch = stats['countByBranch'] as Map<String, int>;
    if (revenueByBranch.isEmpty) return [];
    return [
      _pdfSection('Revenue by Branch'),
      pw.SizedBox(height: 8),
      pw.Table.fromTextArray(
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.deepPurple),
        cellPadding: const pw.EdgeInsets.all(8),
        headers: ['Branch', 'Orders', 'Revenue', '% of Total'],
        data: revenueByBranch.entries.map((e) {
          final total = stats['totalRevenue'] as double;
          final pct = total > 0 ? (e.value / total * 100).toStringAsFixed(1) : '0';
          final name = branchFilter.getBranchName(e.key);
          return [name, '${countByBranch[e.key] ?? 0}', 'QAR ${e.value.toStringAsFixed(2)}', '$pct%'];
        }).toList(),
      ),
    ];
  }

  static List<pw.Widget> _buildItemWiseSales(Map<String, dynamic> stats) {
    final items = stats['itemSales'] as List<Map<String, dynamic>>;
    if (items.isEmpty) return [];
    return [
      _pdfSection('Item-wise Sales (Top 30)'),
      pw.SizedBox(height: 8),
      pw.Table.fromTextArray(
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.deepPurple),
        cellPadding: const pw.EdgeInsets.all(6),
        headers: ['#', 'Item', 'Qty Sold', 'Revenue'],
        data: items.take(30).toList().asMap().entries.map((e) {
          final item = e.value;
          return [
            '${e.key + 1}',
            item['name'],
            '${item['quantity']}',
            'QAR ${(item['revenue'] as double).toStringAsFixed(2)}',
          ];
        }).toList(),
      ),
    ];
  }

  static List<pw.Widget> _buildProfitMarginSection(List<Map<String, dynamic>> marginData) {
    if (marginData.isEmpty) {
      return [
        _pdfSection('Profit & Margin Analysis'),
        pw.SizedBox(height: 8),
        pw.Text('No recipe/cost data available. Configure recipes for margin analysis.', style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey600)),
      ];
    }
    return [
      _pdfSection('Profit & Margin Analysis'),
      pw.SizedBox(height: 8),
      pw.Table.fromTextArray(
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 9),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.deepPurple),
        cellPadding: const pw.EdgeInsets.all(6),
        cellStyle: const pw.TextStyle(fontSize: 9),
        headers: ['Item', 'Category', 'Price', 'Cost', 'Profit', 'Margin %'],
        data: marginData.take(50).map((m) {
          return [
            m['name'],
            m['category'],
            'QAR ${(m['price'] as double).toStringAsFixed(2)}',
            m['cost'] > 0 ? 'QAR ${(m['cost'] as double).toStringAsFixed(2)}' : 'N/A',
            m['cost'] > 0 ? 'QAR ${(m['profit'] as double).toStringAsFixed(2)}' : 'N/A',
            m['cost'] > 0 ? '${(m['margin'] as double).toStringAsFixed(1)}%' : 'N/A',
          ];
        }).toList(),
      ),
    ];
  }

  static List<pw.Widget> _buildInventorySection(List<Map<String, dynamic>> inventoryData) {
    if (inventoryData.isEmpty) {
      return [
        _pdfSection('Inventory & Stock Status'),
        pw.SizedBox(height: 8),
        pw.Text('No inventory data available.', style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey600)),
      ];
    }

    double totalValue = 0;
    int lowStockCount = 0;
    int outOfStockCount = 0;
    for (final item in inventoryData) {
      totalValue += item['value'] as double;
      if (item['isOut'] == true) outOfStockCount++;
      else if (item['isLow'] == true) lowStockCount++;
    }

    return [
      _pdfSection('Inventory & Stock Status'),
      pw.SizedBox(height: 8),
      pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(color: PdfColors.grey100, borderRadius: pw.BorderRadius.circular(6)),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
          children: [
            _pdfKpi('Total Items', '${inventoryData.length}', PdfColors.blue),
            _pdfKpi('Total Value', 'QAR ${totalValue.toStringAsFixed(0)}', PdfColors.green),
            _pdfKpi('Low Stock', '$lowStockCount', PdfColors.orange),
            _pdfKpi('Out of Stock', '$outOfStockCount', PdfColors.red),
          ],
        ),
      ),
      pw.SizedBox(height: 8),
      pw.Table.fromTextArray(
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 9),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.deepPurple),
        cellPadding: const pw.EdgeInsets.all(5),
        cellStyle: const pw.TextStyle(fontSize: 9),
        headers: ['Ingredient', 'Stock', 'Unit', 'Value', 'Status'],
        data: inventoryData.take(50).map((i) {
          return [
            i['name'],
            '${(i['stock'] as double).toStringAsFixed(1)}',
            i['unit'],
            'QAR ${(i['value'] as double).toStringAsFixed(2)}',
            i['status'],
          ];
        }).toList(),
      ),
    ];
  }

  static List<pw.Widget> _buildStaffSection(List<Map<String, dynamic>> staffData) {
    if (staffData.isEmpty) {
      return [
        _pdfSection('Staff Summary'),
        pw.SizedBox(height: 8),
        pw.Text('No staff data available.', style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey600)),
      ];
    }

    final activeCount = staffData.where((s) => s['isActive'] == true).length;
    // Group by role
    final Map<String, int> roleCount = {};
    for (final s in staffData) {
      final role = s['role']?.toString() ?? 'Staff';
      roleCount[role] = (roleCount[role] ?? 0) + 1;
    }

    return [
      _pdfSection('Staff Summary'),
      pw.SizedBox(height: 8),
      pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(color: PdfColors.grey100, borderRadius: pw.BorderRadius.circular(6)),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
          children: [
            _pdfKpi('Total Staff', '${staffData.length}', PdfColors.blue),
            _pdfKpi('Active', '$activeCount', PdfColors.green),
            _pdfKpi('Roles', '${roleCount.length}', PdfColors.orange),
          ],
        ),
      ),
      pw.SizedBox(height: 8),
      pw.Table.fromTextArray(
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.deepPurple),
        cellPadding: const pw.EdgeInsets.all(6),
        headers: ['Name', 'Role', 'Email', 'Salary', 'Status'],
        data: staffData.map((s) {
          return [
            s['name'],
            s['role'],
            s['email'],
            'QAR ${(s['salary'] as double).toStringAsFixed(0)}',
            s['isActive'] == true ? 'Active' : 'Inactive',
          ];
        }).toList(),
      ),
    ];
  }

  static List<pw.Widget> _buildPromotionsSection(Map<String, dynamic> promoData) {
    final totalActive = promoData['totalActive'] ?? 0;
    if (totalActive == 0) {
      return [
        _pdfSection('Promotions Performance'),
        pw.SizedBox(height: 8),
        pw.Text('No active promotions found.', style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey600)),
      ];
    }

    final widgets = <pw.Widget>[
      _pdfSection('Promotions Performance'),
      pw.SizedBox(height: 8),
      pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(color: PdfColors.grey100, borderRadius: pw.BorderRadius.circular(6)),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
          children: [
            _pdfKpi('Active Combos', '${promoData['activeCombos'] ?? 0}', PdfColors.blue),
            _pdfKpi('Active Sales', '${promoData['activeSales'] ?? 0}', PdfColors.green),
            _pdfKpi('Active Coupons', '${promoData['activeCoupons'] ?? 0}', PdfColors.orange),
          ],
        ),
      ),
    ];

    // Combos table
    final combos = promoData['combos'] as List? ?? [];
    if (combos.isNotEmpty) {
      widgets.add(pw.SizedBox(height: 8));
      widgets.add(pw.Text('Active Combos', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)));
      widgets.add(pw.SizedBox(height: 4));
      widgets.add(pw.Table.fromTextArray(
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 9),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.deepPurple),
        cellPadding: const pw.EdgeInsets.all(5),
        cellStyle: const pw.TextStyle(fontSize: 9),
        headers: ['Name', 'Price', 'Orders'],
        data: combos.map((c) => [c['name'], 'QAR ${(c['price'] as double).toStringAsFixed(2)}', '${c['orders']}']).toList(),
      ));
    }

    // Coupons table
    final coupons = promoData['coupons'] as List? ?? [];
    if (coupons.isNotEmpty) {
      widgets.add(pw.SizedBox(height: 8));
      widgets.add(pw.Text('Active Coupons', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)));
      widgets.add(pw.SizedBox(height: 4));
      widgets.add(pw.Table.fromTextArray(
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 9),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.deepPurple),
        cellPadding: const pw.EdgeInsets.all(5),
        cellStyle: const pw.TextStyle(fontSize: 9),
        headers: ['Code', 'Discount', 'Uses'],
        data: coupons.map((c) => [c['code'], c['value'], '${c['uses']}']).toList(),
      ));
    }

    return widgets;
  }

  static pw.Widget _pdfKpi(String title, String value, PdfColor color) {
    return pw.Column(children: [
      pw.Text(value, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: color)),
      pw.SizedBox(height: 4),
      pw.Text(title, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
    ]);
  }

  static pw.Widget _pdfSection(String title) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: const pw.BoxDecoration(
        color: PdfColors.deepPurple50,
        border: pw.Border(left: pw.BorderSide(color: PdfColors.deepPurple, width: 4)),
      ),
      child: pw.Text(title, style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: PdfColors.deepPurple)),
    );
  }

  static String _formatOrderType(String type) {
    return type.replaceAll('_', ' ').split(' ').map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '').join(' ');
  }

  static List<pw.Widget> _buildExpenseSection(List<Map<String, dynamic>> expenseData) {
    if (expenseData.isEmpty) {
      return [
        _pdfSection('Expense Summary'),
        pw.SizedBox(height: 8),
        pw.Text('No expenses recorded for this period.', style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey600)),
      ];
    }

    double totalExpenses = 0.0;
    for (final e in expenseData) {
      totalExpenses += (e['amount'] as double);
    }

    return [
      _pdfSection('Expense Summary'),
      pw.SizedBox(height: 8),
      pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(color: PdfColors.grey100, borderRadius: pw.BorderRadius.circular(6)),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
          children: [
            _pdfKpi('Total Paid', 'QAR ${totalExpenses.toStringAsFixed(2)}', PdfColors.red),
            _pdfKpi('Total Entries', '${expenseData.length}', PdfColors.purple),
          ],
        ),
      ),
      pw.SizedBox(height: 8),
      pw.Table.fromTextArray(
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 9),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.deepPurple),
        cellPadding: const pw.EdgeInsets.all(5),
        cellStyle: const pw.TextStyle(fontSize: 9),
        headers: ['Date', 'Title', 'Category', 'Vendor', 'Amount'],
        data: expenseData.map((e) {
          return [
            DateFormat('MMM dd').format(e['date'] as DateTime),
            e['title'].toString(),
            e['category'].toString(),
            e['vendor'].toString(),
            'QAR ${(e['amount'] as double).toStringAsFixed(2)}',
          ];
        }).toList(),
      ),
    ];
  }

  // ─── Excel Generation ───────────────────────────────────────
  static Future<void> _generateExcel(
    List<Map<String, dynamic>> orders,
    DateTimeRange dateRange,
    Set<String> selectedSections,
    BranchFilterService branchFilter,
    List<String> branchIds,
    Map<String, dynamic> stats,
    List<Map<String, dynamic>> marginData,
    List<Map<String, dynamic>> inventoryData,
    List<Map<String, dynamic>> staffData,
    Map<String, dynamic> promoData,
    List<Map<String, dynamic>> expenseData,
  ) async {
    final excel = xl.Excel.createExcel();
    final dateFmt = DateFormat('MMM dd, yyyy');
    final dateStr = '${dateFmt.format(dateRange.start)} – ${dateFmt.format(dateRange.end)}';

    // ─── Summary Sheet (always) ─────────────────────────────
    final summarySheet = excel['Summary'];
    summarySheet.appendRow([xl.TextCellValue('Business Report')]);
    summarySheet.appendRow([xl.TextCellValue('Date Range: $dateStr')]);
    summarySheet.appendRow([xl.TextCellValue('')]);
    summarySheet.appendRow([xl.TextCellValue('Metric'), xl.TextCellValue('Value')]);
    summarySheet.appendRow([xl.TextCellValue('Total Orders'), xl.IntCellValue(stats['totalOrders'] as int)]);
    summarySheet.appendRow([xl.TextCellValue('Completed Orders'), xl.IntCellValue(stats['completedOrders'] as int)]);
    summarySheet.appendRow([xl.TextCellValue('Cancelled Orders'), xl.IntCellValue(stats['cancelledOrders'] as int)]);
    summarySheet.appendRow([xl.TextCellValue('Cancellation Rate'), xl.TextCellValue('${(stats['cancellationRate'] as double).toStringAsFixed(1)}%')]);
    summarySheet.appendRow([xl.TextCellValue('Total Revenue (QAR)'), xl.DoubleCellValue(stats['totalRevenue'] as double)]);
    summarySheet.appendRow([xl.TextCellValue('Avg Order Value (QAR)'), xl.DoubleCellValue(stats['avgOrderValue'] as double)]);
    summarySheet.appendRow([xl.TextCellValue('Total Tax (QAR)'), xl.DoubleCellValue(stats['totalTax'] as double)]);
    summarySheet.appendRow([xl.TextCellValue('Total Discounts (QAR)'), xl.DoubleCellValue(stats['totalDiscount'] as double)]);
    summarySheet.appendRow([xl.TextCellValue('Peak Hour'), xl.TextCellValue('${stats['peakHour']}:00 (${stats['peakHourOrders']} orders)')]);

    // ─── Orders Sheet ─────────────────────────────────────────
    if (selectedSections.contains('order_details') || selectedSections.contains('sales_summary')) {
      final ordersSheet = excel['Orders'];
      ordersSheet.appendRow([
        xl.TextCellValue('Date'), xl.TextCellValue('Customer'), xl.TextCellValue('Source'),
        xl.TextCellValue('Type'), xl.TextCellValue('Items'), xl.TextCellValue('Total (QAR)'),
        xl.TextCellValue('Status'), xl.TextCellValue('Branch'),
      ]);
      final orderDateFmt = DateFormat('yyyy-MM-dd HH:mm');
      for (final order in orders) {
        final ts = order['timestamp'] as Timestamp?;
        final date = ts != null ? orderDateFmt.format(ts.toDate()) : '';
        final branchList = order['branchIds'] as List<dynamic>? ?? [];
        final branch = branchList.isNotEmpty ? branchList.first.toString() : '';
        ordersSheet.appendRow([
          xl.TextCellValue(date),
          xl.TextCellValue(order['customerName']?.toString() ?? 'Guest'),
          xl.TextCellValue((order['source'] ?? order['Order_source'] ?? 'App').toString()),
          xl.TextCellValue(order['Order_type']?.toString() ?? 'delivery'),
          xl.IntCellValue((order['items'] as List?)?.length ?? 0),
          xl.DoubleCellValue((order['totalAmount'] as num?)?.toDouble() ?? 0),
          xl.TextCellValue(order['status']?.toString() ?? ''),
          xl.TextCellValue(branch),
        ]);
      }
    }

    // Revenue by Source
    if (selectedSections.contains('revenue_by_source') || selectedSections.contains('sales_summary')) {
      final sourceSheet = excel['By Source'];
      sourceSheet.appendRow([xl.TextCellValue('Source'), xl.TextCellValue('Orders'), xl.TextCellValue('Revenue (QAR)')]);
      final revBySource = stats['revenueBySource'] as Map<String, double>;
      final countBySource = stats['countBySource'] as Map<String, int>;
      for (final entry in revBySource.entries) {
        sourceSheet.appendRow([xl.TextCellValue(entry.key), xl.IntCellValue(countBySource[entry.key] ?? 0), xl.DoubleCellValue(entry.value)]);
      }
    }

    // Revenue by Branch
    if (selectedSections.contains('revenue_by_branch') || selectedSections.contains('sales_summary')) {
      final branchSheet = excel['By Branch'];
      branchSheet.appendRow([xl.TextCellValue('Branch'), xl.TextCellValue('Orders'), xl.TextCellValue('Revenue (QAR)')]);
      final revByBranch = stats['revenueByBranch'] as Map<String, double>;
      final countByBranch = stats['countByBranch'] as Map<String, int>;
      for (final entry in revByBranch.entries) {
        branchSheet.appendRow([xl.TextCellValue(branchFilter.getBranchName(entry.key)), xl.IntCellValue(countByBranch[entry.key] ?? 0), xl.DoubleCellValue(entry.value)]);
      }
    }

    // Item Sales
    if (selectedSections.contains('item_wise_sales') || selectedSections.contains('sales_summary')) {
      final itemSheet = excel['Item Sales'];
      itemSheet.appendRow([xl.TextCellValue('Item'), xl.TextCellValue('Qty Sold'), xl.TextCellValue('Revenue (QAR)')]);
      final items = stats['itemSales'] as List<Map<String, dynamic>>;
      for (final item in items) {
        itemSheet.appendRow([xl.TextCellValue(item['name'] as String), xl.IntCellValue(item['quantity'] as int), xl.DoubleCellValue(item['revenue'] as double)]);
      }
    }

    // Profit & Margin
    if (selectedSections.contains('profit_margin') && marginData.isNotEmpty) {
      final marginSheet = excel['Profit Margin'];
      marginSheet.appendRow([xl.TextCellValue('Item'), xl.TextCellValue('Category'), xl.TextCellValue('Price'), xl.TextCellValue('Cost'), xl.TextCellValue('Profit'), xl.TextCellValue('Margin %')]);
      for (final m in marginData) {
        marginSheet.appendRow([
          xl.TextCellValue(m['name']), xl.TextCellValue(m['category']),
          xl.DoubleCellValue(m['price']), xl.DoubleCellValue(m['cost']),
          xl.DoubleCellValue(m['profit']), xl.DoubleCellValue(m['margin']),
        ]);
      }
    }

    // Inventory
    if (selectedSections.contains('inventory_stock') && inventoryData.isNotEmpty) {
      final invSheet = excel['Inventory'];
      invSheet.appendRow([xl.TextCellValue('Ingredient'), xl.TextCellValue('Stock'), xl.TextCellValue('Unit'), xl.TextCellValue('Cost/Unit'), xl.TextCellValue('Value'), xl.TextCellValue('Status')]);
      for (final i in inventoryData) {
        invSheet.appendRow([
          xl.TextCellValue(i['name']), xl.DoubleCellValue(i['stock']),
          xl.TextCellValue(i['unit']), xl.DoubleCellValue(i['costPerUnit']),
          xl.DoubleCellValue(i['value']), xl.TextCellValue(i['status']),
        ]);
      }
    }

    // Staff
    if (selectedSections.contains('staff_summary') && staffData.isNotEmpty) {
      final staffSheet = excel['Staff'];
      staffSheet.appendRow([xl.TextCellValue('Name'), xl.TextCellValue('Role'), xl.TextCellValue('Email'), xl.TextCellValue('Salary (QAR)'), xl.TextCellValue('Status')]);
      for (final s in staffData) {
        staffSheet.appendRow([
          xl.TextCellValue(s['name']), xl.TextCellValue(s['role']),
          xl.TextCellValue(s['email']), xl.DoubleCellValue(s['salary'] as double),
          xl.TextCellValue(s['isActive'] == true ? 'Active' : 'Inactive'),
        ]);
      }
    }

    // Promotions
    if (selectedSections.contains('promotions_performance')) {
      final promoSheet = excel['Promotions'];
      promoSheet.appendRow([xl.TextCellValue('Type'), xl.TextCellValue('Name/Code'), xl.TextCellValue('Details')]);
      for (final c in (promoData['combos'] as List? ?? [])) {
        promoSheet.appendRow([xl.TextCellValue('Combo'), xl.TextCellValue(c['name']), xl.TextCellValue('QAR ${c['price']}, ${c['orders']} orders')]);
      }
      for (final s in (promoData['sales'] as List? ?? [])) {
        promoSheet.appendRow([xl.TextCellValue('Sale'), xl.TextCellValue(s['name']), xl.TextCellValue('${s['discount']} OFF')]);
      }
      for (final c in (promoData['coupons'] as List? ?? [])) {
        promoSheet.appendRow([xl.TextCellValue('Coupon'), xl.TextCellValue(c['code']), xl.TextCellValue('${c['value']} OFF, ${c['uses']} uses')]);
      }
    }

    // Expenses
    if (selectedSections.contains('expense_summary') && expenseData.isNotEmpty) {
      final expSheet = excel['Expenses'];
      expSheet.appendRow([xl.TextCellValue('Date'), xl.TextCellValue('Title'), xl.TextCellValue('Category'), xl.TextCellValue('Vendor'), xl.TextCellValue('Amount (QAR)')]);
      for (final e in expenseData) {
        expSheet.appendRow([
          xl.TextCellValue(DateFormat('yyyy-MM-dd').format(e['date'] as DateTime)),
          xl.TextCellValue(e['title'].toString()),
          xl.TextCellValue(e['category'].toString()),
          xl.TextCellValue(e['vendor'].toString()),
          xl.DoubleCellValue(e['amount'] as double),
        ]);
      }
    }

    // Remove default sheet
    excel.delete('Sheet1');

    // Save
    final bytes = excel.encode();
    if (bytes != null) {
      await FileSaver.instance.saveFile(
        name: 'Business_Report_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx',
        bytes: Uint8List.fromList(bytes),
        mimeType: MimeType.microsoftExcel,
      );
    }
  }
}
