// lib/services/pos/pos_register_service.dart
// Manages POS register opening/closing per day per branch (Odoo-style)
// Industry-grade: session metrics, force-close, payment breakdowns

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../constants.dart';

class PosRegisterSession {
  final String id;
  final String branchId;
  final String openedBy;
  final double openingBalance;
  final DateTime openedAt;
  final DateTime? closedAt;
  final double? closingBalance;
  final double? expectedBalance;
  final String? closedBy;
  final String? notes;
  // ── Enriched session metrics (populated at close time) ──
  final int totalOrders;
  final int totalCancelled;
  final double totalCashSales;
  final double totalCardSales;
  final double totalOnlineSales;
  final double totalRefunds;
  final int sessionDurationMinutes;
  final bool isForceClosed;
  final String? overriddenBy;
  final int activeOrdersAtClose;

  const PosRegisterSession({
    required this.id,
    required this.branchId,
    required this.openedBy,
    required this.openingBalance,
    required this.openedAt,
    this.closedAt,
    this.closingBalance,
    this.expectedBalance,
    this.closedBy,
    this.notes,
    this.totalOrders = 0,
    this.totalCancelled = 0,
    this.totalCashSales = 0.0,
    this.totalCardSales = 0.0,
    this.totalOnlineSales = 0.0,
    this.totalRefunds = 0.0,
    this.sessionDurationMinutes = 0,
    this.isForceClosed = false,
    this.overriddenBy,
    this.activeOrdersAtClose = 0,
  });

  bool get isOpen => closedAt == null;

  double get totalSales => totalCashSales + totalCardSales + totalOnlineSales;

  double get variance {
    if (closingBalance == null || expectedBalance == null) return 0;
    return closingBalance! - expectedBalance!;
  }

  double get variancePercent {
    if (expectedBalance == null || expectedBalance == 0) return 0;
    return (variance / expectedBalance!) * 100;
  }

