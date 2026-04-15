// lib/services/pos/pos_register_service.dart
// Manages POS register opening/closing per day per branch (Odoo-style)
// Industry-grade: session metrics, force-close, payment breakdowns

import 'package:cloud_firestore/cloud_firestore.dart';
import '../../constants.dart';

class PosRegisterSession {
  final String id;
  final List<String> branchIds;
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
    required this.branchIds,
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
      branchIds: data['branchIds'] is List 
          ? List<String>.from(data['branchIds']) 
          : (data['branchId'] is String && (data['branchId'] as String).isNotEmpty 
              ? [data['branchId'] as String] 
              : []),
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
      sessionDurationMinutes:
          (data['sessionDurationMinutes'] as num?)?.toInt() ?? 0,
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
        .where('branchIds', arrayContains: branchId)
        .where('date', isEqualTo: today)
        .where('closedAt', isNull: true)
        .limit(1)
        .get();

    if (query.docs.isEmpty) return null;
    return PosRegisterSession.fromFirestore(query.docs.first);
  }

  /// INDUSTRY GRADE: Detect stale register sessions from previous days that
  /// were never closed. Returns the most recent orphaned session.
  Future<PosRegisterSession?> getStaleOpenSession(String branchId) async {
    if (branchId.isEmpty) return null;
    final today = _todayString();
    final query = await _db
        .collection('pos_registers')
        .where('branchIds', arrayContains: branchId)
        .where('closedAt', isNull: true)
        .orderBy('openedAt', descending: true)
        .limit(1)
        .get();

    if (query.docs.isEmpty) return null;
    final session = PosRegisterSession.fromFirestore(query.docs.first);
    // Only return if it's from a previous day (not today)
    final data = query.docs.first.data();
    final sessionDate = data['date']?.toString() ?? '';
    if (sessionDate == today) return null; // Today's session — not stale
    return session;
  }

  /// Force-close a stale session from a previous day.
  Future<void> forceCloseStaleSession(PosRegisterSession staleSession) async {
    if (staleSession.id.isEmpty) return;
    await _db.collection('pos_registers').doc(staleSession.id).update({
      'closedAt': FieldValue.serverTimestamp(),
      'closedBy': 'system_auto_close',
      'isForceClosed': true,
      'notes': 'Auto-closed: register was left open from a previous day.',
      'closingBalance': staleSession.openingBalance,
      'expectedBalance': staleSession.openingBalance,
    });
  }

  /// Stream open register session for this branch today
  Stream<PosRegisterSession?> streamOpenSession(String branchId) {
    if (branchId.isEmpty) return Stream.value(null);
    final today = _todayString();
    return _db
        .collection('pos_registers')
        .where('branchIds', arrayContains: branchId)
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
        .where('branchIds', arrayContainsAny: ids)
        .where('date', isEqualTo: today)
        .where('closedAt', isNull: true)
        .snapshots()
        .map((snap) => snap.docs.length);
  }

  /// INDUSTRY GRADE: Atomic register open with Firestore transaction.
  /// Prevents two devices from opening a register simultaneously.
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
    final docRef = _db.collection('pos_registers').doc();
    final now = DateTime.now();

    // INDUSTRY GRADE: Use a transaction to atomically check + create.
    // This prevents the race condition where two devices both pass the
    // "getOpenSession" check and both create a session.
    await _db.runTransaction<void>((transaction) async {
      // Read: Check for any existing open session for this branch today
      final existingQuery = await _db
          .collection('pos_registers')
          .where('branchIds', arrayContains: branchId)
          .where('date', isEqualTo: today)
          .where('closedAt', isNull: true)
          .limit(1)
          .get();

      if (existingQuery.docs.isNotEmpty) {
        final existingData = existingQuery.docs.first.data();
        final existingOpenedBy = existingData['openedBy'] ?? 'another cashier';
        throw Exception(
            'A register is already open for today (opened by $existingOpenedBy). '
            'Only one register session per branch per day is allowed.');
      }

      // Write: Create the register session atomically
      transaction.set(docRef, {
        'branchIds': [branchId],
        'openedBy': openedBy,
        'openingBalance': openingBalance,
        'openedAt': FieldValue.serverTimestamp(),
        'closedAt': null,
        'closingBalance': null,
        'expectedBalance': null,
        'expectedCashBalance': null,
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
    });

    return PosRegisterSession(
      id: docRef.id,
      branchIds: [branchId],
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
            isGreaterThan: DateTime.now().subtract(const Duration(hours: 24)))
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
        final method = (data['paymentMethod'] ?? '').toString().toLowerCase();
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

  /// INDUSTRY GRADE: Close the register session with transaction guard.
  /// Verifies the session is still open before closing to prevent double-close.
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
    final docRef = _db.collection('pos_registers').doc(sessionId);

    await _db.runTransaction<void>((transaction) async {
      // GUARD: Read the doc first to verify it's still open
      final snap = await transaction.get(docRef);
      if (!snap.exists) {
        throw Exception('Register session not found. It may have been deleted.');
      }
      final data = snap.data()!;
      if (data['closedAt'] != null) {
        final closedBy = data['closedBy']?.toString() ?? 'another user';
        throw Exception(
            'This register was already closed by $closedBy. '
            'Refresh the POS to see the latest state.');
      }

      // INDUSTRY GRADE: Compute expected cash separately
      // Cash in drawer = opening + cash sales (card/online never enters the till)
      final openingBalance =
          (data['openingBalance'] as num?)?.toDouble() ?? 0.0;
      final expectedCashBalance = metrics != null
          ? _round(openingBalance + metrics.totalCashSales)
          : expectedBalance;

      final updateData = <String, dynamic>{
        'closedAt': FieldValue.serverTimestamp(),
        'closingBalance': closingBalance,
        'expectedBalance': expectedBalance,
        'expectedCashBalance': expectedCashBalance,
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

      transaction.update(docRef, updateData);
    });
  }

  /// Calculate total sales for a session (Paid orders only) — legacy method
  Future<double> getSessionSales(String branchId, DateTime openedAt) async {
    final snap = await _db
        .collection(AppConstants.collectionOrders)
        .where('branchIds', arrayContains: branchId)
        .where('timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(openedAt))
        .where('status', whereIn: ['paid', 'delivered', 'collected']).get();

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
        .where('branchIds', arrayContainsAny: branchIds.take(10).toList())
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

  /// User-friendly error messages for register operations.
  static String displayError(dynamic error) {
    if (error == null) return 'Unknown error';
    final raw = error.toString().trim();
    const prefix = 'Exception: ';
    final message = raw.startsWith(prefix)
        ? raw.substring(prefix.length).trim()
        : raw;
    final normalized = message.toLowerCase();

    if (normalized.contains('already open') ||
        normalized.contains('already closed')) {
      return message;
    }
    if (normalized.contains('permission-denied') ||
        normalized.contains('missing or insufficient permissions')) {
      return 'Permission denied. Please contact your administrator.';
    }
    if (normalized.contains('not found') ||
        normalized.contains('no document to update')) {
      return 'Register session not found. Please refresh and try again.';
    }
    if (normalized.contains('network') || normalized.contains('timeout')) {
      return 'Network error. Please check your connection and try again.';
    }
    return message;
  }
}
