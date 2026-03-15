import 'dart:io';
import 'package:csv/csv.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class CsvExportService {
  /// General wrapper to generate CSV, save it, and trigger a share dialog or mailto
  static Future<void> _exportAndShare(BuildContext context, String fileName,
      List<List<dynamic>> csvData) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(
          child: CircularProgressIndicator(color: Colors.deepPurple),
        ),
      );

      final String csvString = const ListToCsvConverter().convert(csvData);

      final directory = await getApplicationDocumentsDirectory();
      final path = '${directory.path}/$fileName';
      final file = File(path);
      await file.writeAsString(csvString);

      if (context.mounted) Navigator.pop(context); // close dialog

      // We use share_plus as it natively triggers the OS share sheet which supports email attachments
      // much better than a raw mailto URI which often drops attachments on iOS/Android.
      await Share.shareXFiles(
        [XFile(path)],
        text: 'Attached is the requested CSV export: $fileName',
        subject: 'Zayka Analytics Export',
      );
    } catch (e) {
      if (context.mounted) Navigator.pop(context);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export CSV: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  static Future<void> exportWasteHistory(BuildContext context,
      List<String> branchIds, DateTimeRange dateRange) async {
    final snapshot = await FirebaseFirestore.instance
        .collectionGroup('waste_entries')
        .where('branchIds',
            arrayContainsAny:
                branchIds.isEmpty ? ['dummy'] : branchIds.take(10).toList())
        .where('wasteDate',
            isGreaterThanOrEqualTo: Timestamp.fromDate(dateRange.start))
        .where('wasteDate',
            isLessThanOrEqualTo: Timestamp.fromDate(dateRange.end))
        .orderBy('wasteDate', descending: true)
        .get();

    final List<List<dynamic>> rows = [
      [
        'Date',
        'Item Name',
        'Item Type',
        'Quantity',
        'Unit',
        'Estimated Loss (QAR)',
        'Reason',
        'Recorded By',
        'Notes'
      ]
    ];

    for (var doc in snapshot.docs) {
      final data = doc.data();
      final date = (data['wasteDate'] as Timestamp?)?.toDate();
      rows.add([
        date != null ? DateFormat('yyyy-MM-dd HH:mm').format(date) : '-',
        data['itemName'] ?? '-',
        data['itemType'] ?? '-',
        data['quantity'] ?? 0,
        data['unit'] ?? '-',
        (data['estimatedLoss'] ?? 0).toDouble(),
        data['reason'] ?? '-',
        data['recordedBy'] ?? '-',
        data['notes'] ?? ''
      ]);
    }

    final filename =
        'Waste_History_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv';
    await _exportAndShare(context, filename, rows);
  }

  static Future<void> exportPurchaseOrders(BuildContext context,
      List<String> branchIds, DateTimeRange dateRange) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('purchase_orders')
        .where('branchIds',
            arrayContainsAny:
                branchIds.isEmpty ? ['dummy'] : branchIds.take(10).toList())
        .where('orderDate',
            isGreaterThanOrEqualTo: Timestamp.fromDate(dateRange.start))
        .where('orderDate',
            isLessThanOrEqualTo: Timestamp.fromDate(dateRange.end))
        .orderBy('orderDate', descending: true)
        .get();

    final List<List<dynamic>> rows = [
      [
        'PO Number',
        'Order Date',
        'Supplier',
        'Status',
        'Total Amount (QAR)',
        'Expected Delivery',
        'Received Date'
      ]
    ];

    for (var doc in snapshot.docs) {
      final data = doc.data();
      final orderDate = (data['orderDate'] as Timestamp?)?.toDate();
      final expDelDate = (data['expectedDeliveryDate'] as Timestamp?)?.toDate();
      final recDate = (data['receivedDate'] as Timestamp?)?.toDate();

      rows.add([
        data['poNumber'] ?? '-',
        orderDate != null ? DateFormat('yyyy-MM-dd').format(orderDate) : '-',
        data['supplierName'] ?? '-',
        data['status'] ?? '-',
        (data['totalAmount'] ?? 0).toDouble(),
        expDelDate != null ? DateFormat('yyyy-MM-dd').format(expDelDate) : '-',
        recDate != null ? DateFormat('yyyy-MM-dd').format(recDate) : '-',
      ]);
    }

    final filename =
        'Purchase_Orders_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv';
    await _exportAndShare(context, filename, rows);
  }

  static Future<void> exportStockMovements(BuildContext context,
      List<String> branchIds, DateTimeRange dateRange) async {
    final snapshot = await FirebaseFirestore.instance
        .collectionGroup('stock_movements')
        .where('branchIds',
            arrayContainsAny:
                branchIds.isEmpty ? ['dummy'] : branchIds.take(10).toList())
        .where('createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(dateRange.start))
        .where('createdAt',
            isLessThanOrEqualTo: Timestamp.fromDate(dateRange.end))
        .orderBy('createdAt', descending: true)
        .get();

    final List<List<dynamic>> rows = [
      [
        'Date',
        'Movement Type',
        'Item Name',
        'Quantity Change',
        'Balance Before',
        'Balance After',
        'Reason',
        'Recorded By'
      ]
    ];

    for (var doc in snapshot.docs) {
      final data = doc.data();
      final date = (data['createdAt'] as Timestamp?)?.toDate();

      rows.add([
        date != null ? DateFormat('yyyy-MM-dd HH:mm').format(date) : '-',
        data['movementType'] ?? '-',
        data['ingredientName'] ?? '-',
        (data['quantity'] ?? 0).toDouble(),
        (data['balanceBefore'] ?? 0).toDouble(),
        (data['balanceAfter'] ?? 0).toDouble(),
        data['reason'] ?? data['warning'] ?? '-',
        data['recordedBy'] ?? '-',
      ]);
    }

    final filename =
        'Stock_Movements_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv';
    await _exportAndShare(context, filename, rows);
  }
}
