import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart' as excel_lib;
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'CsvExportService.dart';

class PurchaseOrderExportService {
  static Future<void> exportOrders(
    BuildContext context, {
    required List<Map<String, dynamic>> orders,
    required String format,
  }) async {
    if (orders.isEmpty) {
      throw Exception('There are no purchase orders to export.');
    }

    if (format == 'csv') {
      await CsvExportService.exportPurchaseOrdersFromData(context, orders);
      return;
    }

    final progressLabel = format == 'pdf'
        ? 'Generating PDF export...'
        : 'Generating Excel export...';

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: Colors.deepPurple,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(child: Text(progressLabel)),
          ],
        ),
      ),
    );

    try {
      if (format == 'excel') {
        final bytes = _buildExcel(orders);
        await FileSaver.instance.saveFile(
          name:
              'Purchase_Orders_${DateFormat('yyyyMMdd').format(DateTime.now())}',
          bytes: Uint8List.fromList(bytes),
          fileExtension: 'xlsx',
          mimeType: MimeType.microsoftExcel,
        );
      } else if (format == 'pdf') {
        final bytes = await _buildPdf(orders);
        await FileSaver.instance.saveFile(
          name:
              'Purchase_Orders_${DateFormat('yyyyMMdd').format(DateTime.now())}',
          bytes: Uint8List.fromList(bytes),
          fileExtension: 'pdf',
          mimeType: MimeType.pdf,
        );
      } else {
        throw Exception('Unsupported export format: $format');
      }

      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              format == 'pdf'
                  ? 'Purchase order PDF export is ready.'
                  : 'Purchase order Excel export is ready.',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export purchase orders: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  static List<int> _buildExcel(List<Map<String, dynamic>> orders) {
    final excel = excel_lib.Excel.createExcel();
    final summarySheet = excel['Summary'];
    final ordersSheet = excel['Purchase Orders'];

    final totalAmount = orders.fold<double>(
      0,
      (runningTotal, order) => runningTotal + _readTotalAmount(order),
    );
    final statusCounts = <String, int>{};
    for (final order in orders) {
      final status = _readStatus(order);
      statusCounts[status] = (statusCounts[status] ?? 0) + 1;
    }

    summarySheet.appendRow([
      excel_lib.TextCellValue('Purchase Order Export Summary'),
    ]);
    summarySheet.appendRow([
      excel_lib.TextCellValue('Generated At'),
      excel_lib.TextCellValue(
          DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())),
    ]);
    summarySheet.appendRow([
      excel_lib.TextCellValue('Total Orders'),
      excel_lib.IntCellValue(orders.length),
    ]);
    summarySheet.appendRow([
      excel_lib.TextCellValue('Total Value (QAR)'),
      excel_lib.DoubleCellValue(totalAmount),
    ]);
    for (final entry in statusCounts.entries) {
      summarySheet.appendRow([
        excel_lib.TextCellValue('Status: ${entry.key}'),
        excel_lib.IntCellValue(entry.value),
      ]);
    }

    ordersSheet.appendRow([
      excel_lib.TextCellValue('PO Number'),
      excel_lib.TextCellValue('Order Date'),
      excel_lib.TextCellValue('Supplier'),
      excel_lib.TextCellValue('Status'),
      excel_lib.TextCellValue('Items'),
      excel_lib.TextCellValue('Total Amount (QAR)'),
      excel_lib.TextCellValue('Expected Delivery'),
      excel_lib.TextCellValue('Received Date'),
      excel_lib.TextCellValue('Created By'),
      excel_lib.TextCellValue('Notes'),
    ]);

    for (final order in orders) {
      ordersSheet.appendRow([
        excel_lib.TextCellValue((order['poNumber'] ?? '-').toString()),
        excel_lib.TextCellValue(_formatDate(_orderDate(order))),
        excel_lib.TextCellValue((order['supplierName'] ?? '-').toString()),
        excel_lib.TextCellValue(_readStatus(order)),
        excel_lib.IntCellValue((order['lineItems'] as List?)?.length ?? 0),
        excel_lib.DoubleCellValue(_readTotalAmount(order)),
        excel_lib.TextCellValue(
          _formatDate((order['expectedDeliveryDate'] as Timestamp?)?.toDate()),
        ),
        excel_lib.TextCellValue(
          _formatDate((order['receivedDate'] as Timestamp?)?.toDate()),
        ),
        excel_lib.TextCellValue((order['createdBy'] ?? '-').toString()),
        excel_lib.TextCellValue((order['notes'] ?? '').toString()),
      ]);
    }

    excel.delete('Sheet1');
    final bytes = excel.encode();
    if (bytes == null) {
      throw Exception('Failed to generate Excel export.');
    }
    return bytes;
  }

  static Future<List<int>> _buildPdf(List<Map<String, dynamic>> orders) async {
    final pdf = pw.Document();
    final totalAmount = orders.fold<double>(
      0,
      (runningTotal, order) => runningTotal + _readTotalAmount(order),
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => [
          pw.Text(
            'Purchase Orders Export',
            style: pw.TextStyle(
              fontSize: 20,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            'Generated ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            children: [
              _pdfSummaryCard('Orders', '${orders.length}'),
              pw.SizedBox(width: 10),
              _pdfSummaryCard(
                  'Total Value', 'QAR ${totalAmount.toStringAsFixed(2)}'),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headers: const [
              'PO Number',
              'Order Date',
              'Supplier',
              'Status',
              'Items',
              'Total (QAR)',
              'Expected Delivery',
              'Received Date',
            ],
            headerStyle: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration: const pw.BoxDecoration(
              color: PdfColors.deepPurple,
            ),
            cellStyle: const pw.TextStyle(
              fontSize: 8,
              color: PdfColors.black,
            ),
            cellAlignments: const {
              4: pw.Alignment.centerRight,
              5: pw.Alignment.centerRight,
            },
            data: orders
                .map(
                  (order) => [
                    (order['poNumber'] ?? '-').toString(),
                    _formatDate(_orderDate(order)),
                    (order['supplierName'] ?? '-').toString(),
                    _readStatus(order),
                    '${(order['lineItems'] as List?)?.length ?? 0}',
                    _readTotalAmount(order).toStringAsFixed(2),
                    _formatDate(
                      (order['expectedDeliveryDate'] as Timestamp?)?.toDate(),
                    ),
                    _formatDate(
                      (order['receivedDate'] as Timestamp?)?.toDate(),
                    ),
                  ],
                )
                .toList(),
            cellPadding: const pw.EdgeInsets.symmetric(
              horizontal: 6,
              vertical: 5,
            ),
            border: pw.TableBorder.all(
              color: PdfColors.grey300,
              width: 0.4,
            ),
            rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
            oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
          ),
        ],
      ),
    );

    return pdf.save();
  }

  static pw.Widget _pdfSummaryCard(String label, String value) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  static DateTime? _orderDate(Map<String, dynamic> order) {
    return (order['orderDate'] as Timestamp?)?.toDate() ??
        (order['createdAt'] as Timestamp?)?.toDate();
  }

  static String _formatDate(DateTime? date) {
    if (date == null) {
      return '-';
    }
    return DateFormat('yyyy-MM-dd').format(date);
  }

  static String _readStatus(Map<String, dynamic> order) {
    final status = (order['status'] ?? 'unknown').toString().trim();
    return status.isEmpty ? 'unknown' : status;
  }

  static double _readTotalAmount(Map<String, dynamic> order) {
    return ((order['totalAmount'] as num?) ?? 0).toDouble();
  }
}
