// lib/services/pos/pos_register_service.dart
// Manages POS register opening/closing per day per branch (Odoo-style)

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
  });

  bool get isOpen => closedAt == null;

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
    );
  }
}

class PosRegisterService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Check if there's an open register session for this branch today
  Future<PosRegisterSession?> getOpenSession(String branchId) async {
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

  /// Open a new register session
  Future<PosRegisterSession> openRegister({
    required String branchId,
    required String openedBy,
    required double openingBalance,
    String? notes,
  }) async {
    final today = _todayString();

    // Prevent duplicate opens
    final existing = await getOpenSession(branchId);
    if (existing != null) {
      throw Exception('A register session is already open for today.');
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
    });

    return PosRegisterSession(
      id: docRef.id,
      branchId: branchId,
      openedBy: openedBy,
      openingBalance: openingBalance,
      openedAt: now,
    );
  }

  /// Close the register session
  Future<void> closeRegister({
    required String sessionId,
    required double closingBalance,
    required double expectedBalance,
    required String closedBy,
    String? notes,
  }) async {
    await _db.collection('pos_registers').doc(sessionId).update({
      'closedAt': FieldValue.serverTimestamp(),
      'closingBalance': closingBalance,
      'expectedBalance': expectedBalance,
      'closedBy': closedBy,
      'notes': notes ?? '',
    });
  }

  /// Calculate total sales for a session (Paid orders only)
  Future<double> getSessionSales(String branchId, DateTime openedAt) async {
    final snap = await _db
        .collection(AppConstants.collectionOrders)
        .where('branchIds', arrayContains: branchId)
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(openedAt))
        .where('status', whereIn: ['paid', 'delivered', 'collected'])
        .get();

    double total = 0;
    for (final doc in snap.docs) {
      final data = doc.data();
      total += (data['totalAmount'] as num?)?.toDouble() ?? 0.0;
    }
    return double.parse(total.toStringAsFixed(2));
  }

  String _todayString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
}
