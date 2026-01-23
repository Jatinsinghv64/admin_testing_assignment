import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/material.dart';

class AnalyticsPdfService {
  /// Generates and previews/downloads a PDF report
  static Future<void> generateReport({
    required BuildContext context,
    required String reportTitle,
    required DateTimeRange dateRange,
    required String orderType,
    required int totalOrders,
    required double totalRevenue,
    required double avgOrderValue,
    required List<Map<String, dynamic>> topItems,
    required Map<String, int> orderTypeDistribution,
    int cancelledCount = 0,
    int refundedCount = 0,
    List<Map<String, dynamic>>? topRiders,
    List<Map<String, dynamic>>? topCustomers,
  }) async {
    final pdf = pw.Document();

    // Load logo
    Uint8List? logoBytes;
    try {
      final logoData = await rootBundle.load('assets/mitranlogo.jpg');
      logoBytes = logoData.buffer.asUint8List();
    } catch (e) {
      // Logo not found, continue without it
    }

    final dateFormatter = DateFormat('MMM dd, yyyy');
    final dateRangeStr =
        '${dateFormatter.format(dateRange.start)} - ${dateFormatter.format(dateRange.end)}';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        header: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  if (logoBytes != null)
                    pw.Image(pw.MemoryImage(logoBytes), width: 60, height: 60)
                  else
                    pw.Container(width: 60),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        reportTitle,
                        style: pw.TextStyle(
                          fontSize: 24,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.deepPurple,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        dateRangeStr,
                        style: const pw.TextStyle(
                          fontSize: 12,
                          color: PdfColors.grey700,
                        ),
                      ),
                      pw.Text(
                        'Order Type: ${_formatOrderType(orderType)}',
                        style: const pw.TextStyle(
                          fontSize: 10,
                          color: PdfColors.grey600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              pw.Divider(color: PdfColors.deepPurple, thickness: 2),
              pw.SizedBox(height: 10),
            ],
          );
        },
        footer: (pw.Context context) {
          return pw.Container(
            alignment: pw.Alignment.centerRight,
            margin: const pw.EdgeInsets.only(top: 10),
            child: pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount} | Generated on ${DateFormat('MMM dd, yyyy HH:mm').format(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey),
            ),
          );
        },
        build: (pw.Context context) => [
          // KPI Summary Section - First Row
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                _buildPdfKpiCard(
                    'Total Orders', totalOrders.toString(), PdfColors.blue),
                _buildPdfKpiCard('Revenue',
                    'QAR ${totalRevenue.toStringAsFixed(0)}', PdfColors.green),
                _buildPdfKpiCard(
                    'Avg Order',
                    'QAR ${avgOrderValue.toStringAsFixed(0)}',
                    PdfColors.orange),
              ],
            ),
          ),
          pw.SizedBox(height: 12),
          // KPI Summary Section - Second Row (Cancelled/Refunded)
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                _buildPdfKpiCard(
                    'Cancelled', cancelledCount.toString(), PdfColors.red),
                _buildPdfKpiCard(
                    'Refunded', refundedCount.toString(), PdfColors.purple),
                _buildPdfKpiCard(
                    'Problem Rate',
                    totalOrders > 0
                        ? '${((cancelledCount + refundedCount) / totalOrders * 100).toStringAsFixed(1)}%'
                        : '0%',
                    PdfColors.amber),
              ],
            ),
          ),
          pw.SizedBox(height: 24),

          // Order Type Distribution
          if (orderTypeDistribution.isNotEmpty) ...[
            _buildPdfSectionTitle('Order Type Distribution'),
            pw.SizedBox(height: 8),
            pw.Table.fromTextArray(
              headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.deepPurple),
              cellPadding: const pw.EdgeInsets.all(8),
              headerAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.center,
                2: pw.Alignment.center,
              },
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.center,
                2: pw.Alignment.center,
              },
              headers: ['Order Type', 'Count', 'Percentage'],
              data: orderTypeDistribution.entries.map((e) {
                final total =
                    orderTypeDistribution.values.fold<int>(0, (a, b) => a + b);
                final percentage = total > 0
                    ? (e.value / total * 100).toStringAsFixed(1)
                    : '0.0';
                return [
                  _formatOrderType(e.key),
                  e.value.toString(),
                  '$percentage%'
                ];
              }).toList(),
            ),
            pw.SizedBox(height: 24),
          ],

          // Top Selling Items
          if (topItems.isNotEmpty) ...[
            _buildPdfSectionTitle('Top Selling Items'),
            pw.SizedBox(height: 8),
            pw.Table.fromTextArray(
              headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.deepPurple),
              cellPadding: const pw.EdgeInsets.all(8),
              headerAlignments: {
                0: pw.Alignment.center,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.center,
                3: pw.Alignment.center,
              },
              cellAlignments: {
                0: pw.Alignment.center,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.center,
                3: pw.Alignment.center,
              },
              headers: ['Rank', 'Item Name', 'Quantity Sold', 'Revenue'],
              data: topItems.asMap().entries.map((e) {
                final item = e.value;
                return [
                  '#${e.key + 1}',
                  item['name'] ?? 'Unknown',
                  item['quantity']?.toString() ?? '0',
                  'QAR ${(item['revenue'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
                ];
              }).toList(),
            ),
            pw.SizedBox(height: 24),
          ],

          // Top Delivery Riders
          if (topRiders != null && topRiders.isNotEmpty) ...[
            _buildPdfSectionTitle('Top Delivery Riders'),
            pw.SizedBox(height: 8),
            pw.Table.fromTextArray(
              headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.deepPurple),
              cellPadding: const pw.EdgeInsets.all(8),
              headerAlignments: {
                0: pw.Alignment.center,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.center,
              },
              cellAlignments: {
                0: pw.Alignment.center,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.center,
              },
              headers: ['Rank', 'Rider Name', 'Deliveries'],
              data: topRiders.asMap().entries.map((e) {
                final rider = e.value;
                return [
                  '#${e.key + 1}',
                  rider['name'] ?? 'Unknown',
                  rider['count']?.toString() ?? '0',
                ];
              }).toList(),
            ),
            pw.SizedBox(height: 24),
          ],

          // Top Customers
          if (topCustomers != null && topCustomers.isNotEmpty) ...[
            _buildPdfSectionTitle('Top Customers'),
            pw.SizedBox(height: 8),
            pw.Table.fromTextArray(
              headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.deepPurple),
              cellPadding: const pw.EdgeInsets.all(8),
              headerAlignments: {
                0: pw.Alignment.center,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.center,
                3: pw.Alignment.center,
              },
              cellAlignments: {
                0: pw.Alignment.center,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.center,
                3: pw.Alignment.center,
              },
              headers: ['Rank', 'Customer', 'Orders', 'Total Spend'],
              data: topCustomers.asMap().entries.map((e) {
                final customer = e.value;
                return [
                  '#${e.key + 1}',
                  customer['name'] ?? 'Unknown',
                  customer['orderCount']?.toString() ?? '0',
                  'QAR ${(customer['totalSpend'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
                ];
              }).toList(),
            ),
          ],
        ],
      ),
    );

    // Show print/download preview
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name:
          '${reportTitle.replaceAll(' ', '_')}_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }

  static pw.Widget _buildPdfKpiCard(
      String title, String value, PdfColor color) {
    return pw.Column(
      children: [
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 20,
            fontWeight: pw.FontWeight.bold,
            color: color,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          title,
          style: const pw.TextStyle(
            fontSize: 12,
            color: PdfColors.grey700,
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildPdfSectionTitle(String title) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: const pw.BoxDecoration(
        color: PdfColors.deepPurple50,
        border: pw.Border(
            left: pw.BorderSide(color: PdfColors.deepPurple, width: 4)),
      ),
      child: pw.Text(
        title,
        style: pw.TextStyle(
          fontSize: 16,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.deepPurple,
        ),
      ),
    );
  }

  static String _formatOrderType(String type) {
    switch (type.toLowerCase()) {
      case 'all':
        return 'All Orders';
      case 'delivery':
        return 'Delivery';
      case 'takeaway':
        return 'Takeaway';
      case 'pickup':
        return 'Pickup';
      case 'dine_in':
        return 'Dine In';
      default:
        return type;
    }
  }
}
