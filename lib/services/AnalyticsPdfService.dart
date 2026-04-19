import 'package:flutter/services.dart';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/material.dart';

class AnalyticsPdfService {
  /// Generates and previews/downloads an industry-grade PDF report.
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
    double totalInventoryValue = 0,
    int lowStockCount = 0,
    int deadStockCount = 0,
    double totalWasteCost = 0,
    int wasteCount = 0,
    double totalPurchases = 0,
    int poCount = 0,
    List<dynamic>? topWastedItems,
    // New: raw orders for day-by-day breakdown & full detail table
    List<Map<String, dynamic>>? rawOrders,
    double totalTax = 0,
    double totalDiscount = 0,
    String branchLabel = 'All Branches',
  }) async {
    final pdf = pw.Document();

    pw.Font? regular;
    pw.Font? bold;
    pw.Font? arabic;
    try {
      regular = await PdfGoogleFonts.robotoRegular();
      bold = await PdfGoogleFonts.robotoBold();
      arabic = await PdfGoogleFonts.notoSansArabicRegular();
    } catch (_) {
      regular = pw.Font.helvetica();
      bold = pw.Font.helveticaBold();
    }

    Uint8List? logoBytes;
    try {
      final d = await rootBundle.load('assets/Qore.JPG');
      logoBytes = d.buffer.asUint8List();
    } catch (_) {}

    final dateFmt = DateFormat('MMM dd, yyyy');
    final timeFmt = DateFormat('dd/MM HH:mm');
    final dateRangeStr =
        '${dateFmt.format(dateRange.start)} – ${dateFmt.format(dateRange.end)}';

    // ── Day-by-day + hourly breakdown ──────────────────────────────────────
    final Map<String, double> revenueByDay = {};
    final Map<String, int> countByDay = {};
    final Map<int, int> countByHour = {};

    if (rawOrders != null) {
      for (final order in rawOrders) {
        DateTime? dt;
        final ts = order['timestamp'];
        if (ts != null) {
          try {
            dt = (ts as dynamic).toDate() as DateTime;
          } catch (_) {}
        }
        if (dt != null) {
          final dayKey = DateFormat('MMM dd').format(dt);
          final amount = (order['totalAmount'] as num?)?.toDouble() ?? 0.0;
          final status = order['status']?.toString().toLowerCase() ?? '';
          if (!['cancelled', 'refunded'].contains(status)) {
            revenueByDay[dayKey] = (revenueByDay[dayKey] ?? 0) + amount;
            countByDay[dayKey] = (countByDay[dayKey] ?? 0) + 1;
          }
          countByHour[dt.hour] = (countByHour[dt.hour] ?? 0) + 1;
        }
      }
    }

    int peakHour = 0;
    int peakHourCount = 0;
    countByHour.forEach((h, c) {
      if (c > peakHourCount) {
        peakHour = h;
        peakHourCount = c;
      }
    });

    final netRevenue = totalRevenue - totalDiscount;

    // ── Build PDF ──────────────────────────────────────────────────────────
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        theme: pw.ThemeData.withFont(base: regular, bold: bold).copyWith(
          defaultTextStyle: pw.TextStyle(
            fontFallback: arabic != null ? [arabic] : [],
          ),
        ),
        header: (ctx) => pw.Column(
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
                    pw.Text('Qore Operations Intelligence',
                        style: pw.TextStyle(
                            fontSize: 15,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.deepPurple)),
                    pw.SizedBox(height: 2),
                    pw.Text(reportTitle,
                        style: const pw.TextStyle(
                            fontSize: 10, color: PdfColors.grey800)),
                    pw.Text(dateRangeStr,
                        style: const pw.TextStyle(
                            fontSize: 9, color: PdfColors.grey700)),
                    pw.Text('Branch: $branchLabel',
                        style: const pw.TextStyle(
                            fontSize: 8, color: PdfColors.grey600)),
                    pw.Text('Order Type: ${_fmtType(orderType)}',
                        style: const pw.TextStyle(
                            fontSize: 8, color: PdfColors.grey600)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 6),
            pw.Divider(color: PdfColors.deepPurple, thickness: 1.5),
            pw.SizedBox(height: 4),
          ],
        ),
        footer: (ctx) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 8),
          child: pw.Text(
            'Page ${ctx.pageNumber}/${ctx.pagesCount} · Generated: ${DateFormat('MMM dd, yyyy HH:mm').format(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey),
          ),
        ),
        build: (ctx) {
          final w = <pw.Widget>[];

          // ── KPI Row 1: Core Sales ─────────────────────────────────────
          w.add(_kpiRow([
            _kpiCard(
                'Total Orders', totalOrders.toString(), PdfColors.blue700),
            _kpiCard('Gross Revenue',
                'QAR ${totalRevenue.toStringAsFixed(2)}', PdfColors.green700),
            _kpiCard('Avg Order Value',
                'QAR ${avgOrderValue.toStringAsFixed(2)}', PdfColors.orange700),
            _kpiCard('Net Revenue',
                'QAR ${netRevenue.toStringAsFixed(2)}', PdfColors.teal700),
          ]));
          w.add(pw.SizedBox(height: 8));

          // ── KPI Row 2: Tax / Discount / Problems ──────────────────────
          w.add(_kpiRow([
            _kpiCard('Total Tax',
                'QAR ${totalTax.toStringAsFixed(2)}', PdfColors.indigo),
            _kpiCard('Total Discounts',
                'QAR ${totalDiscount.toStringAsFixed(2)}', PdfColors.purple),
            _kpiCard('Cancelled', cancelledCount.toString(), PdfColors.red),
            _kpiCard(
                'Problem Rate',
                totalOrders > 0
                    ? '${((cancelledCount + refundedCount) / totalOrders * 100).toStringAsFixed(1)}%'
                    : '0%',
                PdfColors.amber),
          ]));
          w.add(pw.SizedBox(height: 8));

          // ── KPI Row 3: Operations ─────────────────────────────────────
          w.add(_kpiRow([
            _kpiCard(
                peakHourCount > 0
                    ? 'Peak Hour: ${peakHour.toString().padLeft(2, '0')}:00'
                    : 'Peak Hour',
                '$peakHourCount orders',
                PdfColors.deepPurple),
            _kpiCard('Low Stock', lowStockCount.toString(), PdfColors.orange),
            _kpiCard(
                'Waste Cost',
                'QAR ${totalWasteCost.toStringAsFixed(2)}',
                PdfColors.red900),
            _kpiCard(
                'PO Purchases',
                'QAR ${totalPurchases.toStringAsFixed(2)}',
                PdfColors.indigo800),
          ]));
          w.add(pw.SizedBox(height: 20));

          // ── Day-by-Day Revenue Breakdown ──────────────────────────────
          if (revenueByDay.isNotEmpty) {
            w.add(_sectionTitle('Day-by-Day Revenue Breakdown'));
            w.add(pw.SizedBox(height: 8));
            final dKeys = revenueByDay.keys.toList();
            w.add(pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                  fontSize: 9),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.deepPurple),
              cellPadding: const pw.EdgeInsets.all(6),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellAlignment: pw.Alignment.center,
              oddRowDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey50),
              headers: ['Date', 'Orders', 'Revenue (QAR)', '% of Total'],
              data: dKeys.map((day) {
                final rev = revenueByDay[day]!;
                final cnt = countByDay[day] ?? 0;
                final pct = totalRevenue > 0
                    ? (rev / totalRevenue * 100).toStringAsFixed(1)
                    : '0.0';
                return [day, cnt.toString(), rev.toStringAsFixed(2), '$pct%'];
              }).toList(),
            ));
            // Totals footer
            w.add(pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              color: PdfColors.deepPurple50,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('TOTAL',
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold, fontSize: 9)),
                  pw.Text(
                      '${countByDay.values.fold(0, (a, b) => a + b)} orders  ·  QAR ${totalRevenue.toStringAsFixed(2)}',
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 9,
                          color: PdfColors.deepPurple)),
                ],
              ),
            ));
            w.add(pw.SizedBox(height: 20));
          }

          // ── Order Type Distribution ───────────────────────────────────
          if (orderTypeDistribution.isNotEmpty) {
            w.add(_sectionTitle('Order Type Distribution'));
            w.add(pw.SizedBox(height: 8));
            final tot =
                orderTypeDistribution.values.fold<int>(0, (a, b) => a + b);
            w.add(pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                  fontSize: 9),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.deepPurple),
              cellPadding: const pw.EdgeInsets.all(6),
              cellAlignment: pw.Alignment.center,
              oddRowDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey50),
              headers: ['Order Type', 'Count', '% of Total'],
              data: orderTypeDistribution.entries.map((e) {
                final pct =
                    tot > 0 ? (e.value / tot * 100).toStringAsFixed(1) : '0.0';
                return [_fmtType(e.key), e.value.toString(), '$pct%'];
              }).toList(),
            ));
            w.add(pw.SizedBox(height: 20));
          }

          // ── Top Selling Items ─────────────────────────────────────────
          if (topItems.isNotEmpty) {
            w.add(_sectionTitle('Top Selling Items'));
            w.add(pw.SizedBox(height: 4));
            w.add(pw.Text(
              'Original price vs actual revenue (after discounts)',
              style: const pw.TextStyle(
                  fontSize: 8, color: PdfColors.grey600),
            ));
            w.add(pw.SizedBox(height: 8));
            w.add(pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                  fontSize: 8),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.deepPurple),
              cellPadding: const pw.EdgeInsets.all(5),
              cellStyle: const pw.TextStyle(fontSize: 8),
              cellAlignment: pw.Alignment.center,
              oddRowDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey50),
              headers: [
                '#',
                'Item Name',
                'Qty',
                'Original (QAR)',
                'Actual (QAR)',
                'Discount'
              ],
              data: topItems.asMap().entries.map((e) {
                final item = e.value;
                final orig =
                    (item['originalRevenue'] as num?)?.toDouble() ?? 0;
                final actual = (item['revenue'] as num?)?.toDouble() ?? 0;
                final savings = (item['savings'] as num?)?.toDouble() ?? 0;
                final hasDis = item['hasDiscount'] == true;
                return [
                  '${e.key + 1}',
                  item['name'] ?? 'Unknown',
                  item['quantity']?.toString() ?? '0',
                  orig.toStringAsFixed(2),
                  actual.toStringAsFixed(2),
                  hasDis ? '-${savings.toStringAsFixed(2)}' : '-',
                ];
              }).toList(),
            ));
            final totalSavings = topItems.fold<double>(
                0,
                (s, i) =>
                    s + ((i['savings'] as num?)?.toDouble() ?? 0));
            w.add(pw.Container(
              margin: const pw.EdgeInsets.only(top: 4),
              padding: const pw.EdgeInsets.all(6),
              decoration: pw.BoxDecoration(
                color: PdfColors.green50,
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Total Discounts Given:',
                      style: pw.TextStyle(
                          fontSize: 9, fontWeight: pw.FontWeight.bold)),
                  pw.Text('QAR ${totalSavings.toStringAsFixed(2)}',
                      style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.green700)),
                ],
              ),
            ));
            w.add(pw.SizedBox(height: 20));
          }

          // ── Full Order Detail Table ────────────────────────────────────
          if (rawOrders != null && rawOrders.isNotEmpty) {
            final cap = rawOrders.length > 150 ? 150 : rawOrders.length;
            w.add(_sectionTitle(
                'Order Details ($cap${rawOrders.length > 150 ? ' of ${rawOrders.length}' : ''} orders)'));
            w.add(pw.SizedBox(height: 8));
            w.add(pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                  fontSize: 7),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.deepPurple),
              cellPadding: const pw.EdgeInsets.all(4),
              cellStyle: const pw.TextStyle(fontSize: 7),
              cellAlignment: pw.Alignment.center,
              oddRowDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey50),
              headers: [
                '#',
                'Date/Time',
                'Customer',
                'Type',
                'Source',
                'Items',
                'Tax',
                'Disc.',
                'Total (QAR)',
                'Payment',
                'Status',
              ],
              data: rawOrders.take(150).toList().asMap().entries.map((e) {
                final o = e.value;
                DateTime? dt;
                try {
                  dt = (o['timestamp'] as dynamic).toDate() as DateTime;
                } catch (_) {}
                final total = (o['totalAmount'] as num?)?.toDouble() ?? 0.0;
                final tax = (o['tax'] as num?)?.toDouble() ??
                    (o['taxAmount'] as num?)?.toDouble() ?? 0.0;
                final disc = (o['discountAmount'] as num?)?.toDouble() ??
                    (o['discount'] as num?)?.toDouble() ?? 0.0;
                final items = (o['items'] as List?)?.length ?? 0;
                final pay = o['paymentMethod']?.toString() ??
                    o['payment_method']?.toString() ?? '-';
                final src = o['Order_source']?.toString() ??
                    o['order_source']?.toString() ?? '-';
                final type = o['Order_type']?.toString() ??
                    o['order_type']?.toString() ?? '-';
                return [
                  '${e.key + 1}',
                  dt != null ? timeFmt.format(dt) : '-',
                  o['customerName']?.toString() ?? 'Guest',
                  type,
                  src.toUpperCase(),
                  items.toString(),
                  tax.toStringAsFixed(2),
                  disc.toStringAsFixed(2),
                  total.toStringAsFixed(2),
                  pay,
                  o['status']?.toString() ?? '-',
                ];
              }).toList(),
            ));
            w.add(pw.SizedBox(height: 20));
          }

          // ── Top Riders ────────────────────────────────────────────────
          if (topRiders != null && topRiders.isNotEmpty) {
            w.add(_sectionTitle('Top Delivery Riders'));
            w.add(pw.SizedBox(height: 8));
            w.add(pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.deepPurple),
              cellPadding: const pw.EdgeInsets.all(7),
              cellAlignment: pw.Alignment.center,
              oddRowDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey50),
              headers: ['Rank', 'Rider Name', 'Deliveries'],
              data: topRiders.asMap().entries.map((e) {
                final r = e.value;
                return [
                  '#${e.key + 1}',
                  r['name'] ?? 'Unknown',
                  r['count']?.toString() ?? '0'
                ];
              }).toList(),
            ));
            w.add(pw.SizedBox(height: 20));
          }

          // ── Top Customers ─────────────────────────────────────────────
          if (topCustomers != null && topCustomers.isNotEmpty) {
            w.add(_sectionTitle('Top Customers'));
            w.add(pw.SizedBox(height: 8));
            w.add(pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.deepPurple),
              cellPadding: const pw.EdgeInsets.all(7),
              cellAlignment: pw.Alignment.center,
              oddRowDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey50),
              headers: ['Rank', 'Customer', 'Orders', 'Total Spend (QAR)'],
              data: topCustomers.asMap().entries.map((e) {
                final c = e.value;
                return [
                  '#${e.key + 1}',
                  c['name'] ?? 'Unknown',
                  c['orderCount']?.toString() ?? '0',
                  'QAR ${(c['totalSpend'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
                ];
              }).toList(),
            ));
            w.add(pw.SizedBox(height: 20));
          }

          // ── Top Wasted Items ──────────────────────────────────────────
          if (topWastedItems != null && topWastedItems.isNotEmpty) {
            w.add(_sectionTitle('Top Wasted Items'));
            w.add(pw.SizedBox(height: 8));
            w.add(pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.deepPurple),
              cellPadding: const pw.EdgeInsets.all(7),
              cellAlignment: pw.Alignment.center,
              oddRowDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey50),
              headers: ['#', 'Item Name', 'Qty', 'Est. Loss (QAR)'],
              data: topWastedItems.asMap().entries.map((e) {
                final item = e.value as Map<String, dynamic>;
                return [
                  '${e.key + 1}',
                  item['name'] ?? 'Unknown',
                  '${item['qty']} ${item['unit']}',
                  (item['loss'] as double).toStringAsFixed(2),
                ];
              }).toList(),
            ));
          }

          return w;
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat fmt) async => pdf.save(),
      name:
          '${reportTitle.replaceAll(' ', '_')}_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }

  // ── Helper widgets ────────────────────────────────────────────────────────

  static pw.Widget _kpiRow(List<pw.Widget> cards) => pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          color: PdfColors.grey100,
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
            children: cards),
      );

  static pw.Widget _kpiCard(String title, String value, PdfColor color) =>
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(value,
              style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                  color: color)),
          pw.SizedBox(height: 3),
          pw.Text(title,
              style:
                  const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
        ],
      );

  static pw.Widget _sectionTitle(String title) => pw.Container(
        padding:
            const pw.EdgeInsets.symmetric(vertical: 7, horizontal: 10),
        decoration: const pw.BoxDecoration(
          color: PdfColors.deepPurple50,
          border:
              pw.Border(left: pw.BorderSide(color: PdfColors.deepPurple, width: 4)),
        ),
        child: pw.Text(
          title,
          style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.deepPurple),
        ),
      );

  static String _fmtType(String type) {
    switch (type.toLowerCase()) {
      case 'all':
        return 'All Orders';
      case 'delivery':
        return 'Delivery';
      case 'takeaway':
      case 'take_away':
        return 'Takeaway';
      case 'pickup':
        return 'Pickup';
      case 'dine_in':
        return 'Dine In';
      default:
        return type
            .replaceAll('_', ' ')
            .split(' ')
            .map((word) =>
                word.isNotEmpty
                    ? '${word[0].toUpperCase()}${word.substring(1)}'
                    : '')
            .join(' ');
    }
  }
}
