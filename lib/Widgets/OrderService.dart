import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../main.dart';
import 'TimeUtils.dart';
import '../Widgets/RiderAssignment.dart';
import '../constants.dart'; // ✅ Added

class OrderService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<QuerySnapshot<Map<String, dynamic>>> getOrdersStream({
    required String orderType,
    required String status,
    required UserScopeService userScope,
  }) {
    // ✅ Use Constant
    Query<Map<String, dynamic>> baseQuery = _db
        .collection(AppConstants.collectionOrders)
        .where('Order_type', isEqualTo: orderType);

    if (!userScope.isSuperAdmin) {
      baseQuery = baseQuery.where('branchIds', arrayContains: userScope.branchId);
    }

    if (status == 'all') {
      final startOfBusinessDay = TimeUtils.getBusinessStartTimestamp();
      final endOfBusinessDay = TimeUtils.getBusinessEndTimestamp();

      baseQuery = baseQuery
          .where('timestamp', isGreaterThanOrEqualTo: startOfBusinessDay)
          .where('timestamp', isLessThan: endOfBusinessDay);
    } else {
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
    // ✅ Use Constant
    final orderRef = _db.collection(AppConstants.collectionOrders).doc(orderId);

    try {
      if (newStatus == AppConstants.statusCancelled) {
        await _db.runTransaction((transaction) async {
          final snapshot = await transaction.get(orderRef);
          if (!snapshot.exists) throw Exception("Order does not exist!");

          final data = snapshot.data() as Map<String, dynamic>;

          if (data['status'] == AppConstants.statusDelivered) {
            throw Exception("Cannot cancel an order that is already delivered!");
          }

          final Map<String, dynamic> updates = {
            'status': AppConstants.statusCancelled,
            'timestamps.cancelled': FieldValue.serverTimestamp(),
            'riderId': FieldValue.delete(),
          };

          if (reason != null) updates['cancellationReason'] = reason;
          updates['cancelledBy'] = currentUserEmail ?? 'Admin';

          transaction.update(orderRef, updates);

          final String? riderId = data['riderId'];
          if (riderId != null && riderId.isNotEmpty) {
            // ✅ Use Constant
            final driverRef = _db.collection(AppConstants.collectionDrivers).doc(riderId);
            transaction.update(driverRef, {
              'assignedOrderId': '',
              'isAvailable': true,
            });
          }
        });

        await RiderAssignmentService.cancelAutoAssignment(orderId);

      } else {
        final WriteBatch batch = _db.batch();
        final Map<String, dynamic> updateData = {'status': newStatus};

        if (newStatus == AppConstants.statusPrepared) {
          updateData['timestamps.prepared'] = FieldValue.serverTimestamp();
        } else if (newStatus == AppConstants.statusDelivered) {
          updateData['timestamps.delivered'] = FieldValue.serverTimestamp();

          final orderDoc = await orderRef.get();
          final data = orderDoc.data() as Map<String, dynamic>? ?? {};
          final String orderType = (data['Order_type'] as String?)?.toLowerCase() ?? '';
          final String? riderId = data['riderId'] as String?;

          if (orderType == 'delivery' && riderId != null && riderId.isNotEmpty) {
            final driverRef = _db.collection(AppConstants.collectionDrivers).doc(riderId);
            batch.update(driverRef, {'assignedOrderId': '', 'isAvailable': true});
          }
        } else if (newStatus == AppConstants.statusPickedUp) {
          updateData['timestamps.pickedUp'] = FieldValue.serverTimestamp();
        } else if (newStatus == AppConstants.statusRiderAssigned) {
          updateData['timestamps.riderAssigned'] = FieldValue.serverTimestamp();
        }

        batch.update(orderRef, updateData);
        await batch.commit();
      }
    } catch (e, stack) {
      debugPrint("Error updating order: $e");
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Order Status Update Failed: $orderId -> $newStatus');
      rethrow;
    }
  }
}