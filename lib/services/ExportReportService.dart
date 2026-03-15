// lib/services/ExportReportService.dart
// Generates PDF and Excel reports from Firestore order data

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
    required String reportType,
    required List<String> branchIds,
    required BranchFilterService branchFilter,
    required UserScopeService userScope,
  }) async {
    // Fetch orders for the date range
    final orders = await _fetchOrders(dateRange, branchIds, userScope);
    
    if (format == 'pdf') {
      await _generatePdf(context, orders, dateRange, reportType, branchFilter, branchIds);
    } else {
      await _generateExcel(orders, dateRange, reportType, branchFilter, branchIds);
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

  // ─── Report Computation ─────────────────────────────────────
  static Map<String, dynamic> _computeStats(List<Map<String, dynamic>> orders) {
    double totalRevenue = 0;
    int completedOrders = 0;
    final Map<String, double> revenueBySource = {};
    final Map<String, double> revenueByBranch = {};
    final Map<String, int> countBySource = {};
    final Map<String, int> countByBranch = {};
    final Map<String, Map<String, dynamic>> itemSales = {};

    for (final order in orders) {
      final amount = (order['totalAmount'] as num?)?.toDouble() ?? 0;
      final status = order['status']?.toString() ?? '';
      final source = (order['source']?.toString() ?? 'app').toUpperCase();
      final branchList = order['branchIds'] as List<dynamic>? ?? [];
      final branch = branchList.isNotEmpty ? branchList.first.toString() : 'Unknown';

      if (!['cancelled', 'refunded'].contains(status.toLowerCase())) {
        totalRevenue += amount;
        completedOrders++;
      }

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

    return {
      'totalOrders': orders.length,
      'completedOrders': completedOrders,
      'totalRevenue': totalRevenue,
      'avgOrderValue': avgOrderValue,
      'revenueBySource': revenueBySource,
      'revenueByBranch': revenueByBranch,
      'countBySource': countBySource,
      'countByBranch': countByBranch,
      'itemSales': itemSales.values.toList()..sort((a, b) => (b['quantity'] as int).compareTo(a['quantity'] as int)),
    };
  }

  // ─── PDF Generation ─────────────────────────────────────────
  static Future<void> _generatePdf(
    BuildContext context,
    List<Map<String, dynamic>> orders,
    DateTimeRange dateRange,
    String reportType,
    BranchFilterService branchFilter,
    List<String> branchIds,
  ) async {
    final pdf = pw.Document();
    final stats = _computeStats(orders);
    final dateFmt = DateFormat('MMM dd, yyyy');
    final dateStr = '${dateFmt.format(dateRange.start)} – ${dateFmt.format(dateRange.end)}';
    final branchLabel = branchFilter.selectedBranchId == null
        ? 'All Branches'
        : branchFilter.getBranchName(branchFilter.selectedBranchId!);
    final reportTitle = _getReportTitle(reportType);

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
                    pw.Text(reportTitle, style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfColors.deepPurple)),
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
        build: (ctx) => _buildPdfContent(reportType, stats, orders, branchFilter),
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
      name: '${reportTitle.replaceAll(' ', '_')}_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }

  static List<pw.Widget> _buildPdfContent(
    String reportType,
    Map<String, dynamic> stats,
    List<Map<String, dynamic>> orders,
    BranchFilterService branchFilter,
  ) {
    final widgets = <pw.Widget>[];

    // Summary KPIs (always shown)
    widgets.add(pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(color: PdfColors.grey100, borderRadius: pw.BorderRadius.circular(8)),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: [
          _pdfKpi('Total Orders', '${stats['totalOrders']}', PdfColors.blue),
          _pdfKpi('Revenue', 'QAR ${(stats['totalRevenue'] as double).toStringAsFixed(0)}', PdfColors.green),
          _pdfKpi('Avg Order', 'QAR ${(stats['avgOrderValue'] as double).toStringAsFixed(0)}', PdfColors.orange),
        ],
      ),
    ));
    widgets.add(pw.SizedBox(height: 20));

    switch (reportType) {
      case 'order_details':
        widgets.addAll(_buildOrderDetailsTable(orders));
        break;
      case 'revenue_by_source':
        widgets.addAll(_buildRevenueBySource(stats));
        break;
      case 'revenue_by_branch':
        widgets.addAll(_buildRevenueByBranch(stats, branchFilter));
        break;
      case 'item_wise_sales':
        widgets.addAll(_buildItemWiseSales(stats));
        break;
      case 'sales_summary':
      default:
        widgets.addAll(_buildRevenueBySource(stats));
        widgets.add(pw.SizedBox(height: 16));
        widgets.addAll(_buildItemWiseSales(stats));
        break;
    }

    return widgets;
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
            (o['source'] ?? 'App').toString().toUpperCase(),
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

  static pw.Widget _pdfKpi(String title, String value, PdfColor color) {
    return pw.Column(children: [
      pw.Text(value, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: color)),
      pw.SizedBox(height: 4),
      pw.Text(title, style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
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

  // ─── Excel Generation ───────────────────────────────────────
  static Future<void> _generateExcel(
    List<Map<String, dynamic>> orders,
    DateTimeRange dateRange,
    String reportType,
    BranchFilterService branchFilter,
    List<String> branchIds,
  ) async {
    final excel = xl.Excel.createExcel();
    final stats = _computeStats(orders);
    final dateFmt = DateFormat('MMM dd, yyyy');
    final dateStr = '${dateFmt.format(dateRange.start)} – ${dateFmt.format(dateRange.end)}';
    final reportTitle = _getReportTitle(reportType);

    // ─── Summary Sheet ────────────────────────────────────────
    final summarySheet = excel['Summary'];
    summarySheet.appendRow([xl.TextCellValue(reportTitle)]);
    summarySheet.appendRow([xl.TextCellValue('Date Range: $dateStr')]);
    summarySheet.appendRow([xl.TextCellValue('')]);
    summarySheet.appendRow([xl.TextCellValue('Metric'), xl.TextCellValue('Value')]);
    summarySheet.appendRow([xl.TextCellValue('Total Orders'), xl.IntCellValue(stats['totalOrders'] as int)]);
    summarySheet.appendRow([xl.TextCellValue('Completed Orders'), xl.IntCellValue(stats['completedOrders'] as int)]);
    summarySheet.appendRow([xl.TextCellValue('Total Revenue (QAR)'), xl.DoubleCellValue(stats['totalRevenue'] as double)]);
    summarySheet.appendRow([xl.TextCellValue('Avg Order Value (QAR)'), xl.DoubleCellValue(stats['avgOrderValue'] as double)]);

    // ─── Orders Sheet ─────────────────────────────────────────
    if (reportType == 'order_details' || reportType == 'sales_summary') {
      final ordersSheet = excel['Orders'];
      ordersSheet.appendRow([
        xl.TextCellValue('Date'),
        xl.TextCellValue('Customer'),
        xl.TextCellValue('Source'),
        xl.TextCellValue('Type'),
        xl.TextCellValue('Items'),
        xl.TextCellValue('Total (QAR)'),
        xl.TextCellValue('Status'),
        xl.TextCellValue('Branch'),
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
          xl.TextCellValue((order['source'] ?? 'App').toString()),
          xl.TextCellValue(order['Order_type']?.toString() ?? 'delivery'),
          xl.IntCellValue((order['items'] as List?)?.length ?? 0),
          xl.DoubleCellValue((order['totalAmount'] as num?)?.toDouble() ?? 0),
          xl.TextCellValue(order['status']?.toString() ?? ''),
          xl.TextCellValue(branch),
        ]);
      }
    }

    // ─── Revenue by Source Sheet ──────────────────────────────
    if (reportType == 'revenue_by_source' || reportType == 'sales_summary') {
      final sourceSheet = excel['By Source'];
      sourceSheet.appendRow([xl.TextCellValue('Source'), xl.TextCellValue('Orders'), xl.TextCellValue('Revenue (QAR)')]);
      final revBySource = stats['revenueBySource'] as Map<String, double>;
      final countBySource = stats['countBySource'] as Map<String, int>;
      for (final entry in revBySource.entries) {
        sourceSheet.appendRow([
          xl.TextCellValue(entry.key),
          xl.IntCellValue(countBySource[entry.key] ?? 0),
          xl.DoubleCellValue(entry.value),
        ]);
      }
    }

    // ─── Revenue by Branch Sheet ─────────────────────────────
    if (reportType == 'revenue_by_branch' || reportType == 'sales_summary') {
      final branchSheet = excel['By Branch'];
      branchSheet.appendRow([xl.TextCellValue('Branch'), xl.TextCellValue('Orders'), xl.TextCellValue('Revenue (QAR)')]);
      final revByBranch = stats['revenueByBranch'] as Map<String, double>;
      final countByBranch = stats['countByBranch'] as Map<String, int>;
      for (final entry in revByBranch.entries) {
        branchSheet.appendRow([
          xl.TextCellValue(branchFilter.getBranchName(entry.key)),
          xl.IntCellValue(countByBranch[entry.key] ?? 0),
          xl.DoubleCellValue(entry.value),
        ]);
      }
    }

    // ─── Item Sales Sheet ────────────────────────────────────
    if (reportType == 'item_wise_sales' || reportType == 'sales_summary') {
      final itemSheet = excel['Item Sales'];
      itemSheet.appendRow([xl.TextCellValue('Item'), xl.TextCellValue('Qty Sold'), xl.TextCellValue('Revenue (QAR)')]);
      final items = stats['itemSales'] as List<Map<String, dynamic>>;
      for (final item in items) {
        itemSheet.appendRow([
          xl.TextCellValue(item['name'] as String),
          xl.IntCellValue(item['quantity'] as int),
          xl.DoubleCellValue(item['revenue'] as double),
        ]);
      }
    }

    // Remove default sheet
    excel.delete('Sheet1');

    // Save
    final bytes = excel.encode();
    if (bytes != null) {
      await FileSaver.instance.saveFile(
        name: '${reportTitle.replaceAll(' ', '_')}_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx',
        bytes: Uint8List.fromList(bytes),
        mimeType: MimeType.microsoftExcel,
      );
    }
  }

  static String _getReportTitle(String reportType) {
    switch (reportType) {
      case 'order_details': return 'Order Details Report';
      case 'revenue_by_source': return 'Revenue by Source';
      case 'revenue_by_branch': return 'Revenue by Branch';
      case 'item_wise_sales': return 'Item-wise Sales';
      case 'sales_summary':
      default: return 'Sales Summary Report';
    }
  }
}
