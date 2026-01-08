import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'TimeUtils.dart';
import '../constants.dart';

/// Helper class to track cache expiration for branch data
class _CachedBranch {
  final Map<String, dynamic> data;
  final DateTime cachedAt;

  _CachedBranch(this.data) : cachedAt = DateTime.now();

  bool get isExpired => 
    DateTime.now().difference(cachedAt) > AppConstants.branchCacheExpiration;
}

class PrintingService {
  static ByteData? _cachedArabicFont;
  static ByteData? _cachedLogo;
  static bool _logoLoadAttempted = false; // Track if we tried loading the logo
  
  // Cache with expiration tracking
  static final Map<String, _CachedBranch> _branchCache = {};

  static Future<void> _loadAssets() async {
    // 1. Load Font
    if (_cachedArabicFont == null) {
      try {
        _cachedArabicFont = await rootBundle.load("assets/fonts/NotoSansArabic-Regular.ttf");
      } catch (e) {
        debugPrint("⚠️ Error loading font: $e");
      }
    }
    // 2. Load Logo (only attempt once to avoid repeated errors)
    if (_cachedLogo == null && !_logoLoadAttempted) {
      _logoLoadAttempted = true;
      try {
        // Ensure this file exists in your assets folder and pubspec.yaml
        _cachedLogo = await rootBundle.load("assets/mitranlogo.jpg");
      } catch (e) {
        debugPrint("⚠️ Logo asset not found - receipts will print without logo. "
            "Add 'assets/mitranlogo.jpg' to pubspec.yaml to fix.");
      }
    }
  }

  /// Clear expired branch cache entries
  static void _clearExpiredCache() {
    final now = DateTime.now();
    _branchCache.removeWhere((key, cached) => 
      now.difference(cached.cachedAt) > AppConstants.branchCacheExpiration
    );
  }

