import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart'; // ✅ Added for production monitoring

import '../main.dart'; // For UserScopeService
import 'TimeUtils.dart'; // Ensure this path matches where you moved TimeUtils
import '../Widgets/RiderAssignment.dart'; // Ensure this path matches your structure

class OrderService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Listens to the stream of orders based on filters
  Stream<QuerySnapshot<Map<String, dynamic>>> getOrdersStream({
    required String orderType,
    required String status,
    required UserScopeService userScope,
  }) {
    Query<Map<String, dynamic>> baseQuery = _db
        .collection('Orders')
        .where('Order_type', isEqualTo: orderType);

    // 1. Security: Filter by Branch (if not Super Admin)
    if (!userScope.isSuperAdmin) {
      baseQuery = baseQuery.where('branchIds', arrayContains: userScope.branchId);
    }

    // 2. Filter by Status/Time
    if (status == 'all') {
      // ✅ Use TimeUtils for consistent "Business Day" logic across the app
      final startOfBusinessDay = TimeUtils.getBusinessStartTimestamp();
      final endOfBusinessDay = TimeUtils.getBusinessEndTimestamp(); // Ensure this method exists in TimeUtils or calculate it here

      baseQuery = baseQuery
          .where('timestamp', isGreaterThanOrEqualTo: startOfBusinessDay)
          .where('timestamp', isLessThan: endOfBusinessDay);
    } else {
      // Specific status filtering (e.g., 'pending') ignores date to catch old stuck orders
      baseQuery = baseQuery.where('status', isEqualTo: status);
    }

    // 3. Sorting
    return baseQuery.orderBy('timestamp', descending: true).snapshots();
  }

  /// Updates the status of an order safely using Transactions or Batches
  Future<void> updateOrderStatus(
      BuildContext context,
      String orderId,
      String newStatus,
      {String? reason, String? currentUserEmail}
      ) async {
    final orderRef = _db.collection('Orders').doc(orderId);

    try {
      if (newStatus == 'cancelled') {
        // 🛑 Transaction for Cancellation (Prevents race conditions)
        await _db.runTransaction((transaction) async {
          final snapshot = await transaction.get(orderRef);
          if (!snapshot.exists) throw Exception("Order does not exist!");

          final data = snapshot.data() as Map<String, dynamic>;

          // Safety Check: Don't cancel if already delivered
          if (data['status'] == 'delivered') {
            throw Exception("Cannot cancel an order that is already delivered!");
          }

          final Map<String, dynamic> updates = {
            'status': 'cancelled',
            'timestamps.cancelled': FieldValue.serverTimestamp(),
            'riderId': FieldValue.delete(), // Remove rider assignment
          };

          if (reason != null) updates['cancellationReason'] = reason;
          updates['cancelledBy'] = currentUserEmail ?? 'Admin';

          transaction.update(orderRef, updates);

          // 🧹 cleanup: Free up the Rider if one was assigned
          final String? riderId = data['riderId'];
          if (riderId != null && riderId.isNotEmpty) {
            final driverRef = _db.collection('Drivers').doc(riderId);
            transaction.update(driverRef, {
              'assignedOrderId': '',
              'isAvailable': true,
            });
          }
        });

        // Stop any background auto-assignment tasks
        await RiderAssignmentService.cancelAutoAssignment(orderId);

      } else {
        // 🚀 Batch for Standard Updates (Faster/Cheaper)
        final WriteBatch batch = _db.batch();
        final Map<String, dynamic> updateData = {'status': newStatus};

        // Timestamp Logic
        if (newStatus == 'prepared') {
          updateData['timestamps.prepared'] = FieldValue.serverTimestamp();
        } else if (newStatus == 'delivered') {
          updateData['timestamps.delivered'] = FieldValue.serverTimestamp();

          // Free up rider if Delivery
          final orderDoc = await orderRef.get();
          final data = orderDoc.data() as Map<String, dynamic>? ?? {};
          final String orderType = (data['Order_type'] as String?)?.toLowerCase() ?? '';
          final String? riderId = data['riderId'] as String?;

          if (orderType == 'delivery' && riderId != null && riderId.isNotEmpty) {
            final driverRef = _db.collection('Drivers').doc(riderId);
            batch.update(driverRef, {'assignedOrderId': '', 'isAvailable': true});
          }
        } else if (newStatus == 'pickedUp') {
          updateData['timestamps.pickedUp'] = FieldValue.serverTimestamp();
        } else if (newStatus == 'rider_assigned') {
          updateData['timestamps.riderAssigned'] = FieldValue.serverTimestamp();
        }

        batch.update(orderRef, updateData);
        await batch.commit();
      }
    } catch (e, stack) {
      // 🚨 Production Observability: Log error to Crashlytics
      debugPrint("Error updating order: $e");
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Order Status Update Failed: $orderId -> $newStatus');
      rethrow; // Re-throw so the UI can show a SnackBar
    }
  }
}