  factory PosRegisterSession.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return PosRegisterSession(
      id: doc.id,
      branchId: data['branchId'] ?? '',
      openedBy: data['openedBy'] ?? '',
      openingBalance: (data['openingBalance'] as num?)?.toDouble() ?? 0.0,
      openedAt: (data['openedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      closedAt: (data['closedAt'] as Timestamp?)?.toDate(),
      closingBalance: (data['closingBalance'] as num?)?.toDouble(),
      expectedBalance: (data['expectedBalance'] as num?)?.toDouble(),
      closedBy: data['closedBy'],
      notes: data['notes'],
      totalOrders: (data['totalOrders'] as num?)?.toInt() ?? 0,
      totalCancelled: (data['totalCancelled'] as num?)?.toInt() ?? 0,
      totalCashSales: (data['totalCashSales'] as num?)?.toDouble() ?? 0.0,
      totalCardSales: (data['totalCardSales'] as num?)?.toDouble() ?? 0.0,
      totalOnlineSales: (data['totalOnlineSales'] as num?)?.toDouble() ?? 0.0,
      totalRefunds: (data['totalRefunds'] as num?)?.toDouble() ?? 0.0,
      sessionDurationMinutes: (data['sessionDurationMinutes'] as num?)?.toInt() ?? 0,
      isForceClosed: data['isForceClosed'] == true,
      overriddenBy: data['overriddenBy'],
      activeOrdersAtClose: (data['activeOrdersAtClose'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Breakdown of session sales by payment method
class RegisterSessionMetrics {
  final int totalOrders;
  final int totalCancelled;
  final double totalCashSales;
  final double totalCardSales;
  final double totalOnlineSales;
  final double totalRefunds;
  final double totalSales;

  const RegisterSessionMetrics({
    required this.totalOrders,
    required this.totalCancelled,
    required this.totalCashSales,
    required this.totalCardSales,
    required this.totalOnlineSales,
    required this.totalRefunds,
    required this.totalSales,
  });

  factory RegisterSessionMetrics.empty() => const RegisterSessionMetrics(
        totalOrders: 0,
        totalCancelled: 0,
        totalCashSales: 0,
        totalCardSales: 0,
        totalOnlineSales: 0,
        totalRefunds: 0,
        totalSales: 0,
      );
}

class PosRegisterService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Check if there's an open register session for this branch today
  Future<PosRegisterSession?> getOpenSession(String branchId) async {
    if (branchId.isEmpty) return null;
    final today = _todayString();
    final query = await _db
        .collection('pos_registers')
        .where('branchId', isEqualTo: branchId)
        .where('date', isEqualTo: today)
        .where('closedAt', isNull: true)
        .limit(1)
        .get();

    if (query.docs.isEmpty) return null;
    return PosRegisterSession.fromFirestore(query.docs.first);
  }

  /// Stream open register session for this branch today
  Stream<PosRegisterSession?> streamOpenSession(String branchId) {
    if (branchId.isEmpty) return Stream.value(null);
    final today = _todayString();
    return _db
        .collection('pos_registers')
        .where('branchId', isEqualTo: branchId)
        .where('date', isEqualTo: today)
        .where('closedAt', isNull: true)
        .limit(1)
        .snapshots()
        .map((snap) {
      if (snap.docs.isEmpty) return null;
      return PosRegisterSession.fromFirestore(snap.docs.first);
    });
  }

  /// Stream count of currently open registers across branches
  Stream<int> streamOpenRegisterCount(List<String> branchIds) {
    if (branchIds.isEmpty) return Stream.value(0);
    final today = _todayString();
    final ids = branchIds.take(10).toList();
    return _db
        .collection('pos_registers')
        .where('branchId', whereIn: ids)
        .where('date', isEqualTo: today)
        .where('closedAt', isNull: true)
        .snapshots()
        .map((snap) => snap.docs.length);
  }

  /// Open a new register session
  Future<PosRegisterSession> openRegister({
    required String branchId,
    required String openedBy,
    required double openingBalance,
    String? notes,
  }) async {
    // Validate inputs
    if (branchId.isEmpty) {
      throw Exception('Branch ID is required to open a register.');
    }
    if (openedBy.isEmpty) {
      throw Exception('Cashier identity is required to open a register.');
    }
    if (openingBalance < 0) {
      throw Exception('Opening balance cannot be negative.');
    }

    final today = _todayString();

    // Prevent duplicate opens
    final existing = await getOpenSession(branchId);
    if (existing != null) {
      throw Exception(
          'A register session is already open for today (opened by ${existing.openedBy}).');
    }

    final docRef = _db.collection('pos_registers').doc();
    final now = DateTime.now();

    await docRef.set({
      'branchId': branchId,
      'openedBy': openedBy,
      'openingBalance': openingBalance,
      'openedAt': FieldValue.serverTimestamp(),
      'closedAt': null,
      'closingBalance': null,
      'expectedBalance': null,
      'closedBy': null,
      'notes': notes ?? '',
      'date': today,
      // Session metrics (populated at close time)
      'totalOrders': 0,
      'totalCancelled': 0,
      'totalCashSales': 0.0,
      'totalCardSales': 0.0,
      'totalOnlineSales': 0.0,
      'totalRefunds': 0.0,
      'sessionDurationMinutes': 0,
      'isForceClosed': false,
      'overriddenBy': null,
      'activeOrdersAtClose': 0,
    });

    return PosRegisterSession(
      id: docRef.id,
      branchId: branchId,
      openedBy: openedBy,
      openingBalance: openingBalance,
      openedAt: now,
    );
  }

  /// Check if there are active (non-terminal) orders for this branch
  Future<List<String>> getActiveOrderIds(String branchId) async {
    final snap = await _db
        .collection(AppConstants.collectionOrders)
        .where('branchIds', arrayContains: branchId)
        .where('timestamp',
            isGreaterThan:
                DateTime.now().subtract(const Duration(hours: 24)))
        .where('status', whereIn: [
          AppConstants.statusPending,
          AppConstants.statusPreparing,
          AppConstants.statusPrepared,
          AppConstants.statusServed,
          AppConstants.statusNeedsAssignment,
          AppConstants.statusRiderAssigned,
          AppConstants.statusPickedUp,
          AppConstants.statusPickedUpLegacy,
          'ready',
          'placed',
        ])
        .limit(10)
        .get();

    return snap.docs.map((doc) {
      final data = doc.data();
      return OrderNumberHelper.getDisplayNumber(data, orderId: doc.id);
    }).toList();
  }

  /// Compute session metrics: order count, cash/card/online breakdown, cancellations
  Future<RegisterSessionMetrics> computeSessionMetrics(
      String branchId, DateTime openedAt) async {
    // Fetch all orders placed during this session
    final snap = await _db
        .collection(AppConstants.collectionOrders)
        .where('branchIds', arrayContains: branchId)
        .where('timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(openedAt))
        .get();

    int totalOrders = 0;
    int totalCancelled = 0;
    double totalCash = 0;
    double totalCard = 0;
    double totalOnline = 0;
    double totalRefunds = 0;

    for (final doc in snap.docs) {
      final data = doc.data();
      totalOrders++;

      final status = (data['status'] ?? '').toString().toLowerCase();
      if (status == 'cancelled' || status == 'failed') {
        totalCancelled++;
        continue;
      }

      // Parse payments array for method-level breakdown
      final payments = data['payments'] as List<dynamic>? ?? [];
      if (payments.isNotEmpty) {
        for (final p in payments) {
          if (p is! Map) continue;
          final method = (p['method'] ?? '').toString().toLowerCase();
          final applied = (p['appliedAmount'] as num?)?.toDouble() ?? 0.0;

          // Check for nested split payments
          final nestedPayments = p['payments'] as List<dynamic>?;
          if (nestedPayments != null && nestedPayments.isNotEmpty) {
            for (final np in nestedPayments) {
              if (np is! Map) continue;
              final nestedMethod =
                  (np['method'] ?? '').toString().toLowerCase();
              final nestedApplied =
                  (np['appliedAmount'] as num?)?.toDouble() ?? 0.0;
              _addToMethod(nestedMethod, nestedApplied,
                  cashRef: (v) => totalCash += v,
                  cardRef: (v) => totalCard += v,
                  onlineRef: (v) => totalOnline += v);
            }
          } else {
            _addToMethod(method, applied,
                cashRef: (v) => totalCash += v,
                cardRef: (v) => totalCard += v,
                onlineRef: (v) => totalOnline += v);
          }
        }
      } else {
        // Fallback: use paymentMethod field + totalAmount
        final method =
            (data['paymentMethod'] ?? '').toString().toLowerCase();
        final amount = (data['totalAmount'] as num?)?.toDouble() ?? 0.0;
        final isPaid = ['paid', 'delivered', 'collected'].contains(status);
        if (isPaid) {
          _addToMethod(method, amount,
              cashRef: (v) => totalCash += v,
              cardRef: (v) => totalCard += v,
              onlineRef: (v) => totalOnline += v);
        }
      }
    }

    return RegisterSessionMetrics(
      totalOrders: totalOrders,
      totalCancelled: totalCancelled,
      totalCashSales: _round(totalCash),
      totalCardSales: _round(totalCard),
      totalOnlineSales: _round(totalOnline),
      totalRefunds: _round(totalRefunds),
      totalSales: _round(totalCash + totalCard + totalOnline),
    );
  }

  void _addToMethod(
    String method,
    double amount, {
    required void Function(double) cashRef,
    required void Function(double) cardRef,
    required void Function(double) onlineRef,
  }) {
    if (method == 'cash') {
      cashRef(amount);
    } else if (method == 'card') {
      cardRef(amount);
    } else if (method == 'online') {
      onlineRef(amount);
    } else {
      // Default unrecognized methods to cash
      cashRef(amount);
    }
  }

  /// Close the register session with enriched metrics
  Future<void> closeRegister({
    required String sessionId,
    required double closingBalance,
    required double expectedBalance,
    required String closedBy,
    String? notes,
    RegisterSessionMetrics? metrics,
    bool isForceClosed = false,
    String? overriddenBy,
    int activeOrdersAtClose = 0,
    int sessionDurationMinutes = 0,
  }) async {
    final updateData = <String, dynamic>{
      'closedAt': FieldValue.serverTimestamp(),
      'closingBalance': closingBalance,
      'expectedBalance': expectedBalance,
      'closedBy': closedBy,
      'notes': notes ?? '',
      'isForceClosed': isForceClosed,
      'activeOrdersAtClose': activeOrdersAtClose,
      'sessionDurationMinutes': sessionDurationMinutes,
    };

    if (overriddenBy != null) {
      updateData['overriddenBy'] = overriddenBy;
    }

    if (metrics != null) {
      updateData['totalOrders'] = metrics.totalOrders;
      updateData['totalCancelled'] = metrics.totalCancelled;
      updateData['totalCashSales'] = metrics.totalCashSales;
      updateData['totalCardSales'] = metrics.totalCardSales;
      updateData['totalOnlineSales'] = metrics.totalOnlineSales;
      updateData['totalRefunds'] = metrics.totalRefunds;
    }

    await _db.collection('pos_registers').doc(sessionId).update(updateData);
  }

  /// Calculate total sales for a session (Paid orders only) — legacy method
  Future<double> getSessionSales(String branchId, DateTime openedAt) async {
    final snap = await _db
        .collection(AppConstants.collectionOrders)
        .where('branchIds', arrayContains: branchId)
        .where('timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(openedAt))
        .where('status', whereIn: ['paid', 'delivered', 'collected'])
        .get();

    double total = 0;
    for (final doc in snap.docs) {
      final data = doc.data();
      total += (data['totalAmount'] as num?)?.toDouble() ?? 0.0;
    }
    return double.parse(total.toStringAsFixed(2));
  }

  /// Get session history for analytics (paginated)
  Future<List<PosRegisterSession>> getSessionHistory({
    required List<String> branchIds,
    required DateTime startDate,
    required DateTime endDate,
    int limit = 50,
  }) async {
    if (branchIds.isEmpty) return [];

    final query = await _db
        .collection('pos_registers')
        .where('branchId', whereIn: branchIds.take(10).toList())
        .where('openedAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
        .where('openedAt',
            isLessThanOrEqualTo: Timestamp.fromDate(
                DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59)))
        .orderBy('openedAt', descending: true)
        .limit(limit)
        .get();

    return query.docs
        .map((doc) => PosRegisterSession.fromFirestore(doc))
        .toList();
  }

  String _todayString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  static double _round(double v) => double.parse(v.toStringAsFixed(2));
}