  /// Force clear the branch cache (useful when branch data is updated)
  static void clearBranchCache([String? branchId]) {
    if (branchId != null) {
      _branchCache.remove(branchId);
    } else {
      _branchCache.clear();
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
      await _loadAssets();

      // Fallback Font
      final fontData = _cachedArabicFont ?? await rootBundle.load("assets/fonts/NotoSansArabic-Regular.ttf");
      final pw.Font arabicFont = pw.Font.ttf(fontData);

      // Logo Image Provider
      final pw.ImageProvider? logoImage = _cachedLogo != null ? pw.MemoryImage(_cachedLogo!.buffer.asUint8List()) : null;

      await Printing.layoutPdf(
          onLayout: (PdfPageFormat format) async {
            final Map<String, dynamic> order = Map<String, dynamic>.from(orderDoc.data() as Map);

            // --- 1. Prepare Data & Totals ---
            final double subtotal = (order['subtotal'] as num?)?.toDouble() ?? 0.0;
            final double discount = (order['discountAmount'] as num?)?.toDouble() ?? 0.0;
            final double totalAmount = (order['totalAmount'] as num?)?.toDouble() ?? 0.0;

            // Items
            final List<dynamic> rawItems = (order['items'] ?? []) as List<dynamic>;
            int totalItemCount = 0;
            final List<Map<String, dynamic>> items = rawItems.map((e) {
              final m = Map<String, dynamic>.from(e as Map);
              final int qty = int.tryParse((m['quantity'] ?? m['qty'] ?? '1').toString()) ?? 1;
              totalItemCount += qty;
              return {
                'name': (m['name'] ?? 'Item').toString(),
                'name_ar': (m['name_ar'] ?? '').toString(),
                'qty': qty,
                'price': double.tryParse((m['price'] ?? m['unitPrice'] ?? m['amount'] ?? '0').toString()) ?? 0.0,
              };
            }).toList();

            // Dates
            final DateTime? rawDate = (order['timestamp'] as Timestamp?)?.toDate();
            final DateTime? orderDate = rawDate != null ? TimeUtils.getRestaurantTime(rawDate) : null;
            final String formattedDate = orderDate != null ? DateFormat('dd/MM/yyyy').format(orderDate) : "N/A";
            final String formattedTime = orderDate != null ? DateFormat('hh:mm a').format(orderDate) : "N/A";

            // Branch Info
            final List<dynamic> branchIds = order['branchIds'] ?? [];
            String primaryBranchId = branchIds.isNotEmpty ? branchIds.first.toString() : '';

            String branchName = "MITRAN Restaurant";
            String branchNameAr = "مطعم ميت ران";
            String branchPhone = "";
            String branchAddress = "Doha, Qatar";

            if (primaryBranchId.isNotEmpty) {
              // Clear expired cache entries
              PrintingService._clearExpiredCache();
              
              // Check cache or fetch from Firestore
              final cached = PrintingService._branchCache[primaryBranchId];
              if (cached == null || cached.isExpired) {
                final branchSnap = await FirebaseFirestore.instance
                    .collection('Branch')
                    .doc(primaryBranchId)
                    .get()
                    .timeout(AppConstants.firestoreTimeout);
                if (branchSnap.exists) {
                  PrintingService._branchCache[primaryBranchId] = _CachedBranch(branchSnap.data()!);
                }
              }
              final branchData = PrintingService._branchCache[primaryBranchId]?.data;
              if (branchData != null) {
                branchName = branchData['name'] ?? branchName;
                branchNameAr = branchData['name_ar'] ?? branchNameAr;
                branchPhone = branchData['phone'] ?? "";

                final addressMap = branchData['address'] as Map<String, dynamic>? ?? {};
                final street = addressMap['street'] ?? '';
                final city = addressMap['city'] ?? '';
                branchAddress = (street.isNotEmpty || city.isNotEmpty) ? "$street, $city" : branchAddress;
              }
            }

            // Order Details
            final String dailyOrderNumber = order['dailyOrderNumber']?.toString() ?? orderDoc.id.substring(0, 6).toUpperCase();
            final String orderType = (order['Order_type'] ?? 'Unknown').toString().toUpperCase().replaceAll('_', ' ');
            final String customerName = (order['customerName'] ?? 'Walk-in').toString();
            
            // Takeaway-specific fields
            final String orderTypeLower = (order['Order_type'] ?? '').toString().toLowerCase();
            final bool isTakeaway = orderTypeLower == 'takeaway';
            final String carPlateNumber = (order['carPlateNumber'] ?? '').toString();
            final String specialInstructions = (order['specialInstructions'] ?? '').toString();

            // QR Code (Simple Order Ref)
            final String qrData = "Order: $dailyOrderNumber\nAmt: $totalAmount\nDate: $formattedDate";

            // --- 2. PDF Styles ---
            final pdf = pw.Document();
            const double fontSizeSmall = 8;
            const double fontSizeRegular = 9;

            final pw.TextStyle fontReg = pw.TextStyle(fontSize: fontSizeRegular);
            final pw.TextStyle fontBold = pw.TextStyle(fontSize: fontSizeRegular, fontWeight: pw.FontWeight.bold);
            final pw.TextStyle fontArReg = pw.TextStyle(font: arabicFont, fontSize: fontSizeRegular);
            final pw.TextStyle fontArBold = pw.TextStyle(font: arabicFont, fontSize: fontSizeRegular, fontWeight: pw.FontWeight.bold);

            // Helper: Bilingual Row
            pw.Widget bilingualRow(String en, String ar, String value, {bool isBold = false}) {
              return pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(en, style: isBold ? fontBold : fontReg),
                      if(ar.isNotEmpty) pw.Text(ar, style: isBold ? fontArBold : fontArReg, textDirection: pw.TextDirection.rtl),
                    ],
                  ),
                  pw.Text(value, style: isBold ? fontBold : fontReg),
                ],
              );
            }

