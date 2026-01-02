import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../main.dart'; // For UserScopeService class definition if not separated
import '../Widgets/RiderAssignment.dart';
import 'TimeUtils.dart';

class OrderService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<QuerySnapshot<Map<String, dynamic>>> getOrdersStream({
    required String orderType,
    required String status,
    required UserScopeService userScope,
  }) {
    Query<Map<String, dynamic>> baseQuery = _db
        .collection('Orders')
        .where('Order_type', isEqualTo: orderType);

    if (!userScope.isSuperAdmin) {
      baseQuery = baseQuery.where('branchIds', arrayContains: userScope.branchId);
    }

    if (status == 'all') {
      // Use TimeUtils to centralize the logic
      final startOfBusinessDay = TimeUtils.getBusinessStartDateTime();
      final endOfBusinessDay = TimeUtils.getBusinessEndDateTime();

      baseQuery = baseQuery
          .where('timestamp', isGreaterThanOrEqualTo: startOfBusinessDay)
          .where('timestamp', isLessThan: endOfBusinessDay);
    } else {
      // Specific status filtering ignores date to catch old pending orders
      baseQuery = baseQuery.where('status', isEqualTo: status);
    }

    return baseQuery.orderBy('timestamp', descending: true).snapshots();
  }

  Future<void> updateOrderStatus(
      BuildContext context,
      String orderId,
      String newStatus,
      {String? reason, String? currentUserEmail}
      ) async {
    final orderRef = _db.collection('Orders').doc(orderId);

    if (newStatus == 'cancelled') {
      // Transaction for Cancellation
      await _db.runTransaction((transaction) async {
        final snapshot = await transaction.get(orderRef);
        if (!snapshot.exists) throw Exception("Order does not exist!");

        final data = snapshot.data() as Map<String, dynamic>;
        if (data['status'] == 'delivered') {
          throw Exception("Cannot cancel an order that is already delivered!");
        }

        final Map<String, dynamic> updates = {
          'status': 'cancelled',
          'timestamps.cancelled': FieldValue.serverTimestamp(),
          'riderId': FieldValue.delete(),
        };

        if (reason != null) updates['cancellationReason'] = reason;
        updates['cancelledBy'] = currentUserEmail ?? 'Admin';

        transaction.update(orderRef, updates);

        // Handle Rider Cleanup
        final String? riderId = data['riderId'];
        if (riderId != null && riderId.isNotEmpty) {
          final driverRef = _db.collection('Drivers').doc(riderId);
          transaction.update(driverRef, {
            'assignedOrderId': '',
            'isAvailable': true,
          });
        }
      });

      // Stop auto-assignment if active
      await RiderAssignmentService.cancelAutoAssignment(orderId);

    } else {
      // Batch for standard status updates
      final WriteBatch batch = _db.batch();
      final Map<String, dynamic> updateData = {'status': newStatus};

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
  }
}