import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'TimeUtils.dart';

class PrintingService {
  // Optimization: Cache font and branch data to prevent reloading
  static ByteData? _cachedArabicFont;
  static final Map<String, Map<String, dynamic>> _branchCache = {};

  static Future<void> _loadFont() async {
    if (_cachedArabicFont == null) {
      try {
        _cachedArabicFont = await rootBundle.load("assets/fonts/NotoSansArabic-Regular.ttf");
      } catch (e) {
        debugPrint("Error pre-loading font: $e");
      }
    }
  }

  static String _toArabicNumerals(String number) {
    const en = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '.'];
    const ar = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩', '.'];
    for (int i = 0; i < en.length; i++) {
      number = number.replaceAll(en[i], ar[i]);
    }
    return number;
  }

  static Future<void> printReceipt(BuildContext context, DocumentSnapshot orderDoc) async {
    try {
      await _loadFont();

      // Fallback if font fails to load
      final fontData = _cachedArabicFont ?? await rootBundle.load("assets/fonts/NotoSansArabic-Regular.ttf");
      final pw.Font arabicFont = pw.Font.ttf(fontData);

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async {
          final Map<String, dynamic> order = Map<String, dynamic>.from(orderDoc.data() as Map);

          // --- Prepare Items ---
          final List<dynamic> rawItems = (order['items'] ?? []) as List<dynamic>;
          final List<Map<String, dynamic>> items = rawItems.map((e) {
            final m = Map<String, dynamic>.from(e as Map);
            return {
              'name': (m['name'] ?? 'Item').toString(),
              'name_ar': (m['name_ar'] ?? '').toString(),
              'qty': int.tryParse((m['quantity'] ?? m['qty'] ?? '1').toString()) ?? 1,
              'price': double.tryParse((m['price'] ?? m['unitPrice'] ?? m['amount'] ?? '0').toString()) ?? 0.0,
            };
          }).toList();

          // --- Prepare Totals ---
          final double subtotal = (order['subtotal'] as num?)?.toDouble() ?? 0.0;
          final double discount = (order['discountAmount'] as num?)?.toDouble() ?? 0.0;
          final double totalAmount = (order['totalAmount'] as num?)?.toDouble() ?? 0.0;
          final double riderPaymentAmount = (order['riderPaymentAmount'] as num?)?.toDouble() ?? 0.0;

          // Fallback subtotal calculation
          final double calculatedSubtotal = items.fold(0, (sum, item) => sum + (item['price'] * item['qty']));
          final double finalSubtotal = subtotal > 0 ? subtotal : calculatedSubtotal;

          // --- Dates ---
          final DateTime? rawDate = (order['timestamp'] as Timestamp?)?.toDate();
          final DateTime? orderDate = rawDate != null ? TimeUtils.getRestaurantTime(rawDate) : null;

          final String formattedDate = orderDate != null ? DateFormat('dd/MM/yyyy').format(orderDate) : "N/A";
          final String formattedTime = orderDate != null ? DateFormat('hh:mm a').format(orderDate) : "N/A";

          // --- Branch Details ---
          final List<dynamic> branchIds = order['branchIds'] ?? [];
          String primaryBranchId = branchIds.isNotEmpty ? branchIds.first.toString() : '';

          String branchName = "Restaurant Name";
          String branchNameAr = "اسم المطعم";
          String branchPhone = "";
          String branchAddress = "";
          String branchAddressAr = "";
          // Note: If you have a logo, you can load it here similarly to the font

          if (primaryBranchId.isNotEmpty) {
            if (!_branchCache.containsKey(primaryBranchId)) {
              final branchSnap = await FirebaseFirestore.instance.collection('Branch').doc(primaryBranchId).get();
              if (branchSnap.exists) {
                _branchCache[primaryBranchId] = branchSnap.data()!;
              }
            }

            final branchData = _branchCache[primaryBranchId];
            if (branchData != null) {
              branchName = branchData['name'] ?? branchName;
              branchNameAr = branchData['name_ar'] ?? branchNameAr;
              branchPhone = branchData['phone'] ?? "";

              final addressMap = branchData['address'] as Map<String, dynamic>? ?? {};

              final street = addressMap['street'] ?? '';
              final city = addressMap['city'] ?? '';
              branchAddress = (street.isNotEmpty && city.isNotEmpty) ? "$street, $city" : (street + city);

              final streetAr = addressMap['street_ar'] ?? street;
              final cityAr = addressMap['city_ar'] ?? city;
              branchAddressAr = (streetAr.isNotEmpty && cityAr.isNotEmpty) ? "$streetAr, $cityAr" : (streetAr + cityAr);
            }
          }

          // --- Order Type & Customer ---
          final String rawOrderType = (order['Order_type'] ?? 'Unknown').toString();
          final String displayOrderType = rawOrderType.replaceAll('_', ' ').toUpperCase();
          final Map<String, String> orderTypeTranslations = {
            'DELIVERY': 'توصيل',
            'TAKEAWAY': 'سفري',
            'PICKUP': 'يستلم',
            'DINE IN': 'تناول الطعام',
          };
          final String displayOrderTypeAr = orderTypeTranslations[displayOrderType] ?? displayOrderType;
          final String dailyOrderNumber = order['dailyOrderNumber']?.toString() ?? orderDoc.id.substring(0, 6).toUpperCase();

          final String customerName = (order['customerName'] ?? 'Walk-in Customer').toString();
          final String carPlate = (order['carPlateNumber'] ?? '').toString();

          final String customerDisplay = rawOrderType.toLowerCase() == 'takeaway' && carPlate.isNotEmpty
              ? 'Car Plate: $carPlate'
              : customerName;

          final String customerDisplayAr = rawOrderType.toLowerCase() == 'takeaway' && carPlate.isNotEmpty
              ? 'لوحة السيارة: $carPlate'
              : (customerName == 'Walk-in Customer' ? 'عميل مباشر' : customerName);


          final pdf = pw.Document();

          // --- Styles ---
          const pw.TextStyle regular = pw.TextStyle(fontSize: 9);
          final pw.TextStyle bold = pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold);
          final pw.TextStyle small = pw.TextStyle(fontSize: 8, color: PdfColors.grey600);
          final pw.TextStyle heading = pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold);
          final pw.TextStyle totalStyle = pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold);

          final pw.TextStyle arRegular = pw.TextStyle(font: arabicFont, fontSize: 9);
          final pw.TextStyle arBold = pw.TextStyle(font: arabicFont, fontSize: 9, fontWeight: pw.FontWeight.bold);
          final pw.TextStyle arHeading = pw.TextStyle(font: arabicFont, fontSize: 16, fontWeight: pw.FontWeight.bold);
          final pw.TextStyle arTotal = pw.TextStyle(font: arabicFont, fontSize: 12, fontWeight: pw.FontWeight.bold);

          // --- Helpers ---
          pw.Widget buildBilingualLabel(String en, String ar,
              {required pw.TextStyle enStyle,
                required pw.TextStyle arStyle,
                pw.CrossAxisAlignment alignment = pw.CrossAxisAlignment.start}) {
            return pw.Column(
              crossAxisAlignment: alignment,
              children: [
                pw.Text(en, style: enStyle),
                if (ar.isNotEmpty)
                  pw.Text(ar, style: arStyle, textDirection: pw.TextDirection.rtl),
              ],
            );
          }

          pw.Widget buildSummaryRow(String en, String ar, double amount,
              {required pw.TextStyle enLabelStyle,
                required pw.TextStyle arLabelStyle,
                required pw.TextStyle enValueStyle,
                required pw.TextStyle arValueStyle,
                PdfColor? valueColor,
                String prefix = ''}) {

            final finalEnValueStyle = valueColor != null ? enValueStyle.copyWith(color: valueColor) : enValueStyle;
            final finalArValueStyle = valueColor != null ? arValueStyle.copyWith(color: valueColor) : arValueStyle;

            final String enPrice = '$prefix${amount.toStringAsFixed(2)}';
            final String arPrice = '$prefix${_toArabicNumerals(amount.toStringAsFixed(2))}';

            return pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(en, style: enLabelStyle),
                      pw.Text(ar, style: arLabelStyle, textDirection: pw.TextDirection.rtl),
                    ]),
                pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('QAR $enPrice', style: finalEnValueStyle, textAlign: pw.TextAlign.right),
                      pw.Text('ر.ق $arPrice', style: finalArValueStyle, textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.right),
                    ]),
              ],
            );
          }

          pdf.addPage(
            pw.Page(
              pageFormat: PdfPageFormat.roll80,
              build: (_) {
                return pw.Container(
                  width: format.availableWidth,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      // 1. Branch Header
                      pw.Center(child: pw.Text(branchName, style: heading)),
                      pw.Center(child: pw.Text(branchNameAr, style: arHeading, textDirection: pw.TextDirection.rtl)),

                      if (branchAddress.isNotEmpty)
                        pw.Center(child: pw.Text(branchAddress, style: regular, textAlign: pw.TextAlign.center)),
                      if (branchAddressAr.isNotEmpty)
                        pw.Center(child: pw.Text(branchAddressAr, style: arRegular, textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),

                      if (branchPhone.isNotEmpty)
                        pw.Center(child: pw.Text("Tel: $branchPhone", style: regular)),

                      pw.SizedBox(height: 5),
                      pw.Center(child: pw.Text("TAX INVOICE", style: bold.copyWith(fontSize: 10))),
                      pw.Center(child: pw.Text("فاتورة ضريبية", style: arBold.copyWith(fontSize: 10), textDirection: pw.TextDirection.rtl)),

                      pw.SizedBox(height: 10),

                      // 2. Order Metadata
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          buildBilingualLabel('Order #: $dailyOrderNumber', 'رقم الطلب: $dailyOrderNumber',
                              enStyle: regular, arStyle: arRegular),
                          buildBilingualLabel('Type: $displayOrderType', 'نوع: $displayOrderTypeAr',
                              enStyle: bold, arStyle: arBold, alignment: pw.CrossAxisAlignment.end),
                        ],
                      ),
                      pw.SizedBox(height: 3),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          buildBilingualLabel('Date: $formattedDate', 'تاريخ: $formattedDate',
                              enStyle: regular, arStyle: arRegular),
                          buildBilingualLabel('Time: $formattedTime', 'زمن: $formattedTime',
                              enStyle: regular, arStyle: arRegular, alignment: pw.CrossAxisAlignment.end),
                        ],
                      ),

                      pw.SizedBox(height: 3),
                      buildBilingualLabel('Customer: $customerDisplay', 'عميل: $customerDisplayAr',
                          enStyle: regular, arStyle: arRegular),

                      pw.SizedBox(height: 10),

                      // 3. Items Table (Reverted to Table for alignment)
                      pw.Table(
                        columnWidths: {
                          0: const pw.FlexColumnWidth(5),
                          1: const pw.FlexColumnWidth(1.5),
                          2: const pw.FlexColumnWidth(2.5),
                        },
                        border: const pw.TableBorder(
                          top: pw.BorderSide(color: PdfColors.black, width: 1),
                          bottom: pw.BorderSide(color: PdfColors.black, width: 1),
                          horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
                        ),
                        children: [
                          // Header
                          pw.TableRow(
                            children: [
                              pw.Padding(
                                  padding: const pw.EdgeInsets.symmetric(vertical: 4),
                                  child: buildBilingualLabel('ITEM', 'بند', enStyle: bold, arStyle: arBold)),
                              pw.Padding(
                                  padding: const pw.EdgeInsets.symmetric(vertical: 4),
                                  child: buildBilingualLabel('QTY', 'كمية', enStyle: bold, arStyle: arBold, alignment: pw.CrossAxisAlignment.center)),
                              pw.Padding(
                                  padding: const pw.EdgeInsets.symmetric(vertical: 4),
                                  child: buildBilingualLabel('TOTAL', 'المجموع', enStyle: bold, arStyle: arBold, alignment: pw.CrossAxisAlignment.end)),
                            ],
                          ),
                          // Rows
                          ...items.map((item) {
                            return pw.TableRow(
                              children: [
                                pw.Padding(
                                    padding: const pw.EdgeInsets.symmetric(vertical: 3),
                                    child: buildBilingualLabel(item['name'], item['name_ar'], enStyle: regular, arStyle: arRegular)),
                                pw.Padding(
                                    padding: const pw.EdgeInsets.symmetric(vertical: 3),
                                    child: pw.Text(item['qty'].toString(), style: regular, textAlign: pw.TextAlign.center)),
                                pw.Padding(
                                  padding: const pw.EdgeInsets.symmetric(vertical: 3),
                                  child: pw.Column(
                                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                                    children: [
                                      pw.Text('QAR ${(item['price'] * item['qty']).toStringAsFixed(2)}', style: regular, textAlign: pw.TextAlign.right),
                                      pw.Text('ر.ق ${_toArabicNumerals((item['price'] * item['qty']).toStringAsFixed(2))}', style: arRegular, textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.right),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          }),
                        ],
                      ),

                      pw.SizedBox(height: 10),

                      // 4. Summary Section
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.end,
                        children: [
                          pw.Expanded(
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                              children: [
                                buildSummaryRow('Subtotal:', 'المجموع الفرعي:', finalSubtotal,
                                    enLabelStyle: regular, arLabelStyle: arRegular,
                                    enValueStyle: bold, arValueStyle: arBold),

                                if (rawOrderType.toLowerCase() == 'delivery' && riderPaymentAmount > 0)
                                  buildSummaryRow('Rider Payment:', 'أجرة المندوب:', riderPaymentAmount,
                                      enLabelStyle: regular, arLabelStyle: arRegular,
                                      enValueStyle: bold, arValueStyle: arBold,
                                      valueColor: PdfColors.blueGrey),

                                if (discount > 0)
                                  buildSummaryRow('Discount:', 'خصم:', discount,
                                      enLabelStyle: regular, arLabelStyle: arRegular,
                                      enValueStyle: bold, arValueStyle: arBold,
                                      valueColor: PdfColors.green, prefix: '- '),

                                pw.Divider(height: 5, color: PdfColors.grey),

                                buildSummaryRow('TOTAL:', 'المجموع الكلي:', totalAmount,
                                    enLabelStyle: totalStyle, arLabelStyle: arTotal,
                                    enValueStyle: totalStyle, arValueStyle: arTotal),
                              ],
                            ),
                          ),
                        ],
                      ),

                      pw.SizedBox(height: 20),
                      pw.Divider(thickness: 1),
                      pw.SizedBox(height: 5),
                      pw.Center(child: pw.Text("Thank You For Your Order!", style: bold)),
                      pw.Center(child: pw.Text("شكرا لطلبك!", style: arBold, textDirection: pw.TextDirection.rtl)),
                      pw.SizedBox(height: 5),
                      pw.Center(child: pw.Text("Invoice ID: ${orderDoc.id}", style: small)),
                    ],
                  ),
                );
              },
            ),
          );
          return pdf.save();
        },
      );
    } catch (e, st) {
      debugPrint("Error while printing: $e\n$st");
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to print: $e")));
      }
    }
  }
}