            pdf.addPage(
                pw.Page(
                    pageFormat: PdfPageFormat.roll80,
                    margin: const pw.EdgeInsets.all(10),
                    build: (pw.Context context) {
                      return pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.center,
                          children: [
                            // --- LOGO & HEADER ---
                            if (logoImage != null)
                              pw.Container(
                                height: 50,
                                width: 50,
                                margin: const pw.EdgeInsets.only(bottom: 5),
                                child: pw.Image(logoImage),
                              ),

                            pw.Text(branchName, style: fontBold.copyWith(fontSize: 12)),
                            pw.Text(branchNameAr, style: fontArBold.copyWith(fontSize: 12), textDirection: pw.TextDirection.rtl),

                            if(branchAddress.isNotEmpty)
                              pw.Text(branchAddress, style: fontReg.copyWith(fontSize: fontSizeSmall), textAlign: pw.TextAlign.center),
                            if(branchPhone.isNotEmpty)
                              pw.Text("Tel: $branchPhone", style: fontReg.copyWith(fontSize: fontSizeSmall)),

                            pw.SizedBox(height: 5),
                            pw.Divider(thickness: 1),

                            // --- TITLE ---
                            pw.Text("SALES RECEIPT / إيصال بيع", style: fontBold.copyWith(fontSize: 11)),
                            pw.SizedBox(height: 5),

                            // --- DETAILS BOX ---
                            pw.Container(
                                padding: const pw.EdgeInsets.all(5),
                                decoration: pw.BoxDecoration(
                                    border: pw.Border.all(color: PdfColors.grey400),
                                    borderRadius: pw.BorderRadius.circular(5)
                                ),
                                child: pw.Column(
                                    children: [
                                      bilingualRow("Order #", "رقم الطلب", dailyOrderNumber, isBold: true),
                                      pw.SizedBox(height: 2),
                                      bilingualRow("Date", "التاريخ", "$formattedDate $formattedTime"),
                                      pw.SizedBox(height: 2),
                                      bilingualRow("Type", "النوع", orderType),
                                      pw.SizedBox(height: 2),
                                      // For takeaway: show car plate instead of customer name
                                      if (isTakeaway && carPlateNumber.isNotEmpty)
                                        bilingualRow("Car Plate", "رقم لوحة السيارة", carPlateNumber.length > 15 ? "${carPlateNumber.substring(0,12)}..." : carPlateNumber)
                                      else
                                        bilingualRow("Customer", "العميل", customerName.length > 15 ? "${customerName.substring(0,12)}..." : customerName),
                                      // For takeaway: show special instructions if present
                                      if (isTakeaway && specialInstructions.isNotEmpty) ...[
                                        pw.SizedBox(height: 2),
                                        bilingualRow("Instructions", "تعليمات خاصة", specialInstructions.length > 20 ? "${specialInstructions.substring(0,17)}..." : specialInstructions),
                                      ],
                                    ]
                                )
                            ),

                            pw.SizedBox(height: 10),

                            // --- ITEMS TABLE ---
                            pw.Table(
                                columnWidths: {
                                  0: const pw.FlexColumnWidth(4), // Item
                                  1: const pw.FlexColumnWidth(1), // Qty
                                  2: const pw.FlexColumnWidth(2), // Total
                                },
                                border: const pw.TableBorder(
                                  bottom: pw.BorderSide(width: 0.5, color: PdfColors.black),
                                ),
                                children: [
                                  // Header
                                  pw.TableRow(
                                      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                                      children: [
                                        pw.Padding(padding: const pw.EdgeInsets.all(2), child: pw.Text("ITEM / الصنف", style: fontBold)),
                                        pw.Padding(padding: const pw.EdgeInsets.all(2), child: pw.Text("QTY", style: fontBold, textAlign: pw.TextAlign.center)),
                                        pw.Padding(padding: const pw.EdgeInsets.all(2), child: pw.Text("AMT", style: fontBold, textAlign: pw.TextAlign.right)),
                                      ]
                                  ),
                                  // Items
                                  ...items.map((item) {
                                    final itemTotal = (item['price'] * item['qty']).toDouble();
                                    return pw.TableRow(
                                        children: [
                                          pw.Padding(
                                              padding: const pw.EdgeInsets.symmetric(vertical: 2),
                                              child: pw.Column(
                                                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                                                  children: [
                                                    pw.Text(item['name'], style: fontReg),
                                                    if (item['name_ar'].isNotEmpty)
                                                      pw.Text(item['name_ar'], style: fontArReg, textDirection: pw.TextDirection.rtl),
                                                  ]
                                              )
                                          ),
                                          pw.Padding(
                                              padding: const pw.EdgeInsets.symmetric(vertical: 4),
                                              child: pw.Text(item['qty'].toString(), style: fontReg, textAlign: pw.TextAlign.center)
                                          ),
                                          pw.Padding(
                                              padding: const pw.EdgeInsets.symmetric(vertical: 4),
                                              child: pw.Text(itemTotal.toStringAsFixed(2), style: fontReg, textAlign: pw.TextAlign.right)
                                          ),
                                        ]
                                    );
                                  }).toList()
                                ]
                            ),

                            pw.SizedBox(height: 10),

                            // --- TOTALS ---
                            pw.Row(
                                mainAxisAlignment: pw.MainAxisAlignment.end,
                                children: [
                                  pw.Container(
                                      width: 140,
                                      child: pw.Column(
                                          children: [
                                            // Total Items Count
                                            pw.Row(
                                                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                                                children: [
                                                  pw.Text("Total Items", style: fontReg.copyWith(fontSize: 8, color: PdfColors.grey700)),
                                                  pw.Text("$totalItemCount", style: fontReg.copyWith(fontSize: 8, color: PdfColors.grey700)),
                                                ]
                                            ),
                                            pw.SizedBox(height: 4),

                                            bilingualRow("Subtotal", "المجموع", totalAmount.toStringAsFixed(2)),

                                            if (discount > 0)
                                              bilingualRow("Discount", "الخصم", "- ${discount.toStringAsFixed(2)}"),

                                            pw.Divider(thickness: 1),

                                            pw.Row(
                                                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                                                children: [
                                                  pw.Text("TOTAL", style: fontBold.copyWith(fontSize: 14)),
                                                  pw.Text("QAR ${totalAmount.toStringAsFixed(2)}", style: fontBold.copyWith(fontSize: 14)),
                                                ]
                                            ),
                                            pw.Align(
                                              alignment: pw.Alignment.centerRight,
                                              child: pw.Text("المجموع الكلي", style: fontArBold, textDirection: pw.TextDirection.rtl),
                                            ),
                                          ]
                                      )
                                  )
                                ]
                            ),

                            pw.SizedBox(height: 15),

                            // --- FOOTER & QR ---
                            pw.Row(
                                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: pw.CrossAxisAlignment.center,
                                children: [
                                  pw.Container(
                                    height: 40,
                                    width: 40,
                                    child: pw.BarcodeWidget(
                                      barcode: pw.Barcode.qrCode(),
                                      data: qrData,
                                      drawText: false,
                                    ),
                                  ),
                                  pw.Expanded(
                                      child: pw.Column(
                                          crossAxisAlignment: pw.CrossAxisAlignment.end,
                                          children: [
                                            pw.Text("Thank you for dining with us!", style: fontBold),
                                            pw.Text("شكرا لزيارتكم!", style: fontArBold, textDirection: pw.TextDirection.rtl),
                                            pw.SizedBox(height: 2),
                                            pw.Text("www.mitran-restaurant.com", style: fontReg.copyWith(fontSize: 7, color: PdfColors.grey600)),
                                          ]
                                      )
                                  )
                                ]
                            ),
                          ]
                      );
                    }
                )
            );

            return pdf.save();
          }
      );
    } catch (e, st) {
      debugPrint("Error printing: $e $st");
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Print Error: $e")));
      }
    }
  }
}